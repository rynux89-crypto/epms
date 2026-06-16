package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsSimulatorSupport;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.servlet.ServletContext;

public final class UpsRealtimeService {
    private static final int COMM_FAIL_OFFLINE_THRESHOLD = 3;

    private UpsRealtimeService() {
    }

    public static Map<String, Object> realtimeStatus(String selectedId, ServletContext app) throws Exception {
        Map<String, Object> view = new HashMap<String, Object>();
        List<Map<String, Object>> devices = UpsDeviceLookupService.listActiveDevicesWithProfile();
        Map<String, Object> selected = null;
        if ((selectedId == null || selectedId.trim().isEmpty()) && !devices.isEmpty()) {
            selectedId = String.valueOf(devices.get(0).get("ups_id"));
        }
        if (selectedId != null && !selectedId.trim().isEmpty()) {
            for (Map<String, Object> device : devices) {
                if (selectedId.equals(String.valueOf(device.get("ups_id")))) {
                    selected = device;
                    break;
                }
            }
        }

        Map<String, Object> m = selectedId == null || selectedId.trim().isEmpty()
            ? new HashMap<String, Object>()
            : latestStatusMeasurement(selectedId);
        boolean hasMeasurement = m.get("measured_at") != null;
        boolean ok = isCommOk(selected);
        boolean uibClosed = bitOn(m.get("switchgear_status_code"), 0);
        boolean ssibClosed = bitOn(m.get("switchgear_status_code"), 1);
        boolean uobClosed = bitOn(m.get("switchgear_status_code"), 3);
        boolean bf2Closed = bitOn(m.get("switchgear_status_code"), 4);
        boolean mbbClosed = bitOn(m.get("switchgear_status_code"), 10);
        boolean bbClosed = intValue(m.get("battery_breaker_status_code"), 0) != 0;

        int upsModeCode = intValue(m.get("ups_operation_mode_code"), ok ? 2 : 0);
        int systemModeCode = intValue(m.get("system_operation_mode_code"), 2);

        if (UpsSimulatorSupport.isSimulatorDevice(selected)) {
            String simStatus = UpsSimulatorSupport.readStatus(250);
            if (simStatus != null && !simStatus.trim().isEmpty()) {
                hasMeasurement = true;
                ok = true;
                m.put("measured_at", new Timestamp(System.currentTimeMillis()));
            }
            String simScenario = UpsSimulatorSupport.jsonText(simStatus, "scenario", "");
            mergeSimulatorMeasurement(m, simStatus);
            putSimulatorDefaults(m, simScenario);
            upsModeCode = UpsSimulatorSupport.jsonInt(simStatus, "ups_operation_mode_code", upsModeCode);
            systemModeCode = UpsSimulatorSupport.jsonInt(simStatus, "system_operation_mode_code", systemModeCode);
            if ("normal".equals(simScenario)) upsModeCode = 2;
            if ("battery".equals(simScenario) || "low_battery".equals(simScenario)) upsModeCode = 4;
            uibClosed = UpsSimulatorSupport.jsonBool(simStatus, "uib", uibClosed);
            uobClosed = UpsSimulatorSupport.jsonBool(simStatus, "uob", uobClosed);
            ssibClosed = UpsSimulatorSupport.jsonBool(simStatus, "ssib", ssibClosed);
            bf2Closed = UpsSimulatorSupport.jsonBool(simStatus, "bf2", bf2Closed);
            mbbClosed = UpsSimulatorSupport.jsonBool(simStatus, "mbb", mbbClosed);
            bbClosed = UpsSimulatorSupport.jsonBool(simStatus, "bb", bbClosed);
            syncSimulatorBreakerEvents(app, selected, uibClosed, uobClosed, ssibClosed, bf2Closed, mbbClosed, bbClosed);
        }
        if (!ok) {
            hasMeasurement = false;
        }

        boolean inverterPath = hasMeasurement && uibClosed && uobClosed;
        boolean staticBypassPath = hasMeasurement && ssibClosed && bf2Closed;
        boolean maintenanceBypassPath = hasMeasurement && mbbClosed;
        boolean batteryPath = hasMeasurement && bbClosed;

        view.put("devices", devices);
        view.put("selectedId", selectedId);
        view.put("selected", selected);
        view.put("measurement", m);
        view.put("hasMeasurement", Boolean.valueOf(hasMeasurement));
        view.put("upsMode", modeText(Integer.valueOf(upsModeCode), ok ? "\uC815\uC0C1 \uC791\uB3D9" : "\uB300\uAE30"));
        view.put("systemMode", systemModeText(Integer.valueOf(systemModeCode), "\uC778\uBC84\uD130"));
        view.put("uibClosed", Boolean.valueOf(uibClosed));
        view.put("uobClosed", Boolean.valueOf(uobClosed));
        view.put("ssibClosed", Boolean.valueOf(ssibClosed));
        view.put("bf2Closed", Boolean.valueOf(bf2Closed));
        view.put("mbbClosed", Boolean.valueOf(mbbClosed));
        view.put("bbClosed", Boolean.valueOf(bbClosed));
        view.put("inverterPath", Boolean.valueOf(inverterPath));
        view.put("staticBypassPath", Boolean.valueOf(staticBypassPath));
        view.put("uibPathClass", pathClass(hasMeasurement && uibClosed));
        view.put("uobPathClass", pathClass(hasMeasurement && uobClosed));
        view.put("inverterPathClass", pathClass(inverterPath));
        view.put("ssibPathClass", pathClass(hasMeasurement && ssibClosed));
        view.put("bypassInputBranchClass", pathClass(hasMeasurement && (ssibClosed || mbbClosed)));
        view.put("staticBypassPathClass", pathClass(staticBypassPath));
        view.put("maintenanceBypassPathClass", pathClass(maintenanceBypassPath));
        view.put("batteryPathClass", pathClass(batteryPath));
        return view;
    }

