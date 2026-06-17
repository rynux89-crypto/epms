package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsJsonSupport;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import javax.servlet.ServletContext;

public final class UpsApiService {
    private UpsApiService() {
    }

    public static String statusJson() {
        StringBuilder json = new StringBuilder();
        json.append("{\"ok\":true,\"items\":[");
        boolean first = true;
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.last_comm_status, " +
                 "m.measured_at, m.load_percent, m.battery_charge_percent " +
                 "FROM dbo.ups_device d OUTER APPLY (" +
                 "SELECT TOP 1 * FROM dbo.ups_measurement m WHERE m.ups_id = d.ups_id ORDER BY m.measured_at DESC) m " +
                 "WHERE d.enabled = 1 ORDER BY d.ups_name")) {
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    if (!first) {
                        json.append(',');
                    }
                    first = false;
                    json.append('{')
                        .append("\"ups_id\":").append(rs.getInt("ups_id")).append(',')
                        .append("\"ups_name\":").append(UpsJsonSupport.quote(rs.getString("ups_name"))).append(',')
                        .append("\"location\":").append(UpsJsonSupport.quote(rs.getString("location"))).append(',')
                        .append("\"ip_address\":").append(UpsJsonSupport.quote(rs.getString("ip_address"))).append(',')
                        .append("\"last_comm_status\":").append(UpsJsonSupport.quote(rs.getString("last_comm_status"))).append(',')
                        .append("\"measured_at\":").append(UpsJsonSupport.quote(String.valueOf(rs.getObject("measured_at")))).append(',')
                        .append("\"load_percent\":").append(jsonNumber(rs.getObject("load_percent"))).append(',')
                        .append("\"battery_charge_percent\":").append(jsonNumber(rs.getObject("battery_charge_percent")))
                        .append('}');
                }
            }
            json.append("]}");
            return json.toString();
        } catch (Exception e) {
            return UpsJsonSupport.error(e.getMessage());
        }
    }

    public static String collectorPollJson(ServletContext application) {
        int beforeMeasurements = 0;
        int afterMeasurements = 0;
        int beforeComm = 0;
        int afterComm = 0;
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            beforeMeasurements = countTable(conn, "dbo.ups_measurement");
            beforeComm = countTable(conn, "dbo.ups_comm_status");
        } catch (Exception e) {
            return UpsJsonSupport.error(e.getMessage());
        }

        try {
            long started = System.currentTimeMillis();
            if (application != null) {
                application.setAttribute("ups.collector.lastStartAt", new Timestamp(started));
            }
            new UpsCollectorService().pollEnabledDevices();
            try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
                afterMeasurements = countTable(conn, "dbo.ups_measurement");
                afterComm = countTable(conn, "dbo.ups_comm_status");
            }
            if (application != null) {
                application.setAttribute("ups.collector.status", "OK");
                application.setAttribute("ups.collector.lastSuccessAt", new Timestamp(System.currentTimeMillis()));
                application.setAttribute("ups.collector.lastDurationMs", Long.valueOf(System.currentTimeMillis() - started));
                application.removeAttribute("ups.collector.lastError");
            }
            return "{\"ok\":true" +
                ",\"measurement_before\":" + beforeMeasurements +
                ",\"measurement_after\":" + afterMeasurements +
                ",\"measurement_inserted\":" + (afterMeasurements - beforeMeasurements) +
                ",\"comm_before\":" + beforeComm +
                ",\"comm_after\":" + afterComm +
                "}";
        } catch (Exception e) {
            if (application != null) {
                application.setAttribute("ups.collector.status", "ERROR");
                application.setAttribute("ups.collector.lastErrorAt", new Timestamp(System.currentTimeMillis()));
                application.setAttribute("ups.collector.lastError", e.getMessage());
            }
            return "{\"ok\":false" +
                ",\"measurement_before\":" + beforeMeasurements +
                ",\"comm_before\":" + beforeComm +
                ",\"error\":\"" + UpsJsonSupport.esc(e.getMessage()) + "\"}";
        }
    }

    public static String simulatorAlarmTestJson(String rawRuleCode, String rawActive) {
        String ruleCode = cleanRuleCode(rawRuleCode);
        boolean active = activeParam(rawActive);
        if (ruleCode.length() == 0) {
            return UpsJsonSupport.error("invalid rule code");
        }

        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            Integer upsId = findSimulatorUpsId(conn);
            if (upsId == null) {
                return UpsJsonSupport.error("simulator UPS is not registered");
            }

            AlarmRule rule = loadAlarmRule(conn, ruleCode);
            if (rule == null) {
                return UpsJsonSupport.error("alarm rule not found");
            }

            if (active) {
                if (hasActiveAlarm(conn, upsId.intValue(), ruleCode)) {
                    return "{\"ok\":true,\"inserted\":false,\"alreadyActive\":true}";
                }
                try (PreparedStatement ps = conn.prepareStatement(
                        "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
                        "VALUES (?, ?, ?, ?, ?, sysdatetime(), 'ACTIVE')")) {
                    ps.setInt(1, upsId.intValue());
                    ps.setString(2, ruleCode);
                    ps.setString(3, rule.metricKey);
                    ps.setString(4, rule.severity == null ? "WARNING" : rule.severity);
                    ps.setString(5, rule.message);
                    ps.executeUpdate();
                }
                return "{\"ok\":true,\"inserted\":true,\"status\":\"ACTIVE\"}";
            }

            int updated;
            try (PreparedStatement ps = conn.prepareStatement(
                    "UPDATE dbo.ups_alarm_log SET status='CLEARED', cleared_at=sysdatetime() " +
                    "WHERE ups_id=? AND rule_code=? AND status='ACTIVE'")) {
                ps.setInt(1, upsId.intValue());
                ps.setString(2, ruleCode);
                updated = ps.executeUpdate();
            }
            return "{\"ok\":true,\"cleared\":" + updated + ",\"status\":\"CLEARED\"}";
        } catch (Exception e) {
            return UpsJsonSupport.error(e.getMessage());
        }
    }

    public static String simulatorBreakerEventJson(String rawName, String rawBefore, String rawAfter) {
        String name = cleanBreakerName(rawName);
        String before = cleanBreakerState(rawBefore);
        String after = cleanBreakerState(rawAfter);
        if (name.length() == 0 || before.length() == 0 || after.length() == 0) {
            return UpsJsonSupport.error("invalid breaker event");
        }
        if (before.equals(after)) {
            return "{\"ok\":true,\"inserted\":false}";
        }
        String metricKey = "BB".equals(name) ? "battery_breaker_status" : "switchgear_status";
        String ruleCode = "BREAKER_" + name + "_CHANGE";
        String message = name + " " + before + " -> " + after;
        return insertSimulatorEvent(ruleCode, metricKey, message, 3);
    }

    public static String simulatorScenarioEventJson(String rawBefore, String rawAfter) {
        String before = cleanScenario(rawBefore);
        String after = cleanScenario(rawAfter);
        if (after.length() == 0) {
            return UpsJsonSupport.error("invalid scenario event");
        }
        if (before.equals(after)) {
            return "{\"ok\":true,\"inserted\":false}";
        }
        if (isAlarmScenario(before) || isAlarmScenario(after)) {
            return "{\"ok\":true,\"inserted\":false,\"suppressed\":true}";
        }
        String message = before.length() == 0 ? scenarioLabel(after) : scenarioLabel(before) + " -> " + scenarioLabel(after);
        return insertSimulatorEvent("UPS_SCENARIO_CHANGE", "ups_operation_mode", message, 15);
    }

    private static boolean isAlarmScenario(String scenario) {
        return "low_battery".equals(scenario)
            || "overload".equals(scenario)
            || "input_fault".equals(scenario)
            || "output_fault".equals(scenario)
            || "bypass_fault".equals(scenario)
            || "power_module_fault".equals(scenario)
            || "critical".equals(scenario);
    }

    private static String insertSimulatorEvent(String ruleCode, String metricKey, String message, int duplicateSeconds) {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            Integer upsId = findSimulatorUpsId(conn);
            if (upsId == null) {
                return UpsJsonSupport.error("simulator UPS is not registered");
            }
            try (PreparedStatement dup = conn.prepareStatement(
                    "SELECT TOP 1 1 FROM dbo.ups_alarm_log " +
                    "WHERE ups_id=? AND rule_code=? AND REPLACE(alarm_message, N'차단기 ', N'')=? AND status='EVENT' " +
                    "AND occurred_at >= DATEADD(second, ?, sysdatetime())")) {
                dup.setInt(1, upsId.intValue());
                dup.setString(2, ruleCode);
                dup.setString(3, message);
                dup.setInt(4, -Math.abs(duplicateSeconds));
                try (ResultSet rs = dup.executeQuery()) {
                    if (rs.next()) {
                        return "{\"ok\":true,\"inserted\":false,\"duplicate\":true}";
                    }
                }
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
                    "VALUES (?, ?, ?, 'INFO', ?, sysdatetime(), 'EVENT')")) {
                ps.setInt(1, upsId.intValue());
                ps.setString(2, ruleCode);
                ps.setString(3, metricKey);
                ps.setString(4, message);
                ps.executeUpdate();
            }
            return "{\"ok\":true,\"inserted\":true}";
        } catch (Exception e) {
            return UpsJsonSupport.error(e.getMessage());
        }
    }

    private static Integer findSimulatorUpsId(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 ups_id FROM dbo.ups_device WHERE ip_address='127.0.0.1' AND modbus_port=1502 AND unit_id=1 ORDER BY ups_id");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? Integer.valueOf(rs.getInt("ups_id")) : null;
        }
    }

    private static int countTable(Connection conn, String tableName) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM " + tableName);
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    private static String jsonNumber(Object value) {
        return value == null ? "null" : String.valueOf(value);
    }

    private static String cleanRuleCode(String raw) {
        if (raw == null) {
            return "";
        }
        String s = raw.trim().toUpperCase(java.util.Locale.ROOT);
        return s.matches("[A-Z0-9_]{2,80}") ? s : "";
    }

    private static boolean activeParam(String raw) {
        if (raw == null) {
            return false;
        }
        String s = raw.trim().toLowerCase(java.util.Locale.ROOT);
        return "1".equals(s) || "true".equals(s) || "yes".equals(s) || "on".equals(s) || "active".equals(s);
    }

    private static String cleanBreakerName(String raw) {
        if (raw == null) {
            return "";
        }
        String s = raw.trim().toUpperCase(java.util.Locale.ROOT);
        if ("UIB".equals(s) || "UOB".equals(s) || "SSIB".equals(s) || "BF2".equals(s) || "MBB".equals(s) || "BB".equals(s)) {
            return s;
        }
        return "";
    }

    private static String cleanBreakerState(String raw) {
        if (raw == null) {
            return "";
        }
        String s = raw.trim().toLowerCase(java.util.Locale.ROOT);
        if ("1".equals(s) || "true".equals(s) || "closed".equals(s) || "close".equals(s) || "on".equals(s)) {
            return "Close";
        }
        if ("0".equals(s) || "false".equals(s) || "open".equals(s) || "off".equals(s)) {
            return "Open";
        }
        return "";
    }

    private static String cleanScenario(String raw) {
        if (raw == null) {
            return "";
        }
        String s = raw.trim().toLowerCase(java.util.Locale.ROOT);
        if ("normal".equals(s) || "battery".equals(s) || "bypass".equals(s) || "low_battery".equals(s) ||
            "overload".equals(s) || "input_fault".equals(s) || "output_fault".equals(s) ||
            "bypass_fault".equals(s) || "power_module_fault".equals(s) || "critical".equals(s)) {
            return s;
        }
        return "";
    }

    private static String scenarioLabel(String s) {
        if ("normal".equals(s)) return "정상";
        if ("battery".equals(s)) return "배터리 운전";
        if ("bypass".equals(s)) return "바이패스 운전";
        if ("low_battery".equals(s)) return "배터리 부족";
        if ("overload".equals(s)) return "과부하";
        if ("input_fault".equals(s)) return "입력 이상";
        if ("output_fault".equals(s)) return "출력 이상";
        if ("bypass_fault".equals(s)) return "바이패스 이상";
        if ("power_module_fault".equals(s)) return "파워 모듈 이상";
        if ("critical".equals(s)) return "중요 알람";
        return s;
    }

    private static AlarmRule loadAlarmRule(Connection conn, String ruleCode) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 metric_key, severity, message_template, threshold_value FROM dbo.ups_alarm_rule WHERE rule_code=?")) {
            ps.setString(1, ruleCode);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return null;
                }
                AlarmRule rule = new AlarmRule();
                rule.metricKey = rs.getString("metric_key");
                rule.severity = rs.getString("severity");
                rule.message = renderMessage(rs.getString("message_template"), rs.getObject("threshold_value"));
                return rule;
            }
        }
    }

    private static boolean hasActiveAlarm(Connection conn, int upsId, String ruleCode) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 1 FROM dbo.ups_alarm_log WHERE ups_id=? AND rule_code=? AND status='ACTIVE'")) {
            ps.setInt(1, upsId);
            ps.setString(2, ruleCode);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    private static String renderMessage(String template, Object threshold) {
        String msg = template == null || template.trim().isEmpty() ? "시뮬레이터 알람 테스트" : template;
        String value = displayValue(threshold);
        msg = msg.replace("{value}", value).replace("{threshold}", value).replace("{metric}", "");
        return msg.length() > 500 ? msg.substring(0, 500) : msg;
    }

    private static String displayValue(Object raw) {
        if (raw == null) {
            return "TEST";
        }
        try {
            BigDecimal value = raw instanceof BigDecimal ? (BigDecimal) raw : new BigDecimal(String.valueOf(raw));
            return value.setScale(1, RoundingMode.HALF_UP).toPlainString();
        } catch (Exception ignore) {
            return String.valueOf(raw);
        }
    }

    private static final class AlarmRule {
        String metricKey;
        String severity;
        String message;
    }
}
