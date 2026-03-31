<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.net.URLEncoder, java.time.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static final java.time.format.DateTimeFormatter TS_FMT =
        java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private static String formatTs(Object v) {
        if (v == null) return "";
        if (v instanceof Timestamp) {
            LocalDateTime ldt = ((Timestamp) v).toLocalDateTime();
            return TS_FMT.format(ldt);
        }
        String s = String.valueOf(v).trim();
        int dot = s.indexOf('.');
        return dot >= 0 ? s.substring(0, dot) : s;
    }

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
            if (u.startsWith("STAGE=")) continue;
            if (t.startsWith("패널=")) continue;
            if (t.startsWith("판넬=")) continue;
            keep.add(t);
        }
        if (!keep.isEmpty()) return String.join(", ", keep);
        return s;
    }

    private static String formatAlarmDescHtml(Object v) {
        String cleaned = cleanAlarmDesc(v);
        if (cleaned == null || cleaned.isEmpty()) return "";
        String escaped = h(cleaned);
        return escaped
            .replace(", ", "<br>")
            .replace(",", ",<wbr>")
            .replace("=", "=<wbr>")
            .replace("_", "_<wbr>");
    }

    private static String extractDescField(Object descObj, String key) {
        if (descObj == null || key == null || key.trim().isEmpty()) return "";
        String desc = String.valueOf(descObj);
        String target = key.trim().toLowerCase(Locale.ROOT) + "=";
        String lower = desc.toLowerCase(Locale.ROOT);
        int idx = lower.indexOf(target);
        if (idx < 0) return "";
        int start = idx + target.length();
        int end = desc.indexOf(',', start);
        if (end < 0) end = desc.indexOf('|', start);
        if (end < 0) end = desc.length();
        return desc.substring(start, end).trim();
    }

    private static String buildMeterDisplay(Map<String, Object> a) {
        String meterName = String.valueOf(a.get("meter_name") == null ? "" : a.get("meter_name")).trim();
        String desc = String.valueOf(a.get("description") == null ? "" : a.get("description"));
        String item = extractDescField(desc, "item");
        if (meterName.isEmpty()) {
            if (!item.isEmpty()) return item;
            return "-";
        }
        return meterName;
    }

    private static String buildPanelDisplay(Map<String, Object> a) {
        String panelName = String.valueOf(a.get("panel_name") == null ? "" : a.get("panel_name")).trim();
        if (!panelName.isEmpty()) return panelName;
        String desc = String.valueOf(a.get("description") == null ? "" : a.get("description"));
        String panel = extractDescField(desc, "panel");
        return panel.isEmpty() ? "-" : panel;
    }

    private static String buildAlarmTypeDisplay(Map<String, Object> a) {
        String ruleName = String.valueOf(a.get("rule_name") == null ? "" : a.get("rule_name")).trim();
        if (!ruleName.isEmpty()) return ruleName;
        String ruleCode = String.valueOf(a.get("rule_code") == null ? "" : a.get("rule_code")).trim();
        if (!ruleCode.isEmpty()) return ruleCode;
        String alarmType = String.valueOf(a.get("alarm_type") == null ? "" : a.get("alarm_type")).trim();
        return alarmType.isEmpty() ? "-" : alarmType;
    }
