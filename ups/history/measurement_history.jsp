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

%>
<%
request.setCharacterEncoding("UTF-8");
String err = null;
String selectedId = request.getParameter("ups_id");
String upsSearch = request.getParameter("ups");
String searchText = upsSearch == null ? "" : upsSearch.trim();
String normalizedSearchText = searchText.replaceAll("\\s+", "");
String export = request.getParameter("export");
int limit = parseLimit(request.getParameter("limit"));
epms.util.UpsDateRangeSupport.DateRange range = epms.util.UpsDateRangeSupport.lastDays(request, 1);
String fromRaw = range.fromRaw;
String toRaw = range.toRaw;
boolean explicitTo = range.explicitTo;
Timestamp fromTs = range.fromTs;
Timestamp toTs = range.toTs;

List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();

try {
    devices = epms.ups.UpsDeviceLookupService.listDevicesBasic();
    rows = epms.ups.UpsMeasurementHistoryService.measurementHistory(selectedId, searchText, fromTs, toTs, limit);
} catch (Exception e) {
    err = e.getMessage();
}

if ("csv".equalsIgnoreCase(export)) {
    epms.util.CsvDownloadSupport.begin(response, out, "ups_measurement_history.csv");
    epms.util.CsvDownloadSupport.writeRow(out, "UPS", "IP", "Port", "Measured At", "V L1-2", "V L2-3", "V L3-1", "I L1", "I L2", "I L3", "Frequency", "Load %", "kW", "kVA", "PF L1", "PF L2", "PF L3", "Battery V", "Battery A", "Battery %", "Battery Temp", "Remain Min", "UPS Mode", "System Mode", "Raw Status");
    for (Map<String, Object> r : rows) {
        epms.util.CsvDownloadSupport.writeRow(out, r.get("ups_name"), r.get("ip_address"), r.get("modbus_port"), r.get("measured_at"), r.get("output_voltage_l12"), r.get("output_voltage_l23"), r.get("output_voltage_l31"), r.get("output_current_l1"), r.get("output_current_l2"), r.get("output_current_l3"), r.get("frequency"), r.get("load_percent"), r.get("output_power_kw"), r.get("output_apparent_total_kva"), r.get("output_pf_l1"), r.get("output_pf_l2"), r.get("output_pf_l3"), r.get("battery_voltage"), r.get("battery_current"), r.get("battery_charge_percent"), r.get("battery_temperature"), r.get("remaining_minutes"), r.get("ups_operation_mode_code"), r.get("system_operation_mode_code"), r.get("raw_status"));
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 측정 이력</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        body { background:#f2f4f7; }
        .history-shell { max-width:none; width:100%; margin:0 auto; }
        .history-filter { display:flex; flex-wrap:wrap; gap:8px; align-items:center; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:12px; margin-bottom:12px; }
        .history-filter label { font-size:13px; color:#475569; font-weight:800; }
        .history-filter input, .history-filter select { min-height:36px; border:1px solid #cbd8e6; border-radius:6px; padding:8px 10px; background:#fff; color:#111827; }
        .history-filter input[name="ups"] { min-width:260px; }
        .history-filter input[type="datetime-local"] { min-width:190px; }
        .history-filter select[name="limit"] { min-width:82px; }
        .history-filter button { min-height:36px; padding:8px 12px; }
        .history-table-wrap { overflow:auto; max-height:calc(100vh - 230px); background:#fff; border:1px solid #d7e1ec; border-radius:8px; }
        .history-table { width:100%; min-width:1960px; border-collapse:collapse; font-size:12px; white-space:nowrap; table-layout:fixed; }
        .history-table th, .history-table td { border-bottom:1px solid #e6edf5; border-right:1px solid #edf2f7; padding:7px 8px; text-align:right; }
        .history-table th:last-child, .history-table td:last-child { border-right:none; }
        .history-table th { position:sticky; top:0; background:#eef4fb; color:#1f3347; z-index:1; }
        .history-table th:first-child, .history-table td:first-child,
        .history-table th:nth-child(2), .history-table td:nth-child(2) { text-align:left; }
        .history-table th, .history-table td { overflow:hidden; text-overflow:ellipsis; }
        .col-ups { width:180px; }
        .col-time { width:168px; }
        .col-v { width:82px; }
        .col-a { width:78px; }
        .col-small { width:76px; }
        .col-pf { width:72px; }
        .col-battery { width:92px; }
        .col-mode { width:118px; }
        .col-status { width:110px; }
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
<%@ include file="../includes/ups_footer.jspf" %>
</body>
</html>
