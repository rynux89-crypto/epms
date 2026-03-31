package epms.alarm;

import java.sql.Connection;
import java.util.List;
import java.util.Map;

/**
 * Thin orchestration facade for alarm-domain helper classes.
 *
 * <p>This class is intentionally stateless and servlet-free so JSP code can
 * migrate from many helper calls toward a single alarm facade entry point.
 * The current implementation focuses on pure logic only. DB/repository and
 * servlet request orchestration should be introduced in later stages.</p>
 */
public final class AlarmFacade {
    private static final int BATCH_FLUSH_THRESHOLD = 500;
    private static final AlarmRuleCache AI_RULE_CACHE = new AlarmRuleCache(30_000L);
    private static final AlarmStateCache AI_OPEN_STATE_CACHE = new AlarmStateCache();
    private static final AlarmStateCache DI_EVENT_STATE_CACHE = new AlarmStateCache();
    private static final AlarmStateCache DI_ALARM_STATE_CACHE = new AlarmStateCache();
    private static final long AI_OPEN_STATE_TTL_MS = 5_000L;
    private static final long DI_OPEN_STATE_TTL_MS = 5_000L;
    private static final AlarmIngestService INGEST_SERVICE =
            new AlarmIngestService(AI_RULE_CACHE, AI_OPEN_STATE_CACHE, new AlarmBatchWriter());

    private AlarmFacade() {
    }

    public static AlarmRuleDef ruleDef(
            int ruleId,
            String ruleCode,
            String targetScope,
            String metricKey,
            String sourceToken,
            String messageTemplate,
            String operator,
            Double threshold1,
            Double threshold2,
            int durationSec,
            Double hysteresis,
            String severity) {
        return new AlarmRuleDef(
                ruleId,
                ruleCode,
                targetScope,
                metricKey,
                sourceToken,
                messageTemplate,
                operator,
                threshold1,
                threshold2,
                durationSec,
                hysteresis,
                severity
        );
    }

    public static boolean evalOpen(String operator, Double threshold1, Double threshold2, double value) {
        return AlarmOpenEvaluator.evalOpen(operator, threshold1, threshold2, value);
    }

    public static String evalStage(AlarmRuleDef rule, double value) {
        return AlarmOpenEvaluator.evalStage(rule, value);
    }

    public static String renderAiMessage(
            AlarmRuleDef rule,
            int meterId,
            String stage,
            String source,
            double value,
            String fallback) {
        return AlarmMessageRenderer.render(
                rule == null ? null : rule.getMessageTemplate(),
                AlarmMessageRenderer.aiVars(rule, meterId, stage, source, value),
                fallback
        );
    }

    public static Double computeUnbalancePercent(Double a, Double b, Double c) {
        return AlarmDerivedMetrics.computeUnbalancePercent(a, b, c);
    }

    public static Double computeVariationPercent(Double previous, Double current) {
        return AlarmDerivedMetrics.computeVariationPercent(previous, current);
    }

    public static String buildAiEventType(String ruleCode, String metricKey, String sourceKey, String stage) {
        return AlarmEventTypeUtil.buildAiEventType(ruleCode, metricKey, sourceKey, stage);
    }

    public static String normalizeEventToken(String rawTag) {
        return AlarmEventTypeUtil.normalizeTagKey(rawTag);
    }

    public static java.util.List<String> splitSourceTokens(String raw) {
        return AlarmEventTypeUtil.splitSourceTokens(raw);
    }

    public static String renderTemplate(String template, Map<String, String> vars, String fallback) {
        return AlarmMessageRenderer.render(template, vars, fallback);
    }

    public static java.util.List<AlarmRuleDef> loadEnabledAiRuleDefs(Connection conn) throws Exception {
        return AI_RULE_CACHE.getAiRules(conn);
    }

    public static boolean isAiAlarmOpen(int meterId, String alarmType, long nowMs) {
        return AI_OPEN_STATE_CACHE.isOpenFresh(new AlarmStateKey(meterId, alarmType), nowMs, AI_OPEN_STATE_TTL_MS);
    }

    public static void rememberAiAlarmOpen(int meterId, String alarmType, String severity, Double measuredValue, long openedAtMs) {
        AI_OPEN_STATE_CACHE.putOpen(
                new AlarmStateKey(meterId, alarmType),
                new AlarmOpenState(openedAtMs, severity, measuredValue)
        );
    }

