<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.net.URLEncoder, java.time.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String cleanAlarmDesc(Object v) {
        if (v == null) return "";
        String s = String.valueOf(v).trim();
        if (s.isEmpty()) return s;

        String[] parts = s.split("\\s*,\\s*");
        List<String> keep = new ArrayList<>();
        for (String p : parts) {
            if (p == null) continue;
            String t = p.trim();
            if (t.isEmpty()) continue;
            String u = t.toUpperCase(Locale.ROOT);
            if (u.startsWith("PLC ")) continue;
            if (u.startsWith("METER=")) continue;
            if (u.startsWith("PANEL=")) continue;
            if (u.startsWith("PANEL_NAME=")) continue;
            if (u.startsWith("PANNEL=")) continue;
            if (u.startsWith("RULE=")) continue;
            if (t.startsWith("패널=")) continue;
            if (t.startsWith("판넬=")) continue;
            keep.add(t);
        }
        if (!keep.isEmpty()) return String.join(", ", keep);
        return s;
    }
%>
<%
    request.setCharacterEncoding("UTF-8");

    String meterId = request.getParameter("meter_id");
    String buildingName = request.getParameter("building_name");
    String usageType = request.getParameter("usage_type");
    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");
    // backward compatibility
    String fromDate = request.getParameter("from_date");
    String toDate = request.getParameter("to_date");
    boolean initialLoad =
        (meterId == null || meterId.trim().isEmpty()) &&
        (buildingName == null || buildingName.trim().isEmpty()) &&
        (usageType == null || usageType.trim().isEmpty()) &&
        ((startDate == null || startDate.trim().isEmpty()) && (fromDate == null || fromDate.trim().isEmpty())) &&
        ((endDate == null || endDate.trim().isEmpty()) && (toDate == null || toDate.trim().isEmpty())) &&
        (startTime == null || startTime.trim().isEmpty()) &&
        (endTime == null || endTime.trim().isEmpty());

    if (meterId == null) meterId = "";
    if (buildingName == null) buildingName = "";
    if (usageType == null) usageType = "";
    if (fromDate == null) fromDate = "";
    if (toDate == null) toDate = "";
    if (startDate == null || startDate.trim().isEmpty()) startDate = fromDate;
    if (endDate == null || endDate.trim().isEmpty()) endDate = toDate;

    if (initialLoad) {
        LocalDate today = LocalDate.now();
        startDate = today.minusDays(1).toString();
        endDate = today.toString();
    }
    if (startTime == null || startTime.trim().isEmpty()) startTime = "00:00:00";
    if (endTime == null || endTime.trim().isEmpty()) endTime = "23:59:59";

    List<String[]> meterOptions = new ArrayList<>(); // [meter_id, meter_name]
    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<Map<String, Object>> alarms = new ArrayList<>();
    String error = null;

    try {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT building_name FROM vw_alarm_log WHERE building_name IS NOT NULL ORDER BY building_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) buildingOptions.add(rs.getString(1));
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT usage_type FROM vw_alarm_log WHERE usage_type IS NOT NULL ORDER BY usage_type");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) usageOptions.add(rs.getString(1));
        }

        StringBuilder meterSql = new StringBuilder();
        meterSql.append("SELECT meter_id, name FROM meters WHERE 1=1 ");
        List<Object> meterParams = new ArrayList<>();
        if (!buildingName.isEmpty()) {
            meterSql.append("AND building_name = ? ");
            meterParams.add(buildingName);
        }
        if (!usageType.isEmpty()) {
            meterSql.append("AND usage_type = ? ");
            meterParams.add(usageType);
        }
        meterSql.append("ORDER BY meter_id");
        try (PreparedStatement ps = conn.prepareStatement(meterSql.toString())) {
            for (int i = 0; i < meterParams.size(); i++) ps.setObject(i + 1, meterParams.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    meterOptions.add(new String[]{ rs.getString("meter_id"), rs.getString("name") });
                }
            }
        }

        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 2000 ")
           .append("  alarm_id, meter_id, meter_name, panel_name, building_name, usage_type, ")
           .append("  alarm_type, severity, triggered_at, cleared_at, description ")
           .append("FROM vw_alarm_log WHERE 1=1 ");

        List<Object> params = new ArrayList<>();

        if (!meterId.isEmpty()) {
            try {
                sql.append("AND meter_id = ? ");
                params.add(Integer.parseInt(meterId));
            } catch (Exception ignore) {
                meterId = "";
            }
        }
        if (!buildingName.isEmpty()) {
            sql.append("AND building_name = ? ");
            params.add(buildingName);
        }
        if (!usageType.isEmpty()) {
            sql.append("AND usage_type = ? ");
            params.add(usageType);
        }
        if (!startDate.isEmpty() && !endDate.isEmpty()) {
            sql.append("AND triggered_at BETWEEN ? AND ? ");
            params.add(startDate + " " + startTime);
            params.add(endDate + " " + endTime);
        }
        sql.append("ORDER BY triggered_at DESC");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setObject(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("alarm_id", rs.getLong("alarm_id"));
                    row.put("meter_id", rs.getInt("meter_id"));
                    row.put("meter_name", rs.getString("meter_name"));
                    row.put("panel_name", rs.getString("panel_name"));
                    row.put("building_name", rs.getString("building_name"));
                    row.put("usage_type", rs.getString("usage_type"));
                    row.put("alarm_type", rs.getString("alarm_type"));
                    row.put("severity", rs.getString("severity"));
                    row.put("triggered_at", rs.getTimestamp("triggered_at"));
                    row.put("cleared_at", rs.getTimestamp("cleared_at"));
                    row.put("description", rs.getString("description"));
                    alarms.add(row);
                }
            }
        }
    } catch (Exception e) {
        error = "조회 실패: " + e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }

    String filterQuery =
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
    <title>알람 목록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-meter-status.page-alarm { height: auto; min-height: 100vh; overflow: auto; }
        .page-meter-status.page-alarm .dash { height: auto; min-height: 100vh; }
        .page-meter-status.page-alarm .dash-main { overflow: auto; }
        .table-wrap { flex: 1 1 auto; min-height: 0; overflow: auto; }
        .alarm-table { table-layout: auto; margin-bottom: 0; }
        .alarm-table th, .alarm-table td { white-space: nowrap; text-align: center; }
        .alarm-table tbody tr { cursor: pointer; }
        .alarm-table tbody tr:hover { background: #f3f8ff; }
        .sev-High { color: #b42318; font-weight: 700; }
        .sev-Medium { color: #b54708; font-weight: 700; }
        .sev-Low { color: #027a48; font-weight: 700; }
        .filter-box { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .filter-box label { font-weight: 700; }
        .filter-box input, .filter-box select { min-width: 120px; margin: 0; }
        .filter-box button { margin: 0; }
    </style>
</head>
<body class="page-meter-status page-alarm">
<div class="dash">
    <div class="dash-top">
        <div class="title-bar">
            <h2>🚨 알람 목록</h2>
            <button class="back-btn" type="button" onclick="location.href='epms_main.jsp'">EPMS 홈</button>
        </div>

        <form method="get" class="search-form" id="alarmFilterForm">
            <div class="form-row" style="width:100%;">
                <div class="card" style="flex: 1 1 auto; margin: 0;">
                    <div class="filter-box">
                        <label for="building_name">건물</label>
                        <select id="building_name" name="building_name">
                            <option value="">전체</option>
                            <% for (String b : buildingOptions) { %>
                                <option value="<%= h(b) %>" <%= b.equals(buildingName) ? "selected" : "" %>><%= h(b) %></option>
                            <% } %>
                        </select>

                        <label for="usage_type">용도</label>
                        <select id="usage_type" name="usage_type">
                            <option value="">전체</option>
                            <% for (String u : usageOptions) { %>
                                <option value="<%= h(u) %>" <%= u.equals(usageType) ? "selected" : "" %>><%= h(u) %></option>
                            <% } %>
                        </select>

                        <label for="meter_id">Meter</label>
                        <select id="meter_id" name="meter_id">
                            <option value="">전체</option>
                            <% for (String[] m : meterOptions) { %>
                                <option value="<%= h(m[0]) %>" <%= m[0].equals(meterId) ? "selected" : "" %>><%= h(m[1]) %> (#<%= h(m[0]) %>)</option>
                            <% } %>
                        </select>

                        <label for="startDate">기간</label>
                        <input id="startDate" type="date" name="startDate" value="<%= startDate %>">
                        <input id="startTime" type="time" step="1" name="startTime" value="<%= startTime %>">
                        <span>~</span>
                        <input id="endDate" type="date" name="endDate" value="<%= endDate %>">
                        <input id="endTime" type="time" step="1" name="endTime" value="<%= endTime %>">

                        <button type="submit">조회</button>
                    </div>
                </div>
            </div>
        </form>
    </div>

    <div class="dash-main" style="display:flex; min-height:0;">
        <section class="panel_s" style="width:100%; min-height:0;">
            <% if (error != null && !error.trim().isEmpty()) { %>
            <div class="msg-box"><%= h(error) %></div>
            <% } %>
            <div style="font-weight:700; margin-bottom:8px;">조회 건수: <%= alarms.size() %></div>
            <div class="table-wrap">
                <table class="alarm-table">
                    <thead>
                    <tr>
                        <th>발생시각</th>
                        <th>건물</th>
                        <th>용도</th>
                        <th>미터</th>
                        <th>패널명</th>
                        <th>알람유형</th>
                        <th>심각도</th>
                        <th>해제시각</th>
                        <th>설명</th>
                    </tr>
                    </thead>
                    <tbody>
                    <% for (Map<String, Object> a : alarms) {
                        long aid = (Long) a.get("alarm_id");
                        Object clearedObj = a.get("cleared_at");
                        String clearedText = (clearedObj == null) ? "-" : String.valueOf(clearedObj);
                        if ("null".equalsIgnoreCase(clearedText.trim()) || clearedText.trim().isEmpty()) clearedText = "-";
                    %>
                        <tr onclick="location.href='alarm_detail.jsp?alarm_id=<%= aid %>&<%= filterQuery %>'">
                            <td><%= h(a.get("triggered_at")) %></td>
                            <td><%= h(a.get("building_name")) %></td>
                            <td><%= h(a.get("usage_type")) %></td>
                            <td><%= h(a.get("meter_name")) %> (#<%= h(a.get("meter_id")) %>)</td>
                            <td><%= h(a.get("panel_name")) %></td>
                            <td><%= h(a.get("alarm_type")) %></td>
                            <td class="sev-<%= h(a.get("severity")) %>"><%= h(a.get("severity")) %></td>
                            <td><%= h(clearedText) %></td>
                            <td><%= h(cleanAlarmDesc(a.get("description"))) %></td>
                        </tr>
                    <% } %>
                    <% if (alarms.isEmpty()) { %>
                        <tr><td colspan="9" style="text-align:center;">조회 결과가 없습니다.</td></tr>
                    <% } %>
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>
<script>
(function(){
    const form = document.getElementById("alarmFilterForm");
    const building = document.getElementById("building_name");
    const usage = document.getElementById("usage_type");
    const meter = document.getElementById("meter_id");
    if (!form || !building || !usage || !meter) return;

    function refreshMeterOptions() {
        meter.value = "";
        form.submit();
    }

    building.addEventListener("change", refreshMeterOptions);
    usage.addEventListener("change", refreshMeterOptions);
})();
</script>
</body>
</html>

