<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private int intValue(Object value) {
        if (value == null) return 0;
        try {
            return value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value));
        } catch (Exception ignore) {
            return 0;
        }
    }

    private String fmt(Object value, int scale) {
        return epms.util.UpsFormatSupport.fmt(value, scale);
    }

    private String dt(Object value) {
        return epms.util.UpsFormatSupport.displayDateTime(value);
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
String upsSearch = request.getParameter("ups");
String searchText = upsSearch == null ? "" : upsSearch.trim();
String fromRaw = request.getParameter("from");
String toRaw = request.getParameter("to");
boolean explicitTo = toRaw != null && !toRaw.trim().isEmpty();
String export = request.getParameter("export");

Calendar nowCal = Calendar.getInstance();
String defaultTo = epms.util.UpsFormatSupport.htmlDateTime(nowCal);
Calendar fromCal = (Calendar) nowCal.clone();
fromCal.add(Calendar.DAY_OF_MONTH, -1);
String defaultFrom = epms.util.UpsFormatSupport.htmlDateTime(fromCal);
if (fromRaw == null || fromRaw.trim().isEmpty()) fromRaw = defaultFrom;
if (toRaw == null || toRaw.trim().isEmpty()) toRaw = defaultTo;
Timestamp fromTs = epms.util.UpsFormatSupport.parseDateTime(fromRaw, false);
Timestamp toTs = epms.util.UpsFormatSupport.parseDateTime(toRaw, true);

List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
try {
    rows = epms.ups.UpsQueryService.reportRows(searchText, fromTs, toTs);
} catch (Exception e) {
    err = e.getMessage();
}

int totalUps = rows.size();
int totalMeasurements = 0;
int totalAlarms = 0;
int totalEvents = 0;
int totalCritical = 0;
double avgLoadSum = 0d;
int avgLoadCount = 0;
for (Map<String, Object> r : rows) {
    totalMeasurements += intValue(r.get("measurement_count"));
    totalAlarms += intValue(r.get("alarm_count"));
    totalEvents += intValue(r.get("event_count"));
    totalCritical += intValue(r.get("critical_count"));
    Object avg = r.get("avg_load_percent");
    if (avg instanceof Number) {
        avgLoadSum += ((Number) avg).doubleValue();
        avgLoadCount++;
    }
}
Double fleetAvgLoad = avgLoadCount == 0 ? null : Double.valueOf(avgLoadSum / avgLoadCount);

if ("csv".equalsIgnoreCase(export)) {
    response.reset();
    response.setCharacterEncoding("UTF-8");
    response.setContentType("text/csv;charset=UTF-8");
    response.setHeader("Content-Disposition", "attachment; filename=\"ups_report.csv\"");
    out.print("\uFEFF");
    out.println("UPS,Location,IP,Measurements,First Measured,Last Measured,Avg Load %,Max Load %,Avg kW,Max kW,Avg kVA,Max kVA,Avg Hz,Min Hz,Max Hz,Avg V L1-2,Avg V L2-3,Avg V L3-1,Max A L1,Max A L2,Max A L3,Avg PF L1,Avg PF L2,Avg PF L3,Min Battery %,Avg Battery %,Max Battery Temp,Battery Mode Count,Alarm Count,Event Count,Critical Count");
    for (Map<String, Object> r : rows) {
        out.println(
            csv(r.get("ups_name")) + "," +
            csv(r.get("location")) + "," +
            csv(r.get("ip_address")) + ":" + csv(r.get("modbus_port")) + "," +
            csv(r.get("measurement_count")) + "," +
            csv(dt(r.get("first_measured_at"))) + "," +
            csv(dt(r.get("last_measured_at"))) + "," +
            csv(r.get("avg_load_percent")) + "," +
            csv(r.get("max_load_percent")) + "," +
            csv(r.get("avg_output_kw")) + "," +
            csv(r.get("max_output_kw")) + "," +
            csv(r.get("avg_output_kva")) + "," +
            csv(r.get("max_output_kva")) + "," +
            csv(r.get("avg_frequency")) + "," +
            csv(r.get("min_frequency")) + "," +
            csv(r.get("max_frequency")) + "," +
            csv(r.get("avg_voltage_l12")) + "," +
            csv(r.get("avg_voltage_l23")) + "," +
            csv(r.get("avg_voltage_l31")) + "," +
            csv(r.get("max_current_l1")) + "," +
            csv(r.get("max_current_l2")) + "," +
            csv(r.get("max_current_l3")) + "," +
            csv(r.get("avg_pf_l1")) + "," +
            csv(r.get("avg_pf_l2")) + "," +
            csv(r.get("avg_pf_l3")) + "," +
            csv(r.get("min_battery_charge")) + "," +
            csv(r.get("avg_battery_charge")) + "," +
            csv(r.get("max_battery_temperature")) + "," +
            csv(r.get("battery_mode_count")) + "," +
            csv(r.get("alarm_count")) + "," +
            csv(r.get("event_count")) + "," +
            csv(r.get("critical_count"))
        );
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 레포트</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body { background:#f2f4f7; }
        .report-shell { max-width:1360px; margin:0 auto; }
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
        .report-table-wrap { overflow:auto; max-height:calc(100vh - 270px); background:#fff; border:1px solid #d7e1ec; border-radius:8px; }
        .report-table { width:max-content; min-width:2140px; border-collapse:collapse; font-size:12px; white-space:nowrap; table-layout:fixed; }
        .report-table th, .report-table td { border-bottom:1px solid #e6edf5; border-right:1px solid #edf2f7; padding:7px 9px; text-align:right; overflow:hidden; text-overflow:ellipsis; }
        .report-table th { position:sticky; top:0; background:#eef4fb; color:#1f3347; z-index:1; }
        .report-table th:first-child, .report-table td:first-child,
        .report-table th:nth-child(2), .report-table td:nth-child(2),
        .report-table th:nth-child(3), .report-table td:nth-child(3) { text-align:left; }
        .col-ups { width:150px; }
        .col-location { width:150px; }
        .col-ip { width:130px; }
        .col-count { width:74px; }
        .col-time { width:150px; }
        .col-small { width:74px; }
        .col-med { width:86px; }
        .col-wide { width:96px; }
        .empty { padding:24px; text-align:center; color:#64748b; }
    </style>
</head>
<body>
<div class="page-wrap report-shell">
    <div class="title-bar">
        <div>
            <h2>UPS 레포트</h2>
            <p class="muted">기간별 UPS 운전 요약, 전력 품질, 배터리, 알람/이벤트 집계를 확인합니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form class="report-filter" method="get" id="reportFilter">
        <label for="ups">UPS 검색</label>
        <input id="ups" name="ups" value="<%= h(searchText) %>" placeholder="UPS 이름, 위치, IP">
        <label for="from">시작</label>
        <input id="from" type="datetime-local" name="from" value="<%= h(fromRaw) %>">
        <label for="to">종료</label>
        <input id="to" type="datetime-local" name="to" value="<%= h(toRaw) %>" <%= explicitTo ? "" : "data-auto-now=\"1\"" %>>
        <button type="submit">검색</button>
        <button type="button" onclick="location.href='ups_report.jsp'">전체</button>
        <button type="submit" name="export" value="csv">CSV 다운로드</button>
    </form>

    <div class="summary-grid">
        <div class="summary-card"><span>UPS 수</span><strong><%= totalUps %></strong></div>
        <div class="summary-card"><span>측정 건수</span><strong><%= totalMeasurements %></strong></div>
        <div class="summary-card"><span>평균 부하율</span><strong><%= fleetAvgLoad == null ? "-" : fmt(fleetAvgLoad, 1) %>%</strong></div>
        <div class="summary-card"><span>알람</span><strong><%= totalAlarms %></strong></div>
        <div class="summary-card"><span>이벤트</span><strong><%= totalEvents %></strong></div>
        <div class="summary-card"><span>중요</span><strong><%= totalCritical %></strong></div>
    </div>

    <div class="report-table-wrap">
        <% if (rows.isEmpty()) { %>
        <div class="empty">조회된 레포트 데이터가 없습니다.</div>
        <% } else { %>
        <table class="report-table">
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
                    <th>UPS</th><th>위치</th><th>IP</th><th>측정</th><th>첫 수집</th><th>최근 수집</th>
                    <th>평균 부하</th><th>최대 부하</th><th>평균 kW</th><th>최대 kW</th><th>평균 kVA</th><th>최대 kVA</th>
                    <th>평균 Hz</th><th>최소 Hz</th><th>최대 Hz</th>
                    <th>평균 V12</th><th>평균 V23</th><th>평균 V31</th>
                    <th>최대 A1</th><th>최대 A2</th><th>최대 A3</th>
                    <th>PF1</th><th>PF2</th><th>PF3</th>
                    <th>최소 배터리</th><th>평균 배터리</th><th>최대 온도</th><th>배터리 운전</th>
                    <th>알람</th><th>이벤트</th><th>중요</th>
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
