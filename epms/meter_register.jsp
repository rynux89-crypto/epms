<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static Double parseDoubleNullable(String value) {
        if (value == null) return null;
        String s = value.trim();
        if (s.isEmpty()) return null;
        try {
            return Double.parseDouble(s);
        } catch (Exception e) {
            return null;
        }
    }

    private static class MeterRegisterRequest {
        String action;
        Integer meterId;
        String name;
        String buildingName;
        String panelName;
        String usageType;
        Double ratedVoltage;
        Double ratedCurrent;
    }

    private static MeterRegisterRequest buildMeterRegisterRequest(javax.servlet.http.HttpServletRequest request) {
        MeterRegisterRequest req = new MeterRegisterRequest();
        req.action = request.getParameter("action");
        req.meterId = parsePositiveInt(request.getParameter("meter_id"));
        req.name = trimToNull(request.getParameter("name"));
        req.buildingName = trimToNull(request.getParameter("building_name"));
        req.panelName = trimToNull(request.getParameter("panel_name"));
        req.usageType = trimToNull(request.getParameter("usage_type"));
        req.ratedVoltage = parseDoubleNullable(request.getParameter("rated_voltage"));
        req.ratedCurrent = parseDoubleNullable(request.getParameter("rated_current"));
        return req;
    }

    private static String buildMeterRegisterQuerySuffix(String buildingQ, String panelQ) {
        try {
            return "&building_q=" + URLEncoder.encode(buildingQ == null ? "" : buildingQ, "UTF-8") +
                   "&panel_q=" + URLEncoder.encode(panelQ == null ? "" : panelQ, "UTF-8");
        } catch (Exception ignore) {
            return "";
        }
    }

    private static String validateMeterRegisterRequest(MeterRegisterRequest req) {
        if (req == null) return "요청이 올바르지 않습니다.";
        if ("add".equals(req.action) || "update".equals(req.action)) {
            if (req.name == null) return "계측기 이름을 입력해 주세요.";
        }
        if ("update".equals(req.action) || "delete".equals(req.action)) {
            if (req.meterId == null) return "유효하지 않은 계측기 ID입니다.";
        }
        return null;
    }

    private static String handleAddMeter(Connection conn, MeterRegisterRequest req) {
        try {
            String insSql =
                "INSERT INTO dbo.meters " +
                "(name, panel_name, building_name, usage_type, rated_voltage, rated_current) " +
                "VALUES (?, ?, ?, ?, ?, ?)";
            try (PreparedStatement ps = conn.prepareStatement(insSql)) {
                ps.setString(1, req.name);
                ps.setString(2, req.panelName);
                ps.setString(3, req.buildingName);
                ps.setString(4, req.usageType);
                if (req.ratedVoltage == null) ps.setNull(5, Types.DOUBLE); else ps.setDouble(5, req.ratedVoltage);
                if (req.ratedCurrent == null) ps.setNull(6, Types.DOUBLE); else ps.setDouble(6, req.ratedCurrent);
                ps.executeUpdate();
            }
            return null;
        } catch (Exception e) {
            return "등록 실패: " + e.getMessage();
        }
    }

    private static String handleUpdateMeter(Connection conn, MeterRegisterRequest req) {
        String updSql =
            "UPDATE dbo.meters " +
            "SET name = ?, panel_name = ?, building_name = ?, usage_type = ?, rated_voltage = ?, rated_current = ? " +
            "WHERE meter_id = ?";
        try (PreparedStatement ps = conn.prepareStatement(updSql)) {
            ps.setString(1, req.name);
            ps.setString(2, req.panelName);
            ps.setString(3, req.buildingName);
            ps.setString(4, req.usageType);
            if (req.ratedVoltage == null) ps.setNull(5, Types.DOUBLE); else ps.setDouble(5, req.ratedVoltage);
            if (req.ratedCurrent == null) ps.setNull(6, Types.DOUBLE); else ps.setDouble(6, req.ratedCurrent);
            ps.setInt(7, req.meterId);
            int affected = ps.executeUpdate();
            if (affected == 0) return "수정할 계측기를 찾을 수 없습니다.";
            return null;
        } catch (Exception e) {
            return "수정 실패: " + e.getMessage();
        }
    }

    private static String handleDeleteMeter(Connection conn, MeterRegisterRequest req) {
        String delSql = "DELETE FROM dbo.meters WHERE meter_id = ?";
        try (PreparedStatement ps = conn.prepareStatement(delSql)) {
            ps.setInt(1, req.meterId);
            int affected = ps.executeUpdate();
            if (affected == 0) return "삭제할 계측기를 찾을 수 없습니다.";
            return null;
        } catch (Exception e) {
            return "삭제 실패: " + e.getMessage();
        }
    }
