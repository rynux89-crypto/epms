package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsSimulatorSupport;

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

public final class UpsMeasurementHistoryService {
    private UpsMeasurementHistoryService() {
    }

    public static List<Map<String, Object>> measurementHistory(String selectedId, String searchText, Timestamp fromTs, Timestamp toTs, int limit) throws Exception {
        List<Map<String, Object>> devices = UpsDeviceLookupService.listDevicesBasic();
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        out.addAll(simulatorLiveRows(devices, selectedId, searchText, fromTs, toTs));

        String normalizedSearchText = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP ").append(limit).append(" d.ups_name, d.ip_address, d.modbus_port, ")
           .append("m.measured_at, m.output_voltage_l12, m.output_voltage_l23, m.output_voltage_l31, ")
           .append("m.output_current_l1, m.output_current_l2, m.output_current_l3, ")
           .append("m.frequency, m.load_percent, m.output_power_kw, m.output_apparent_total_kva, ")
           .append("m.output_pf_l1, m.output_pf_l2, m.output_pf_l3, ")
           .append("m.battery_voltage, m.battery_current, m.battery_charge_percent, m.battery_temperature, m.remaining_minutes, ")
           .append("m.ups_operation_mode_code, m.system_operation_mode_code, m.raw_status ")
           .append("FROM dbo.ups_measurement m INNER JOIN dbo.ups_device d ON d.ups_id = m.ups_id WHERE 1=1 ");
        List<Object> params = new ArrayList<Object>();
        appendDeviceFilters(sql, params, "m.ups_id", "d", selectedId, searchText, normalizedSearchText, false);
        if (fromTs != null) {
            sql.append("AND m.measured_at >= ? ");
            params.add(fromTs);
        }
        if (toTs != null) {
            sql.append("AND m.measured_at <= ? ");
            params.add(toTs);
        }
        sql.append("ORDER BY m.measured_at DESC");
        out.addAll(query(sql.toString(), params));
        return out;
    }

    private static List<Map<String, Object>> simulatorLiveRows(List<Map<String, Object>> devices, String selectedId, String searchText, Timestamp fromTs, Timestamp toTs) {
        List<Map<String, Object>> liveRows = new ArrayList<Map<String, Object>>();
        for (Map<String, Object> device : devices) {
            if (!matchesSelected(device, selectedId)) continue;
            if (!matchesSearch(device, searchText)) continue;
            Map<String, Object> live = simulatorLiveRow(device, fromTs, toTs);
            if (live != null) liveRows.add(live);
        }
        return liveRows;
    }

    private static Map<String, Object> simulatorLiveRow(Map<String, Object> device, Timestamp fromTs, Timestamp toTs) {
        if (!UpsSimulatorSupport.isSimulatorDevice(device)) return null;
        Timestamp now = new Timestamp(System.currentTimeMillis());
        if (!inRange(now, fromTs, toTs)) return null;
        String simStatus = UpsSimulatorSupport.readStatus(250);
        if (simStatus == null || simStatus.trim().isEmpty()) return null;

        Map<String, Object> row = new HashMap<String, Object>();
        row.put("ups_name", device.get("ups_name"));
        row.put("ip_address", device.get("ip_address"));
        row.put("modbus_port", device.get("modbus_port"));
        row.put("measured_at", now);
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_voltage_l12", "output_voltage_l12");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_voltage_l23", "output_voltage_l23");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_voltage_l31", "output_voltage_l31");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_current_l1", "output_current_l1");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_current_l2", "output_current_l2");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_current_l3", "output_current_l3");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_frequency_hz", "frequency");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_load_percent", "load_percent");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_power_kw", "output_power_kw");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_apparent_total_kva", "output_apparent_total_kva");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_pf_l1", "output_pf_l1");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_pf_l2", "output_pf_l2");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_pf_l3", "output_pf_l3");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "battery_voltage", "battery_voltage");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "battery_current", "battery_current");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "battery_charge_percent", "battery_charge_percent");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "battery_temperature_c", "battery_temperature");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "remaining_minutes", "remaining_minutes");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "ups_operation_mode_code", "ups_operation_mode_code");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "system_operation_mode_code", "system_operation_mode_code");
        row.put("raw_status", "LIVE");
        return row;
    }

    private static void appendDeviceFilters(StringBuilder sql, List<Object> params, String selectedColumn, String deviceAlias, String selectedId, String searchText, String normalizedSearchText, boolean includeLocation) {
        if (selectedId != null && !selectedId.trim().isEmpty()) {
            sql.append("AND ").append(selectedColumn).append(" = ? ");
            params.add(Integer.valueOf(selectedId.trim()));
        }
        if (searchText == null || searchText.trim().isEmpty()) return;
        sql.append("AND (").append(deviceAlias).append(".ups_name LIKE ? OR ").append(deviceAlias).append(".ip_address LIKE ? ");
        params.add("%" + searchText.trim() + "%");
        params.add("%" + searchText.trim() + "%");
        if (includeLocation) {
            sql.append("OR ").append(deviceAlias).append(".location LIKE ? ");
            params.add("%" + searchText.trim() + "%");
        }
        if (!normalizedSearchText.isEmpty()) {
            sql.append("OR REPLACE(").append(deviceAlias).append(".ups_name, ' ', '') LIKE ? ");
            params.add("%" + normalizedSearchText + "%");
            if (includeLocation) {
                sql.append("OR REPLACE(").append(deviceAlias).append(".location, ' ', '') LIKE ? ");
                params.add("%" + normalizedSearchText + "%");
            }
        }
        if (searchText.toLowerCase(Locale.ROOT).contains("sim")) {
            sql.append("OR (").append(deviceAlias).append(".ip_address = '127.0.0.1' AND ").append(deviceAlias).append(".modbus_port = 1502) ");
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

    private static boolean inRange(Timestamp value, Timestamp fromTs, Timestamp toTs) {
        if (value == null) return true;
        if (fromTs != null && value.before(fromTs)) return false;
        return toTs == null || !value.after(toTs);
    }

    private static boolean matchesSelected(Map<String, Object> device, String selectedId) {
        return selectedId == null || selectedId.trim().isEmpty() || selectedId.trim().equals(String.valueOf(device.get("ups_id")));
    }

    private static boolean matchesSearch(Map<String, Object> device, String searchText) {
        if (searchText == null || searchText.trim().isEmpty()) return true;
        String raw = searchText.trim();
        String normalized = normalize(raw);
        String name = String.valueOf(device.get("ups_name"));
        String ip = String.valueOf(device.get("ip_address"));
        String normalizedName = normalize(name);
        boolean simMatch = raw.toLowerCase(Locale.ROOT).contains("sim") && UpsSimulatorSupport.isSimulatorDevice(device);
        return name.contains(raw) || ip.contains(raw) || normalizedName.contains(normalized) || simMatch;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", "");
    }
}
