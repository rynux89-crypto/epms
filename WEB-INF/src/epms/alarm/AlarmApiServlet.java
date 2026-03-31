package epms.alarm;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import javax.servlet.RequestDispatcher;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

/**
 * Thin servlet entrypoint for the alarm API.
 *
 * <p>For now this servlet keeps backward compatibility by forwarding
 * non-trivial actions to the existing JSP implementation while exposing a
 * stable controller endpoint for future migration.</p>
 */
public final class AlarmApiServlet extends HttpServlet {
    private static final String JSP_PATH = "/WEB-INF/jspf/alarm_api_runtime.jsp";
    private static final String JSON_TYPE = "application/json;charset=UTF-8";
    private static final long QUEUE_WARN_INTERVAL_MS = 30_000L;
    private static final DateTimeFormatter ISO_FMT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX").withZone(ZoneId.systemDefault());
    private static volatile long lastQueueWarnAtMs = 0L;

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        serviceAlarm(req, resp);
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        serviceAlarm(req, resp);
    }

    private void serviceAlarm(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        resp.setCharacterEncoding(StandardCharsets.UTF_8.name());
        resp.setContentType(JSON_TYPE);

        String action = req.getParameter("action");
        if (action == null || action.trim().isEmpty()) {
            writeJsonError(resp, "action is required");
            return;
        }
        String normalizedAction = action.trim();

        if ("health".equalsIgnoreCase(normalizedAction) || "diag".equalsIgnoreCase(normalizedAction)) {
            String pressureLevel = AlarmFacade.getQueuePressureLevel();
            boolean detailedDiag = "diag".equalsIgnoreCase(normalizedAction);
            resp.getWriter().write(
                    "{\"ok\":true,\"info\":\"alarm servlet alive\",\"diagStatus\":\"" + escapeJson(AlarmFacade.getOverallDiagStatus()) + "\"" +
                            ",\"aiRuleCacheSize\":" + AlarmFacade.getAiRuleCacheSize() +
                            ",\"aiOpenStateSize\":" + AlarmFacade.getAiOpenStateSize() +
                            ",\"diEventStateSize\":" + AlarmFacade.getDiEventStateSize() +
                            ",\"diAlarmStateSize\":" + AlarmFacade.getDiAlarmStateSize() +
                            ",\"queueWarnIntervalMs\":" + QUEUE_WARN_INTERVAL_MS +
                            ",\"lastQueueWarnAtMs\":" + lastQueueWarnAtMs +
                            ",\"lastQueueWarnAt\":\"" + escapeJson(formatEpochMillis(lastQueueWarnAtMs)) + "\"" +
                            ",\"queuePressureHigh\":" + ("HIGH".equals(pressureLevel) ? "true" : "false") +
                            ",\"queueAdviceCode\":\"" + escapeJson(buildQueueAdviceCode(pressureLevel)) + "\"" +
                            ",\"queueAdvice\":\"" + escapeJson(buildQueueAdvice(pressureLevel)) + "\"" +
                            ",\"queueUtilizationPct\":" + AlarmFacade.getQueueUtilizationPercent() +
                            ",\"queueRemainingUntilFlush\":" + AlarmFacade.getQueueRemainingUntilFlush() +
                            (detailedDiag ? ",\"diagMode\":\"DETAILED\"" : "") +
                            (detailedDiag ? ",\"queueHeadroomPct\":" + Math.max(0, 100 - AlarmFacade.getQueueUtilizationPercent()) : "") +
                            (detailedDiag ? ",\"queuePressureReason\":\"" + escapeJson(buildQueuePressureReason(pressureLevel)) + "\"" : "") +
                            "," + AlarmFacade.getQueuedWriteSummaryJson() + "}"
            );
            return;
        }

        if ("process_ai".equalsIgnoreCase(normalizedAction) || "process_di".equalsIgnoreCase(normalizedAction)) {
            maybeWarnQueuePressure();
            if (!"POST".equalsIgnoreCase(req.getMethod())) {
                writeJsonError(resp, "POST method is required");
                return;
            }

            int plcId = parseIntSafe(req.getParameter("plc_id"), 0);
            if (plcId <= 0) {
                writeJsonError(resp, "plc_id is required");
                return;
            }

            req.setAttribute("alarmApi.action", normalizedAction);
            req.setAttribute("alarmApi.validated", Boolean.TRUE);
            RequestDispatcher dispatcher = req.getRequestDispatcher(JSP_PATH);
            dispatcher.forward(req, resp);
            return;
        }

        writeJsonError(resp, "unknown action");
    }

    private void maybeWarnQueuePressure() {
        if (!AlarmFacade.isQueueAboveFlushThreshold()) {
            return;
        }
        long now = System.currentTimeMillis();
        long prev = lastQueueWarnAtMs;
        if ((now - prev) < QUEUE_WARN_INTERVAL_MS) {
            return;
        }
        lastQueueWarnAtMs = now;
        log("alarm queue pressure [" + AlarmFacade.getQueuePressureLevel() + "]: queuedWriteOps=" + AlarmFacade.getQueuedWriteCount()
                + ", highWaterMark=" + AlarmFacade.getQueuedWriteHighWaterMark()
                + ", threshold=" + AlarmFacade.getBatchFlushThreshold());
    }

    private static int parseIntSafe(String raw, int fallback) {
        if (raw == null) {
            return fallback;
        }
        try {
            return Integer.parseInt(raw.trim());
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private static void writeJsonError(HttpServletResponse resp, String message) throws IOException {
        resp.getWriter().write("{\"ok\":false,\"error\":\"" + escapeJson(message) + "\"}");
    }

    private static String escapeJson(String s) {
        if (s == null) {
            return "";
        }
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private static String formatEpochMillis(long epochMs) {
        if (epochMs <= 0L) {
            return "";
        }
        return ISO_FMT.format(Instant.ofEpochMilli(epochMs));
    }

    private static String buildQueueAdvice(String pressureLevel) {
        if ("HIGH".equalsIgnoreCase(pressureLevel)) {
            return "Queue pressure is high. Consider enabling batch flush or reducing per-request write amplification.";
        }
        if ("WARN".equalsIgnoreCase(pressureLevel)) {
            return "Queue pressure is rising. Watch queuedWriteOps and high-water mark closely.";
        }
        return "Queue pressure is normal.";
    }

    private static String buildQueueAdviceCode(String pressureLevel) {
        if ("HIGH".equalsIgnoreCase(pressureLevel)) {
            return "ENABLE_BATCH_OR_SCALE_OUT";
        }
        if ("WARN".equalsIgnoreCase(pressureLevel)) {
            return "WATCH_QUEUE_GROWTH";
        }
        return "NO_ACTION";
    }

    private static String buildQueuePressureReason(String pressureLevel) {
        if ("HIGH".equalsIgnoreCase(pressureLevel)) {
            return "Queued writes have reached or exceeded the configured flush threshold.";
        }
        if ("WARN".equalsIgnoreCase(pressureLevel)) {
            return "Queued writes have exceeded 50% of the configured flush threshold.";
        }
        return "Queued writes are within the normal operating range.";
    }
}
