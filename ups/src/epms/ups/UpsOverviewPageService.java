package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsFormatSupport;
import epms.util.UpsSimulatorSupport;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Timestamp;
import java.util.HashMap;
import java.util.Map;

public final class UpsOverviewPageService {
    private UpsOverviewPageService() {
    }

    public static UpsOverviewPageModel build(boolean includeInactive) {
        UpsOverviewPageModel model = new UpsOverviewPageModel();
        model.includeInactive = includeInactive;
        try {
            for (Map<String, Object> row : loadRows(includeInactive)) {
                applySimulatorStatus(row);
                UpsOverviewItem item = toItem(row);
                model.items.add(item);
                if ("normal".equals(item.statusClass)) model.normalCount++;
                else if ("alarm".equals(item.statusClass)) model.alarmCount++;
                else if ("comm".equals(item.statusClass)) model.commCount++;
                else if ("disabled".equals(item.statusClass)) model.disabledCount++;
                else model.unknownCount++;
            }
        } catch (Exception e) {
            model.err = e.getMessage();
        }
        return model;
    }

    private static java.util.List<Map<String, Object>> loadRows(boolean includeInactive) throws Exception {
        java.util.List<Map<String, Object>> out = new java.util.ArrayList<Map<String, Object>>();
        String sql =
            "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.enabled, d.last_comm_status, " +
            "COALESCE(cs.consecutive_fail_count, 0) AS consecutive_fail_count, " +
            "m.measured_at, m.load_percent, m.output_voltage, m.output_power_kw, m.output_apparent_total_kva, m.frequency, " +
            "m.battery_charge_percent, m.battery_temperature, m.remaining_minutes, m.ups_operation_mode_code, " +
            "ISNULL(a.active_alarm_count, 0) AS active_alarm_count " +
            "FROM dbo.ups_device d " +
            "LEFT JOIN dbo.ups_comm_status cs ON cs.ups_id = d.ups_id " +
            "OUTER APPLY (SELECT TOP 1 * FROM dbo.ups_measurement m WHERE m.ups_id = d.ups_id ORDER BY m.measured_at DESC) m " +
            "OUTER APPLY (SELECT COUNT(*) AS active_alarm_count FROM dbo.ups_alarm_log a WHERE a.ups_id = d.ups_id AND a.status = 'ACTIVE') a " +
            (includeInactive ? "" : "WHERE d.enabled = 1 ") +
            "ORDER BY d.ups_name";
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            ResultSetMetaData md = rs.getMetaData();
            while (rs.next()) {
                Map<String, Object> row = new HashMap<String, Object>();
                for (int i = 1; i <= md.getColumnCount(); i++) row.put(md.getColumnLabel(i), rs.getObject(i));
                out.add(row);
            }
        }
        return out;
    }

    private static UpsOverviewItem toItem(Map<String, Object> row) {
        UpsOverviewItem item = new UpsOverviewItem();
        item.upsId = str(row.get("ups_id"));
        item.upsName = str(row.get("ups_name"));
        item.location = str(row.get("location"));
        item.ipAddress = str(row.get("ip_address"));
        item.modbusPort = str(row.get("modbus_port"));
        item.unitId = str(row.get("unit_id"));
        item.statusClass = statusClass(row);
        item.statusText = statusText(item.statusClass);
        item.measuredAtText = overviewDate(row, item.statusClass);
        item.loadText = overviewValue(row, item.statusClass, "load_percent", 1, "");
        item.batteryText = overviewValue(row, item.statusClass, "battery_charge_percent", 0, "");
        item.outputVoltageText = overviewValue(row, item.statusClass, "output_voltage", 0, "");
        item.outputKwText = overviewValue(row, item.statusClass, "output_power_kw", 0, "");
        item.outputKvaText = overviewValue(row, item.statusClass, "output_apparent_total_kva", 0, "");
        item.frequencyText = overviewValue(row, item.statusClass, "frequency", 1, "");
        item.operationModeText = overviewMode(row, item.statusClass);
        item.batteryTempText = overviewValue(row, item.statusClass, "battery_temperature", 1, "");
        item.remainingText = overviewValue(row, item.statusClass, "remaining_minutes", 0, "");
        item.activeAlarmCount = intValue(row.get("active_alarm_count"));
        return item;
    }

    private static String statusClass(Map<String, Object> row) {
        if (!isEnabled(row.get("enabled"))) return "disabled";
        if (isCommBad(row)) return "comm";
        if (row.get("measured_at") == null) return "unknown";
        if (intValue(row.get("active_alarm_count")) > 0) return "alarm";
        return "normal";
    }

    private static String statusText(String cls) {
        if ("normal".equals(cls)) return "\uC815\uC0C1";
        if ("alarm".equals(cls)) return "\uC54C\uB78C";
        if ("comm".equals(cls)) return "\uD1B5\uC2E0\uBD88\uB7C9";
        if ("disabled".equals(cls)) return "\uBE44\uD65C\uC131";
        return "\uBBF8\uC218\uC9D1";
    }

    private static boolean isCommBad(Map<String, Object> row) {
        Object raw = row.get("last_comm_status");
        if (raw == null) return false;
        int failCount = intValue(row.get("consecutive_fail_count"));
        if (failCount > 0 && failCount < 3) return false;
        String comm = String.valueOf(raw).trim();
        return comm.length() > 0 && !"OK".equalsIgnoreCase(comm);
    }

    private static boolean isEnabled(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return ((Boolean)value).booleanValue();
        if (value instanceof Number) return ((Number)value).intValue() != 0;
        String text = String.valueOf(value).trim();
        return "1".equals(text) || "true".equalsIgnoreCase(text) || "Y".equalsIgnoreCase(text);
    }

    private static String overviewValue(Map<String, Object> row, String cls, String key, int scale, String unit) {
        if ("comm".equals(cls)) return "-";
        String value = UpsFormatSupport.fmtDash(row.get(key), scale);
        return unit == null || unit.length() == 0 ? value : value + unit;
    }

    private static String overviewDate(Map<String, Object> row, String cls) {
        if ("comm".equals(cls)) return "-";
        Object value = row.get("measured_at");
        if (value == null) return "\uBBF8\uC218\uC9D1";
        return UpsFormatSupport.displaySlashDateTime(value);
    }

    private static String overviewMode(Map<String, Object> row, String cls) {
        if ("comm".equals(cls) || row.get("measured_at") == null) return "-";
        String label = UpsFormatSupport.upsModeLabel(row.get("ups_operation_mode_code"));
        return label == null || label.length() == 0 ? "-" : label;
    }

    private static void applySimulatorStatus(Map<String, Object> row) {
        if (!"127.0.0.1".equals(String.valueOf(row.get("ip_address"))) ||
            !"1502".equals(String.valueOf(row.get("modbus_port")))) {
            return;
        }
        String simStatus = UpsSimulatorSupport.readStatus(250);
        if (simStatus == null || simStatus.trim().isEmpty()) return;

        String scenario = UpsSimulatorSupport.jsonText(simStatus, "scenario", "normal");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_load_percent", "load_percent");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_voltage_l12", "output_voltage");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_power_kw", "output_power_kw");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_apparent_total_kva", "output_apparent_total_kva");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "output_frequency_hz", "frequency");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "battery_charge_percent", "battery_charge_percent");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "battery_temperature_c", "battery_temperature");
        UpsSimulatorSupport.putJsonDecimal(row, simStatus, "remaining_minutes", "remaining_minutes");
        applySimulatorDefaults(row, scenario);
        row.put("measured_at", new Timestamp(System.currentTimeMillis()));
        row.put("last_comm_status", "OK");
        if ("normal".equals(scenario) || "bypass".equals(scenario)
                || "maintenance_bypass".equals(scenario)
                || "battery_test".equals(scenario)
                || "battery_charging".equals(scenario)) {
            row.put("active_alarm_count", Integer.valueOf(0));
        } else if (intValue(row.get("active_alarm_count")) == 0) {
            row.put("active_alarm_count", Integer.valueOf(1));
        }
    }

    private static void applySimulatorDefaults(Map<String, Object> target, String scenario) {
        putIfMissing(target, "load_percent", "42");
        putIfMissing(target, "output_voltage", "380");
        putIfMissing(target, "output_power_kw", "40");
        putIfMissing(target, "output_apparent_total_kva", "43");
        putIfMissing(target, "frequency", "60.0");
        putIfMissing(target, "battery_temperature", "28.5");
        if ("battery".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("45"));
            target.put("battery_charge_percent", new BigDecimal("72"));
        } else if ("battery_charging".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("120"));
            target.put("battery_charge_percent", new BigDecimal("88"));
        } else if ("battery_test".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("90"));
            target.put("battery_charge_percent", new BigDecimal("88"));
        } else if ("low_battery".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("7"));
            target.put("battery_charge_percent", new BigDecimal("8"));
        } else if ("bypass".equals(scenario) || "maintenance_bypass".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("120"));
            if (target.get("battery_charge_percent") == null) target.put("battery_charge_percent", new BigDecimal("96"));
        } else if ("output_off".equals(scenario) || "epo".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("120"));
            target.put("load_percent", BigDecimal.ZERO);
            target.put("output_voltage", BigDecimal.ZERO);
            target.put("output_power_kw", BigDecimal.ZERO);
            target.put("output_apparent_total_kva", BigDecimal.ZERO);
            if (target.get("battery_charge_percent") == null) target.put("battery_charge_percent", new BigDecimal("96"));
        } else if ("critical".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("120"));
            target.put("battery_charge_percent", new BigDecimal("5"));
        } else {
            target.put("remaining_minutes", new BigDecimal("120"));
            if (target.get("battery_charge_percent") == null) target.put("battery_charge_percent", new BigDecimal("96"));
        }
    }

    private static void putIfMissing(Map<String, Object> target, String key, String value) {
        if (target.get(key) == null && value != null) target.put(key, new BigDecimal(value));
    }

    private static int intValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Number) return ((Number)value).intValue();
        try { return Integer.parseInt(String.valueOf(value)); } catch (Exception ignore) { return 0; }
    }

    private static String str(Object value) {
        return value == null ? "" : String.valueOf(value);
    }
}
