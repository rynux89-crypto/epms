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
String allEventsUrl = "1".equals(request.getParameter("embed")) ? "event_view.jsp?embed=1" : "event_view.jsp";

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
        .event-table { min-width:1040px; }
        .event-table .col-id { width:72px; }
        .event-table .col-ups { width:150px; }
        .event-table .col-severity { width:98px; }
        .event-table .col-message { width:auto; }
        .event-table .col-time { width:178px; }
        .event-table .col-status { width:90px; }
        .event-table th:nth-child(4), .event-table td:nth-child(4) { text-align:left; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-title"><h2>UPS 이벤트</h2></div>
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>
    <form class="event-filter" method="get" id="eventFilter">
        <% if ("1".equals(request.getParameter("embed"))) { %><input type="hidden" name="embed" value="1"><% } %>
        <label for="ups">UPS 검색</label>
        <input id="ups" name="ups" value="<%= h(searchText) %>" placeholder="UPS 이름, 위치, IP, 이벤트">
        <label for="from">시작</label>
        <input id="from" name="from" type="datetime-local" value="<%= h(eventModel.fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" name="to" type="datetime-local" value="<%= h(eventModel.toRaw) %>" <%= eventModel.explicitTo ? "" : "data-auto-now=\"1\"" %>>
        <button type="submit">검색</button>
        <button type="button" onclick="location.href='<%= h(allEventsUrl) %>'">전체</button>
        <button type="submit" name="export" value="csv">CSV 다운로드</button>
        <span class="event-count" id="eventCount">조회 <%= rows.size() %>건</span>
    </form>
    <div class="ups-list-wrap" id="eventContent">
        <table class="data-table ups-list-table event-table">
            <colgroup>
                <col class="col-id"><col class="col-ups"><col class="col-severity"><col class="col-message"><col class="col-time"><col class="col-status">
            </colgroup>
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
    function refreshEvent() {
        if (!form || document.hidden || !window.fetch || !window.DOMParser) return;
        updateAutoNow();
        var params = new URLSearchParams(new FormData(form));
        if (new URLSearchParams(window.location.search).get('embed') === '1') params.set('embed', '1');
        fetch(window.location.pathname + '?' + params.toString(), {cache:'no-store', headers:{'X-Requested-With':'fetch'}})
            .then(function (response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.text();
            })
            .then(function (html) {
                var doc = new DOMParser().parseFromString(html, 'text/html');
                var nextContent = doc.getElementById('eventContent');
                var nextCount = doc.getElementById('eventCount');
                var content = document.getElementById('eventContent');
                var count = document.getElementById('eventCount');
                if (nextContent && content) content.innerHTML = nextContent.innerHTML;
                if (nextCount && count) count.textContent = nextCount.textContent;
            })
            .catch(function () {});
    }
    setInterval(refreshEvent, refreshMs);
})();
</script>
</body>
</html>
