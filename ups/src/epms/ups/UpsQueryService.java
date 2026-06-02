package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsFormatSupport;
import epms.util.UpsSimulatorSupport;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Timestamp;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import javax.servlet.ServletContext;

public final class UpsQueryService {
    private UpsQueryService() {
    }

    public static List<Map<String, Object>> listDevicesBasic() throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT ups_id, ups_name, ip_address, modbus_port FROM dbo.ups_device ORDER BY ups_name");
             ResultSet rs = ps.executeQuery()) {
            return rows(rs);
        }
    }

    public static List<Map<String, Object>> listDevicesWithProfile() throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.enabled, " +
                 "d.last_comm_status, d.last_success_at, p.profile_name " +
                 "FROM dbo.ups_device d LEFT JOIN dbo.ups_modbus_profile p ON p.profile_id = d.profile_id ORDER BY d.ups_name");
             ResultSet rs = ps.executeQuery()) {
            return rows(rs);
        }
    }

    public static List<Map<String, Object>> measurementHistory(String selectedId, String searchText, Timestamp fromTs, Timestamp toTs, int limit) throws Exception {
        List<Map<String, Object>> devices = listDevicesBasic();
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

    public static List<Map<String, Object>> alarmRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        String normalizedSearchText = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 200 a.alarm_id, d.ups_name, a.severity, a.metric_key, a.alarm_message, a.occurred_at, a.cleared_at, a.status ")
           .append("FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ")
           .append("WHERE a.status <> 'EVENT' ");
        List<Object> params = new ArrayList<Object>();
        appendAlarmSearch(sql, params, searchText, normalizedSearchText);
        appendTimeRange(sql, params, fromTs, toTs);
        sql.append("ORDER BY a.occurred_at DESC");
        return query(sql.toString(), params);
    }

    public static List<Map<String, Object>> eventRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        String normalizedSearchText = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 200 a.alarm_id, d.ups_name, a.severity, a.alarm_message, a.occurred_at, a.status ")
           .append("FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ")
           .append("WHERE a.status = 'EVENT' ");
        List<Object> params = new ArrayList<Object>();
        appendEventSearch(sql, params, searchText, normalizedSearchText);
        appendTimeRange(sql, params, fromTs, toTs);
        sql.append("ORDER BY a.occurred_at DESC");
        return query(sql.toString(), params);
    }

    public static Map<String, Object> latestPhasorMeasurement(String selectedId) throws Exception {
        if (selectedId == null || selectedId.trim().isEmpty()) return new HashMap<String, Object>();
        List<Object> params = new ArrayList<Object>();
        params.add(Integer.valueOf(selectedId.trim()));
        List<Map<String, Object>> rows = query(
            "SELECT TOP 1 measured_at, output_voltage_l12, output_voltage_l23, output_voltage_l31, " +
            "output_current_l1, output_current_l2, output_current_l3, output_pf_l1, output_pf_l2, output_pf_l3 " +
            "FROM dbo.ups_measurement WHERE ups_id = ? ORDER BY measured_at DESC",
            params);
        return rows.isEmpty() ? new HashMap<String, Object>() : rows.get(0);
    }

    public static Map<String, Object> realtimeStatus(String selectedId, ServletContext app) throws Exception {
        Map<String, Object> view = new HashMap<String, Object>();
        List<Map<String, Object>> devices = listDevicesWithProfile();
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

    public static Map<String, Object> latestStatusMeasurement(String selectedId) throws Exception {
        if (selectedId == null || selectedId.trim().isEmpty()) return new HashMap<String, Object>();
        List<Object> params = new ArrayList<Object>();
        params.add(Integer.valueOf(selectedId.trim()));
        List<Map<String, Object>> rows = query(
            "SELECT TOP 1 * FROM dbo.ups_measurement WHERE ups_id = ? ORDER BY measured_at DESC",
            params);
        return rows.isEmpty() ? new HashMap<String, Object>() : rows.get(0);
    }

    public static void syncSimulatorScenarioEvent(ServletContext app) {
        if (app == null) return;
        String simStatus = UpsSimulatorSupport.readStatus(250);
        String current = UpsSimulatorSupport.jsonText(simStatus, "scenario", "");
        if (current.isEmpty()) return;
        synchronized (app) {
            Object oldValue = app.getAttribute("ups.simulator.scenario");
            app.setAttribute("ups.simulator.scenario", current);
            if (!(oldValue instanceof String)) {
                if (!"normal".equals(current)) insertScenarioEvent("", current);
                return;
            }
            String previous = (String) oldValue;
            if (!previous.equals(current)) insertScenarioEvent(previous, current);
        }
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
            target.put("remaining_minutes", new BigDecimal("45"));
            target.put("battery_current", new BigDecimal("-35"));
            target.put("battery_charge_percent", new BigDecimal("72"));
        } else if ("low_battery".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("7"));
            target.put("battery_current", new BigDecimal("-48"));
            target.put("battery_charge_percent", new BigDecimal("8"));
        } else if ("critical".equals(scenario)) {
            target.put("remaining_minutes", new BigDecimal("120"));
            target.put("battery_current", new BigDecimal("4"));
            target.put("battery_charge_percent", new BigDecimal("5"));
        } else {
            target.put("remaining_minutes", new BigDecimal("120"));
            target.put("battery_current", new BigDecimal("4"));
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
