package epms.plc;

import java.lang.reflect.Field;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import javax.servlet.ServletContext;

public final class ModbusPollingSupport {
    private static final String POLL_RUNTIME_ATTR = "EPMS_MODBUS_POLL_RUNTIME";
    private static final int DI_POLLING_MS = 500;

    public static final class PollState {
        public final AtomicLong attemptCount = new AtomicLong(0);
        public final AtomicLong successCount = new AtomicLong(0);
        public final AtomicLong readCount = new AtomicLong(0);
        public final AtomicLong diReadCount = new AtomicLong(0);
        public final AtomicLong aiReadCount = new AtomicLong(0);
        public final AtomicLong readDurationSumMs = new AtomicLong(0);
        public final AtomicBoolean aiInProgress = new AtomicBoolean(false);
        public final AtomicBoolean diInProgress = new AtomicBoolean(false);
        public final AtomicBoolean modbusIoInProgress = new AtomicBoolean(false);
        public volatile long lastReadDurationMs = 0L;
        public volatile long lastDiReadMs = 0L;
        public volatile long lastAiReadMs = 0L;
        public volatile long lastProcMs = 0L;
        public volatile List<PlcAiReadRow> lastRows = Collections.emptyList();
        public volatile List<PlcDiReadRow> lastDiRows = Collections.emptyList();
        public volatile boolean running = false;
        public volatile boolean autoStartAllowed = true;
        public volatile int pollingMs = 1000;
        public volatile String lastInfo = "";
        public volatile String lastError = "";
        public volatile long lastRunAt = 0L;
        public volatile long lastSuccessAt = 0L;
        public volatile long nextAiPollAt = 0L;
    }

    public static final class PollRuntime {
        public final ScheduledExecutorService exec;
        public final ConcurrentHashMap<Integer, ScheduledFuture<?>> aiTasks = new ConcurrentHashMap<>();
        public final ConcurrentHashMap<Integer, ScheduledFuture<?>> diTasks = new ConcurrentHashMap<>();
        public final ConcurrentHashMap<Integer, PollState> states = new ConcurrentHashMap<>();

        PollRuntime() {
            ThreadFactory tf = new ThreadFactory() {
                private final AtomicInteger seq = new AtomicInteger(1);

                @Override
                public Thread newThread(Runnable r) {
                    Thread t = new Thread(r, "epms-modbus-poll-" + seq.getAndIncrement());
                    t.setDaemon(true);
                    return t;
                }
            };
            this.exec = Executors.newScheduledThreadPool(4, tf);
        }
    }

    private ModbusPollingSupport() {
    }

    public static PollRuntime getPollRuntime(ServletContext app) {
        synchronized (app) {
            Object cur = app.getAttribute(POLL_RUNTIME_ATTR);
            if (cur instanceof PollRuntime) {
                return (PollRuntime) cur;
            }
            if (cur != null) {
                shutdownLegacyPollRuntime(cur);
            }
            PollRuntime created = new PollRuntime();
            app.setAttribute(POLL_RUNTIME_ATTR, created);
            return created;
        }
    }

    public static PollState getPollState(PollRuntime rt, int plcId) {
        return rt.states.computeIfAbsent(Integer.valueOf(plcId), k -> new PollState());
    }

    public static void stopServerPolling(PollRuntime rt, int plcId) {
        if (rt == null) {
            return;
        }
        ScheduledFuture<?> aiOld = rt.aiTasks.remove(Integer.valueOf(plcId));
        if (aiOld != null) {
            aiOld.cancel(false);
        }
        ScheduledFuture<?> diOld = rt.diTasks.remove(Integer.valueOf(plcId));
        if (diOld != null) {
            diOld.cancel(false);
        }
        PollState st = getPollState(rt, plcId);
        st.running = false;
        st.autoStartAllowed = false;
        st.aiInProgress.set(false);
        st.diInProgress.set(false);
        st.modbusIoInProgress.set(false);
        st.lastError = "";
        st.lastInfo = "Polling stopped.";
        st.lastRunAt = System.currentTimeMillis();
    }

    public static void startServerPolling(PollRuntime rt, int plcId, int pollingMs, String alarmApiUrl) {
        stopServerPolling(rt, plcId);
        final PollState st = getPollState(rt, plcId);
        ModbusPollingExecutionSupport.resetPollState(st, pollingMs);

        Runnable pollTask = new Runnable() {
            @Override
            public void run() {
                ModbusPollingExecutionSupport.runPollCycle(st, plcId, pollingMs, alarmApiUrl);
            }
        };

        ScheduledFuture<?> pollFuture = rt.exec.scheduleAtFixedRate(pollTask, 0, DI_POLLING_MS, TimeUnit.MILLISECONDS);
        rt.diTasks.put(Integer.valueOf(plcId), pollFuture);
        rt.aiTasks.put(Integer.valueOf(plcId), pollFuture);
    }

    public static void ensurePollingStarted(PollRuntime rt, Integer plcId, String alarmApiUrl) {
        try {
            if (rt == null) {
                return;
            }
            Map<Integer, PlcConfig> cfgMap = ModbusConfigRepository.loadAllPlcConfigs();
            if (cfgMap == null || cfgMap.isEmpty()) {
                return;
            }

            for (Map.Entry<Integer, PlcConfig> entry : cfgMap.entrySet()) {
                Integer id = entry.getKey();
                PlcConfig cfg = entry.getValue();
                if (id == null || cfg == null) continue;
                if (plcId != null && !plcId.equals(id)) continue;
                if (!cfg.enabled || !cfg.exists || cfg.ip == null || cfg.ip.trim().isEmpty()) continue;

                PollState st = getPollState(rt, id.intValue());
                if (st != null && !st.autoStartAllowed) continue;
                ScheduledFuture<?> diTask = rt.diTasks.get(id);
                ScheduledFuture<?> aiTask = rt.aiTasks.get(id);
                boolean running = st != null && st.running;
                boolean diAlive = diTask != null && !diTask.isCancelled() && !diTask.isDone();
                boolean aiAlive = aiTask != null && !aiTask.isCancelled() && !aiTask.isDone();
                if (running && diAlive && aiAlive) continue;

                int pollingMs = cfg.pollingMs > 0 ? cfg.pollingMs : 1000;
                startServerPolling(rt, id.intValue(), pollingMs, alarmApiUrl);
            }
        } catch (Exception ignore) {
        }
    }

    private static void shutdownLegacyPollRuntime(Object legacy) {
        if (legacy == null) {
            return;
        }
        try {
            Field aiF = legacy.getClass().getDeclaredField("aiTasks");
            Field diF = legacy.getClass().getDeclaredField("diTasks");
            Field execF = legacy.getClass().getDeclaredField("exec");
            aiF.setAccessible(true);
            diF.setAccessible(true);
            execF.setAccessible(true);

            Object aiObj = aiF.get(legacy);
            Object diObj = diF.get(legacy);
            Object execObj = execF.get(legacy);

            cancelFutureMap(aiObj);
            cancelFutureMap(diObj);
            if (execObj instanceof ScheduledExecutorService) {
                ((ScheduledExecutorService) execObj).shutdownNow();
            }
        } catch (Exception ignore) {
            // Legacy runtime shape may differ; best-effort shutdown only.
        }
    }

    private static void cancelFutureMap(Object mapObj) {
        if (!(mapObj instanceof Map)) {
            return;
        }
        for (Object v : ((Map<?, ?>) mapObj).values()) {
            if (v instanceof Future) {
                try {
                    ((Future<?>) v).cancel(false);
                } catch (Exception ignore) {
                }
            }
        }
    }
}
