<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String fmt(Object value, int scale) {
        return epms.util.UpsFormatSupport.fmtDash(value, scale);
    }

    private String fmtUnit(Object value, int scale, String unit) {
        return value == null ? "--- " + unit : fmt(value, scale) + " " + unit;
    }

    private String fmtUnit(Object value, int scale, String unit, boolean hide) {
        return hide ? "-" : fmtUnit(value, scale, unit);
    }

    private String fmtPlain(Object value, int scale, boolean hide) {
        return hide ? "-" : fmt(value, scale);
    }

    private String fmtPlainUnit(Object value, int scale, String unit, boolean hide) {
        return hide ? "-" : fmt(value, scale) + unit;
    }

    private String fmtDate(Object value) {
        return value == null ? "----/--/-- --:--:--" : epms.util.UpsFormatSupport.displaySlashDateTime(value);
    }

    private String fmtDate(Object value, boolean hide) {
        return hide ? "-" : fmtDate(value);
    }

    private boolean commBad(Map<String, Object> selected) {
        if (selected == null || selected.get("last_comm_status") == null) return false;
        int failCount = intValue(selected.get("consecutive_fail_count"), 0);
        if (failCount > 0 && failCount < 3) return false;
        String comm = String.valueOf(selected.get("last_comm_status"));
        return !("OK".equalsIgnoreCase(comm) || "NORMAL".equalsIgnoreCase(comm) || "ONLINE".equalsIgnoreCase(comm));
    }

    private int intValue(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            return value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value).trim());
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private String nowText() {
        return new java.text.SimpleDateFormat("yyyy/MM/dd HH:mm:ss").format(new java.util.Date());
    }

    private boolean enabledDevice(Map<String, Object> device) {
        if (device == null) return false;
        Object enabled = device.get("enabled");
        if (enabled == null) return false;
        if (enabled instanceof Boolean) return Boolean.TRUE.equals(enabled);
        String value = String.valueOf(enabled).trim();
        return "1".equals(value) || "true".equalsIgnoreCase(value) || "Y".equalsIgnoreCase(value);
    }

    private List<Map<String, Object>> activeDevices(List<Map<String, Object>> devices) {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        if (devices == null) return out;
        for (Map<String, Object> device : devices) {
            if (enabledDevice(device)) out.add(device);
        }
        return out;
    }

    private boolean containsDeviceId(List<Map<String, Object>> devices, String selectedId) {
        if (selectedId == null || selectedId.trim().length() == 0) return false;
        for (Map<String, Object> device : devices) {
            if (selectedId.equals(String.valueOf(device.get("ups_id")))) return true;
        }
        return false;
    }

%>
<%
request.setCharacterEncoding("UTF-8");
String err = null;
String selectedId = request.getParameter("ups_id");
boolean embedded = "1".equals(request.getParameter("embed"));
List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
Map<String, Object> selected = null;
Map<String, Object> m = new HashMap<String, Object>();
Map<String, Object> statusView = new HashMap<String, Object>();

try {
    statusView = epms.ups.UpsRealtimeService.realtimeStatus(selectedId, application);
    devices = (List<Map<String, Object>>) statusView.get("devices");
    selectedId = String.valueOf(statusView.get("selectedId"));
    selected = (Map<String, Object>) statusView.get("selected");
    m = (Map<String, Object>) statusView.get("measurement");
} catch (Exception e) {
    err = e.getMessage();
}

