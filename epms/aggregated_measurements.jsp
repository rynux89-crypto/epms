<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String nvl(String value) {
        return value == null ? "" : value.trim();
    }

    private static Integer parseIntSafe(String value) {
        try {
            if (value == null || value.trim().isEmpty()) return null;
            return Integer.valueOf(Integer.parseInt(value.trim()));
        } catch (Exception ignore) {
            return null;
        }
    }

    private static String periodViewName(String period) {
        if ("hourly".equalsIgnoreCase(period)) return "dbo.vw_hourly_measurements";
        if ("monthly".equalsIgnoreCase(period)) return "dbo.vw_monthly_measurements";
        if ("yearly".equalsIgnoreCase(period)) return "dbo.vw_yearly_measurements";
        return "dbo.vw_daily_measurements";
    }

    private static String periodDateColumn(String period) {
        if ("hourly".equalsIgnoreCase(period)) return "measured_hour";
        if ("monthly".equalsIgnoreCase(period)) return "measured_month";
        if ("yearly".equalsIgnoreCase(period)) return "measured_year";
        return "measured_date";
    }

    private static String periodDateLabel(String period) {
        if ("hourly".equalsIgnoreCase(period)) return "집계 시간대(시작)";
        if ("daily".equalsIgnoreCase(period)) return "집계 일자";
        if ("monthly".equalsIgnoreCase(period)) return "집계 월";
        if ("yearly".equalsIgnoreCase(period)) return "집계 연도";
        return "집계 기준";
    }

    private static String enc(String value) {
        try {
            return URLEncoder.encode(nvl(value), "UTF-8");
        } catch (Exception ignore) {
            return nvl(value);
        }
    }

    private static String buildPeriodHref(String period, String panelName, Integer meterId, String fromValue, String toValue) {
        StringBuilder href = new StringBuilder("aggregated_measurements.jsp?period=").append(enc(period));
        if (!nvl(panelName).isEmpty()) {
            href.append("&panel_name=").append(enc(panelName));
        }
        if (meterId != null) {
            href.append("&meter_id=").append(meterId.intValue());
        }
        if (!nvl(fromValue).isEmpty()) {
            href.append("&from_value=").append(enc(fromValue));
        }
        if (!nvl(toValue).isEmpty()) {
            href.append("&to_value=").append(enc(toValue));
        }
        return href.toString();
    }

    private static String fmt2(Object value) {
        if (value == null) return "";
        if (value instanceof Number) {
            return String.format(java.util.Locale.US, "%.2f", ((Number)value).doubleValue());
        }
        try {
            return String.format(java.util.Locale.US, "%.2f", Double.parseDouble(String.valueOf(value)));
        } catch (Exception ignore) {
            return String.valueOf(value);
        }
    }