    public static void clearAiAlarmOpen(int meterId, String alarmType) {
        AI_OPEN_STATE_CACHE.clear(new AlarmStateKey(meterId, alarmType));
    }

    public static void queueOpenAiAlarm(int meterId, String alarmType, String severity, String description) {
        INGEST_SERVICE.queue(new AlarmWriteOp(
                AlarmWriteOp.Kind.OPEN_AI_ALARM,
                new AlarmStateKey(meterId, alarmType),
                severity,
                description
        ));
    }

    public static void queueClearAiAlarm(int meterId, String alarmType, String description) {
        INGEST_SERVICE.queue(new AlarmWriteOp(
                AlarmWriteOp.Kind.CLEAR_AI_ALARM,
                new AlarmStateKey(meterId, alarmType),
                null,
                description
        ));
    }

    public static void queueOpenDiEvent(int deviceId, String eventType, String severity, String description) {
        DI_EVENT_STATE_CACHE.putOpen(
                new AlarmStateKey(deviceId, eventType),
                new AlarmOpenState(System.currentTimeMillis(), severity, null)
        );
        INGEST_SERVICE.queue(new AlarmWriteOp(
                AlarmWriteOp.Kind.OPEN_DI_EVENT,
                new AlarmStateKey(deviceId, eventType),
                severity,
                description
        ));
    }

    public static void queueCloseDiEvent(int deviceId, String eventType, String description) {
        DI_EVENT_STATE_CACHE.clear(new AlarmStateKey(deviceId, eventType));
        INGEST_SERVICE.queue(new AlarmWriteOp(
                AlarmWriteOp.Kind.CLOSE_DI_EVENT,
                new AlarmStateKey(deviceId, eventType),
                null,
                description
        ));
    }

    public static void queueOpenDiAlarm(int meterId, String alarmType, String severity, String description) {
        DI_ALARM_STATE_CACHE.putOpen(
                new AlarmStateKey(meterId, alarmType),
                new AlarmOpenState(System.currentTimeMillis(), severity, null)
        );
        INGEST_SERVICE.queue(new AlarmWriteOp(
                AlarmWriteOp.Kind.OPEN_DI_ALARM,
                new AlarmStateKey(meterId, alarmType),
                severity,
                description
        ));
    }

    public static void queueClearDiAlarm(int meterId, String alarmType, String description) {
        DI_ALARM_STATE_CACHE.clear(new AlarmStateKey(meterId, alarmType));
        INGEST_SERVICE.queue(new AlarmWriteOp(
                AlarmWriteOp.Kind.CLEAR_DI_ALARM,
                new AlarmStateKey(meterId, alarmType),
                null,
                description
        ));
    }

    public static int getQueuedWriteCount() {
        return INGEST_SERVICE.getBatchWriter() == null ? 0 : INGEST_SERVICE.getBatchWriter().size();
    }

    public static int getAiRuleCacheSize() {
        return AI_RULE_CACHE.size();
    }

    public static int getBatchFlushThreshold() {
        return BATCH_FLUSH_THRESHOLD;
    }

    public static boolean isQueueAboveFlushThreshold() {
        return getQueuedWriteCount() >= BATCH_FLUSH_THRESHOLD;
    }

    public static int getQueueUtilizationPercent() {
        int threshold = getBatchFlushThreshold();
        if (threshold <= 0) {
            return 0;
        }
        return (int)Math.round((getQueuedWriteCount() * 100.0d) / threshold);
    }

    public static int getQueueRemainingUntilFlush() {
        return Math.max(0, getBatchFlushThreshold() - getQueuedWriteCount());
    }

    public static String getQueuePressureLevel() {
        int queued = getQueuedWriteCount();
        int threshold = getBatchFlushThreshold();
        if (queued >= threshold) {
            return "HIGH";
        }
        if (queued >= Math.max(1, threshold / 2)) {
            return "WARN";
        }
        return "NORMAL";
    }

    public static String getOverallDiagStatus() {
        String pressure = getQueuePressureLevel();
        if ("HIGH".equalsIgnoreCase(pressure)) {
            return "DEGRADED";
        }
        if ("WARN".equalsIgnoreCase(pressure)) {
            return "WATCH";
        }
        return "OK";
    }

    public static int getQueuedWriteHighWaterMark() {
        AlarmBatchWriter writer = INGEST_SERVICE.getBatchWriter();
        return writer == null ? 0 : writer.getHighWaterMark();
    }

