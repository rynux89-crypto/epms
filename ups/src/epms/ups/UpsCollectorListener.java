package epms.ups;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;

public final class UpsCollectorListener implements ServletContextListener {
    private ScheduledExecutorService scheduler;
    private final UpsCollectorService service = new UpsCollectorService();

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "ups-modbus-collector");
            t.setDaemon(true);
            return t;
        });
        scheduler.scheduleAtFixedRate(this::safePoll, 2L, 5L, TimeUnit.SECONDS);
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        if (scheduler != null) {
            scheduler.shutdownNow();
        }
    }

    private void safePoll() {
        try {
            service.pollEnabledDevices();
        } catch (Exception ignore) {
        }
    }
}
