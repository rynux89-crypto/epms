package epms.alarm;

import epms.alarm.AlarmApiModels.AiPreparedMetrics;
import epms.alarm.AlarmApiModels.AiRow;
import epms.alarm.AlarmApiModels.CacheEntry;
import epms.alarm.AlarmApiModels.DiRuleMeta;
import epms.alarm.AlarmApiModels.DiRuntimeContext;
import epms.alarm.AlarmApiModels.OpenCloseCount;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Timestamp;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class AlarmApiProcessingSupport {
    private AlarmApiProcessingSupport() {
    }

    public static AlarmProcessingResult processAiEvents(
            int plcId,
            List<AiRow> aiRows,
            Timestamp measuredAt,
            ConcurrentHashMap<String, Long> aiPendingOnMs) throws Exception {
        if (aiRows == null || aiRows.isEmpty()) return AlarmFacade.processingResult(0, 0, 0);

        long measuredAtMs = measuredAt.getTime();
        String selAlarmOpenSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String selAlarmOpenAnyRuleSql =
            "SELECT alarm_id, alarm_type FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type LIKE ? ESCAPE '\\' AND cleared_at IS NULL";
        String insAlarmSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token, measured_value, operator, threshold1, threshold2) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        String clearAlarmSql =
            "UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?";

        try (Connection conn = AlarmPersistenceSupport.createConnection();
             PreparedStatement selAlarmOpen = conn.prepareStatement(selAlarmOpenSql);
             PreparedStatement selAlarmOpenAnyRule = conn.prepareStatement(selAlarmOpenAnyRuleSql);
             PreparedStatement insAlarm = conn.prepareStatement(insAlarmSql);
             PreparedStatement clearAlarm = conn.prepareStatement(clearAlarmSql)) {

            AlarmPersistenceSupport.ensureAlarmSchema(conn);
            Map<String, String> tokenAlias = AlarmAiMetricsSupport.loadAiTokenColumnAlias(conn);
            Map<String, List<String>> metricCatalogTokens = AlarmAiMetricsSupport.loadMetricCatalogSourceTokens(conn);
            List<AlarmRuleDef> rules = AlarmFacade.loadEnabledAiRuleDefs(conn);
            if (rules.isEmpty()) return AlarmFacade.processingResult(0, 0, aiRows.size());

            AiPreparedMetrics prepared = AlarmAiMetricsSupport.prepareAiMetrics(conn, aiRows, measuredAt, tokenAlias);
            for (Map.Entry<Integer, Map<String, Double>> me : prepared.valueByMeterMetric.entrySet()) {
                int meterId = me.getKey().intValue();
                Map<String, Double> metricValues = me.getValue();
                Map<String, Double> previousValues = prepared.previousByMeter.get(String.valueOf(meterId));
                AlarmAiMetricsSupport.enrichAiDerivedMetrics(metricValues, previousValues);
            }
            return AlarmAiProcessingSupport.processPreparedAiEvents(
                selAlarmOpen,
                selAlarmOpenAnyRule,
                insAlarm,
                clearAlarm,
                plcId,
                aiRows.size(),
                measuredAtMs,
                measuredAt,
                prepared,
                rules,
                metricCatalogTokens,
                aiPendingOnMs);
        }
    }

    public static AlarmProcessingResult processDiEvents(
            int plcId,
            List<Map<String, Object>> diRows,
            Timestamp measuredAt,
            ConcurrentHashMap<String, Integer> lastDiValueMap,
            ConcurrentHashMap<String, CacheEntry<Map<String, DiRuleMeta>>> diRuleCache,
            long diRuleCacheTtlMs) throws Exception {
        int opened = 0;
        int closed = 0;
        if (diRows == null || diRows.isEmpty()) return AlarmFacade.processingResult(0, 0, 0);

        String selOpenSql =
            "SELECT TOP 1 event_id FROM dbo.device_events " +
            "WHERE device_id = ? AND event_type = ? AND restored_time IS NULL " +
            "ORDER BY event_id DESC";
        String insSql =
            "INSERT INTO dbo.device_events (device_id, event_type, event_time, severity, description) " +
            "VALUES (?, ?, ?, ?, ?)";
        String closeSql =
            "UPDATE dbo.device_events " +
            "SET restored_time = ?, duration_seconds = DATEDIFF(SECOND, event_time, ?), " +
            "    downtime_minutes = DATEDIFF(SECOND, event_time, ?) / 60.0 " +
            "WHERE event_id = ?";
        String selAlarmOpenSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String selAlarmOpenAllSql =
            "SELECT alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String insAlarmSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
        String clearAlarmSql =
            "UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?";

        try (Connection conn = AlarmPersistenceSupport.createConnection();
             PreparedStatement selOpen = conn.prepareStatement(selOpenSql);
             PreparedStatement ins = conn.prepareStatement(insSql);
             PreparedStatement close = conn.prepareStatement(closeSql);
             PreparedStatement selAlarmOpen = conn.prepareStatement(selAlarmOpenSql);
             PreparedStatement selAlarmOpenAll = conn.prepareStatement(selAlarmOpenAllSql);
             PreparedStatement insAlarm = conn.prepareStatement(insAlarmSql);
             PreparedStatement clearAlarm = conn.prepareStatement(clearAlarmSql)) {

            AlarmPersistenceSupport.ensureAlarmSchema(conn);
            DiRuntimeContext diContext = AlarmDiProcessingSupport.loadDiRuntimeContext(conn, diRuleCache, diRuleCacheTtlMs);

            for (Map<String, Object> row : diRows) {
                OpenCloseCount c = AlarmDiProcessingSupport.processSingleDiRow(
                    selOpen,
                    ins,
                    close,
                    selAlarmOpen,
                    selAlarmOpenAll,
                    insAlarm,
                    clearAlarm,
                    diContext.meterIdByName,
                    diContext.diRuleMetaMap,
                    plcId,
                    measuredAt,
                    row,
                    lastDiValueMap);
                opened += c.opened;
                closed += c.closed;
            }
        }
        return AlarmFacade.processingResult(opened, closed, diRows.size());
    }
}