%>
<%
try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String message = request.getParameter("msg");
    String error = request.getParameter("err");
    String self = request.getRequestURI();

    String buildingQ = request.getParameter("building_q");
    String panelQ = request.getParameter("panel_q");
    if (buildingQ == null) buildingQ = "";
    if (panelQ == null) panelQ = "";
    buildingQ = buildingQ.trim();
    panelQ = panelQ.trim();

    String querySuffix = buildMeterRegisterQuerySuffix(buildingQ, panelQ);

    if ("POST".equalsIgnoreCase(request.getMethod())) {
        MeterRegisterRequest formReq = buildMeterRegisterRequest(request);
        error = validateMeterRegisterRequest(formReq);

        if (error == null) {
            if ("add".equals(formReq.action)) {
                error = handleAddMeter(conn, formReq);
                if (error == null) {
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("계측기가 등록되었습니다.", "UTF-8") + querySuffix);
                    return;
                }
            } else if ("update".equals(formReq.action)) {
                error = handleUpdateMeter(conn, formReq);
                if (error == null) {
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("계측기 정보가 수정되었습니다.", "UTF-8") + querySuffix);
                    return;
                }
            } else if ("delete".equals(formReq.action)) {
                error = handleDeleteMeter(conn, formReq);
                if (error == null) {
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("계측기가 삭제되었습니다.", "UTF-8") + querySuffix);
                    return;
                }
            }
        }
    }

    Map<String, Integer> stats = new HashMap<>();
    List<Map<String, Object>> schemaRows = new ArrayList<>();
    List<String> buildingOptions = new ArrayList<>();
    List<String> panelOptions = new ArrayList<>();
    List<Map<String, Object>> rows = new ArrayList<>();

    try {
        String statsSql =
            "SELECT COUNT(*) AS total_cnt, " +
            "       COUNT(DISTINCT building_name) AS building_cnt, " +
            "       COUNT(DISTINCT panel_name) AS panel_cnt " +
            "FROM dbo.meters";
        try (PreparedStatement ps = conn.prepareStatement(statsSql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                stats.put("total_cnt", rs.getInt("total_cnt"));
                stats.put("building_cnt", rs.getInt("building_cnt"));
                stats.put("panel_cnt", rs.getInt("panel_cnt"));
            }
        }

        String schemaSql =
            "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE " +
            "FROM INFORMATION_SCHEMA.COLUMNS " +
            "WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'meters' " +
            "ORDER BY ORDINAL_POSITION";
        try (PreparedStatement ps = conn.prepareStatement(schemaSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("column_name", rs.getString("COLUMN_NAME"));
                r.put("data_type", rs.getString("DATA_TYPE"));
                r.put("char_len", rs.getObject("CHARACTER_MAXIMUM_LENGTH"));
                r.put("is_nullable", rs.getString("IS_NULLABLE"));
                schemaRows.add(r);
            }
        }

        String bSql =
            "SELECT DISTINCT LTRIM(RTRIM(building_name)) AS building_name FROM dbo.meters " +
            "WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name)) <> '' " +
            "ORDER BY LTRIM(RTRIM(building_name))";
        try (PreparedStatement ps = conn.prepareStatement(bSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) buildingOptions.add(rs.getString(1));
        }

        String pSql =
            "SELECT panel_name " +
            "FROM (" +
            "  SELECT LTRIM(RTRIM(panel_name)) AS panel_name, MIN(meter_id) AS first_meter_id " +
            "  FROM dbo.meters " +
            "  WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> '' " +
            "  GROUP BY LTRIM(RTRIM(panel_name))" +
            ") p " +
            "ORDER BY p.first_meter_id, p.panel_name";
        try (PreparedStatement ps = conn.prepareStatement(pSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) panelOptions.add(rs.getString(1));
        }

        String listSql =
            "SELECT meter_id, name, panel_name, building_name, usage_type, rated_voltage, rated_current " +
            "FROM dbo.meters " +
            "WHERE (? = '' OR LTRIM(RTRIM(ISNULL(building_name, ''))) LIKE ?) " +
            "  AND (? = '' OR LTRIM(RTRIM(ISNULL(panel_name, ''))) LIKE ?) " +
            "ORDER BY meter_id";
        try (PreparedStatement ps = conn.prepareStatement(listSql)) {
            ps.setString(1, buildingQ);
            ps.setString(2, "%" + buildingQ + "%");
            ps.setString(3, panelQ);
            ps.setString(4, "%" + panelQ + "%");
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("meter_id", rs.getInt("meter_id"));
                    r.put("name", rs.getString("name"));
                    r.put("panel_name", rs.getString("panel_name"));
                    r.put("building_name", rs.getString("building_name"));
                    r.put("usage_type", rs.getString("usage_type"));
                    r.put("rated_voltage", rs.getObject("rated_voltage"));
                    r.put("rated_current", rs.getObject("rated_current"));
                    rows.add(r);
                }
            }
        }
    } catch (Exception e) {
        error = "조회 실패: " + e.getMessage();
    }
