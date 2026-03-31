<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.net.URLEncoder, java.time.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String normalizeSeverity(Object v) {
        String s = v == null ? "" : String.valueOf(v).trim().toUpperCase(Locale.ROOT);
        if ("CRITICAL".equals(s) || "HIGH".equals(s)) return "CRITICAL";
        if ("ALARM".equals(s) || "MEDIUM".equals(s)) return "ALARM";
        return "NORMAL";
    }

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
    try (Connection conn = openDbConnection()) {
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
    String pageParam = request.getParameter("page");
    String pageSizeParam = request.getParameter("page_size");

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

    int currentPage = 1;
    try {
        if (pageParam != null && !pageParam.trim().isEmpty()) currentPage = Integer.parseInt(pageParam.trim());
    } catch (Exception ignore) {}
    if (currentPage < 1) currentPage = 1;
    int pageSize = 100;
    try {
        if (pageSizeParam != null && !pageSizeParam.trim().isEmpty()) pageSize = Integer.parseInt(pageSizeParam.trim());
    } catch (Exception ignore) {}
    if (!(pageSize == 50 || pageSize == 100 || pageSize == 150 || pageSize == 200)) pageSize = 100;
    int totalCount = 0;
    int totalPages = 1;

    List<String[]> meterOptions = new ArrayList<>(); // [meter_id, meter_name]
    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String> severityOptions = new ArrayList<>();
    List<String> eventTypeOptions = new ArrayList<>();
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

        severityOptions.add("NORMAL");
        severityOptions.add("ALARM");
        severityOptions.add("CRITICAL");

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT event_type FROM dbo.device_events WHERE event_type IS NOT NULL ORDER BY event_type");
             ResultSet rs = ps.executeQuery()) {
            LinkedHashSet<String> eventTypeSet = new LinkedHashSet<String>();
            while (rs.next()) {
                String cleaned = cleanEventType(rs.getString(1));
                if (cleaned != null) {
                    cleaned = cleaned.trim();
                    if (!cleaned.isEmpty()) eventTypeSet.add(cleaned);
                }
            }
            eventTypeOptions.addAll(eventTypeSet);
        }

        StringBuilder fromWhere = new StringBuilder();
        fromWhere.append("FROM dbo.device_events de ")
                 .append("LEFT JOIN dbo.meters m ON m.meter_id = de.device_id ")
                 .append("WHERE 1=1 ");

        List<Object> params = new ArrayList<>();

        if (!meterId.isEmpty()) {
            try {
                fromWhere.append("AND de.device_id = ? ");
                params.add(Integer.parseInt(meterId));
            } catch (Exception ignore) { meterId = ""; }
        }
        if (!buildingName.isEmpty()) {
            fromWhere.append("AND m.building_name = ? ");
            params.add(buildingName);
        }
        if (!usageType.isEmpty()) {
            fromWhere.append("AND m.usage_type = ? ");
            params.add(usageType);
        }
        if (!severity.isEmpty()) {
            fromWhere.append("AND CASE ")
                     .append("WHEN UPPER(ISNULL(de.severity,'')) IN ('CRITICAL','HIGH') THEN 'CRITICAL' ")
                     .append("WHEN UPPER(ISNULL(de.severity,'')) IN ('ALARM','MEDIUM') THEN 'ALARM' ")
                     .append("ELSE 'NORMAL' END = ? ");
            params.add(severity);
        }
        if (!eventType.isEmpty()) {
            fromWhere.append("AND CASE ")
                     .append("WHEN UPPER(ISNULL(de.event_type,'')) IN ('DI_TAG_ON1_OFF1_ST1','DI_TAG_ON2_OFF2_ST2','DI_ON_OFF') THEN 'DI_ON_OFF' ")
                     .append("WHEN UPPER(ISNULL(de.event_type,'')) = 'DI_TRIP_TM' THEN 'DI_TR_ALARM' ")
                     .append("WHEN UPPER(ISNULL(de.event_type,'')) = 'DI_OCGR_ALL_51G' THEN 'DI_OCGR_51G' ")
                     .append("WHEN UPPER(ISNULL(de.event_type,'')) IN ('DI-ELD','DI_ELD_14','DI_ELD_6') THEN 'DI_ELD' ")
                     .append("ELSE de.event_type END = ? ");
            params.add(eventType);
        }
        if (!startDate.isEmpty() && !endDate.isEmpty()) {
            fromWhere.append("AND de.event_time BETWEEN ? AND ? ");
            params.add(startDate + " " + startTime);
            params.add(endDate + " " + endTime);
        }
        if ("OPEN".equalsIgnoreCase(openOnly) || "Y".equalsIgnoreCase(openOnly)) {
            fromWhere.append("AND de.restored_time IS NULL ");
        } else if ("CLOSE".equalsIgnoreCase(openOnly)) {
            fromWhere.append("AND de.restored_time IS NOT NULL ");
        }

        try (PreparedStatement cps = conn.prepareStatement("SELECT COUNT(*) " + fromWhere.toString())) {
            for (int i = 0; i < params.size(); i++) {
                cps.setObject(i + 1, params.get(i));
            }
            try (ResultSet rs = cps.executeQuery()) {
                if (rs.next()) totalCount = rs.getInt(1);
            }
        }

        totalPages = Math.max(1, (int) Math.ceil(totalCount / (double) pageSize));
        if (currentPage > totalPages) currentPage = totalPages;
        int offset = (currentPage - 1) * pageSize;

        StringBuilder sql = new StringBuilder();
        sql.append("SELECT ")
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
           .append(fromWhere.toString().replaceFirst("^FROM dbo.device_events de LEFT JOIN dbo.meters m ON m.meter_id = de.device_id ", ""))
           .append("ORDER BY de.event_time DESC, de.event_id DESC ")
           .append("OFFSET ? ROWS FETCH NEXT ? ROWS ONLY");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int bindIndex = 1;
            for (int i = 0; i < params.size(); i++) {
                ps.setObject(bindIndex++, params.get(i));
            }
            ps.setInt(bindIndex++, offset);
            ps.setInt(bindIndex, pageSize);
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
    }

    String filterQuery =
        "meter_id=" + URLEncoder.encode(meterId, "UTF-8") +
        "&building_name=" + URLEncoder.encode(buildingName, "UTF-8") +
        "&usage_type=" + URLEncoder.encode(usageType, "UTF-8") +
        "&severity=" + URLEncoder.encode(severity, "UTF-8") +
        "&event_type=" + URLEncoder.encode(eventType, "UTF-8") +
        "&open_only=" + URLEncoder.encode(openOnly, "UTF-8") +
        "&startDate=" + URLEncoder.encode(startDate, "UTF-8") +
        "&startTime=" + URLEncoder.encode(startTime, "UTF-8") +
        "&endDate=" + URLEncoder.encode(endDate, "UTF-8") +
        "&endTime=" + URLEncoder.encode(endTime, "UTF-8") +
        "&page_size=" + URLEncoder.encode(String.valueOf(pageSize), "UTF-8");
    int pageWindow = 5;
    int pageStart = Math.max(1, currentPage - 2);
    int pageEnd = Math.min(totalPages, pageStart + pageWindow - 1);
    if (pageEnd - pageStart + 1 < pageWindow) {
        pageStart = Math.max(1, pageEnd - pageWindow + 1);
    }
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
        .page-meter-status.page-event .dash {
            height: auto;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            width: min(96vw, 1760px);
            margin: 0 auto;
        }
        .page-meter-status.page-event .dash-main {
            overflow: auto;
            flex: 1 1 auto;
            display: flex;
            min-height: 0;
        }
        .search-form .card {
            border-radius: 16px;
            padding: 16px 18px;
            box-shadow: 0 12px 24px rgba(15,23,42,.06);
        }
        .table-wrap {
            flex: 1 1 auto;
            min-height: 0;
            overflow: auto;
            border: 1px solid #dbe7f5;
            border-radius: 18px;
            background: #fff;
            box-shadow: inset 0 1px 0 rgba(255,255,255,.8);
        }
        .event-table { table-layout: fixed; margin-bottom: 0; width: 100%; min-width: 1450px; }
        .event-table th, .event-table td { text-align: center; vertical-align: middle; }
        .event-table th:nth-child(1), .event-table td:nth-child(1),
        .event-table th:nth-child(9), .event-table td:nth-child(9) { white-space: normal; word-break: break-word; }
        .event-table th:nth-child(4), .event-table td:nth-child(4),
        .event-table th:nth-child(5), .event-table td:nth-child(5),
        .event-table th:nth-child(6), .event-table td:nth-child(6) { white-space: normal; word-break: break-word; }
        .event-table td:nth-child(10) {
            white-space: normal;
            word-break: break-word;
            overflow-wrap: anywhere;
            text-align: left;
            line-height: 1.45;
        }
        .event-table tbody tr { cursor: pointer; }
        .event-table tbody tr:hover { background: #f3f8ff; }
        .sev-CRITICAL, .sev-High { color: #b42318; font-weight: 700; }
        .sev-ALARM, .sev-Medium { color: #b54708; font-weight: 700; }
        .sev-WARN, .sev-Low, .sev-NORMAL { color: #027a48; font-weight: 700; }
        .badge-open { color: #b42318; font-weight: 700; }
        .badge-close { color: #027a48; font-weight: 700; }
        .filter-card {
            min-height: 0;
            display: flex;
            flex-direction: column;
            align-items: stretch;
            gap: 10px;
            width: 100%;
            min-width: 0;
        }
        .filter-line {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 8px 10px;
            width: 100%;
            min-width: 0;
        }
        .filter-card label {
            font-weight: 700;
            white-space: nowrap;
            word-break: keep-all;
            flex: 0 0 auto;
        }
        .filter-card input, .filter-card select { min-width: 128px; margin: 0; }
        .filter-card .event-type-input { min-width: 180px; flex: 0 1 220px; }
        .filter-card .spacer { color: #667085; font-weight: 700; }
        .filter-card .submit-inline {
            margin-left: 4px;
            white-space: nowrap;
        }
        .count-badge {
            display: inline-flex;
            align-items: center;
            padding: 7px 14px;
            border-radius: 999px;
            border: 1px solid #cfe0ff;
            background: #eef5ff;
            color: #204f97;
            font-size: 13px;
            font-weight: 800;
            margin-bottom: 10px;
        }
        .summary-bar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            margin-bottom: 10px;
            flex-wrap: wrap;
        }
        .summary-actions {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            color: #465468;
            font-size: 13px;
            font-weight: 700;
        }
        .summary-actions select {
            min-width: 90px;
            margin: 0;
        }
        .page-footer {
            margin-top: auto;
            text-align: center;
            color: #6b7b91;
            font-size: 12px;
            padding: 12px 0 18px;
        }
        .pager {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            margin-top: 12px;
            flex-wrap: wrap;
        }
        .pager-info {
            color: #5d6b82;
            font-size: 13px;
            font-weight: 600;
        }
        .pager-links {
            display: flex;
            gap: 6px;
            flex-wrap: wrap;
        }
        .pager-links a,
        .pager-links span {
            min-width: 34px;
            height: 34px;
            padding: 0 10px;
            border-radius: 10px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            border: 1px solid #d5deea;
            background: #fff;
            color: #23415f;
            text-decoration: none;
            font-size: 13px;
            font-weight: 700;
        }
        .pager-links .active {
            background: #2f6ee5;
            border-color: #2f6ee5;
            color: #fff;
        }
        @media (max-width: 768px) {
            .filter-card .event-type-input { flex: 1 1 100%; min-width: 0; }
            .event-table { min-width: 1100px; }
        }
        .msg-box { color: #b42318; font-weight: 700; margin-bottom: 8px; }
    </style>
</head>
<body class="page-meter-status page-event">
<div class="dash">
    <div class="dash-top">
        <div class="title-bar">
            <h2>📄 이벤트 목록</h2>
            <div class="inline-actions">
                <button class="back-btn" type="button" onclick="location.href='epms_main.jsp'">EPMS 홈</button>
            </div>
        </div>

        <form method="get" class="search-form" id="eventFilterForm">
            <div class="form-row" style="width:100%;">
                <div class="card" style="flex: 1 1 auto; margin: 0;">
                    <div class="filter-card">
                        <div class="filter-line">
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
                                    <option value="<%= h(sv) %>" <%= sv.equalsIgnoreCase(severity) ? "selected" : "" %>><%= h(sv) %></option>
                                <% } %>
                            </select>

                            <label for="event_type">이벤트유형</label>
                            <select id="event_type" name="event_type" class="event-type-input">
                                <option value="">전체</option>
                                <% for (String et : eventTypeOptions) { %>
                                    <option value="<%= h(et) %>" <%= et.equals(eventType) ? "selected" : "" %>><%= h(et) %></option>
                                <% } %>
                            </select>

                            <label for="open_only">상태</label>
                            <select id="open_only" name="open_only">
                                <option value="" <%= openOnly.isEmpty() ? "selected" : "" %>>전체</option>
                                <option value="OPEN" <%= ("OPEN".equalsIgnoreCase(openOnly) || "Y".equalsIgnoreCase(openOnly)) ? "selected" : "" %>>Open</option>
                                <option value="CLOSE" <%= "CLOSE".equalsIgnoreCase(openOnly) ? "selected" : "" %>>Close</option>
                            </select>
                        </div>

                        <div class="filter-line">
                            <label for="startDate">기간</label>
                            <input id="startDate" type="date" name="startDate" value="<%= h(startDate) %>">
                            <input id="startTime" type="time" step="1" name="startTime" value="<%= h(startTime) %>">
                            <span class="spacer">~</span>
                            <input id="endDate" type="date" name="endDate" value="<%= h(endDate) %>">
                            <input id="endTime" type="time" step="1" name="endTime" value="<%= h(endTime) %>">
                            <button class="submit-inline" type="submit">조회</button>
                        </div>
                    </div>
                </div>
            </div>
        </form>
    </div>

    <div class="dash-main">
        <section class="panel_s" style="width:100%; min-height:0;">
            <% if (queryError != null) { %>
                <div class="msg-box"><%= h(queryError) %></div>
            <% } %>
            <div class="summary-bar">
                <div class="count-badge">조회 건수: <%= totalCount %></div>
                <div class="summary-actions">
                    <label for="page_size">페이지당</label>
                    <select id="page_size" name="page_size" form="eventFilterForm" onchange="this.form.submit()">
                        <option value="50" <%= pageSize == 50 ? "selected" : "" %>>50</option>
                        <option value="100" <%= pageSize == 100 ? "selected" : "" %>>100</option>
                        <option value="150" <%= pageSize == 150 ? "selected" : "" %>>150</option>
                        <option value="200" <%= pageSize == 200 ? "selected" : "" %>>200</option>
                    </select>
                    <span>개</span>
                </div>
            </div>
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
                        String eventIdStr = String.valueOf(e.get("event_id") == null ? "" : e.get("event_id"));
                        String eventTimeStr = String.valueOf(e.get("event_time") == null ? "" : e.get("event_time"));
                        String sev = normalizeSeverity(e.get("severity"));
                        boolean isOpen = (e.get("restored_time") == null);
                        Object restoredObj = e.get("restored_time");
                        String restoredText = (restoredObj == null) ? "-" : String.valueOf(restoredObj);
                        if ("null".equalsIgnoreCase(restoredText.trim()) || restoredText.trim().isEmpty()) restoredText = "-";
                    %>
                        <tr data-event-id="<%= h(eventIdStr) %>" data-meter-id="<%= h(meterIdStr) %>" data-event-time="<%= h(eventTimeStr) %>" onclick="goEventDetail(this)">
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
            <div class="pager">
                <div class="pager-info">페이지 <%= currentPage %> / <%= totalPages %></div>
                <div class="pager-links">
                    <% if (currentPage > 1) { %>
                        <a href="event_view.jsp?<%= filterQuery %>&page=<%= currentPage - 1 %>">이전</a>
                    <% } %>
                    <% for (int p = pageStart; p <= pageEnd; p++) { %>
                        <% if (p == currentPage) { %>
                            <span class="active"><%= p %></span>
                        <% } else { %>
                            <a href="event_view.jsp?<%= filterQuery %>&page=<%= p %>"><%= p %></a>
                        <% } %>
                    <% } %>
                    <% if (currentPage < totalPages) { %>
                        <a href="event_view.jsp?<%= filterQuery %>&page=<%= currentPage + 1 %>">다음</a>
                    <% } %>
                </div>
            </div>
        </section>
    </div>
    <footer class="page-footer">© EPMS Dashboard | SNUT CNT</footer>
</div>

<script>
function goEventDetail(tr) {
    const eventId = tr.getAttribute("data-event-id");
    const meterId = tr.getAttribute("data-meter-id");
    const eventTime = tr.getAttribute("data-event-time");
    if (!eventId && (!meterId || !eventTime)) {
        alert("이벤트 전달 파라미터가 없습니다.");
        return;
    }
    let url = "event_detail.jsp?";
    if (eventId) {
        url += "event_id=" + encodeURIComponent(eventId);
    } else {
        url += "meter_id=" + encodeURIComponent(meterId) +
               "&event_time=" + encodeURIComponent(eventTime);
    }
    location.href = url;
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
<%
    }
%>
</body>
</html>

