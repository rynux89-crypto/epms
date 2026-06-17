package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsFormatSupport;
import epms.util.UpsSimulatorSupport;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import javax.servlet.ServletContext;

public final class UpsAlarmEventService {
    private UpsAlarmEventService() {
    }

    public static List<Map<String, Object>> alarmRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        return UpsAlarmRow.toMaps(alarmRowList(searchText, fromTs, toTs));
    }

    public static List<Map<String, Object>> activeAlarmRows(String searchText) throws Exception {
        return UpsAlarmRow.toMaps(activeAlarmRowList(searchText));
    }

    public static List<UpsAlarmRow> activeAlarmRowList(String searchText) throws Exception {
        String normalizedSearchText = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 200 a.alarm_id, d.ups_name, d.enabled AS device_enabled, a.severity, a.metric_key, a.alarm_message, a.occurred_at, a.cleared_at, a.status ")
           .append("FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ")
           .append("WHERE a.status = 'ACTIVE' AND d.enabled = 1 ");
        List<Object> params = new ArrayList<Object>();
        appendAlarmSearch(sql, params, searchText, normalizedSearchText);
        sql.append("ORDER BY a.occurred_at DESC");
        return queryAlarmRows(sql.toString(), params);
    }

    public static List<UpsAlarmRow> alarmRowList(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        String normalizedSearchText = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 200 a.alarm_id, d.ups_name, d.enabled AS device_enabled, a.severity, a.metric_key, a.alarm_message, a.occurred_at, a.cleared_at, a.status ")
           .append("FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ")
           .append("WHERE a.status <> 'EVENT' ");
        List<Object> params = new ArrayList<Object>();
        appendAlarmSearch(sql, params, searchText, normalizedSearchText);
        appendTimeRange(sql, params, fromTs, toTs);
        sql.append("ORDER BY a.occurred_at DESC");
        return queryAlarmRows(sql.toString(), params);
    }

    public static List<Map<String, Object>> eventRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        return UpsAlarmRow.toMaps(eventRowList(searchText, fromTs, toTs));
    }

    public static List<UpsAlarmRow> eventRowList(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        String normalizedSearchText = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 200 a.alarm_id, d.ups_name, d.enabled AS device_enabled, a.severity, a.alarm_message, a.occurred_at, a.status ")
           .append("FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ")
           .append("WHERE a.status = 'EVENT' ");
        List<Object> params = new ArrayList<Object>();
        appendEventSearch(sql, params, searchText, normalizedSearchText);
        appendTimeRange(sql, params, fromTs, toTs);
        sql.append("ORDER BY a.occurred_at DESC");
        return queryAlarmRows(sql.toString(), params);
    }

    public static void syncSimulatorScenarioEvent(ServletContext app) {
        if (app == null) return;
        String simStatus = UpsSimulatorSupport.readStatus(250);
        String current = UpsSimulatorSupport.jsonText(simStatus, "scenario", "");
        if (current.isEmpty()) return;
        synchronized (app) {
            Object oldValue = app.getAttribute("ups.simulator.scenario");
            app.setAttribute("ups.simulator.scenario", current);
            if (isAlarmScenario(current)) return;
            if (!(oldValue instanceof String)) {
                if (!"normal".equals(current)) insertScenarioEvent("", current);
                return;
            }
            String previous = (String) oldValue;
            if (isAlarmScenario(previous)) return;
            if (!previous.equals(current)) insertScenarioEvent(previous, current);
        }
    }

    private static boolean isAlarmScenario(String scenario) {
        return "low_battery".equals(scenario)
            || "overload".equals(scenario)
            || "input_fault".equals(scenario)
            || "output_fault".equals(scenario)
            || "bypass_fault".equals(scenario)
            || "power_module_fault".equals(scenario)
            || "critical".equals(scenario)
            || "epo".equals(scenario)
            || "output_off".equals(scenario);
    }

    private static void insertScenarioEvent(String before, String after) {
        String message = before == null || before.isEmpty()
            ? UpsFormatSupport.scenarioLabel(after)
            : UpsFormatSupport.scenarioLabel(before) + " -> " + UpsFormatSupport.scenarioLabel(after);
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            Integer upsId = findSimulatorUpsId(conn);
            if (upsId == null) return;
            try (PreparedStatement dup = conn.prepareStatement(
                    "SELECT TOP 1 1 FROM dbo.ups_alarm_log WHERE ups_id=? AND rule_code='UPS_SCENARIO_CHANGE' " +
                    "AND alarm_message=? AND status='EVENT' AND occurred_at >= DATEADD(second, -15, sysdatetime())")) {
                dup.setInt(1, upsId.intValue());
                dup.setString(2, message);
                try (ResultSet rs = dup.executeQuery()) {
                    if (rs.next()) return;
                }
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
                    "VALUES (?, 'UPS_SCENARIO_CHANGE', 'ups_operation_mode', 'INFO', ?, sysdatetime(), 'EVENT')")) {
                ps.setInt(1, upsId.intValue());
                ps.setString(2, message);
                ps.executeUpdate();
            }
        } catch (Exception ignore) {
        }
    }

    private static Integer findSimulatorUpsId(Connection conn) throws Exception {
        try (PreparedStatement find = conn.prepareStatement(
                "SELECT TOP 1 ups_id FROM dbo.ups_device WHERE ip_address='127.0.0.1' AND modbus_port=1502 AND unit_id=1 ORDER BY ups_id");
             ResultSet rs = find.executeQuery()) {
            return rs.next() ? Integer.valueOf(rs.getInt("ups_id")) : null;
        }
    }

    private static void appendAlarmSearch(StringBuilder sql, List<Object> params, String searchText, String normalizedSearchText) {
        if (searchText == null || searchText.trim().isEmpty()) return;
        appendBaseAlarmSearch(sql, params, searchText, normalizedSearchText);
        if (normalizedSearchText.contains("\uC785\uB825\uC774\uC0C1")) {
            sql.append("OR a.rule_code LIKE 'INPUT_%' OR a.metric_key = 'input_status' ");
        }
        if (normalizedSearchText.contains("\uCD9C\uB825\uC774\uC0C1") || normalizedSearchText.contains("\uACFC\uBD80\uD558")) {
            sql.append("OR a.rule_code LIKE 'OUTPUT_%' OR a.metric_key = 'output_status' OR a.metric_key = 'output_load_total_percent' ");
        }
        if (normalizedSearchText.contains("\uBC14\uC774\uD328\uC2A4\uC774\uC0C1") || normalizedSearchText.contains("\uBC14\uC774\uD328\uC2A4")) {
            sql.append("OR a.rule_code LIKE 'BYPASS_%' OR a.metric_key = 'bypass_status' ");
        }
        if (normalizedSearchText.contains("\uD30C\uC6CC\uBAA8\uB4C8\uC774\uC0C1") || normalizedSearchText.contains("\uD30C\uC6CC\uBAA8\uB4C8")) {
            sql.append("OR a.rule_code LIKE 'POWER_MODULE_%' OR a.metric_key = 'power_module_status' ");
        }
        if (normalizedSearchText.contains("\uBC30\uD130\uB9AC")) {
            sql.append("OR a.rule_code LIKE 'BATTERY_%' OR a.rule_code LIKE 'ENERGY_%' OR a.metric_key LIKE 'battery_%' OR a.metric_key LIKE 'energy_storage_%' ");
        }
        if (normalizedSearchText.contains("\uC911\uC694")) {
            sql.append("OR a.severity = 'CRITICAL' OR a.rule_code LIKE '%CRITICAL%' ");
        }
        sql.append(") ");
    }

    private static void appendEventSearch(StringBuilder sql, List<Object> params, String searchText, String normalizedSearchText) {
        if (searchText == null || searchText.trim().isEmpty()) return;
        appendBaseAlarmSearch(sql, params, searchText, normalizedSearchText);
        sql.append(") ");
    }

    private static void appendBaseAlarmSearch(StringBuilder sql, List<Object> params, String searchText, String normalizedSearchText) {
        sql.append("AND (d.ups_name LIKE ? OR d.location LIKE ? OR d.ip_address LIKE ? OR a.rule_code LIKE ? OR a.alarm_message LIKE ? ");
        String like = "%" + searchText.trim() + "%";
        params.add(like);
        params.add(like);
        params.add(like);
        params.add(like);
        params.add(like);
        if (!normalizedSearchText.isEmpty()) {
            sql.append("OR REPLACE(d.ups_name, ' ', '') LIKE ? OR REPLACE(d.location, ' ', '') LIKE ? OR REPLACE(a.rule_code, ' ', '') LIKE ? OR REPLACE(a.alarm_message, ' ', '') LIKE ? ");
            String nlike = "%" + normalizedSearchText + "%";
            params.add(nlike);
            params.add(nlike);
            params.add(nlike);
            params.add(nlike);
        }
        if (searchText.toLowerCase(Locale.ROOT).contains("sim")) {
            sql.append("OR (d.ip_address = '127.0.0.1' AND d.modbus_port = 1502) ");
        }
    }

    private static void appendTimeRange(StringBuilder sql, List<Object> params, Timestamp fromTs, Timestamp toTs) {
        if (fromTs != null) {
            sql.append("AND a.occurred_at >= ? ");
            params.add(fromTs);
        }
        if (toTs != null) {
            sql.append("AND a.occurred_at <= ? ");
            params.add(toTs);
        }
    }

    private static List<UpsAlarmRow> queryAlarmRows(String sql, List<Object> params) throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            bind(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                List<UpsAlarmRow> out = new ArrayList<UpsAlarmRow>();
                while (rs.next()) {
                    out.add(UpsAlarmRow.from(rs));
                }
                return out;
            }
        }
    }

    private static void bind(PreparedStatement ps, List<Object> params) throws Exception {
        for (int i = 0; i < params.size(); i++) {
            Object p = params.get(i);
            if (p instanceof Timestamp) ps.setTimestamp(i + 1, (Timestamp)p);
            else if (p instanceof Integer) ps.setInt(i + 1, ((Integer)p).intValue());
            else ps.setObject(i + 1, p);
        }
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", "");
    }
}
