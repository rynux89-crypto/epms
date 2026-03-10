<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.net.URLEncoder, java.time.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String cleanEventDesc(Object v) {
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

    private static String cleanEventType(Object v) {
        if (v == null) return "";
        String s = String.valueOf(v).trim();
        if ("DI_TAG_ON1_OFF1_ST1".equalsIgnoreCase(s)) return "DI_ON_OFF";
        if ("DI_TAG_ON2_OFF2_ST2".equalsIgnoreCase(s)) return "DI_ON_OFF";
        if ("DI_On_OFF".equalsIgnoreCase(s)) return "DI_ON_OFF";
        if ("DI_TRIP_TM".equalsIgnoreCase(s)) return "DI_TR_ALARM";
        if ("DI_OCGR_ALL_51G".equalsIgnoreCase(s)) return "DI_OCGR_51G";
        if ("DI-ELD".equalsIgnoreCase(s)) return "DI_ELD";
        if ("DI_ELD_14".equalsIgnoreCase(s)) return "DI_ELD";
        if ("DI_ELD_6".equalsIgnoreCase(s)) return "DI_ELD";
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
    String severity = request.getParameter("severity");
    String eventType = request.getParameter("event_type");
    String openOnly = request.getParameter("open_only");

    if (meterId == null) meterId = "";
    if (buildingName == null) buildingName = "";
    if (usageType == null) usageType = "";
    if (fromDate == null) fromDate = "";
    if (toDate == null) toDate = "";
    if (startDate == null || startDate.trim().isEmpty()) startDate = fromDate;
    if (endDate == null || endDate.trim().isEmpty()) endDate = toDate;
    if (startTime == null) startTime = "";
    if (endTime == null) endTime = "";
    if (severity == null) severity = "";
    if (eventType == null) eventType = "";
    if (openOnly == null) openOnly = "";

    boolean initialLoad =
        meterId.isEmpty() && buildingName.isEmpty() && usageType.isEmpty() &&
        startDate.isEmpty() && endDate.isEmpty() && severity.isEmpty() && eventType.isEmpty() && openOnly.isEmpty() &&
        startTime.isEmpty() && endTime.isEmpty();
    if (initialLoad) {
        LocalDate today = LocalDate.now();
        startDate = today.minusDays(1).toString();
        endDate = today.toString();
    }
    if (startTime.trim().isEmpty()) startTime = "00:00:00";
    if (endTime.trim().isEmpty()) endTime = "23:59:59";

    List<String[]> meterOptions = new ArrayList<>(); // [meter_id, meter_name]
    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String> severityOptions = new ArrayList<>();
    List<Map<String, Object>> events = new ArrayList<>();
    String queryError = null;

    try {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT building_name FROM meters WHERE building_name IS NOT NULL ORDER BY building_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) buildingOptions.add(rs.getString(1));
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT usage_type FROM meters WHERE usage_type IS NOT NULL ORDER BY usage_type");
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
            for (int i = 0; i < meterParams.size(); i++) {
                ps.setObject(i + 1, meterParams.get(i));
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    meterOptions.add(new String[]{ rs.getString("meter_id"), rs.getString("name") });
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT severity FROM dbo.device_events WHERE severity IS NOT NULL ORDER BY severity");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) severityOptions.add(rs.getString(1));
        }

        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 2000 ")
           .append("  de.event_id, de.device_id, m.name AS meter_name, m.panel_name, m.building_name, m.usage_type, ")
           .append("  de.event_type, de.severity, de.event_time, de.restored_time, de.description, ")
           .append("  alink.alarm_id ")
           .append("FROM dbo.device_events de ")
           .append("LEFT JOIN dbo.meters m ON m.meter_id = de.device_id ")
           .append("OUTER APPLY ( ")
           .append("  SELECT TOP 1 al.alarm_id ")
           .append("  FROM dbo.alarm_log al ")
           .append("  WHERE al.meter_id = de.device_id ")
           .append("    AND al.alarm_type = de.event_type ")
           .append("    AND ABS(DATEDIFF(SECOND, al.triggered_at, de.event_time)) <= 5 ")
           .append("  ORDER BY ABS(DATEDIFF(SECOND, al.triggered_at, de.event_time)), al.alarm_id DESC ")
           .append(") alink ")
           .append("WHERE 1=1 ");

        List<Object> params = new ArrayList<>();

        if (!meterId.isEmpty()) {
            try {
                sql.append("AND de.device_id = ? ");
                params.add(Integer.parseInt(meterId));
            } catch (Exception ignore) { meterId = ""; }
        }
        if (!buildingName.isEmpty()) {
            sql.append("AND m.building_name = ? ");
            params.add(buildingName);
        }
        if (!usageType.isEmpty()) {
            sql.append("AND m.usage_type = ? ");
            params.add(usageType);
        }
        if (!severity.isEmpty()) {
            sql.append("AND de.severity = ? ");
            params.add(severity);
        }
        if (!eventType.isEmpty()) {
            sql.append("AND de.event_type LIKE ? ");
            params.add("%" + eventType + "%");
        }
        if (!startDate.isEmpty() && !endDate.isEmpty()) {
            sql.append("AND de.event_time BETWEEN ? AND ? ");
            params.add(startDate + " " + startTime);
            params.add(endDate + " " + endTime);
        }
        if ("OPEN".equalsIgnoreCase(openOnly) || "Y".equalsIgnoreCase(openOnly)) {
            sql.append("AND de.restored_time IS NULL ");
        } else if ("CLOSE".equalsIgnoreCase(openOnly)) {
            sql.append("AND de.restored_time IS NOT NULL ");
        }
        sql.append("ORDER BY de.event_time DESC, de.event_id DESC");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setObject(i + 1, params.get(i));
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("event_id", rs.getLong("event_id"));
                    row.put("device_id", rs.getInt("device_id"));
                    row.put("meter_name", rs.getString("meter_name"));
                    row.put("panel_name", rs.getString("panel_name"));
                    row.put("building_name", rs.getString("building_name"));
                    row.put("usage_type", rs.getString("usage_type"));
                    row.put("event_type", rs.getString("event_type"));
                    row.put("severity", rs.getString("severity"));
                    row.put("event_time", rs.getTimestamp("event_time"));
                    row.put("restored_time", rs.getTimestamp("restored_time"));
                    row.put("description", rs.getString("description"));
                    row.put("alarm_id", rs.getObject("alarm_id"));
                    events.add(row);
                }
            }
        }
    } catch (Exception e) {
        queryError = e.getMessage();
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
    <title>이벤트 목록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-meter-status.page-event { height: auto; min-height: 100vh; overflow: auto; }
        .page-meter-status.page-event .dash { height: auto; min-height: 100vh; }
        .page-meter-status.page-event .dash-main { overflow: auto; }
        .table-wrap { flex: 1 1 auto; min-height: 0; overflow: auto; }
        .event-table { table-layout: auto; margin-bottom: 0; }
        .event-table th, .event-table td { white-space: nowrap; text-align: center; }
        .event-table tbody tr { cursor: pointer; }
        .event-table tbody tr:hover { background: #f3f8ff; }
        .sev-CRITICAL, .sev-High { color: #b42318; font-weight: 700; }
        .sev-ALARM, .sev-Medium { color: #b54708; font-weight: 700; }
        .sev-WARN, .sev-Low { color: #027a48; font-weight: 700; }
        .badge-open { color: #b42318; font-weight: 700; }
        .badge-close { color: #027a48; font-weight: 700; }
        .filter-box { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .filter-box + .filter-box { margin-top: 8px; }
        .filter-box label { font-weight: 700; }
        .filter-box input, .filter-box select { min-width: 120px; margin: 0; }
        .filter-box .event-type-input { min-width: 120px; flex: 0 1 140px; }
        .filter-box .period-sep { color: #667085; font-weight: 700; }
        .filter-box button { margin: 0; }
        @media (max-width: 768px) {
            .filter-box .event-type-input { flex: 1 1 100%; min-width: 0; }
        }
        .msg-box { color: #b42318; font-weight: 700; margin-bottom: 8px; }
    </style>
</head>
<body class="page-meter-status page-event">
<div class="dash">
    <div class="dash-top">
        <div class="title-bar">
            <h2>이벤트 목록</h2>
            <button class="back-btn" type="button" onclick="location.href='epms_main.jsp'">EPMS 홈</button>
        </div>

        <form method="get" class="search-form" id="eventFilterForm">
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

                        <label for="meter_id">미터</label>
                        <select id="meter_id" name="meter_id">
                            <option value="">전체</option>
                            <% for (String[] m : meterOptions) { %>
                                <option value="<%= h(m[0]) %>" <%= m[0].equals(meterId) ? "selected" : "" %>><%= h(m[1]) %> (#<%= h(m[0]) %>)</option>
                            <% } %>
                        </select>

                        <label for="severity">심각도</label>
                        <select id="severity" name="severity">
                            <option value="">전체</option>
                            <% for (String sv : severityOptions) { %>
                                <option value="<%= h(sv) %>" <%= sv.equals(severity) ? "selected" : "" %>><%= h(sv) %></option>
                            <% } %>
                        </select>

                        <label for="event_type">이벤트유형</label>
                        <input id="event_type" class="event-type-input" type="text" name="event_type" value="<%= h(eventType) %>" placeholder="예: OCR / DI_">

                        <label for="open_only">상태</label>
                        <select id="open_only" name="open_only">
                            <option value="" <%= openOnly.isEmpty() ? "selected" : "" %>>전체</option>
                            <option value="OPEN" <%= ("OPEN".equalsIgnoreCase(openOnly) || "Y".equalsIgnoreCase(openOnly)) ? "selected" : "" %>>Open</option>
                            <option value="CLOSE" <%= "CLOSE".equalsIgnoreCase(openOnly) ? "selected" : "" %>>Close</option>
                        </select>

                        
                    </div>

                    <div class="filter-box">
                        <label for="startDate">기간</label>
                        <input id="startDate" type="date" name="startDate" value="<%= h(startDate) %>">
                        <input id="startTime" type="time" step="1" name="startTime" value="<%= h(startTime) %>">
                        <span class="period-sep">~</span>
                        <input id="endDate" type="date" name="endDate" value="<%= h(endDate) %>">
                        <input id="endTime" type="time" step="1" name="endTime" value="<%= h(endTime) %>">
                        <button type="submit">조회</button>
                    </div>
                    
                </div>
            </div>
        </form>
    </div>

    <div class="dash-main" style="display:flex; min-height:0;">
        <section class="panel_s" style="width:100%; min-height:0;">
            <% if (queryError != null) { %>
                <div class="msg-box"><%= h(queryError) %></div>
            <% } %>
            <div style="font-weight:700; margin-bottom:8px;">조회 건수: <%= events.size() %></div>
            <div class="table-wrap">
                <table class="event-table">
                    <thead>
                    <tr>
                        <th>발생시각</th>
                        <th>건물</th>
                        <th>용도</th>
                        <th>미터</th>
                        <th>패널명</th>
                        <th>이벤트유형</th>
                        <th>심각도</th>
                        <th>상태</th>
                        <th>해제시각</th>
                        <th>설명</th>
                    </tr>
                    </thead>
                    <tbody>
                    <% for (Map<String, Object> e : events) {
                        String meterIdStr = String.valueOf(e.get("device_id") == null ? "" : e.get("device_id"));
                        String eventTimeStr = String.valueOf(e.get("event_time") == null ? "" : e.get("event_time"));
                        String sev = String.valueOf(e.get("severity") == null ? "" : e.get("severity"));
                        boolean isOpen = (e.get("restored_time") == null);
                        Object restoredObj = e.get("restored_time");
                        String restoredText = (restoredObj == null) ? "-" : String.valueOf(restoredObj);
                        if ("null".equalsIgnoreCase(restoredText.trim()) || restoredText.trim().isEmpty()) restoredText = "-";
                    %>
                        <tr data-meter-id="<%= h(meterIdStr) %>" data-event-time="<%= h(eventTimeStr) %>" onclick="goEventDetail(this)">
                            <td><%= h(e.get("event_time")) %></td>
                            <td><%= h(e.get("building_name")) %></td>
                            <td><%= h(e.get("usage_type")) %></td>
                            <td><%= h(e.get("meter_name")) %> (#<%= h(e.get("device_id")) %>)</td>
                            <td><%= h(e.get("panel_name")) %></td>
                            <td><%= h(cleanEventType(e.get("event_type"))) %></td>
                            <td class="sev-<%= h(sev) %>"><%= h(sev) %></td>
                            <td class="<%= isOpen ? "badge-open" : "badge-close" %>"><%= isOpen ? "OPEN" : "CLOSED" %></td>
                            <td><%= h(restoredText) %></td>
                            <td><%= h(cleanEventDesc(e.get("description"))) %></td>
                        </tr>
                    <% } %>
                    <% if (events.isEmpty()) { %>
                        <tr><td colspan="10" style="text-align:center;">조회 결과가 없습니다.</td></tr>
                    <% } %>
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>

<script>
function goEventDetail(tr) {
    const meterId = tr.getAttribute("data-meter-id");
    const eventTime = tr.getAttribute("data-event-time");
    if (!meterId || !eventTime) {
        alert("이벤트 전달 파라미터가 없습니다.");
        return;
    }
    location.href = "event_detail.jsp?meter_id=" + encodeURIComponent(meterId) +
                    "&event_time=" + encodeURIComponent(eventTime);
}

(function(){
    const form = document.getElementById("eventFilterForm");
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

