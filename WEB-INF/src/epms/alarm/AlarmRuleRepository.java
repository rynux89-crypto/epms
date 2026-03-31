package epms.alarm;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public final class AlarmRuleRepository {
    private AlarmRuleRepository() {
    }

    public static List<AlarmRuleDef> loadEnabledAiRuleDefs(Connection conn) throws Exception {
        List<AlarmRuleDef> out = new ArrayList<>();
        String sql =
                "IF OBJECT_ID('dbo.metric_catalog','U') IS NOT NULL " +
                "SELECT r.rule_id, r.rule_code, r.target_scope, r.metric_key, r.source_token, r.message_template, r.operator, r.threshold1, r.threshold2, r.duration_sec, r.hysteresis, r.severity " +
                "FROM dbo.alarm_rule r " +
                "JOIN dbo.metric_catalog mc ON mc.metric_key = r.metric_key " +
                "WHERE r.enabled = 1 " +
                "  AND UPPER(r.target_scope) IN ('METER','AI') " +
                "  AND mc.enabled = 1 " +
                "  AND UPPER(ISNULL(mc.source_type,'AI')) IN ('AI','SYSTEM') " +
                "ORDER BY r.rule_id " +
                "ELSE " +
                "SELECT rule_id, rule_code, target_scope, metric_key, source_token, message_template, operator, threshold1, threshold2, duration_sec, hysteresis, severity " +
                "FROM dbo.alarm_rule " +
                "WHERE enabled = 1 AND UPPER(target_scope) IN ('METER','AI') " +
                "ORDER BY rule_id";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String ruleCode = rs.getString("rule_code");
                String metricKey = rs.getString("metric_key");
                if (ruleCode == null || ruleCode.trim().isEmpty()) {
                    continue;
                }
                if (metricKey == null || metricKey.trim().isEmpty()) {
                    continue;
                }
                Object t1 = rs.getObject("threshold1");
                Object t2 = rs.getObject("threshold2");
                Object hy = rs.getObject("hysteresis");
                out.add(new AlarmRuleDef(
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
                        rs.getString("severity")
                ));
            }
        }
        return out;
    }
}
