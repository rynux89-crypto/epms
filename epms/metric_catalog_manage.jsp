<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static class MetricCatalogRequest {
        String action;
        String metricKey;
        String displayName;
        String sourceType;
        String newMetricKey;
    }

    private static String trimToNull(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String normalizeMetricKey(String value) {
        String trimmed = trimToNull(value);
        return trimmed == null ? null : trimmed.toUpperCase(Locale.ROOT);
    }

    private static String normalizeSourceType(String value) {
        String trimmed = trimToNull(value);
        return trimmed == null ? "AI" : trimmed.toUpperCase(Locale.ROOT);
    }

    private static MetricCatalogRequest buildMetricCatalogRequest(javax.servlet.http.HttpServletRequest request) {
        MetricCatalogRequest req = new MetricCatalogRequest();
        req.action = trimToNull(request.getParameter("action"));
        req.metricKey = normalizeMetricKey(request.getParameter("metric_key"));
        req.displayName = request.getParameter("display_name");
        req.sourceType = normalizeSourceType(request.getParameter("source_type"));
        req.newMetricKey = normalizeMetricKey(request.getParameter("new_metric_key"));
        return req;
    }

    private static String validateMetricCatalogRequest(MetricCatalogRequest req) {
        if (req == null || req.action == null) return "요청이 올바르지 않습니다.";
        if ("add".equals(req.action) || "update".equals(req.action) || "toggle".equals(req.action) || "delete".equals(req.action)) {
            if (req.metricKey == null) {
                return "add".equals(req.action) ? "metric_key를 입력하세요." : "metric_key가 없습니다.";
            }
        }
        if ("rename".equals(req.action)) {
            if (req.metricKey == null || req.newMetricKey == null) {
                return "기존/신규 metric_key를 모두 입력하세요.";
            }
        }
        return null;
    }

    private static String handleAddMetricCatalog(Connection conn, MetricCatalogRequest req) {
        String insSql =
            "MERGE dbo.metric_catalog t " +
            "USING (SELECT ? AS metric_key) s ON (t.metric_key = s.metric_key) " +
            "WHEN MATCHED THEN UPDATE SET display_name=?, source_type=?, enabled=1, updated_at=SYSUTCDATETIME() " +
            "WHEN NOT MATCHED THEN INSERT (metric_key, display_name, source_type, enabled, created_at, updated_at) VALUES (?, ?, ?, 1, SYSUTCDATETIME(), SYSUTCDATETIME());";
        try (PreparedStatement ps = conn.prepareStatement(insSql)) {
            ps.setString(1, req.metricKey);
            ps.setString(2, req.displayName);
            ps.setString(3, req.sourceType);
            ps.setString(4, req.metricKey);
            ps.setString(5, req.displayName);
            ps.setString(6, req.sourceType);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleUpdateMetricCatalog(Connection conn, MetricCatalogRequest req) {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.metric_catalog SET display_name=?, source_type=?, updated_at=SYSUTCDATETIME() WHERE metric_key=?")) {
            ps.setString(1, req.displayName);
            ps.setString(2, req.sourceType);
            ps.setString(3, req.metricKey);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleRenameMetricCatalog(Connection conn, MetricCatalogRequest req) {
        if (req.metricKey.equals(req.newMetricKey)) return "__NO_CHANGE__";

        int fkCnt = 0;
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(1) FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID('dbo.metric_catalog')");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) fkCnt = rs.getInt(1);
        } catch (Exception e) {
            return e.getMessage();
        }
        if (fkCnt > 0) {
            return "metric_catalog를 참조하는 FK가 있어 rename을 차단했습니다. FK 영향 검토 후 진행하세요.";
        }

        int dupCnt = 0;
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM dbo.metric_catalog WHERE metric_key = ?")) {
            ps.setString(1, req.newMetricKey);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) dupCnt = rs.getInt(1);
            }
        } catch (Exception e) {
            return e.getMessage();
        }
        if (dupCnt > 0) {
            return "이미 존재하는 metric_key 입니다: " + req.newMetricKey;
        }

        boolean oldAutoCommit = true;
        try {
            oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);

            int existsOld = 0;
            try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM dbo.metric_catalog WHERE metric_key = ?")) {
                ps.setString(1, req.metricKey);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) existsOld = rs.getInt(1);
                }
            }
            if (existsOld == 0) throw new SQLException("기존 metric_key가 존재하지 않습니다: " + req.metricKey);

            try (PreparedStatement ps = conn.prepareStatement(
                    "UPDATE dbo.metric_catalog SET metric_key = ?, updated_at = SYSUTCDATETIME() WHERE metric_key = ?")) {
                ps.setString(1, req.newMetricKey);
                ps.setString(2, req.metricKey);
                ps.executeUpdate();
            }

            try (PreparedStatement ps = conn.prepareStatement(
                    "UPDATE dbo.alarm_rule SET metric_key = ?, updated_at = SYSUTCDATETIME() WHERE metric_key = ?")) {
                ps.setString(1, req.newMetricKey);
                ps.setString(2, req.metricKey);
                ps.executeUpdate();
            }

            try (PreparedStatement ps = conn.prepareStatement("UPDATE dbo.alarm_log SET metric_key = ? WHERE metric_key = ?")) {
                ps.setString(1, req.newMetricKey);
                ps.setString(2, req.metricKey);
                ps.executeUpdate();
            } catch (Exception ignore) {}
            try (PreparedStatement ps = conn.prepareStatement("UPDATE dbo.alarm_log SET source_token = ? WHERE source_token = ?")) {
                ps.setString(1, req.newMetricKey);
                ps.setString(2, req.metricKey);
                ps.executeUpdate();
            } catch (Exception ignore) {}

            conn.commit();
            return null;
        } catch (Exception ex) {
            try { conn.rollback(); } catch (Exception ignore) {}
            return ex.getMessage();
        } finally {
            try { conn.setAutoCommit(oldAutoCommit); } catch (Exception ignore) {}
        }
    }

    private static String handleToggleMetricCatalog(Connection conn, MetricCatalogRequest req) {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.metric_catalog SET enabled = CASE WHEN enabled=1 THEN 0 ELSE 1 END, updated_at=SYSUTCDATETIME() WHERE metric_key=?")) {
            ps.setString(1, req.metricKey);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleDeleteMetricCatalog(Connection conn, MetricCatalogRequest req) {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.metric_catalog WHERE metric_key=?")) {
            ps.setString(1, req.metricKey);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
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
            MetricCatalogRequest formReq = buildMetricCatalogRequest(request);
            String formErr = validateMetricCatalogRequest(formReq);
            if (formErr != null) {
                response.sendRedirect(self + "?err=" + URLEncoder.encode(formErr, "UTF-8"));
                return;
            }

            if ("add".equals(formReq.action)) {
                String saveErr = handleAddMetricCatalog(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("지표키를 저장했습니다.", "UTF-8"));
                return;
            }

            if ("update".equals(formReq.action)) {
                String saveErr = handleUpdateMetricCatalog(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("지표키를 수정했습니다.", "UTF-8"));
                return;
            }

            if ("rename".equals(formReq.action)) {
                String saveErr = handleRenameMetricCatalog(conn, formReq);
                if ("__NO_CHANGE__".equals(saveErr)) {
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("동일한 키입니다. 변경 사항이 없습니다.", "UTF-8"));
                    return;
                }
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("metric_key를 변경했습니다: " + formReq.metricKey + " -> " + formReq.newMetricKey, "UTF-8"));
                return;
            }

            if ("toggle".equals(formReq.action)) {
                String saveErr = handleToggleMetricCatalog(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("상태를 변경했습니다.", "UTF-8"));
                return;
            }

            if ("delete".equals(formReq.action)) {
                String saveErr = handleDeleteMetricCatalog(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
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
