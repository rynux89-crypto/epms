package epms.plc;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public final class ModbusPollingExecutionSupport {
    private ModbusPollingExecutionSupport() {
    }

    public static void resetPollState(ModbusPollingSupport.PollState st, int pollingMs) {
        st.attemptCount.set(0L);
        st.successCount.set(0L);
        st.readCount.set(0L);
        st.diReadCount.set(0L);
        st.aiReadCount.set(0L);
        st.readDurationSumMs.set(0L);
        st.aiInProgress.set(false);
        st.diInProgress.set(false);
        st.modbusIoInProgress.set(false);
        st.lastReadDurationMs = 0L;
        st.lastDiReadMs = 0L;
        st.lastAiReadMs = 0L;
        st.lastProcMs = 0L;
        st.lastRows = Collections.emptyList();
        st.lastDiRows = Collections.emptyList();
        st.lastRunAt = 0L;
        st.lastSuccessAt = 0L;
        st.nextAiPollAt = 0L;
        st.running = true;
        st.autoStartAllowed = true;
        st.pollingMs = pollingMs;
        st.lastInfo = "";
        st.lastError = "";
    }

    public static void runPollCycle(ModbusPollingSupport.PollState st, int plcId, int pollingMs, String alarmApiUrl) {
        if (!st.autoStartAllowed || !st.running) return;
        if (!tryAcquireModbusIo(st, 50L)) return;
        try {
            long now = System.currentTimeMillis();
            ModbusCycleSupport.LoadedResources resources = ModbusCycleSupport.loadResources(plcId);
            PlcConfig cfg = resources.cfg;
            if (applyInvalidPlcState(st, cfg)) return;
            try (epms.util.ModbusSupport.ModbusTcpClient client = new epms.util.ModbusSupport.ModbusTcpClient(cfg.ip, cfg.port)) {
                runDiCycle(st, plcId, cfg, resources.diTagList, client);
                now = System.currentTimeMillis();
                if (st.nextAiPollAt <= now) {
                    runAiCycle(st, plcId, cfg, resources.aiMapList, resources.aiMatchMap, client, pollingMs, alarmApiUrl);
                }
            }
        } catch (Exception e) {
            applyPollFailure(st, e);
        } finally {
            st.modbusIoInProgress.set(false);
        }
    }

    private static void runDiCycle(
            ModbusPollingSupport.PollState st,
            int plcId,
            PlcConfig cfg,
            List<PlcDiTagEntry> diTagList,
            epms.util.ModbusSupport.ModbusTcpClient client) throws Exception {
        try {
            st.diInProgress.set(true);
            st.attemptCount.incrementAndGet();
            ModbusCycleSupport.DiCycleResult diResult =
                    ModbusCycleSupport.runDiCycle(plcId, cfg, diTagList, client, new Timestamp(System.currentTimeMillis()));
            if (!st.autoStartAllowed || !st.running) return;
            applyDiPollSuccess(st, plcId, diResult.diData, diResult.diPersist, diResult.elapsedMs);
        } finally {
            st.diInProgress.set(false);
        }
    }

    private static void runAiCycle(
            ModbusPollingSupport.PollState st,
            int plcId,
            PlcConfig cfg,
            List<PlcAiMapEntry> aiMapList,
            Map<String, PlcAiMeasurementMatchEntry> aiMatchMap,
            epms.util.ModbusSupport.ModbusTcpClient client,
            int pollingMs,
            String alarmApiUrl) throws Exception {
        try {
            st.aiInProgress.set(true);
            st.attemptCount.incrementAndGet();
            ModbusCycleSupport.AiCycleResult aiResult =
                    ModbusCycleSupport.runAiCycle(plcId, cfg, aiMapList, aiMatchMap, client, new Timestamp(System.currentTimeMillis()), alarmApiUrl);
            if (!st.autoStartAllowed || !st.running) return;
            applyAiPollSuccess(st, plcId, aiResult.aiData, aiResult.aiPersist, aiResult.aiAlarmPersist, aiResult.elapsedMs);
            st.nextAiPollAt = System.currentTimeMillis() + Math.max(1000, pollingMs);
        } finally {
            st.aiInProgress.set(false);
        }
    }

    private static boolean applyInvalidPlcState(ModbusPollingSupport.PollState st, PlcConfig cfg) {
        if (!cfg.exists || cfg.ip == null) {
            st.lastError = "Selected PLC config not found.";
            st.lastRunAt = System.currentTimeMillis();
            return true;
        }
        if (!cfg.enabled) {
            st.lastError = "Selected PLC is inactive.";
            st.lastRunAt = System.currentTimeMillis();
            return true;
        }
        return false;
    }

    private static void applyPollFailure(ModbusPollingSupport.PollState st, Exception e) {
        if (st == null || !st.autoStartAllowed || !st.running) return;
        e.printStackTrace();
        st.lastError = e.getMessage();
        st.lastRunAt = System.currentTimeMillis();
    }

    private static void applyDiPollSuccess(ModbusPollingSupport.PollState st, int plcId, PlcDiReadData diData, int[] diPersist, long usedElapsed) {
        if (st == null || !st.autoStartAllowed || !st.running) return;
        st.successCount.incrementAndGet();
        st.readCount.incrementAndGet();
        st.diReadCount.incrementAndGet();
        st.lastReadDurationMs = usedElapsed;
        st.lastDiReadMs = diData.durationMs;
        st.lastProcMs = 0L;
        st.readDurationSumMs.addAndGet(usedElapsed);
        st.lastDiRows = new ArrayList<PlcDiReadRow>(diData.rows);
        st.lastInfo = "DI read success. PLC " + plcId + ", di_tags=" + diData.rows.size() +
                ", events_opened=" + diPersist[0] + ", events_closed=" + diPersist[1];
        st.lastError = "";
        st.lastRunAt = System.currentTimeMillis();
        st.lastSuccessAt = st.lastRunAt;
    }

    private static void applyAiPollSuccess(ModbusPollingSupport.PollState st, int plcId, PlcAiReadData aiData, int[] aiPersist, int[] aiAlarmPersist, long usedElapsed) {
        if (st == null || !st.autoStartAllowed || !st.running) return;
        st.successCount.incrementAndGet();
        st.readCount.incrementAndGet();
        st.aiReadCount.incrementAndGet();
        st.lastReadDurationMs = usedElapsed;
        st.lastAiReadMs = aiData.durationMs;
        st.lastProcMs = 0L;
        st.readDurationSumMs.addAndGet(usedElapsed);
        st.lastRows = new ArrayList<PlcAiReadRow>(aiData.rows);
        st.lastInfo = "AI read success. PLC " + plcId + ", meters=" + aiData.meterRead + ", total_floats=" + aiData.totalFloat +
                ", measurements_ins=" + aiPersist[0] + ", harmonic_ins=" + aiPersist[1] +
                ", flicker_ins=" + aiPersist[2] +
                ", ai_alarm_opened=" + aiAlarmPersist[0] + ", ai_alarm_closed=" + aiAlarmPersist[1];
        st.lastError = "";
        st.lastRunAt = System.currentTimeMillis();
        st.lastSuccessAt = st.lastRunAt;
    }

    private static boolean tryAcquireModbusIo(ModbusPollingSupport.PollState st, long waitMs) {
        if (st == null) return false;
        long deadline = System.currentTimeMillis() + Math.max(0L, waitMs);
        while (true) {
            if (st.modbusIoInProgress.compareAndSet(false, true)) return true;
            if (System.currentTimeMillis() >= deadline) return false;
            try {
                Thread.sleep(25L);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return false;
            }
        }
    }
}
