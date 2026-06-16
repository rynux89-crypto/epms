<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String displayDateTime(Object value) {
        return epms.util.UpsFormatSupport.displayDateTime(value);
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String upsSearch = request.getParameter("ups");
String export = request.getParameter("export");
epms.util.UpsDateRangeSupport.DateRange range = epms.util.UpsDateRangeSupport.lastDays(request, 30);
epms.ups.UpsAlarmEventPageModel eventModel = epms.ups.UpsAlarmEventPageService.events(upsSearch, range, application);
String err = eventModel.err;
String searchText = eventModel.searchText;
List<Map<String, Object>> rows = eventModel.rows;

if ("csv".equalsIgnoreCase(export)) {
    epms.util.CsvDownloadSupport.begin(response, out, "ups_event_history.csv");
    epms.util.CsvDownloadSupport.writeRow(out, "ID", "UPS", "Severity", "Message", "Occurred At", "Status");
    for (Map<String, Object> r : rows) {
        epms.util.CsvDownloadSupport.writeRow(out, r.get("alarm_id"), r.get("ups_name"), r.get("severity"), epms.util.UpsEventFormatSupport.displayEventMessage(r.get("alarm_message")), displayDateTime(r.get("occurred_at")), r.get("status"));
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 이벤트</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
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
        <div><h2>UPS 이벤트</h2><p class="muted">스위치 조작, 운전 상태 변경 등 최근 이벤트 이력을 표시합니다.</p></div>
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
        <input id="from" name="from" type="datetime-local" value="<%= h(eventModel.fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" name="to" type="datetime-local" value="<%= h(eventModel.toRaw) %>" <%= eventModel.explicitTo ? "" : "data-auto-now=\"1\"" %>>
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
                <td><%= h(epms.util.UpsEventFormatSupport.displayEventMessage(r.get("alarm_message"))) %></td>
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
<%@ include file="../includes/ups_footer.jspf" %>
</body>
</html>
