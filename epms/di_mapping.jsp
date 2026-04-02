<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%
try (Connection conn = openDbConnection()) {
    String plcParam = request.getParameter("plc_id");
    String pointParam = request.getParameter("point_id");
    String diAddressParam = request.getParameter("di_address");
    String panelNameParam = request.getParameter("panel_name");
    String itemNameParam = request.getParameter("item_name");
    String tagNameParam = request.getParameter("tag_name");
    String enabledParam = request.getParameter("enabled");
    String sortParam = request.getParameter("sort");

    Integer plcId = null;
    Integer pointId = null;
    Integer diAddress = null;
    String panelName = panelNameParam == null ? "" : panelNameParam.trim();
    String itemName = itemNameParam == null ? "" : itemNameParam.trim();
    String tagName = tagNameParam == null ? "" : tagNameParam.trim();
    String enabledFilter = enabledParam == null ? "Y" : enabledParam.trim().toUpperCase(Locale.ROOT);
    String sortKey = sortParam == null ? "plc_di_address_bit" : sortParam.trim();

    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.valueOf(plcParam.trim()); } catch (Exception ignore) {}
    try { if (pointParam != null && !pointParam.trim().isEmpty()) pointId = Integer.valueOf(pointParam.trim()); } catch (Exception ignore) {}
    try { if (diAddressParam != null && !diAddressParam.trim().isEmpty()) diAddress = Integer.valueOf(diAddressParam.trim()); } catch (Exception ignore) {}

    Set<String> allowedSortKeys = new HashSet<>(Arrays.asList(
        "plc_di_address_bit",
        "point_di_address_bit",
        "panel_item_tag",
        "item_name",
        "tag_name"
    ));
    if (!allowedSortKeys.contains(sortKey)) sortKey = "plc_di_address_bit";

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<Map<String, Object>> mapRows = new ArrayList<>();
    List<Map<String, Object>> tagRows = new ArrayList<>();
    List<String> panelOptions = new ArrayList<>();
    String error = null;

    try {
        String plcSql = "SELECT plc_id, plc_ip, plc_port, unit_id, enabled FROM dbo.plc_config ORDER BY plc_id";
        try (PreparedStatement ps = conn.prepareStatement(plcSql);
             ResultSet rs = ps.executeQuery()) {
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

        String panelSql =
            "SELECT DISTINCT LTRIM(RTRIM(panel_name)) AS panel_name " +
            "FROM dbo.plc_di_tag_map " +
            "WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> '' " +
            "ORDER BY LTRIM(RTRIM(panel_name))";
        try (PreparedStatement ps = conn.prepareStatement(panelSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) panelOptions.add(rs.getString(1));
        }

        StringBuilder mapSql = new StringBuilder();
        mapSql.append("SELECT di_map_id, plc_id, point_id, start_address, bit_count, enabled, updated_at ")
              .append("FROM dbo.plc_di_map WHERE 1=1 ");
        List<Integer> mapParams = new ArrayList<>();
        if (plcId != null) { mapSql.append("AND plc_id = ? "); mapParams.add(plcId); }
        if (pointId != null) { mapSql.append("AND point_id = ? "); mapParams.add(pointId); }
        mapSql.append("ORDER BY plc_id, start_address, point_id");

        try (PreparedStatement ps = conn.prepareStatement(mapSql.toString())) {
            for (int i = 0; i < mapParams.size(); i++) ps.setInt(i + 1, mapParams.get(i).intValue());
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
        List<Object> tagParams = new ArrayList<>();
        if (plcId != null) { tagSql.append("AND plc_id = ? "); tagParams.add(plcId); }
        if (pointId != null) { tagSql.append("AND point_id = ? "); tagParams.add(pointId); }
        if (diAddress != null) { tagSql.append("AND di_address = ? "); tagParams.add(diAddress); }
        if (!panelName.isEmpty()) { tagSql.append("AND LTRIM(RTRIM(ISNULL(panel_name,''))) = ? "); tagParams.add(panelName); }
        if (!itemName.isEmpty()) { tagSql.append("AND ISNULL(item_name,'') LIKE ? "); tagParams.add("%" + itemName + "%"); }
        if (!tagName.isEmpty()) { tagSql.append("AND ISNULL(tag_name,'') LIKE ? "); tagParams.add("%" + tagName + "%"); }
        if ("Y".equals(enabledFilter)) tagSql.append("AND enabled = 1 ");
        else if ("N".equals(enabledFilter)) tagSql.append("AND enabled = 0 ");

        if ("point_di_address_bit".equals(sortKey)) {
            tagSql.append("ORDER BY point_id, di_address, bit_no, plc_id");
        } else if ("panel_item_tag".equals(sortKey)) {
            tagSql.append("ORDER BY panel_name, item_name, tag_name, di_address, bit_no");
        } else if ("item_name".equals(sortKey)) {
            tagSql.append("ORDER BY item_name, panel_name, tag_name, di_address, bit_no");
        } else if ("tag_name".equals(sortKey)) {
            tagSql.append("ORDER BY tag_name, item_name, panel_name, di_address, bit_no");
        } else {
            tagSql.append("ORDER BY plc_id, di_address, bit_no");
        }

        try (PreparedStatement ps = conn.prepareStatement(tagSql.toString())) {
            for (int i = 0; i < tagParams.size(); i++) {
                Object v = tagParams.get(i);
                if (v instanceof Integer) ps.setInt(i + 1, ((Integer)v).intValue());
                else ps.setString(i + 1, String.valueOf(v));
            }
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
    }

    int activeTagCount = 0;
    for (Map<String, Object> r : tagRows) {
        if (Boolean.TRUE.equals(r.get("enabled"))) activeTagCount++;
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
        .filter-grid {
            display: grid;
            grid-template-columns: repeat(4, minmax(220px, 1fr));
            gap: 10px 12px;
            align-items: end;
            margin-top: 10px;
        }
        .filter-item {
            display: flex;
            flex-direction: column;
            gap: 4px;
            min-width: 0;
        }
        .filter-item label {
            font-size: 12px;
            color: #475569;
            font-weight: 700;
        }
        .filter-item input,
        .filter-item select {
            width: 100%;
            margin: 0;
        }
        .filter-actions {
            display: flex;
            gap: 8px;
            align-items: end;
            flex-wrap: wrap;
        }
        .filter-actions button {
            height: 34px;
        }
        .filter-summary {
            grid-column: 1 / -1;
            font-size: 12px;
            color: #475569;
        }
        .stats { display: flex; gap: 10px; flex-wrap: wrap; margin: 10px 0; }
        .stat-card {
            min-width: 140px;
            padding: 10px 12px;
            border-radius: 8px;
            background: #f8fbff;
            border: 1px solid #dbe5f2;
        }
        .stat-card .k { font-size: 12px; color: #64748b; }
        .stat-card .v { font-size: 20px; font-weight: 700; color: #1f3347; margin-top: 4px; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        td { font-size: 12px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .section-title { margin: 14px 0 6px; font-size: 15px; font-weight: 700; color: #1f3347; }
        .hint { font-size: 12px; color: #64748b; margin-bottom: 6px; }
        @media (max-width: 1100px) {
            .filter-grid { grid-template-columns: repeat(2, minmax(220px, 1fr)); }
        }
        @media (max-width: 680px) {
            .filter-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>DI 매핑 조회</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/ai_mapping.jsp'">AI 매핑</button>
            <button class="back-btn" onclick="location.href='/epms/plc/plc_excel_import.jsp'">PLC Excel Import</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        기준 파일: <span class="mono">docs/IO_Address_Tag_List_20260209-전원구조태깅추가.xlsx</span><br/>
        기준 규칙: DI 주소는 <span class="mono">plc_di_map.start_address</span>와 동일 주소 체계를 사용합니다.
    </div>

    <% if (error != null) { %>
    <div class="err-box">DB 오류: <%= h(error) %></div>
    <% } %>

    <form method="GET" class="filter-grid">
        <div class="filter-item">
            <label for="plc_id">PLC</label>
            <select id="plc_id" name="plc_id">
                <option value="">전체</option>
                <% for (Map<String, Object> p : plcList) { %>
                <% String v = String.valueOf(p.get("plc_id")); %>
                <option value="<%= h(v) %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                    PLC <%= p.get("plc_id") %> - <%= h(String.valueOf(p.get("plc_ip"))) %>:<%= p.get("plc_port") %> (unit <%= p.get("unit_id") %>)
                </option>
                <% } %>
            </select>
        </div>

        <div class="filter-item">
            <label for="point_id">Point ID</label>
            <input id="point_id" type="number" name="point_id" min="1" value="<%= pointId == null ? "" : pointId %>">
        </div>

        <div class="filter-item">
            <label for="di_address">Address</label>
            <input id="di_address" type="number" name="di_address" min="0" value="<%= diAddress == null ? "" : diAddress %>">
        </div>

        <div class="filter-item">
            <label for="panel_name">판넬명</label>
            <select id="panel_name" name="panel_name">
                <option value="">전체</option>
                <% for (String p : panelOptions) { %>
                <option value="<%= h(p) %>" <%= p.equals(panelName) ? "selected" : "" %>><%= h(p) %></option>
                <% } %>
            </select>
        </div>

        <div class="filter-item">
            <label for="item_name">Item Name</label>
            <input id="item_name" type="text" name="item_name" value="<%= h(itemName) %>" placeholder="item_name 포함 검색">
        </div>

        <div class="filter-item">
            <label for="tag_name">Tag Name</label>
            <input id="tag_name" type="text" name="tag_name" value="<%= h(tagName) %>" placeholder="tag_name 포함 검색">
        </div>

        <div class="filter-item">
            <label for="enabled">Enabled</label>
            <select id="enabled" name="enabled">
                <option value="" <%= enabledFilter.isEmpty() ? "selected" : "" %>>전체</option>
                <option value="Y" <%= "Y".equals(enabledFilter) ? "selected" : "" %>>ACTIVE</option>
                <option value="N" <%= "N".equals(enabledFilter) ? "selected" : "" %>>INACTIVE</option>
            </select>
        </div>

        <div class="filter-item">
            <label for="sort">정렬</label>
            <select id="sort" name="sort">
                <option value="plc_di_address_bit" <%= "plc_di_address_bit".equals(sortKey) ? "selected" : "" %>>PLC / Address / Bit</option>
                <option value="point_di_address_bit" <%= "point_di_address_bit".equals(sortKey) ? "selected" : "" %>>Point / Address / Bit</option>
                <option value="panel_item_tag" <%= "panel_item_tag".equals(sortKey) ? "selected" : "" %>>Panel / Item / Tag</option>
                <option value="item_name" <%= "item_name".equals(sortKey) ? "selected" : "" %>>Item Name</option>
                <option value="tag_name" <%= "tag_name".equals(sortKey) ? "selected" : "" %>>Tag Name</option>
            </select>
        </div>

        <div class="filter-actions">
            <button type="submit">조회</button>
            <button type="button" onclick="location.href='di_mapping.jsp'">초기화</button>
        </div>

        <div class="filter-summary">DI Address Map <%= mapRows.size() %>건 / DI Tag Map <%= tagRows.size() %>건</div>
    </form>

    <div class="stats">
        <div class="stat-card">
            <div class="k">DI Address Map</div>
            <div class="v"><%= mapRows.size() %></div>
        </div>
        <div class="stat-card">
            <div class="k">DI Tag Map</div>
            <div class="v"><%= tagRows.size() %></div>
        </div>
        <div class="stat-card">
            <div class="k">ACTIVE Tags</div>
            <div class="v"><%= activeTagCount %></div>
        </div>
        <div class="stat-card">
            <div class="k">INACTIVE Tags</div>
            <div class="v"><%= tagRows.size() - activeTagCount %></div>
        </div>
    </div>

    <div class="section-title">1) DI Tag Map</div>
    <div class="hint">tag_name, item_name, panel_name 기준으로 현재 활성/비활성 태그를 조회합니다.</div>
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
                <td><%= h(String.valueOf(r.get("tag_name") == null ? "-" : r.get("tag_name"))) %></td>
                <td><%= h(String.valueOf(r.get("item_name") == null ? "-" : r.get("item_name"))) %></td>
                <td><%= h(String.valueOf(r.get("panel_name") == null ? "-" : r.get("panel_name"))) %></td>
                <td>
                    <% if (Boolean.TRUE.equals(r.get("enabled"))) { %>
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

    <div class="section-title">2) DI Address Map</div>
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
                    <% if (Boolean.TRUE.equals(r.get("enabled"))) { %>
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
</div>
<footer>짤 EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
<%
} // end try-with-resources
%>
