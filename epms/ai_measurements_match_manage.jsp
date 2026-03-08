<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
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

    private static Integer toInt(String v) {
        if (v == null) return null;
        String t = v.trim();
        if (t.isEmpty()) return null;
        try { return Integer.valueOf(Integer.parseInt(t)); } catch (Exception e) { return null; }
    }

    private static boolean toBool(String v) {
        if (v == null) return false;
        String t = v.trim().toLowerCase(java.util.Locale.ROOT);
        return "1".equals(t) || "true".equals(t) || "y".equals(t) || "yes".equals(t) || "on".equals(t);
    }
%>
<%
    request.setCharacterEncoding("UTF-8");

    String msg = request.getParameter("msg");
    String editTokenParam = request.getParameter("edit_token");
    String err = null;
    List<Map<String, Object>> rows = new ArrayList<>();
    Map<String, Object> editRow = null;

    try {
        if ("POST".equalsIgnoreCase(request.getMethod())) {
            String action = request.getParameter("action");
            if (action == null) action = "";

            if ("add".equalsIgnoreCase(action)) {
                String token = request.getParameter("token");
                Integer floatIndex = toInt(request.getParameter("float_index"));
                Integer floatRegisters = toInt(request.getParameter("float_registers"));
                String measurementColumn = request.getParameter("measurement_column");
                String targetTable = request.getParameter("target_table");
                boolean isSupported = toBool(request.getParameter("is_supported"));
                String note = request.getParameter("note");

                if (token == null || token.trim().isEmpty()) {
                    err = "token은 필수입니다.";
                } else if (floatIndex == null || floatRegisters == null) {
                    err = "float_index, float_registers는 숫자 필수입니다.";
                } else {
                    String sql =
                        "INSERT INTO dbo.plc_ai_measurements_match " +
                        "(token, float_index, float_registers, measurement_column, target_table, is_supported, note, updated_at) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?, SYSDATETIME())";
                    try (PreparedStatement ps = conn.prepareStatement(sql)) {
                        ps.setString(1, token.trim().toUpperCase(java.util.Locale.ROOT));
                        ps.setInt(2, floatIndex.intValue());
                        ps.setInt(3, floatRegisters.intValue());
                        if (measurementColumn == null || measurementColumn.trim().isEmpty()) ps.setNull(4, Types.NVARCHAR);
                        else ps.setString(4, measurementColumn.trim());
                        if (targetTable == null || targetTable.trim().isEmpty()) ps.setNull(5, Types.NVARCHAR);
                        else ps.setString(5, targetTable.trim().toLowerCase(java.util.Locale.ROOT));
                        ps.setBoolean(6, isSupported);
                        if (note == null || note.trim().isEmpty()) ps.setNull(7, Types.NVARCHAR);
                        else ps.setString(7, note.trim());
                        ps.executeUpdate();
                    }
                    response.sendRedirect("ai_measurements_match_manage.jsp?msg=" + URLEncoder.encode("등록 완료", "UTF-8"));
                    return;
                }
            } else if ("update".equalsIgnoreCase(action)) {
                String originalToken = request.getParameter("original_token");
                String token = request.getParameter("token");
                Integer floatIndex = toInt(request.getParameter("float_index"));
                Integer floatRegisters = toInt(request.getParameter("float_registers"));
                String measurementColumn = request.getParameter("measurement_column");
                String targetTable = request.getParameter("target_table");
                boolean isSupported = toBool(request.getParameter("is_supported"));
                String note = request.getParameter("note");

                if (originalToken == null || originalToken.trim().isEmpty()) {
                    err = "수정 대상 token이 없습니다.";
                } else if (token == null || token.trim().isEmpty()) {
                    err = "token은 필수입니다.";
                } else if (floatIndex == null || floatRegisters == null) {
                    err = "float_index, float_registers는 숫자 필수입니다.";
                } else {
                    String sql =
                        "UPDATE dbo.plc_ai_measurements_match " +
                        "SET token = ?, float_index = ?, float_registers = ?, measurement_column = ?, target_table = ?, " +
                        "    is_supported = ?, note = ?, updated_at = SYSDATETIME() " +
                        "WHERE token = ?";
                    try (PreparedStatement ps = conn.prepareStatement(sql)) {
                        ps.setString(1, token.trim().toUpperCase(java.util.Locale.ROOT));
                        ps.setInt(2, floatIndex.intValue());
                        ps.setInt(3, floatRegisters.intValue());
                        if (measurementColumn == null || measurementColumn.trim().isEmpty()) ps.setNull(4, Types.NVARCHAR);
                        else ps.setString(4, measurementColumn.trim());
                        if (targetTable == null || targetTable.trim().isEmpty()) ps.setNull(5, Types.NVARCHAR);
                        else ps.setString(5, targetTable.trim().toLowerCase(java.util.Locale.ROOT));
                        ps.setBoolean(6, isSupported);
                        if (note == null || note.trim().isEmpty()) ps.setNull(7, Types.NVARCHAR);
                        else ps.setString(7, note.trim());
                        ps.setString(8, originalToken.trim().toUpperCase(java.util.Locale.ROOT));
                        int changed = ps.executeUpdate();
                        if (changed == 0) err = "수정 대상이 없습니다.";
                    }
                    if (err == null) {
                        response.sendRedirect("ai_measurements_match_manage.jsp?msg=" + URLEncoder.encode("수정 완료", "UTF-8"));
                        return;
                    }
                }
            } else if ("delete".equalsIgnoreCase(action)) {
                String token = request.getParameter("token");
                if (token == null || token.trim().isEmpty()) {
                    err = "삭제할 token이 없습니다.";
                } else {
                    String sql = "DELETE FROM dbo.plc_ai_measurements_match WHERE token = ?";
                    try (PreparedStatement ps = conn.prepareStatement(sql)) {
                        ps.setString(1, token.trim().toUpperCase(java.util.Locale.ROOT));
                        ps.executeUpdate();
                    }
                    response.sendRedirect("ai_measurements_match_manage.jsp?msg=" + URLEncoder.encode("삭제 완료", "UTF-8"));
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
                if (editTokenParam != null && editTokenParam.trim().equalsIgnoreCase(String.valueOf(r.get("token")))) {
                    editRow = r;
                }
            }
        }
    } catch (Exception e) {
        err = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>AI-Measurements 매칭 관리</title>
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
        <h2>AI-Measurements 매칭 관리</h2>
        <div style="display:flex; gap:8px;">
            <button class="back-btn" onclick="location.href='/epms/ai_measurements_match.jsp'">매칭 검증 화면</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %>
    <div class="ok-box"><%= h(msg) %></div>
    <% } %>
    <% if (err != null && !err.trim().isEmpty()) { %>
    <div class="err-box">오류: <%= h(err) %></div>
    <% } %>

    <div class="section-title">신규 등록</div>
    <form method="post" class="toolbar">
        <input type="hidden" name="action" value="add" />
        <input type="text" name="token" class="mid-input mono" placeholder="TOKEN (예: KW)" required />
        <input type="number" name="float_index" class="small-input" placeholder="index" required />
        <input type="number" name="float_registers" class="small-input" placeholder="regs" value="2" required />
        <input type="text" name="measurement_column" class="wide-input mono" placeholder="measurement_column" />
        <input type="text" name="target_table" class="mid-input mono" placeholder="target_table" />
        <label>지원 <input type="checkbox" name="is_supported" value="1" checked /></label>
        <input type="text" name="note" class="wide-input" placeholder="note" />
        <button type="submit" class="btn-mini">등록</button>
    </form>

    <% if (editRow != null) { %>
    <div class="section-title">수정</div>
    <form method="post" class="toolbar">
        <input type="hidden" name="action" value="update" />
        <input type="hidden" name="original_token" value="<%= h(editRow.get("token")) %>" />
        <input type="text" name="token" class="mid-input mono" value="<%= h(editRow.get("token")) %>" required />
        <input type="number" name="float_index" class="small-input" value="<%= h(editRow.get("float_index")) %>" required />
        <input type="number" name="float_registers" class="small-input" value="<%= h(editRow.get("float_registers")) %>" required />
        <input type="text" name="measurement_column" class="wide-input mono" value="<%= h(editRow.get("measurement_column")) %>" />
        <input type="text" name="target_table" class="mid-input mono" value="<%= h(editRow.get("target_table")) %>" />
        <label>지원 <input type="checkbox" name="is_supported" value="1" <%= ((Boolean)editRow.get("is_supported")) ? "checked" : "" %> /></label>
        <input type="text" name="note" class="wide-input" value="<%= h(editRow.get("note")) %>" />
        <button type="submit" class="btn-mini">수정 저장</button>
        <button type="button" class="btn-mini" onclick="location.href='ai_measurements_match_manage.jsp'">취소</button>
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
                        <button type="button" class="btn-mini btn-action" onclick="location.href='ai_measurements_match_manage.jsp?edit_token=<%= h(r.get("token")) %>'">편집</button>
                        <form method="post" onsubmit="return confirm('정말 삭제하시겠습니까?');">
                            <input type="hidden" name="action" value="delete" />
                            <input type="hidden" name="token" value="<%= h(r.get("token")) %>" />
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
