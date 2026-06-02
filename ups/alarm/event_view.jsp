<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private Timestamp parseDateTime(String raw, boolean endOfMinute) {
        return epms.util.UpsFormatSupport.parseDateTime(raw, endOfMinute);
    }

    private String htmlDateTime(java.util.Calendar cal) {
        return epms.util.UpsFormatSupport.htmlDateTime(cal);
    }

    private String displayDateTime(Object value) {
        return epms.util.UpsFormatSupport.displayDateTime(value);
    }

    private String csv(Object value) {
        if (value == null) return "";
        String s = String.valueOf(value).replace("\r", " ").replace("\n", " ");
        if (s.startsWith("=") || s.startsWith("+") || s.startsWith("-") || s.startsWith("@")) {
            s = "'" + s;
        }
        if (s.indexOf(',') >= 0 || s.indexOf('"') >= 0) {
            s = "\"" + s.replace("\"", "\"\"") + "\"";
        }
        return s;
    }

    private String displayEventMessage(Object value) {
        if (value == null) return "";
        return String.valueOf(value).replace("차단기 ", "").replace("차단기", "").trim();
    }

    private String readUrl(String urlText, int timeoutMs) {
        return epms.util.UpsSimulatorSupport.readUrl(urlText, timeoutMs);
    }

    private String jsonText(String json, String key, String fallback) {
        return epms.util.UpsSimulatorSupport.jsonText(json, key, fallback);
    }

    private String scenarioLabel(String s) {
        return epms.util.UpsFormatSupport.scenarioLabel(s);
    }

    private void syncSimulatorScenarioEvent(javax.servlet.ServletContext app) {
        if (app == null) return;
        String simStatus = readUrl("http://127.0.0.1:1503/api/status", 250);
        String current = jsonText(simStatus, "scenario", "");
        if (current.isEmpty()) return;
        synchronized (app) {
            Object oldValue = app.getAttribute("ups.simulator.scenario");
            app.setAttribute("ups.simulator.scenario", current);
            if (!(oldValue instanceof String)) {
                if (!"normal".equals(current)) insertScenarioEvent("", current);
                return;
            }
            String previous = (String) oldValue;
            if (previous.equals(current)) return;
            insertScenarioEvent(previous, current);
        }
    }

    private void insertScenarioEvent(String before, String after) {
        String message = before == null || before.isEmpty()
            ? scenarioLabel(after)
            : scenarioLabel(before) + " -> " + scenarioLabel(after);
        try (Connection conn = openUpsDbConnection()) {
            Integer upsId = null;
            try (PreparedStatement find = conn.prepareStatement(
                    "SELECT TOP 1 ups_id FROM dbo.ups_device WHERE ip_address='127.0.0.1' AND modbus_port=1502 AND unit_id=1 ORDER BY ups_id")) {
                try (ResultSet rs = find.executeQuery()) {
                    if (rs.next()) upsId = Integer.valueOf(rs.getInt("ups_id"));
                }
            }
            if (upsId == null) return;
            try (PreparedStatement dup = conn.prepareStatement(
                    "SELECT TOP 1 1 FROM dbo.ups_alarm_log WHERE ups_id=? AND rule_code='UPS_SCENARIO_CHANGE' AND alarm_message=? AND status='EVENT' AND occurred_at >= DATEADD(second, -15, sysdatetime())")) {
                dup.setInt(1, upsId.intValue());
                dup.setString(2, message);
                try (ResultSet rs = dup.executeQuery()) {
                    if (rs.next()) return;
                }
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) VALUES (?, 'UPS_SCENARIO_CHANGE', 'ups_operation_mode', 'INFO', ?, sysdatetime(), 'EVENT')")) {
                ps.setInt(1, upsId.intValue());
                ps.setString(2, message);
                ps.executeUpdate();
            }
        } catch (Exception ignore) {
        }
    }
