<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String fmt(Object value, int scale) {
        if (value == null) return "---";
        try {
            double v = value instanceof Number ? ((Number)value).doubleValue() : Double.parseDouble(String.valueOf(value));
            return String.format(java.util.Locale.US, "%,." + scale + "f", v);
        } catch (Exception ignore) {
            return String.valueOf(value);
        }
    }

    private String fmtUnit(Object value, int scale, String unit) {
        return value == null ? "--- " + unit : fmt(value, scale) + " " + unit;
    }

    private String fmtDate(Object value) {
        return value == null ? "----/--/-- --:--:--" : String.valueOf(value).replace('-', '/');
    }

    private String nowText() {
        return new java.text.SimpleDateFormat("yyyy/MM/dd HH:mm:ss").format(new java.util.Date());
    }

    private String modeText(Object value, String fallback) {
        if (value == null) return fallback;
        int code;
        try {
            code = value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value));
        } catch (Exception ignore) {
            return fallback;
        }
        if (code == 0x02 || code == 2) return "정상 작동";
        if (code == 0x04 || code == 4) return "배터리 운전";
        if (code == 0x10 || code == 16) return "정지";
        if (code == 0x408 || code == 1032) return "요청 바이패스";
        if (code == 0x28 || code == 40) return "강제 바이패스";
        if (code == 0x808 || code == 2056) return "유지보수 바이패스";
        if (code == 0x2008 || code == 8200) return "ECO 모드";
        if (code == 0x10000 || code == 65536) return "바이패스 대기";
        return fallback;
    }

    private String systemModeText(Object value, String fallback) {
        if (value == null) return fallback;
        int code;
        try {
            code = value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value));
        } catch (Exception ignore) {
            return fallback;
        }
        if ((code & (1 << 1)) != 0) return "인버터";
        if ((code & (1 << 2)) != 0) return "요청 바이패스";
        if ((code & (1 << 3)) != 0) return "강제 바이패스";
        if ((code & (1 << 4)) != 0) return "정지";
        if ((code & (1 << 6)) != 0) return "유지보수 바이패스";
        if ((code & (1 << 7)) != 0) return "ECO";
        if ((code & (1 << 9)) != 0) return "바이패스 대기";
        return fallback;
    }

    private int intValue(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            return value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value));
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private boolean bitOn(Object value, int bit) {
        return (intValue(value, 0) & (1 << bit)) != 0;
    }

    private String readUrl(String urlText, int timeoutMs) {
        java.net.HttpURLConnection conn = null;
        try {
            java.net.URL url = new java.net.URL(urlText);
            conn = (java.net.HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setRequestMethod("GET");
            try (java.io.BufferedReader br = new java.io.BufferedReader(new java.io.InputStreamReader(conn.getInputStream(), "UTF-8"))) {
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) sb.append(line);
                return sb.toString();
            }
        } catch (Exception ignore) {
            return null;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private boolean jsonBool(String json, String key, boolean fallback) {
        if (json == null) return fallback;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(key) + "\"\\s*:\\s*(true|false)");
            java.util.regex.Matcher m = p.matcher(json);
            return m.find() ? Boolean.parseBoolean(m.group(1)) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private int jsonInt(String json, String key, int fallback) {
        if (json == null) return fallback;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+)");
            java.util.regex.Matcher m = p.matcher(json);
            return m.find() ? Integer.parseInt(m.group(1)) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private java.math.BigDecimal jsonDecimal(String json, String key, java.math.BigDecimal fallback) {
        if (json == null) return fallback;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)");
            java.util.regex.Matcher m = p.matcher(json);
            return m.find() ? new java.math.BigDecimal(m.group(1)) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private void putJsonDecimal(Map<String, Object> target, String json, String jsonKey, String metricKey) {
        java.math.BigDecimal value = jsonDecimal(json, jsonKey, null);
        if (value != null) target.put(metricKey, value);
    }

    private void putIfMissing(Map<String, Object> target, String metricKey, String value) {
        if (target.get(metricKey) == null && value != null) {
            target.put(metricKey, new java.math.BigDecimal(value));
        }
    }

    private void putSimulatorDefaults(Map<String, Object> target, String scenario) {
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
            target.put("remaining_minutes", new java.math.BigDecimal("45"));
            target.put("battery_current", new java.math.BigDecimal("-35"));
            target.put("battery_charge_percent", new java.math.BigDecimal("72"));
        } else if ("low_battery".equals(scenario)) {
            target.put("remaining_minutes", new java.math.BigDecimal("7"));
            target.put("battery_current", new java.math.BigDecimal("-48"));
            target.put("battery_charge_percent", new java.math.BigDecimal("8"));
        } else if ("critical".equals(scenario)) {
            target.put("remaining_minutes", new java.math.BigDecimal("120"));
            target.put("battery_current", new java.math.BigDecimal("4"));
            target.put("battery_charge_percent", new java.math.BigDecimal("5"));
        } else {
            target.put("remaining_minutes", new java.math.BigDecimal("120"));
            target.put("battery_current", new java.math.BigDecimal("4"));
            if (target.get("battery_charge_percent") == null) target.put("battery_charge_percent", new java.math.BigDecimal("96"));
        }
    }

    private String jsonText(String json, String key, String fallback) {
        if (json == null) return fallback;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"");
            java.util.regex.Matcher m = p.matcher(json);
            return m.find() ? m.group(1) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String err = null;
String selectedId = request.getParameter("ups_id");
List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
Map<String, Object> selected = null;
Map<String, Object> m = new HashMap<String, Object>();

try (Connection conn = openUpsDbConnection()) {
    try (PreparedStatement ps = conn.prepareStatement(
        "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.enabled, d.last_comm_status, d.last_success_at, p.profile_name " +
        "FROM dbo.ups_device d LEFT JOIN dbo.ups_modbus_profile p ON p.profile_id = d.profile_id ORDER BY d.ups_name")) {
        try (ResultSet rs = ps.executeQuery()) {
            ResultSetMetaData md = rs.getMetaData();
            while (rs.next()) {
                Map<String, Object> row = new HashMap<String, Object>();
                for (int i = 1; i <= md.getColumnCount(); i++) row.put(md.getColumnLabel(i), rs.getObject(i));
                devices.add(row);
            }
        }
    }

    if ((selectedId == null || selectedId.trim().isEmpty()) && !devices.isEmpty()) {
        selectedId = String.valueOf(devices.get(0).get("ups_id"));
    }
    if (selectedId != null && !selectedId.trim().isEmpty()) {
        for (Map<String, Object> d : devices) {
            if (selectedId.equals(String.valueOf(d.get("ups_id")))) {
                selected = d;
                break;
            }
        }
        try (PreparedStatement ps = conn.prepareStatement(
            "SELECT TOP 1 * FROM dbo.ups_measurement WHERE ups_id = ? ORDER BY measured_at DESC")) {
            ps.setInt(1, Integer.parseInt(selectedId));
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData md = rs.getMetaData();
                if (rs.next()) {
                    for (int i = 1; i <= md.getColumnCount(); i++) m.put(md.getColumnLabel(i), rs.getObject(i));
                }
            }
        }
    }
} catch (Exception e) {
    err = e.getMessage();
}

