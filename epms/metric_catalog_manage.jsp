<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static class MetricCatalogRequest {
        String action;
        String originalMetricKey;
        String metricKey;
        String displayName;
        String sourceType;
        String newMetricKey;
        String tagTokens;
    }

    private static String buildTagTokenRequest(javax.servlet.http.HttpServletRequest request, String paramName) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        if (request != null && paramName != null) {
            String[] values = request.getParameterValues(paramName);
            if (values != null) {
                for (String value : values) {
                    String token = trimToNull(value);
                    if (token != null) out.add(token.toUpperCase(Locale.ROOT));
                }
            }
            if (out.isEmpty()) {
                String raw = request.getParameter(paramName);
                List<String> parsed = parseTagTokens(raw);
                out.addAll(parsed);
            }
        }
        return out.isEmpty() ? null : String.join(",", out);
    }

    private static List<String> parseTagTokens(String raw) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        if (raw == null) return new ArrayList<>(out);
        String normalized = raw.replace('\n', ',').replace('\r', ',').replace(';', ',');
        String[] parts = normalized.split(",");
        for (String p : parts) {
            String token = trimToNull(p);
            if (token == null) continue;
            out.add(token.toUpperCase(Locale.ROOT));
        }
        return new ArrayList<>(out);
    }

    private static Map<String, List<String>> loadMetricTagMappings(Connection conn) {
        LinkedHashMap<String, List<String>> out = new LinkedHashMap<>();
        String sql =
            "IF OBJECT_ID('dbo.metric_catalog_tag_map','U') IS NOT NULL " +
            "SELECT metric_key, source_token FROM dbo.metric_catalog_tag_map WHERE enabled = 1 ORDER BY metric_key, sort_no, source_token " +
            "ELSE SELECT CAST(NULL AS VARCHAR(100)) AS metric_key, CAST(NULL AS VARCHAR(120)) AS source_token WHERE 1=0";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String metricKey = normalizeMetricKey(rs.getString("metric_key"));
                String token = trimToNull(rs.getString("source_token"));
                if (metricKey == null || token == null) continue;
                List<String> list = out.get(metricKey);
                if (list == null) {
                    list = new ArrayList<>();
                    out.put(metricKey, list);
                }
                String normalized = token.toUpperCase(Locale.ROOT);
                if (!list.contains(normalized)) list.add(normalized);
            }
        } catch (Exception ignore) {}
        return out;
    }

    private static String joinMetricTagTokens(List<String> tokens) {
        if (tokens == null || tokens.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (String token : tokens) {
            if (token == null || token.trim().isEmpty()) continue;
            if (sb.length() > 0) sb.append(", ");
            sb.append(token.trim().toUpperCase(Locale.ROOT));
        }
        return sb.toString();
    }

    private static String buildTagSummary(List<String> tokens, int maxCount) {
        if (tokens == null || tokens.isEmpty()) return "태그 선택";
        StringBuilder sb = new StringBuilder();
        int idx = 0;
        for (String token : tokens) {
            if (token == null || token.trim().isEmpty()) continue;
            if (idx > 0) sb.append(", ");
            sb.append(token.trim().toUpperCase(Locale.ROOT));
            idx++;
            if (idx >= maxCount) break;
        }
        if (idx == 0) return "태그 선택";
        if (tokens.size() > idx) sb.append(" 외 ").append(tokens.size() - idx).append("개");
        return sb.toString();
    }

    private static String saveMetricTagMappings(Connection conn, String metricKey, List<String> tokens, boolean replace) {
        String mk = normalizeMetricKey(metricKey);
        if (mk == null) return "metric_key가 없습니다.";
        boolean oldAutoCommit = true;
        try {
            oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);

            if (replace) {
                try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.metric_catalog_tag_map WHERE metric_key = ?")) {
                    ps.setString(1, mk);
                    ps.executeUpdate();
                }
            }

            if (tokens != null && !tokens.isEmpty()) {
                try (PreparedStatement ps = conn.prepareStatement(
                        "MERGE dbo.metric_catalog_tag_map t " +
                        "USING (SELECT ? AS metric_key, ? AS source_token) s " +
                        "ON (t.metric_key = s.metric_key AND t.source_token = s.source_token) " +
                        "WHEN MATCHED THEN UPDATE SET enabled = 1, updated_at = SYSUTCDATETIME() " +
                        "WHEN NOT MATCHED THEN INSERT (metric_key, source_token, sort_no, enabled, created_at, updated_at) VALUES (?, ?, ?, 1, SYSUTCDATETIME(), SYSUTCDATETIME());")) {
                    int sortNo = 1;
                    for (String token : tokens) {
                        String tk = trimToNull(token);
                        if (tk == null) continue;
                        tk = tk.toUpperCase(Locale.ROOT);
                        ps.setString(1, mk);
                        ps.setString(2, tk);
                        ps.setString(3, mk);
                        ps.setString(4, tk);
                        ps.setInt(5, sortNo++);
                        ps.executeUpdate();
                    }
                }
            }
            conn.commit();
            return null;
        } catch (Exception e) {
            try { conn.rollback(); } catch (Exception ignore) {}
            return e.getMessage();
        } finally {
            try { conn.setAutoCommit(oldAutoCommit); } catch (Exception ignore) {}
        }
    }

    private static List<String> loadAvailableAiTokens(Connection conn) {
        List<String> out = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT token FROM dbo.plc_ai_measurements_match WHERE is_supported = 1 AND token IS NOT NULL ORDER BY token");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String token = trimToNull(rs.getString(1));
                if (token != null) out.add(token.toUpperCase(Locale.ROOT));
            }
        } catch (Exception ignore) {}
        return out;
    }

    private static List<String> loadAvailableDiTokens(Connection conn) {
        List<String> out = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "IF OBJECT_ID('dbo.plc_di_tag_map','U') IS NOT NULL " +
                "SELECT DISTINCT tag_name FROM dbo.plc_di_tag_map WHERE enabled = 1 AND tag_name IS NOT NULL ORDER BY tag_name " +
                "ELSE SELECT CAST(NULL AS NVARCHAR(200)) WHERE 1=0");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String token = trimToNull(rs.getString(1));
                if (token != null) out.add(token.toUpperCase(Locale.ROOT));
            }
        } catch (Exception ignore) {}
        return out;
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
        req.originalMetricKey = normalizeMetricKey(request.getParameter("original_metric_key"));
        req.metricKey = normalizeMetricKey(request.getParameter("metric_key"));
        req.displayName = request.getParameter("display_name");
        req.sourceType = normalizeSourceType(request.getParameter("source_type"));
        req.newMetricKey = normalizeMetricKey(request.getParameter("new_metric_key"));
        req.tagTokens = buildTagTokenRequest(request, "tag_tokens");
        return req;
    }

    private static String validateMetricCatalogRequest(MetricCatalogRequest req) {
        if (req == null || req.action == null) return "요청이 올바르지 않습니다.";
        if ("save_form".equals(req.action) || "add".equals(req.action) || "update".equals(req.action) || "toggle".equals(req.action) || "delete".equals(req.action) || "save_tags".equals(req.action)) {
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
            return saveMetricTagMappings(conn, req.metricKey, parseTagTokens(req.tagTokens), true);
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
            try (PreparedStatement ps = conn.prepareStatement(
                    "IF OBJECT_ID('dbo.metric_catalog_tag_map','U') IS NOT NULL " +
                    "UPDATE dbo.metric_catalog_tag_map SET metric_key = ?, updated_at = SYSUTCDATETIME() WHERE metric_key = ?")) {
                ps.setString(1, req.newMetricKey);
                ps.setString(2, req.metricKey);
                ps.executeUpdate();
            } catch (Exception ignore) {}

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
        try {
            try (PreparedStatement ps = conn.prepareStatement(
                    "IF OBJECT_ID('dbo.metric_catalog_tag_map','U') IS NOT NULL DELETE FROM dbo.metric_catalog_tag_map WHERE metric_key=?")) {
                ps.setString(1, req.metricKey);
                ps.executeUpdate();
            }
            try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.metric_catalog WHERE metric_key=?")) {
                ps.setString(1, req.metricKey);
                ps.executeUpdate();
            }
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleSaveMetricCatalogTags(Connection conn, MetricCatalogRequest req) {
        return saveMetricTagMappings(conn, req.metricKey, parseTagTokens(req.tagTokens), true);
    }

    private static String handleSaveMetricCatalogForm(Connection conn, MetricCatalogRequest req) {
        String originalKey = req.originalMetricKey;
        if (originalKey == null || originalKey.trim().isEmpty()) {
            return handleAddMetricCatalog(conn, req);
        }

        if (originalKey.equals(req.metricKey)) {
            String err = handleUpdateMetricCatalog(conn, req);
            if (err != null) return err;
            return handleSaveMetricCatalogTags(conn, req);
        }

        MetricCatalogRequest renameReq = new MetricCatalogRequest();
        renameReq.metricKey = originalKey;
        renameReq.newMetricKey = req.metricKey;
        String renameErr = handleRenameMetricCatalog(conn, renameReq);
        if (renameErr != null && !"__NO_CHANGE__".equals(renameErr)) return renameErr;

        String updateErr = handleUpdateMetricCatalog(conn, req);
        if (updateErr != null) return updateErr;
        return handleSaveMetricCatalogTags(conn, req);
    }

%>
<%
    try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");
    String self = request.getRequestURI();
    String msg = request.getParameter("msg");
    String err = request.getParameter("err");
    List<Map<String, Object>> rows = new ArrayList<>();
    Map<String, List<String>> metricTagMappings = new HashMap<>();
    List<String> availableAiTokens = new ArrayList<>();
    List<String> availableDiTokens = new ArrayList<>();
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
            "END; " +
            "IF OBJECT_ID('dbo.metric_catalog_tag_map','U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.metric_catalog_tag_map ( " +
            "    map_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY, " +
            "    metric_key VARCHAR(100) NOT NULL, " +
            "    source_token VARCHAR(120) NOT NULL, " +
            "    sort_no INT NOT NULL DEFAULT 1, " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "  CREATE UNIQUE INDEX ux_metric_catalog_tag_map_key_token ON dbo.metric_catalog_tag_map(metric_key, source_token); " +
            "  CREATE INDEX ix_metric_catalog_tag_map_metric_key ON dbo.metric_catalog_tag_map(metric_key, enabled, sort_no); " +
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

            if ("save_form".equals(formReq.action) || "add".equals(formReq.action)) {
                String saveErr = handleSaveMetricCatalogForm(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("지표키를 저장했습니다.", "UTF-8"));
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

        metricTagMappings = loadMetricTagMappings(conn);
        availableAiTokens = loadAvailableAiTokens(conn);
        availableDiTokens = loadAvailableDiTokens(conn);

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT metric_key, display_name, source_type, enabled FROM dbo.metric_catalog ORDER BY metric_key");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String metricKey = rs.getString("metric_key");
                String normalizedKey = normalizeMetricKey(metricKey);
                Map<String, Object> r = new HashMap<>();
                r.put("metric_key", metricKey);
                r.put("display_name", rs.getString("display_name"));
                r.put("source_type", rs.getString("source_type"));
                r.put("enabled", rs.getBoolean("enabled"));
                List<String> mappedTokens = metricTagMappings.get(normalizedKey);
                String mappedTokenText = joinMetricTagTokens(mappedTokens);
                r.put("tag_tokens", mappedTokenText);
                rows.add(r);
            }
        }
    } catch (Exception e) {
        err = e.getMessage();
    }