    public static Map<String, Object> latestStatusMeasurement(String selectedId) throws Exception {
        return latestStatusMeasurementRow(selectedId).toMap();
    }

    public static UpsMeasurementRow latestStatusMeasurementRow(String selectedId) throws Exception {
        if (selectedId == null || selectedId.trim().isEmpty()) return UpsMeasurementRow.empty();
        List<Object> params = new ArrayList<Object>();
        params.add(Integer.valueOf(selectedId.trim()));
        return queryMeasurementRow(
            "SELECT TOP 1 * FROM dbo.ups_measurement WHERE ups_id = ? ORDER BY measured_at DESC",
            params);
    }

    public static Map<String, Object> latestPhasorMeasurement(String selectedId) throws Exception {
        return latestPhasorMeasurementRow(selectedId).toMap();
    }

    public static UpsMeasurementRow latestPhasorMeasurementRow(String selectedId) throws Exception {
        if (selectedId == null || selectedId.trim().isEmpty()) return UpsMeasurementRow.empty();
        List<Object> params = new ArrayList<Object>();
        params.add(Integer.valueOf(selectedId.trim()));
        return queryMeasurementRow(
            "SELECT TOP 1 measured_at, output_voltage_l12, output_voltage_l23, output_voltage_l31, " +
            "output_current_l1, output_current_l2, output_current_l3, output_pf_l1, output_pf_l2, output_pf_l3 " +
            "FROM dbo.ups_measurement WHERE ups_id = ? ORDER BY measured_at DESC",
            params);
    }

    private static String modeText(Object value, String fallback) {
        int code = intValue(value, -1);
        if (code == 2) return "\uC815\uC0C1 \uC791\uB3D9";
        if (code == 4) return "\uBC30\uD130\uB9AC \uC6B4\uC804";
        if (code == 16) return "\uC815\uC9C0";
        if (code == 1032) return "\uC694\uCCAD \uBC14\uC774\uD328\uC2A4";
        if (code == 40) return "\uAC15\uC81C \uBC14\uC774\uD328\uC2A4";
        if (code == 2056) return "\uC720\uC9C0\uBCF4\uC218 \uBC14\uC774\uD328\uC2A4";
        if (code == 8200) return "ECO \uBAA8\uB4DC";
        if (code == 65536) return "\uBC14\uC774\uD328\uC2A4 \uB300\uAE30";
        return fallback;
    }

