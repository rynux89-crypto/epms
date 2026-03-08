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
%>
<%
    request.setCharacterEncoding("UTF-8");
    String self = request.getRequestURI();
    String msg = request.getParameter("msg");
    String err = request.getParameter("err");
    List<Map<String, Object>> rows = new ArrayList<>();
    try {
        String ensureSql =
            "IF OBJECT_ID('dbo.metric_catalog','U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.metric_catalog ( " +
            "    metric_key VARCHAR(100) NOT NULL PRIMARY KEY, " +
            "    display_name NVARCHAR(150) NULL, " +
            "    source_type VARCHAR(20) NOT NULL DEFAULT 'AI', " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "END";
        try (Statement st = conn.createStatement()) {
            st.execute(ensureSql);
        }

        if ("POST".equalsIgnoreCase(request.getMethod())) {
            String action = request.getParameter("action");
            if ("add".equals(action)) {
                String key = request.getParameter("metric_key");
                String name = request.getParameter("display_name");
                String sourceType = request.getParameter("source_type");
                if (key == null || key.trim().isEmpty()) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode("metric_key를 입력하세요.", "UTF-8"));
                    return;
                }
                String insSql =
                    "MERGE dbo.metric_catalog t " +
                    "USING (SELECT ? AS metric_key) s ON (t.metric_key = s.metric_key) " +
                    "WHEN MATCHED THEN UPDATE SET display_name=?, source_type=?, enabled=1, updated_at=SYSUTCDATETIME() " +
                    "WHEN NOT MATCHED THEN INSERT (metric_key, display_name, source_type, enabled, created_at, updated_at) VALUES (?, ?, ?, 1, SYSUTCDATETIME(), SYSUTCDATETIME());";
                try (PreparedStatement ps = conn.prepareStatement(insSql)) {
                    String mk = key.trim().toUpperCase(Locale.ROOT);
                    String st = (sourceType == null || sourceType.trim().isEmpty()) ? "AI" : sourceType.trim().toUpperCase(Locale.ROOT);
                    ps.setString(1, mk);
                    ps.setString(2, name);
                    ps.setString(3, st);
                    ps.setString(4, mk);
                    ps.setString(5, name);
                    ps.setString(6, st);
                    ps.executeUpdate();
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("지표키를 저장했습니다.", "UTF-8"));
                return;
            }

            if ("update".equals(action)) {
                String key = request.getParameter("metric_key");
                String name = request.getParameter("display_name");
                String sourceType = request.getParameter("source_type");
                if (key == null || key.trim().isEmpty()) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode("metric_key가 없습니다.", "UTF-8"));
                    return;
                }
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE dbo.metric_catalog SET display_name=?, source_type=?, updated_at=SYSUTCDATETIME() WHERE metric_key=?")) {
                    String st = (sourceType == null || sourceType.trim().isEmpty()) ? "AI" : sourceType.trim().toUpperCase(Locale.ROOT);
                    ps.setString(1, name);
                    ps.setString(2, st);
                    ps.setString(3, key.trim().toUpperCase(Locale.ROOT));
                    ps.executeUpdate();
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("지표키를 수정했습니다.", "UTF-8"));
                return;
            }

            if ("rename".equals(action)) {
                String oldKey = request.getParameter("metric_key");
                String newKey = request.getParameter("new_metric_key");
                if (oldKey == null || oldKey.trim().isEmpty() || newKey == null || newKey.trim().isEmpty()) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode("기존/신규 metric_key를 모두 입력하세요.", "UTF-8"));
                    return;
                }
                oldKey = oldKey.trim().toUpperCase(Locale.ROOT);
                newKey = newKey.trim().toUpperCase(Locale.ROOT);
                if (oldKey.equals(newKey)) {
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("동일한 키입니다. 변경 사항이 없습니다.", "UTF-8"));
                    return;
                }

                // FK dependency check on metric_catalog table itself.
                int fkCnt = 0;
                try (PreparedStatement ps = conn.prepareStatement(
                        "SELECT COUNT(1) FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID('dbo.metric_catalog')");
                     ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) fkCnt = rs.getInt(1);
                }
                if (fkCnt > 0) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode("metric_catalog를 참조하는 FK가 있어 rename을 차단했습니다. FK 영향 검토 후 진행하세요.", "UTF-8"));
                    return;
                }

                // Duplicate check.
                int dupCnt = 0;
                try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM dbo.metric_catalog WHERE metric_key = ?")) {
                    ps.setString(1, newKey);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) dupCnt = rs.getInt(1);
                    }
                }
                if (dupCnt > 0) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode("이미 존재하는 metric_key 입니다: " + newKey, "UTF-8"));
                    return;
                }

                boolean oldAutoCommit = conn.getAutoCommit();
                try {
                    conn.setAutoCommit(false);

                    int existsOld = 0;
                    try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM dbo.metric_catalog WHERE metric_key = ?")) {
                        ps.setString(1, oldKey);
                        try (ResultSet rs = ps.executeQuery()) {
                            if (rs.next()) existsOld = rs.getInt(1);
                        }
                    }
                    if (existsOld == 0) throw new SQLException("기존 metric_key가 존재하지 않습니다: " + oldKey);

                    try (PreparedStatement ps = conn.prepareStatement(
                            "UPDATE dbo.metric_catalog SET metric_key = ?, updated_at = SYSUTCDATETIME() WHERE metric_key = ?")) {
                        ps.setString(1, newKey);
                        ps.setString(2, oldKey);
                        ps.executeUpdate();
                    }

                    // Propagate to alarm_rule.
                    try (PreparedStatement ps = conn.prepareStatement(
                            "UPDATE dbo.alarm_rule SET metric_key = ?, updated_at = SYSUTCDATETIME() WHERE metric_key = ?")) {
                        ps.setString(1, newKey);
                        ps.setString(2, oldKey);
                        ps.executeUpdate();
                    }

                    // Propagate to alarm_log metadata when optional columns exist.
                    try (PreparedStatement ps = conn.prepareStatement("UPDATE dbo.alarm_log SET metric_key = ? WHERE metric_key = ?")) {
                        ps.setString(1, newKey);
                        ps.setString(2, oldKey);
                        ps.executeUpdate();
                    } catch (Exception ignore) {}
                    try (PreparedStatement ps = conn.prepareStatement("UPDATE dbo.alarm_log SET source_token = ? WHERE source_token = ?")) {
                        ps.setString(1, newKey);
                        ps.setString(2, oldKey);
                        ps.executeUpdate();
                    } catch (Exception ignore) {}

                    conn.commit();
                } catch (Exception ex) {
                    try { conn.rollback(); } catch (Exception ignore) {}
                    throw ex;
                } finally {
                    try { conn.setAutoCommit(oldAutoCommit); } catch (Exception ignore) {}
                }

                response.sendRedirect(self + "?msg=" + URLEncoder.encode("metric_key를 변경했습니다: " + oldKey + " -> " + newKey, "UTF-8"));
                return;
            }

            if ("toggle".equals(action)) {
                String key = request.getParameter("metric_key");
                if (key != null && !key.trim().isEmpty()) {
                    try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE dbo.metric_catalog SET enabled = CASE WHEN enabled=1 THEN 0 ELSE 1 END, updated_at=SYSUTCDATETIME() WHERE metric_key=?")) {
                        ps.setString(1, key.trim().toUpperCase(Locale.ROOT));
                        ps.executeUpdate();
                    }
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("상태를 변경했습니다.", "UTF-8"));
                return;
            }

            if ("delete".equals(action)) {
                String key = request.getParameter("metric_key");
                if (key != null && !key.trim().isEmpty()) {
                    try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.metric_catalog WHERE metric_key=?")) {
                        ps.setString(1, key.trim().toUpperCase(Locale.ROOT));
                        ps.executeUpdate();
                    }
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("지표키를 삭제했습니다.", "UTF-8"));
                return;
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT metric_key, display_name, source_type, enabled, updated_at FROM dbo.metric_catalog ORDER BY metric_key");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("metric_key", rs.getString("metric_key"));
                r.put("display_name", rs.getString("display_name"));
                r.put("source_type", rs.getString("source_type"));
                r.put("enabled", rs.getBoolean("enabled"));
                r.put("updated_at", rs.getTimestamp("updated_at"));
                rows.add(r);
            }
        }
    } catch (Exception e) {
        err = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%>
<html>
<head>
    <title>Metric Catalog Manage</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1200px; margin: 0 auto; }
        .ok-box { margin: 10px 0; padding: 10px; border: 1px solid #b7ebc6; background: #ebfff1; color: #0f7a2a; border-radius: 8px; }
        .err-box { margin: 10px 0; padding: 10px; border: 1px solid #ffc9c9; background: #fff1f1; color: #b42318; border-radius: 8px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .toolbar { display: grid; grid-template-columns: 1fr 1fr 160px auto; gap: 6px; margin-top: 10px; align-items: end; }
        .badge { display:inline-block; padding: 2px 8px; border-radius:999px; font-size: 11px; font-weight:700; }
        .on { background:#e8f7ec; border:1px solid #b9e6c6; color:#1b7f3b; }
        .off { background:#fff3e0; border:1px solid #ffd8a8; color:#b45309; }
        .row-form { display:inline; margin:0; padding:0; box-shadow:none; background:transparent; }
        .action-wrap { display:flex; flex-wrap:wrap; gap:6px; align-items:center; }
        .edit-input { width:160px; }
        .edit-select { width:110px; }
        .rename-input { width:120px; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>지표키 카탈로그 관리</h2>
        <div style="display:flex; gap:8px;">
            <button class="back-btn" onclick="location.href='/epms/alarm_rule.jsp'">알람 규칙 등록</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="ok-box"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form method="POST">
        <input type="hidden" name="action" value="add">
        <div class="toolbar">
            <input name="metric_key" class="mono" placeholder="metric_key (예: POWER_FACTOR)" required>
            <input name="display_name" placeholder="표시명 (예: 역률)">
            <select name="source_type" class="mono">
                <option value="AI">AI</option>
                <option value="METER">METER</option>
                <option value="DI">DI</option>
                <option value="SYSTEM">SYSTEM</option>
            </select>
            <button type="submit">저장</button>
        </div>
    </form>

    <table style="margin-top:12px;">
        <thead>
            <tr><th>metric_key</th><th>display_name</th><th>source_type</th><th>enabled</th><th>updated_at</th><th>작업</th></tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
            <tr><td colspan="6">등록된 지표키가 없습니다.</td></tr>
        <% } else { for (Map<String, Object> r : rows) { %>
            <tr>
                <td class="mono"><%= h(r.get("metric_key")) %></td>
                <td><%= h(r.get("display_name")) %></td>
                <td class="mono"><%= h(r.get("source_type")) %></td>
                <td><% if ((Boolean)r.get("enabled")) { %><span class="badge on">ON</span><% } else { %><span class="badge off">OFF</span><% } %></td>
                <td class="mono"><%= h(r.get("updated_at")) %></td>
                <td>
                    <div class="action-wrap">
                    <form method="POST" class="row-form action-wrap">
                        <input type="hidden" name="action" value="update">
                        <input type="hidden" name="metric_key" value="<%= h(r.get("metric_key")) %>">
                        <input name="display_name" value="<%= h(r.get("display_name")) %>" placeholder="표시명" class="edit-input">
                        <select name="source_type" class="mono edit-select">
                            <option value="AI" <%= "AI".equalsIgnoreCase(String.valueOf(r.get("source_type"))) ? "selected" : "" %>>AI</option>
                            <option value="METER" <%= "METER".equalsIgnoreCase(String.valueOf(r.get("source_type"))) ? "selected" : "" %>>METER</option>
                            <option value="DI" <%= "DI".equalsIgnoreCase(String.valueOf(r.get("source_type"))) ? "selected" : "" %>>DI</option>
                            <option value="SYSTEM" <%= "SYSTEM".equalsIgnoreCase(String.valueOf(r.get("source_type"))) ? "selected" : "" %>>SYSTEM</option>
                        </select>
                        <button type="submit">수정</button>
                    </form>
                    <form method="POST" class="row-form action-wrap">
                        <input type="hidden" name="action" value="rename">
                        <input type="hidden" name="metric_key" value="<%= h(r.get("metric_key")) %>">
                        <input name="new_metric_key" class="mono rename-input" placeholder="새 key">
                        <button type="submit" onclick="return confirm('metric_key를 변경하면 연관 규칙의 metric_key도 함께 변경됩니다. 계속하시겠습니까?');">rename</button>
                    </form>
                    <form method="POST" class="row-form action-wrap">
                        <input type="hidden" name="action" value="toggle">
                        <input type="hidden" name="metric_key" value="<%= h(r.get("metric_key")) %>">
                        <button type="submit">ON/OFF</button>
                    </form>
                    <form method="POST" class="row-form action-wrap" onsubmit="return confirm('삭제하시겠습니까?');">
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="metric_key" value="<%= h(r.get("metric_key")) %>">
                        <button type="submit">삭제</button>
                    </form>
                    </div>
                </td>
            </tr>
        <% }} %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
