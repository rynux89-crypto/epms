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
boolean activeOnly = "ACTIVE".equalsIgnoreCase(request.getParameter("status"));
epms.util.UpsDateRangeSupport.DateRange range = epms.util.UpsDateRangeSupport.lastDays(request, 1);
epms.ups.UpsAlarmListPageModel alarmModel = epms.ups.UpsAlarmListPageService.build(upsSearch, range, activeOnly);
String err = alarmModel.err;
String searchText = alarmModel.searchText;
List<Map<String, Object>> rows = alarmModel.rows;

if ("csv".equalsIgnoreCase(export)) {
    epms.util.CsvDownloadSupport.begin(response, out, "ups_alarm_history.csv");
    epms.util.CsvDownloadSupport.writeRow(out, "ID", "UPS", "Severity", "Message", "Occurred At", "Cleared At", "Status");
    for (Map<String, Object> r : rows) {
        epms.util.CsvDownloadSupport.writeRow(out, r.get("alarm_id"), r.get("ups_name"), r.get("severity"), r.get("alarm_message"), displayDateTime(r.get("occurred_at")), displayDateTime(r.get("cleared_at")), r.get("status"));
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 알람</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        .alarm-filter { display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin:0 0 12px; padding:12px; background:#fff; border:1px solid #dbe5f2; border-radius:8px; }
        .alarm-filter label { font-size:13px; color:#475569; font-weight:800; }
        .alarm-filter input { min-width:260px; padding:8px 10px; border:1px solid #cbd8e6; border-radius:6px; }
        .alarm-filter input[type="datetime-local"] { min-width:190px; }
        .alarm-filter button { padding:8px 12px; }
        .alarm-count { color:#64748b; font-size:13px; }
        .alarm-table { min-width:1180px; }
        .alarm-table .col-id { width:72px; }
        .alarm-table .col-ups { width:150px; }
        .alarm-table .col-severity { width:98px; }
        .alarm-table .col-message { width:auto; }
        .alarm-table .col-time { width:178px; }
        .alarm-table .col-status { width:90px; }
        .alarm-table th:nth-child(4), .alarm-table td:nth-child(4) { text-align:left; }
    </style>
</head>
<body>
<div class="page-wrap">
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>
    <form class="alarm-filter" method="get" id="alarmFilter">
        <% if (alarmModel.activeOnly) { %><input type="hidden" id="activeStatus" name="status" value="ACTIVE"><% } %>
        <label for="ups">UPS 검색</label>
        <input id="ups" name="ups" value="<%= h(searchText) %>" placeholder="UPS 이름, 위치, IP, 알람">
        <label for="from">시작</label>
        <input id="from" name="from" type="datetime-local" value="<%= h(alarmModel.fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" name="to" type="datetime-local" value="<%= h(alarmModel.toRaw) %>" <%= alarmModel.explicitTo ? "" : "data-auto-now=\"1\"" %>>
        <button type="submit" data-alarm-action="search">검색</button>
        <button type="submit" name="status" value="ACTIVE" data-alarm-action="active">활성알람만</button>
        <button type="submit" name="export" value="csv" data-alarm-action="export">CSV 다운로드</button>
        <span class="alarm-count" id="alarmCount"><%= alarmModel.activeOnly ? "활성알람만" : "전체" %> <%= rows.size() %>건</span>
    </form>
    <div class="ups-list-wrap" id="alarmContent">
        <table class="data-table ups-list-table alarm-table">
            <colgroup>
                <col class="col-id"><col class="col-ups"><col class="col-severity"><col class="col-message"><col class="col-time"><col class="col-time"><col class="col-status">
            </colgroup>
            <thead><tr><th>ID</th><th>UPS</th><th>등급</th><th>메시지</th><th>발생</th><th>해제</th><th>상태</th></tr></thead>
            <tbody>
            <% if (rows.isEmpty()) { %><tr><td colspan="7">알람 이력이 없습니다.</td></tr><% } %>
            <% for (Map<String, Object> r : rows) { %>
            <tr>
                <td><%= h(r.get("alarm_id")) %></td>
                <td><%= h(r.get("ups_name")) %></td>
                <td><%= h(r.get("severity")) %></td>
                <td><%= h(r.get("alarm_message")) %></td>
                <td><%= h(displayDateTime(r.get("occurred_at"))) %></td>
                <td><%= h(displayDateTime(r.get("cleared_at"))) %></td>
                <td><%= h(r.get("status")) %></td>
            </tr>
            <% } %>
            </tbody>
        </table>
    </div>
</div>
<script>
(function () {
    var form = document.getElementById('alarmFilter');
    var to = document.getElementById('to');
    var refreshMs = 5000;
    var submitAction = '';
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
    if (form) {
        form.addEventListener('click', function (event) {
            var button = event.target.closest('button[type="submit"]');
            submitAction = button ? (button.getAttribute('data-alarm-action') || '') : '';
        });
        form.addEventListener('submit', function () {
            var activeStatus = document.getElementById('activeStatus');
            if (activeStatus && submitAction === 'search') {
                activeStatus.parentNode.removeChild(activeStatus);
            }
        });
    }
    function refreshAlarm() {
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
                var nextContent = doc.getElementById('alarmContent');
                var nextCount = doc.getElementById('alarmCount');
                var content = document.getElementById('alarmContent');
                var count = document.getElementById('alarmCount');
                if (nextContent && content) content.innerHTML = nextContent.innerHTML;
                if (nextCount && count) count.textContent = nextCount.textContent;
            })
            .catch(function () {});
    }
    setInterval(refreshAlarm, refreshMs);
})();
</script>
</body>
</html>