    private static String systemModeText(Object value, String fallback) {
        int code = intValue(value, -1);
        if ((code & (1 << 1)) != 0) return "\uC778\uBC84\uD130";
        if ((code & (1 << 2)) != 0) return "\uC694\uCCAD \uBC14\uC774\uD328\uC2A4";
        if ((code & (1 << 3)) != 0) return "\uAC15\uC81C \uBC14\uC774\uD328\uC2A4";
        if ((code & (1 << 4)) != 0) return "\uC815\uC9C0";
        if ((code & (1 << 6)) != 0) return "\uC720\uC9C0\uBCF4\uC218 \uBC14\uC774\uD328\uC2A4";
        if ((code & (1 << 7)) != 0) return "ECO";
        if ((code & (1 << 9)) != 0) return "\uBC14\uC774\uD328\uC2A4 \uB300\uAE30";
        return fallback;
    }

    private static void mergeSimulatorMeasurement(Map<String, Object> target, String simStatus) {
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_voltage_l12", "output_voltage_l12");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_voltage_l23", "output_voltage_l23");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_voltage_l31", "output_voltage_l31");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_current_l1", "output_current_l1");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_current_l2", "output_current_l2");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_current_l3", "output_current_l3");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_frequency_hz", "frequency");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_load_percent", "load_percent");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_power_kw", "output_power_kw");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_power_l1_kw", "output_power_l1_kw");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_power_l2_kw", "output_power_l2_kw");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_power_l3_kw", "output_power_l3_kw");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_apparent_total_kva", "output_apparent_total_kva");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_apparent_l1_kva", "output_apparent_l1_kva");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_apparent_l2_kva", "output_apparent_l2_kva");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_apparent_l3_kva", "output_apparent_l3_kva");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_pf_l1", "output_pf_l1");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_pf_l2", "output_pf_l2");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "output_pf_l3", "output_pf_l3");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "battery_voltage", "battery_voltage");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "battery_current", "battery_current");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "battery_charge_percent", "battery_charge_percent");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "battery_temperature_c", "battery_temperature");
        UpsSimulatorSupport.putJsonDecimal(target, simStatus, "remaining_minutes", "remaining_minutes");
    }

    private static void putSimulatorDefaults(Map<String, Object> target, String scenario) {
        putIfMissing(target, "output_power_kw", "40");
        putIfMissing(target, "output_power_l1_kw", "13");
        putIfMissing(target, "output_power_l2_kw", "13");
        putIfMissing(target, "output_power_l3_kw", "14");
        putIfMissing(target, "output_apparent_total_kva", "43");
        putIfMissing(target, "output_apparent_l1_kva", "14");
        putIfMissing(target, "output_apparent_l2_kva", "14");
        putIfMissing(target, "output_apparent_l3_kva", "15");
        putIfMissing(target, "output_pf_l1", "0.96");
        putIfMissing(target, "output_pf_l2", "0.95");
        putIfMissing(target, "output_pf_l3", "0.97");
        putIfMissing(target, "battery_voltage", "540");
        putIfMissing(target, "battery_temperature", "28.5");
        if ("battery".equals(scenario)) {
            putIfMissing(target, "remaining_minutes", "45");
            putIfMissing(target, "battery_current", "-35");
            putIfMissing(target, "battery_charge_percent", "72");
        } else if ("low_battery".equals(scenario)) {
            putIfMissing(target, "remaining_minutes", "7");
            putIfMissing(target, "battery_current", "-48");
            putIfMissing(target, "battery_charge_percent", "8");
        } else if ("critical".equals(scenario)) {
            putIfMissing(target, "remaining_minutes", "120");
            putIfMissing(target, "battery_current", "4");
            putIfMissing(target, "battery_charge_percent", "5");
        } else {
            putIfMissing(target, "remaining_minutes", "120");
            putIfMissing(target, "battery_current", "4");
            if (target.get("battery_charge_percent") == null) target.put("battery_charge_percent", new BigDecimal("96"));
        }
    }

    private static void putIfMissing(Map<String, Object> target, String key, String value) {
        if (target.get(key) == null && value != null) {
            target.put(key, new BigDecimal(value));
        }
    }

    private static void syncSimulatorBreakerEvents(ServletContext app, Map<String, Object> selected,
            boolean uib, boolean uob, boolean ssib, boolean bf2, boolean mbb, boolean bb) {
        if (app == null || selected == null) return;
        String upsId = String.valueOf(selected.get("ups_id"));
        String attrKey = "ups.simulator.breakers." + upsId;
        String current = breakerSnapshot(uib, uob, ssib, bf2, mbb, bb);
        synchronized (app) {
            Object oldValue = app.getAttribute(attrKey);
            app.setAttribute(attrKey, current);
            if (!(oldValue instanceof String)) return;
            String previous = (String) oldValue;
            if (previous.length() != current.length() || previous.equals(current)) return;
            insertBreakerEvent(selected, "UIB", previous.charAt(0) == '1', current.charAt(0) == '1');
            insertBreakerEvent(selected, "UOB", previous.charAt(1) == '1', current.charAt(1) == '1');
            insertBreakerEvent(selected, "SSIB", previous.charAt(2) == '1', current.charAt(2) == '1');
            insertBreakerEvent(selected, "BF2", previous.charAt(3) == '1', current.charAt(3) == '1');
            insertBreakerEvent(selected, "MBB", previous.charAt(4) == '1', current.charAt(4) == '1');
            insertBreakerEvent(selected, "BB", previous.charAt(5) == '1', current.charAt(5) == '1');
        }
    }

    private static String breakerSnapshot(boolean uib, boolean uob, boolean ssib, boolean bf2, boolean mbb, boolean bb) {
        return (uib ? "1" : "0") + (uob ? "1" : "0") + (ssib ? "1" : "0") + (bf2 ? "1" : "0") + (mbb ? "1" : "0") + (bb ? "1" : "0");
    }

    private static void insertBreakerEvent(Map<String, Object> selected, String name, boolean before, boolean after) {
        if (before == after || selected == null) return;
        String metricKey = "BB".equals(name) ? "battery_breaker_status" : "switchgear_status";
        String ruleCode = "BREAKER_" + name + "_CHANGE";
        String message = name + " " + (before ? "Close" : "Open") + " -> " + (after ? "Close" : "Open");
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            int upsId = Integer.parseInt(String.valueOf(selected.get("ups_id")));
            if (recentEventExists(conn, upsId, ruleCode, message, 3)) return;
            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
                    "VALUES (?, ?, ?, 'INFO', ?, sysdatetime(), 'EVENT')")) {
                ps.setInt(1, upsId);
                ps.setString(2, ruleCode);
                ps.setString(3, metricKey);
                ps.setString(4, message);
                ps.executeUpdate();
            }
        } catch (Exception ignore) {
        }
    }

    private static boolean recentEventExists(Connection conn, int upsId, String ruleCode, String message, int seconds) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 1 FROM dbo.ups_alarm_log WHERE ups_id=? AND rule_code=? AND alarm_message=? AND status='EVENT' " +
                "AND occurred_at >= DATEADD(second, -" + seconds + ", sysdatetime())")) {
            ps.setInt(1, upsId);
            ps.setString(2, ruleCode);
            ps.setString(3, message);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    private static boolean isCommOk(Map<String, Object> selected) {
        if (selected == null) return false;
        int failCount = intValue(selected.get("consecutive_fail_count"), 0);
        if (failCount > 0 && failCount < COMM_FAIL_OFFLINE_THRESHOLD) return true;
        String comm = String.valueOf(selected.get("last_comm_status"));
        return "OK".equalsIgnoreCase(comm) || "NORMAL".equalsIgnoreCase(comm) || "ONLINE".equalsIgnoreCase(comm);
    }

    private static boolean bitOn(Object value, int bit) {
        return (intValue(value, 0) & (1 << bit)) != 0;
    }

    private static int intValue(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            return value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value).trim());
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private static String pathClass(boolean active) {
        return active ? "mimic-active" : "mimic-idle";
    }

    private static UpsMeasurementRow queryMeasurementRow(String sql, List<Object> params) throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            bind(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? UpsMeasurementRow.from(rs) : UpsMeasurementRow.empty();
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

}