%>
<%
    try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String meterId = request.getParameter("meter_id");
    String diKey = request.getParameter("di_key");
    String panelName = request.getParameter("panel_name");
    String ruleCode = request.getParameter("rule_code");
    String buildingName = request.getParameter("building_name");
    String usageType = request.getParameter("usage_type");
    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");
    String openOnly = request.getParameter("open_only");
    String pageParam = request.getParameter("page");
    String pageSizeParam = request.getParameter("page_size");
    // backward compatibility
    String fromDate = request.getParameter("from_date");
    String toDate = request.getParameter("to_date");
    boolean openOnlyChecked = "Y".equalsIgnoreCase(openOnly) || "true".equalsIgnoreCase(openOnly) || "on".equalsIgnoreCase(openOnly);
    boolean initialLoad =
        (meterId == null || meterId.trim().isEmpty()) &&
        (ruleCode == null || ruleCode.trim().isEmpty()) &&
        (panelName == null || panelName.trim().isEmpty()) &&
        (buildingName == null || buildingName.trim().isEmpty()) &&
        (usageType == null || usageType.trim().isEmpty()) &&
        ((startDate == null || startDate.trim().isEmpty()) && (fromDate == null || fromDate.trim().isEmpty())) &&
        ((endDate == null || endDate.trim().isEmpty()) && (toDate == null || toDate.trim().isEmpty())) &&
        (startTime == null || startTime.trim().isEmpty()) &&
        (endTime == null || endTime.trim().isEmpty());

    if (meterId == null) meterId = "";
    if (diKey == null) diKey = "";
    if (panelName == null) panelName = "";
    if (ruleCode == null) ruleCode = "";
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

    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String> panelOptions = new ArrayList<>();
    List<Map<String, String>> ruleOptions = new ArrayList<>();
    List<Map<String, Object>> alarms = new ArrayList<>();
    String error = null;

    try {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT m.building_name " +
                "FROM dbo.alarm_log a LEFT JOIN dbo.meters m ON m.meter_id = a.meter_id " +
                "WHERE m.building_name IS NOT NULL ORDER BY m.building_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) buildingOptions.add(rs.getString(1));
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT m.usage_type " +
                "FROM dbo.alarm_log a LEFT JOIN dbo.meters m ON m.meter_id = a.meter_id " +
                "WHERE m.usage_type IS NOT NULL ORDER BY m.usage_type");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) usageOptions.add(rs.getString(1));
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT panel_name FROM ( " +
                "  SELECT DISTINCT m.panel_name AS panel_name " +
                "  FROM dbo.alarm_log a LEFT JOIN dbo.meters m ON m.meter_id = a.meter_id " +
                "  WHERE m.panel_name IS NOT NULL AND LTRIM(RTRIM(m.panel_name)) <> '' " +
                "  UNION " +
                "  SELECT DISTINCT panel_name " +
                "  FROM dbo.plc_di_tag_map " +
                "  WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> '' " +
                ") x ORDER BY panel_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) panelOptions.add(rs.getString(1));
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT r.rule_code, r.rule_name " +
                "FROM dbo.alarm_rule r " +
                "WHERE r.enabled = 1 " +
                "ORDER BY r.rule_name, r.rule_code");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> opt = new HashMap<>();
                opt.put("rule_code", rs.getString("rule_code"));
                opt.put("rule_name", rs.getString("rule_name"));
                ruleOptions.add(opt);
            }
        }

        StringBuilder fromWhere = new StringBuilder();
        fromWhere.append("FROM dbo.alarm_log a ")
                 .append("LEFT JOIN dbo.meters m ON m.meter_id = a.meter_id ")
                 .append("LEFT JOIN dbo.alarm_rule r ON r.rule_id = a.rule_id ")
                 .append("WHERE 1=1 ");

        List<Object> params = new ArrayList<Object>();

        if (!buildingName.isEmpty()) {
            fromWhere.append("AND m.building_name = ? ");
            params.add(buildingName);
        }
        if (!usageType.isEmpty()) {
            fromWhere.append("AND m.usage_type = ? ");
            params.add(usageType);
        }
        if (!panelName.isEmpty()) {
            fromWhere.append("AND (m.panel_name = ? OR a.description LIKE ?) ");
            params.add(panelName);
            params.add("%panel=" + panelName + "%");
        }
        if (!ruleCode.isEmpty()) {
            fromWhere.append("AND COALESCE(NULLIF(a.rule_code,''), NULLIF(r.rule_code,''), NULLIF(a.alarm_type,'')) = ? ");
            params.add(ruleCode);
        }
        if (openOnlyChecked) {
            fromWhere.append("AND a.cleared_at IS NULL ");
        }
        if (!startDate.isEmpty() && !endDate.isEmpty()) {
            fromWhere.append("AND a.triggered_at BETWEEN ? AND ? ");
            params.add(startDate + " " + startTime);
            params.add(endDate + " " + endTime);
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
           .append("  a.alarm_id, a.meter_id, m.name AS meter_name, m.panel_name, m.building_name, m.usage_type, ")
           .append("  a.alarm_type, a.rule_code, r.rule_name, a.severity, a.triggered_at, a.cleared_at, a.description ")
           .append(fromWhere)
           .append("ORDER BY a.triggered_at DESC, a.alarm_id DESC ")
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
                    row.put("alarm_id", rs.getLong("alarm_id"));
                    row.put("meter_id", rs.getInt("meter_id"));
                    row.put("meter_name", rs.getString("meter_name"));
                    row.put("panel_name", rs.getString("panel_name"));
                    row.put("building_name", rs.getString("building_name"));
                    row.put("usage_type", rs.getString("usage_type"));
                    row.put("alarm_type", rs.getString("alarm_type"));
                    row.put("rule_code", rs.getString("rule_code"));
                    row.put("rule_name", rs.getString("rule_name"));
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
    }

    String filterQuery =
        "panel_name=" + URLEncoder.encode(panelName, "UTF-8") +
        "&rule_code=" + URLEncoder.encode(ruleCode, "UTF-8") +
        "&building_name=" + URLEncoder.encode(buildingName, "UTF-8") +
        "&usage_type=" + URLEncoder.encode(usageType, "UTF-8") +
        "&startDate=" + URLEncoder.encode(startDate, "UTF-8") +
        "&startTime=" + URLEncoder.encode(startTime, "UTF-8") +
        "&endDate=" + URLEncoder.encode(endDate, "UTF-8") +
        "&endTime=" + URLEncoder.encode(endTime, "UTF-8") +
        "&open_only=" + URLEncoder.encode(openOnlyChecked ? "Y" : "", "UTF-8") +
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
    <title>알람 목록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-meter-status.page-alarm { height: auto; min-height: 100vh; overflow: auto; }
        .page-meter-status.page-alarm .dash {
            height: auto;
            min-height: 100vh;
            width: 100%;
            max-width: 1480px;
            margin: 0 auto;
            display: flex;
            flex-direction: column;
        }
        .page-meter-status.page-alarm .dash-main {
            overflow: auto;
            flex: 1 1 auto;
        }
        .page-meter-status.page-alarm .dash-top,
        .page-meter-status.page-alarm .search-form,
        .page-meter-status.page-alarm .search-form .form-row,
        .page-meter-status.page-alarm .search-form .card {
            width: 100%;
            max-width: 100%;
            min-width: 0;
        }
        .page-meter-status.page-alarm .search-form {
            padding: 14px;
            overflow: hidden;
        }
        .alarm-table { table-layout: fixed; margin-bottom: 0; width: 100%; }
        .alarm-table th, .alarm-table td { white-space: nowrap; text-align: center; vertical-align: middle; }
        .alarm-table th:nth-child(1), .alarm-table td:nth-child(1),
        .alarm-table .triggered-cell {
            width: 170px;
            white-space: normal;
            word-wrap: break-word;
            overflow-wrap: anywhere;
            word-break: break-word;
            line-height: 1.4;
        }
        .alarm-table th:nth-child(2), .alarm-table td:nth-child(2) { width: 7%; }
        .alarm-table th:nth-child(3), .alarm-table td:nth-child(3) { width: 7%; }
        .alarm-table th:nth-child(4), .alarm-table td:nth-child(4) {
            width: 17%;
            white-space: normal;
            overflow-wrap: anywhere;
            word-break: break-word;
            line-height: 1.4;
        }
        .alarm-table th:nth-child(5), .alarm-table td:nth-child(5) {
            width: 10%;
            white-space: normal;
            overflow-wrap: anywhere;
            word-break: break-word;
            line-height: 1.4;
        }
        .alarm-table th:nth-child(6), .alarm-table td:nth-child(6) {
            width: 12%;
            white-space: normal;
            overflow-wrap: anywhere;
            word-break: break-word;
            line-height: 1.4;
        }
        .alarm-table th:nth-child(7), .alarm-table td:nth-child(7) { width: 6%; }
        .alarm-table th:nth-child(8), .alarm-table td:nth-child(8) { width: 12%; }
        .alarm-table th:nth-child(9), .alarm-table td:nth-child(9),
        .alarm-table .desc-head,
        .alarm-table .desc-cell {
            width: 20%;
            text-align: left;
            line-height: 1.45;
        }
        .alarm-table .desc-text {
            display: block;
            width: 100%;
            white-space: normal !important;
            word-wrap: break-word !important;
            overflow-wrap: anywhere !important;
            word-break: break-word !important;
            line-height: 1.45;
        }
        .alarm-table tbody tr { cursor: pointer; }
        .alarm-table tbody tr:hover { background: #f3f8ff; }
        .sev-High { color: #b42318; font-weight: 700; }
        .sev-Medium { color: #b54708; font-weight: 700; }
        .sev-Low { color: #027a48; font-weight: 700; }
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
        .filter-card input, .filter-card select { min-width: 120px; }
        .filter-card label {
            white-space: nowrap;
            word-break: keep-all;
            flex: 0 0 auto;
        }
        .filter-card .check-inline {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            margin-left: 10px;
            font-weight: 600;
            white-space: nowrap;
        }
        .filter-card .check-inline input {
            margin: 0;
            min-width: 0;
        }
        .filter-card .submit-inline {
            margin-left: 4px;
            white-space: nowrap;
        }
        @media (max-width: 1600px) {
            .page-meter-status.page-alarm .dash { max-width: 1280px; }
        }
        @media (max-width: 1200px) {
            .page-meter-status.page-alarm .dash { max-width: 100%; }
            .filter-line { flex-wrap: wrap; }
            .filter-card input, .filter-card select { min-width: 0; }
        }
        .page-footer {
            text-align: center;
            color: #6b7a90;
            font-size: 12px;
            padding: 16px 0 24px;
            margin-top: auto;
        }
        .summary-bar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            margin-bottom: 8px;
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

                            <label for="panel_name">판넬명</label>
                            <select id="panel_name" name="panel_name">
                                <option value="">전체</option>
                                <% for (String p : panelOptions) { %>
                                    <option value="<%= h(p) %>" <%= p.equals(panelName) ? "selected" : "" %>><%= h(p) %></option>
                                <% } %>
                            </select>

                            <label for="rule_code">알람유형</label>
                            <select id="rule_code" name="rule_code">
                                <option value="">전체</option>
                                <% for (Map<String, String> opt : ruleOptions) {
                                       String optionCode = opt.get("rule_code") == null ? "" : opt.get("rule_code");
                                       String optionName = opt.get("rule_name") == null ? optionCode : opt.get("rule_name");
                                %>
                                    <option value="<%= h(optionCode) %>" <%= optionCode.equals(ruleCode) ? "selected" : "" %>><%= h(optionName) %></option>
                                <% } %>
                            </select>
                        </div>

                        <div class="filter-line">
                            <label for="startDate">기간</label>
                            <input id="startDate" type="date" name="startDate" value="<%= startDate %>">
                            <input id="startTime" type="time" step="1" name="startTime" value="<%= startTime %>">
                            <span class="spacer">~</span>
                            <input id="endDate" type="date" name="endDate" value="<%= endDate %>">
                            <input id="endTime" type="time" step="1" name="endTime" value="<%= endTime %>">
                            <label class="check-inline" for="open_only">
                                <input id="open_only" type="checkbox" name="open_only" value="Y" <%= openOnlyChecked ? "checked" : "" %>>
                                오픈 알람만
                            </label>

                            <button class="submit-inline" type="submit">조회</button>
                        </div>
                    </div>
                </div>
            </div>
        </form>
    </div>

    <div class="dash-main stack" style="min-height:0;">
        <section class="panel_s" style="width:100%; min-height:0;">
            <% if (error != null && !error.trim().isEmpty()) { %>
            <div class="msg-box"><%= h(error) %></div>
            <% } %>
            <div class="summary-bar">
                <div class="summary-meta" id="alarmSummary" style="margin-bottom:0;">
                    <span class="badge">조회 건수: <%= totalCount %></span>
                </div>
                <div class="summary-actions">
                    <label for="page_size">페이지당</label>
                    <select id="page_size" name="page_size" form="alarmFilterForm">
                        <option value="50" <%= pageSize == 50 ? "selected" : "" %>>50</option>
                        <option value="100" <%= pageSize == 100 ? "selected" : "" %>>100</option>
                        <option value="150" <%= pageSize == 150 ? "selected" : "" %>>150</option>
                        <option value="200" <%= pageSize == 200 ? "selected" : "" %>>200</option>
                    </select>
                    <span>개</span>
                </div>
            </div>
            <div class="table-wrap">
                <table class="alarm-table">
                    <colgroup>
                        <col style="width:12%;">
                        <col style="width:7%;">
                        <col style="width:7%;">
                        <col style="width:17%;">
                        <col style="width:10%;">
                        <col style="width:12%;">
                        <col style="width:6%;">
                        <col style="width:12%;">
                        <col style="width:17%;">
                    </colgroup>
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
                        <th class="desc-head">설명</th>
                    </tr>
                    </thead>
                    <tbody id="alarmTableBody">
                    <% for (Map<String, Object> a : alarms) {
                        long aid = (Long) a.get("alarm_id");
                        Object clearedObj = a.get("cleared_at");
                        String clearedText = (clearedObj == null) ? "-" : String.valueOf(clearedObj);
                        if ("null".equalsIgnoreCase(clearedText.trim()) || clearedText.trim().isEmpty()) clearedText = "-";
                    %>
                        <tr onclick="location.href='alarm_detail.jsp?alarm_id=<%= aid %>&<%= filterQuery %>'">
                            <td class="triggered-cell"><%= h(formatTs(a.get("triggered_at"))) %></td>
                            <td><%= h(a.get("building_name")) %></td>
                            <td><%= h(a.get("usage_type")) %></td>
                            <td><%= h(buildMeterDisplay(a)) %></td>
                            <td><%= h(buildPanelDisplay(a)) %></td>
                            <td><%= h(buildAlarmTypeDisplay(a)) %></td>
                            <td class="sev-<%= h(a.get("severity")) %>"><%= h(a.get("severity")) %></td>
                            <td class="triggered-cell"><%= h("-".equals(clearedText) ? clearedText : formatTs(clearedText)) %></td>
                            <td class="desc-cell"><div class="desc-text"><%= formatAlarmDescHtml(a.get("description")) %></div></td>
                        </tr>
                    <% } %>
                    <% if (alarms.isEmpty()) { %>
                        <tr><td colspan="9">조회 결과가 없습니다.</td></tr>
                    <% } %>
                    </tbody>
                </table>
            </div>
            <div class="pager" id="alarmPager">
                <div class="pager-info">페이지 <%= currentPage %> / <%= totalPages %></div>
                <div class="pager-links">
                    <% if (currentPage > 1) { %>
                        <a href="alarm_view.jsp?<%= filterQuery %>&page=<%= currentPage - 1 %>">이전</a>
                    <% } %>
                    <% for (int p = pageStart; p <= pageEnd; p++) { %>
                        <% if (p == currentPage) { %>
                            <span class="active"><%= p %></span>
                        <% } else { %>
                            <a href="alarm_view.jsp?<%= filterQuery %>&page=<%= p %>"><%= p %></a>
                        <% } %>
                    <% } %>
                    <% if (currentPage < totalPages) { %>
                        <a href="alarm_view.jsp?<%= filterQuery %>&page=<%= currentPage + 1 %>">다음</a>
                    <% } %>
                </div>
            </div>
        </section>
    </div>
    <div class="page-footer">© EPMS Dashboard | SNUT CNT</div>
</div>
<script>
(function(){
    const form = document.getElementById("alarmFilterForm");
    const building = document.getElementById("building_name");
    const usage = document.getElementById("usage_type");
    const panelNameInput = document.getElementById("panel_name");
    const ruleCodeInput = document.getElementById("rule_code");
    const openOnly = document.getElementById("open_only");
    const pageSizeInput = document.getElementById("page_size");
    const summary = document.getElementById("alarmSummary");
    const tableBody = document.getElementById("alarmTableBody");
    const pager = document.getElementById("alarmPager");
    if (!form || !building || !usage || !panelNameInput || !ruleCodeInput) return;

    function refreshFilterOptions() {
        form.submit();
    }

    let autoRefreshTimer = null;
    let refreshBusy = false;

    async function refreshAlarmList() {
        if (refreshBusy || !summary || !tableBody) return;
        refreshBusy = true;
        try {
            const formData = new FormData(form);
            const params = new URLSearchParams();
            formData.forEach(function(value, key){
                if (typeof value === "string") params.append(key, value);
            });
            const url = form.getAttribute("action") ? form.getAttribute("action") : window.location.pathname;
            const res = await fetch(url + "?" + params.toString() + "&_ts=" + Date.now(), {
                cache: "no-store",
                headers: { "X-Requested-With": "fetch" }
            });
            const html = await res.text();
            const doc = new DOMParser().parseFromString(html, "text/html");
            const nextSummary = doc.getElementById("alarmSummary");
            const nextBody = doc.getElementById("alarmTableBody");
            const nextPager = doc.getElementById("alarmPager");
            if (nextSummary) summary.innerHTML = nextSummary.innerHTML;
            if (nextBody) tableBody.innerHTML = nextBody.innerHTML;
            if (pager && nextPager) pager.innerHTML = nextPager.innerHTML;
        } catch (ignore) {
        } finally {
            refreshBusy = false;
        }
    }

    function stopAutoRefresh() {
        if (autoRefreshTimer) {
            clearInterval(autoRefreshTimer);
            autoRefreshTimer = null;
        }
    }

    function startAutoRefresh() {
        stopAutoRefresh();
        const intervalMs = (openOnly && openOnly.checked) ? 1000 : 3000;
        autoRefreshTimer = setInterval(function(){
            if (document.visibilityState === "hidden") return;
            refreshAlarmList();
        }, intervalMs);
    }

    building.addEventListener("change", refreshFilterOptions);
    usage.addEventListener("change", refreshFilterOptions);
    panelNameInput.addEventListener("change", refreshFilterOptions);
    ruleCodeInput.addEventListener("change", refreshFilterOptions);
    if (pageSizeInput) {
        pageSizeInput.addEventListener("change", function(){
            const pageField = form.querySelector('input[name="page"]');
            if (pageField) pageField.value = "1";
            refreshFilterOptions();
        });
    }
    form.addEventListener("submit", function(e){
        if (!summary || !tableBody) return;
        e.preventDefault();
        refreshAlarmList();
    });
    if (openOnly) {
        openOnly.addEventListener("change", function(){
            if (openOnly.checked) {
                refreshAlarmList();
                startAutoRefresh();
            } else {
                stopAutoRefresh();
                refreshAlarmList();
            }
        });
    }
    document.addEventListener("visibilitychange", function(){
        if (document.visibilityState === "visible") {
            startAutoRefresh();
            refreshAlarmList();
        }
    });
    startAutoRefresh();
})();
</script>
<%
    }
%>
</body>
</html>

