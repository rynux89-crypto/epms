<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String fmt(Object value, int scale) {
        if (value == null) return "";
        try {
            double v = value instanceof Number ? ((Number)value).doubleValue() : Double.parseDouble(String.valueOf(value));
            return String.format(java.util.Locale.US, "%,." + scale + "f", v);
        } catch (Exception ignore) {
            return String.valueOf(value);
        }
    }

    private String dt(Object value) {
        return value == null ? "" : String.valueOf(value).replace('-', '/');
    }

    private int parseLimit(String raw) {
        try {
            int n = Integer.parseInt(raw == null ? "" : raw.trim());
            if (n == 100 || n == 200 || n == 500 || n == 1000) return n;
        } catch (Exception ignore) {
        }
        return 200;
    }

    private Timestamp parseDateTime(String raw) {
        if (raw == null || raw.trim().isEmpty()) return null;
        String s = raw.trim().replace('T', ' ');
        if (s.length() == 16) s += ":00";
        try {
            return Timestamp.valueOf(s);
        } catch (Exception ignore) {
            return null;
        }
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
String selectedId = request.getParameter("ups_id");
String fromRaw = request.getParameter("from");
String toRaw = request.getParameter("to");
String export = request.getParameter("export");
int limit = parseLimit(request.getParameter("limit"));
Timestamp fromTs = parseDateTime(fromRaw);
Timestamp toTs = parseDateTime(toRaw);

List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();

try (Connection conn = openUpsDbConnection()) {
    try (PreparedStatement ps = conn.prepareStatement(
        "SELECT ups_id, ups_name, ip_address, modbus_port FROM dbo.ups_device ORDER BY ups_name")) {
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> d = new HashMap<String, Object>();
                d.put("ups_id", rs.getInt("ups_id"));
                d.put("ups_name", rs.getString("ups_name"));
                d.put("ip_address", rs.getString("ip_address"));
                d.put("modbus_port", rs.getInt("modbus_port"));
                devices.add(d);
            }
        }
    }

    StringBuilder sql = new StringBuilder();
    sql.append("SELECT TOP ").append(limit).append(" d.ups_name, d.ip_address, d.modbus_port, ")
       .append("m.measured_at, m.output_voltage_l12, m.output_voltage_l23, m.output_voltage_l31, ")
       .append("m.output_current_l1, m.output_current_l2, m.output_current_l3, ")
       .append("m.frequency, m.load_percent, m.output_power_kw, m.output_apparent_total_kva, ")
       .append("m.output_pf_l1, m.output_pf_l2, m.output_pf_l3, ")
       .append("m.battery_voltage, m.battery_current, m.battery_charge_percent, m.battery_temperature, m.remaining_minutes, ")
       .append("m.ups_operation_mode_code, m.system_operation_mode_code, m.raw_status ")
       .append("FROM dbo.ups_measurement m INNER JOIN dbo.ups_device d ON d.ups_id = m.ups_id WHERE 1=1 ");
    List<Object> params = new ArrayList<Object>();
    if (selectedId != null && !selectedId.trim().isEmpty()) {
        sql.append("AND m.ups_id = ? ");
        params.add(Integer.valueOf(selectedId.trim()));
    }
    if (fromTs != null) {
        sql.append("AND m.measured_at >= ? ");
        params.add(fromTs);
    }
    if (toTs != null) {
        sql.append("AND m.measured_at <= ? ");
        params.add(toTs);
    }
    sql.append("ORDER BY m.measured_at DESC");

    try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
        for (int i = 0; i < params.size(); i++) {
            Object p = params.get(i);
            if (p instanceof Timestamp) ps.setTimestamp(i + 1, (Timestamp)p);
            else if (p instanceof Integer) ps.setInt(i + 1, ((Integer)p).intValue());
            else ps.setObject(i + 1, p);
        }
        try (ResultSet rs = ps.executeQuery()) {
            ResultSetMetaData md = rs.getMetaData();
            while (rs.next()) {
                Map<String, Object> row = new HashMap<String, Object>();
                for (int i = 1; i <= md.getColumnCount(); i++) row.put(md.getColumnLabel(i), rs.getObject(i));
                rows.add(row);
            }
        }
    }
} catch (Exception e) {
    err = e.getMessage();
}

