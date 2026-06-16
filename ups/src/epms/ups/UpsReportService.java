package epms.ups;

import epms.util.UpsDataSourceProvider;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class UpsReportService {
    private UpsReportService() {
    }

    public static List<Map<String, Object>> reportRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        List<Map<String, Object>> rows = measurementReportRows(searchText, fromTs, toTs);
        Map<String, Map<String, Object>> alarmMap = alarmReportMap(searchText, fromTs, toTs);
        for (Map<String, Object> row : rows) {
            String upsId = String.valueOf(row.get("ups_id"));
            Map<String, Object> alarm = alarmMap.get(upsId);
            row.put("alarm_count", alarm == null ? Integer.valueOf(0) : alarm.get("alarm_count"));
            row.put("event_count", alarm == null ? Integer.valueOf(0) : alarm.get("event_count"));
            row.put("critical_count", alarm == null ? Integer.valueOf(0) : alarm.get("critical_count"));
        }
        return rows;
    }

    private static List<Map<String, Object>> measurementReportRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        StringBuilder sql = new StringBuilder();
        List<Object> params = new ArrayList<Object>();
        sql.append("SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, ")
           .append("COUNT(m.measurement_id) AS measurement_count, MIN(m.measured_at) AS first_measured_at, MAX(m.measured_at) AS last_measured_at, ")
           .append("AVG(m.load_percent) AS avg_load_percent, MAX(m.load_percent) AS max_load_percent, ")
           .append("AVG(m.output_power_kw) AS avg_output_kw, MAX(m.output_power_kw) AS max_output_kw, ")
           .append("AVG(m.output_apparent_total_kva) AS avg_output_kva, MAX(m.output_apparent_total_kva) AS max_output_kva, ")
           .append("AVG(m.frequency) AS avg_frequency, MIN(m.frequency) AS min_frequency, MAX(m.frequency) AS max_frequency, ")
           .append("AVG(m.output_voltage_l12) AS avg_voltage_l12, AVG(m.output_voltage_l23) AS avg_voltage_l23, AVG(m.output_voltage_l31) AS avg_voltage_l31, ")
           .append("MAX(m.output_current_l1) AS max_current_l1, MAX(m.output_current_l2) AS max_current_l2, MAX(m.output_current_l3) AS max_current_l3, ")
           .append("AVG(m.output_pf_l1) AS avg_pf_l1, AVG(m.output_pf_l2) AS avg_pf_l2, AVG(m.output_pf_l3) AS avg_pf_l3, ")
           .append("MIN(m.battery_charge_percent) AS min_battery_charge, AVG(m.battery_charge_percent) AS avg_battery_charge, ")
           .append("MAX(m.battery_temperature) AS max_battery_temperature, ")
           .append("SUM(CASE WHEN m.ups_operation_mode_code = 4 THEN 1 ELSE 0 END) AS battery_mode_count ")
           .append("FROM dbo.ups_device d ")
           .append("LEFT JOIN dbo.ups_measurement m ON m.ups_id = d.ups_id ");
        if (fromTs != null) {
            sql.append("AND m.measured_at >= ? ");
            params.add(fromTs);
        }
        if (toTs != null) {
            sql.append("AND m.measured_at <= ? ");
            params.add(toTs);
        }
        sql.append("WHERE 1=1 ");
        appendReportDeviceSearch(sql, params, searchText);
        sql.append("GROUP BY d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port ")
           .append("ORDER BY d.ups_name");
        return query(sql.toString(), params);
    }

    private static Map<String, Map<String, Object>> alarmReportMap(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        StringBuilder sql = new StringBuilder();
        List<Object> params = new ArrayList<Object>();
        sql.append("SELECT d.ups_id, ")
           .append("SUM(CASE WHEN a.status <> 'EVENT' THEN 1 ELSE 0 END) AS alarm_count, ")
           .append("SUM(CASE WHEN a.status = 'EVENT' THEN 1 ELSE 0 END) AS event_count, ")
           .append("SUM(CASE WHEN a.severity = 'CRITICAL' THEN 1 ELSE 0 END) AS critical_count ")
           .append("FROM dbo.ups_device d ")
           .append("LEFT JOIN dbo.ups_alarm_log a ON a.ups_id = d.ups_id ");
        if (fromTs != null) {
            sql.append("AND a.occurred_at >= ? ");
            params.add(fromTs);
        }
        if (toTs != null) {
            sql.append("AND a.occurred_at <= ? ");
            params.add(toTs);
        }
        sql.append("WHERE 1=1 ");
        appendReportDeviceSearch(sql, params, searchText);
        sql.append("GROUP BY d.ups_id");

        List<Map<String, Object>> rows = query(sql.toString(), params);
        Map<String, Map<String, Object>> out = new HashMap<String, Map<String, Object>>();
        for (Map<String, Object> row : rows) {
            out.put(String.valueOf(row.get("ups_id")), row);
        }
        return out;
    }

    private static void appendReportDeviceSearch(StringBuilder sql, List<Object> params, String searchText) {
        if (searchText == null || searchText.trim().isEmpty()) return;
        String raw = searchText.trim();
        String normalized = normalize(raw);
        sql.append("AND (d.ups_name LIKE ? OR d.location LIKE ? OR d.ip_address LIKE ? ");
        String like = "%" + raw + "%";
        params.add(like);
        params.add(like);
        params.add(like);
        if (!normalized.isEmpty()) {
            String nlike = "%" + normalized + "%";
            sql.append("OR REPLACE(d.ups_name, ' ', '') LIKE ? OR REPLACE(d.location, ' ', '') LIKE ? ");
            params.add(nlike);
            params.add(nlike);
        }
        if (raw.toLowerCase(Locale.ROOT).contains("sim")) {
            sql.append("OR (d.ip_address = '127.0.0.1' AND d.modbus_port = 1502) ");
        }
        sql.append(") ");
    }

    private static List<Map<String, Object>> query(String sql, List<Object> params) throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            bind(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                return rows(rs);
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

    private static List<Map<String, Object>> rows(ResultSet rs) throws Exception {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        ResultSetMetaData md = rs.getMetaData();
        while (rs.next()) {
            Map<String, Object> row = new HashMap<String, Object>();
            for (int i = 1; i <= md.getColumnCount(); i++) {
                row.put(md.getColumnLabel(i), rs.getObject(i));
            }
            out.add(row);
        }
        return out;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", "");
    }
}
