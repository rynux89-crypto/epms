<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%
    request.setCharacterEncoding("UTF-8");
    String plcParam = request.getParameter("plc_id");
    Integer plcId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}
    String panelName = request.getParameter("panel_name");
    if (panelName == null) panelName = "";
    panelName = panelName.trim();

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<String> panelList = new ArrayList<>();
    List<Map<String, Object>> rows = new ArrayList<>();
    String error = null;

    try {
        String q = "SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config ORDER BY plc_id";
        try (PreparedStatement ps = conn.prepareStatement(q); ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> p = new HashMap<>();
                p.put("plc_id", rs.getInt("plc_id"));
                p.put("plc_ip", rs.getString("plc_ip"));
                p.put("plc_port", rs.getInt("plc_port"));
                p.put("unit_id", rs.getInt("unit_id"));
                p.put("polling_ms", rs.getInt("polling_ms"));
                p.put("enabled", rs.getBoolean("enabled"));
                plcList.add(p);
            }
        }

        StringBuilder panelSql = new StringBuilder();
        panelSql.append("SELECT mt.panel_name ")
                .append("FROM dbo.meters mt ")
                .append("WHERE mt.panel_name IS NOT NULL AND LTRIM(RTRIM(mt.panel_name)) <> '' ")
                .append("GROUP BY mt.panel_name ")
                .append("ORDER BY MIN(mt.meter_id), mt.panel_name");
        try (PreparedStatement ps = conn.prepareStatement(panelSql.toString())) {
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) panelList.add(rs.getString(1));
            }
        }

        StringBuilder sql = new StringBuilder();
        sql.append("SELECT m.map_id, m.plc_id, m.meter_id, m.start_address, m.float_count, m.byte_order, m.enabled, ")
           .append("       CONVERT(VARCHAR(19), m.updated_at, 120) AS updated_at_text, ")
           .append("       mt.name AS meter_name, mt.panel_name, mt.building_name ")
           .append("FROM dbo.plc_meter_map m ")
           .append("LEFT JOIN dbo.meters mt ON mt.meter_id = m.meter_id ")
           .append("WHERE m.enabled = 1 ");
        if (plcId != null) sql.append("AND m.plc_id = ? ");
        if (!panelName.isEmpty()) sql.append("AND mt.panel_name = ? ");
        sql.append("ORDER BY m.meter_id");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int paramIdx = 1;
            if (plcId != null) ps.setInt(paramIdx++, plcId);
            if (!panelName.isEmpty()) ps.setString(paramIdx++, panelName);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("map_id", rs.getInt("map_id"));
                    r.put("plc_id", rs.getInt("plc_id"));
                    r.put("meter_id", rs.getInt("meter_id"));
                    r.put("start_address", rs.getInt("start_address"));
                    r.put("float_count", rs.getInt("float_count"));
                    r.put("byte_order", rs.getString("byte_order"));
                    r.put("enabled", rs.getBoolean("enabled"));
                    r.put("updated_at", rs.getString("updated_at_text"));
                    r.put("meter_name", rs.getString("meter_name"));
                    r.put("panel_name", rs.getString("panel_name"));
                    r.put("building_name", rs.getString("building_name"));
                    rows.add(r);
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
    <title>AI Mapping</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1400px; margin: 0 auto; }
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
        .toolbar {
            display: flex;
            align-items: center;
            gap: 8px;
            flex-wrap: wrap;
        }
        .badge {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 999px;
            font-size: 11px;
            font-weight: 700;
        }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        td { font-size: 12px; }
        th { font-size: 12px; white-space: nowrap; }
        .th-wrap { display: inline-flex; flex-direction: column; align-items: center; gap: 4px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .sort-btn {
            padding: 3px 8px;
            font-size: 12px;
            line-height: 1.4;
            border: 1px solid #cbd5e1;
            border-radius: 999px;
            background: #f8fafc;
            color: #334155;
            cursor: pointer;
        }
        .sort-btn:hover { background: #eef2f7; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🔗 AI 매핑 (Excel 기반)</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/di_mapping.jsp'">DI 매핑</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        기준 파일은 고정값이 아니며, 최근 <span class="mono">plc/plc_excel_import.jsp</span>에서 적용한 엑셀 기준으로 표시됩니다.<br/>
        AI 매핑 주소는 import 시 엑셀 기준주소 +1로 저장됩니다 (예: Excel 40000 → DB 40001).<br/>
        본 화면은 현재 활성(enabled=1) 매핑만 표시합니다.
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
        <label for="panel_name">판넬명:</label>
        <select id="panel_name" name="panel_name">
            <option value="">전체</option>
            <% for (String pn : panelList) { %>
            <option value="<%= h(pn) %>" <%= pn.equals(panelName) ? "selected" : "" %>><%= h(pn) %></option>
            <% } %>
        </select>
        <button type="submit">조회</button>
        <span style="margin-left:8px;font-size:12px;color:#475569;">총 <%= rows.size() %>건</span>
    </form>

    <table>
        <thead>
        <tr>
            <th><span class="th-wrap"><span>map_id</span><button type="button" class="sort-btn" data-col="0">ASC</button></span></th>
            <th><span class="th-wrap"><span>plc_id</span><button type="button" class="sort-btn" data-col="1">ASC</button></span></th>
            <th><span class="th-wrap"><span>meter_id</span><button type="button" class="sort-btn" data-col="2">ASC</button></span></th>
            <th><span class="th-wrap"><span>meter_name</span><button type="button" class="sort-btn" data-col="3">ASC</button></span></th>
            <th><span class="th-wrap"><span>panel</span><button type="button" class="sort-btn" data-col="4">ASC</button></span></th>
            <th><span class="th-wrap"><span>building</span><button type="button" class="sort-btn" data-col="5">ASC</button></span></th>
            <th><span class="th-wrap"><span>DB start_address</span><button type="button" class="sort-btn" data-col="6">ASC</button></span></th>
            <th><span class="th-wrap"><span>float_count</span><button type="button" class="sort-btn" data-col="7">ASC</button></span></th>
            <th><span class="th-wrap"><span>byte_order</span><button type="button" class="sort-btn" data-col="8">ASC</button></span></th>
            <th><span class="th-wrap"><span>enabled</span><button type="button" class="sort-btn" data-col="9">ASC</button></span></th>
            <th><span class="th-wrap"><span>updated_at</span><button type="button" class="sort-btn" data-col="10">ASC</button></span></th>
        </tr>
        </thead>
        <tbody id="aiMappingBody">
        <% if (rows.isEmpty()) { %>
        <tr><td colspan="11">데이터가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : rows) { %>
            <tr>
                <td><%= r.get("map_id") %></td>
                <td><%= r.get("plc_id") %></td>
                <td><%= r.get("meter_id") %></td>
                <td><%= r.get("meter_name") == null ? "-" : r.get("meter_name") %></td>
                <td><%= r.get("panel_name") == null ? "-" : r.get("panel_name") %></td>
                <td><%= r.get("building_name") == null ? "-" : r.get("building_name") %></td>
                <td class="mono"><%= r.get("start_address") %></td>
                <td><%= r.get("float_count") %></td>
                <td class="mono"><%= r.get("byte_order") %></td>
                <td>
                    <% if ((Boolean)r.get("enabled")) { %>
                    <span class="badge b-on">ACTIVE</span>
                    <% } else { %>
                    <span class="badge b-off">INACTIVE</span>
                    <% } %>
                </td>
                <td><%= r.get("updated_at") == null ? "-" : r.get("updated_at") %></td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
(function(){
  const tbody = document.getElementById('aiMappingBody');
  if (!tbody) return;

  function cellValue(tr, colIdx) {
    const td = tr.children[colIdx];
    return td ? String(td.textContent || '').trim() : '';
  }

  function compareAsc(a, b, colIdx) {
    const av = cellValue(a, colIdx);
    const bv = cellValue(b, colIdx);
    const an = Number(av);
    const bn = Number(bv);
    if (av !== '' && bv !== '' && Number.isFinite(an) && Number.isFinite(bn)) {
      return an - bn;
    }
    return av.localeCompare(bv, 'ko', { numeric: true, sensitivity: 'base' });
  }

  document.querySelectorAll('.sort-btn').forEach(function(btn){
    btn.addEventListener('click', function(){
      const colIdx = parseInt(btn.getAttribute('data-col') || '-1', 10);
      if (colIdx < 0) return;
      const rows = Array.from(tbody.querySelectorAll('tr')).filter(function(tr){
        return tr.children.length > 1;
      });
      rows.sort(function(a, b){ return compareAsc(a, b, colIdx); });
      rows.forEach(function(tr){ tbody.appendChild(tr); });
    });
  });
})();
</script>
</body>
</html>

