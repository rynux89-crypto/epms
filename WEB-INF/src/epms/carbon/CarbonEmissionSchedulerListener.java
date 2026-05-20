package epms.carbon;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import javax.servlet.ServletContextEvent;
import javax.servlet.ServletContextListener;

public final class CarbonEmissionSchedulerListener implements ServletContextListener {
    private ScheduledExecutorService scheduler;
    private final CarbonEmissionService service = new CarbonEmissionService();

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "carbon-emission-scheduler");
            t.setDaemon(true);
            return t;
        });

        scheduler.execute(this::safeRefreshAll);

        long initialDelaySeconds = secondsUntilNextRun();
        scheduler.scheduleAtFixedRate(this::safeRefreshAll, initialDelaySeconds, 24L * 60L * 60L, TimeUnit.SECONDS);
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        if (scheduler != null) {
            scheduler.shutdownNow();
        }
    }

    private void safeRefreshAll() {
        try {
            if (service.hasConfiguredFactors()) {
                service.refreshAllScopes();
            }
        } catch (Exception ignore) {
        }
    }

    private static long secondsUntilNextRun() {
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime next = now.toLocalDate().plusDays(1).atTime(0, 10);
        return Math.max(60L, Duration.between(now, next).getSeconds());
    }
}