%>
<%
    try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String period = nvl(request.getParameter("period"));
    if (!"hourly".equalsIgnoreCase(period) && !"monthly".equalsIgnoreCase(period) && !"yearly".equalsIgnoreCase(period)) period = "daily";
    String panelName = nvl(request.getParameter("panel_name"));
    Integer meterId = parseIntSafe(request.getParameter("meter_id"));
    String fromValue = nvl(request.getParameter("from_value"));
    String toValue = nvl(request.getParameter("to_value"));
    boolean hasExplicitFilter =
            request.getParameter("panel_name") != null ||
            request.getParameter("meter_id") != null ||
            request.getParameter("from_value") != null ||
            request.getParameter("to_value") != null;

    if (!hasExplicitFilter && meterId == null) {
        meterId = Integer.valueOf(1);
    }

    if (fromValue.isEmpty()) {
        if ("hourly".equals(period)) fromValue = java.time.LocalDate.now().minusDays(2).toString();
        else if ("daily".equals(period)) fromValue = java.time.LocalDate.now().minusDays(30).toString();
        else if ("monthly".equals(period)) fromValue = java.time.LocalDate.now().minusMonths(12).withDayOfMonth(1).toString();
        else fromValue = String.valueOf(java.time.LocalDate.now().getYear() - 5);
    }
    if (toValue.isEmpty()) {
        if ("hourly".equals(period)) toValue = java.time.LocalDate.now().toString();
        else if ("daily".equals(period)) toValue = java.time.LocalDate.now().toString();
        else if ("monthly".equals(period)) toValue = java.time.LocalDate.now().withDayOfMonth(1).toString();
        else toValue = String.valueOf(java.time.LocalDate.now().getYear());
    }

    List<String> panelOptions = new ArrayList<>();
    List<Map<String, Object>> meterOptions = new ArrayList<>();
    List<Map<String, Object>> rows = new ArrayList<>();
    String error = null;
    int rowCount = 0;

    try {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT panel_name FROM dbo.meters " +
                "WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> '' ORDER BY panel_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) panelOptions.add(rs.getString(1));
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, name, panel_name FROM dbo.meters ORDER BY meter_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> m = new HashMap<>();
                m.put("meter_id", rs.getInt("meter_id"));
                m.put("name", rs.getString("name"));
                m.put("panel_name", rs.getString("panel_name"));
                meterOptions.add(m);
            }
        }

        String viewName = periodViewName(period);
        String dateColumn = periodDateColumn(period);
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT * FROM ").append(viewName).append(" WHERE 1=1 ");
        List<Object> params = new ArrayList<>();

        if (!panelName.isEmpty()) {
            sql.append("AND panel_name = ? ");
            params.add(panelName);
        }
        if (meterId != null) {
            sql.append("AND meter_id = ? ");
            params.add(meterId);
        }
        if ("yearly".equals(period)) {
            Integer fromYear = parseIntSafe(fromValue);
            Integer toYear = parseIntSafe(toValue);
            if (fromYear != null) {
                sql.append("AND ").append(dateColumn).append(" >= ? ");
                params.add(fromYear);
            }
            if (toYear != null) {
                sql.append("AND ").append(dateColumn).append(" <= ? ");
                params.add(toYear);
            }
        } else if ("hourly".equals(period)) {
            if (!fromValue.isEmpty()) {
                sql.append("AND ").append(dateColumn).append(" >= ? ");
                params.add(java.sql.Timestamp.valueOf(java.time.LocalDate.parse(fromValue).atStartOfDay()));
            }
            if (!toValue.isEmpty()) {
                sql.append("AND ").append(dateColumn).append(" < ? ");
                params.add(java.sql.Timestamp.valueOf(java.time.LocalDate.parse(toValue).plusDays(1).atStartOfDay()));
            }
        } else {
            if (!fromValue.isEmpty()) {
                sql.append("AND ").append(dateColumn).append(" >= ? ");
                params.add(java.sql.Date.valueOf(fromValue));
            }
            if (!toValue.isEmpty()) {
                sql.append("AND ").append(dateColumn).append(" <= ? ");
                params.add(java.sql.Date.valueOf(toValue));
            }
        }
        sql.append("ORDER BY ").append(dateColumn).append(" DESC, meter_id ASC");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setObject(i + 1, params.get(i));
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("meter_id", rs.getObject("meter_id"));
                    r.put("meter_name", rs.getObject("meter_name"));
                    r.put("panel_name", rs.getObject("panel_name"));
                    r.put("building_name", rs.getObject("building_name"));
                    r.put("usage_type", rs.getObject("usage_type"));
                    r.put(dateColumn, rs.getObject(dateColumn));
                    r.put("avg_current", rs.getObject("avg_current"));
                    r.put("max_line_voltage", rs.getObject("max_line_voltage"));
                    r.put("min_line_voltage", rs.getObject("min_line_voltage"));
                    r.put("max_phase_voltage", rs.getObject("max_phase_voltage"));
                    r.put("min_phase_voltage", rs.getObject("min_phase_voltage"));
                    if ("daily".equals(period) || "hourly".equals(period)) {
                        r.put("max_current", rs.getObject("max_current"));
                        r.put("min_current", rs.getObject("min_current"));
                    }
                    r.put("energy_consumed_kwh", rs.getObject("energy_consumed_kwh"));
                    r.put("reactive_energy_kvarh", rs.getObject("reactive_energy_kvarh"));
                    r.put("line_voltage_avg", rs.getObject("line_voltage_avg"));
                    r.put("phase_voltage_avg", rs.getObject("phase_voltage_avg"));
                    r.put("power_factor", rs.getObject("power_factor"));
                    r.put("max_power", rs.getObject("max_power"));
                    rows.add(r);
                }
            }
        }
        rowCount = rows.size();
    } catch (Exception e) {
        error = e.getMessage();
    }
