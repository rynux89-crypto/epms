<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.net.URLEncoder, java.text.SimpleDateFormat" %>
<%@ include file="../includes/dbconn.jsp" %>
<%
    request.setCharacterEncoding("UTF-8");

    String alarmIdParam = request.getParameter("alarm_id");
    String meterId = request.getParameter("meter_id");
    String eventTimeParam = request.getParameter("event_time");
    String buildingName = request.getParameter("building_name");
    String usageType = request.getParameter("usage_type");
    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");
    // backward compatibility
    String fromDate = request.getParameter("from_date");
    String toDate = request.getParameter("to_date");

    if (meterId == null) meterId = "";
    if (buildingName == null) buildingName = "";
    if (usageType == null) usageType = "";
    if (fromDate == null) fromDate = "";
    if (toDate == null) toDate = "";
    if (startDate == null || startDate.trim().isEmpty()) startDate = fromDate;
    if (endDate == null || endDate.trim().isEmpty()) endDate = toDate;
    if (startTime == null || startTime.trim().isEmpty()) startTime = "00:00:00";
    if (endTime == null || endTime.trim().isEmpty()) endTime = "23:59:59";

    Long alarmId = null;
    Integer meterIdInt = null;
    try {
        if (alarmIdParam != null && !alarmIdParam.trim().isEmpty()) {
            alarmId = Long.parseLong(alarmIdParam);
        }
    } catch (Exception ignore) {}
    try {
        if (meterId != null && !meterId.trim().isEmpty()) {
            meterIdInt = Integer.parseInt(meterId.trim());
        }
    } catch (Exception ignore) {}

    Map<String, Object> alarm = new HashMap<>();
    List<Map<String, Object>> points = new ArrayList<>();
    boolean foundAlarm = false;
    String queryError = null;

    try {
        if (alarmId != null || (meterIdInt != null && eventTimeParam != null && !eventTimeParam.trim().isEmpty())) {
            String alarmSql;
            boolean byAlarmId = (alarmId != null);
            if (byAlarmId) {
                alarmSql =
                "SELECT TOP 1 meter_id, meter_name, panel_name, building_name, usage_type, " +
                "alarm_id, alarm_type, severity, triggered_at, cleared_at, description " +
                "FROM vw_alarm_log WHERE alarm_id = ?";
            } else {
                alarmSql =
                "SELECT TOP 1 meter_id, meter_name, panel_name, building_name, usage_type, " +
                "alarm_id, alarm_type, severity, triggered_at, cleared_at, description " +
                "FROM vw_alarm_log " +
                "WHERE meter_id = ? " +
                "ORDER BY ABS(DATEDIFF(SECOND, triggered_at, CAST(? AS DATETIME2))) ASC, alarm_id DESC";
            }

            try (PreparedStatement ps = conn.prepareStatement(alarmSql)) {
                if (byAlarmId) {
                    ps.setLong(1, alarmId);
                } else {
                    ps.setInt(1, meterIdInt.intValue());
                    ps.setString(2, eventTimeParam.trim());
                }
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        foundAlarm = true;
                        alarm.put("meter_id", rs.getInt("meter_id"));
                        alarm.put("meter_name", rs.getString("meter_name"));
                        alarm.put("panel_name", rs.getString("panel_name"));
                        alarm.put("building_name", rs.getString("building_name"));
                        alarm.put("usage_type", rs.getString("usage_type"));
                        alarm.put("alarm_id", rs.getLong("alarm_id"));
                        alarm.put("alarm_type", rs.getString("alarm_type"));
                        alarm.put("severity", rs.getString("severity"));
                        alarm.put("triggered_at", rs.getTimestamp("triggered_at"));
                        alarm.put("cleared_at", rs.getTimestamp("cleared_at"));
                        alarm.put("description", rs.getString("description"));
                    }
                }
            }

            if (foundAlarm) {
                Integer selectedMeterId = (Integer) alarm.get("meter_id");
                Timestamp triggeredAt = (Timestamp) alarm.get("triggered_at");

                String dataSql =
                    "SELECT measured_at, voltage_ab, voltage_bc, voltage_ca, voltage_an, voltage_bn, voltage_cn, current_a, current_b, current_c, frequency, " +
                    "power_factor, power_factor_a, power_factor_b, power_factor_c, " +
                    "active_power_total, reactive_power_total, apparent_power_total, quality_status " +
                    "FROM vw_meter_measurements " +
                    "WHERE meter_id = ? " +
                    "  AND measured_at BETWEEN DATEADD(HOUR, -1, ?) AND DATEADD(HOUR, 1, ?) " +
                    "ORDER BY measured_at";

                try (PreparedStatement ps = conn.prepareStatement(dataSql)) {
                    ps.setInt(1, selectedMeterId);
                    ps.setTimestamp(2, triggeredAt);
                    ps.setTimestamp(3, triggeredAt);

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
                            double lineAvg = (vab + vbc + vca) / 3.0;
                            double phaseAvg = (van + vbn + vcn) / 3.0;
                            p.put("measured_at", rs.getTimestamp("measured_at"));
                            p.put("average_voltage", lineAvg); // chart/backward compatibility
                            p.put("phase_voltage_avg", phaseAvg);
                            p.put("line_voltage_avg", lineAvg);
                            p.put("average_current", (ia + ib + ic) / 3.0);
                            p.put("frequency", rs.getDouble("frequency"));
                            Double pfA = (Double) rs.getObject("power_factor_a");
                            Double pfB = (Double) rs.getObject("power_factor_b");
                            Double pfC = (Double) rs.getObject("power_factor_c");
                            Double pfSingle = (Double) rs.getObject("power_factor");
                            Double pfAvg = null;
                            if (pfA != null && pfB != null && pfC != null) {
                                pfAvg = Double.valueOf((pfA.doubleValue() + pfB.doubleValue() + pfC.doubleValue()) / 3.0);
                            } else if (pfSingle != null) {
                                pfAvg = pfSingle;
                            }
                            p.put("power_factor_avg", pfAvg);
                            p.put("active_power_total", (Double) rs.getObject("active_power_total"));
                            p.put("reactive_power_total", (Double) rs.getObject("reactive_power_total"));
                            p.put("apparent_power_total", (Double) rs.getObject("apparent_power_total"));
                            p.put("quality_status", rs.getString("quality_status"));
                            points.add(p);
                        }
                    }
                }
            }
        }
    } catch (Exception e) {
        queryError = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
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
    <title>알람 상세</title>
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
        .v.one-line { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .table-wrap { flex: 1 1 auto; min-height: 0; overflow: auto; }
        .data-table { table-layout: auto; margin-bottom: 0; }
        .data-table th, .data-table td { white-space: nowrap; text-align: center; }
        .sev-High { color: #b42318; font-weight: 700; }
        .sev-Medium { color: #b54708; font-weight: 700; }
        .sev-Low { color: #027a48; font-weight: 700; }
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
            <h2>알람 상세</h2>
            <button class="back-btn" type="button" onclick="location.href='alarm_view.jsp?<%= backQuery %>'">목록으로</button>
        </div>
    </div>

    <div class="dash-main" style="display:flex; flex-direction:column; gap:12px; min-height:0;">
        <% if (queryError != null) { %>
            <div class="msg-box"><%= queryError %></div>
        <% } %>

        <% if (!foundAlarm) { %>
            <section class="panel_s" style="justify-content:center; align-items:center;">알람을 찾을 수 없습니다.</section>
        <% } else { %>
            <section class="panel_s">
                <div class="kv-grid">
                    <div class="kv"><div class="k">Alarm ID</div><div class="v"><%= alarm.get("alarm_id") %></div></div>
                    <div class="kv"><div class="k">Meter</div><div class="v"><%= alarm.get("meter_name") %> (#<%= alarm.get("meter_id") %>)</div></div>
                    <div class="kv"><div class="k">건물/용도</div><div class="v"><%= alarm.get("building_name") %> / <%= alarm.get("usage_type") %></div></div>
                    <div class="kv"><div class="k">패널</div><div class="v"><%= alarm.get("panel_name") %></div></div>
                    <div class="kv"><div class="k">알람유형</div><div class="v"><%= alarm.get("alarm_type") %></div></div>
                    <div class="kv"><div class="k">심각도</div><div class="v sev-<%= alarm.get("severity") %>"><%= alarm.get("severity") %></div></div>
                    <div class="kv"><div class="k">발생시각</div><div class="v"><%= alarm.get("triggered_at") %></div></div>
                    <%
                        Object clearedObj = alarm.get("cleared_at");
                        String clearedText = (clearedObj == null) ? "-" : String.valueOf(clearedObj);
                        if ("null".equalsIgnoreCase(clearedText.trim()) || clearedText.trim().isEmpty()) clearedText = "-";
                    %>
                    <div class="kv"><div class="k">해제시각</div><div class="v"><%= clearedText %></div></div>
                    <div class="kv" style="grid-column: 1 / -1;"><div class="k">설명</div><div class="v one-line" title="<%= alarm.get("description") %>"><%= alarm.get("description") %></div></div>
                </div>
                <div class="status-text">조회 구간: 발생시각 기준 전후 1시간</div>
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
                                <%
                                    Double pfAvg = (Double) p.get("power_factor_avg");
                                    Double pAct = (Double) p.get("active_power_total");
                                    Double pRea = (Double) p.get("reactive_power_total");
                                    Double pApp = (Double) p.get("apparent_power_total");
                                %>
                                <td><%= (pfAvg == null) ? "-" : String.format("%.3f", pfAvg.doubleValue()) %></td>
                                <td><%= (pAct == null) ? "-" : String.format("%,.2f", pAct.doubleValue()) %></td>
                                <td><%= (pRea == null) ? "-" : String.format("%,.2f", pRea.doubleValue()) %></td>
                                <td><%= (pApp == null) ? "-" : String.format("%.2f", pApp.doubleValue()) %></td>
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
    const eventEpoch = <%= (alarm.get("triggered_at") instanceof Timestamp) ? String.valueOf(((Timestamp) alarm.get("triggered_at")).getTime()) : "null" %>;

    function findClosestIndex(times, target) {
        if (!times || times.length === 0 || target === null) return -1;
        var idx = -1;
        var best = Number.MAX_SAFE_INTEGER;
        for (var i = 0; i < times.length; i++) {
            var t = times[i];
            if (t === null || t === undefined) continue;
            var diff = Math.abs(Number(t) - Number(target));
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
</body>
</html>