%>
<html>
<head>
    <title>Metric Catalog Manage</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { width: min(90vw, 1600px); max-width: min(90vw, 1600px); margin: 0 auto; }
        .ok-box { margin: 10px 0; padding: 10px; border: 1px solid #b7ebc6; background: #ebfff1; color: #0f7a2a; border-radius: 8px; }
        .err-box { margin: 10px 0; padding: 10px; border: 1px solid #ffc9c9; background: #fff1f1; color: #b42318; border-radius: 8px; }
        .note-box { margin: 10px 0; padding: 10px 12px; border: 1px solid #cfe2ff; background: #eef6ff; color: #1d4f91; border-radius: 8px; line-height: 1.55; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .toolbar { display: grid; grid-template-columns: 1fr 1fr 120px 1.4fr auto auto; gap: 6px; margin-top: 10px; align-items: end; }
        .badge { display:inline-block; padding: 2px 8px; border-radius:999px; font-size: 11px; font-weight:700; }
        .on { background:#e8f7ec; border:1px solid #b9e6c6; color:#1b7f3b; }
        .off { background:#fff3e0; border:1px solid #ffd8a8; color:#b45309; }
        .row-form { display:inline-flex; margin:0; padding:4px 6px; box-shadow:none; background:#f8fbff; border:1px solid #d7e3f2; border-radius:10px; gap:4px; align-items:center; min-width:0; }
        .action-buttons { display:flex; gap:10px; align-items:center; justify-content:center; flex-wrap:nowrap; }
        .row-form input,
        .row-form select {
            margin: 0;
            padding: 5px 8px;
            min-height: 30px;
            font-size: 12px;
            border-radius: 9px;
        }
        .row-form button {
            padding: 3px 9px;
            min-height: 28px;
            font-size: 11px;
            box-shadow: 0 4px 10px rgba(31, 111, 235, 0.16);
        }
        .action-buttons .row-form {
            padding: 0;
            border: none;
            background: transparent;
            box-shadow: none;
        }
        .action-buttons button {
            min-width: 64px;
            min-height: 30px;
            padding: 4px 12px;
            font-size: 11px;
            border-radius: 999px;
            white-space: nowrap;
        }
        table td { vertical-align: middle; }
        .catalog-table th:last-child,
        .catalog-table td:last-child { width: 220px; }
        .table-scroll {
            margin-top: 12px;
            overflow-x: auto;
            overflow-y: visible;
            padding-bottom: 8px;
            border: 1px solid #dbe4ee;
            border-radius: 12px;
            background: #fff;
            scrollbar-gutter: stable both-edges;
        }
        .table-scroll::-webkit-scrollbar { height: 12px; }
        .table-scroll::-webkit-scrollbar-track { background: #eaf0f6; border-radius: 999px; }
        .table-scroll::-webkit-scrollbar-thumb { background: #9fb5cc; border-radius: 999px; }
        .tag-picker {
            position: relative;
            width: 100%;
        }
        .tag-picker > summary {
            list-style: none;
            cursor: pointer;
            min-height: 38px;
            padding: 8px 12px;
            border: 1px solid #c7d7ea;
            border-radius: 12px;
            background: #fff;
            color: #35506c;
            display: flex;
            align-items: center;
            box-shadow: inset 0 1px 0 rgba(255,255,255,0.8);
        }
        .tag-picker > summary::-webkit-details-marker { display: none; }
        .tag-picker[open] > summary {
            border-bottom-left-radius: 0;
            border-bottom-right-radius: 0;
        }
        .tag-panel {
            position: absolute;
            left: 0;
            right: 0;
            top: calc(100% - 1px);
            z-index: 20;
            background: #fff;
            border: 1px solid #c7d7ea;
            border-top: none;
            border-bottom-left-radius: 12px;
            border-bottom-right-radius: 12px;
            box-shadow: 0 12px 24px rgba(22, 48, 71, 0.12);
            padding: 10px;
        }
        .row-tag-picker[open] > summary {
            border-bottom-left-radius: 12px;
            border-bottom-right-radius: 12px;
            border-top-left-radius: 0;
            border-top-right-radius: 0;
        }
        .row-tag-picker .tag-panel {
            top: auto;
            bottom: calc(100% - 1px);
            border-top: 1px solid #c7d7ea;
            border-bottom: none;
            border-top-left-radius: 12px;
            border-top-right-radius: 12px;
            border-bottom-left-radius: 0;
            border-bottom-right-radius: 0;
            box-shadow: 0 -12px 24px rgba(22, 48, 71, 0.12);
        }
        .tag-search {
            width: 100%;
            margin: 0 0 8px 0;
            padding: 8px 10px;
            border: 1px solid #d5e0ec;
            border-radius: 10px;
        }
        .tag-list {
            max-height: 180px;
            overflow: auto;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(110px, 1fr));
            gap: 6px;
        }
        .tag-option {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 6px 8px;
            border: 1px solid #e0e8f1;
            border-radius: 10px;
            background: #f9fbfe;
            font-size: 12px;
            color: #274761;
        }
        .tag-option input { margin: 0; }
        .tag-inline-summary {
            display: inline-flex;
            flex-wrap: wrap;
            gap: 4px;
            max-width: 100%;
        }
        .tag-chip {
            display: inline-flex;
            align-items: center;
            padding: 2px 7px;
            border-radius: 999px;
            background: #edf4ff;
            border: 1px solid #cfe0ff;
            color: #1e4f8f;
            font-size: 11px;
            line-height: 1.2;
        }
        .catalog-table {
            width: 100% !important;
            min-width: 0;
            margin-top: 0 !important;
            table-layout: fixed !important;
            overflow: visible !important;
            border: none !important;
            margin-bottom: 0 !important;
            box-shadow: none !important;
            border-radius: 0 !important;
        }
        .catalog-table th,
        .catalog-table td { word-wrap: normal; }
        .catalog-table td { padding-top: 8px; padding-bottom: 8px; }
        .catalog-table td { overflow: visible; position: relative; }
        .catalog-table .token-col {
            white-space: normal;
            overflow-wrap: anywhere;
            word-break: break-word;
        }
        .catalog-table th:nth-child(1), .catalog-table td:nth-child(1) { width: 120px; }
        .catalog-table th:nth-child(2), .catalog-table td:nth-child(2) { width: 110px; }
        .catalog-table th:nth-child(3), .catalog-table td:nth-child(3) { width: 90px; }
        .catalog-table th:nth-child(4), .catalog-table td:nth-child(4) { width: 260px; }
        .catalog-table th:nth-child(5), .catalog-table td:nth-child(5) { width: 80px; text-align: center; vertical-align: middle; }
        .catalog-table th:nth-child(6), .catalog-table td:nth-child(6) { width: 220px; text-align:center; white-space: nowrap; }
        .hint-text { font-size: 11px; color: #60758a; margin-top: 4px; }
        .form-cancel { background: linear-gradient(180deg, #8ca3bc 0%, #6f879f 100%); }
        .form-cancel:hover { background: linear-gradient(180deg, #758da8 0%, #5b7187 100%); }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🗂️ 지표키 카탈로그 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/alarm_rule_manage.jsp'">알람 규칙 관리 / 등록</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="ok-box"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="err-box"><%= h(err) %></div><% } %>
    <div class="note-box">
        이 화면에서는 <b>지표키</b>와 <b>소속 태그들</b>을 같이 관리합니다.<br>
        알람 규칙에서 이 지표키를 선택하면, 여기에 등록된 여러 태그가 같은 규칙의 적용 대상이 됩니다.<br>
        예: <b>POWER_FACTOR</b>에 <b>PF, PFA, PFB, PFC</b>를 등록하면 역률 규칙 하나로 여러 태그를 함께 평가할 수 있습니다.
    </div>

    <form method="POST" id="metricForm">
        <input type="hidden" name="action" value="save_form" id="form_action">
        <input type="hidden" name="original_metric_key" value="" id="original_metric_key">
        <div class="toolbar">
            <input name="metric_key" id="form_metric_key" class="mono" placeholder="metric_key (예: POWER_FACTOR)" required>
            <input name="display_name" id="form_display_name" placeholder="표시명 (예: 역률)">
            <select name="source_type" id="form_source_type" class="mono">
                <option value="AI">AI</option>
                <option value="METER">METER</option>
                <option value="DI">DI</option>
                <option value="SYSTEM">SYSTEM</option>
            </select>
            <details class="tag-picker" id="form_tag_picker">
                <summary class="mono" id="form_tag_summary">태그 선택</summary>
                <div class="tag-panel">
                    <input type="text" class="tag-search" placeholder="태그 검색">
                    <div class="tag-list">
                        <% for (String token : availableAiTokens) { %>
                            <label class="tag-option" data-source-types="AI,METER,SYSTEM">
                                <input type="checkbox" name="tag_tokens" value="<%= h(token) %>">
                                <span class="mono"><%= h(token) %></span>
                            </label>
                        <% } %>
                        <% for (String token : availableDiTokens) { %>
                            <label class="tag-option" data-source-types="DI">
                                <input type="checkbox" name="tag_tokens" value="<%= h(token) %>">
                                <span class="mono"><%= h(token) %></span>
                            </label>
                        <% } %>
                    </div>
                </div>
            </details>
            <button type="submit" id="form_submit_btn">저장</button>
            <button type="button" id="form_cancel_btn" class="form-cancel" style="display:none;">취소</button>
        </div>
        <div class="hint-text">검색 후 체크해서 여러 태그를 바로 묶을 수 있습니다.</div>
    </form>

    <div class="table-scroll">
    <table class="catalog-table" style="margin-top:12px;">
        <thead>
            <tr><th>metric_key</th><th>display_name</th><th>source_type</th><th>소속 태그</th><th>enabled</th><th>작업</th></tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
            <tr><td colspan="6">등록된 지표키가 없습니다.</td></tr>
        <% } else { for (Map<String, Object> r : rows) { %>
            <tr>
                <td class="mono"><%= h(r.get("metric_key")) %></td>
                <td><%= h(r.get("display_name")) %></td>
                <td class="mono"><%= h(r.get("source_type")) %></td>
                <td class="mono token-col"><%= h(r.get("tag_tokens")) %></td>
                <td><% if ((Boolean)r.get("enabled")) { %><span class="badge on">ON</span><% } else { %><span class="badge off">OFF</span><% } %></td>
                <td>
                    <div class="action-buttons">
                    <button type="button"
                            class="btn-edit-metric"
                            data-metric-key="<%= h(r.get("metric_key")) %>"
                            data-display-name="<%= h(r.get("display_name")) %>"
                            data-source-type="<%= h(r.get("source_type")) %>"
                            data-tag-tokens="<%= h(r.get("tag_tokens")) %>">수정</button>
                    <form method="POST" class="row-form">
                        <input type="hidden" name="action" value="toggle">
                        <input type="hidden" name="metric_key" value="<%= h(r.get("metric_key")) %>">
                        <button type="submit">ON/OFF</button>
                    </form>
                    <form method="POST" class="row-form" onsubmit="return confirm('삭제하시겠습니까?');">
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
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
  function getTagPickerSummary(tokens){
    const clean = (tokens || []).filter(Boolean);
    if (!clean.length) return '태그 선택';
    const head = clean.slice(0, 3).join(', ');
    return clean.length > 3 ? head + ' 외 ' + (clean.length - 3) + '개' : head;
  }

  function setTagPickerValues(picker, tokens){
    if (!picker) return;
    const wanted = new Set((tokens || []).map(function(x){ return String(x).trim().toUpperCase(); }).filter(Boolean));
    picker.querySelectorAll('input[type="checkbox"][name="tag_tokens"]').forEach(function(chk){
      chk.checked = wanted.has(String(chk.value || '').trim().toUpperCase());
    });
    const summary = picker.querySelector('summary');
    if (summary) summary.textContent = getTagPickerSummary(Array.from(wanted));
  }

  function getTagPickerValues(picker){
    if (!picker) return [];
    return Array.from(picker.querySelectorAll('input[type="checkbox"][name="tag_tokens"]:checked'))
      .map(function(chk){ return String(chk.value || '').trim().toUpperCase(); })
      .filter(Boolean);
  }

  function applySourceTypeToPicker(picker, sourceType){
    if (!picker) return;
    const scope = String(sourceType || 'AI').trim().toUpperCase();
    const search = picker.querySelector('.tag-search');
    const q = search ? String(search.value || '').trim().toLowerCase() : '';
    picker.querySelectorAll('.tag-option').forEach(function(opt){
      const types = String(opt.getAttribute('data-source-types') || 'AI').toUpperCase().split(',');
      const allow = types.indexOf(scope) >= 0;
      const txt = (opt.textContent || '').toLowerCase();
      const matchSearch = (!q || txt.indexOf(q) >= 0);
      opt.style.display = (allow && matchSearch) ? '' : 'none';
    });
  }

  document.querySelectorAll('.tag-picker').forEach(function(picker){
    const search = picker.querySelector('.tag-search');
    const summary = picker.querySelector('summary');
    if (search) {
      search.addEventListener('input', function(){
        applySourceTypeToPicker(picker, sourceTypeInput ? sourceTypeInput.value : 'AI');
      });
    }
    picker.querySelectorAll('input[type="checkbox"][name="tag_tokens"]').forEach(function(chk){
      chk.addEventListener('change', function(){
        if (summary) summary.textContent = getTagPickerSummary(getTagPickerValues(picker));
      });
    });
    if (summary) summary.textContent = getTagPickerSummary(getTagPickerValues(picker));
  });

  document.addEventListener('click', function(e){
    document.querySelectorAll('.tag-picker[open]').forEach(function(picker){
      if (!picker.contains(e.target)) picker.removeAttribute('open');
    });
  });

  const metricForm = document.getElementById('metricForm');
  const originalMetricKey = document.getElementById('original_metric_key');
  const metricKeyInput = document.getElementById('form_metric_key');
  const displayNameInput = document.getElementById('form_display_name');
  const sourceTypeInput = document.getElementById('form_source_type');
  const submitBtn = document.getElementById('form_submit_btn');
  const cancelBtn = document.getElementById('form_cancel_btn');
  const topTagPicker = document.getElementById('form_tag_picker');

  function resetMetricForm(){
    if (!metricForm) return;
    originalMetricKey.value = '';
    metricKeyInput.value = '';
    displayNameInput.value = '';
    sourceTypeInput.value = 'AI';
    setTagPickerValues(topTagPicker, []);
    applySourceTypeToPicker(topTagPicker, 'AI');
    if (submitBtn) submitBtn.textContent = '저장';
    if (cancelBtn) cancelBtn.style.display = 'none';
  }

  document.querySelectorAll('.btn-edit-metric').forEach(function(btn){
    btn.addEventListener('click', function(){
      const tags = String(btn.getAttribute('data-tag-tokens') || '')
        .split(',')
        .map(function(x){ return x.trim(); })
        .filter(Boolean);
      originalMetricKey.value = btn.getAttribute('data-metric-key') || '';
      metricKeyInput.value = btn.getAttribute('data-metric-key') || '';
      displayNameInput.value = btn.getAttribute('data-display-name') || '';
      sourceTypeInput.value = btn.getAttribute('data-source-type') || 'AI';
      setTagPickerValues(topTagPicker, tags);
      applySourceTypeToPicker(topTagPicker, sourceTypeInput.value);
      if (submitBtn) submitBtn.textContent = '수정 저장';
      if (cancelBtn) cancelBtn.style.display = '';
      window.scrollTo({ top: 0, behavior: 'smooth' });
      metricKeyInput.focus();
    });
  });

  if (sourceTypeInput) {
    sourceTypeInput.addEventListener('change', function(){
      applySourceTypeToPicker(topTagPicker, sourceTypeInput.value);
    });
  }

  if (cancelBtn) {
    cancelBtn.addEventListener('click', function(){
      resetMetricForm();
    });
  }

  applySourceTypeToPicker(topTagPicker, sourceTypeInput ? sourceTypeInput.value : 'AI');
</script>
<%
    }
%>
</body>
</html>