%>
<%
request.setCharacterEncoding("UTF-8");
epms.ups.UpsQueryService.syncSimulatorScenarioEvent(application);
List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
String err = null;
String upsSearch = request.getParameter("ups");
String searchText = upsSearch == null ? "" : upsSearch.trim();
String normalizedSearchText = searchText.replaceAll("\\s+", "");
String fromRaw = request.getParameter("from");
String toRaw = request.getParameter("to");
String export = request.getParameter("export");
boolean explicitTo = toRaw != null && !toRaw.trim().isEmpty();
java.util.Calendar nowCal = java.util.Calendar.getInstance();
String defaultTo = htmlDateTime(nowCal);
java.util.Calendar fromCal = (java.util.Calendar) nowCal.clone();
fromCal.add(java.util.Calendar.DAY_OF_MONTH, -1);
String defaultFrom = htmlDateTime(fromCal);
if (fromRaw == null || fromRaw.trim().isEmpty()) fromRaw = defaultFrom;
if (toRaw == null || toRaw.trim().isEmpty()) toRaw = defaultTo;
Timestamp fromTs = parseDateTime(fromRaw, false);
Timestamp toTs = parseDateTime(toRaw, true);
try {
    rows = epms.ups.UpsQueryService.eventRows(searchText, fromTs, toTs);
} catch (Exception e) {
    err = e.getMessage();
}
if ("csv".equalsIgnoreCase(export)) {
    response.reset();
    response.setCharacterEncoding("UTF-8");
    response.setContentType("text/csv;charset=UTF-8");
    response.setHeader("Content-Disposition", "attachment; filename=\"ups_event_history.csv\"");
    out.print("\uFEFF");
    out.println("ID,UPS,Severity,Message,Occurred At,Status");
    for (Map<String, Object> r : rows) {
        out.println(
            csv(r.get("alarm_id")) + "," +
            csv(r.get("ups_name")) + "," +
            csv(r.get("severity")) + "," +
            csv(displayEventMessage(r.get("alarm_message"))) + "," +
            csv(displayDateTime(r.get("occurred_at"))) + "," +
            csv(r.get("status"))
        );
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 이벤트</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .event-filter { display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin:0 0 12px; padding:12px; background:#fff; border:1px solid #dbe5f2; border-radius:8px; }
        .event-filter label { font-size:13px; color:#475569; font-weight:800; }
        .event-filter input { min-width:260px; padding:8px 10px; border:1px solid #cbd8e6; border-radius:6px; }
        .event-filter input[type="datetime-local"] { min-width:190px; }
        .event-filter button { padding:8px 12px; }
        .event-count { color:#64748b; font-size:13px; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div><h2>UPS 이벤트</h2><p class="muted">시나리오 변경, 스위치 조작 등 순간 이벤트 200건을 표시합니다.</p></div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='alarm_view.jsp'">알람</button>
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>
    <form class="event-filter" method="get" id="eventFilter">
        <label for="ups">UPS 검색</label>
        <input id="ups" name="ups" value="<%= h(searchText) %>" placeholder="UPS 이름, 위치, IP, 이벤트">
        <label for="from">시작</label>
        <input id="from" name="from" type="datetime-local" value="<%= h(fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" name="to" type="datetime-local" value="<%= h(toRaw) %>" <%= explicitTo ? "" : "data-auto-now=\"1\"" %>>
        <button type="submit">검색</button>
        <button type="submit" name="export" value="csv">CSV 다운로드</button>
        <button type="button" onclick="location.href='event_view.jsp'">전체</button>
        <span class="event-count">조회 <%= rows.size() %>건</span>
    </form>
    <div class="panel">
        <table class="data-table">
            <thead><tr><th>ID</th><th>UPS</th><th>등급</th><th>메시지</th><th>발생</th><th>상태</th></tr></thead>
            <tbody>
            <% if (rows.isEmpty()) { %><tr><td colspan="6">이벤트 이력이 없습니다.</td></tr><% } %>
            <% for (Map<String, Object> r : rows) { %>
            <tr>
                <td><%= h(r.get("alarm_id")) %></td>
                <td><%= h(r.get("ups_name")) %></td>
                <td><%= h(r.get("severity")) %></td>
                <td><%= h(displayEventMessage(r.get("alarm_message"))) %></td>
                <td><%= h(displayDateTime(r.get("occurred_at"))) %></td>
                <td><%= h(r.get("status")) %></td>
            </tr>
            <% } %>
            </tbody>
        </table>
    </div>
</div>
<script>
(function () {
    var form = document.getElementById('eventFilter');
    var to = document.getElementById('to');
    var refreshMs = 5000;
    function pad(n) { return n < 10 ? '0' + n : '' + n; }
    function nowValue() {
        var d = new Date();
        return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
    function updateAutoNow() {
        if (to && to.dataset.autoNow === '1') to.value = nowValue();
    }
    if (to) {
        to.addEventListener('input', function () { delete to.dataset.autoNow; });
        updateAutoNow();
        setInterval(updateAutoNow, 1000);
    }
    setInterval(function () {
        if (!form || document.hidden) return;
        updateAutoNow();
        form.submit();
    }, refreshMs);
})();
</script>
</body>
</html>