String comm = selected == null ? "UNKNOWN" : String.valueOf(selected.get("last_comm_status"));
boolean ok = "OK".equalsIgnoreCase(comm) || "NORMAL".equalsIgnoreCase(comm) || "ONLINE".equalsIgnoreCase(comm);
String upsMode = modeText(m.get("ups_operation_mode_code"), ok ? "정상 작동" : "대기");
String systemMode = systemModeText(m.get("system_operation_mode_code"), "인버터");
Object totalLoad = m.get("load_percent");
Object totalKw = m.get("output_power_kw");
Object totalKva = m.get("output_apparent_total_kva");
boolean hasMeasurement = m.get("measured_at") != null;
boolean uibClosed = bitOn(m.get("switchgear_status_code"), 0);
boolean ssibClosed = bitOn(m.get("switchgear_status_code"), 1);
boolean uobClosed = bitOn(m.get("switchgear_status_code"), 3);
boolean bf2Closed = bitOn(m.get("switchgear_status_code"), 4);
boolean mbbClosed = bitOn(m.get("switchgear_status_code"), 10);
boolean bbClosed = intValue(m.get("battery_breaker_status_code"), 0) != 0;
boolean simulatorDevice = selected != null
        && "127.0.0.1".equals(String.valueOf(selected.get("ip_address")))
        && "1502".equals(String.valueOf(selected.get("modbus_port")));