%>
<html>
<head>
    <title>계측기 등록 관리</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1400px; margin: 0 auto; }
        .notice { padding: 10px 12px; border-radius: 8px; margin-bottom: 10px; font-weight: 700; }
        .ok-msg { border: 1px solid #b7ebc6; background: #ebfff1; color: #0f7a2a; }
        .err-msg { border: 1px solid #ffc9c9; background: #fff1f1; color: #b42318; }
        .info-box {
            margin: 10px 0;
            padding: 10px 12px;
            border-radius: 8px;
            background: #eef6ff;
            border: 1px solid #cfe2ff;
            color: #1d4f91;
            font-size: 13px;
        }
        .schema-line {
            margin-top: 8px;
            padding: 8px 10px;
            border: 1px solid #dbe7ff;
            border-radius: 6px;
            background: #fff;
            font-size: 12px;
            color: #334155;
            white-space: nowrap;
            overflow-x: auto;
        }
        .search-grid { display: flex; gap: 8px; align-items: center; margin-bottom: 10px; flex-wrap: nowrap; }
        .search-item { display: flex; align-items: center; gap: 6px; min-width: 0; flex: 1 1 0; }
        .search-item label { font-size: 12px; color: #334155; font-weight: 600; white-space: nowrap; min-width: 84px; }
        .search-item input { margin: 0; width: 180px; }
        .search-item .quick-select { width: 180px; margin: 0; }
        .form-grid { display: grid; grid-template-columns: 1fr 1fr 1fr 0.8fr 0.8fr 0.8fr auto; gap: 8px; align-items: end; }
        .input-group { display: flex; flex-direction: column; gap: 4px; }
        .input-group label { font-size: 12px; color: #334155; font-weight: 600; }
        .quick-select { margin: 0; width: 100%; }
        .btn { height: 34px; padding: 0 14px; border: none; border-radius: 6px; cursor: pointer; color: #fff; font-weight: 700; }
        .btn-primary { background: #007acc; }
        .btn-primary:hover { background: #005fa3; }
        .btn-sub { background: #475569; }
        .btn-sub:hover { background: #334155; }
        .action-btn { border: none; border-radius: 6px; padding: 6px 10px; font-size: 12px; font-weight: 700; cursor: pointer; color: #fff; }
        .btn-update { background: #006d77; }
        .btn-delete { background: #c62828; }
        .actions-wrap { display: flex; gap: 6px; justify-content: center; }
        .row-form { margin: 0; padding: 0; box-shadow: none; background: transparent; display: inline; }
        .in-cell { width: 100%; min-width: 90px; margin: 0; }
        @media (max-width: 1200px) {
            .search-grid { flex-wrap: wrap; }
            .search-item { flex: 1 1 100%; }
            .search-item input, .search-item .quick-select { width: 100%; }
            .form-grid { grid-template-columns: 1fr 1fr; }
            .btn { width: 100%; }
            .actions-wrap { flex-direction: column; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🗂️ 계측기 등록 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <% if (message != null && !message.trim().isEmpty()) { %>
    <div class="notice ok-msg"><%= message %></div>
    <% } %>
    <% if (error != null && !error.trim().isEmpty()) { %>
    <div class="notice err-msg"><%= error %></div>
    <% } %>

    <div class="info-box">
        <div>대상 테이블: <b>dbo.meters</b> (기본키 <b>meter_id</b>, 신규 등록 시 자동 부여)</div>
        <div>총 <b><%= stats.get("total_cnt") == null ? 0 : stats.get("total_cnt") %></b>건 / 건물 <b><%= stats.get("building_cnt") == null ? 0 : stats.get("building_cnt") %></b>종 / 패널 <b><%= stats.get("panel_cnt") == null ? 0 : stats.get("panel_cnt") %></b>종</div>
        <div class="schema-line">
            <% for (int i = 0; i < schemaRows.size(); i++) { %>
                <% Map<String, Object> c = schemaRows.get(i); %>
                <b><%= c.get("column_name") %></b>:
                <%= c.get("data_type") %><% if (c.get("char_len") != null) { %>(<%= c.get("char_len") %>)<% } %>
                / <%= c.get("is_nullable") %><%= (i < schemaRows.size() - 1) ? " | " : "" %>
            <% } %>
        </div>
    </div>

    <form method="GET">
        <div class="search-grid">
            <div class="search-item">
                <label for="building_q">건물명 검색</label>
                <input id="building_q" type="text" name="building_q" value="<%= h(buildingQ) %>" placeholder="예: 공학관">
                <select id="building_q_select" class="quick-select">
                    <option value="">건물 전체 목록에서 선택</option>
                    <% for (String b : buildingOptions) { %>
                    <option value="<%= h(b) %>"><%= h(b) %></option>
                    <% } %>
                </select>
            </div>
            <div class="search-item">
                <label for="panel_q">패널명 검색</label>
                <input id="panel_q" type="text" name="panel_q" value="<%= h(panelQ) %>" placeholder="예: MDB">
                <select id="panel_q_select" class="quick-select">
                    <option value="">패널 전체 목록에서 선택</option>
                    <% for (String p : panelOptions) { %>
                    <option value="<%= h(p) %>"><%= h(p) %></option>
                    <% } %>
                </select>
            </div>
            <button class="btn btn-primary" type="submit">조회</button>
            <button class="btn btn-sub" type="button" onclick="location.href='meter_register.jsp'">초기화</button>
        </div>
    </form>

    <form method="POST">
        <input type="hidden" name="action" value="add">
        <input type="hidden" name="building_q" value="<%= h(buildingQ) %>">
        <input type="hidden" name="panel_q" value="<%= h(panelQ) %>">
        <div class="form-grid">
            <div class="input-group">
                <label for="name">계측기 이름</label>
                <input id="name" type="text" name="name" maxlength="100" required>
            </div>
            <div class="input-group">
                <label for="building_name">건물명</label>
                <input id="building_name" type="text" name="building_name" maxlength="100">
            </div>
            <div class="input-group">
                <label for="panel_name">패널명</label>
                <input id="panel_name" type="text" name="panel_name" maxlength="100">
            </div>
            <div class="input-group">
                <label for="usage_type">용도</label>
                <input id="usage_type" type="text" name="usage_type" maxlength="50">
            </div>
            <div class="input-group">
                <label for="rated_voltage">정격 전압</label>
                <input id="rated_voltage" type="number" step="any" name="rated_voltage">
            </div>
            <div class="input-group">
                <label for="rated_current">정격 전류</label>
                <input id="rated_current" type="number" step="any" name="rated_current">
            </div>
            <button class="btn btn-primary" type="submit">신규 등록</button>
        </div>
    </form>

    <table>
        <thead>
        <tr>
            <th>계측기 ID</th>
            <th>계측기 이름</th>
            <th>건물명</th>
            <th>패널명</th>
            <th>용도</th>
            <th>정격 전압</th>
            <th>정격 전류</th>
            <th>관리</th>
        </tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
        <tr><td colspan="8">조회된 계측기가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : rows) { %>
            <% String formId = "upd_" + r.get("meter_id"); %>
            <tr>
                <td><%= r.get("meter_id") %></td>
                <td><input class="in-cell" type="text" name="name" maxlength="100" value="<%= h(r.get("name")) %>" form="<%= formId %>" required></td>
                <td><input class="in-cell" type="text" name="building_name" maxlength="100" value="<%= h(r.get("building_name")) %>" form="<%= formId %>"></td>
                <td><input class="in-cell" type="text" name="panel_name" maxlength="100" value="<%= h(r.get("panel_name")) %>" form="<%= formId %>"></td>
                <td><input class="in-cell" type="text" name="usage_type" maxlength="50" value="<%= h(r.get("usage_type")) %>" form="<%= formId %>"></td>
                <td><input class="in-cell" type="number" step="any" name="rated_voltage" value="<%= h(r.get("rated_voltage")) %>" form="<%= formId %>"></td>
                <td><input class="in-cell" type="number" step="any" name="rated_current" value="<%= h(r.get("rated_current")) %>" form="<%= formId %>"></td>
                <td>
                    <div class="actions-wrap">
                        <form id="<%= formId %>" class="row-form" method="POST">
                            <input type="hidden" name="action" value="update">
                            <input type="hidden" name="meter_id" value="<%= r.get("meter_id") %>">
                            <input type="hidden" name="building_q" value="<%= h(buildingQ) %>">
                            <input type="hidden" name="panel_q" value="<%= h(panelQ) %>">
                            <button type="submit" class="action-btn btn-update">수정</button>
                        </form>
                        <form class="row-form" method="POST" onsubmit="return confirm('해당 계측기를 삭제하시겠습니까?');">
                            <input type="hidden" name="action" value="delete">
                            <input type="hidden" name="meter_id" value="<%= r.get("meter_id") %>">
                            <input type="hidden" name="building_q" value="<%= h(buildingQ) %>">
                            <input type="hidden" name="panel_q" value="<%= h(panelQ) %>">
                            <button type="submit" class="action-btn btn-delete">삭제</button>
                        </form>
                    </div>
                </td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
(function(){
    var bInput = document.getElementById('building_q');
    var pInput = document.getElementById('panel_q');
    var bSel = document.getElementById('building_q_select');
    var pSel = document.getElementById('panel_q_select');
    if (bSel && bInput) {
        bSel.addEventListener('change', function(){
            if (bSel.value) bInput.value = bSel.value;
        });
    }
    if (pSel && pInput) {
        pSel.addEventListener('change', function(){
            if (pSel.value) pInput.value = pSel.value;
        });
    }
})();
</script>
<%
} // end try-with-resources
%>
</body>
</html>
