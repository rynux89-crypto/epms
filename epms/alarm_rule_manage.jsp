<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static final String DEFAULT_MESSAGE_TEMPLATE = "source=${source}, value=${value}, 기준 ${operator} ${t1}";
    private static final String DEFAULT_BETWEEN_TEMPLATE = "source=${source}, value=${value}, 기준 ${operator} ${t1} ~ ${t2}";
    private static final String DEFAULT_OUTSIDE_TEMPLATE = "source=${source}, value=${value}, 기준 ${t1} ~ ${t2} 범위 이탈";

    private static Double roundToTwoDecimals(Double value) {
        if (value == null) return null;
        return Double.valueOf(Math.round(value.doubleValue() * 100.0d) / 100.0d);
    }

    private static String normKey(String v) {
        if (v == null) return "";
        return v.trim().toUpperCase(Locale.ROOT);
    }

    private static Map<String, List<String>> loadMeasurementColumnTokens(Connection conn) {
        Map<String, List<String>> map = new HashMap<>();
        String sql =
            "IF OBJECT_ID('dbo.plc_ai_measurements_match','U') IS NOT NULL " +
            "SELECT token, measurement_column FROM dbo.plc_ai_measurements_match WHERE is_supported = 1";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String token = normKey(rs.getString("token"));
                String column = normKey(rs.getString("measurement_column"));
                if (token.isEmpty() || column.isEmpty()) continue;
                List<String> list = map.get(column);
                if (list == null) {
                    list = new ArrayList<>();
                    map.put(column, list);
                }
                if (!list.contains(token)) list.add(token);
            }
        } catch (Exception ignore) {
        }
        for (List<String> list : map.values()) Collections.sort(list);
        return map;
    }

    private static String joinTokens(Map<String, List<String>> columnTokens, String... columns) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        if (columnTokens == null || columns == null) return "";
        for (String column : columns) {
            String key = normKey(column);
            if (key.isEmpty()) continue;
            List<String> list = columnTokens.get(key);
            if (list != null) out.addAll(list);
        }
        StringBuilder sb = new StringBuilder();
        for (String token : out) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(token);
        }
        return sb.toString();
    }

    private static Map<String, List<String>> loadMetricCatalogTagTokens(Connection conn) {
        Map<String, List<String>> map = new HashMap<>();
        String sql =
            "IF OBJECT_ID('dbo.metric_catalog_tag_map','U') IS NOT NULL " +
            "SELECT metric_key, source_token FROM dbo.metric_catalog_tag_map WHERE enabled = 1 ORDER BY metric_key, sort_no, source_token";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String metricKey = normKey(rs.getString("metric_key"));
                String token = normKey(rs.getString("source_token"));
                if (metricKey.isEmpty() || token.isEmpty()) continue;
                List<String> list = map.get(metricKey);
                if (list == null) {
                    list = new ArrayList<>();
                    map.put(metricKey, list);
                }
                if (!list.contains(token)) list.add(token);
            }
        } catch (Exception ignore) {
        }
        return map;
    }

    private static String joinMetricCatalogTokens(Map<String, List<String>> metricTagTokens, String metricKey) {
        if (metricTagTokens == null) return "";
        List<String> list = metricTagTokens.get(normKey(metricKey));
        if (list == null || list.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (String token : list) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(token);
        }
        return sb.toString();
    }

    private static String resolveRuleInputDisplay(String metricKey, String sourceToken, String targetScope,
                                                  Map<String, List<String>> columnTokens,
                                                  Map<String, List<String>> metricTagTokens) {
        String scope = normKey(targetScope);
        String mk = normKey(metricKey);
        String st = normKey(sourceToken);
        if (!st.isEmpty()) return st;
        if ("PLC".equals(scope)) return mk;

        String configured = joinMetricCatalogTokens(metricTagTokens, mk);
        if (!configured.isEmpty()) return configured;

        if ("POWER_FACTOR".equals(mk) || "PF_GROUP".equals(mk)) {
            String x = joinTokens(columnTokens, "power_factor", "power_factor_avg");
            return x.isEmpty() ? "PF 계열" : x;
        }
        if ("FREQUENCY_GROUP".equals(mk) || "HZ_GROUP".equals(mk)) {
            String x = joinTokens(columnTokens, "frequency");
            return x.isEmpty() ? "HZ" : x;
        }
        if ("THD_VOLTAGE".equals(mk) || "THD_VOLTAGE_MAX".equals(mk)) {
            String x = joinTokens(columnTokens, "thd_voltage_a", "thd_voltage_b", "thd_voltage_c");
            return x.isEmpty() ? "H_V*_1 계열" : x;
        }
        if ("THD_CURRENT".equals(mk) || "THD_CURRENT_MAX".equals(mk)) {
            String x = joinTokens(columnTokens, "thd_current_a", "thd_current_b", "thd_current_c");
            return x.isEmpty() ? "H_I*_1 계열" : x;
        }
        if ("UNBALANCE".equals(mk) || "UNBALANCE_MAX".equals(mk)) return "voltage_unbalance_rate / 상전압 계열";
        if ("V_VARIATION".equals(mk) || "VOLTAGE_VARIATION".equals(mk)) return "V_VAR 계열";
        if ("I_VARIATION".equals(mk) || "CURRENT_VARIATION".equals(mk)) return "I_VAR 계열";
        if ("VARIATION".equals(mk) || "VARIATION_MAX".equals(mk)) return "V_VAR / I_VAR 계열";
        if ("PEAK".equals(mk) || "MAX_POWER".equals(mk) || "PEAK_POWER".equals(mk)) return "PEAK";
        return "";
    }

    private static List<String> loadSelectableMetricKeys(Connection conn) throws Exception {
        TreeSet<String> set = new TreeSet<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "IF OBJECT_ID('dbo.metric_catalog','U') IS NOT NULL " +
                "SELECT metric_key FROM dbo.metric_catalog " +
                "ELSE SELECT CAST(NULL AS VARCHAR(100)) WHERE 1=0");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String k = normKey(rs.getString(1));
                if (!k.isEmpty()) set.add(k);
            }
        }
        try (PreparedStatement ps = conn.prepareStatement("SELECT DISTINCT metric_key FROM dbo.alarm_rule");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String k = normKey(rs.getString(1));
                if (!k.isEmpty()) set.add(k);
            }
        }
        return new ArrayList<>(set);
    }

    private static class AlarmRuleRequest {
        String action;
        Integer ruleId;
        String ruleCode;
        String ruleName;
        String category;
        String targetScope;
        String metricKey;
        String operator;
        Double threshold1;
        Double threshold2;
        Integer durationSec;
        Double hysteresis;
        String severity;
        String sourceToken;
        String messageTemplate;
        String description;
    }

    private static AlarmRuleRequest buildAlarmRuleRequest(javax.servlet.http.HttpServletRequest request) {
        AlarmRuleRequest req = new AlarmRuleRequest();
        req.action = request.getParameter("action");
        req.ruleId = parseNullableInt(request.getParameter("rule_id"));
        req.ruleCode = request.getParameter("rule_code");
        req.ruleName = request.getParameter("rule_name");
        req.category = request.getParameter("category");
        req.targetScope = request.getParameter("target_scope");
        req.metricKey = request.getParameter("metric_key");
        req.operator = request.getParameter("operator");
        req.threshold1 = roundToTwoDecimals(parseNullableDouble(request.getParameter("threshold1")));
        req.threshold2 = roundToTwoDecimals(parseNullableDouble(request.getParameter("threshold2")));
        req.durationSec = Integer.valueOf(0);
        req.hysteresis = null;
        req.severity = request.getParameter("severity");
        if (req.severity == null || req.severity.trim().isEmpty()) req.severity = "ALARM";
        req.sourceToken = request.getParameter("source_token");
        req.messageTemplate = request.getParameter("message_template");
        if (req.messageTemplate == null || req.messageTemplate.trim().isEmpty()) {
            req.messageTemplate = DEFAULT_MESSAGE_TEMPLATE;
        }
        req.description = request.getParameter("description");
        return req;
    }

    private static String validateAlarmRuleRequest(AlarmRuleRequest req, Set<String> metricKeySet) {
        if (req == null) return "요청이 올바르지 않습니다.";
        String action = req.action == null ? "" : req.action;
        String scope = normKey(req.targetScope);
        if ("add".equals(action)) {
            if (req.ruleCode == null || req.ruleCode.trim().isEmpty() ||
                req.ruleName == null || req.ruleName.trim().isEmpty() ||
                req.category == null || req.category.trim().isEmpty() ||
                req.metricKey == null || req.metricKey.trim().isEmpty()) {
                return "필수값(rule_code/rule_name/category/metric_key)을 입력하세요.";
            }
        }
        if ("update".equals(action) || "toggle".equals(action) || "delete".equals(action)) {
            if (req.ruleId == null) return "잘못된 rule_id 입니다.";
        }
        if ("add".equals(action) || "update".equals(action)) {
            String metricKeyNorm = normKey(req.metricKey);
            if (metricKeyNorm.isEmpty()) {
                return "허용되지 않은 지표키입니다. 목록에서 선택해 주세요.";
            }
            if (!"PLC".equals(scope) && !metricKeySet.contains(metricKeyNorm)) {
                return "허용되지 않은 지표키입니다. 목록에서 선택해 주세요.";
            }
        }
        return null;
    }

    private static String handleAddAlarmRule(Connection conn, AlarmRuleRequest req) {
        String insSql =
            "INSERT INTO dbo.alarm_rule " +
            "(rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, threshold2, duration_sec, hysteresis, severity, enabled, source_token, message_template, description, updated_at) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, SYSUTCDATETIME())";
        try (PreparedStatement ps = conn.prepareStatement(insSql)) {
            ps.setString(1, req.ruleCode.trim().toUpperCase(Locale.ROOT));
            ps.setString(2, req.ruleName.trim());
            ps.setString(3, req.category.trim().toUpperCase(Locale.ROOT));
            ps.setString(4, (req.targetScope == null || req.targetScope.trim().isEmpty()) ? "METER" : req.targetScope.trim().toUpperCase(Locale.ROOT));
            ps.setString(5, normKey(req.metricKey));
            ps.setString(6, (req.operator == null || req.operator.trim().isEmpty()) ? ">=" : req.operator.trim());
            if (req.threshold1 == null) ps.setNull(7, Types.DECIMAL); else ps.setDouble(7, req.threshold1);
            if (req.threshold2 == null) ps.setNull(8, Types.DECIMAL); else ps.setDouble(8, req.threshold2);
            ps.setInt(9, (req.durationSec == null || req.durationSec.intValue() < 0) ? 0 : req.durationSec.intValue());
            if (req.hysteresis == null) ps.setNull(10, Types.DECIMAL); else ps.setDouble(10, req.hysteresis);
            ps.setString(11, req.severity == null ? "ALARM" : req.severity.trim().toUpperCase(Locale.ROOT));
            ps.setString(12, req.sourceToken);
            ps.setString(13, req.messageTemplate);
            ps.setString(14, req.description);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleUpdateAlarmRule(Connection conn, AlarmRuleRequest req) {
        String updSql =
            "UPDATE dbo.alarm_rule SET " +
            " rule_name = ?, category = ?, target_scope = ?, metric_key = ?, operator = ?, " +
            " threshold1 = ?, threshold2 = ?, duration_sec = ?, hysteresis = ?, severity = ?, source_token = ?, message_template = ?, description = ?, updated_at = SYSUTCDATETIME() " +
            "WHERE rule_id = ?";
        try (PreparedStatement ps = conn.prepareStatement(updSql)) {
            ps.setString(1, req.ruleName);
            ps.setString(2, req.category);
            ps.setString(3, req.targetScope);
            ps.setString(4, normKey(req.metricKey));
            ps.setString(5, req.operator);
            if (req.threshold1 == null) ps.setNull(6, Types.DECIMAL); else ps.setDouble(6, req.threshold1);
            if (req.threshold2 == null) ps.setNull(7, Types.DECIMAL); else ps.setDouble(7, req.threshold2);
            ps.setInt(8, (req.durationSec == null || req.durationSec.intValue() < 0) ? 0 : req.durationSec.intValue());
            if (req.hysteresis == null) ps.setNull(9, Types.DECIMAL); else ps.setDouble(9, req.hysteresis);
            ps.setString(10, req.severity == null ? "ALARM" : req.severity.trim().toUpperCase(Locale.ROOT));
            ps.setString(11, req.sourceToken);
            ps.setString(12, req.messageTemplate);
            ps.setString(13, req.description);
            ps.setInt(14, req.ruleId.intValue());
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleToggleAlarmRule(Connection conn, AlarmRuleRequest req) {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.alarm_rule SET enabled = CASE WHEN enabled = 1 THEN 0 ELSE 1 END, updated_at = SYSUTCDATETIME() WHERE rule_id = ?")) {
            ps.setInt(1, req.ruleId.intValue());
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleDeleteAlarmRule(Connection conn, AlarmRuleRequest req) {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.alarm_rule WHERE rule_id = ?")) {
            ps.setInt(1, req.ruleId.intValue());
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

    String self = request.getRequestURI();
    String message = request.getParameter("msg");
    String error = request.getParameter("err");
    List<Map<String, Object>> rows = new ArrayList<>();
    List<String> metricKeys = new ArrayList<>();
    List<String> diMetricKeys = new ArrayList<>();
    Map<String, List<String>> columnTokens = new HashMap<>();

    try {
        String ensureSql =
            "IF OBJECT_ID('dbo.alarm_rule', 'U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.alarm_rule ( " +
            "    rule_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY, " +
            "    rule_code VARCHAR(50) NOT NULL, " +
            "    rule_name NVARCHAR(120) NOT NULL, " +
            "    category VARCHAR(30) NOT NULL, " +
            "    target_scope VARCHAR(20) NOT NULL DEFAULT 'METER', " +
            "    metric_key VARCHAR(100) NOT NULL, " +
            "    operator VARCHAR(10) NOT NULL DEFAULT '>=', " +
            "    threshold1 DECIMAL(18,6) NULL, " +
            "    threshold2 DECIMAL(18,6) NULL, " +
            "    duration_sec INT NOT NULL DEFAULT 0, " +
            "    hysteresis DECIMAL(18,6) NULL, " +
            "    severity VARCHAR(20) NOT NULL DEFAULT 'WARN', " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    source_token VARCHAR(120) NULL, " +
            "    message_template NVARCHAR(300) NULL, " +
            "    description NVARCHAR(500) NULL, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "  CREATE UNIQUE INDEX ux_alarm_rule_code ON dbo.alarm_rule(rule_code); " +
            "END";
        try (Statement st = conn.createStatement()) {
            st.execute(ensureSql);
        }
        String ensureColsSql =
            "IF COL_LENGTH('dbo.alarm_rule','source_token') IS NULL ALTER TABLE dbo.alarm_rule ADD source_token VARCHAR(120) NULL; " +
            "IF COL_LENGTH('dbo.alarm_rule','message_template') IS NULL ALTER TABLE dbo.alarm_rule ADD message_template NVARCHAR(300) NULL;";
        try (Statement st = conn.createStatement()) {
            st.execute(ensureColsSql);
        }

        metricKeys = loadSelectableMetricKeys(conn);
        Set<String> metricKeySet = new HashSet<>(metricKeys);
        try (PreparedStatement ps = conn.prepareStatement(
                "IF OBJECT_ID('dbo.metric_catalog','U') IS NOT NULL " +
                "SELECT DISTINCT metric_key FROM dbo.metric_catalog WHERE source_type = 'DI' " +
                "UNION " +
                "SELECT DISTINCT metric_key FROM dbo.alarm_rule WHERE target_scope = 'PLC' " +
                "ELSE SELECT DISTINCT metric_key FROM dbo.alarm_rule WHERE target_scope = 'PLC'");
             ResultSet rs = ps.executeQuery()) {
            TreeSet<String> diKeySet = new TreeSet<>();
            while (rs.next()) {
                String mk = normKey(rs.getString(1));
                if (!mk.isEmpty()) diKeySet.add(mk);
            }
            diMetricKeys = new ArrayList<>(diKeySet);
        } catch (Exception ignore) {
        }

        if ("POST".equalsIgnoreCase(request.getMethod())) {
            AlarmRuleRequest formReq = buildAlarmRuleRequest(request);
            String formErr = validateAlarmRuleRequest(formReq, metricKeySet);
            if (formErr != null) {
                response.sendRedirect(self + "?err=" + URLEncoder.encode(formErr, "UTF-8"));
                return;
            }

            if ("add".equals(formReq.action)) {
                String saveErr = handleAddAlarmRule(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("알람 규칙을 추가했습니다.", "UTF-8"));
                return;
            }

            if ("update".equals(formReq.action)) {
                String saveErr = handleUpdateAlarmRule(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("알람 규칙을 수정했습니다.", "UTF-8"));
                return;
            }

            if ("toggle".equals(formReq.action)) {
                String saveErr = handleToggleAlarmRule(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("알람 규칙 상태가 변경되었습니다.", "UTF-8"));
                return;
            }

            if ("delete".equals(formReq.action)) {
                String saveErr = handleDeleteAlarmRule(conn, formReq);
                if (saveErr != null) {
                    response.sendRedirect(self + "?err=" + URLEncoder.encode(saveErr, "UTF-8"));
                    return;
                }
                response.sendRedirect(self + "?msg=" + URLEncoder.encode("알람 규칙을 삭제했습니다.", "UTF-8"));
                return;
            }
        }

        columnTokens = loadMeasurementColumnTokens(conn);
        Map<String, List<String>> metricTagTokens = loadMetricCatalogTagTokens(conn);

        String q =
            "SELECT r.rule_id, r.rule_code, r.rule_name, r.category, r.target_scope, r.metric_key, r.operator, r.threshold1, r.threshold2, r.duration_sec, " +
            "       r.hysteresis, r.severity, r.source_token, r.message_template, r.enabled, r.description, r.updated_at, mc.display_name AS metric_display_name " +
            "FROM dbo.alarm_rule r " +
            "LEFT JOIN dbo.metric_catalog mc ON mc.metric_key = r.metric_key " +
            "ORDER BY r.rule_id";
        try (PreparedStatement ps = conn.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("rule_id", rs.getInt("rule_id"));
                r.put("rule_code", rs.getString("rule_code"));
                r.put("rule_name", rs.getString("rule_name"));
                r.put("category", rs.getString("category"));
                r.put("target_scope", rs.getString("target_scope"));
                r.put("metric_key", rs.getString("metric_key"));
                String metricDisplayName = rs.getString("metric_display_name");
                String metricKey = rs.getString("metric_key");
                String metricDisplay = (metricDisplayName == null || metricDisplayName.trim().isEmpty())
                    ? metricKey
                    : (metricDisplayName.trim() + " (" + metricKey + ")");
                r.put("metric_display", metricDisplay);
                r.put("operator", rs.getString("operator"));
                r.put("threshold1", rs.getObject("threshold1"));
                r.put("threshold2", rs.getObject("threshold2"));
                r.put("duration_sec", rs.getInt("duration_sec"));
                r.put("hysteresis", rs.getObject("hysteresis"));
                r.put("severity", rs.getString("severity"));
                String dbSeverity = rs.getString("severity");
                String opText = rs.getString("operator");
                String opNorm = opText == null ? "" : opText.trim().toUpperCase(Locale.ROOT);
                boolean rangeMode = "BETWEEN".equals(opNorm) || "OUTSIDE".equals(opNorm);
                boolean hasSecondThreshold = rs.getObject("threshold2") != null;
                r.put("severity_display", (!rangeMode && hasSecondThreshold)
                    ? "ALARM / CRITICAL"
                    : ((dbSeverity == null || dbSeverity.trim().isEmpty()) ? "ALARM" : dbSeverity.trim().toUpperCase(Locale.ROOT)));
                r.put("source_token", rs.getString("source_token"));
                r.put("message_template", rs.getString("message_template"));
                r.put("enabled", rs.getBoolean("enabled"));
                r.put("description", rs.getString("description"));
                r.put("updated_at", rs.getTimestamp("updated_at"));
                r.put("resolved_input", resolveRuleInputDisplay(
                    rs.getString("metric_key"),
                    rs.getString("source_token"),
                    rs.getString("target_scope"),
                    columnTokens,
                    metricTagTokens
                ));
                rows.add(r);
            }
        }
    } catch (Exception e) {
        error = e.getMessage();
    }
%>
<html>
<head>
    <title>Alarm Rule Manage</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1800px; margin: 0 auto; }
        .note-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .toolbar { display: grid; grid-template-columns: repeat(5, minmax(120px, 1fr)); gap: 8px; align-items: start; }
        .toolbar .full { grid-column: 1 / -1; }
        .field-group { display: flex; flex-direction: column; gap: 4px; }
        .field-label {
            font-size: 12px;
            font-weight: 700;
            color: #35526b;
            line-height: 1.2;
            padding-left: 2px;
        }
        .field-help {
            font-size: 11px;
            color: #6f8091;
            line-height: 1.35;
            padding-left: 2px;
        }
        .toolbar input, .toolbar select { width: 100%; margin: 0; }
        .toolbar button { margin: 0; }
        .form-actions { display: flex; gap: 6px; }
        .rule-table th {
            font-size: 10px;
            white-space: nowrap;
            word-break: keep-all;
            padding: 6px 5px;
            line-height: 1.1;
        }
        .rule-table-wrap {
            overflow-x: hidden;
            overflow-y: visible;
            margin-top: 12px;
            border: 1px solid #d7e0ea;
            border-radius: 14px;
            background: #fff;
            -webkit-overflow-scrolling: touch;
            scrollbar-width: thin;
            scrollbar-color: #9cb7d3 #edf3fb;
        }
        .rule-table-wrap::-webkit-scrollbar { height: 10px; }
        .rule-table-wrap::-webkit-scrollbar-track { background: #edf3fb; border-radius: 999px; }
        .rule-table-wrap::-webkit-scrollbar-thumb { background: #9cb7d3; border-radius: 999px; }
        .rule-table {
            width: 100% !important;
            min-width: 0;
            table-layout: fixed !important;
            margin-bottom: 0;
            border: none;
            border-radius: 0;
            box-shadow: none;
        }
        .rule-table td {
            font-size: 12px;
            vertical-align: middle;
            white-space: normal;
            word-break: break-word;
            overflow-wrap: anywhere;
        }
        .rule-table th:nth-child(1), .rule-table td:nth-child(1) { width: 3%; }
        .rule-table th:nth-child(2), .rule-table td:nth-child(2) { width: 6%; }
        .rule-table th:nth-child(3), .rule-table td:nth-child(3) { width: 7%; }
        .rule-table th:nth-child(4), .rule-table td:nth-child(4) { width: 5%; }
        .rule-table th:nth-child(5), .rule-table td:nth-child(5) { width: 5%; }
        .rule-table th:nth-child(6), .rule-table td:nth-child(6) { width: 6%; }
        .rule-table th:nth-child(7), .rule-table td:nth-child(7) { width: 4%; }
        .rule-table th:nth-child(8), .rule-table td:nth-child(8) { width: 6%; }
        .rule-table th:nth-child(9), .rule-table td:nth-child(9) { width: 6%; }
        .rule-table th:nth-child(10), .rule-table td:nth-child(10) { width: 6%; }
        .rule-table th:nth-child(11), .rule-table td:nth-child(11) { width: 8%; }
        .rule-table th:nth-child(12), .rule-table td:nth-child(12) { width: 10%; }
        .rule-table th:nth-child(13), .rule-table td:nth-child(13) { width: 10%; }
        .rule-table th:nth-child(14), .rule-table td:nth-child(14) { width: 5%; }
        .rule-table th:nth-child(15), .rule-table td:nth-child(15) { width: 6%; }
        .rule-table th:nth-child(16), .rule-table td:nth-child(16) { width: 5%; }
        .rule-table th:nth-child(17), .rule-table td:nth-child(17) { width: 7%; }
        .act-wrap {
            display: flex;
            gap: 4px;
            justify-content: center;
            align-items: center;
            flex-wrap: nowrap;
            white-space: nowrap;
        }
        .btn-sm { padding: 4px 7px; font-size: 11px; white-space: nowrap; }
        .row-form { margin: 0; padding: 0; box-shadow: none; background: transparent; display: inline; }
        .rule-table tbody tr.pickable { cursor: pointer; }
        .rule-table tbody tr.pickable:hover { background: #f5f9ff; }
        .rule-table tbody tr.selected { background: #eaf3ff; }
        .is-disabled { opacity: 0.6; }
        .form-card {
            margin-top: 14px;
            margin-bottom: 16px;
            padding: 16px 18px 18px;
            border: none;
            border-radius: 0;
            background: transparent;
            box-shadow: none;
        }
        .form-title {
            margin: 0 0 6px 0;
            font-size: 1.05rem;
            font-weight: 700;
            color: #163047;
        }
        .form-subtitle {
            margin: 0 0 14px 0;
            font-size: 12px;
            color: #60758a;
            line-height: 1.5;
        }
        .form-split {
            display: grid;
            grid-template-columns: 1.4fr 1fr;
            gap: 18px;
            align-items: start;
        }
        .sub-form-card {
            border: 1px solid #d7e3f0;
            border-radius: 14px;
            background: #fff;
            padding: 14px 16px 16px;
            box-shadow: 0 6px 18px rgba(15, 23, 42, 0.05);
        }
        .sub-form-card h3 {
            margin: 0 0 4px 0;
            font-size: 16px;
            color: #163047;
        }
        .sub-form-card .mini-help {
            margin: 0 0 12px 0;
            font-size: 12px;
            color: #60758a;
            line-height: 1.5;
        }
        .scope-pill {
            display: inline-flex;
            align-items: center;
            min-height: 42px;
            padding: 0 12px;
            border: 1px solid #d7e3f0;
            border-radius: 10px;
            background: #f8fbff;
            color: #163047;
            font-weight: 700;
        }
        @media (max-width: 1200px) {
            .form-split {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🚨 알람 규칙 관리 / 등록</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/alarm_view.jsp'">알람 목록</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="note-box">
        알람 규칙을 등록하고 관리합니다. 표의 행을 클릭하면 상단 입력창에서 수정됩니다.<br>
        2단계 규칙: <b>임계값1=ALARM, 임계값2=CRITICAL</b> 기준으로 판정됩니다. 임계값2를 비우면 단일 임계 규칙입니다.
    </div>

    <% if (message != null && !message.trim().isEmpty()) { %>
    <div class="ok-box"><%= h(message) %></div>
    <% } %>
    <% if (error != null && !error.trim().isEmpty()) { %>
    <div class="err-box"><%= h(error) %></div>
    <% } %>

    <div class="form-card">
        <div class="form-split">
            <div class="sub-form-card">
                <h3>AI 알람 규칙 입력폼</h3>
                <p class="mini-help">아날로그 값 기준의 AI 규칙을 등록하거나 목록에서 선택한 AI 규칙을 수정합니다.</p>
                <form method="POST" id="aiRuleForm">
                    <input type="hidden" name="action" id="aiActionField" value="add">
                    <input type="hidden" name="rule_id" id="aiRuleIdField" value="">
                    <div class="toolbar">
                        <div class="field-group">
                            <label class="field-label" for="ai_rule_code">규칙 코드</label>
                            <input id="ai_rule_code" name="rule_code" placeholder="예: PF_LOW" required class="mono">
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_rule_name">규칙명</label>
                            <input id="ai_rule_name" name="rule_name" placeholder="규칙명" required>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_category">분류</label>
                            <input id="ai_category" name="category" placeholder="분류" value="POWER_QUALITY" required class="mono">
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_target_scope">적용범위</label>
                            <input id="ai_target_scope" name="target_scope" placeholder="적용범위" value="METER" required class="mono">
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_metric_key">지표키</label>
                            <select id="ai_metric_key" name="metric_key" required class="mono">
                                <option value="">지표키 선택</option>
                                <% for (String mk : metricKeys) { %>
                                <option value="<%= h(mk) %>"><%= h(mk) %></option>
                                <% } %>
                            </select>
                            <div class="field-help">어떤 태그 묶음에 이 규칙을 적용할지 선택합니다.</div>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_source_token">연결 토큰/태그</label>
                            <input id="ai_source_token" name="source_token" placeholder="비우면 지표키에 연결된 전체 태그 적용" class="mono">
                            <div class="field-help">특정 태그만 지정할 때만 입력합니다.</div>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_operator">연산자</label>
                            <select id="ai_operator" name="operator" class="mono">
                                <option value="<">&lt;  미만</option>
                                <option value="<=">&lt;= 이하</option>
                                <option value=">">&gt;  초과</option>
                                <option value=">=">&gt;= 이상</option>
                                <option value="=">=  같음</option>
                                <option value="BETWEEN">BETWEEN 범위</option>
                                <option value="OUTSIDE">OUTSIDE 범위이탈</option>
                            </select>
                            <div class="field-help">보통 저하는 `미만`, 초과는 `초과/이상`, 정상 범위 밖 알람은 `OUTSIDE`를 사용합니다.</div>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_threshold1">임계값1</label>
                            <input id="ai_threshold1" type="number" step="0.01" name="threshold1" placeholder="ALARM 기준">
                            <div class="field-help">단일 규칙이면 이 값만 입력합니다.</div>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_threshold2">임계값2</label>
                            <input id="ai_threshold2" type="number" step="0.01" name="threshold2" placeholder="CRITICAL 기준">
                            <div class="field-help">더 심한 2단계 알람이 필요할 때만 입력합니다.</div>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="ai_severity">발생 단계</label>
                            <select id="ai_severity" name="severity" class="mono">
                                <option value="ALARM">ALARM</option>
                                <option value="CRITICAL">CRITICAL</option>
                            </select>
                            <div class="field-help">단일 단계 규칙에서 ALARM 또는 CRITICAL을 선택합니다. BETWEEN/OUTSIDE도 단일 단계일 때 이 값을 사용합니다. 임계값2가 있으면 자동으로 ALARM/CRITICAL 2단계가 적용됩니다.</div>
                        </div>
                        <div class="field-group full">
                            <label class="field-label" for="ai_message_template">메시지 템플릿</label>
                            <input id="ai_message_template" name="message_template" value="source=\${source}, value=\${value}, 기준 \${operator} \${t1}" placeholder="source=\${source}, value=\${value}, 기준 \${operator} \${t1}">
                            <div class="field-help">사용 가능 변수: \${meter_id}, \${rule_code}, \${stage}, \${metric}, \${source}, \${value}, \${operator}, \${t1}, \${t2}</div>
                        </div>
                        <div class="field-group full">
                            <label class="field-label" for="ai_description">설명</label>
                            <input id="ai_description" name="description" placeholder="설명" class="full">
                        </div>
                        <div class="full form-actions">
                            <button type="submit" id="aiSubmitBtn">AI 규칙 추가</button>
                            <button type="button" id="aiClearBtn">선택 해제</button>
                        </div>
                    </div>
                </form>
            </div>

            <div class="sub-form-card">
                <h3>DI 알람 규칙 입력폼</h3>
                <p class="mini-help">디지털 비트 유형 기준의 DI 규칙을 등록하거나 목록에서 선택한 DI 규칙을 수정합니다.</p>
                <form method="POST" id="diRuleForm">
                    <input type="hidden" name="action" id="diActionField" value="add">
                    <input type="hidden" name="rule_id" id="diRuleIdField" value="">
                    <input type="hidden" name="target_scope" id="di_target_scope" value="PLC">
                    <input type="hidden" name="operator" id="di_operator" value="=">
                    <input type="hidden" name="threshold1" id="di_threshold1" value="1">
                    <input type="hidden" name="threshold2" id="di_threshold2" value="">
                    <input type="hidden" name="source_token" id="di_source_token" value="">
                    <div class="toolbar">
                        <div class="field-group">
                            <label class="field-label" for="di_rule_code">규칙 코드</label>
                            <input id="di_rule_code" name="rule_code" placeholder="예: DI_TRIP" required class="mono">
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="di_rule_name">규칙명</label>
                            <input id="di_rule_name" name="rule_name" placeholder="예: 트립" required>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="di_category">분류</label>
                            <input id="di_category" name="category" placeholder="분류" value="DI" required class="mono">
                        </div>
                        <div class="field-group">
                            <label class="field-label">적용범위</label>
                            <div class="scope-pill">PLC</div>
                        </div>
                        <div class="field-group">
                            <label class="field-label" for="di_metric_key">DI 유형</label>
                            <select id="di_metric_key" name="metric_key" required class="mono">
                                <option value="">DI 유형 선택</option>
                                <% for (String mk : diMetricKeys) { %>
                                <option value="<%= h(mk) %>"><%= h(mk) %></option>
                                <% } %>
                            </select>
                            <div class="field-help">TRIP, OCR, OCGR 같은 DI 유형 기준으로 연결합니다.</div>
                        </div>
                        <div class="field-group full">
                            <label class="field-label" for="di_message_template">메시지 템플릿</label>
                            <input id="di_message_template" name="message_template" value="source=\${tag}, item=\${item}, panel=\${panel}, addr=\${address}, bit=\${bit}" placeholder="source=\${tag}, item=\${item}, panel=\${panel}, addr=\${address}, bit=\${bit}">
                            <div class="field-help">사용 가능 변수: \${rule_code}, \${metric}, \${source}, \${tag}, \${item}, \${panel}, \${address}, \${bit}, \${point_id}</div>
                        </div>
                        <div class="field-group full">
                            <label class="field-label" for="di_description">설명</label>
                            <input id="di_description" name="description" placeholder="설명" class="full">
                        </div>
                        <div class="full form-actions">
                            <button type="submit" id="diSubmitBtn">DI 규칙 추가</button>
                            <button type="button" id="diClearBtn">선택 해제</button>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <div class="rule-table-wrap">
    <table class="rule-table">
        <thead>
        <tr>
            <th>No.</th>
            <th>규칙 코드</th>
            <th>규칙명</th>
            <th>분류</th>
            <th>적용범위</th>
            <th>지표키</th>
            <th>연산자</th>
            <th>임계값1(ALARM)</th>
            <th>임계값2(CRITICAL)</th>
            <th>발생 단계</th>
            <th>연결토큰</th>
            <th>실제 판단 입력</th>
            <th>메시지템플릿</th>
            <th>사용여부</th>
            <th>설명</th>
            <th>수정시각</th>
            <th>작업</th>
        </tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
        <tr><td colspan="17">등록된 알람 규칙이 없습니다.</td></tr>
        <% } else { %>
        <% for (int rowIdx = 0; rowIdx < rows.size(); rowIdx++) { Map<String, Object> r = rows.get(rowIdx); %>
        <tr class="pickable"
            data-rule-id="<%= h(r.get("rule_id")) %>"
            data-rule-code="<%= h(r.get("rule_code")) %>"
            data-rule-name="<%= h(r.get("rule_name")) %>"
            data-category="<%= h(r.get("category")) %>"
            data-target-scope="<%= h(r.get("target_scope")) %>"
            data-metric-key="<%= h(r.get("metric_key")) %>"
            data-operator="<%= h(r.get("operator")) %>"
            data-threshold1="<%= h(r.get("threshold1")) %>"
            data-threshold2="<%= h(r.get("threshold2")) %>"
            data-severity="<%= h(r.get("severity")) %>"
            data-source-token="<%= h(r.get("source_token")) %>"
            data-message-template="<%= h(r.get("message_template")) %>"
            data-description="<%= h(r.get("description")) %>">
            <td><%= rowIdx + 1 %></td>
            <td class="mono"><%= h(r.get("rule_code")) %></td>
            <td><%= h(r.get("rule_name")) %></td>
            <td class="mono"><%= h(r.get("category")) %></td>
            <td class="mono"><%= h(r.get("target_scope")) %></td>
            <td class="mono"><%= h(r.get("metric_display")) %></td>
            <td class="mono"><%= h(r.get("operator")) %></td>
            <td class="mono"><%= h(r.get("threshold1")) %></td>
            <td class="mono"><%= h(r.get("threshold2")) %></td>
            <td class="mono"><%= h(r.get("severity_display")) %></td>
            <td class="mono"><%= h(r.get("source_token")) %></td>
            <td class="mono"><%= h(r.get("resolved_input")) %></td>
            <td><%= h(r.get("message_template")) %></td>
            <td><% if ((Boolean)r.get("enabled")) { %><span class="badge b-on">사용</span><% } else { %><span class="badge b-off">미사용</span><% } %></td>
            <td><%= h(r.get("description")) %></td>
            <td class="mono"><%= h(r.get("updated_at")) %></td>
            <td>
                <div class="act-wrap">
                    <form method="POST" class="row-form" onclick="event.stopPropagation();">
                        <input type="hidden" name="action" value="toggle">
                        <input type="hidden" name="rule_id" value="<%= r.get("rule_id") %>">
                        <button type="submit" class="btn-sm"><%= ((Boolean)r.get("enabled")) ? "비활성" : "활성" %></button>
                    </form>
                    <form method="POST" class="row-form" onclick="event.stopPropagation();" onsubmit="return confirm('이 규칙을 삭제하시겠습니까?');">
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="rule_id" value="<%= r.get("rule_id") %>">
                        <button type="submit" class="btn-sm">삭제</button>
                    </form>
                </div>
            </td>
        </tr>
        <% } %>
        <% } %>
        </tbody>
    </table>
    </div>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
(function(){
  const aiForm = document.getElementById('aiRuleForm');
  const diForm = document.getElementById('diRuleForm');
  if (!aiForm || !diForm) return;
  const AI_DEFAULT_TEMPLATE = 'source=\\${source}, value=\\${value}, 기준 \\${operator} \\${t1}';
  const AI_BETWEEN_TEMPLATE = 'source=\\${source}, value=\\${value}, 기준 \\${operator} \\${t1} ~ \\${t2}';
  const AI_OUTSIDE_TEMPLATE = 'source=\\${source}, value=\\${value}, 기준 \\${t1} ~ \\${t2} 범위 이탈';
  const DI_DEFAULT_TEMPLATE = 'source=\\${tag}, item=\\${item}, panel=\\${panel}, addr=\\${address}, bit=\\${bit}';

  const ai = {
    form: aiForm,
    actionField: document.getElementById('aiActionField'),
    ruleIdField: document.getElementById('aiRuleIdField'),
    submitBtn: document.getElementById('aiSubmitBtn'),
    clearBtn: document.getElementById('aiClearBtn'),
    fields: {
      ruleCode: document.getElementById('ai_rule_code'),
      ruleName: document.getElementById('ai_rule_name'),
      category: document.getElementById('ai_category'),
      targetScope: document.getElementById('ai_target_scope'),
      metricKey: document.getElementById('ai_metric_key'),
      operator: document.getElementById('ai_operator'),
      threshold1: document.getElementById('ai_threshold1'),
      threshold2: document.getElementById('ai_threshold2'),
      severity: document.getElementById('ai_severity'),
      sourceToken: document.getElementById('ai_source_token'),
      messageTemplate: document.getElementById('ai_message_template'),
      description: document.getElementById('ai_description')
    }
  };

  const di = {
    form: diForm,
    actionField: document.getElementById('diActionField'),
    ruleIdField: document.getElementById('diRuleIdField'),
    submitBtn: document.getElementById('diSubmitBtn'),
    clearBtn: document.getElementById('diClearBtn'),
    fields: {
      ruleCode: document.getElementById('di_rule_code'),
      ruleName: document.getElementById('di_rule_name'),
      category: document.getElementById('di_category'),
      targetScope: document.getElementById('di_target_scope'),
      metricKey: document.getElementById('di_metric_key'),
      operator: document.getElementById('di_operator'),
      threshold1: document.getElementById('di_threshold1'),
      threshold2: document.getElementById('di_threshold2'),
      sourceToken: document.getElementById('di_source_token'),
      messageTemplate: document.getElementById('di_message_template'),
      description: document.getElementById('di_description')
    }
  };

  function clearSelectedRows() {
    document.querySelectorAll('.rule-table tbody tr.selected').forEach(tr => tr.classList.remove('selected'));
  }

  function setAddMode(ctx) {
    ctx.actionField.value = 'add';
    ctx.ruleIdField.value = '';
    ctx.submitBtn.textContent = (ctx === di) ? 'DI 규칙 추가' : 'AI 규칙 추가';
    ctx.fields.ruleCode.readOnly = false;
    if (ctx === ai && ctx.fields.messageTemplate) ctx.fields.messageTemplate.dataset.autoTemplate = '1';
    clearSelectedRows();
  }

  function normalizeAiTemplateByOperator(force){
    const operator = ai.fields.operator.value || '';
    const current = (ai.fields.messageTemplate.value || '').trim();
    const autoTemplate = ai.fields.messageTemplate.dataset.autoTemplate === '1';
    const isDefaultLike = !current || current === AI_DEFAULT_TEMPLATE || current === AI_BETWEEN_TEMPLATE || current === AI_OUTSIDE_TEMPLATE;
    const needsRangeUpgrade = (operator === 'BETWEEN' || operator === 'OUTSIDE') && current.indexOf('${t2}') < 0;
    if (!force && !autoTemplate && !isDefaultLike && !needsRangeUpgrade) return;
    if (operator === 'BETWEEN') {
      ai.fields.messageTemplate.value = AI_BETWEEN_TEMPLATE;
    } else if (operator === 'OUTSIDE') {
      ai.fields.messageTemplate.value = AI_OUTSIDE_TEMPLATE;
    } else {
      ai.fields.messageTemplate.value = AI_DEFAULT_TEMPLATE;
    }
    ai.fields.messageTemplate.dataset.autoTemplate = '1';
  }

  function setUpdateModeFromRow(tr) {
    const scope = (tr.dataset.targetScope || '').toUpperCase();
    const ctx = (scope === 'PLC') ? di : ai;
    ctx.actionField.value = 'update';
    ctx.ruleIdField.value = tr.dataset.ruleId || '';
    ctx.submitBtn.textContent = (ctx === di) ? '선택 DI 규칙 수정' : '선택 AI 규칙 수정';

    ctx.fields.ruleCode.value = tr.dataset.ruleCode || '';
    ctx.fields.ruleCode.readOnly = true;
    ctx.fields.ruleName.value = tr.dataset.ruleName || '';
    ctx.fields.category.value = tr.dataset.category || '';
    ctx.fields.targetScope.value = tr.dataset.targetScope || ((ctx === di) ? 'PLC' : 'METER');
    ctx.fields.metricKey.value = tr.dataset.metricKey || '';
    if (ctx.fields.operator) ctx.fields.operator.value = tr.dataset.operator || ((ctx === di) ? '=' : '>=');
    if (ctx.fields.threshold1) ctx.fields.threshold1.value = tr.dataset.threshold1 || ((ctx === di) ? '1' : '');
    if (ctx.fields.threshold2) ctx.fields.threshold2.value = tr.dataset.threshold2 || '';
    if (ctx.fields.severity) ctx.fields.severity.value = tr.dataset.severity || 'ALARM';
    if (ctx.fields.sourceToken) ctx.fields.sourceToken.value = tr.dataset.sourceToken || '';
    if (ctx.fields.messageTemplate) ctx.fields.messageTemplate.value = tr.dataset.messageTemplate || ((ctx === di) ? DI_DEFAULT_TEMPLATE : AI_DEFAULT_TEMPLATE);
    ctx.fields.description.value = tr.dataset.description || '';
    if (ctx === ai) {
      const mt = (tr.dataset.messageTemplate || '').trim();
      const isAutoLike = !mt || mt === AI_DEFAULT_TEMPLATE || mt === AI_BETWEEN_TEMPLATE || mt === AI_OUTSIDE_TEMPLATE || mt.indexOf('${t2}') < 0;
      ctx.fields.messageTemplate.dataset.autoTemplate = isAutoLike ? '1' : '0';
      normalizeAiTemplateByOperator(false);
    }

    clearSelectedRows();
    tr.classList.add('selected');
    syncAiSeverityUi();
  }

  document.querySelectorAll('.rule-table tbody tr.pickable').forEach(function(tr){
    tr.addEventListener('click', function(){
      setUpdateModeFromRow(tr);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  });

  ai.clearBtn.addEventListener('click', function(){
    ai.form.reset();
    ai.fields.targetScope.value = 'METER';
    ai.fields.category.value = 'POWER_QUALITY';
    ai.fields.messageTemplate.dataset.autoTemplate = '1';
    normalizeAiTemplateByOperator(true);
    syncAiSeverityUi();
    ai.fields.severity.value = 'ALARM';
    setAddMode(ai);
  });

  di.clearBtn.addEventListener('click', function(){
    di.form.reset();
    di.fields.targetScope.value = 'PLC';
    di.fields.operator.value = '=';
    di.fields.threshold1.value = '1';
    di.fields.threshold2.value = '';
    di.fields.sourceToken.value = '';
    di.fields.messageTemplate.value = DI_DEFAULT_TEMPLATE;
    di.fields.category.value = 'DI';
    setAddMode(di);
  });

  ai.fields.operator.addEventListener('change', function(){
    normalizeAiTemplateByOperator(false);
  });

  ai.fields.messageTemplate.addEventListener('input', function(){
    ai.fields.messageTemplate.dataset.autoTemplate = '0';
  });

  function syncAiSeverityUi(){
    const hasThreshold2 = !!((ai.fields.threshold2.value || '').trim());
    ai.fields.severity.disabled = hasThreshold2;
  }

  ai.fields.threshold2.addEventListener('input', syncAiSeverityUi);
  ai.fields.threshold2.addEventListener('change', syncAiSeverityUi);

  setAddMode(ai);
  setAddMode(di);
  ai.fields.messageTemplate.dataset.autoTemplate = '1';
  normalizeAiTemplateByOperator(false);
  syncAiSeverityUi();
})();
</script>
<%
    }
%>
</body>
</html>
