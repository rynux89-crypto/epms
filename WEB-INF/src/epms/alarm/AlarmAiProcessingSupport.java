package epms.alarm;

import epms.alarm.AlarmApiModels.AiPreparedMetrics;
import epms.alarm.AlarmApiModels.OpenCloseCount;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class AlarmAiProcessingSupport {
    private AlarmAiProcessingSupport() {
    }

    public static AlarmProcessingResult processPreparedAiEvents(
            PreparedStatement selAlarmOpen,
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement insAlarm,
            PreparedStatement clearAlarm,
            int plcId,
            int aiRowCount,
            long measuredAtMs,
            Timestamp measuredAt,
            AiPreparedMetrics prepared,
            List<AlarmRuleDef> rules,
            Map<String, List<String>> metricCatalogTokens,
            ConcurrentHashMap<String, Long> aiPendingOnMs) throws Exception {
        int opened = 0;
        int closed = 0;
        if (prepared == null || prepared.valueByMeterMetric == null || prepared.valueByMeterMetric.isEmpty()) {
            return AlarmFacade.processingResult(0, 0, aiRowCount);
        }

        for (Map.Entry<Integer, Map<String, Double>> me : prepared.valueByMeterMetric.entrySet()) {
            int meterId = me.getKey().intValue();
            Map<String, Double> metricValues = me.getValue();
            OpenCloseCount c = processAiMeterRules(
                selAlarmOpen,
                selAlarmOpenAnyRule,
                insAlarm,
                clearAlarm,
                plcId,
                meterId,
                measuredAtMs,
                measuredAt,
                metricValues,
                rules,
                metricCatalogTokens,
                aiPendingOnMs);
            opened += c.opened;
            closed += c.closed;
        }
        return AlarmFacade.processingResult(opened, closed, aiRowCount);
    }

    private static OpenCloseCount processAiMeterRules(
            PreparedStatement selAlarmOpen,
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement insAlarm,
            PreparedStatement clearAlarm,
            int plcId,
            int meterId,
            long measuredAtMs,
            Timestamp measuredAt,
            Map<String, Double> metricValues,
            List<AlarmRuleDef> rules,
            Map<String, List<String>> metricCatalogTokens,
            ConcurrentHashMap<String, Long> aiPendingOnMs) throws Exception {
        OpenCloseCount out = new OpenCloseCount();
        for (AlarmRuleDef rule : rules) {
            String metricKey = normKey(rule.getMetricKey());
            for (Map.Entry<String, Double> sourceEntry : resolveAiRuleSourceValues(rule, metricCatalogTokens, metricValues).entrySet()) {
                OpenCloseCount c = processSingleAiSource(
                    selAlarmOpen,
                    selAlarmOpenAnyRule,
                    insAlarm,
                    clearAlarm,
                    plcId,
                    meterId,
                    measuredAtMs,
                    measuredAt,
                    rule,
                    metricKey,
                    sourceEntry.getKey(),
                    sourceEntry.getValue().doubleValue(),
                    aiPendingOnMs);
                out.opened += c.opened;
                out.closed += c.closed;
            }
        }
        return out;
    }

    private static OpenCloseCount processSingleAiSource(
            PreparedStatement selAlarmOpen,
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement insAlarm,
            PreparedStatement clearAlarm,
            int plcId,
            int meterId,
            long measuredAtMs,
            Timestamp measuredAt,
            AlarmRuleDef rule,
            String metricKey,
            String sourceKey,
            double value,
            ConcurrentHashMap<String, Long> aiPendingOnMs) throws Exception {
        OpenCloseCount out = new OpenCloseCount();
        String stage = AlarmFacade.evalStage(rule, value);
        String rulePrefix = AlarmFacade.buildAiEventType(rule.getRuleCode(), metricKey, sourceKey, "").replaceAll("_+$", "");
        String targetAlarmType = (stage == null) ? null : AlarmFacade.buildAiEventType(rule.getRuleCode(), metricKey, sourceKey, stage);

        if (targetAlarmType != null) {
            if (AlarmFacade.isAiAlarmOpen(meterId, targetAlarmType, measuredAtMs)) {
                aiPendingOnMs.remove(plcId + ":" + meterId + ":" + rulePrefix);
                return out;
            }
            Long openAlarmId = AlarmPersistenceSupport.findOpenAlarmId(selAlarmOpen, meterId, targetAlarmType);
            if (openAlarmId != null) {
                AlarmFacade.rememberAiAlarmOpen(meterId, targetAlarmType, stage, Double.valueOf(value), measuredAtMs);
                aiPendingOnMs.remove(plcId + ":" + meterId + ":" + rulePrefix);
                return out;
            }
        }

        out.closed += closeStaleAiAlarmStages(selAlarmOpenAnyRule, clearAlarm, meterId, rulePrefix + "_", targetAlarmType, measuredAt);

        if (targetAlarmType == null) {
            aiPendingOnMs.remove(plcId + ":" + meterId + ":" + rulePrefix);
            return out;
        }

        String pendingKey = plcId + ":" + meterId + ":" + rulePrefix + ":" + stage;
        Long prev = aiPendingOnMs.putIfAbsent(pendingKey, Long.valueOf(measuredAtMs));
        long startMs = (prev == null) ? measuredAtMs : prev.longValue();
        int holdSec = Math.max(0, rule.getDurationSec());
        if (holdSec > 0 && measuredAtMs - startMs < (holdSec * 1000L)) return out;

        String resolvedSource = sourceKey.isEmpty() ? metricKey : sourceKey;
        String desc = "PLC " + plcId + " AI alarm: meter=" + meterId +
            ", rule=" + rule.getRuleCode() +
            ", stage=" + stage +
            ", metric=" + rule.getMetricKey() +
            ", source=" + resolvedSource +
            ", value=" + formatDecimal2(value) +
            ", op=" + (rule.getOperator() == null ? "" : rule.getOperator()) +
            ", t1=" + (rule.getThreshold1() == null ? "null" : formatDecimal2(rule.getThreshold1())) +
            ", t2=" + (rule.getThreshold2() == null ? "null" : formatDecimal2(rule.getThreshold2()));
        desc = AlarmFacade.renderAiMessage(rule, meterId, stage, resolvedSource, value, desc);
        Long openAlarmId = AlarmPersistenceSupport.findOpenAlarmId(selAlarmOpen, meterId, targetAlarmType);
        if (openAlarmId == null) {
            AlarmPersistenceSupport.insertAiAlarm(insAlarm, meterId, targetAlarmType, stage, measuredAt, desc, rule, value, resolvedSource);
            AlarmFacade.rememberAiAlarmOpen(meterId, targetAlarmType, stage, Double.valueOf(value), measuredAtMs);
            out.opened++;
        } else {
            AlarmFacade.rememberAiAlarmOpen(meterId, targetAlarmType, stage, Double.valueOf(value), measuredAtMs);
        }
        aiPendingOnMs.remove(pendingKey);
        return out;
    }

    private static int closeStaleAiAlarmStages(
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement clearAlarm,
            int meterId,
            String rulePrefix,
            String targetAlarmType,
            Timestamp measuredAt) throws Exception {
        int closed = 0;
        selAlarmOpenAnyRule.setInt(1, meterId);
        selAlarmOpenAnyRule.setString(2, escapeLikeLiteral(rulePrefix) + "\\_%");
        List<Long> closeIds = new ArrayList<>();
        List<String> closeTypes = new ArrayList<>();
        try (ResultSet rs = selAlarmOpenAnyRule.executeQuery()) {
            while (rs.next()) {
                long alarmId = rs.getLong("alarm_id");
                String alarmType = rs.getString("alarm_type");
                if (targetAlarmType == null || alarmType == null || !targetAlarmType.equals(alarmType)) {
                    closeIds.add(Long.valueOf(alarmId));
                    closeTypes.add(alarmType);
                }
            }
        }
        for (int i = 0; i < closeIds.size(); i++) {
            Long alarmId = closeIds.get(i);
            String alarmType = closeTypes.get(i);
            AlarmPersistenceSupport.clearOpenAlarm(clearAlarm, measuredAt, alarmId);
            if (alarmType != null && !alarmType.trim().isEmpty()) {
                AlarmFacade.queueClearAiAlarm(meterId, alarmType, "non-target ai alarm cleared");
            }
            closed++;
        }
        return closed;
    }

    private static String escapeLikeLiteral(String s) {
        if (s == null || s.isEmpty()) return "";
        return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_").replace("[", "\\[");
    }

    private static String formatDecimal2(Double value) {
        if (value == null) return "";
        return String.format(Locale.US, "%.2f", value.doubleValue());
    }

    private static String formatDecimal2(double value) {
        return String.format(Locale.US, "%.2f", value);
    }

    private static String normKey(String s) {
        return s == null ? "" : s.trim().toUpperCase(Locale.ROOT);
    }

    private static LinkedHashMap<String, Double> resolveAiRuleSourceValues(
            AlarmRuleDef rule,
            Map<String, List<String>> metricCatalogTokens,
            Map<String, Double> metricValues) {
        LinkedHashMap<String, Double> out = new LinkedHashMap<>();
        if (rule == null || metricValues == null) return out;

        String metricKey = normKey(rule.getMetricKey());
        if (isCalculatedMetricKey(metricKey)) {
            Double computed = metricValues.get(metricKey);
            if (computed != null) out.put(metricKey, computed);
            return out;
        }
        List<String> candidates = AlarmFacade.splitSourceTokens(rule.getSourceToken());
        if (candidates.isEmpty() && metricCatalogTokens != null) {
            List<String> mapped = metricCatalogTokens.get(metricKey);
            if (mapped != null && !mapped.isEmpty()) candidates = mapped;
        }

        for (String key : candidates) {
            Double v = metricValues.get(normKey(key));
            if (v != null) out.put(normKey(key), v);
        }

        if (out.isEmpty()) {
            Double v = metricValues.get(metricKey);
            if (v != null) out.put(metricKey, v);
        }
        return out;
    }

    private static boolean isCalculatedMetricKey(String metricKey) {
        String mk = normKey(metricKey);
        return "V_UNBALANCE".equals(mk)
            || "VOLTAGE_UNBALANCE".equals(mk)
            || "VOLTAGE_UNBALANCE_RATE".equals(mk)
            || "I_UNBALANCE".equals(mk)
            || "CURRENT_UNBALANCE".equals(mk)
            || "CURRENT_UNBALANCE_RATE".equals(mk)
            || "V_VARIATION".equals(mk)
            || "VOLTAGE_VARIATION".equals(mk)
            || "I_VARIATION".equals(mk)
            || "CURRENT_VARIATION".equals(mk);
    }
}
