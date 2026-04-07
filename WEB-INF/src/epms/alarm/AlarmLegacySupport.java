package epms.alarm;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class AlarmLegacySupport {
    private AlarmLegacySupport() {
    }

    public static final class DiGroupMapRule {
        public String groupKey;
        public String metricKey;
        public String matchType;
        public String matchValue;
        public int priority;
    }

    public static final class DiGroupRule {
        public String metricKey;
        public String matchMode;
        public Integer countThreshold;
    }

    public static final class DiGroupState {
        public int pointId;
        public String metricKey;
        public int bitCount;
        public int onCount;
        public String itemName;
        public String panelName;
        public List<String> samples = new ArrayList<>();
    }

    public static int closeStaleAiStages(
            PreparedStatement selOpenAnyRule,
            PreparedStatement close,
            PreparedStatement selAlarmOpen,
            PreparedStatement clearAlarm,
            int meterId,
            String rulePrefix,
            String targetEventType,
            Timestamp measuredAt) throws Exception {
        int closed = 0;
        selOpenAnyRule.setInt(1, meterId);
        selOpenAnyRule.setString(2, escapeLikeLiteral(rulePrefix) + "\\_%");
        List<Long> closeIds = new ArrayList<>();
        List<String> closeTypes = new ArrayList<>();
        try (ResultSet rs = selOpenAnyRule.executeQuery()) {
            while (rs.next()) {
                long eid = rs.getLong("event_id");
                String et = rs.getString("event_type");
                if (targetEventType == null || et == null || !targetEventType.equals(et)) {
                    closeIds.add(Long.valueOf(eid));
                    closeTypes.add(et);
                }
            }
        }
        for (Long eid : closeIds) {
            closed += AlarmPersistenceSupport.closeOpenEvent(close, measuredAt, eid);
        }
        for (String et : closeTypes) {
            if (et == null || et.trim().isEmpty()) continue;
            AlarmPersistenceSupport.clearOpenAlarm(clearAlarm, measuredAt, AlarmPersistenceSupport.findOpenAlarmId(selAlarmOpen, meterId, et));
            AlarmFacade.clearAiAlarmOpen(meterId, et);
            AlarmFacade.queueClearAiAlarm(meterId, et, "stale ai alarm cleared");
        }
        return closed;
    }

    public static boolean shouldCloseOpenEvent(AlarmRuleDef r, double value) {
        double h = (r.getHysteresis() == null) ? 0.0d : Math.abs(r.getHysteresis().doubleValue());
        if (h <= 0.0d) return !AlarmFacade.evalOpen(r.getOperator(), r.getThreshold1(), r.getThreshold2(), value);

        String op = r.getOperator() == null ? ">=" : r.getOperator().trim().toUpperCase(Locale.ROOT);
        if ("BETWEEN".equals(op)) {
            if (r.getThreshold1() == null || r.getThreshold2() == null) return true;
            double lo = Math.min(r.getThreshold1().doubleValue(), r.getThreshold2().doubleValue());
            double hi = Math.max(r.getThreshold1().doubleValue(), r.getThreshold2().doubleValue());
            return value < (lo - h) || value > (hi + h);
        }
        if ("OUTSIDE".equals(op)) {
            if (r.getThreshold1() == null || r.getThreshold2() == null) return true;
            double lo = Math.min(r.getThreshold1().doubleValue(), r.getThreshold2().doubleValue());
            double hi = Math.max(r.getThreshold1().doubleValue(), r.getThreshold2().doubleValue());
            return value >= (lo + h) && value <= (hi - h);
        }
        if (r.getThreshold1() == null) return true;
        double x = r.getThreshold1().doubleValue();

        if (">=".equals(op) || ">".equals(op)) return value < (x - h);
        if ("<=".equals(op) || "<".equals(op)) return value > (x + h);
        if ("=".equals(op)) return Math.abs(value - x) > h;
        if ("!=".equals(op) || "<>".equals(op)) return Math.abs(value - x) <= h;
        return !AlarmFacade.evalOpen(op, r.getThreshold1(), r.getThreshold2(), value);
    }

    public static List<AlarmRuleDef> loadEnabledDiRules(Connection conn) throws Exception {
        List<AlarmRuleDef> out = new ArrayList<>();
        String sql =
            "SELECT rule_id, rule_code, target_scope, metric_key, source_token, message_template, operator, threshold1, threshold2, duration_sec, hysteresis, severity " +
            "FROM dbo.alarm_rule " +
            "WHERE enabled = 1 AND UPPER(target_scope) = 'PLC' " +
            "ORDER BY rule_id";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Object t1 = rs.getObject("threshold1");
                Object t2 = rs.getObject("threshold2");
                Object hy = rs.getObject("hysteresis");
                String ruleCode = rs.getString("rule_code");
                String metricKey = rs.getString("metric_key");
                if (ruleCode == null || ruleCode.trim().isEmpty()) continue;
                if (metricKey == null || metricKey.trim().isEmpty()) continue;
                out.add(AlarmFacade.ruleDef(
                    rs.getInt("rule_id"),
                    ruleCode,
                    rs.getString("target_scope"),
                    metricKey,
                    rs.getString("source_token"),
                    rs.getString("message_template"),
                    rs.getString("operator"),
                    (t1 instanceof Number) ? ((Number) t1).doubleValue() : null,
                    (t2 instanceof Number) ? ((Number) t2).doubleValue() : null,
                    rs.getInt("duration_sec"),
                    (hy instanceof Number) ? ((Number) hy).doubleValue() : null,
                    rs.getString("severity")));
            }
        }
        return out;
    }

    public static List<DiGroupMapRule> loadEnabledDiGroupMapRules(Connection conn) {
        List<DiGroupMapRule> out = new ArrayList<>();
        String sql =
            "IF OBJECT_ID('dbo.di_signal_group_map','U') IS NOT NULL " +
            "SELECT group_key, metric_key, match_type, match_value, priority " +
            "FROM dbo.di_signal_group_map WHERE enabled = 1 ORDER BY priority, group_map_id";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                DiGroupMapRule r = new DiGroupMapRule();
                r.groupKey = rs.getString("group_key");
                r.metricKey = rs.getString("metric_key");
                r.matchType = rs.getString("match_type");
                r.matchValue = rs.getString("match_value");
                r.priority = rs.getInt("priority");
                if (r.metricKey == null || r.metricKey.trim().isEmpty()) continue;
                out.add(r);
            }
        } catch (Exception ignore) {
        }
        return out;
    }

    public static Map<String, DiGroupRule> loadEnabledDiGroupRules(Connection conn) {
        Map<String, DiGroupRule> out = new HashMap<>();
        String sql =
            "IF OBJECT_ID('dbo.di_group_rule_map','U') IS NOT NULL " +
            "SELECT metric_key, match_mode, count_threshold FROM dbo.di_group_rule_map WHERE enabled = 1";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                DiGroupRule r = new DiGroupRule();
                r.metricKey = rs.getString("metric_key");
                r.matchMode = rs.getString("match_mode");
                Object x = rs.getObject("count_threshold");
                r.countThreshold = (x instanceof Number) ? Integer.valueOf(((Number) x).intValue()) : null;
                if (r.metricKey == null || r.metricKey.trim().isEmpty()) continue;
                out.put(r.metricKey.trim().toUpperCase(Locale.ROOT), r);
            }
        } catch (Exception ignore) {
        }
        return out;
    }

    public static boolean matchesDiGroupRule(Map<String, Object> row, DiGroupMapRule rule) {
        if (row == null || rule == null) return false;
        String matchType = rule.matchType == null ? "" : rule.matchType.trim().toUpperCase(Locale.ROOT);
        String matchValue = normalizeMatchText(rule.matchValue);
        if (matchValue.isEmpty()) return false;
        if ("TAG_NAME".equals(matchType)) return normalizeMatchText(String.valueOf(row.get("tag_name") == null ? "" : row.get("tag_name"))).contains(matchValue);
        if ("ITEM_NAME".equals(matchType)) return normalizeMatchText(String.valueOf(row.get("item_name") == null ? "" : row.get("item_name"))).contains(matchValue);
        if ("PANEL_NAME".equals(matchType)) return normalizeMatchText(String.valueOf(row.get("panel_name") == null ? "" : row.get("panel_name"))).contains(matchValue);
        if ("POINT_ID".equals(matchType)) return String.valueOf(((Number) row.get("point_id")).intValue()).equals(matchValue);
        if ("ADDRESS_BIT".equals(matchType)) {
            String key = ((Number) row.get("di_address")).intValue() + ":" + ((Number) row.get("bit_no")).intValue();
            return key.equals(matchValue) || key.equals(matchValue.replace('.', ':'));
        }
        return false;
    }

    public static boolean evalDiGroupActive(DiGroupRule groupRule, DiGroupState state) {
        if (state == null || state.bitCount <= 0) return false;
        String mode = groupRule == null || groupRule.matchMode == null ? "ANY_ON" : groupRule.matchMode.trim().toUpperCase(Locale.ROOT);
        if ("ALL_ON".equals(mode)) return state.onCount == state.bitCount;
        if ("COUNT_GE".equals(mode)) {
            int threshold = (groupRule == null || groupRule.countThreshold == null || groupRule.countThreshold.intValue() <= 0) ? 1 : groupRule.countThreshold.intValue();
            return state.onCount >= threshold;
        }
        return state.onCount >= 1;
    }

    public static void insertDiRuleAlarm(
            PreparedStatement insAlarm,
            int deviceId,
            String eventType,
            String severity,
            Timestamp measuredAt,
            String description,
            AlarmRuleDef rule,
            double value) throws Exception {
        insAlarm.setInt(1, deviceId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        insAlarm.setInt(6, rule.getRuleId());
        insAlarm.setString(7, rule.getRuleCode());
        insAlarm.setString(8, rule.getMetricKey());
        insAlarm.setString(9, (rule.getSourceToken() == null || rule.getSourceToken().trim().isEmpty()) ? rule.getMetricKey() : rule.getSourceToken());
        insAlarm.setDouble(10, value);
        insAlarm.setString(11, rule.getOperator());
        if (rule.getThreshold1() == null) insAlarm.setNull(12, Types.FLOAT); else insAlarm.setDouble(12, rule.getThreshold1().doubleValue());
        if (rule.getThreshold2() == null) insAlarm.setNull(13, Types.FLOAT); else insAlarm.setDouble(13, rule.getThreshold2().doubleValue());
        insAlarm.executeUpdate();
    }

    private static String normalizeMatchText(String s) {
        if (s == null) return "";
        return s.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "").trim();
    }

    private static String escapeLikeLiteral(String s) {
        if (s == null || s.isEmpty()) return "";
        return s.replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_")
                .replace("[", "\\[");
    }
}
