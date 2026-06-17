<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String fmt(Object value, int scale) {
        return epms.util.UpsFormatSupport.fmt(value, scale);
    }

    private String dt(Object value) {
        return epms.util.UpsFormatSupport.displayDateTime(value);
    }

%>
<%
request.setCharacterEncoding("UTF-8");
String upsSearch = request.getParameter("ups");
String export = request.getParameter("export");

epms.util.UpsDateRangeSupport.DateRange range = epms.util.UpsDateRangeSupport.lastDays(request, 1);
epms.ups.UpsReportPageModel reportModel = epms.ups.UpsReportPageService.build(upsSearch, range);
String err = reportModel.err;
String searchText = reportModel.searchText;
List<Map<String, Object>> rows = reportModel.rows;

if ("csv".equalsIgnoreCase(export)) {
    epms.util.CsvDownloadSupport.begin(response, out, "ups_report.csv");
    epms.util.CsvDownloadSupport.writeRow(out, "UPS", "Location", "IP", "Measurements (records)", "First Measured", "Last Measured", "Avg Load (%)", "Max Load (%)", "Avg Output (kW)", "Max Output (kW)", "Avg Apparent Power (kVA)", "Max Apparent Power (kVA)", "Avg Frequency (Hz)", "Min Frequency (Hz)", "Max Frequency (Hz)", "Avg Voltage L1-2 (V)", "Avg Voltage L2-3 (V)", "Avg Voltage L3-1 (V)", "Max Current L1 (A)", "Max Current L2 (A)", "Max Current L3 (A)", "Avg Power Factor L1", "Avg Power Factor L2", "Avg Power Factor L3", "Min Battery Charge (%)", "Avg Battery Charge (%)", "Max Battery Temp (℃)", "Battery Mode Count (records)", "Alarm Count (records)", "Event Count (records)", "Critical Count (records)");
    for (Map<String, Object> r : rows) {
        epms.util.CsvDownloadSupport.writeRow(out, r.get("ups_name"), r.get("location"), String.valueOf(r.get("ip_address")) + ":" + String.valueOf(r.get("modbus_port")), r.get("measurement_count"), dt(r.get("first_measured_at")), dt(r.get("last_measured_at")), r.get("avg_load_percent"), r.get("max_load_percent"), r.get("avg_output_kw"), r.get("max_output_kw"), r.get("avg_output_kva"), r.get("max_output_kva"), r.get("avg_frequency"), r.get("min_frequency"), r.get("max_frequency"), r.get("avg_voltage_l12"), r.get("avg_voltage_l23"), r.get("avg_voltage_l31"), r.get("max_current_l1"), r.get("max_current_l2"), r.get("max_current_l3"), r.get("avg_pf_l1"), r.get("avg_pf_l2"), r.get("avg_pf_l3"), r.get("min_battery_charge"), r.get("avg_battery_charge"), r.get("max_battery_temperature"), r.get("battery_mode_count"), r.get("alarm_count"), r.get("event_count"), r.get("critical_count"));
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 레포트</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        body { background:#f2f4f7; }
        .report-shell { margin:0 auto; }
        .report-filter { display:flex; flex-wrap:wrap; gap:8px; align-items:center; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:12px; margin-bottom:12px; }
        .report-filter label { font-size:13px; color:#475569; font-weight:800; }
        .report-filter input { min-height:36px; border:1px solid #cbd8e6; border-radius:6px; padding:8px 10px; background:#fff; color:#111827; }
        .report-filter input[name="ups"] { min-width:260px; }
        .report-filter input[type="datetime-local"] { min-width:190px; }
        .report-filter button { min-height:36px; padding:8px 12px; }
        .summary-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:10px; margin-bottom:12px; }
        .summary-card { background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:12px; }
        .summary-card span { display:block; color:#64748b; font-size:12px; font-weight:800; }
        .summary-card strong { display:block; margin-top:6px; color:#0f172a; font-size:24px; }
        .report-table-wrap { max-height:calc(100vh - 270px); }
        .report-table { min-width:2440px; }
        .report-table th, .report-table td { text-align:center; }
        .report-table th:first-child, .report-table td:first-child,
        .report-table th:nth-child(2), .report-table td:nth-child(2),
        .report-table th:nth-child(3), .report-table td:nth-child(3) { text-align:left; }
        .col-ups { width:150px; }
        .col-location { width:150px; }
        .col-ip { width:130px; }
        .col-count { width:74px; }
        .col-time { width:178px; }
        .col-small { width:74px; }
        .col-med { width:86px; }
        .col-wide { width:96px; }
        .empty { padding:24px; text-align:center; color:#64748b; }
    </style>
</head>
<body>
<div class="page-wrap report-shell">
<% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form class="report-filter" method="get" id="reportFilter">
        <label for="ups">UPS 검색</label>
        <input id="ups" name="ups" value="<%= h(searchText) %>" placeholder="UPS 이름, 위치, IP">
        <label for="from">시작</label>
        <input id="from" type="datetime-local" name="from" value="<%= h(reportModel.fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" type="datetime-local" name="to" value="<%= h(reportModel.toRaw) %>" <%= reportModel.explicitTo ? "" : "data-auto-now=\"1\"" %>>
        <button type="submit">검색</button>
        <button type="button" onclick="location.href='ups_report.jsp'">전체</button>
        <button type="submit" name="export" value="csv">CSV 다운로드</button>
    </form>

    <div class="summary-grid">
        <div class="summary-card"><span>UPS 수</span><strong><%= reportModel.totalUps %></strong></div>
        <div class="summary-card"><span>측정 건수</span><strong><%= reportModel.totalMeasurements %></strong></div>
        <div class="summary-card"><span>평균 부하율</span><strong><%= reportModel.fleetAvgLoad == null ? "-" : fmt(reportModel.fleetAvgLoad, 1) %>%</strong></div>
        <div class="summary-card"><span>알람</span><strong><%= reportModel.totalAlarms %></strong></div>
        <div class="summary-card"><span>이벤트</span><strong><%= reportModel.totalEvents %></strong></div>
        <div class="summary-card"><span>중요</span><strong><%= reportModel.totalCritical %></strong></div>
    </div>

    <div class="ups-list-wrap report-table-wrap">
        <% if (rows.isEmpty()) { %>
        <div class="empty">조회된 레포트 데이터가 없습니다.</div>
        <% } else { %>
        <table class="ups-list-table report-table">
            <colgroup>
                <col class="col-ups"><col class="col-location"><col class="col-ip">
                <col class="col-count"><col class="col-time"><col class="col-time">
                <col class="col-med"><col class="col-med"><col class="col-med"><col class="col-med"><col class="col-med"><col class="col-med">
                <col class="col-small"><col class="col-small"><col class="col-small">
                <col class="col-med"><col class="col-med"><col class="col-med">
                <col class="col-med"><col class="col-med"><col class="col-med">
                <col class="col-small"><col class="col-small"><col class="col-small">
                <col class="col-wide"><col class="col-wide"><col class="col-wide"><col class="col-wide">
                <col class="col-count"><col class="col-count"><col class="col-count">
            </colgroup>
            <thead>
                <tr>
                    <th>UPS</th><th>위치</th><th>IP</th><th>측정(건)</th><th>첫 수집</th><th>최근 수집</th>
                    <th>평균 부하(%)</th><th>최대 부하(%)</th><th>평균 출력(kW)</th><th>최대 출력(kW)</th><th>평균 피상전력(kVA)</th><th>최대 피상전력(kVA)</th>
                    <th>평균 주파수(Hz)</th><th>최소 주파수(Hz)</th><th>최대 주파수(Hz)</th>
                    <th>평균 전압 V12(V)</th><th>평균 전압 V23(V)</th><th>평균 전압 V31(V)</th>
                    <th>최대 전류 L1(A)</th><th>최대 전류 L2(A)</th><th>최대 전류 L3(A)</th>
                    <th>평균 PF L1</th><th>평균 PF L2</th><th>평균 PF L3</th>
                    <th>최소 배터리(%)</th><th>평균 배터리(%)</th><th>최대 온도(℃)</th><th>배터리 운전(건)</th>
                    <th>알람(건)</th><th>이벤트(건)</th><th>중요(건)</th>
                </tr>
            </thead>
            <tbody>
            <% for (Map<String, Object> r : rows) { %>
                <tr>
                    <td><%= h(r.get("ups_name")) %></td>
                    <td><%= h(r.get("location")) %></td>
                    <td><%= h(r.get("ip_address")) %>:<%= h(r.get("modbus_port")) %></td>
                    <td><%= h(r.get("measurement_count")) %></td>
                    <td><%= h(dt(r.get("first_measured_at"))) %></td>
                    <td><%= h(dt(r.get("last_measured_at"))) %></td>
                    <td><%= fmt(r.get("avg_load_percent"), 1) %></td>
                    <td><%= fmt(r.get("max_load_percent"), 1) %></td>
                    <td><%= fmt(r.get("avg_output_kw"), 1) %></td>
                    <td><%= fmt(r.get("max_output_kw"), 1) %></td>
                    <td><%= fmt(r.get("avg_output_kva"), 1) %></td>
                    <td><%= fmt(r.get("max_output_kva"), 1) %></td>
                    <td><%= fmt(r.get("avg_frequency"), 1) %></td>
                    <td><%= fmt(r.get("min_frequency"), 1) %></td>
                    <td><%= fmt(r.get("max_frequency"), 1) %></td>
                    <td><%= fmt(r.get("avg_voltage_l12"), 0) %></td>
                    <td><%= fmt(r.get("avg_voltage_l23"), 0) %></td>
                    <td><%= fmt(r.get("avg_voltage_l31"), 0) %></td>
                    <td><%= fmt(r.get("max_current_l1"), 0) %></td>
                    <td><%= fmt(r.get("max_current_l2"), 0) %></td>
                    <td><%= fmt(r.get("max_current_l3"), 0) %></td>
                    <td><%= fmt(r.get("avg_pf_l1"), 2) %></td>
                    <td><%= fmt(r.get("avg_pf_l2"), 2) %></td>
                    <td><%= fmt(r.get("avg_pf_l3"), 2) %></td>
                    <td><%= fmt(r.get("min_battery_charge"), 0) %></td>
                    <td><%= fmt(r.get("avg_battery_charge"), 0) %></td>
                    <td><%= fmt(r.get("max_battery_temperature"), 1) %></td>
                    <td><%= h(r.get("battery_mode_count")) %></td>
                    <td><%= h(r.get("alarm_count")) %></td>
                    <td><%= h(r.get("event_count")) %></td>
                    <td><%= h(r.get("critical_count")) %></td>
                </tr>
            <% } %>
            </tbody>
        </table>
        <% } %>
    </div>
</div>
<script>
(function () {
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