if ("csv".equalsIgnoreCase(export)) {
    response.reset();
    response.setCharacterEncoding("UTF-8");
    response.setContentType("text/csv;charset=UTF-8");
    response.setHeader("Content-Disposition", "attachment; filename=\"ups_measurement_history.csv\"");
    out.print("\uFEFF");
    out.println("UPS,IP,Port,Measured At,V L1-2,V L2-3,V L3-1,I L1,I L2,I L3,Frequency,Load %,kW,kVA,PF L1,PF L2,PF L3,Battery V,Battery A,Battery %,Battery Temp,Remain Min,UPS Mode,System Mode,Raw Status");
    for (Map<String, Object> r : rows) {
        out.println(
            csv(r.get("ups_name")) + "," +
            csv(r.get("ip_address")) + "," +
            csv(r.get("modbus_port")) + "," +
            csv(r.get("measured_at")) + "," +
            csv(r.get("output_voltage_l12")) + "," +
            csv(r.get("output_voltage_l23")) + "," +
            csv(r.get("output_voltage_l31")) + "," +
            csv(r.get("output_current_l1")) + "," +
            csv(r.get("output_current_l2")) + "," +
            csv(r.get("output_current_l3")) + "," +
            csv(r.get("frequency")) + "," +
            csv(r.get("load_percent")) + "," +
            csv(r.get("output_power_kw")) + "," +
            csv(r.get("output_apparent_total_kva")) + "," +
            csv(r.get("output_pf_l1")) + "," +
            csv(r.get("output_pf_l2")) + "," +
            csv(r.get("output_pf_l3")) + "," +
            csv(r.get("battery_voltage")) + "," +
            csv(r.get("battery_current")) + "," +
            csv(r.get("battery_charge_percent")) + "," +
            csv(r.get("battery_temperature")) + "," +
            csv(r.get("remaining_minutes")) + "," +
            csv(r.get("ups_operation_mode_code")) + "," +
            csv(r.get("system_operation_mode_code")) + "," +
            csv(r.get("raw_status"))
        );
    }
    return;
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 측정 이력</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body { background:#f2f4f7; }
        .history-shell { max-width:1320px; margin:0 auto; }
        .history-filter { display:flex; flex-wrap:wrap; gap:10px; align-items:end; background:#fff; border:1px solid #d7e1ec; border-radius:8px; padding:12px; margin-bottom:12px; }
        .history-filter label { display:grid; gap:4px; font-size:12px; color:#475569; }
        .history-filter input, .history-filter select { min-height:34px; border:1px solid #b9c7d7; border-radius:6px; padding:6px 8px; background:#fff; color:#111827; }
        .history-filter button { min-height:34px; }
        .history-table-wrap { overflow:auto; max-height:calc(100vh - 230px); background:#fff; border:1px solid #d7e1ec; border-radius:8px; }
        .history-table { width:max-content; min-width:1900px; border-collapse:collapse; font-size:12px; white-space:nowrap; table-layout:fixed; }
        .history-table th, .history-table td { border-bottom:1px solid #e6edf5; border-right:1px solid #edf2f7; padding:7px 12px; text-align:right; }
        .history-table th:last-child, .history-table td:last-child { border-right:none; }
        .history-table th { position:sticky; top:0; background:#eef4fb; color:#1f3347; z-index:1; }
        .history-table th:first-child, .history-table td:first-child,
        .history-table th:nth-child(2), .history-table td:nth-child(2) { text-align:left; }
        .history-table th, .history-table td { overflow:hidden; text-overflow:ellipsis; }
        .col-ups { width:170px; }
        .col-time { width:210px; }
        .col-num { width:86px; }
        .col-mode { width:100px; }
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
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form class="history-filter" method="get">
        <label>UPS
            <select name="ups_id">
                <option value="">전체</option>
                <% for (Map<String, Object> d : devices) { String id = String.valueOf(d.get("ups_id")); %>
                <option value="<%= h(id) %>" <%= id.equals(selectedId) ? "selected" : "" %>><%= h(d.get("ups_name")) %> - <%= h(d.get("ip_address")) %>:<%= h(d.get("modbus_port")) %></option>
                <% } %>
            </select>
        </label>
        <label>시작
            <input type="datetime-local" name="from" value="<%= h(fromRaw) %>">
        </label>
        <label>종료
            <input type="datetime-local" name="to" value="<%= h(toRaw) %>">
        </label>
        <label>건수
            <select name="limit">
                <% int[] limits = new int[]{100, 200, 500, 1000}; for (int n : limits) { %>
                <option value="<%= n %>" <%= n == limit ? "selected" : "" %>><%= n %></option>
                <% } %>
            </select>
        </label>
        <button type="submit">조회</button>
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
                <col class="col-num"><col class="col-num"><col class="col-num">
                <col class="col-num"><col class="col-num"><col class="col-num">
                <col class="col-num"><col class="col-num"><col class="col-num"><col class="col-num">
                <col class="col-num"><col class="col-num"><col class="col-num">
                <col class="col-num"><col class="col-num"><col class="col-num"><col class="col-num"><col class="col-num">
                <col class="col-mode"><col class="col-mode"><col class="col-mode">
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
                    <td><%= h(dt(r.get("measured_at"))) %></td>
                    <td><%= fmt(r.get("output_voltage_l12"), 0) %></td>
                    <td><%= fmt(r.get("output_voltage_l23"), 0) %></td>
                    <td><%= fmt(r.get("output_voltage_l31"), 0) %></td>
                    <td><%= fmt(r.get("output_current_l1"), 0) %></td>
                    <td><%= fmt(r.get("output_current_l2"), 0) %></td>
                    <td><%= fmt(r.get("output_current_l3"), 0) %></td>
                    <td><%= fmt(r.get("frequency"), 1) %></td>
                    <td><%= fmt(r.get("load_percent"), 1) %></td>
                    <td><%= fmt(r.get("output_power_kw"), 0) %></td>
                    <td><%= fmt(r.get("output_apparent_total_kva"), 0) %></td>
                    <td><%= fmt(r.get("output_pf_l1"), 2) %></td>
                    <td><%= fmt(r.get("output_pf_l2"), 2) %></td>
                    <td><%= fmt(r.get("output_pf_l3"), 2) %></td>
                    <td><%= fmt(r.get("battery_charge_percent"), 0) %></td>
                    <td><%= fmt(r.get("battery_voltage"), 0) %></td>
                    <td><%= fmt(r.get("battery_current"), 0) %></td>
                    <td><%= fmt(r.get("battery_temperature"), 1) %></td>
                    <td><%= fmt(r.get("remaining_minutes"), 0) %></td>
                    <td><%= h(r.get("ups_operation_mode_code")) %></td>
                    <td><%= h(r.get("system_operation_mode_code")) %></td>
                    <td><%= h(r.get("raw_status")) %></td>
                </tr>
            <% } %>
            </tbody>
        </table>
        <% } %>
    </div>
</div>
</body>
</html>
