<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private int parseLimit(String raw) {
        try {
            int n = Integer.parseInt(raw == null ? "" : raw.trim());
            if (n == 100 || n == 200 || n == 500 || n == 1000) return n;
        } catch (Exception ignore) {
        }
        return 200;
    }

    private String csv(Object value) {
        if (value == null) return "";
        String s = String.valueOf(value).replace("\r", " ").replace("\n", " ");
        if (s.startsWith("=") || s.startsWith("+") || s.startsWith("-") || s.startsWith("@")) s = "'" + s;
        if (s.indexOf(',') >= 0 || s.indexOf('"') >= 0) {
            s = "\"" + s.replace("\"", "\"\"") + "\"";
        }
        return s;
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String err = null;
String selectedId = request.getParameter("ups_id");
String upsSearch = request.getParameter("ups");
String searchText = upsSearch == null ? "" : upsSearch.trim();
String normalizedSearchText = searchText.replaceAll("\\s+", "");
String fromRaw = request.getParameter("from");
String toRaw = request.getParameter("to");
boolean explicitTo = toRaw != null && !toRaw.trim().isEmpty();
String export = request.getParameter("export");
int limit = parseLimit(request.getParameter("limit"));
java.util.Calendar nowCal = java.util.Calendar.getInstance();
String defaultTo = epms.util.UpsFormatSupport.htmlDateTime(nowCal);
java.util.Calendar fromCal = (java.util.Calendar) nowCal.clone();
fromCal.add(java.util.Calendar.DAY_OF_MONTH, -1);
String defaultFrom = epms.util.UpsFormatSupport.htmlDateTime(fromCal);
if (fromRaw == null || fromRaw.trim().isEmpty()) fromRaw = defaultFrom;
if (toRaw == null || toRaw.trim().isEmpty()) toRaw = defaultTo;
Timestamp fromTs = epms.util.UpsFormatSupport.parseDateTime(fromRaw, false);
Timestamp toTs = epms.util.UpsFormatSupport.parseDateTime(toRaw, true);

List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();

try {
    devices = epms.ups.UpsQueryService.listDevicesBasic();
    rows = epms.ups.UpsQueryService.measurementHistory(selectedId, searchText, fromTs, toTs, limit);
} catch (Exception e) {
    err = e.getMessage();
}

if ("csv".equalsIgnoreCase(export)) {
    response.reset();
    response.setCharacterEncoding("UTF-8");
    response.setContentType("text/csv;charset=UTF-8");
    response.setHeader("Content-Disposition", "attachment; filename=\"ups_measurement_history.csv\"");
    out.print("\uFEFF");
    out.println("UPS,IP,Port,Measured At,V L1-2,V L2-3,V L3-1,I L1,I L2,I L3,Frequency,Load %,kW,kVA,PF L1,PF L2,PF L3,Battery V,Battery A,Battery %,Battery Temp,Remain Min,UPS Mode,System Mode,Raw Status");
    for (Map<String, Object> r : rows) {
        out.println(
            csv(r.get("ups_name")) + "," +
            csv(r.get("ip_address")) + "," +
            csv(r.get("modbus_port")) + "," +
            csv(r.get("measured_at")) + "," +
            csv(r.get("output_voltage_l12")) + "," +
            csv(r.get("output_voltage_l23")) + "," +
            csv(r.get("output_voltage_l31")) + "," +
            csv(r.get("output_current_l1")) + "," +
            csv(r.get("output_current_l2")) + "," +
            csv(r.get("output_current_l3")) + "," +
            csv(r.get("frequency")) + "," +
            csv(r.get("load_percent")) + "," +
            csv(r.get("output_power_kw")) + "," +
            csv(r.get("output_apparent_total_kva")) + "," +
            csv(r.get("output_pf_l1")) + "," +
            csv(r.get("output_pf_l2")) + "," +
            csv(r.get("output_pf_l3")) + "," +
            csv(r.get("battery_voltage")) + "," +
            csv(r.get("battery_current")) + "," +
            csv(r.get("battery_charge_percent")) + "," +
            csv(r.get("battery_temperature")) + "," +
            csv(r.get("remaining_minutes")) + "," +
            csv(r.get("ups_operation_mode_code")) + "," +
            csv(r.get("system_operation_mode_code")) + "," +
            csv(r.get("raw_status"))
        );
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 측정 이력</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body { background:#f2f4f7; }
        .history-shell { max-width:1320px; margin:0 auto; }
        .history-filter { display:flex; flex-wrap:wrap; gap:8px; align-items:center; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:12px; margin-bottom:12px; }
        .history-filter label { font-size:13px; color:#475569; font-weight:800; }
        .history-filter input, .history-filter select { min-height:36px; border:1px solid #cbd8e6; border-radius:6px; padding:8px 10px; background:#fff; color:#111827; }
        .history-filter input[name="ups"] { min-width:260px; }
        .history-filter input[type="datetime-local"] { min-width:190px; }
        .history-filter select[name="limit"] { min-width:82px; }
        .history-filter button { min-height:36px; padding:8px 12px; }
        .history-table-wrap { overflow:auto; max-height:calc(100vh - 230px); background:#fff; border:1px solid #d7e1ec; border-radius:8px; }
        .history-table { width:max-content; min-width:1780px; border-collapse:collapse; font-size:12px; white-space:nowrap; table-layout:fixed; }
        .history-table th, .history-table td { border-bottom:1px solid #e6edf5; border-right:1px solid #edf2f7; padding:7px 10px; text-align:right; }
        .history-table th:last-child, .history-table td:last-child { border-right:none; }
        .history-table th { position:sticky; top:0; background:#eef4fb; color:#1f3347; z-index:1; }
        .history-table th:first-child, .history-table td:first-child,
        .history-table th:nth-child(2), .history-table td:nth-child(2) { text-align:left; }
        .history-table th, .history-table td { overflow:hidden; text-overflow:ellipsis; }
        .col-ups { width:160px; }
        .col-time { width:170px; }
        .col-v { width:78px; }
        .col-a { width:72px; }
        .col-small { width:70px; }
        .col-pf { width:68px; }
        .col-battery { width:86px; }
        .col-mode { width:96px; }
        .col-status { width:82px; }
        .empty { padding:22px; text-align:center; color:#64748b; }
        .summary { margin:0 0 8px; color:#64748b; font-size:13px; }
    </style>
</head>
<body>
<div class="page-wrap history-shell">
    <div class="title-bar">
        <div>
            <h2>UPS 측정 이력</h2>
            <p class="muted">DB에 저장된 UPS 측정값을 조회합니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form class="history-filter" method="get" id="historyFilter">
        <label for="ups">UPS 검색</label>
        <input id="ups" name="ups" value="<%= h(searchText) %>" placeholder="UPS 이름, IP">
        <% if (selectedId != null && !selectedId.trim().isEmpty()) { %>
        <input type="hidden" name="ups_id" value="<%= h(selectedId) %>">
        <% } %>
        <label for="from">시작</label>
        <input id="from" type="datetime-local" name="from" value="<%= h(fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" type="datetime-local" name="to" value="<%= h(toRaw) %>" <%= explicitTo ? "" : "data-auto-now=\"1\"" %>>
        <label for="limit">건수</label>
        <select id="limit" name="limit">
            <% int[] limits = new int[]{100, 200, 500, 1000}; for (int n : limits) { %>
            <option value="<%= n %>" <%= n == limit ? "selected" : "" %>><%= n %></option>
            <% } %>
        </select>
        <button type="submit">검색</button>
        <button type="button" onclick="location.href='measurement_history.jsp'">전체</button>
        <button type="submit" name="export" value="csv">CSV 다운로드</button>
    </form>

    <p class="summary">조회 결과 <strong><%= rows.size() %></strong>건</p>
    <div class="history-table-wrap">
        <% if (rows.isEmpty()) { %>
        <div class="empty">조회된 측정 이력이 없습니다.</div>
        <% } else { %>
        <table class="history-table">
            <colgroup>
                <col class="col-ups">
                <col class="col-time">
                <col class="col-v"><col class="col-v"><col class="col-v">
                <col class="col-a"><col class="col-a"><col class="col-a">
                <col class="col-small"><col class="col-small"><col class="col-small"><col class="col-small">
                <col class="col-pf"><col class="col-pf"><col class="col-pf">
                <col class="col-battery"><col class="col-battery"><col class="col-battery"><col class="col-battery"><col class="col-battery">
                <col class="col-mode"><col class="col-mode"><col class="col-status">
            </colgroup>
            <thead>
                <tr>
                    <th>UPS</th><th>측정 시간</th>
                    <th>V L1-2</th><th>V L2-3</th><th>V L3-1</th>
                    <th>A L1</th><th>A L2</th><th>A L3</th>
                    <th>Hz</th><th>Load %</th><th>kW</th><th>kVA</th>
                    <th>PF L1</th><th>PF L2</th><th>PF L3</th>
                    <th>Battery %</th><th>Battery V</th><th>Battery A</th><th>Temp</th><th>Remain</th>
                    <th>UPS Mode</th><th>System Mode</th><th>Status</th>
                </tr>
            </thead>
            <tbody>
            <% for (Map<String, Object> r : rows) { %>
                <tr>
                    <td><%= h(r.get("ups_name")) %></td>
                    <td><%= h(epms.util.UpsFormatSupport.displaySlashDateTime(r.get("measured_at"))) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_voltage_l12"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_voltage_l23"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_voltage_l31"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_current_l1"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_current_l2"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_current_l3"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("frequency"), 1) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("load_percent"), 1) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_power_kw"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_apparent_total_kva"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_pf_l1"), 2) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_pf_l2"), 2) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("output_pf_l3"), 2) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("battery_charge_percent"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("battery_voltage"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("battery_current"), 0) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("battery_temperature"), 1) %></td>
                    <td><%= epms.util.UpsFormatSupport.fmt(r.get("remaining_minutes"), 0) %></td>
                    <td><%= h(epms.util.UpsFormatSupport.upsModeLabel(r.get("ups_operation_mode_code"))) %></td>
                    <td><%= h(epms.util.UpsFormatSupport.systemModeLabel(r.get("system_operation_mode_code"))) %></td>
                    <td><%= h(r.get("raw_status")) %></td>
                </tr>
            <% } %>
            </tbody>
        </table>
        <% } %>
    </div>
</div>
<script>
(function () {
    var form = document.getElementById('historyFilter');
    var to = document.getElementById('to');
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
})();
</script>
</body>
</html>