%>
<html>
<head>
    <title>Aggregated Measurements</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1500px; margin: 0 auto; }
        .info-box, .err-box {
            margin: 10px 0;
            padding: 10px 12px;
            border-radius: 8px;
            font-size: 13px;
        }
        .info-box { background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; }
        .err-box { background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-weight: 700; }
        .toolbar { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
        .tabbar { display:flex; gap:8px; flex-wrap:wrap; margin: 8px 0 12px; }
        .tabbar a {
            text-decoration:none;
            padding:8px 12px;
            border-radius:999px;
            border:1px solid #cbd5e1;
            color:#334155;
            background:#f8fafc;
            font-weight:700;
            font-size:13px;
        }
        .tabbar a.active { background:#2563eb; border-color:#2563eb; color:#fff; }
        .summary-box {
            margin: 10px 0 14px;
            padding: 10px 12px;
            border: 1px solid #dbe3ec;
            border-radius: 10px;
            background: #f8fbfe;
            color: #334155;
            font-size: 13px;
        }
        .table-scroll {
            overflow-x: auto;
            margin-bottom: 24px;
            border: 1px solid #dbe3ec;
            border-radius: 12px;
            background: #fff;
            box-shadow: var(--shadow-soft);
        }
        .aggregate-table {
            min-width: 2100px;
            margin-bottom: 0;
            border: none;
            border-radius: 0;
            box-shadow: none;
            table-layout: auto;
        }
        .aggregate-table th,
        .aggregate-table td {
            white-space: nowrap;
            word-break: keep-all;
            vertical-align: middle;
        }
        .aggregate-table th {
            position: sticky;
            top: 0;
            z-index: 1;
        }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td, th { font-size: 12px; white-space: nowrap; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>집계 측정값 조회</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        기준 뷰: <span class="mono"><%= h(periodViewName(period)) %></span><br/>
        집계 저장 프로시저가 채운 시간/일간/월간/년간 테이블을 meter 정보와 함께 조회합니다.
    </div>

    <% if (error != null) { %>
    <div class="err-box">오류: <%= h(error) %></div>
    <% } %>

    <div class="tabbar">
        <a class="<%= "hourly".equals(period) ? "active" : "" %>" href="<%= h(buildPeriodHref("hourly", panelName, meterId, fromValue, toValue)) %>">시간</a>
        <a class="<%= "daily".equals(period) ? "active" : "" %>" href="<%= h(buildPeriodHref("daily", panelName, meterId, fromValue, toValue)) %>">일간</a>
        <a class="<%= "monthly".equals(period) ? "active" : "" %>" href="<%= h(buildPeriodHref("monthly", panelName, meterId, fromValue, toValue)) %>">월간</a>
        <a class="<%= "yearly".equals(period) ? "active" : "" %>" href="<%= h(buildPeriodHref("yearly", panelName, meterId, fromValue, toValue)) %>">년간</a>
    </div>

    <form method="get" class="toolbar">
        <input type="hidden" name="period" value="<%= h(period) %>" />
        <label for="panel_name">Panel:</label>
        <select id="panel_name" name="panel_name">
            <option value="">전체</option>
            <% for (String p : panelOptions) { %>
            <option value="<%= h(p) %>" <%= panelName.equals(p) ? "selected" : "" %>><%= h(p) %></option>
            <% } %>
        </select>

        <label for="meter_id">Meter:</label>
        <select id="meter_id" name="meter_id">
            <option value="">전체</option>
            <% for (Map<String, Object> m : meterOptions) { %>
            <% String mv = String.valueOf(m.get("meter_id")); %>
            <option value="<%= h(mv) %>" <%= (meterId != null && meterId.toString().equals(mv)) ? "selected" : "" %>>
                #<%= h(mv) %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
            </option>
            <% } %>
        </select>

        <label for="from_value"><%= "yearly".equals(period) ? "From Year" : "From" %>:</label>
        <input id="from_value" name="from_value" class="mono" value="<%= h(fromValue) %>" <%= "yearly".equals(period) ? "" : "type=\"date\"" %> />
        <label for="to_value"><%= "yearly".equals(period) ? "To Year" : "To" %>:</label>
        <input id="to_value" name="to_value" class="mono" value="<%= h(toValue) %>" <%= "yearly".equals(period) ? "" : "type=\"date\"" %> />
        <button type="submit">조회</button>
    </form>

    <div class="summary-box">
        조회 건수: <b><%= rowCount %></b>
    </div>

    <div class="table-scroll">
    <table class="aggregate-table">
        <thead>
        <tr>
            <th>meter_id</th>
            <th>meter_name</th>
            <th>panel_name</th>
            <th><%= h(periodDateLabel(period)) %></th>
            <th>line_voltage_avg</th>
            <th>max_line_voltage</th>
            <th>min_line_voltage</th>
            <th>phase_voltage_avg</th>
            <th>max_phase_voltage</th>
            <th>min_phase_voltage</th>
            <th>avg_current</th>
            <% if ("daily".equals(period) || "hourly".equals(period)) { %>
            <th>max_current</th>
            <th>min_current</th>
            <% } %>
            <th>power_factor</th>
            <th>energy_consumed_kwh</th>
            <th>reactive_energy_kvarh</th>
            <th>max_power</th>
        </tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
        <tr>
            <td colspan="<%= ("daily".equals(period) || "hourly".equals(period)) ? "17" : "15" %>">데이터가 없습니다.</td>
        </tr>
        <% } else { %>
            <% for (Map<String, Object> r : rows) { %>
            <tr>
                <td class="mono"><%= h(r.get("meter_id")) %></td>
                <td><%= h(r.get("meter_name")) %></td>
                <td><%= h(r.get("panel_name")) %></td>
                <td class="mono"><%= h(r.get(periodDateColumn(period))) %></td>
                <td class="mono"><%= h(fmt2(r.get("line_voltage_avg"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("max_line_voltage"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("min_line_voltage"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("phase_voltage_avg"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("max_phase_voltage"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("min_phase_voltage"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("avg_current"))) %></td>
                <% if ("daily".equals(period) || "hourly".equals(period)) { %>
                <td class="mono"><%= h(fmt2(r.get("max_current"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("min_current"))) %></td>
                <% } %>
                <td class="mono"><%= h(fmt2(r.get("power_factor"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("energy_consumed_kwh"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("reactive_energy_kvarh"))) %></td>
                <td class="mono"><%= h(fmt2(r.get("max_power"))) %></td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
    </div>
</div>
<footer>짤 EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
<%
    }
%>
