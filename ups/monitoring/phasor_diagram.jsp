<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
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

    private double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }

    private double pfAngle(Object pf) {
        if (pf == null) return 0d;
        return Math.toDegrees(Math.acos(clamp(Math.abs(dbl(pf, 1d)), 0d, 1d)));
    }

    private String readUrl(String urlText, int timeoutMs) {
        return epms.util.UpsSimulatorSupport.readUrl(urlText, timeoutMs);
    }

    private void putJsonDecimal(Map<String, Object> target, String json, String jsonKey, String metricKey) {
        epms.util.UpsSimulatorSupport.putJsonDecimal(target, json, jsonKey, metricKey);
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

    private String dateText(Object value) {
        if (value == null) return "수집 데이터 없음";
        return epms.util.UpsFormatSupport.displaySlashDateTime(value);
    }

    private String dateText(Object value, boolean hide) {
        return hide ? "-" : dateText(value);
    }

    private boolean commBad(Map<String, Object> selected) {
        if (selected == null || selected.get("last_comm_status") == null) return false;
        String comm = String.valueOf(selected.get("last_comm_status"));
        return !("OK".equalsIgnoreCase(comm) || "NORMAL".equalsIgnoreCase(comm) || "ONLINE".equalsIgnoreCase(comm));
    }

    private String angleText(Object pf, boolean hide) {
        return hide || pf == null ? "-" : fmt(pfAngle(pf), 1) + "\u00B0";
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String err = null;
String selectedId = request.getParameter("ups_id");
List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
Map<String, Object> selected = null;
Map<String, Object> m = new HashMap<String, Object>();
boolean simulatorLive = false;

try {
    devices = epms.ups.UpsQueryService.listDevicesWithProfile();
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
        m = epms.ups.UpsQueryService.latestPhasorMeasurement(selectedId);
    }
} catch (Exception e) {
    err = e.getMessage();
}

if (epms.util.UpsSimulatorSupport.isSimulatorDevice(selected)) {
    String simStatus = epms.util.UpsSimulatorSupport.readStatus(250);
    if (simStatus != null && !simStatus.trim().isEmpty()) {
        simulatorLive = true;
        putJsonDecimal(m, simStatus, "output_voltage_l12", "output_voltage_l12");
        putJsonDecimal(m, simStatus, "output_voltage_l23", "output_voltage_l23");
        putJsonDecimal(m, simStatus, "output_voltage_l31", "output_voltage_l31");
        putJsonDecimal(m, simStatus, "output_current_l1", "output_current_l1");
        putJsonDecimal(m, simStatus, "output_current_l2", "output_current_l2");
        putJsonDecimal(m, simStatus, "output_current_l3", "output_current_l3");
        putJsonDecimal(m, simStatus, "output_pf_l1", "output_pf_l1");
        putJsonDecimal(m, simStatus, "output_pf_l2", "output_pf_l2");
        putJsonDecimal(m, simStatus, "output_pf_l3", "output_pf_l3");
        m.put("measured_at", new java.sql.Timestamp(System.currentTimeMillis()));
    }
}

boolean hideData = commBad(selected) && !simulatorLive;
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
boolean hasData = !hideData && m.get("measured_at") != null;
%>
<!doctype html>
<html>
<head>
    <title>UPS Phasor Diagram</title>
    <meta http-equiv="refresh" content="5">
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body { background:#f2f4f7; }
        .phasor-shell { max-width:1060px; margin:0 auto; }
        .phasor-toolbar { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:12px; }
        .phasor-toolbar select { min-width:260px; padding:8px 10px; border:1px solid #9aa3ad; border-radius:6px; background:#fff; }
        .phasor-layout { display:grid; grid-template-columns:minmax(0, 1fr) 300px; gap:14px; align-items:start; }
        .phasor-panel { background:#fff; border:1px solid #d7e1ec; border-radius:8px; padding:14px; }
        .phasor-svg { width:100%; max-width:680px; display:block; margin:0 auto; }
        .axis { stroke:#c4d0dd; stroke-width:1.2; }
        .grid { fill:none; stroke:#aebdcb; stroke-width:1.4; stroke-dasharray:4 4; }
        .vline { stroke-width:4; marker-end:url(#arrow); }
        .iline { stroke-width:3; stroke-dasharray:9 6; marker-end:url(#arrow); }
        .l1 { stroke:#1267b1; color:#1267b1; fill:#1267b1; }
        .l2 { stroke:#b42318; color:#b42318; fill:#b42318; }
        .l3 { stroke:#16794c; color:#16794c; fill:#16794c; }
        .svg-label { font:700 14px "Segoe UI", Arial, sans-serif; }
        .legend { display:flex; flex-wrap:wrap; gap:10px 18px; justify-content:center; color:#334155; font-size:13px; margin-top:8px; }
        .legend span { display:inline-flex; align-items:center; gap:6px; }
        .swatch { width:22px; height:0; border-top:4px solid currentColor; }
        .swatch.current { border-top-style:dashed; }
        .phase-card { border:1px solid #e0e8f1; border-radius:8px; padding:12px; margin-bottom:10px; }
        .phase-card h3 { margin:0 0 10px; font-size:18px; }
        .phase-row { display:flex; justify-content:space-between; gap:12px; font-size:14px; line-height:1.8; }
        .phase-row strong { color:#0f172a; }
        .note { margin-top:10px; color:#64748b; font-size:12px; line-height:1.55; }
        @media (max-width: 900px) {
            .phasor-layout { grid-template-columns:1fr; }
            .phasor-toolbar { align-items:flex-start; flex-direction:column; }
        }
    </style>
</head>
<body>
<div class="page-wrap phasor-shell">
    <div class="title-bar">
        <div>
            <h2>UPS Phasor Diagram</h2>
            <p class="muted">출력 전압과 역률을 기준으로 전류 위상을 추정합니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='ups_status.jsp'">실시간 상태</button>
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

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
        <div class="muted">최근 수집: <%= h(dateText(m.get("measured_at"), hideData)) %> / 자동 갱신 5초</div>
    </div>

    <div class="phasor-layout">
        <div class="phasor-panel">
            <svg class="phasor-svg" viewBox="0 0 660 500" role="img" aria-label="UPS phasor diagram">
                <defs>
                    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                        <path d="M 0 0 L 10 5 L 0 10 z" fill="context-stroke"></path>
                    </marker>
                </defs>
                <circle class="grid" cx="330" cy="250" r="50"></circle>
                <circle class="grid" cx="330" cy="250" r="100"></circle>
                <circle class="grid" cx="330" cy="250" r="150"></circle>
                <circle class="grid" cx="330" cy="250" r="200"></circle>
                <line class="axis" x1="90" y1="250" x2="570" y2="250"></line>
                <line class="axis" x1="330" y1="30" x2="330" y2="470"></line>
                <line class="axis" x1="160" y1="420" x2="500" y2="80"></line>
                <line class="axis" x1="160" y1="80" x2="500" y2="420"></line>

                <% if (hasData) { %>
                <line class="vline l1" <%= line(cx, cy, v1r, v1a) %>></line>
                <line class="vline l2" <%= line(cx, cy, v2r, v2a) %>></line>
                <line class="vline l3" <%= line(cx, cy, v3r, v3a) %>></line>
                <line class="iline l1" <%= line(cx, cy, i1r, i1a) %>></line>
                <line class="iline l2" <%= line(cx, cy, i2r, i2a) %>></line>
                <line class="iline l3" <%= line(cx, cy, i3r, i3a) %>></line>

                <text class="svg-label l1" <%= labelPos(cx, cy, v1r + 18d, v1a) %>>V1</text>
                <text class="svg-label l2" <%= labelPos(cx, cy, v2r + 18d, v2a) %>>V2</text>
                <text class="svg-label l3" <%= labelPos(cx, cy, v3r + 18d, v3a) %>>V3</text>
                <text class="svg-label l1" <%= labelPos(cx, cy, i1r + 18d, i1a) %>>I1</text>
                <text class="svg-label l2" <%= labelPos(cx, cy, i2r + 18d, i2a) %>>I2</text>
                <text class="svg-label l3" <%= labelPos(cx, cy, i3r + 18d, i3a) %>>I3</text>
                <% } else { %>
                <text x="330" y="248" text-anchor="middle" class="svg-label" fill="#64748b">측정 데이터가 없습니다.</text>
                <text x="330" y="276" text-anchor="middle" fill="#94a3b8" style="font:13px 'Segoe UI', Arial, sans-serif;">UPS 등록 후 통신이 성공하면 위상도가 표시됩니다.</text>
                <% } %>
            </svg>
            <div class="legend">
                <span><i class="swatch"></i>전압 벡터</span>
                <span><i class="swatch current"></i>전류 벡터</span>
                <span class="l1"><i class="swatch"></i>L1</span>
                <span class="l2"><i class="swatch"></i>L2</span>
                <span class="l3"><i class="swatch"></i>L3</span>
            </div>
            <div class="note">역률 기반 추정 위상도입니다. 별도의 leading/lagging 정보가 없으면 전류가 전압보다 늦는 지상(lagging) 부하로 가정합니다.</div>
        </div>

        <div>
            <div class="phase-card">
                <h3 class="l1">L1</h3>
                <div class="phase-row"><span>전압</span><strong><%= fmtUnit(m.get("output_voltage_l12"), 0, "V", hideData) %></strong></div>
                <div class="phase-row"><span>전류</span><strong><%= fmtUnit(m.get("output_current_l1"), 0, "A", hideData) %></strong></div>
                <div class="phase-row"><span>역률</span><strong><%= fmt(m.get("output_pf_l1"), 2, hideData) %></strong></div>
                <div class="phase-row"><span>추정 위상각</span><strong><%= angleText(m.get("output_pf_l1"), hideData) %></strong></div>
            </div>
            <div class="phase-card">
                <h3 class="l2">L2</h3>
                <div class="phase-row"><span>전압</span><strong><%= fmtUnit(m.get("output_voltage_l23"), 0, "V", hideData) %></strong></div>
                <div class="phase-row"><span>전류</span><strong><%= fmtUnit(m.get("output_current_l2"), 0, "A", hideData) %></strong></div>
                <div class="phase-row"><span>역률</span><strong><%= fmt(m.get("output_pf_l2"), 2, hideData) %></strong></div>
                <div class="phase-row"><span>추정 위상각</span><strong><%= angleText(m.get("output_pf_l2"), hideData) %></strong></div>
            </div>
            <div class="phase-card">
                <h3 class="l3">L3</h3>
                <div class="phase-row"><span>전압</span><strong><%= fmtUnit(m.get("output_voltage_l31"), 0, "V", hideData) %></strong></div>
                <div class="phase-row"><span>전류</span><strong><%= fmtUnit(m.get("output_current_l3"), 0, "A", hideData) %></strong></div>
                <div class="phase-row"><span>역률</span><strong><%= fmt(m.get("output_pf_l3"), 2, hideData) %></strong></div>
                <div class="phase-row"><span>추정 위상각</span><strong><%= angleText(m.get("output_pf_l3"), hideData) %></strong></div>
            </div>
        </div>
    </div>
</div>
</body>
</html>
