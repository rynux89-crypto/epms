package epms.ups;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;

public final class UpsCollectorListener implements ServletContextListener {
    private ScheduledExecutorService scheduler;
    private final UpsCollectorService service = new UpsCollectorService();
    private ServletContextEvent contextEvent;

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        contextEvent = sce;
        scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "ups-modbus-collector");
            t.setDaemon(true);
            return t;
        });
        sce.getServletContext().setAttribute("ups.collector.status", "STARTED");
        sce.getServletContext().setAttribute("ups.collector.intervalSeconds", Long.valueOf(1L));
        scheduler.scheduleAtFixedRate(this::safePoll, 1L, 1L, TimeUnit.SECONDS);
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        if (scheduler != null) {
            scheduler.shutdownNow();
        }
    }

    private void safePoll() {
        long started = System.currentTimeMillis();
        if (contextEvent != null) {
            contextEvent.getServletContext().setAttribute("ups.collector.lastStartAt", new java.sql.Timestamp(started));
        }
        try {
            service.pollEnabledDevices();
            if (contextEvent != null) {
                contextEvent.getServletContext().setAttribute("ups.collector.status", "OK");
                contextEvent.getServletContext().setAttribute("ups.collector.lastSuccessAt", new java.sql.Timestamp(System.currentTimeMillis()));
                contextEvent.getServletContext().setAttribute("ups.collector.lastDurationMs", Long.valueOf(System.currentTimeMillis() - started));
                contextEvent.getServletContext().removeAttribute("ups.collector.lastError");
            }
        } catch (Exception ignore) {
            if (contextEvent != null) {
                contextEvent.getServletContext().setAttribute("ups.collector.status", "ERROR");
                contextEvent.getServletContext().setAttribute("ups.collector.lastErrorAt", new java.sql.Timestamp(System.currentTimeMillis()));
                contextEvent.getServletContext().setAttribute("ups.collector.lastDurationMs", Long.valueOf(System.currentTimeMillis() - started));
                contextEvent.getServletContext().setAttribute("ups.collector.lastError", ignore.getMessage());
            }
        }
    }
}
