<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%
    String plcParam = request.getParameter("plc_id");
    String pointParam = request.getParameter("point_id");
    Integer plcId = null;
    Integer pointId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}
    try { if (pointParam != null && !pointParam.trim().isEmpty()) pointId = Integer.parseInt(pointParam.trim()); } catch (Exception ignore) {}

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<Map<String, Object>> mapRows = new ArrayList<>();
    List<Map<String, Object>> tagRows = new ArrayList<>();
    String error = null;

    try {
        String plcSql = "SELECT plc_id, plc_ip, plc_port, unit_id, enabled FROM dbo.plc_config ORDER BY plc_id";
        try (PreparedStatement ps = conn.prepareStatement(plcSql); ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> p = new HashMap<>();
                p.put("plc_id", rs.getInt("plc_id"));
                p.put("plc_ip", rs.getString("plc_ip"));
                p.put("plc_port", rs.getInt("plc_port"));
                p.put("unit_id", rs.getInt("unit_id"));
                p.put("enabled", rs.getBoolean("enabled"));
                plcList.add(p);
            }
        }

        StringBuilder mapSql = new StringBuilder();
        mapSql.append("SELECT di_map_id, plc_id, point_id, start_address, bit_count, enabled, updated_at ")
              .append("FROM dbo.plc_di_map WHERE 1=1 ");
        List<Integer> mapParams = new ArrayList<>();
        if (plcId != null) { mapSql.append("AND plc_id = ? "); mapParams.add(plcId); }
        if (pointId != null) { mapSql.append("AND point_id = ? "); mapParams.add(pointId); }
        mapSql.append("ORDER BY plc_id, start_address, point_id");

        try (PreparedStatement ps = conn.prepareStatement(mapSql.toString())) {
            for (int i = 0; i < mapParams.size(); i++) ps.setInt(i + 1, mapParams.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("di_map_id", rs.getInt("di_map_id"));
                    r.put("plc_id", rs.getInt("plc_id"));
                    r.put("point_id", rs.getInt("point_id"));
                    r.put("start_address", rs.getInt("start_address"));
                    r.put("bit_count", rs.getInt("bit_count"));
                    r.put("enabled", rs.getBoolean("enabled"));
                    r.put("updated_at", rs.getTimestamp("updated_at"));
                    mapRows.add(r);
                }
            }
        }

        StringBuilder tagSql = new StringBuilder();
        tagSql.append("SELECT tag_id, plc_id, point_id, di_address, bit_no, tag_name, item_name, panel_name, enabled ")
              .append("FROM dbo.plc_di_tag_map WHERE 1=1 ");
        List<Integer> params = new ArrayList<>();
        if (plcId != null) { tagSql.append("AND plc_id = ? "); params.add(plcId); }
        if (pointId != null) { tagSql.append("AND point_id = ? "); params.add(pointId); }
        tagSql.append("ORDER BY plc_id, di_address, bit_no");

        try (PreparedStatement ps = conn.prepareStatement(tagSql.toString())) {
            for (int i = 0; i < params.size(); i++) ps.setInt(i + 1, params.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("tag_id", rs.getInt("tag_id"));
                    r.put("plc_id", rs.getInt("plc_id"));
                    r.put("point_id", rs.getInt("point_id"));
                    r.put("di_address", rs.getInt("di_address"));
                    r.put("bit_no", rs.getInt("bit_no"));
                    r.put("tag_name", rs.getString("tag_name"));
                    r.put("item_name", rs.getString("item_name"));
                    r.put("panel_name", rs.getString("panel_name"));
                    r.put("enabled", rs.getBoolean("enabled"));
                    tagRows.add(r);
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
    <title>DI Mapping</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1450px; margin: 0 auto; }
        .info-box {
            margin: 10px 0;
            padding: 10px 12px;
            border-radius: 8px;
            background: #eef6ff;
            border: 1px solid #cfe2ff;
            color: #1d4f91;
            font-size: 13px;
        }
        .err-box {
            margin: 10px 0;
            padding: 10px 12px;
            border-radius: 8px;
            background: #fff1f1;
            border: 1px solid #ffc9c9;
            color: #b42318;
            font-size: 13px;
            font-weight: 700;
        }
        .toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        td { font-size: 12px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .section-title { margin: 14px 0 6px; font-size: 15px; font-weight: 700; color: #1f3347; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🔗 DI 매핑 (Excel 기반)</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/ai_mapping.jsp'">AI 매핑</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        기준 파일: <span class="mono">docs/IO_Address_Tag_List_20260209-전압고조파추가.xlsx</span><br/>
        규칙: DI 기준주소는 DB <span class="mono">start_address</span>와 동일 주소 체계
    </div>

    <% if (error != null) { %>
    <div class="err-box">DB 오류: <%= error %></div>
    <% } %>

    <form method="GET" class="toolbar">
        <label for="plc_id">PLC:</label>
        <select id="plc_id" name="plc_id">
            <option value="">전체</option>
            <% for (Map<String, Object> p : plcList) { %>
            <% String v = String.valueOf(p.get("plc_id")); %>
            <option value="<%= v %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                PLC <%= p.get("plc_id") %> - <%= p.get("plc_ip") %>:<%= p.get("plc_port") %> (unit <%= p.get("unit_id") %>)
            </option>
            <% } %>
        </select>

        <label for="point_id">Point ID:</label>
        <input id="point_id" type="number" name="point_id" min="1" value="<%= pointId == null ? "" : pointId %>">
        <button type="submit">조회</button>
        <span style="margin-left:8px;font-size:12px;color:#475569;">DI Map <%= mapRows.size() %>건 / Tag <%= tagRows.size() %>건</span>
    </form>

    <div class="section-title">1) DI Address Map</div>
    <table>
        <thead>
        <tr>
            <th>di_map_id</th>
            <th>plc_id</th>
            <th>point_id</th>
            <th>start_address</th>
            <th>bit_count</th>
            <th>enabled</th>
            <th>updated_at</th>
        </tr>
        </thead>
        <tbody>
        <% if (mapRows.isEmpty()) { %>
        <tr><td colspan="7">데이터가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : mapRows) { %>
            <tr>
                <td><%= r.get("di_map_id") %></td>
                <td><%= r.get("plc_id") %></td>
                <td><%= r.get("point_id") %></td>
                <td class="mono"><%= r.get("start_address") %></td>
                <td><%= r.get("bit_count") %></td>
                <td>
                    <% if ((Boolean)r.get("enabled")) { %>
                    <span class="badge b-on">ACTIVE</span>
                    <% } else { %>
                    <span class="badge b-off">INACTIVE</span>
                    <% } %>
                </td>
                <td><%= r.get("updated_at") %></td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>

    <div class="section-title">2) DI Tag Map</div>
    <table>
        <thead>
        <tr>
            <th>tag_id</th>
            <th>plc_id</th>
            <th>point_id</th>
            <th>di_address</th>
            <th>bit_no</th>
            <th>tag_name</th>
            <th>item_name</th>
            <th>panel_name</th>
            <th>enabled</th>
        </tr>
        </thead>
        <tbody>
        <% if (tagRows.isEmpty()) { %>
        <tr><td colspan="9">데이터가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : tagRows) { %>
            <tr>
                <td><%= r.get("tag_id") %></td>
                <td><%= r.get("plc_id") %></td>
                <td><%= r.get("point_id") %></td>
                <td class="mono"><%= r.get("di_address") %></td>
                <td class="mono"><%= r.get("bit_no") %></td>
                <td><%= r.get("tag_name") == null ? "-" : r.get("tag_name") %></td>
                <td><%= r.get("item_name") == null ? "-" : r.get("item_name") %></td>
                <td><%= r.get("panel_name") == null ? "-" : r.get("panel_name") %></td>
                <td>
                    <% if ((Boolean)r.get("enabled")) { %>
                    <span class="badge b-on">ACTIVE</span>
                    <% } else { %>
                    <span class="badge b-off">INACTIVE</span>
                    <% } %>
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
