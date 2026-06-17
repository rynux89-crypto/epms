<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String fmt(Object value, int scale) {
        return epms.util.UpsFormatSupport.fmtDash(value, scale);
    }

    private String fmt(Object value, int scale, boolean hide) {
        return hide ? "-" : fmt(value, scale);
    }

    private String fmtUnit(Object value, int scale, String unit, boolean hide) {
        return hide ? "-" : fmt(value, scale) + " " + unit;
    }

    private double dbl(Object value, double fallback) {
        if (value == null) return fallback;
        try {
            return value instanceof Number ? ((Number)value).doubleValue() : Double.parseDouble(String.valueOf(value));
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private int intValue(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            return value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value).trim());
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }

    private double pfAngle(Object pf) {
        if (pf == null) return 0d;
        return Math.toDegrees(Math.acos(clamp(Math.abs(dbl(pf, 1d)), 0d, 1d)));
    }
    private String line(double cx, double cy, double r, double angleDeg) {
        double rad = Math.toRadians(angleDeg);
        double x = cx + Math.cos(rad) * r;
        double y = cy - Math.sin(rad) * r;
        return String.format(java.util.Locale.US, "x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"", cx, cy, x, y);
    }

    private String labelPos(double cx, double cy, double r, double angleDeg) {
        double rad = Math.toRadians(angleDeg);
        double x = cx + Math.cos(rad) * r;
        double y = cy - Math.sin(rad) * r;
        return String.format(java.util.Locale.US, "x=\"%.1f\" y=\"%.1f\"", x, y);
    }

    private String arrowHead(double cx, double cy, double r, double angleDeg, double size) {
        double rad = Math.toRadians(angleDeg);
        double tipX = cx + Math.cos(rad) * r;
        double tipY = cy - Math.sin(rad) * r;
        double left = rad + Math.PI - Math.toRadians(25d);
        double right = rad + Math.PI + Math.toRadians(25d);
        double x1 = tipX + Math.cos(left) * size;
        double y1 = tipY - Math.sin(left) * size;
        double x2 = tipX + Math.cos(right) * size;
        double y2 = tipY - Math.sin(right) * size;
        return String.format(java.util.Locale.US, "%.1f,%.1f %.1f,%.1f %.1f,%.1f", tipX, tipY, x1, y1, x2, y2);
    }

    private String sinePath(double x, double y, double w, double h, double phaseDeg) {
        StringBuilder sb = new StringBuilder();
        double mid = y + h / 2d;
        double amp = h * 0.36d;
        for (int i = 0; i <= 120; i++) {
            double px = x + (w * i / 120d);
            double rad = (Math.PI * 2d * i / 80d) + Math.toRadians(phaseDeg);
            double py = mid - Math.sin(rad) * amp;
            if (i == 0) sb.append("M ");
            else sb.append(" L ");
            sb.append(String.format(java.util.Locale.US, "%.1f %.1f", px, py));
        }
        return sb.toString();
    }

    private String sinePath(double x, double y, double w, double h, double phaseDeg, double value, double topValue) {
        StringBuilder sb = new StringBuilder();
        double mid = y + h / 2d;
        double half = h / 2d;
        double amp = half * clamp(Math.abs(value) / Math.max(1d, topValue), 0d, 1d);
        for (int i = 0; i <= 120; i++) {
            double px = x + (w * i / 120d);
            double rad = (Math.PI * 2d * i / 80d) + Math.toRadians(phaseDeg);
            double py = mid - Math.sin(rad) * amp;
            if (i == 0) sb.append("M ");
            else sb.append(" L ");
            sb.append(String.format(java.util.Locale.US, "%.1f %.1f", px, py));
        }
        return sb.toString();
    }

    private String dateText(Object value) {
        if (value == null) return "수집 데이터 없음";
        return epms.util.UpsFormatSupport.displaySlashDateTime(value);
    }

    private String dateText(Object value, boolean hide) {
        return hide ? "-" : dateText(value);
    }
    private String angleText(Object pf, boolean hide) {
        return hide || pf == null ? "-" : fmt(pfAngle(pf), 1) + "\u00B0";
    }

    private String phasorAngleText(double angleDeg) {
        double normalized = angleDeg % 360d;
        if (normalized < 0d) normalized += 360d;
        return fmt(normalized, 1) + "\u00B0";
    }

    private String currentPhasorAngleText(double angleDeg, Object pf, boolean hide) {
        if (hide) return "-";
        return phasorAngleText(angleDeg) + "/φ" + fmt(pfAngle(pf), 1) + "\u00B0";
    }

    private String waveAxisLabel(double value, boolean hide) {
        return hide ? "-" : fmt(Double.valueOf(value), 1);
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
epms.ups.UpsPhasorPageModel phasorModel = epms.ups.UpsPhasorPageService.build(request.getParameter("ups_id"));
String err = phasorModel.err;
String selectedId = phasorModel.selectedId;
List<Map<String, Object>> devices = activeDevices(phasorModel.devices);
if (!devices.isEmpty() && !containsDeviceId(devices, selectedId)) {
    response.sendRedirect("phasor_diagram.jsp?ups_id=" + java.net.URLEncoder.encode(String.valueOf(devices.get(0).get("ups_id")), "UTF-8"));
    return;
}
Map<String, Object> m = devices.isEmpty() ? new HashMap<String, Object>() : phasorModel.measurement;
boolean hideData = devices.isEmpty() || phasorModel.hideData;
int refreshSeconds = phasorModel.selected == null ? 2 : intValue(phasorModel.selected.get("poll_interval_seconds"), 2);
if (refreshSeconds < 1) refreshSeconds = 1;
double cx = 330d;
double cy = 250d;
double vMax = Math.max(1d, Math.max(dbl(m.get("output_voltage_l12"), 0d), Math.max(dbl(m.get("output_voltage_l23"), 0d), dbl(m.get("output_voltage_l31"), 0d))));
double iMax = Math.max(1d, Math.max(dbl(m.get("output_current_l1"), 0d), Math.max(dbl(m.get("output_current_l2"), 0d), dbl(m.get("output_current_l3"), 0d))));
double v1r = m.get("output_voltage_l12") == null ? 185d : 120d + (dbl(m.get("output_voltage_l12"), 0d) / vMax * 80d);
double v2r = m.get("output_voltage_l23") == null ? 185d : 120d + (dbl(m.get("output_voltage_l23"), 0d) / vMax * 80d);
double v3r = m.get("output_voltage_l31") == null ? 185d : 120d + (dbl(m.get("output_voltage_l31"), 0d) / vMax * 80d);
double i1r = m.get("output_current_l1") == null ? 125d : 80d + (dbl(m.get("output_current_l1"), 0d) / iMax * 70d);
double i2r = m.get("output_current_l2") == null ? 125d : 80d + (dbl(m.get("output_current_l2"), 0d) / iMax * 70d);
double i3r = m.get("output_current_l3") == null ? 125d : 80d + (dbl(m.get("output_current_l3"), 0d) / iMax * 70d);
double v1a = 0d;
double v2a = -120d;
double v3a = 120d;
double i1a = v1a - pfAngle(m.get("output_pf_l1"));
double i2a = v2a - pfAngle(m.get("output_pf_l2"));
double i3a = v3a - pfAngle(m.get("output_pf_l3"));
boolean hasData = !devices.isEmpty() && phasorModel.hasData();
double dialCx = 180d;
double dialCy = 180d;
double dialVMax = Math.max(1d, vMax);
double dialIMax = Math.max(1d, iMax);
double dialV1r = m.get("output_voltage_l12") == null ? 112d : 72d + (dbl(m.get("output_voltage_l12"), 0d) / dialVMax * 52d);
double dialV2r = m.get("output_voltage_l23") == null ? 112d : 72d + (dbl(m.get("output_voltage_l23"), 0d) / dialVMax * 52d);
double dialV3r = m.get("output_voltage_l31") == null ? 112d : 72d + (dbl(m.get("output_voltage_l31"), 0d) / dialVMax * 52d);
double dialI1r = m.get("output_current_l1") == null ? 108d : 68d + (dbl(m.get("output_current_l1"), 0d) / dialIMax * 56d);
double dialI2r = m.get("output_current_l2") == null ? 108d : 68d + (dbl(m.get("output_current_l2"), 0d) / dialIMax * 56d);
double dialI3r = m.get("output_current_l3") == null ? 108d : 68d + (dbl(m.get("output_current_l3"), 0d) / dialIMax * 56d);
double waveVTop = Math.max(1d, vMax * 1.2d);
double waveITop = Math.max(1d, iMax * 1.2d);
%>
<!doctype html>
<html>
<head>
    <title>UPS Phasor Diagram</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        body { background:#dfe6ef; }
        .phasor-shell { width:100%; max-width:1280px; margin:0 auto; padding:8px 10px 6px; box-sizing:border-box; }
        .phasor-toolbar { display:flex; justify-content:space-between; align-items:center; gap:8px; margin-bottom:4px; min-height:30px; }
        .phasor-toolbar form { margin:0; }
        .phasor-toolbar select { min-width:240px; height:28px; padding:2px 8px; border:1px solid #9aa3ad; border-radius:5px; background:#fff; font-size:13px; }
        .phasor-hmi { position:relative; background:#18251f; border:4px solid #ecf2f6; box-shadow:0 14px 34px rgba(22,35,48,.18); padding:7px 10px 6px; color:#23ff35; font-family:Consolas,"Segoe UI",monospace; }
        .hmi-title { height:26px; margin:-7px -10px 6px; padding:4px 10px; background:linear-gradient(90deg,#1f8fd6 0%,#58c5f4 46%,#dff7ff 100%); color:#fff; font-size:16px; line-height:18px; font-weight:900; letter-spacing:.2px; text-shadow:0 1px 2px rgba(0,0,0,.72),0 0 4px rgba(0,0,0,.42); }
        .scope-grid { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr); border-left:1px solid rgba(43,255,65,.32); border-top:1px solid rgba(43,255,65,.32); background-color:#15221c; }
        .scope-cell { min-width:0; height:calc(54vh - 86px); min-height:250px; max-height:310px; border-right:1px solid rgba(43,255,65,.32); border-bottom:1px solid rgba(43,255,65,.32); padding:6px 8px; position:relative; background:#15221c; box-sizing:border-box; display:flex; flex-direction:column; justify-content:center; }
        .scope-cell.wave { height:calc(46vh - 74px); min-height:190px; max-height:250px; }
        .dial-svg, .wave-svg { display:block; width:100%; height:100%; min-height:0; }
        .dial-svg { overflow:visible; }
        .scope-cell:not(.wave) .dial-svg { flex:1 1 auto; margin-top:2px; }
        .scope-cell.wave .wave-svg { flex:1 1 auto; }
        .dial-ring { fill:none; stroke:#18f42f; stroke-width:1.25; opacity:.82; }
        .dial-tick { stroke:#16ef32; stroke-width:.75; opacity:.68; }
        .dial-minor { stroke:#16ef32; stroke-width:.55; opacity:.36; }
        .scope-axis { stroke:#20ff36; stroke-width:1.2; marker-end:url(#scopeArrow); }
        .scope-gridline { stroke:#27ff3a; stroke-width:.75; opacity:.24; }
        .phasor-reference { stroke:#27ff3a; stroke-width:.9; stroke-dasharray:4 5; opacity:.42; }
        .scope-label { fill:#25ff3b; font:700 13px Consolas,"Segoe UI",monospace; }
        .scope-small { fill:#25ff3b; font:700 11px Consolas,"Segoe UI",monospace; }
        .dial-title { transform:translateX(-92px); }
        .scope-y-label { fill:#25ff3b; font:700 9px Consolas,"Segoe UI",monospace; opacity:.95; }
        .scope-tick { stroke:#20ff36; stroke-width:.9; opacity:.75; }
        .phase-red { stroke:#ff3131; fill:#ff3131; color:#ff3131; }
        .phase-yellow { stroke:#ffe84a; fill:#ffe84a; color:#ffe84a; }
        .phase-blue { stroke:#1678ff; fill:#1678ff; color:#1678ff; }
        .phase-vector { stroke-width:2.1; stroke-linecap:round; }
        .phase-arrow { stroke:none; }
        .phase-arrow.phase-red { fill:#ff3131; }
        .phase-arrow.phase-yellow { fill:#ffe84a; }
        .phase-arrow.phase-blue { fill:#1678ff; }
        .wave-line { fill:none; stroke-width:1.45; stroke-linecap:round; }
        .phase-legend { display:flex; align-items:center; gap:8px; margin:0; padding:0; font-size:13px; font-weight:900; color:#d8ffe0; }
        .phase-legend span { display:inline-flex; align-items:center; gap:5px; }
        .phase-dot { width:10px; height:10px; border-radius:50%; background:currentColor; box-shadow:0 0 8px currentColor; }
        .phase-tag { font:900 13px Consolas,"Segoe UI",monospace; text-anchor:middle; dominant-baseline:middle; paint-order:stroke; stroke:#15221c; stroke-width:4px; stroke-linejoin:round; }
        .wave-tag { font-size:12px; }
        .readout { position:absolute; top:44px; right:12px; display:grid; grid-template-columns:max-content max-content; justify-content:start; gap:7px 6px; margin:0; max-width:178px; font-weight:900; font-size:10.5px; line-height:1.15; white-space:nowrap; overflow:hidden; padding:8px 7px; background:rgba(21,34,28,.86); border-left:1px solid rgba(43,255,65,.28); z-index:2; }
        .readout span:nth-child(even) { text-align:left; }
        .wave-caption { position:absolute; top:8px; left:12px; color:#24ff39; font-size:12px; font-weight:800; }
        .empty-hmi { display:grid; place-items:center; min-height:calc(100vh - 150px); color:#20ff36; text-align:center; font-weight:800; }
        .note { margin-top:5px; color:#64748b; font-size:11px; line-height:1.35; }
        @media (max-height: 760px) {
            .phasor-shell { padding-top:4px; padding-bottom:4px; }
            .phasor-toolbar { min-height:28px; }
            .phasor-toolbar select { height:26px; }
            .phasor-hmi { padding:6px 8px 5px; }
            .hmi-title { height:23px; margin:-6px -8px 4px; padding:3px 9px; font-size:15px; line-height:17px; }
            .phase-legend { gap:6px; font-size:12px; }
            .readout { top:34px; right:8px; gap:5px 5px; max-width:166px; padding:6px 5px; font-size:9.8px; }
            .scope-cell { min-height:220px; }
            .scope-cell.wave { min-height:165px; }
            .note { display:none; }
        }
        @media (max-width: 900px) {
            .scope-grid { grid-template-columns:1fr; }
            .phasor-toolbar { align-items:flex-start; flex-direction:column; }
            .phasor-hmi { padding-right:8px; }
            .phase-legend { flex-direction:row; flex-wrap:wrap; margin-bottom:5px; padding:0 2px; background:transparent; border-left:0; }
            .readout { position:static; grid-template-columns:repeat(6, max-content); justify-content:center; margin:2px auto 0; max-width:100%; padding:0; background:transparent; border-left:0; }
            .scope-cell, .scope-cell.wave { height:auto; min-height:0; max-height:none; }
            .dial-svg, .wave-svg { height:auto; }
        }
    </style>
</head>
<body>
<div class="page-wrap phasor-shell">
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <div class="phasor-toolbar">
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
        <div class="muted">최근 수집: <span id="phasorRecentAt"><%= h(dateText(m.get("measured_at"), hideData)) %></span> / 자동 갱신 <span id="phasorRefreshSeconds"><%= refreshSeconds %></span>초</div>
    </div>

    <div class="phasor-hmi" id="phasorHmi">
        <div class="hmi-title">Phasor measurement</div>
        <% if (!hasData) { %>
        <div class="empty-hmi">
            <div>
                <div>측정 데이터가 없습니다.</div>
                <div style="font-size:12px;margin-top:8px;">UPS 등록 후 통신이 성공하면 위상도가 표시됩니다.</div>
            </div>
        </div>
        <% } else { %>
        <div class="scope-grid">
            <div class="scope-cell">
                <svg class="dial-svg" viewBox="0 0 370 305" role="img" aria-label="Voltage phasor">
                    <defs>
                        <marker id="scopeArrowVRed" viewBox="0 0 12 12" refX="10" refY="6" markerWidth="4.5" markerHeight="4.5" orient="auto">
                            <path d="M0 0 L12 6 L0 12 z" fill="#ff3131"></path>
                        </marker>
                        <marker id="scopeArrowVYellow" viewBox="0 0 12 12" refX="10" refY="6" markerWidth="4.5" markerHeight="4.5" orient="auto">
                            <path d="M0 0 L12 6 L0 12 z" fill="#ffe84a"></path>
                        </marker>
                        <marker id="scopeArrowVBlue" viewBox="0 0 12 12" refX="10" refY="6" markerWidth="4.5" markerHeight="4.5" orient="auto">
                            <path d="M0 0 L12 6 L0 12 z" fill="#1678ff"></path>
                        </marker>
                    </defs>
                    <text x="-12" y="10" class="scope-label dial-title">Nominal voltage</text>
                    <text x="-12" y="27" class="scope-small dial-title"><%= h(fmtUnit(m.get("output_voltage_l12"), 0, "V", hideData)) %> L-L</text>
                    <text x="180" y="10" text-anchor="middle" class="scope-small">90°</text>
                    <text x="344" y="154" class="scope-small">0°</text>
                    <text x="180" y="298" text-anchor="middle" class="scope-small">270°</text>
                    <text x="12" y="154" class="scope-small">180°</text>
                    <circle class="dial-ring" cx="180" cy="150" r="42"></circle>
                    <circle class="dial-ring" cx="180" cy="150" r="75"></circle>
                    <circle class="dial-ring" cx="180" cy="150" r="108"></circle>
                    <circle class="dial-ring" cx="180" cy="150" r="133"></circle>
                    <line class="scope-gridline" x1="47" y1="150" x2="313" y2="150"></line>
                    <line class="scope-gridline" x1="180" y1="17" x2="180" y2="283"></line>
                    <line class="phasor-reference" <%= line(dialCx, 150d, 133d, 0d) %>></line>
                    <line class="phasor-reference" <%= line(dialCx, 150d, 133d, 120d) %>></line>
                    <line class="phasor-reference" <%= line(dialCx, 150d, 133d, 240d) %>></line>
                    <line class="phase-vector phase-red" <%= line(dialCx, 150d, dialV1r, v1a) %> marker-end="url(#scopeArrowVRed)"></line>
                    <line class="phase-vector phase-yellow" <%= line(dialCx, 150d, dialV2r, v2a) %> marker-end="url(#scopeArrowVYellow)"></line>
                    <line class="phase-vector phase-blue" <%= line(dialCx, 150d, dialV3r, v3a) %> marker-end="url(#scopeArrowVBlue)"></line>
                    <polygon class="phase-arrow phase-red" points="<%= arrowHead(dialCx, 150d, dialV1r, v1a, 4.5d) %>"></polygon>
                    <polygon class="phase-arrow phase-yellow" points="<%= arrowHead(dialCx, 150d, dialV2r, v2a, 4.5d) %>"></polygon>
                    <polygon class="phase-arrow phase-blue" points="<%= arrowHead(dialCx, 150d, dialV3r, v3a, 4.5d) %>"></polygon>
                    <text class="phase-tag phase-red" <%= labelPos(dialCx, 150d, dialV1r + 13d, v1a) %>>L1</text>
                    <text class="phase-tag phase-yellow" <%= labelPos(dialCx, 150d, dialV2r + 13d, v2a) %>>L2</text>
                    <text class="phase-tag phase-blue" <%= labelPos(dialCx, 150d, dialV3r + 13d, v3a) %>>L3</text>
                    <circle cx="180" cy="150" r="4" fill="#dfffe0"></circle>
                </svg>
                <div class="readout">
                    <span class="phase-red">L12/R-S <%= fmtUnit(m.get("output_voltage_l12"), 0, "V", hideData) %></span><span class="phase-red"><%= phasorAngleText(v1a) %></span>
                    <span class="phase-yellow">L23/S-T <%= fmtUnit(m.get("output_voltage_l23"), 0, "V", hideData) %></span><span class="phase-yellow"><%= phasorAngleText(v2a) %></span>
                    <span class="phase-blue">L31/T-R <%= fmtUnit(m.get("output_voltage_l31"), 0, "V", hideData) %></span><span class="phase-blue"><%= phasorAngleText(v3a) %></span>
                </div>
            </div>
            <div class="scope-cell">
                <svg class="dial-svg" viewBox="0 0 370 305" role="img" aria-label="Current phasor">
                    <defs>
                        <marker id="scopeArrowIRed" viewBox="0 0 12 12" refX="10" refY="6" markerWidth="4.5" markerHeight="4.5" orient="auto">
                            <path d="M0 0 L12 6 L0 12 z" fill="#ff3131"></path>
                        </marker>
                        <marker id="scopeArrowIYellow" viewBox="0 0 12 12" refX="10" refY="6" markerWidth="4.5" markerHeight="4.5" orient="auto">
                            <path d="M0 0 L12 6 L0 12 z" fill="#ffe84a"></path>
                        </marker>
                        <marker id="scopeArrowIBlue" viewBox="0 0 12 12" refX="10" refY="6" markerWidth="4.5" markerHeight="4.5" orient="auto">
                            <path d="M0 0 L12 6 L0 12 z" fill="#1678ff"></path>
                        </marker>
                    </defs>
                    <text x="-12" y="10" class="scope-label dial-title">Max scale current</text>
                    <text x="-12" y="27" class="scope-small dial-title"><%= h(fmt(Double.valueOf(iMax), 1)) %>A</text>
                    <text x="180" y="10" text-anchor="middle" class="scope-small">90°</text>
                    <text x="344" y="154" class="scope-small">0°</text>
                    <text x="180" y="298" text-anchor="middle" class="scope-small">270°</text>
                    <text x="12" y="154" class="scope-small">180°</text>
                    <circle class="dial-ring" cx="180" cy="150" r="42"></circle>
                    <circle class="dial-ring" cx="180" cy="150" r="75"></circle>
                    <circle class="dial-ring" cx="180" cy="150" r="108"></circle>
                    <circle class="dial-ring" cx="180" cy="150" r="133"></circle>
                    <line class="scope-gridline" x1="47" y1="150" x2="313" y2="150"></line>
                    <line class="scope-gridline" x1="180" y1="17" x2="180" y2="283"></line>
                    <line class="phasor-reference" <%= line(dialCx, 150d, 133d, 0d) %>></line>
                    <line class="phasor-reference" <%= line(dialCx, 150d, 133d, 120d) %>></line>
                    <line class="phasor-reference" <%= line(dialCx, 150d, 133d, 240d) %>></line>
                    <line class="phase-vector phase-red" <%= line(dialCx, 150d, dialI1r, i1a) %> marker-end="url(#scopeArrowIRed)"></line>
                    <line class="phase-vector phase-yellow" <%= line(dialCx, 150d, dialI2r, i2a) %> marker-end="url(#scopeArrowIYellow)"></line>
                    <line class="phase-vector phase-blue" <%= line(dialCx, 150d, dialI3r, i3a) %> marker-end="url(#scopeArrowIBlue)"></line>
                    <polygon class="phase-arrow phase-red" points="<%= arrowHead(dialCx, 150d, dialI1r, i1a, 4.5d) %>"></polygon>
                    <polygon class="phase-arrow phase-yellow" points="<%= arrowHead(dialCx, 150d, dialI2r, i2a, 4.5d) %>"></polygon>
                    <polygon class="phase-arrow phase-blue" points="<%= arrowHead(dialCx, 150d, dialI3r, i3a, 4.5d) %>"></polygon>
                    <text class="phase-tag phase-red" <%= labelPos(dialCx, 150d, dialI1r + 13d, i1a) %>>L1</text>
                    <text class="phase-tag phase-yellow" <%= labelPos(dialCx, 150d, dialI2r + 13d, i2a) %>>L2</text>
                    <text class="phase-tag phase-blue" <%= labelPos(dialCx, 150d, dialI3r + 13d, i3a) %>>L3</text>
                    <circle cx="180" cy="150" r="4" fill="#dfffe0"></circle>
                </svg>
                <div class="readout">
                    <span class="phase-red">L1/R <%= fmtUnit(m.get("output_current_l1"), 0, "A", hideData) %></span><span class="phase-red"><%= currentPhasorAngleText(i1a, m.get("output_pf_l1"), hideData) %></span>
                    <span class="phase-yellow">L2/S <%= fmtUnit(m.get("output_current_l2"), 0, "A", hideData) %></span><span class="phase-yellow"><%= currentPhasorAngleText(i2a, m.get("output_pf_l2"), hideData) %></span>
                    <span class="phase-blue">L3/T <%= fmtUnit(m.get("output_current_l3"), 0, "A", hideData) %></span><span class="phase-blue"><%= currentPhasorAngleText(i3a, m.get("output_pf_l3"), hideData) %></span>
                </div>
            </div>
            <div class="scope-cell wave">
                <div class="wave-caption">V</div>
                <svg class="wave-svg" viewBox="0 0 360 240" role="img" aria-label="Voltage waveform">
                    <defs>
                        <marker id="scopeArrowWaveV" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
                            <path d="M0 0 L10 5 L0 10 z" fill="context-stroke"></path>
                        </marker>
                    </defs>
                    <line class="scope-axis" x1="38" y1="120" x2="330" y2="120" marker-end="url(#scopeArrowWaveV)"></line>
                    <line class="scope-axis" x1="38" y1="210" x2="38" y2="30" marker-end="url(#scopeArrowWaveV)"></line>
                    <line class="scope-gridline" x1="38" y1="35" x2="330" y2="35"></line>
                    <line class="scope-gridline" x1="38" y1="77.5" x2="330" y2="77.5"></line>
                    <line class="scope-gridline" x1="38" y1="162.5" x2="330" y2="162.5"></line>
                    <line class="scope-gridline" x1="38" y1="205" x2="330" y2="205"></line>
                    <line class="scope-gridline" x1="86.7" y1="30" x2="86.7" y2="212"></line>
                    <line class="scope-gridline" x1="135.3" y1="30" x2="135.3" y2="212"></line>
                    <line class="scope-gridline" x1="184" y1="30" x2="184" y2="212"></line>
                    <line class="scope-gridline" x1="232.7" y1="30" x2="232.7" y2="212"></line>
                    <line class="scope-gridline" x1="281.3" y1="30" x2="281.3" y2="212"></line>
                    <line class="scope-gridline" x1="330" y1="30" x2="330" y2="212"></line>
                    <line class="scope-tick" x1="34" y1="35" x2="42" y2="35"></line>
                    <line class="scope-tick" x1="34" y1="77.5" x2="42" y2="77.5"></line>
                    <line class="scope-tick" x1="34" y1="120" x2="42" y2="120"></line>
                    <line class="scope-tick" x1="34" y1="162.5" x2="42" y2="162.5"></line>
                    <line class="scope-tick" x1="34" y1="205" x2="42" y2="205"></line>
                    <text x="31" y="38" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(waveVTop, hideData) %></text>
                    <text x="31" y="80.5" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(waveVTop / 2d, hideData) %></text>
                    <text x="31" y="123" text-anchor="end" class="scope-y-label">0.0</text>
                    <text x="31" y="165.5" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(-waveVTop / 2d, hideData) %></text>
                    <text x="31" y="208" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(-waveVTop, hideData) %></text>
                    <path class="wave-line phase-red" d="<%= sinePath(38, 36, 292, 170, 0d, dbl(m.get("output_voltage_l12"), 0d), waveVTop) %>"></path>
                    <path class="wave-line phase-yellow" d="<%= sinePath(38, 36, 292, 170, -120d, dbl(m.get("output_voltage_l23"), 0d), waveVTop) %>"></path>
                    <path class="wave-line phase-blue" d="<%= sinePath(38, 36, 292, 170, 120d, dbl(m.get("output_voltage_l31"), 0d), waveVTop) %>"></path>
                    <text x="308" y="52" class="phase-tag wave-tag phase-red">L1</text>
                    <text x="308" y="120" class="phase-tag wave-tag phase-yellow">L2</text>
                    <text x="308" y="188" class="phase-tag wave-tag phase-blue">L3</text>
                </svg>
            </div>
            <div class="scope-cell wave">
                <div class="wave-caption">A</div>
                <svg class="wave-svg" viewBox="0 0 360 240" role="img" aria-label="Current waveform">
                    <defs>
                        <marker id="scopeArrowWaveI" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
                            <path d="M0 0 L10 5 L0 10 z" fill="context-stroke"></path>
                        </marker>
                    </defs>
                    <line class="scope-axis" x1="38" y1="120" x2="330" y2="120" marker-end="url(#scopeArrowWaveI)"></line>
                    <line class="scope-axis" x1="38" y1="210" x2="38" y2="30" marker-end="url(#scopeArrowWaveI)"></line>
                    <line class="scope-gridline" x1="38" y1="35" x2="330" y2="35"></line>
                    <line class="scope-gridline" x1="38" y1="77.5" x2="330" y2="77.5"></line>
                    <line class="scope-gridline" x1="38" y1="162.5" x2="330" y2="162.5"></line>
                    <line class="scope-gridline" x1="38" y1="205" x2="330" y2="205"></line>
                    <line class="scope-gridline" x1="86.7" y1="30" x2="86.7" y2="212"></line>
                    <line class="scope-gridline" x1="135.3" y1="30" x2="135.3" y2="212"></line>
                    <line class="scope-gridline" x1="184" y1="30" x2="184" y2="212"></line>
                    <line class="scope-gridline" x1="232.7" y1="30" x2="232.7" y2="212"></line>
                    <line class="scope-gridline" x1="281.3" y1="30" x2="281.3" y2="212"></line>
                    <line class="scope-gridline" x1="330" y1="30" x2="330" y2="212"></line>
                    <line class="scope-tick" x1="34" y1="35" x2="42" y2="35"></line>
                    <line class="scope-tick" x1="34" y1="77.5" x2="42" y2="77.5"></line>
                    <line class="scope-tick" x1="34" y1="120" x2="42" y2="120"></line>
                    <line class="scope-tick" x1="34" y1="162.5" x2="42" y2="162.5"></line>
                    <line class="scope-tick" x1="34" y1="205" x2="42" y2="205"></line>
                    <text x="31" y="38" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(waveITop, hideData) %></text>
                    <text x="31" y="80.5" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(waveITop / 2d, hideData) %></text>
                    <text x="31" y="123" text-anchor="end" class="scope-y-label">0.0</text>
                    <text x="31" y="165.5" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(-waveITop / 2d, hideData) %></text>
                    <text x="31" y="208" text-anchor="end" class="scope-y-label"><%= waveAxisLabel(-waveITop, hideData) %></text>
                    <path class="wave-line phase-red" d="<%= sinePath(38, 36, 292, 170, i1a, dbl(m.get("output_current_l1"), 0d), waveITop) %>"></path>
                    <path class="wave-line phase-yellow" d="<%= sinePath(38, 36, 292, 170, i2a, dbl(m.get("output_current_l2"), 0d), waveITop) %>"></path>
                    <path class="wave-line phase-blue" d="<%= sinePath(38, 36, 292, 170, i3a, dbl(m.get("output_current_l3"), 0d), waveITop) %>"></path>
                    <text x="308" y="52" class="phase-tag wave-tag phase-red">L1</text>
                    <text x="308" y="120" class="phase-tag wave-tag phase-yellow">L2</text>
                    <text x="308" y="188" class="phase-tag wave-tag phase-blue">L3</text>
                </svg>
            </div>
        </div>
        <% } %>
    </div>
    <div class="note">역률 기반 추정 위상도입니다. 별도의 leading/lagging 정보가 없으면 전류가 전압보다 늦는 지상(lagging) 부하로 가정합니다.</div>
</div>
<script>
(function () {
    var hmi = document.getElementById('phasorHmi');
    var recent = document.getElementById('phasorRecentAt');
    var form = document.querySelector('.phasor-toolbar form');
    var refreshMs = Math.max(1000, <%= refreshSeconds %> * 1000);
    if (!hmi || !window.fetch || !window.DOMParser) return;
    var busy = false;
    var lastOk = Date.now();
    function selectedUpsId() {
        var params = new URLSearchParams(window.location.search);
        var select = form ? form.querySelector('select[name="ups_id"]') : null;
        return (select && select.value) || params.get('ups_id') || '';
    }
    function refreshPhasor() {
        if (busy || document.hidden) return;
        var select = form ? form.querySelector('select[name="ups_id"]') : null;
        if (select && document.activeElement === select) return;
        busy = true;
        var url = 'phasor_diagram.jsp?_=' + Date.now();
        var upsId = selectedUpsId();
        if (upsId) url += '&ups_id=' + encodeURIComponent(upsId);
        fetch(url, {cache:'no-store', headers:{'X-Requested-With':'fetch'}})
            .then(function (response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.text();
            })
            .then(function (html) {
                var doc = new DOMParser().parseFromString(html, 'text/html');
                var nextHmi = doc.getElementById('phasorHmi');
                var nextRecent = doc.getElementById('phasorRecentAt');
                if (nextHmi) {
                    hmi.innerHTML = nextHmi.innerHTML;
                    lastOk = Date.now();
                }
                if (recent && nextRecent) {
                    recent.textContent = nextRecent.textContent;
                }
            })
            .catch(function () {
                if (Date.now() - lastOk > 30000) window.location.reload();
            })
            .finally(function () {
                busy = false;
            });
    }
    setInterval(refreshPhasor, refreshMs);
})();
</script>
</body>
</html>

