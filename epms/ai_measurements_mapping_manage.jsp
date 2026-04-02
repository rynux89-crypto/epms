<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%@ include file="../includes/ai_measurements_match_support.jspf" %>
<%!
    private static class AiMeasurementMatchRequest {
        String action;
        String token;
        Integer originalFloatIndex;
        Integer floatIndex;
        Integer floatRegisters;
        String measurementColumn;
        String targetTable;
        boolean supported;
        String note;
    }

    private static String normalizeToken(String value) {
        return normalizeAiMatchToken(trimToNull(value));
    }

    private static String normalizeTargetTable(String value) {
        return normalizeAiMatchTargetTable(trimToNull(value));
    }

    private static String normalizeMeasurementColumn(String value) {
        String trimmed = trimToNull(value);
        return trimmed == null ? null : trimmed;
    }

    private static AiMeasurementMatchRequest buildAiMeasurementMatchRequest(javax.servlet.http.HttpServletRequest request) {
        AiMeasurementMatchRequest req = new AiMeasurementMatchRequest();
        req.action = trimToNull(request.getParameter("action"));
        req.token = normalizeToken(request.getParameter("token"));
        req.originalFloatIndex = parseNullableInt(request.getParameter("original_float_index"));
        req.floatIndex = parseNullableInt(request.getParameter("float_index"));
        req.floatRegisters = parseNullableInt(request.getParameter("float_registers"));
        req.measurementColumn = normalizeMeasurementColumn(request.getParameter("measurement_column"));
        req.targetTable = normalizeTargetTable(request.getParameter("target_table"));
        req.supported = parseBoolSafe(request.getParameter("is_supported"));
        req.note = trimToNull(request.getParameter("note"));
        if (isAiMatchPlcOnlyToken(req.token)) {
            req.measurementColumn = null;
            req.targetTable = null;
        }
        return req;
    }

    private static String validateAiMeasurementMatchRequest(AiMeasurementMatchRequest req) {
        if (req == null || req.action == null) return "요청이 올바르지 않습니다.";
        if ("add".equalsIgnoreCase(req.action) || "update".equalsIgnoreCase(req.action)) {
            if (req.token == null) return "token은 필수입니다.";
            if (!isAiMatchAllowedToken(req.token)) return "엑셀 기준에 없는 token입니다: " + req.token;
            if (req.floatIndex == null || req.floatRegisters == null) return "float_index, float_registers는 숫자 필수입니다.";
            if (req.floatIndex.intValue() <= 0) return "float_index는 1 이상이어야 합니다.";
            if (req.floatRegisters.intValue() <= 0) return "float_registers는 1 이상이어야 합니다.";
            if (req.targetTable != null && !isAiMatchValidTargetTable(req.targetTable)) return "target_table은 measurements 또는 harmonic_measurements만 허용됩니다.";
            if (isAiMatchPlcOnlyToken(req.token) && req.measurementColumn != null) return "IR은 DB 미적재 항목이므로 measurement_column을 지정할 수 없습니다.";
        }
        if ("update".equalsIgnoreCase(req.action) && req.originalFloatIndex == null) {
            return "수정 대상 float_index가 없습니다.";
        }
        if ("delete".equalsIgnoreCase(req.action) && req.originalFloatIndex == null) {
            return "삭제할 float_index가 없습니다.";
        }
        return null;
    }

    private static boolean existsFloatIndex(Connection conn, int floatIndex, Integer excludeFloatIndex) throws SQLException {
        String sql = "SELECT COUNT(1) FROM dbo.plc_ai_measurements_match WHERE float_index = ?" +
            (excludeFloatIndex != null ? " AND float_index <> ?" : "");
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, floatIndex);
            if (excludeFloatIndex != null) ps.setInt(2, excludeFloatIndex.intValue());
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private static String handleAddAiMeasurementMatch(Connection conn, AiMeasurementMatchRequest req) {
        try {
            if (existsFloatIndex(conn, req.floatIndex.intValue(), null)) {
                return "동일한 float_index가 이미 존재합니다: " + req.floatIndex;
            }
        } catch (Exception e) {
            return e.getMessage();
        }
        String sql =
            "INSERT INTO dbo.plc_ai_measurements_match " +
            "(token, float_index, float_registers, measurement_column, target_table, is_supported, note, updated_at) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, SYSDATETIME())";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, req.token);
            ps.setInt(2, req.floatIndex.intValue());
            ps.setInt(3, req.floatRegisters.intValue());
            if (req.measurementColumn == null) ps.setNull(4, Types.NVARCHAR);
            else ps.setString(4, req.measurementColumn);
            if (req.targetTable == null) ps.setNull(5, Types.NVARCHAR);
            else ps.setString(5, req.targetTable);
            ps.setBoolean(6, req.supported);
            if (req.note == null) ps.setNull(7, Types.NVARCHAR);
            else ps.setString(7, req.note);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleUpdateAiMeasurementMatch(Connection conn, AiMeasurementMatchRequest req) {
        try {
            if (existsFloatIndex(conn, req.floatIndex.intValue(), req.originalFloatIndex)) {
                return "동일한 float_index가 이미 존재합니다: " + req.floatIndex;
            }
        } catch (Exception e) {
            return e.getMessage();
        }
        String sql =
            "UPDATE dbo.plc_ai_measurements_match " +
            "SET token = ?, float_index = ?, float_registers = ?, measurement_column = ?, target_table = ?, " +
            "    is_supported = ?, note = ?, updated_at = SYSDATETIME() " +
            "WHERE float_index = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, req.token);
            ps.setInt(2, req.floatIndex.intValue());
            ps.setInt(3, req.floatRegisters.intValue());
            if (req.measurementColumn == null) ps.setNull(4, Types.NVARCHAR);
            else ps.setString(4, req.measurementColumn);
            if (req.targetTable == null) ps.setNull(5, Types.NVARCHAR);
            else ps.setString(5, req.targetTable);
            ps.setBoolean(6, req.supported);
            if (req.note == null) ps.setNull(7, Types.NVARCHAR);
            else ps.setString(7, req.note);
            ps.setInt(8, req.originalFloatIndex.intValue());
            int changed = ps.executeUpdate();
            return changed == 0 ? "수정 대상이 없습니다." : null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleDeleteAiMeasurementMatch(Connection conn, AiMeasurementMatchRequest req) {
        String sql = "DELETE FROM dbo.plc_ai_measurements_match WHERE float_index = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, req.originalFloatIndex.intValue());
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }
%>
<%
    try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String msg = request.getParameter("msg");
    Integer editFloatIndexParam = parseNullableInt(request.getParameter("edit_float_index"));
    String err = null;
    List<Map<String, Object>> rows = new ArrayList<>();
    Map<String, Object> editRow = null;

    try {
        if ("POST".equalsIgnoreCase(request.getMethod())) {
            AiMeasurementMatchRequest formReq = buildAiMeasurementMatchRequest(request);
            err = validateAiMeasurementMatchRequest(formReq);

            if (err == null && "add".equalsIgnoreCase(formReq.action)) {
                err = handleAddAiMeasurementMatch(conn, formReq);
                if (err == null) {
                    response.sendRedirect("ai_measurements_mapping_manage.jsp?msg=" + URLEncoder.encode("등록 완료", "UTF-8"));
                    return;
                }
            } else if (err == null && "update".equalsIgnoreCase(formReq.action)) {
                err = handleUpdateAiMeasurementMatch(conn, formReq);
                if (err == null) {
                    response.sendRedirect("ai_measurements_mapping_manage.jsp?msg=" + URLEncoder.encode("수정 완료", "UTF-8"));
                    return;
                }
            } else if (err == null && "delete".equalsIgnoreCase(formReq.action)) {
                err = handleDeleteAiMeasurementMatch(conn, formReq);
                if (err == null) {
                    response.sendRedirect("ai_measurements_mapping_manage.jsp?msg=" + URLEncoder.encode("삭제 완료", "UTF-8"));
                    return;
                }
            }
        }

        String listSql =
            "SELECT token, float_index, float_registers, measurement_column, target_table, is_supported, note, updated_at " +
            "FROM dbo.plc_ai_measurements_match ORDER BY float_index, token";
        try (PreparedStatement ps = conn.prepareStatement(listSql);
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
                r.put("updated_at", rs.getTimestamp("updated_at"));
                rows.add(r);
                if (editFloatIndexParam != null && editFloatIndexParam.intValue() == ((Number)r.get("float_index")).intValue()) {
                    editRow = r;
                }
            }
        }
    } catch (Exception e) {
        err = e.getMessage();
    }
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>AI Measurement Mapping Management</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1600px; margin: 0 auto; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eefbf1; border: 1px solid #c2efcc; color: #1f7a38; font-size: 13px; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .section-title { margin: 14px 0 6px; font-size: 15px; font-weight: 700; color: #1f3347; }
        .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .small-input { width: 90px; }
        .mid-input { width: 160px; }
        .wide-input { width: 240px; }
        .btn-mini { padding: 5px 8px; font-size: 12px; }
        .btn-action {
            width: 56px;
            height: 34px;
            padding: 0;
            font-size: 13px;
            font-weight: 700;
            text-align: center;
            line-height: 1;
        }
        .action-cell { vertical-align: middle; }
        .action-wrap { display: inline-flex; align-items: center; gap: 6px; }
        .action-wrap form { margin: 0; display: inline-flex; align-items: center; }
        td, th { font-size: 12px; white-space: nowrap; vertical-align: middle; padding-top: 4px; padding-bottom: 4px; }
        .action-cell { padding-top: 2px; padding-bottom: 2px; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🧭 AI 측정값 매핑 정의 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/ai_measurements_verify.jsp'">적재 검증 화면</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %>
    <div class="ok-box"><%= h(msg) %></div>
    <% } %>
    <% if (err != null && !err.trim().isEmpty()) { %>
    <div class="err-box">오류: <%= h(err) %></div>
    <% } %>
    <div class="ok-box">기준: 엑셀 <span class="mono">PLC_IO_Address_AI</span> token만 허용합니다. 편집/삭제 기준은 <span class="mono">float_index</span>입니다. <span class="mono">IR</span>은 PLC 전용이므로 measurement_column / target_table을 비웁니다.</div>

    <div class="section-title">신규 등록</div>
    <form method="post" class="toolbar">
        <input type="hidden" name="action" value="add" />
        <input type="text" name="token" class="mid-input mono" placeholder="TOKEN (예: KW, KWH, KVAR, KVARH, IR)" required />
        <input type="number" name="float_index" class="small-input" placeholder="index" required />
        <input type="number" name="float_registers" class="small-input" placeholder="regs" value="2" required />
        <input type="text" name="measurement_column" class="wide-input mono" placeholder="measurement_column" />
        <input type="text" name="target_table" class="mid-input mono" placeholder="measurements | harmonic_measurements" />
        <label>지원 <input type="checkbox" name="is_supported" value="1" checked /></label>
        <input type="text" name="note" class="wide-input" placeholder="note" />
        <button type="submit" class="btn-mini">등록</button>
    </form>

    <% if (editRow != null) { %>
    <div class="section-title">수정</div>
    <form method="post" class="toolbar">
        <input type="hidden" name="action" value="update" />
        <input type="hidden" name="original_float_index" value="<%= h(editRow.get("float_index")) %>" />
        <input type="text" name="token" class="mid-input mono" value="<%= h(editRow.get("token")) %>" required />
        <input type="number" name="float_index" class="small-input" value="<%= h(editRow.get("float_index")) %>" required />
        <input type="number" name="float_registers" class="small-input" value="<%= h(editRow.get("float_registers")) %>" required />
        <input type="text" name="measurement_column" class="wide-input mono" value="<%= h(editRow.get("measurement_column")) %>" />
        <input type="text" name="target_table" class="mid-input mono" value="<%= h(editRow.get("target_table")) %>" />
        <label>지원 <input type="checkbox" name="is_supported" value="1" <%= ((Boolean)editRow.get("is_supported")) ? "checked" : "" %> /></label>
        <input type="text" name="note" class="wide-input" value="<%= h(editRow.get("note")) %>" />
        <button type="submit" class="btn-mini">수정 저장</button>
        <button type="button" class="btn-mini" onclick="location.href='ai_measurements_mapping_manage.jsp'">취소</button>
    </form>
    <% } %>

    <div class="section-title">목록/수정/삭제</div>
    <table>
        <thead>
        <tr>
            <th>token</th>
            <th>float_index</th>
            <th>float_registers</th>
            <th>measurement_column</th>
            <th>target_table</th>
            <th>is_supported</th>
            <th>note</th>
            <th>동작</th>
        </tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
        <tr><td colspan="8">데이터가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : rows) { %>
            <tr>
                <td class="mono"><%= h(r.get("token")) %></td>
                <td class="mono"><%= h(r.get("float_index")) %></td>
                <td class="mono"><%= h(r.get("float_registers")) %></td>
                <td class="mono"><%= h(r.get("measurement_column")) %></td>
                <td class="mono"><%= h(r.get("target_table")) %></td>
                <td><%= ((Boolean)r.get("is_supported")) ? "1" : "0" %></td>
                <td><%= h(r.get("note")) %></td>
                <td class="action-cell">
                    <div class="action-wrap">
                        <button type="button" class="btn-mini btn-action" onclick="location.href='ai_measurements_mapping_manage.jsp?edit_float_index=<%= h(r.get("float_index")) %>'">편집</button>
                        <form method="post" onsubmit="return confirm('정말 삭제하시겠습니까?');">
                            <input type="hidden" name="action" value="delete" />
                            <input type="hidden" name="original_float_index" value="<%= h(r.get("float_index")) %>" />
                            <button type="submit" class="btn-mini btn-action">삭제</button>
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
</body>
</html>
<%
    } // end try-with-resources
%>