    public static int getAiOpenStateSize() {
        return AI_OPEN_STATE_CACHE.size();
    }

    public static int getDiEventStateSize() {
        return DI_EVENT_STATE_CACHE.size();
    }

    public static int getDiAlarmStateSize() {
        return DI_ALARM_STATE_CACHE.size();
    }

    public static AlarmProcessingResult processingResult(int opened, int closed, int inspected) {
        return new AlarmProcessingResult(opened, closed, inspected);
    }

    public static String getQueuedWriteSummaryJson() {
        AlarmBatchWriter writer = INGEST_SERVICE.getBatchWriter();
        if (writer == null) {
            return "\"queuedWriteOps\":0";
        }
        return summarizeQueuedWriteOps(writer.snapshot());
    }

    public static String drainQueuedWriteSummaryJson() {
        AlarmBatchWriter writer = INGEST_SERVICE.getBatchWriter();
        if (writer == null) {
            return "\"queuedWriteOps\":0";
        }
        return summarizeQueuedWriteOps(writer.drain());
    }

    private static String summarizeQueuedWriteOps(List<AlarmWriteOp> ops) {
        if (ops == null) {
            return "\"queuedWriteOps\":0";
        }
        int openAi = 0;
        int clearAi = 0;
        int openDiEvent = 0;
        int closeDiEvent = 0;
        int openDiAlarm = 0;
        int clearDiAlarm = 0;
        for (AlarmWriteOp op : ops) {
            if (op == null || op.getKind() == null) continue;
            switch (op.getKind()) {
                case OPEN_AI_ALARM:
                    openAi++;
                    break;
                case CLEAR_AI_ALARM:
                    clearAi++;
                    break;
                case OPEN_DI_EVENT:
                    openDiEvent++;
                    break;
                case CLOSE_DI_EVENT:
                    closeDiEvent++;
                    break;
                case OPEN_DI_ALARM:
                    openDiAlarm++;
                    break;
                case CLEAR_DI_ALARM:
                    clearDiAlarm++;
                    break;
                default:
                    break;
            }
        }
        return "\"queuedWriteOps\":" + ops.size() +
                ",\"queuedWriteHighWaterMark\":" + getQueuedWriteHighWaterMark() +
                ",\"queueFlushThreshold\":" + BATCH_FLUSH_THRESHOLD +
                ",\"queueAboveFlushThreshold\":" + isQueueAboveFlushThreshold() +
                ",\"queuePressureLevel\":\"" + getQueuePressureLevel() + "\"" +
                ",\"queuedOpenAiAlarms\":" + openAi +
                ",\"queuedClearAiAlarms\":" + clearAi +
                ",\"queuedOpenDiEvents\":" + openDiEvent +
                ",\"queuedCloseDiEvents\":" + closeDiEvent +
                ",\"queuedOpenDiAlarms\":" + openDiAlarm +
                ",\"queuedClearDiAlarms\":" + clearDiAlarm;
    }

    public static boolean isDiEventOpen(int deviceId, String eventType, long nowMs) {
        return DI_EVENT_STATE_CACHE.isOpenFresh(new AlarmStateKey(deviceId, eventType), nowMs, DI_OPEN_STATE_TTL_MS);
    }

    public static boolean isDiAlarmOpen(int meterId, String alarmType, long nowMs) {
        return DI_ALARM_STATE_CACHE.isOpenFresh(new AlarmStateKey(meterId, alarmType), nowMs, DI_OPEN_STATE_TTL_MS);
    }

    public static void rememberDiEventOpen(int deviceId, String eventType, String severity, long openedAtMs) {
        DI_EVENT_STATE_CACHE.putOpen(
                new AlarmStateKey(deviceId, eventType),
                new AlarmOpenState(openedAtMs, severity, null)
        );
    }

    public static void rememberDiAlarmOpen(int meterId, String alarmType, String severity, long openedAtMs) {
        DI_ALARM_STATE_CACHE.putOpen(
                new AlarmStateKey(meterId, alarmType),
                new AlarmOpenState(openedAtMs, severity, null)
        );
    }

    public static void clearDiEventOpen(int deviceId, String eventType) {
        DI_EVENT_STATE_CACHE.clear(new AlarmStateKey(deviceId, eventType));
    }

    public static void clearDiAlarmOpen(int meterId, String alarmType) {
        DI_ALARM_STATE_CACHE.clear(new AlarmStateKey(meterId, alarmType));
    }
}
