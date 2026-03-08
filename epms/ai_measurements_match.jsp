<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%!
    private static String h(Object value) {
        if (value == null) return "";
        String s = String.valueOf(value);
        StringBuilder out = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '&': out.append("&amp;"); break;
                case '<': out.append("&lt;"); break;
                case '>': out.append("&gt;"); break;
                case '"': out.append("&quot;"); break;
                case '\'': out.append("&#39;"); break;
                default: out.append(c);
            }
        }
        return out.toString();
    }
%>
<%
    String plcParam = request.getParameter("plc_id");
    String meterParam = request.getParameter("meter_id");
    Integer plcId = null;
    Integer meterId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}
    try { if (meterParam != null && !meterParam.trim().isEmpty()) meterId = Integer.parseInt(meterParam.trim()); } catch (Exception ignore) {}

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<Map<String, Object>> meterList = new ArrayList<>();
    List<Map<String, Object>> mappingRows = new ArrayList<>();
    List<Map<String, Object>> latestTokenRows = new ArrayList<>();
    Map<String, Object> latestMeasurement = new HashMap<>();
    String error = null;

    try {
        try (PreparedStatement ps = conn.prepareStatement("SELECT plc_id, plc_ip, plc_port, unit_id, enabled FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("plc_id", rs.getInt("plc_id"));
                r.put("plc_ip", rs.getString("plc_ip"));
                r.put("plc_port", rs.getInt("plc_port"));
                r.put("unit_id", rs.getInt("unit_id"));
                r.put("enabled", rs.getBoolean("enabled"));
                plcList.add(r);
            }
        }

        String meterSql = "SELECT meter_id, name, panel_name FROM dbo.meters ORDER BY meter_id";
        try (PreparedStatement ps = conn.prepareStatement(meterSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("meter_id", rs.getInt("meter_id"));
                r.put("name", rs.getString("name"));
                r.put("panel_name", rs.getString("panel_name"));
                meterList.add(r);
            }
        }

        String mapSql =
            "SELECT token, float_index, float_registers, measurement_column, target_table, is_supported, note " +
            "FROM dbo.plc_ai_measurements_match ORDER BY float_index";
        try (PreparedStatement ps = conn.prepareStatement(mapSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("token", rs.getString("token"));
                r.put("float_index", rs.getInt("float_index"));
                r.put("float_registers", rs.getInt("float_registers"));
                r.put("measurement_column", rs.getString("measurement_column"));
                r.put("target_table", rs.getString("target_table"));
                r.put("is_supported", rs.getBoolean("is_supported"));
                r.put("note", rs.getString("note"));
                mappingRows.add(r);
            }
        }

        if (plcId != null && meterId != null) {
            String tokenSql =
                "WITH b AS ( " +
                "    SELECT plc_id, meter_id, start_address " +
                "    FROM dbo.plc_meter_map " +
                "    WHERE plc_id = ? AND meter_id = ? AND enabled = 1 " +
                "), a AS ( " +
                "    SELECT b.plc_id, b.meter_id, m.token, m.float_index, m.measurement_column, " +
                "           b.start_address + ((m.float_index - 1) * 2) AS reg_address " +
                "    FROM b CROSS JOIN dbo.plc_ai_measurements_match m " +
                "    WHERE m.is_supported = 1 AND m.measurement_column IS NOT NULL " +
                "), s AS ( " +
                "    SELECT a.token, a.float_index, a.measurement_column, a.reg_address, " +
                "           x.value_float, x.measured_at, " +
                "           ROW_NUMBER() OVER (PARTITION BY a.token ORDER BY x.measured_at DESC) AS rn " +
                "    FROM a " +
                "    LEFT JOIN dbo.plc_ai_samples x " +
                "      ON x.plc_id = a.plc_id AND x.meter_id = a.meter_id AND x.reg_address = a.reg_address " +
                ") " +
                "SELECT token, float_index, measurement_column, reg_address, value_float, measured_at " +
                "FROM s WHERE rn = 1 ORDER BY float_index";

            try (PreparedStatement ps = conn.prepareStatement(tokenSql)) {
                ps.setInt(1, plcId);
                ps.setInt(2, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Map<String, Object> r = new HashMap<>();
                        r.put("token", rs.getString("token"));
                        r.put("float_index", rs.getInt("float_index"));
                        r.put("measurement_column", rs.getString("measurement_column"));
                        r.put("reg_address", rs.getInt("reg_address"));
                        r.put("value_float", rs.getObject("value_float"));
                        r.put("measured_at", rs.getTimestamp("measured_at"));
                        latestTokenRows.add(r);
                    }
                }
            }

            String latestSql =
                "SELECT TOP 1 * FROM dbo.measurements WHERE meter_id = ? ORDER BY measured_at DESC";
            try (PreparedStatement ps = conn.prepareStatement(latestSql)) {
                ps.setInt(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        ResultSetMetaData md = rs.getMetaData();
                        for (int i = 1; i <= md.getColumnCount(); i++) {
                            latestMeasurement.put(md.getColumnName(i), rs.getObject(i));
                        }
                    }
                }
            }
        }
    } catch (Exception e) {
        error = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%>
<html>
<head>
    <title>AI Tag - Measurements Matching</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1500px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .section-title { margin: 14px 0 6px; font-size: 15px; font-weight: 700; color: #1f3347; }
        .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-ok { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-no { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>AI 태그 - measurements 매칭</h2>
        <div style="display:flex; gap:8px;">
            <button class="back-btn" onclick="location.href='/epms/ai_mapping.jsp'">AI 매핑</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        기준: <span class="mono">docs/IO_Address_Tag_List_20260209-전압고조파추가.xlsx</span>의 AI 태그(62개, float 2레지스터)<br/>
        결과: <span class="mono">dbo.plc_ai_measurements_match</span> 매핑 테이블 기준(기존 measurements 구조는 변경하지 않음)
    </div>

    <% if (error != null) { %>
    <div class="err-box">DB 오류: <%= h(error) %></div>
    <% } %>

    <form method="GET" class="toolbar">
        <label for="plc_id">PLC:</label>
        <select id="plc_id" name="plc_id">
            <option value="">선택</option>
            <% for (Map<String, Object> p : plcList) { %>
            <% String v = String.valueOf(p.get("plc_id")); %>
            <option value="<%= v %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                PLC <%= p.get("plc_id") %> - <%= h(p.get("plc_ip")) %>:<%= p.get("plc_port") %>
            </option>
            <% } %>
        </select>

        <label for="meter_id">Meter:</label>
        <select id="meter_id" name="meter_id">
            <option value="">선택</option>
            <% for (Map<String, Object> m : meterList) { %>
            <% String v = String.valueOf(m.get("meter_id")); %>
            <option value="<%= v %>" <%= (meterId != null && meterId.toString().equals(v)) ? "selected" : "" %>>
                #<%= m.get("meter_id") %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
            </option>
            <% } %>
        </select>
        <button type="submit">검증 조회</button>
    </form>

    <div class="section-title">1) 태그 매핑 정의</div>
    <table>
        <thead>
        <tr>
            <th>float_index</th>
            <th>tag token</th>
            <th>float_regs</th>
            <th>measurement_column</th>
            <th>supported</th>
            <th>target_table</th>
            <th>note</th>
        </tr>
        </thead>
        <tbody>
        <% for (Map<String, Object> r : mappingRows) { %>
        <tr>
            <td class="mono"><%= r.get("float_index") %></td>
            <td class="mono"><%= h(r.get("token")) %></td>
            <td class="mono"><%= r.get("float_registers") %></td>
            <td class="mono"><%= r.get("measurement_column") == null ? "-" : h(r.get("measurement_column")) %></td>
            <td>
                <% if ((Boolean)r.get("is_supported")) { %><span class="badge b-ok">YES</span><% } else { %><span class="badge b-no">NO</span><% } %>
            </td>
            <td class="mono"><%= h(r.get("target_table")) %></td>
            <td><%= r.get("note") == null ? "-" : h(r.get("note")) %></td>
        </tr>
        <% } %>
        </tbody>
    </table>

    <div class="section-title">2) 선택 PLC/Meter의 최신 PLC 샘플 vs measurements 최신값 비교</div>
    <table>
        <thead>
        <tr>
            <th>float_index</th>
            <th>tag</th>
            <th>measurement_column</th>
            <th>reg_address</th>
            <th>PLC value_float</th>
            <th>PLC measured_at</th>
            <th>measurements latest value</th>
        </tr>
        </thead>
        <tbody>
        <% if (latestTokenRows.isEmpty()) { %>
        <tr><td colspan="7">PLC와 Meter를 선택한 뒤 검증 데이터를 조회하세요.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : latestTokenRows) { %>
            <tr>
                <td class="mono"><%= r.get("float_index") %></td>
                <td class="mono"><%= h(r.get("token")) %></td>
                <td class="mono"><%= h(r.get("measurement_column")) %></td>
                <td class="mono"><%= r.get("reg_address") %></td>
                <td class="mono"><%= r.get("value_float") == null ? "-" : h(r.get("value_float")) %></td>
                <td><%= r.get("measured_at") == null ? "-" : h(r.get("measured_at")) %></td>
                <td class="mono">
                    <%
                        String col = (String)r.get("measurement_column");
                        Object mv = (col == null) ? null : latestMeasurement.get(col);
                    %>
                    <%= mv == null ? "-" : h(mv) %>
                </td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
