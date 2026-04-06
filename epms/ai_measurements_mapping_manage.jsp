<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%@ include file="../includes/ai_measurements_match_support.jspf" %>
<%!
    private static boolean tableExists(Connection conn, String tableName) throws SQLException {
        DatabaseMetaData meta = conn.getMetaData();
        try (ResultSet rs = meta.getTables(conn.getCatalog(), null, tableName, new String[]{"TABLE"})) {
            if (rs.next()) return true;
        }
        try (ResultSet rs = meta.getTables(conn.getCatalog(), "dbo", tableName, new String[]{"TABLE"})) {
            return rs.next();
        }
    }

    private static class AiMeasurementMatchRequest {
        String action;
        String token;
        String originalToken;
        Integer originalFloatIndex;
        Integer floatIndex;
        Integer floatRegisters;
        String measurementColumn;
        String targetTable;
        boolean supported;
        String note;
    }

    private static boolean isExcelUnknownToken(String token) {
        return token != null && !isAiMatchAllowedToken(token);
    }

    private static String normalizeToken(String value) {
        return normalizeAiMatchToken(trimToNull(value));
    }

    private static String normalizeTargetTable(String value) {
        String normalized = normalizeAiMatchTargetTable(trimToNull(value));
        return normalized == null ? "measurements" : normalized;
    }

    private static String normalizeMeasurementColumn(String value) {
        String trimmed = trimToNull(value);
        return trimmed == null ? null : trimmed;
    }

    private static AiMeasurementMatchRequest buildAiMeasurementMatchRequest(javax.servlet.http.HttpServletRequest request) {
        AiMeasurementMatchRequest req = new AiMeasurementMatchRequest();
        req.action = trimToNull(request.getParameter("action"));
        req.token = normalizeToken(request.getParameter("token"));
        req.originalToken = normalizeToken(request.getParameter("original_token"));
        req.originalFloatIndex = parseNullableInt(request.getParameter("original_float_index"));
        req.floatIndex = parseNullableInt(request.getParameter("float_index"));
        req.floatRegisters = parseNullableInt(request.getParameter("float_registers"));
        req.measurementColumn = normalizeMeasurementColumn(request.getParameter("measurement_column"));
        req.targetTable = normalizeTargetTable(request.getParameter("target_table"));
        req.supported = parseBoolSafe(request.getParameter("is_supported"));
        req.note = trimToNull(request.getParameter("note"));
        if (isAiMatchPlcOnlyToken(req.token)) {
            req.measurementColumn = null;
            req.targetTable = "measurements";
            req.supported = false;
        }
        return req;
    }

    private static String validateAiMeasurementMatchRequest(AiMeasurementMatchRequest req) {
        if (req == null || req.action == null) return "요청이 올바르지 않습니다.";
        if ("add".equalsIgnoreCase(req.action) || "update".equalsIgnoreCase(req.action)) {
            if (req.token == null) return "token은 필수입니다.";
            if (req.floatIndex == null || req.floatRegisters == null) return "float_index, float_registers는 숫자 필수입니다.";
            if (req.floatIndex.intValue() <= 0) return "float_index는 1 이상이어야 합니다.";
            if (req.floatRegisters.intValue() <= 0) return "float_registers는 1 이상이어야 합니다.";
            if (req.targetTable != null && !isAiMatchValidTargetTable(req.targetTable)) return "target_table은 measurements, harmonic_measurements, flicker_measurements만 허용됩니다.";
            if (isAiMatchPlcOnlyToken(req.token) && req.measurementColumn != null) return "IR은 DB 미적재 항목이므로 measurement_column을 지정할 수 없습니다.";
        }
        if ("update".equalsIgnoreCase(req.action) && req.originalFloatIndex == null) {
            return "수정 대상 float_index가 없습니다.";
        }
        if ("update".equalsIgnoreCase(req.action) && req.originalToken == null) {
            return "수정 대상 token이 없습니다.";
        }
        if ("delete".equalsIgnoreCase(req.action) && req.originalFloatIndex == null) {
            return "삭제할 float_index가 없습니다.";
        }
        if ("delete".equalsIgnoreCase(req.action) && req.originalToken == null) {
            return "삭제할 token이 없습니다.";
        }
        return null;
    }

    private static boolean existsTokenFloatPair(Connection conn, String token, int floatIndex, String excludeToken, Integer excludeFloatIndex) throws SQLException {
        String baseTable = tableExists(conn, "plc_ai_mapping_master")
                ? "dbo.plc_ai_mapping_master"
                : "dbo.plc_ai_measurements_match";
        String sql = "SELECT COUNT(1) FROM " + baseTable + " WHERE token = ? AND float_index = ?" +
            (excludeToken != null && excludeFloatIndex != null ? " AND NOT (token = ? AND float_index = ?)" : "");
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, token);
            ps.setInt(2, floatIndex);
            if (excludeToken != null && excludeFloatIndex != null) {
                ps.setString(3, excludeToken);
                ps.setInt(4, excludeFloatIndex.intValue());
            }
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private static int syncMasterRowsForUpsert(Connection conn, String matchToken, int matchFloatIndex, AiMeasurementMatchRequest req) throws SQLException {
        if (!tableExists(conn, "plc_ai_mapping_master")) return 0;
        String sql =
            "UPDATE dbo.plc_ai_mapping_master " +
            "SET token = ?, measurement_column = ?, target_table = ?, db_insert_yn = ?, note = ?, updated_at = SYSUTCDATETIME() " +
            "WHERE token = ? AND float_index = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, req.token);
            if (req.measurementColumn == null) ps.setNull(2, Types.NVARCHAR);
            else ps.setString(2, req.measurementColumn);
            ps.setString(3, req.targetTable == null ? "measurements" : req.targetTable);
            ps.setBoolean(4, req.supported);
            if (req.note == null) ps.setNull(5, Types.NVARCHAR);
            else ps.setString(5, req.note);
            ps.setString(6, matchToken);
            ps.setInt(7, matchFloatIndex);
            return ps.executeUpdate();
        }
    }

    private static int syncMasterRowsForDelete(Connection conn, String token, int floatIndex) throws SQLException {
        if (!tableExists(conn, "plc_ai_mapping_master")) return 0;
        String sql =
            "UPDATE dbo.plc_ai_mapping_master " +
            "SET measurement_column = NULL, target_table = 'measurements', db_insert_yn = 0, note = ?, updated_at = SYSUTCDATETIME() " +
            "WHERE token = ? AND float_index = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, "MANUAL_DELETE");
            ps.setString(2, token);
            ps.setInt(3, floatIndex);
            return ps.executeUpdate();
        }
    }

    private static String mirrorLegacyRowForAdd(Connection conn, AiMeasurementMatchRequest req) throws SQLException {
        if (!tableExists(conn, "plc_ai_measurements_match")) return null;
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
            ps.setString(5, req.targetTable == null ? "measurements" : req.targetTable);
            ps.setBoolean(6, req.supported);
            if (req.note == null) ps.setNull(7, Types.NVARCHAR);
            else ps.setString(7, req.note);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String mirrorLegacyRowForUpdate(Connection conn, AiMeasurementMatchRequest req) throws SQLException {
        if (!tableExists(conn, "plc_ai_measurements_match")) return null;
        String sql =
            "UPDATE dbo.plc_ai_measurements_match " +
            "SET token = ?, float_index = ?, float_registers = ?, measurement_column = ?, target_table = ?, " +
            "    is_supported = ?, note = ?, updated_at = SYSDATETIME() " +
            "WHERE float_index = ? AND token = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, req.token);
            ps.setInt(2, req.floatIndex.intValue());
            ps.setInt(3, req.floatRegisters.intValue());
            if (req.measurementColumn == null) ps.setNull(4, Types.NVARCHAR);
            else ps.setString(4, req.measurementColumn);
            ps.setString(5, req.targetTable == null ? "measurements" : req.targetTable);
            ps.setBoolean(6, req.supported);
            if (req.note == null) ps.setNull(7, Types.NVARCHAR);
            else ps.setString(7, req.note);
            ps.setInt(8, req.originalFloatIndex.intValue());
            ps.setString(9, req.originalToken);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String mirrorLegacyRowForDelete(Connection conn, AiMeasurementMatchRequest req) throws SQLException {
        if (!tableExists(conn, "plc_ai_measurements_match")) return null;
        String sql = "DELETE FROM dbo.plc_ai_measurements_match WHERE float_index = ? AND token = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, req.originalFloatIndex.intValue());
            ps.setString(2, req.originalToken);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleAddAiMeasurementMatch(Connection conn, AiMeasurementMatchRequest req) {
        try {
            if (existsTokenFloatPair(conn, req.token, req.floatIndex.intValue(), null, null)) {
                return "동일한 token + float_index가 이미 존재합니다: " + req.token + " / " + req.floatIndex;
            }
        } catch (Exception e) {
            return e.getMessage();
        }
        try {
            int masterChanged = syncMasterRowsForUpsert(conn, req.token, req.floatIndex.intValue(), req);
            String legacyErr = mirrorLegacyRowForAdd(conn, req);
            if (legacyErr != null) return legacyErr;
            if (masterChanged == 0 && tableExists(conn, "plc_ai_mapping_master")) {
                return "마스터 기준 row가 없어 legacy 정의만 추가되었습니다. 엑셀 재적용 또는 master 동기화가 필요할 수 있습니다.";
            }
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleUpdateAiMeasurementMatch(Connection conn, AiMeasurementMatchRequest req) {
        try {
            if (existsTokenFloatPair(conn, req.token, req.floatIndex.intValue(), req.originalToken, req.originalFloatIndex)) {
                return "동일한 token + float_index가 이미 존재합니다: " + req.token + " / " + req.floatIndex;
            }
        } catch (Exception e) {
            return e.getMessage();
        }
        try {
            int masterChanged = syncMasterRowsForUpsert(conn, req.originalToken, req.originalFloatIndex.intValue(), req);
            String legacyErr = mirrorLegacyRowForUpdate(conn, req);
            if (legacyErr != null) return legacyErr;
            if (masterChanged == 0 && tableExists(conn, "plc_ai_mapping_master")) {
                return "수정 대상 master row가 없어 legacy 정의만 갱신되었습니다.";
            }
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleDeleteAiMeasurementMatch(Connection conn, AiMeasurementMatchRequest req) {
        try {
            int masterChanged = syncMasterRowsForDelete(conn, req.originalToken, req.originalFloatIndex.intValue());
            String legacyErr = mirrorLegacyRowForDelete(conn, req);
            if (legacyErr != null) return legacyErr;
            if (masterChanged == 0 && tableExists(conn, "plc_ai_mapping_master")) {
                return "삭제 대상 master row가 없어 legacy 정의만 삭제되었습니다.";
            }
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
    String warn = request.getParameter("warn");
    Integer editFloatIndexParam = parseNullableInt(request.getParameter("edit_float_index"));
    String editTokenParam = normalizeToken(request.getParameter("edit_token"));
    String err = null;
    List<Map<String, Object>> rows = new ArrayList<>();
    Map<String, Object> editRow = null;

    try {
        if ("POST".equalsIgnoreCase(request.getMethod())) {
            AiMeasurementMatchRequest formReq = buildAiMeasurementMatchRequest(request);
            err = validateAiMeasurementMatchRequest(formReq);
            String warnMsg = null;

            if (err == null && "add".equalsIgnoreCase(formReq.action)) {
                err = handleAddAiMeasurementMatch(conn, formReq);
                if (err == null) {
                    if (isExcelUnknownToken(formReq.token)) {
                        warnMsg = "엑셀 기준에 없는 token을 저장했습니다: " + formReq.token + " (엑셀 원본에도 반영 필요)";
                    }
                    String redirectUrl = "ai_measurements_mapping_manage.jsp?msg=" + URLEncoder.encode("등록 완료", "UTF-8")
                        + (warnMsg == null ? "" : "&warn=" + URLEncoder.encode(warnMsg, "UTF-8"));
                    response.sendRedirect(redirectUrl);
                    return;
                }
            } else if (err == null && "update".equalsIgnoreCase(formReq.action)) {
                err = handleUpdateAiMeasurementMatch(conn, formReq);
                if (err == null) {
                    if (isExcelUnknownToken(formReq.token)) {
                        warnMsg = "엑셀 기준에 없는 token으로 수정했습니다: " + formReq.token + " (엑셀 원본에도 반영 필요)";
                    }
                    String redirectUrl = "ai_measurements_mapping_manage.jsp?msg=" + URLEncoder.encode("수정 완료", "UTF-8")
                        + (warnMsg == null ? "" : "&warn=" + URLEncoder.encode(warnMsg, "UTF-8"));
                    response.sendRedirect(redirectUrl);
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

        if (tableExists(conn, "plc_ai_mapping_master")) {
            String listSql =
                "SELECT token, float_index, CAST(2 AS INT) AS float_registers, " +
                "       MAX(measurement_column) AS measurement_column, " +
                "       MAX(target_table) AS target_table, " +
                "       MAX(CASE WHEN db_insert_yn = 1 THEN 1 ELSE 0 END) AS is_supported, " +
                "       MAX(note) AS note, " +
                "       MAX(updated_at) AS updated_at " +
                "FROM dbo.plc_ai_mapping_master " +
                "WHERE enabled = 1 " +
                "GROUP BY token, float_index " +
                "ORDER BY float_index, float_registers, token";
            try (PreparedStatement ps = conn.prepareStatement(listSql);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("token", rs.getString("token"));
                    r.put("float_index", rs.getInt("float_index"));
                    r.put("float_registers", rs.getInt("float_registers"));
                    r.put("measurement_column", rs.getString("measurement_column"));
                    r.put("target_table", rs.getString("target_table"));
                    r.put("is_supported", rs.getInt("is_supported") == 1);
                    r.put("note", rs.getString("note"));
                    r.put("updated_at", rs.getTimestamp("updated_at"));
                    r.put("persisted", Boolean.TRUE);
                    rows.add(r);
                    if (editFloatIndexParam != null &&
                        editFloatIndexParam.intValue() == ((Number)r.get("float_index")).intValue() &&
                        (editTokenParam == null || editTokenParam.equals(String.valueOf(r.get("token"))))) {
                        editRow = r;
                    }
                }
            }
        } else {
            String listSql =
                "SELECT token, float_index, float_registers, measurement_column, target_table, is_supported, note, updated_at " +
                "FROM dbo.plc_ai_measurements_match ORDER BY float_index, float_registers, token";
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
                    r.put("persisted", Boolean.TRUE);
                    rows.add(r);
                    if (editFloatIndexParam != null &&
                        editFloatIndexParam.intValue() == ((Number)r.get("float_index")).intValue() &&
                        (editTokenParam == null || editTokenParam.equals(String.valueOf(r.get("token"))))) {
                        editRow = r;
                    }
                }
            }
        }

        boolean hasIrRow = false;
        for (Map<String, Object> r : rows) {
            if ("IR".equals(String.valueOf(r.get("token"))) && Integer.valueOf(21).equals(r.get("float_index"))) {
                hasIrRow = true;
                break;
            }
        }
        if (!hasIrRow) {
            Map<String, Object> irRow = new HashMap<>();
            irRow.put("token", "IR");
            irRow.put("float_index", Integer.valueOf(21));
            irRow.put("float_registers", Integer.valueOf(2));
            irRow.put("measurement_column", null);
            irRow.put("target_table", null);
            irRow.put("is_supported", Boolean.FALSE);
            irRow.put("note", "DB 미적재 PLC 전용");
            irRow.put("updated_at", null);
            irRow.put("persisted", Boolean.FALSE);
            rows.add(irRow);
            if (editFloatIndexParam != null &&
                editFloatIndexParam.intValue() == 21 &&
                "IR".equals(editTokenParam)) {
                editRow = irRow;
            }
            Collections.sort(rows, new Comparator<Map<String, Object>>() {
                @Override
                public int compare(Map<String, Object> a, Map<String, Object> b) {
                    int ai = a.get("float_index") instanceof Number ? ((Number)a.get("float_index")).intValue() : Integer.MAX_VALUE;
                    int bi = b.get("float_index") instanceof Number ? ((Number)b.get("float_index")).intValue() : Integer.MAX_VALUE;
                    if (ai != bi) return Integer.compare(ai, bi);
                    int ar = a.get("float_registers") instanceof Number ? ((Number)a.get("float_registers")).intValue() : Integer.MAX_VALUE;
                    int br = b.get("float_registers") instanceof Number ? ((Number)b.get("float_registers")).intValue() : Integer.MAX_VALUE;
                    if (ar != br) return Integer.compare(ar, br);
                    String at = a.get("token") == null ? "" : String.valueOf(a.get("token"));
                    String bt = b.get("token") == null ? "" : String.valueOf(b.get("token"));
                    return at.compareTo(bt);
                }
            });
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
    <% if (warn != null && !warn.trim().isEmpty()) { %>
    <div class="ok-box" style="background:#fff8e8;border-color:#f5d48f;color:#9a6700;"><%= h(warn) %></div>
    <% } %>
    <% if (err != null && !err.trim().isEmpty()) { %>
    <div class="err-box">오류: <%= h(err) %></div>
    <% } %>
    <div class="ok-box">기준: 엑셀 <span class="mono">PLC_IO_Address_AI</span> token과 운영 중인 추가 token을 함께 허용합니다. 편집/삭제 기준은 <span class="mono">token + float_index</span>입니다. <span class="mono">IR</span>은 PLC 전용이므로 measurement_column / target_table을 비웁니다.</div>

    <div class="section-title">신규 등록</div>
    <form method="post" class="toolbar">
        <input type="hidden" name="action" value="add" />
        <input type="number" name="float_index" class="small-input" placeholder="index" required />
        <input type="number" name="float_registers" class="small-input" placeholder="regs" value="2" required />
        <input type="text" name="token" class="mid-input mono" placeholder="TOKEN (예: KW, KWH, VA, VAH, IR)" required />
        <input type="text" name="measurement_column" class="wide-input mono" placeholder="measurement_column" />
        <input type="text" name="target_table" class="mid-input mono" placeholder="measurements | harmonic_measurements" />
        <label>DB 적재 <input type="checkbox" name="is_supported" value="1" checked /></label>
        <input type="text" name="note" class="wide-input" placeholder="note" />
        <button type="submit" class="btn-mini">등록</button>
    </form>

    <% if (editRow != null) { %>
    <div class="section-title">수정</div>
    <form method="post" class="toolbar">
        <input type="hidden" name="action" value="<%= Boolean.TRUE.equals(editRow.get("persisted")) ? "update" : "add" %>" />
        <% if (Boolean.TRUE.equals(editRow.get("persisted"))) { %>
        <input type="hidden" name="original_token" value="<%= h(editRow.get("token")) %>" />
        <input type="hidden" name="original_float_index" value="<%= h(editRow.get("float_index")) %>" />
        <% } %>
        <input type="number" name="float_index" class="small-input" value="<%= h(editRow.get("float_index")) %>" required />
        <input type="number" name="float_registers" class="small-input" value="<%= h(editRow.get("float_registers")) %>" required />
        <input type="text" name="token" class="mid-input mono" value="<%= h(editRow.get("token")) %>" required />
        <input type="text" name="measurement_column" class="wide-input mono" value="<%= h(editRow.get("measurement_column")) %>" />
        <input type="text" name="target_table" class="mid-input mono" value="<%= h(editRow.get("target_table")) %>" />
        <label>DB 적재 <input type="checkbox" name="is_supported" value="1" <%= ((Boolean)editRow.get("is_supported")) ? "checked" : "" %> /></label>
        <input type="text" name="note" class="wide-input" value="<%= h(editRow.get("note")) %>" />
        <button type="submit" class="btn-mini">수정 저장</button>
        <button type="button" class="btn-mini" onclick="location.href='ai_measurements_mapping_manage.jsp'">취소</button>
    </form>
    <% } %>

    <div class="section-title">목록/수정/삭제</div>
    <table>
        <thead>
        <tr>
            <th>float_index</th>
            <th>float_registers</th>
            <th>token</th>
            <th>measurement_column</th>
            <th>target_table</th>
            <th>DB insert 여부</th>
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
                <td class="mono"><%= h(r.get("float_index")) %></td>
                <td class="mono"><%= h(r.get("float_registers")) %></td>
                <td class="mono"><%= h(r.get("token")) %></td>
                <td class="mono"><%= h(r.get("measurement_column")) %></td>
                <td class="mono"><%= h(r.get("target_table")) %></td>
                <td><%= ((Boolean)r.get("is_supported")) ? "1" : "0" %></td>
                <td><%= h(r.get("note")) %></td>
                <td class="action-cell">
                    <div class="action-wrap">
                        <button type="button" class="btn-mini btn-action" onclick="location.href='ai_measurements_mapping_manage.jsp?edit_float_index=<%= h(r.get("float_index")) %>&edit_token=<%= h(r.get("token")) %>'">편집</button>
                        <form method="post" onsubmit="return confirm('정말 삭제하시겠습니까?');">
                            <input type="hidden" name="action" value="delete" />
                            <input type="hidden" name="original_token" value="<%= h(r.get("token")) %>" />
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
