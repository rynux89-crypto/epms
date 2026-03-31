<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.net.URLEncoder, java.text.SimpleDateFormat" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String normalizeSeverity(Object v) {
        String s = v == null ? "" : String.valueOf(v).trim().toUpperCase(java.util.Locale.ROOT);
        if ("CRITICAL".equals(s) || "HIGH".equals(s)) return "CRITICAL";
        if ("ALARM".equals(s) || "MEDIUM".equals(s)) return "ALARM";
        return "NORMAL";
    }
%>
<%
try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String eventId = request.getParameter("event_id");
    String meterId = request.getParameter("meter_id");
    String eventTimeParam = request.getParameter("event_time");
    String buildingName = request.getParameter("building_name");
    String usageType = request.getParameter("usage_type");
    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");
    String fromDate = request.getParameter("from_date");
    String toDate = request.getParameter("to_date");

    if (meterId == null) meterId = "";
    if (eventTimeParam == null) eventTimeParam = "";
    if (buildingName == null) buildingName = "";
    if (usageType == null) usageType = "";
    if (fromDate == null) fromDate = "";
    if (toDate == null) toDate = "";
    if (startDate == null || startDate.trim().isEmpty()) startDate = fromDate;
    if (endDate == null || endDate.trim().isEmpty()) endDate = toDate;
    if (startTime == null || startTime.trim().isEmpty()) startTime = "00:00:00";
    if (endTime == null || endTime.trim().isEmpty()) endTime = "23:59:59";

    Integer eventIdInt = null;
    try {
        if (eventId != null && !eventId.trim().isEmpty()) eventIdInt = Integer.parseInt(eventId.trim());
    } catch (Exception ignore) {}

    Integer meterIdInt = null;
    try {
        if (!meterId.trim().isEmpty()) meterIdInt = Integer.parseInt(meterId.trim());
    } catch (Exception ignore) {}

    Map<String, Object> event = new HashMap<>();
    List<Map<String, Object>> points = new ArrayList<>();
    boolean foundEvent = false;
    String queryError = null;

    try {
        if (eventIdInt != null || (meterIdInt != null && !eventTimeParam.trim().isEmpty())) {
            if (eventIdInt != null) {
                String eventSql =
                    "SELECT TOP 1 de.event_id, de.device_id, m.name AS meter_name, m.panel_name, m.building_name, m.usage_type, " +
                    "de.event_type, de.severity, de.event_time, de.restored_time, de.description " +
                    "FROM dbo.device_events de " +
                    "LEFT JOIN dbo.meters m ON m.meter_id = de.device_id " +
                    "WHERE de.event_id = ? ";

                try (PreparedStatement ps = conn.prepareStatement(eventSql)) {
                    ps.setInt(1, eventIdInt.intValue());
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            foundEvent = true;
                            event.put("event_id", rs.getLong("event_id"));
                            event.put("device_id", rs.getInt("device_id"));
                            event.put("meter_name", rs.getString("meter_name"));
                            event.put("panel_name", rs.getString("panel_name"));
                            event.put("building_name", rs.getString("building_name"));
                            event.put("usage_type", rs.getString("usage_type"));
                            event.put("event_type", rs.getString("event_type"));
                            event.put("severity", rs.getString("severity"));
                            event.put("event_time", rs.getTimestamp("event_time"));
                            event.put("restored_time", rs.getTimestamp("restored_time"));
                            event.put("description", rs.getString("description"));
                        }
                    }
                }
            } else {
                String eventSql =
                    "SELECT TOP 1 de.event_id, de.device_id, m.name AS meter_name, m.panel_name, m.building_name, m.usage_type, " +
                    "de.event_type, de.severity, de.event_time, de.restored_time, de.description " +
                    "FROM dbo.device_events de " +
                    "LEFT JOIN dbo.meters m ON m.meter_id = de.device_id " +
                    "WHERE de.device_id = ? " +
                    "ORDER BY ABS(DATEDIFF(SECOND, de.event_time, CAST(? AS DATETIME2))) ASC, de.event_id DESC";

                try (PreparedStatement ps = conn.prepareStatement(eventSql)) {
                    ps.setInt(1, meterIdInt.intValue());
                    ps.setString(2, eventTimeParam.trim());
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            foundEvent = true;
                            event.put("event_id", rs.getLong("event_id"));
                            event.put("device_id", rs.getInt("device_id"));
                            event.put("meter_name", rs.getString("meter_name"));
                            event.put("panel_name", rs.getString("panel_name"));
                            event.put("building_name", rs.getString("building_name"));
                            event.put("usage_type", rs.getString("usage_type"));
                            event.put("event_type", rs.getString("event_type"));
                            event.put("severity", rs.getString("severity"));
                            event.put("event_time", rs.getTimestamp("event_time"));
                            event.put("restored_time", rs.getTimestamp("restored_time"));
                            event.put("description", rs.getString("description"));
                        }
                    }
                }
            }

            if (foundEvent) {
                Integer selectedMeterId = (Integer) event.get("device_id");
                Timestamp eventTime = (Timestamp) event.get("event_time");

                boolean loadedPoints = false;
                String dataSqlPfSingle =
                    "SELECT measured_at, voltage_ab, voltage_bc, voltage_ca, voltage_an, voltage_bn, voltage_cn, current_a, current_b, current_c, frequency, " +
                    "power_factor, active_power_total, reactive_power_total, apparent_power_total, quality_status " +
                    "FROM vw_meter_measurements " +
                    "WHERE meter_id = ? " +
                    "  AND measured_at BETWEEN DATEADD(HOUR, -1, ?) AND DATEADD(HOUR, 1, ?) " +
                    "ORDER BY measured_at";
                try (PreparedStatement ps = conn.prepareStatement(dataSqlPfSingle)) {
                    ps.setInt(1, selectedMeterId);
                    ps.setTimestamp(2, eventTime);
                    ps.setTimestamp(3, eventTime);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            Map<String, Object> p = new HashMap<>();
                            double vab = rs.getDouble("voltage_ab");
                            double vbc = rs.getDouble("voltage_bc");
                            double vca = rs.getDouble("voltage_ca");
                            double van = rs.getDouble("voltage_an");
                            double vbn = rs.getDouble("voltage_bn");
                            double vcn = rs.getDouble("voltage_cn");
                            double ia = rs.getDouble("current_a");
                            double ib = rs.getDouble("current_b");
                            double ic = rs.getDouble("current_c");
                            p.put("measured_at", rs.getTimestamp("measured_at"));
                            p.put("average_voltage", (vab + vbc + vca) / 3.0);
                            p.put("phase_voltage_avg", (van + vbn + vcn) / 3.0);
                            p.put("average_current", (ia + ib + ic) / 3.0);
                            p.put("frequency", rs.getDouble("frequency"));
                            p.put("power_factor_avg", rs.getDouble("power_factor"));
                            p.put("active_power_total", rs.getDouble("active_power_total"));
                            p.put("reactive_power_total", rs.getDouble("reactive_power_total"));
                            p.put("apparent_power_total", rs.getDouble("apparent_power_total"));
                            p.put("quality_status", rs.getString("quality_status"));
                            points.add(p);
                        }
                    }
                    loadedPoints = true;
                } catch (Exception ignore) {}

                if (!loadedPoints) {
                    String dataSqlPfPhase =
                        "SELECT measured_at, voltage_ab, voltage_bc, voltage_ca, voltage_an, voltage_bn, voltage_cn, current_a, current_b, current_c, frequency, " +
                        "power_factor_a, power_factor_b, power_factor_c, active_power_total, reactive_power_total, apparent_power_total, quality_status " +
                        "FROM vw_meter_measurements " +
                        "WHERE meter_id = ? " +
                        "  AND measured_at BETWEEN DATEADD(HOUR, -1, ?) AND DATEADD(HOUR, 1, ?) " +
                        "ORDER BY measured_at";
                    try (PreparedStatement ps = conn.prepareStatement(dataSqlPfPhase)) {
                        ps.setInt(1, selectedMeterId);
                        ps.setTimestamp(2, eventTime);
                        ps.setTimestamp(3, eventTime);
                        try (ResultSet rs = ps.executeQuery()) {
                            while (rs.next()) {
                                Map<String, Object> p = new HashMap<>();
                                double vab = rs.getDouble("voltage_ab");
                                double vbc = rs.getDouble("voltage_bc");
                                double vca = rs.getDouble("voltage_ca");
                                double van = rs.getDouble("voltage_an");
                                double vbn = rs.getDouble("voltage_bn");
                                double vcn = rs.getDouble("voltage_cn");
                                double ia = rs.getDouble("current_a");
                                double ib = rs.getDouble("current_b");
                                double ic = rs.getDouble("current_c");
                                p.put("measured_at", rs.getTimestamp("measured_at"));
                                p.put("average_voltage", (vab + vbc + vca) / 3.0);
                                p.put("phase_voltage_avg", (van + vbn + vcn) / 3.0);
                                p.put("average_current", (ia + ib + ic) / 3.0);
                                p.put("frequency", rs.getDouble("frequency"));
                                double pfA = rs.getDouble("power_factor_a");
                                double pfB = rs.getDouble("power_factor_b");
                                double pfC = rs.getDouble("power_factor_c");
                                p.put("power_factor_avg", (pfA + pfB + pfC) / 3.0);
                                p.put("active_power_total", rs.getDouble("active_power_total"));
                                p.put("reactive_power_total", rs.getDouble("reactive_power_total"));
                                p.put("apparent_power_total", rs.getDouble("apparent_power_total"));
                                p.put("quality_status", rs.getString("quality_status"));
                                points.add(p);
                            }
                        }
                    }
                }
            }
        }
    } catch (Exception e) {
        queryError = e.getMessage();
    }

    String backQuery =
        "meter_id=" + URLEncoder.encode(meterId, "UTF-8") +
        "&building_name=" + URLEncoder.encode(buildingName, "UTF-8") +
        "&usage_type=" + URLEncoder.encode(usageType, "UTF-8") +
        "&startDate=" + URLEncoder.encode(startDate, "UTF-8") +
        "&startTime=" + URLEncoder.encode(startTime, "UTF-8") +
        "&endDate=" + URLEncoder.encode(endDate, "UTF-8") +
        "&endTime=" + URLEncoder.encode(endTime, "UTF-8");
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>이벤트 상세</title>
    <script src="../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-meter-status.page-event-detail { height: auto; min-height: 100vh; overflow: auto; }
        .page-meter-status.page-event-detail .dash { height: auto; min-height: 100vh; }
        .page-meter-status.page-event-detail .dash-main { overflow: auto; }
        .kv-grid { display: grid; grid-template-columns: repeat(8, minmax(0,1fr)); gap: 10px; }
        .kv { border: 1px solid #e2e6ef; border-radius: 8px; padding: 8px; background: #fff; }
        .k { font-size: 12px; color: #64748b; }
        .v { font-weight: 700; }
        .table-wrap { flex: 1 1 auto; min-height: 0; overflow: auto; }
        .data-table { table-layout: auto; margin-bottom: 0; }
        .data-table th, .data-table td { white-space: nowrap; text-align: center; }
        .sev-CRITICAL, .sev-High { color: #b42318; font-weight: 700; }
        .sev-ALARM, .sev-Medium { color: #b54708; font-weight: 700; }
        .sev-WARN, .sev-Low, .sev-NORMAL { color: #027a48; font-weight: 700; }
        .msg-box { color: #b42318; font-weight: 700; margin-bottom: 8px; }
        @media (max-width: 960px) { .panel_s[style*="height: 360px;"] { height: 300px !important; } }
        @media (max-width: 1600px) { .kv-grid { grid-template-columns: repeat(4, minmax(0,1fr)); } }
        @media (max-width: 1200px) { .kv-grid { grid-template-columns: repeat(2, minmax(0,1fr)); } }
        @media (max-width: 680px) { .kv-grid { grid-template-columns: 1fr; } }
    </style>
</head>
<body class="page-meter-status page-event-detail">
<div class="dash">
    <div class="dash-top">
        <div class="title-bar">
            <h2>📄 이벤트 상세</h2>
            <div class="inline-actions">
                <button class="back-btn" type="button" onclick="location.href='event_view.jsp?<%= backQuery %>'">목록으로</button>
            </div>
        </div>
    </div>

    <div class="dash-main" style="display:flex; flex-direction:column; gap:12px; min-height:0;">
        <% if (queryError != null) { %>
            <div class="msg-box"><%= h(queryError) %></div>
        <% } %>

        <% if (!foundEvent) { %>
            <section class="panel_s" style="justify-content:center; align-items:center;">이벤트를 찾을 수 없습니다.</section>
        <% } else { %>
            <section class="panel_s">
                <div class="kv-grid">
                    <div class="kv"><div class="k">Event ID</div><div class="v"><%= event.get("event_id") %></div></div>
                    <div class="kv"><div class="k">Meter</div><div class="v"><%= h(event.get("meter_name")) %> (#<%= event.get("device_id") %>)</div></div>
                    <div class="kv"><div class="k">건물/용도</div><div class="v"><%= h(event.get("building_name")) %> / <%= h(event.get("usage_type")) %></div></div>
                    <div class="kv"><div class="k">패널</div><div class="v"><%= h(event.get("panel_name")) %></div></div>
                    <div class="kv"><div class="k">이벤트 유형</div><div class="v"><%= h(event.get("event_type")) %></div></div>
                    <% String normalizedSeverity = normalizeSeverity(event.get("severity")); %>
                    <div class="kv"><div class="k">심각도</div><div class="v sev-<%= h(normalizedSeverity) %>"><%= h(normalizedSeverity) %></div></div>
                    <div class="kv"><div class="k">발생 시각</div><div class="v"><%= event.get("event_time") %></div></div>
                    <%
                        Object restoredObj = event.get("restored_time");
                        String restoredText = (restoredObj == null) ? "-" : String.valueOf(restoredObj);
                        if ("null".equalsIgnoreCase(restoredText.trim()) || restoredText.trim().isEmpty()) restoredText = "-";
                    %>
                    <div class="kv"><div class="k">해제 시각</div><div class="v"><%= h(restoredText) %></div></div>
                    <div class="kv" style="grid-column: 1 / -1;"><div class="k">설명</div><div class="v"><%= h(event.get("description")) %></div></div>
                </div>
                <div class="status-text">조회 구간: 이벤트 발생시각 기준 전후 1시간</div>
            </section>

            <section class="panel_s" style="height: 360px;">
                <div class="chartBox_s" style="height:100%;"><div id="trendChart" style="width:100%;height:100%;"></div></div>
            </section>

            <section class="panel_s" style="flex:1 1 auto; min-height:0;">
                <div style="font-weight:700; margin-bottom:8px;">측정 데이터 건수: <%= points.size() %></div>
                <div class="table-wrap">
                    <table class="data-table">
                        <thead>
                        <tr>
                            <th>측정시각</th>
                            <th>전압(평균)</th>
                            <th>전류(평균)</th>
                            <th>주파수</th>
                            <th>역률(평균)</th>
                            <th>유효전력</th>
                            <th>무효전력</th>
                            <th>피상전력</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% SimpleDateFormat tableTsFmt = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss"); %>
                        <% for (Map<String, Object> p : points) { %>
                            <tr>
                                <td><%= tableTsFmt.format((Timestamp) p.get("measured_at")) %></td>
                                <td><%= String.format("%.2f", (Double) p.get("average_voltage")) %></td>
                                <td><%= String.format("%.2f", (Double) p.get("average_current")) %></td>
                                <td><%= String.format("%.2f", (Double) p.get("frequency")) %></td>
                                <td><%= String.format("%.3f", (Double) p.get("power_factor_avg")) %></td>
                                <td><%= String.format("%,.2f", (Double) p.get("active_power_total")) %></td>
                                <td><%= String.format("%,.2f", (Double) p.get("reactive_power_total")) %></td>
                                <td><%= String.format("%.2f", (Double) p.get("apparent_power_total")) %></td>
                            </tr>
                        <% } %>
                        <% if (points.isEmpty()) { %>
                            <tr><td colspan="8" style="text-align:center;">해당 구간 데이터가 없습니다.</td></tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
            </section>
        <% } %>
    </div>
</div>

<script>
(function(){
    <% SimpleDateFormat xAxisFmt = new SimpleDateFormat("MM-dd HH:mm:ss"); %>
    const labels = [
        <% for (int i = 0; i < points.size(); i++) {
            Map<String, Object> p = points.get(i);
            String ts = xAxisFmt.format((Timestamp) p.get("measured_at")).replace("'", "\\'");
        %>
            '<%= ts %>'<%= i < points.size()-1 ? "," : "" %>
        <% } %>
    ];
    const vAvg = [
        <% for (int i = 0; i < points.size(); i++) { %>
            <%= String.format(java.util.Locale.US, "%.4f", (Double) points.get(i).get("average_voltage")) %><%= i < points.size()-1 ? "," : "" %>
        <% } %>
    ];
    const fAvg = [
        <% for (int i = 0; i < points.size(); i++) { %>
            <%= String.format(java.util.Locale.US, "%.4f", (Double) points.get(i).get("frequency")) %><%= i < points.size()-1 ? "," : "" %>
        <% } %>
    ];
    const measuredEpochs = [
        <% for (int i = 0; i < points.size(); i++) {
            Timestamp mt = (Timestamp) points.get(i).get("measured_at");
        %>
            <%= mt == null ? "null" : String.valueOf(mt.getTime()) %><%= i < points.size()-1 ? "," : "" %>
        <% } %>
    ];
    const eventEpoch = <%= (event.get("event_time") instanceof Timestamp) ? String.valueOf(((Timestamp) event.get("event_time")).getTime()) : "null" %>;

    function findClosestIndex(times, target) {
        if (!times || times.length === 0 || target === null) return -1;
        let idx = -1;
        let best = Number.MAX_SAFE_INTEGER;
        for (let i = 0; i < times.length; i++) {
            const t = times[i];
            if (t === null || t === undefined) continue;
            const diff = Math.abs(Number(t) - Number(target));
            if (diff < best) { best = diff; idx = i; }
        }
        return idx;
    }
    const eventIndex = findClosestIndex(measuredEpochs, eventEpoch);

    const el = document.getElementById('trendChart');
    if (!el || labels.length === 0 || typeof echarts === 'undefined') return;

    const chart = echarts.init(el);
    const option = {
        animation: false,
        grid: { left: 56, right: 56, top: 44, bottom: 72 },
        tooltip: { trigger: 'axis' },
        legend: {
            top: 6,
            left: 'center',
            orient: 'horizontal',
            itemGap: 24,
            icon: 'roundRect',
            textStyle: { fontSize: 12 },
            data: ['전압(평균)', '주파수']
        },
        xAxis: {
            type: 'category',
            data: labels,
            boundaryGap: false,
            axisLabel: { hideOverlap: true, margin: 18 }
        },
        yAxis: [
            { type: 'value', name: '전압', position: 'left' },
            { type: 'value', name: '주파수', position: 'right', splitLine: { show: false } }
        ],
        dataZoom: [
            { type: 'inside', throttle: 50 },
            { type: 'slider', height: 14, bottom: 14 }
        ],
        series: [
            {
                name: '전압(평균)',
                type: 'line',
                color: '#2563eb',
                yAxisIndex: 0,
                data: vAvg,
                showSymbol: false,
                sampling: 'lttb',
                large: true,
                largeThreshold: 2000,
                progressive: 4000,
                progressiveThreshold: 8000,
                lineStyle: { width: 1.8, color: '#2563eb' },
                areaStyle: { opacity: 0 },
                markLine: (eventIndex >= 0) ? {
                    symbol: 'none',
                    silent: true,
                    lineStyle: { color: '#b42318', type: 'dashed', width: 2 },
                    label: { show: false },
                    data: [{ xAxis: labels[eventIndex] }]
                } : undefined
            },
            {
                name: '주파수',
                type: 'line',
                color: '#dc2626',
                yAxisIndex: 1,
                data: fAvg,
                showSymbol: false,
                sampling: 'lttb',
                large: true,
                largeThreshold: 2000,
                progressive: 4000,
                progressiveThreshold: 8000,
                lineStyle: { width: 1.6, color: '#dc2626' },
                areaStyle: { opacity: 0 }
            }
        ]
    };
    chart.setOption(option);
    window.addEventListener('resize', function(){ chart.resize(); });
})();
</script>
<%
} // end try-with-resources
%>
</body>
</html>