if (simulatorDevice) {
    String simStatus = readUrl("http://127.0.0.1:1503/api/status", 250);
    String simScenario = jsonText(simStatus, "scenario", "");
    putJsonDecimal(m, simStatus, "output_voltage_l12", "output_voltage_l12");
    putJsonDecimal(m, simStatus, "output_voltage_l23", "output_voltage_l23");
    putJsonDecimal(m, simStatus, "output_voltage_l31", "output_voltage_l31");
    putJsonDecimal(m, simStatus, "output_current_l1", "output_current_l1");
    putJsonDecimal(m, simStatus, "output_current_l2", "output_current_l2");
    putJsonDecimal(m, simStatus, "output_current_l3", "output_current_l3");
    putJsonDecimal(m, simStatus, "output_frequency_hz", "frequency");
    putJsonDecimal(m, simStatus, "output_load_percent", "load_percent");
    putJsonDecimal(m, simStatus, "output_power_kw", "output_power_kw");
    putJsonDecimal(m, simStatus, "output_power_l1_kw", "output_power_l1_kw");
    putJsonDecimal(m, simStatus, "output_power_l2_kw", "output_power_l2_kw");
    putJsonDecimal(m, simStatus, "output_power_l3_kw", "output_power_l3_kw");
    putJsonDecimal(m, simStatus, "output_apparent_total_kva", "output_apparent_total_kva");
    putJsonDecimal(m, simStatus, "output_apparent_l1_kva", "output_apparent_l1_kva");
    putJsonDecimal(m, simStatus, "output_apparent_l2_kva", "output_apparent_l2_kva");
    putJsonDecimal(m, simStatus, "output_apparent_l3_kva", "output_apparent_l3_kva");
    putJsonDecimal(m, simStatus, "output_pf_l1", "output_pf_l1");
    putJsonDecimal(m, simStatus, "output_pf_l2", "output_pf_l2");
    putJsonDecimal(m, simStatus, "output_pf_l3", "output_pf_l3");
    putJsonDecimal(m, simStatus, "battery_voltage", "battery_voltage");
    putJsonDecimal(m, simStatus, "battery_current", "battery_current");
    putJsonDecimal(m, simStatus, "battery_charge_percent", "battery_charge_percent");
    putJsonDecimal(m, simStatus, "battery_temperature_c", "battery_temperature");
    putJsonDecimal(m, simStatus, "remaining_minutes", "remaining_minutes");
    putSimulatorDefaults(m, simScenario);
    int simUpsMode = jsonInt(simStatus, "ups_operation_mode_code", intValue(m.get("ups_operation_mode_code"), ok ? 2 : 0));
    int simSystemMode = jsonInt(simStatus, "system_operation_mode_code", intValue(m.get("system_operation_mode_code"), 2));
    if ("normal".equals(simScenario)) simUpsMode = 2;
    if ("battery".equals(simScenario) || "low_battery".equals(simScenario)) simUpsMode = 4;
    upsMode = modeText(Integer.valueOf(simUpsMode), ok ? "정상 작동" : "대기");
    systemMode = systemModeText(Integer.valueOf(simSystemMode), "인버터");
    uibClosed = jsonBool(simStatus, "uib", uibClosed);
    uobClosed = jsonBool(simStatus, "uob", uobClosed);
    ssibClosed = jsonBool(simStatus, "ssib", ssibClosed);
    bf2Closed = jsonBool(simStatus, "bf2", bf2Closed);
    mbbClosed = jsonBool(simStatus, "mbb", mbbClosed);
    bbClosed = jsonBool(simStatus, "bb", bbClosed);
}
totalLoad = m.get("load_percent");
totalKw = m.get("output_power_kw");
totalKva = m.get("output_apparent_total_kva");
boolean inverterPath = hasMeasurement && uibClosed && uobClosed;
boolean staticBypassPath = hasMeasurement && ssibClosed && bf2Closed;
boolean maintenanceBypassPath = hasMeasurement && mbbClosed;
boolean bypassPath = staticBypassPath || maintenanceBypassPath;
boolean batteryPath = hasMeasurement && bbClosed;
String uibPathClass = (hasMeasurement && uibClosed) ? "mimic-active" : "mimic-idle";
String uobPathClass = (hasMeasurement && uobClosed) ? "mimic-active" : "mimic-idle";
String inverterPathClass = inverterPath ? "mimic-active" : "mimic-idle";
String ssibPathClass = (hasMeasurement && ssibClosed) ? "mimic-active" : "mimic-idle";
String staticBypassPathClass = staticBypassPath ? "mimic-active" : "mimic-idle";
String maintenanceBypassPathClass = maintenanceBypassPath ? "mimic-active" : "mimic-idle";
String batteryPathClass = batteryPath ? "mimic-active" : "mimic-idle";
%>
<!doctype html>
<html>
<head>
    <title>UPS 모니터링</title>
    <meta http-equiv="refresh" content="5">
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body { background:#f2f4f7; }
        .ups-shell { max-width:1180px; margin:0 auto; }
        .page-wrap.ups-shell { padding-top:10px; padding-bottom:10px; }
        .ups-shell .title-bar { margin-bottom:8px; }
        .ups-shell .title-bar h2 { margin:0 0 2px; font-size:22px; }
        .ups-shell .title-bar p { margin:0; }
        .hmi-scale { zoom:.68; }
        .hmi-toolbar { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:8px; }
        .hmi-toolbar select { min-width:260px; padding:8px 10px; border:1px solid #9aa3ad; border-radius:6px; background:#fff; }
        .hmi {
            border:3px solid #555;
            background:#f7f7f7;
            padding:8px 12px 12px;
            color:#111;
            font-family:"Segoe UI", "Noto Sans KR", Arial, sans-serif;
            display:grid;
            grid-template-columns:minmax(0, 3fr) minmax(360px, 1.42fr);
            gap:8px;
            align-items:stretch;
        }
        .mimic-panel { grid-column:2; grid-row:1; border:2px solid #666; background:#fff; padding:4px 8px 6px; display:flex; align-items:center; min-height:100%; }
        .mimic-wrap { width:100%; }
        .mimic-svg { display:block; width:100%; height:auto; }
        .mimic-line { fill:none; stroke-width:4; stroke-linecap:square; stroke-linejoin:miter; }
        .mimic-active { stroke:#169b45; }
        .mimic-idle { stroke:#9b9b9b; }
        .mimic-text { font-size:24px; font-weight:800; fill:#111; font-family:"Segoe UI","Noto Sans KR",Arial,sans-serif; }
        .mimic-small { font-size:18px; font-weight:800; fill:#222; }
        .mimic-device { fill:#f8f8f8; stroke:#9b9b9b; stroke-width:3; }
        .mimic-device.active { stroke:#169b45; }
        .mimic-switch { stroke-width:4; stroke-linecap:round; }
        .mimic-dot { fill:#9b9b9b; }
        .mimic-dot.active { fill:#169b45; }
        .mimic-mode-box { fill:#fff; stroke:#666; stroke-width:2; }
        .mimic-mode-fill { fill:#5fc878; }
        .hmi-grid {
            display:grid;
            grid-template-columns:1.05fr 1.15fr 1.05fr;
            gap:8px;
            align-content:stretch;
            grid-column:1;
            grid-row:1;
        }
        .hmi-panel {
            border:2px solid #666;
            background:#fff;
            min-height:92px;
            padding:7px 13px;
        }
        .hmi-panel h3 { margin:0 0 6px; text-align:center; font-size:27px; font-weight:800; color:#111; line-height:1.05; }
        .metric-row { display:grid; grid-template-columns:70px 22px 1fr; gap:8px; align-items:center; font-size:25px; line-height:1.16; }
        .metric-row .val { text-align:right; font-weight:700; }
        .battery-panel { display:grid; grid-template-columns:1fr 120px 1fr; align-items:center; gap:10px; }
        .battery-time { font-size:25px; line-height:1.16; }
        .battery-percent { font-size:27px; font-weight:800; text-align:center; }
        .battery-shape { height:54px; border:7px solid #111; position:relative; background:linear-gradient(90deg,#5fc878 var(--charge,0%),#fff var(--charge,0%)); }
        .battery-shape::before { content:""; position:absolute; left:18px; top:-16px; width:32px; height:14px; border:7px solid #111; border-bottom:none; background:#fff; }
        .battery-shape::after { content:""; position:absolute; right:18px; top:-16px; width:32px; height:14px; border:7px solid #111; border-bottom:none; background:#fff; }
        .date-panel { min-height:58px; display:flex; align-items:center; justify-content:center; font-size:25px; font-weight:700; }
        .mode-panel { min-height:78px; padding:0; overflow:hidden; }
        .mode-panel h3 { padding:6px 12px 3px; margin:0; }
        .mode-value { background:#5fc878; text-align:center; font-size:27px; font-weight:800; padding:3px 8px 6px; }
        .total-panel .bar { height:36px; background:#5fc878; margin:6px 0; display:flex; align-items:center; justify-content:center; font-size:25px; font-weight:900; }
        .total-panel .total-values { text-align:center; font-size:25px; font-weight:800; }
        .phase-power { grid-row:span 4; }
        .phase-list { display:grid; gap:11px; padding-top:7px; }
        .phase-item { display:grid; grid-template-columns:64px 1fr; align-items:center; font-size:26px; }
        .phase-item .phase { font-weight:900; }
        .phase-item .nums { text-align:right; line-height:1.2; font-weight:700; }
        .span-left { grid-column:1; }
        .span-mid { grid-column:2; }
        .span-right { grid-column:3; }
        .muted-note { margin-top:6px; color:#64748b; font-size:12px; }
        @media (max-width: 940px) {
            .hmi { display:block; }
            .mimic-panel { margin-top:8px; }
            .hmi-grid { grid-template-columns:1fr; }
            .span-left,.span-mid,.span-right,.phase-power { grid-column:auto; grid-row:auto; }
            .hmi-panel h3 { font-size:24px; }
            .metric-row,.battery-time,.battery-percent,.date-panel,.mode-value,.total-panel .bar,.total-panel .total-values,.phase-item { font-size:22px; }
        }
    </style>
</head>
<body>
<div class="page-wrap ups-shell">
    <div class="title-bar">
        <div>
            <h2>UPS 모니터링</h2>
            <p class="muted">슈나이더 Easy UPS 3-Phase Modular Memory Map 기준 화면입니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='../system/ups_register.jsp'">UPS 등록</button>
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <div class="hmi-toolbar">
        <form method="get">
            <select name="ups_id" onchange="this.form.submit()">
                <% if (devices.isEmpty()) { %>
                <option value="">등록된 UPS 없음</option>
                <% } %>
                <% for (Map<String, Object> d : devices) { String id = String.valueOf(d.get("ups_id")); %>
                <option value="<%= h(id) %>" <%= id.equals(selectedId) ? "selected" : "" %>><%= h(d.get("ups_name")) %> - <%= h(d.get("ip_address")) %></option>
                <% } %>
            </select>
        </form>
        <div class="muted">자동 갱신 5초</div>
    </div>

        <div class="hmi-scale">
        <div class="hmi">
            <div class="mimic-panel">
                <div class="mimic-wrap">
                <svg class="mimic-svg" viewBox="0 0 1040 360" role="img" aria-label="UPS mimic diagram">
                    <defs>
                        <marker id="mimicArrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">
                            <path d="M 0 0 L 10 5 L 0 10 z" fill="context-stroke"></path>
                        </marker>
                    </defs>

                    <rect x="18" y="28" width="58" height="58" class="mimic-device <%= uibClosed ? "active" : "" %>"></rect>
                    <path d="M42 43 L66 57 L42 71 Z" fill="<%= uibClosed ? "#169b45" : "#9b9b9b" %>"></path>
                    <text x="120" y="42" class="mimic-text">UIB</text>
                    <line x1="76" y1="57" x2="180" y2="57" class="mimic-line <%= uibPathClass %>"></line>
                    <circle cx="155" cy="57" r="7" class="mimic-dot <%= uibClosed ? "active" : "" %>"></circle>

                    <rect x="305" y="20" width="74" height="74" class="mimic-device <%= inverterPath ? "active" : "" %>"></rect>
                    <text x="324" y="53" class="mimic-text">~</text>
                    <text x="336" y="78" class="mimic-small">=</text>
                    <line x1="180" y1="57" x2="305" y2="57" class="mimic-line <%= uibPathClass %>"></line>
                    <line x1="379" y1="57" x2="470" y2="57" class="mimic-line <%= inverterPathClass %>"></line>

                    <rect x="560" y="20" width="74" height="74" class="mimic-device <%= inverterPath ? "active" : "" %>"></rect>
                    <text x="580" y="48" class="mimic-small">=</text>
                    <text x="604" y="76" class="mimic-text">~</text>
                    <line x1="470" y1="57" x2="560" y2="57" class="mimic-line <%= inverterPathClass %>"></line>
                    <line x1="634" y1="57" x2="855" y2="57" class="mimic-line <%= uobPathClass %>"></line>
                    <circle cx="795" cy="57" r="7" class="mimic-dot <%= uobClosed ? "active" : "" %>"></circle>
                    <text x="782" y="58" dy="-18" class="mimic-text">UOB</text>
                    <rect x="956" y="28" width="58" height="58" class="mimic-device <%= uobClosed ? "active" : "" %>"></rect>
                    <path d="M973 43 L997 57 L973 71 Z" fill="<%= uobClosed ? "#169b45" : "#9b9b9b" %>"></path>
                    <line x1="855" y1="57" x2="956" y2="57" class="mimic-line <%= uobPathClass %>" marker-end="url(#mimicArrow)"></line>

                    <line x1="470" y1="57" x2="470" y2="138" class="mimic-line <%= batteryPathClass %>"></line>
                    <circle cx="470" cy="112" r="6" class="mimic-dot <%= bbClosed ? "active" : "" %>"></circle>
                    <text x="430" y="108" class="mimic-text">BB</text>
                    <rect x="425" y="150" width="90" height="82" class="mimic-device <%= bbClosed ? "active" : "" %>"></rect>
                    <path d="M452 178 h36 a10 10 0 0 1 10 10 v18 h-8 v-16 h-40 v16 h-8 v-18 a10 10 0 0 1 10-10 z" fill="none" stroke="<%= bbClosed ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></path>
                    <line x1="452" y1="174" x2="452" y2="166" stroke="<%= bbClosed ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></line>
                    <line x1="488" y1="174" x2="488" y2="166" stroke="<%= bbClosed ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></line>

                    <rect x="18" y="262" width="58" height="58" class="mimic-device <%= ssibClosed ? "active" : "" %>"></rect>
                    <path d="M42 277 L66 291 L42 305 Z" fill="<%= ssibClosed ? "#169b45" : "#111" %>"></path>
                    <text x="88" y="272" class="mimic-text">SSIB</text>
                    <line x1="76" y1="291" x2="115" y2="291" class="mimic-line <%= ssibPathClass %>"></line>
                    <line x1="115" y1="291" x2="<%= ssibClosed ? "175" : "145" %>" y2="<%= ssibClosed ? "291" : "268" %>" class="mimic-switch <%= ssibClosed ? "mimic-active" : "mimic-idle" %>"></line>
                    <circle cx="115" cy="291" r="6" class="mimic-dot <%= ssibClosed ? "active" : "" %>"></circle>
                    <circle cx="175" cy="291" r="6" class="mimic-dot <%= bf2Closed ? "active" : "" %>"></circle>
                    <text x="172" y="258" class="mimic-text">BF2</text>
                    <line x1="175" y1="291" x2="<%= bf2Closed ? "230" : "210" %>" y2="<%= bf2Closed ? "291" : "266" %>" class="mimic-switch <%= bf2Closed ? "mimic-active" : "mimic-idle" %>"></line>
                    <line x1="175" y1="291" x2="425" y2="291" class="mimic-line <%= staticBypassPathClass %>"></line>

                    <rect x="425" y="250" width="90" height="82" class="mimic-device <%= staticBypassPath ? "active" : "" %>"></rect>
                    <path d="M470 267 v46" stroke="<%= staticBypassPath ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></path>
                    <path d="M450 281 h26 l-16 20 h28" fill="none" stroke="<%= staticBypassPath ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></path>
                    <line x1="515" y1="291" x2="735" y2="291" class="mimic-line <%= staticBypassPathClass %>"></line>
                    <line x1="735" y1="291" x2="735" y2="57" class="mimic-line <%= staticBypassPathClass %>"></line>

                    <text x="88" y="356" class="mimic-text">MBB</text>
                    <line x1="76" y1="330" x2="120" y2="330" class="mimic-line <%= maintenanceBypassPathClass %>"></line>
                    <line x1="120" y1="330" x2="<%= mbbClosed ? "180" : "150" %>" y2="<%= mbbClosed ? "330" : "307" %>" class="mimic-switch <%= mbbClosed ? "mimic-active" : "mimic-idle" %>"></line>
                    <circle cx="120" cy="330" r="6" class="mimic-dot <%= mbbClosed ? "active" : "" %>"></circle>
                    <line x1="120" y1="330" x2="910" y2="330" class="mimic-line <%= maintenanceBypassPathClass %>"></line>
                    <line x1="910" y1="330" x2="910" y2="57" class="mimic-line <%= maintenanceBypassPathClass %>"></line>

                    <rect x="770" y="120" width="220" height="120" class="mimic-mode-box"></rect>
                    <text x="812" y="155" class="mimic-text">UPS 모드</text>
                    <rect x="770" y="168" width="220" height="34" class="mimic-mode-fill"></rect>
                    <text x="826" y="193" class="mimic-small"><%= h(upsMode) %></text>
                    <line x1="770" y1="208" x2="990" y2="208" stroke="#666" stroke-width="2"></line>
                    <text x="804" y="232" class="mimic-text">시스템 모드</text>
                    <rect x="770" y="244" width="220" height="34" class="mimic-mode-fill"></rect>
                    <text x="842" y="269" class="mimic-small"><%= h(systemMode) %></text>
                </svg>
                </div>
            </div>

            <div class="hmi-grid">
                <div class="hmi-panel span-left">
                    <h3>출력 전압</h3>
                    <div class="metric-row"><span>L1-2</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_voltage_l12"), 0, "V") %></span></div>
                    <div class="metric-row"><span>L2-3</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_voltage_l23"), 0, "V") %></span></div>
                    <div class="metric-row"><span>L3-1</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_voltage_l31"), 0, "V") %></span></div>
                </div>

            <div class="hmi-panel span-mid battery-panel" style="--charge:<%= m.get("battery_charge_percent") == null ? "0" : fmt(m.get("battery_charge_percent"), 0) %>%">
                <div class="battery-time">
                    <div><%= m.get("remaining_minutes") == null ? "--" : fmt(m.get("remaining_minutes"), 0) %> Mn</div>
                    <div>-- Sec</div>
                </div>
                <div class="battery-shape"></div>
                <div class="battery-percent"><%= m.get("battery_charge_percent") == null ? "--" : fmt(m.get("battery_charge_percent"), 0) %>%</div>
            </div>

            <div class="hmi-panel span-right total-panel">
                <h3>총 출력 전력</h3>
                <div class="bar"><%= totalLoad == null ? "--.-" : fmt(totalLoad, 1) %>%</div>
                <div class="total-values"><%= fmt(totalKw, 0) %> kW&nbsp;&nbsp;-&nbsp;&nbsp;<%= fmt(totalKva, 0) %> kVA</div>
            </div>

            <div class="hmi-panel span-left">
                <h3>출력 전류</h3>
                <div class="metric-row"><span>L1</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_current_l1"), 0, "A") %></span></div>
                <div class="metric-row"><span>L2</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_current_l2"), 0, "A") %></span></div>
                <div class="metric-row"><span>L3</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_current_l3"), 0, "A") %></span></div>
            </div>

            <div class="hmi-panel span-mid date-panel"><%= nowText() %></div>

            <div class="hmi-panel span-right phase-power">
                <h3>출력 전력</h3>
                <div class="phase-list">
                    <div class="phase-item"><span class="phase">L1</span><span class="nums"><%= fmt(m.get("output_power_l1_kw"), 0) %> kW<br><%= fmt(m.get("output_apparent_l1_kva"), 0) %> kVA</span></div>
                    <div class="phase-item"><span class="phase">L2</span><span class="nums"><%= fmt(m.get("output_power_l2_kw"), 0) %> kW<br><%= fmt(m.get("output_apparent_l2_kva"), 0) %> kVA</span></div>
                    <div class="phase-item"><span class="phase">L3</span><span class="nums"><%= fmt(m.get("output_power_l3_kw"), 0) %> kW<br><%= fmt(m.get("output_apparent_l3_kva"), 0) %> kVA</span></div>
                </div>
            </div>

            <div class="hmi-panel span-mid mode-panel">
                <h3>UPS 모드</h3>
                <div class="mode-value"><%= h(upsMode) %></div>
            </div>

            <div class="hmi-panel span-left">
                <h3>출력 주파수</h3>
                <div style="text-align:center;font-size:30px;font-weight:800;"><%= fmtUnit(m.get("frequency"), 1, "Hz") %></div>
            </div>

            <div class="hmi-panel span-mid mode-panel">
                <h3>시스템 모드</h3>
                <div class="mode-value"><%= h(systemMode) %></div>
            </div>
            </div>
        </div>
    </div>

    <div class="muted-note">
        <% if (selected != null) { %>
        <%= h(selected.get("ups_name")) %> / <%= h(selected.get("location")) %> / <%= h(selected.get("ip_address")) %>:<%= h(selected.get("modbus_port")) %> / Unit <%= h(selected.get("unit_id")) %> / <%= h(selected.get("profile_name")) %> / 최근 수집: <%= fmtDate(m.get("measured_at")) %>
        <% } else { %>
        UPS 등록 후 Schneider Easy UPS 3-Phase Modular 프로파일을 선택하면 이 화면에서 값이 표시됩니다.
        <% } %>
    </div>
</div>
</body>
</html>