if (devices == null) devices = new ArrayList<Map<String, Object>>();
devices = activeDevices(devices);
if (!devices.isEmpty() && !containsDeviceId(devices, selectedId)) {
    response.sendRedirect("ups_status.jsp?ups_id=" + java.net.URLEncoder.encode(String.valueOf(devices.get(0).get("ups_id")), "UTF-8") + (embedded ? "&embed=1" : ""));
    return;
}
if (m == null) m = new HashMap<String, Object>();
if (devices.isEmpty()) {
    selectedId = "";
    selected = null;
    m = new HashMap<String, Object>();
}
String upsMode = String.valueOf(statusView.get("upsMode"));
String systemMode = String.valueOf(statusView.get("systemMode"));
boolean commBad = commBad(selected);
if (devices.isEmpty()) {
    upsMode = "-";
    systemMode = "-";
}
if (commBad) {
    upsMode = "통신불량";
    systemMode = "-";
}
int refreshSeconds = selected == null ? 2 : intValue(selected.get("poll_interval_seconds"), 2);
if (refreshSeconds < 1) refreshSeconds = 1;
Object totalLoad = m.get("load_percent");
Object totalKw = m.get("output_power_kw");
Object totalKva = m.get("output_apparent_total_kva");
boolean uibClosed = Boolean.TRUE.equals(statusView.get("uibClosed"));
boolean ssibClosed = Boolean.TRUE.equals(statusView.get("ssibClosed"));
boolean uobClosed = Boolean.TRUE.equals(statusView.get("uobClosed"));
boolean bf2Closed = Boolean.TRUE.equals(statusView.get("bf2Closed"));
boolean mbbClosed = Boolean.TRUE.equals(statusView.get("mbbClosed"));
boolean bbClosed = Boolean.TRUE.equals(statusView.get("bbClosed"));
boolean inverterPath = Boolean.TRUE.equals(statusView.get("inverterPath"));
boolean staticBypassPath = Boolean.TRUE.equals(statusView.get("staticBypassPath"));
String uibPathClass = String.valueOf(statusView.get("uibPathClass"));
String uobPathClass = String.valueOf(statusView.get("uobPathClass"));
String inverterPathClass = String.valueOf(statusView.get("inverterPathClass"));
String ssibPathClass = String.valueOf(statusView.get("ssibPathClass"));
String bypassInputBranchClass = String.valueOf(statusView.get("bypassInputBranchClass"));
String staticBypassPathClass = String.valueOf(statusView.get("staticBypassPathClass"));
String maintenanceBypassPathClass = String.valueOf(statusView.get("maintenanceBypassPathClass"));
String batteryPathClass = String.valueOf(statusView.get("batteryPathClass"));
%>
<!doctype html>
<html>
<head>
    <title>UPS 모니터링</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        body { background:#edf2f7; }
        .ups-shell { max-width:1420px; margin:0 auto; }
        .page-wrap.ups-shell { padding-top:14px; padding-bottom:14px; }
        .ups-shell .title-bar { margin-bottom:12px; align-items:center; }
        .ups-shell .title-bar h2 { margin:0 0 2px; font-size:24px; letter-spacing:-.01em; }
        .ups-shell .title-bar p { margin:0; }
        .hmi-scale { zoom:.76; }
        .ups-controlbar { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:10px; padding:8px 10px; border:1px solid #d7e1ec; border-radius:10px; background:#fff; box-shadow:0 10px 28px rgba(15,23,42,.06); }
        .ups-controlbar form { margin:0; }
        .ups-controlbar select { min-width:300px; height:34px; padding:5px 34px 5px 10px; border:1px solid #cbd5e1; border-radius:8px; background:#fff; color:#0f172a; font-size:13px; font-weight:800; outline:none; }
        .ups-controlbar select:focus { border-color:#38bdf8; box-shadow:0 0 0 3px rgba(56,189,248,.16); }
        .ups-control-meta { display:flex; align-items:center; justify-content:flex-end; gap:8px; color:#64748b; font-size:12px; font-weight:700; white-space:nowrap; }
        .ups-control-meta strong { color:#0f172a; font-size:13px; }
        .ups-refresh-badge { display:inline-flex; align-items:center; gap:3px; height:28px; padding:0 10px; border:1px solid #dbe5f2; border-radius:999px; background:#f8fafc; }
        .hmi {
            border:1px solid #d1dae5;
            border-radius:14px;
            background:#f8fafc;
            padding:12px;
            color:#0f172a;
            font-family:"Segoe UI", "Noto Sans KR", Arial, sans-serif;
            display:grid;
            grid-template-columns:minmax(0, 3fr) minmax(360px, 1.42fr);
            gap:12px;
            align-items:stretch;
            box-shadow:0 18px 44px rgba(15,23,42,.10);
        }
        .mimic-panel { grid-column:2; grid-row:1; border:1px solid #cbd5e1; border-radius:12px; background:#fff; padding:10px; display:flex; align-items:stretch; min-height:100%; overflow:hidden; box-shadow:inset 0 0 0 1px rgba(255,255,255,.65); }
        .mimic-wrap { width:100%; min-height:0; display:flex; align-items:center; }
        .mimic-svg { display:block; width:100%; height:100%; max-height:100%; }
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
        .mimic-mode-box { fill:#fff; stroke:#8aa0b6; stroke-width:1.6; }
        .mimic-mode-title { font-size:22px; font-weight:900; fill:#111; font-family:"Segoe UI","Noto Sans KR",Arial,sans-serif; }
        .mimic-mode-fill { fill:#57c978; }
        .mimic-mode-value { font-size:17px; font-weight:900; fill:#fff; font-family:"Segoe UI","Noto Sans KR",Arial,sans-serif; }
        .hmi-grid {
            display:grid;
            grid-template-columns:1.05fr 1.15fr 1.05fr;
            gap:10px;
            align-content:stretch;
            grid-column:1;
            grid-row:1;
        }
        .hmi-panel {
            border:1px solid #cbd5e1;
            border-radius:10px;
            background:#fff;
            min-height:86px;
            padding:10px 14px;
            font-weight:400;
            box-shadow:0 8px 22px rgba(15,23,42,.06);
        }
        .hmi-panel h3 { margin:0 0 8px; text-align:center; font-size:24px; font-weight:900; color:#0f172a; line-height:1.08; }
        .metric-row { display:grid; grid-template-columns:70px 18px 1fr; gap:8px; align-items:center; font-size:22px; font-weight:700; line-height:1.2; color:#334155; }
        .metric-row .val { text-align:right; font-weight:800; color:#111827; }
        .battery-panel { display:grid; grid-template-columns:1fr 120px 1fr; align-items:center; gap:10px; }
        .battery-time { text-align:center; line-height:1.18; }
        .battery-time-title { font-size:19px; font-weight:900; margin-bottom:5px; color:#334155; }
        .battery-time-value { font-size:23px; font-weight:700; }
        .battery-percent { font-size:24px; font-weight:800; text-align:center; line-height:1.15; }
        .battery-temp { margin-top:5px; font-size:18px; color:#334155; }
        .battery-shape { height:48px; border:5px solid #111827; border-radius:4px; position:relative; background:linear-gradient(90deg,#4ade80 var(--charge,0%),#f8fafc var(--charge,0%)); }
        .battery-shape::before { content:""; position:absolute; left:18px; top:-13px; width:30px; height:11px; border:5px solid #111827; border-bottom:none; border-radius:4px 4px 0 0; background:#fff; }
        .battery-shape::after { content:""; position:absolute; right:18px; top:-13px; width:30px; height:11px; border:5px solid #111827; border-bottom:none; border-radius:4px 4px 0 0; background:#fff; }
        .date-panel { min-height:58px; display:flex; align-items:center; justify-content:center; font-size:22px; font-weight:900; color:#0f172a; }
        .mode-panel { min-height:110px; padding:0; overflow:hidden; display:flex; flex-direction:column; }
        .mode-panel h3 { min-height:30px; margin:0; padding:6px 12px 5px; display:flex; align-items:center; justify-content:center; border-bottom:1px solid #cbd5e1; font-size:21px; font-weight:900; line-height:1.1; }
        .mode-value { min-height:42px; background:#dcfce7; color:#166534; border-bottom:1px solid #bbf7d0; display:flex; align-items:center; justify-content:center; text-align:center; font-size:22px; font-weight:900; line-height:1.15; padding:0 10px; }
        .total-panel .bar { height:34px; border-radius:8px; background:#dcfce7; color:#166534; margin:8px 0; display:flex; align-items:center; justify-content:center; font-size:23px; font-weight:800; }
        .total-panel .total-values { text-align:center; font-size:22px; font-weight:800; color:#111827; }
        .phase-power { grid-row:span 3; }
        .phase-list { display:grid; gap:12px; padding-top:22px; }
        .phase-item { display:grid; grid-template-columns:58px 1fr; align-items:center; font-size:23px; }
        .phase-item .phase { font-weight:800; color:#334155; }
        .phase-item .nums { text-align:right; line-height:1.22; font-weight:700; color:#111827; }
        .voltage-panel { grid-row:1; }
        .current-panel { grid-row:2; }
        .frequency-panel { grid-row:3; }
        .pf-panel { grid-row:4; }
        .freq-value { text-align:center; font-size:24px; font-weight:800; padding-top:6px; }
        .pf-list { display:grid; gap:4px; font-size:22px; font-weight:700; padding-top:4px; }
        .pf-row { display:grid; grid-template-columns:48px 14px 1fr; gap:6px; align-items:center; line-height:1.18; }
        .pf-row span:last-child { text-align:right; }
        .span-left { grid-column:1; }
        .span-mid { grid-column:2; }
        .span-right { grid-column:3; }
        .muted-note { margin-top:6px; color:#64748b; font-size:12px; }
        @media (max-width: 940px) {
            .ups-controlbar { align-items:stretch; flex-direction:column; }
            .ups-controlbar select { min-width:0; width:100%; }
            .ups-control-meta { justify-content:flex-start; flex-wrap:wrap; white-space:normal; }
            .hmi { display:block; }
            .mimic-panel { margin-top:8px; }
            .hmi-grid { grid-template-columns:1fr; }
            .span-left,.span-mid,.span-right,.phase-power { grid-column:auto; grid-row:auto; }
            .hmi-panel h3 { font-size:24px; }
            .metric-row,.battery-time-value,.battery-percent,.date-panel,.mode-value,.total-panel .bar,.total-panel .total-values,.phase-item { font-size:22px; }
            .battery-time-title { font-size:18px; }
            .battery-temp { font-size:17px; }
            .freq-value { font-size:22px; }
            .pf-list { font-size:22px; }
        }
    </style>
</head>
<body>
<div class="page-wrap ups-shell">
    <div class="page-title"><h2>UPS 모니터링</h2></div>
<% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <div class="ups-controlbar hmi-toolbar">
        <form method="get">
            <% if (embedded) { %><input type="hidden" name="embed" value="1"><% } %>
            <select name="ups_id" onchange="this.form.submit()">
                <% if (devices.isEmpty()) { %>
                <option value="">등록된 UPS 없음</option>
                <% } %>
                <% for (Map<String, Object> d : devices) { String id = String.valueOf(d.get("ups_id")); %>
                <option value="<%= h(id) %>" <%= id.equals(selectedId) ? "selected" : "" %>><%= h(d.get("ups_name")) %> - <%= h(d.get("ip_address")) %></option>
                <% } %>
            </select>
        </form>
        <div class="ups-control-meta"><span class="ups-refresh-badge">자동 갱신 <strong><%= refreshSeconds %></strong>초</span></div>
    </div>

        <div class="hmi-scale" id="upsStatusContent">
        <div class="hmi">
            <div class="mimic-panel">
                <div class="mimic-wrap">
                <svg class="mimic-svg" viewBox="0 0 1040 402" role="img" aria-label="UPS mimic diagram">
                    <defs>
                        <marker id="mimicArrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">
                            <path d="M 0 0 L 10 5 L 0 10 z" fill="context-stroke"></path>
                        </marker>
                    </defs>

                    <rect x="24" y="28" width="58" height="58" class="mimic-device <%= uibClosed ? "active" : "" %>"></rect>
                    <path d="M48 43 L72 57 L48 71 Z" fill="<%= uibClosed ? "#169b45" : "#9b9b9b" %>"></path>
                    <text x="120" y="42" class="mimic-text">UIB</text>
                    <line x1="82" y1="57" x2="180" y2="57" class="mimic-line <%= uibPathClass %>"></line>
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

                    <rect x="24" y="262" width="58" height="58" class="mimic-device <%= ssibClosed ? "active" : "" %>"></rect>
                    <path d="M48 277 L72 291 L48 305 Z" fill="<%= ssibClosed ? "#169b45" : "#111" %>"></path>
                    <text x="112" y="272" class="mimic-text">SSIB</text>
                    <line x1="82" y1="291" x2="140" y2="291" class="mimic-line <%= ssibPathClass %>"></line>
                    <line x1="100" y1="291" x2="100" y2="364" class="mimic-line <%= bypassInputBranchClass %>"></line>
                    <line x1="140" y1="291" x2="<%= ssibClosed ? "200" : "170" %>" y2="<%= ssibClosed ? "291" : "268" %>" class="mimic-switch <%= ssibClosed ? "mimic-active" : "mimic-idle" %>"></line>
                    <circle cx="140" cy="291" r="6" class="mimic-dot <%= ssibClosed ? "active" : "" %>"></circle>
                    <circle cx="200" cy="291" r="6" class="mimic-dot <%= ssibClosed ? "active" : "" %>"></circle>
                    <text x="197" y="258" class="mimic-text">BF2</text>
                    <line x1="200" y1="291" x2="<%= bf2Closed ? "255" : "235" %>" y2="<%= bf2Closed ? "291" : "266" %>" class="mimic-switch <%= bf2Closed ? "mimic-active" : "mimic-idle" %>"></line>
                    <circle cx="255" cy="291" r="6" class="mimic-dot <%= staticBypassPath ? "active" : "" %>"></circle>
                    <line x1="255" y1="291" x2="425" y2="291" class="mimic-line <%= staticBypassPathClass %>"></line>

                    <rect x="425" y="250" width="90" height="82" class="mimic-device <%= staticBypassPath ? "active" : "" %>"></rect>
                    <path d="M470 267 v46" stroke="<%= staticBypassPath ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></path>
                    <path d="M450 281 h26 l-16 20 h28" fill="none" stroke="<%= staticBypassPath ? "#169b45" : "#9b9b9b" %>" stroke-width="4"></path>
                    <line x1="515" y1="291" x2="735" y2="291" class="mimic-line <%= staticBypassPathClass %>"></line>
                    <line x1="735" y1="291" x2="735" y2="57" class="mimic-line <%= staticBypassPathClass %>"></line>

                    <text x="112" y="390" class="mimic-text">MBB</text>
                    <line x1="100" y1="364" x2="145" y2="364" class="mimic-line <%= maintenanceBypassPathClass %>"></line>
                    <line x1="145" y1="364" x2="<%= mbbClosed ? "205" : "175" %>" y2="<%= mbbClosed ? "364" : "350" %>" class="mimic-switch <%= mbbClosed ? "mimic-active" : "mimic-idle" %>"></line>
                    <circle cx="145" cy="364" r="6" class="mimic-dot <%= mbbClosed ? "active" : "" %>"></circle>
                    <circle cx="205" cy="364" r="6" class="mimic-dot <%= mbbClosed ? "active" : "" %>"></circle>
                    <line x1="205" y1="364" x2="910" y2="364" class="mimic-line <%= maintenanceBypassPathClass %>"></line>
                    <line x1="910" y1="364" x2="910" y2="57" class="mimic-line <%= maintenanceBypassPathClass %>"></line>

                    <rect x="770" y="116" width="220" height="134" rx="8" class="mimic-mode-box"></rect>
                    <text x="880" y="147" text-anchor="middle" class="mimic-mode-title">UPS 모드</text>
                    <rect x="790" y="160" width="180" height="28" rx="4" class="mimic-mode-fill"></rect>
                    <text x="880" y="180" text-anchor="middle" class="mimic-mode-value"><%= h(upsMode) %></text>
                    <text x="880" y="216" text-anchor="middle" class="mimic-mode-title">시스템 모드</text>
                    <rect x="790" y="226" width="180" height="28" rx="4" class="mimic-mode-fill"></rect>
                    <text x="880" y="246" text-anchor="middle" class="mimic-mode-value"><%= h(systemMode) %></text>
                </svg>
                </div>
            </div>

            <div class="hmi-grid">
                <div class="hmi-panel span-left voltage-panel">
                    <h3>출력 전압</h3>
                    <div class="metric-row"><span>L1-2</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_voltage_l12"), 0, "V", commBad) %></span></div>
                    <div class="metric-row"><span>L2-3</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_voltage_l23"), 0, "V", commBad) %></span></div>
                    <div class="metric-row"><span>L3-1</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_voltage_l31"), 0, "V", commBad) %></span></div>
                </div>

            <div class="hmi-panel span-mid battery-panel" style="--charge:<%= commBad || m.get("battery_charge_percent") == null ? "0" : fmt(m.get("battery_charge_percent"), 0) %>%">
                <div class="battery-time">
                    <div class="battery-time-title">잔여시간</div>
                    <div class="battery-time-value"><%= fmtPlainUnit(m.get("remaining_minutes"), 0, " Min", commBad) %></div>
                </div>
                <div class="battery-shape"></div>
                <div class="battery-percent">
                    <div><%= fmtPlainUnit(m.get("battery_charge_percent"), 0, "%", commBad) %></div>
                    <div class="battery-temp"><%= fmtPlainUnit(m.get("battery_temperature"), 1, "&deg;C", commBad) %></div>
                </div>
            </div>

            <div class="hmi-panel span-right total-panel">
                <h3>총 출력 전력</h3>
                <div class="bar"><%= fmtPlainUnit(totalLoad, 1, "%", commBad) %></div>
                <div class="total-values"><%= fmtPlainUnit(totalKw, 0, " kW", commBad) %>&nbsp;&nbsp;-&nbsp;&nbsp;<%= fmtPlainUnit(totalKva, 0, " kVA", commBad) %></div>
            </div>

            <div class="hmi-panel span-left current-panel">
                <h3>출력 전류</h3>
                <div class="metric-row"><span>L1</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_current_l1"), 0, "A", commBad) %></span></div>
                <div class="metric-row"><span>L2</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_current_l2"), 0, "A", commBad) %></span></div>
                <div class="metric-row"><span>L3</span><span>:</span><span class="val"><%= fmtUnit(m.get("output_current_l3"), 0, "A", commBad) %></span></div>
            </div>

            <div class="hmi-panel span-mid date-panel"><%= nowText() %></div>

            <div class="hmi-panel span-right phase-power">
                <h3>출력 전력</h3>
                <div class="phase-list">
                    <div class="phase-item"><span class="phase">L1</span><span class="nums"><%= fmtPlainUnit(m.get("output_power_l1_kw"), 0, " kW", commBad) %><br><%= fmtPlainUnit(m.get("output_apparent_l1_kva"), 0, " kVA", commBad) %></span></div>
                    <div class="phase-item"><span class="phase">L2</span><span class="nums"><%= fmtPlainUnit(m.get("output_power_l2_kw"), 0, " kW", commBad) %><br><%= fmtPlainUnit(m.get("output_apparent_l2_kva"), 0, " kVA", commBad) %></span></div>
                    <div class="phase-item"><span class="phase">L3</span><span class="nums"><%= fmtPlainUnit(m.get("output_power_l3_kw"), 0, " kW", commBad) %><br><%= fmtPlainUnit(m.get("output_apparent_l3_kva"), 0, " kVA", commBad) %></span></div>
                </div>
            </div>

            <div class="hmi-panel span-mid mode-panel">
                <h3>UPS 모드</h3>
                <div class="mode-value"><%= h(upsMode) %></div>
            </div>

            <div class="hmi-panel span-left frequency-panel">
                <h3>출력 주파수</h3>
                <div class="freq-value"><%= fmtUnit(m.get("frequency"), 1, "Hz", commBad) %></div>
            </div>

            <div class="hmi-panel span-left pf-panel">
                <h3>역률</h3>
                <div class="pf-list">
                    <div class="pf-row"><span>L1</span><span>:</span><span><%= fmtPlain(m.get("output_pf_l1"), 2, commBad) %></span></div>
                    <div class="pf-row"><span>L2</span><span>:</span><span><%= fmtPlain(m.get("output_pf_l2"), 2, commBad) %></span></div>
                    <div class="pf-row"><span>L3</span><span>:</span><span><%= fmtPlain(m.get("output_pf_l3"), 2, commBad) %></span></div>
                </div>
            </div>

            <div class="hmi-panel span-mid mode-panel">
                <h3>시스템 모드</h3>
                <div class="mode-value"><%= h(systemMode) %></div>
            </div>
            </div>
        </div>
    </div>

    <div class="muted-note" id="upsStatusNote">
        <% if (selected != null) { %>
        <%= h(selected.get("ups_name")) %> / <%= h(selected.get("location")) %> / <%= h(selected.get("ip_address")) %>:<%= h(selected.get("modbus_port")) %> / Unit <%= h(selected.get("unit_id")) %> / <%= h(selected.get("profile_name")) %> / 최근 수집: <%= fmtDate(m.get("measured_at"), commBad) %>
        <% } else { %>
        UPS 등록 후 Schneider Easy UPS 3-Phase Modular 프로파일을 선택하면 이 화면에서 값이 표시됩니다.
        <% } %>
    </div>
</div>
<script>
(function () {
    var refreshMs = Math.max(1000, <%= refreshSeconds %> * 1000);
    var busy = false;
    function refreshStatus() {
        if (busy || document.hidden || !window.fetch || !window.DOMParser) return;
        busy = true;
        var url = new URL(window.location.href);
        url.searchParams.set('_', Date.now());
        fetch(url.pathname + url.search, {cache:'no-store', headers:{'X-Requested-With':'fetch'}})
            .then(function (response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.text();
            })
            .then(function (html) {
                var doc = new DOMParser().parseFromString(html, 'text/html');
                var nextContent = doc.getElementById('upsStatusContent');
                var nextNote = doc.getElementById('upsStatusNote');
                var content = document.getElementById('upsStatusContent');
                var note = document.getElementById('upsStatusNote');
                if (nextContent && content) content.innerHTML = nextContent.innerHTML;
                if (nextNote && note) note.innerHTML = nextNote.innerHTML;
            })
            .catch(function () {})
            .finally(function () {
                busy = false;
            });
    }
    setInterval(refreshStatus, refreshMs);
})();
</script>
</body>
</html>
