<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static String normKey(String v) {
        if (v == null) return "";
        return v.trim().toUpperCase(Locale.ROOT);
    }

    private static String classifyMetricKey(String key) {
        String k = normKey(key);
        if (k.isEmpty()) return "기타";

        if (k.contains("UNBAL")) return "불평형율";
        if (k.contains("VARIATION") || k.endsWith("_VAR") || k.startsWith("V_VAR") || k.startsWith("I_VAR")) return "변동율";
        if (k.contains("THD") || k.startsWith("H_")) return "고조파왜형율";
        if (k.equals("PF") || k.contains("POWER_FACTOR") || k.startsWith("PF_")) return "역률";
        if (k.equals("HZ") || k.contains("FREQUENCY")) return "주파수";
        if (k.contains("PEAK") || k.contains("MAX_POWER")) return "전력피크";
        if (k.startsWith("DI_") || k.endsWith("_DI") || k.contains("TRIP") || k.contains("OCR") || k.contains("OCGR") || k.contains("OVR")) return "DI/보호";

        if (k.contains("VOLT") || k.startsWith("V") || k.startsWith("PV")) return "전압값";
        if (k.contains("CURR") || k.startsWith("A") || k.startsWith("PI")) return "전류값";

        return "기타";
    }

    private static List<String> loadSystemMetricKeys(Connection conn) throws Exception {
        TreeSet<String> set = new TreeSet<>();
        // Fixed keys used by DI/protection logic.
        set.add("DI_TRIP");
        set.add("DI_TR_ALARM");
        set.add("DI_OCR_ALL_ON");
        set.add("DI_OCGR_ALL_ON");
        set.add("DI_OVR_ALL_ON");
        set.add("DI_ELD_ON");
        set.add("DI_TM_ON");
        set.add("DI_LIGHT_ON");
        // Virtual grouped keys for one-rule-per-kind operation.
        set.add("VOLTAGE");
        set.add("CURRENT");
        set.add("UNBALANCE");
        set.add("VARIATION");
        set.add("THD");
        set.add("THD_VOLTAGE");
        set.add("THD_CURRENT");
        set.add("POWER_FACTOR");
        set.add("FREQUENCY_GROUP");
        set.add("PEAK");
        set.add("MAX_POWER");

        // Keep existing keys selectable so current rules remain editable.
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
        req.threshold1 = parseNullableDouble(request.getParameter("threshold1"));
        req.threshold2 = parseNullableDouble(request.getParameter("threshold2"));
        req.durationSec = parseNullableInt(request.getParameter("duration_sec"));
        req.hysteresis = parseNullableDouble(request.getParameter("hysteresis"));
        req.severity = request.getParameter("severity");
        req.sourceToken = request.getParameter("source_token");
        req.messageTemplate = request.getParameter("message_template");
        req.description = request.getParameter("description");
        return req;
    }

    private static String validateAlarmRuleRequest(AlarmRuleRequest req, Set<String> metricKeySet) {
        if (req == null) return "요청이 올바르지 않습니다.";
        String action = req.action == null ? "" : req.action;
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
            if (metricKeyNorm.isEmpty() || !metricKeySet.contains(metricKeyNorm)) {
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
            ps.setString(11, (req.severity == null || req.severity.trim().isEmpty()) ? "WARN" : req.severity.trim().toUpperCase(Locale.ROOT));
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
            ps.setString(10, req.severity);
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
    request.setCharacterEncoding("UTF-8");

    String self = request.getRequestURI();
    String message = request.getParameter("msg");
    String error = request.getParameter("err");
    List<Map<String, Object>> rows = new ArrayList<>();
    List<String> metricKeys = new ArrayList<>();
    LinkedHashMap<String, List<String>> groupedMetricKeys = new LinkedHashMap<>();

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

        String seedIfEmptySql =
            "IF NOT EXISTS (SELECT 1 FROM dbo.alarm_rule) " +
            "BEGIN " +
            "  INSERT INTO dbo.alarm_rule " +
            "  (rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, threshold2, duration_sec, hysteresis, severity, enabled, description) " +
            "  VALUES " +
            "  ('OCR', N'OCR Over Current', 'PROTECTION', 'METER', 'current_max', '>=', 100.0, NULL, 3, 5.0, 'ALARM', 1, N'Over-current exceeds threshold'), " +
            "  ('OCGR', N'OCGR Ground Over Current', 'PROTECTION', 'METER', 'current_ground', '>=', 30.0, NULL, 2, 3.0, 'ALARM', 1, N'Ground current exceeds threshold'), " +
            "  ('OVR_DI', N'OVR Signal', 'PROTECTION', 'PLC', 'DI_OVR_ALL_ON', '=', 1.0, NULL, 0, NULL, 'ALARM', 1, N'OVR bit group all on'), " +
            "  ('TRIP_DI', N'TRIP Signal', 'PROTECTION', 'PLC', 'di_trip', '=', 1.0, NULL, 0, NULL, 'ALARM', 1, N'DI trip signal on'), " +
            "  ('ELD_DI', N'ELD Leakage Signal', 'PROTECTION', 'PLC', 'DI_ELD_ON', '=', 1.0, NULL, 0, NULL, 'ALARM', 1, N'ELD leakage bit on'), " +
            "  ('TM_DI', N'TM Temperature Signal', 'PROTECTION', 'PLC', 'DI_TM_ON', '=', 1.0, NULL, 0, NULL, 'ALARM', 1, N'Transformer temperature alarm bit on'), " +
            "  ('LIGHT_DI', N'Warning Light Signal', 'PROTECTION', 'PLC', 'DI_LIGHT_ON', '=', 1.0, NULL, 0, NULL, 'WARN', 1, N'Warning light signal on'), " +
            "  ('PF_LOW', N'Power Factor Low', 'POWER_QUALITY', 'METER', 'pf_total', '<', 0.90, NULL, 10, 0.02, 'WARN', 1, N'Power factor below threshold'), " +
            "  ('V_UNBAL', N'Voltage Unbalance', 'POWER_QUALITY', 'METER', 'voltage_unbalance_rate', '>=', 2.0, NULL, 10, 0.5, 'WARN', 1, N'Voltage unbalance over threshold'), " +
            "  ('V_VAR', N'Voltage Variation', 'POWER_QUALITY', 'METER', 'voltage_variation_rate', '>=', 10.0, NULL, 10, 2.0, 'WARN', 1, N'Voltage variation over threshold'), " +
            "  ('I_VAR', N'Current Variation', 'POWER_QUALITY', 'METER', 'current_variation_rate', '>=', 20.0, NULL, 10, 3.0, 'WARN', 1, N'Current variation over threshold'), " +
            "  ('PEAK_HIGH', N'Peak Power High', 'POWER_QUALITY', 'METER', 'PEAK', '>=', 9000.0, NULL, 10, 100.0, 'WARN', 1, N'Peak power exceeds threshold'), " +
            "  ('THD_V', N'Voltage THD', 'HARMONIC', 'METER', 'thd_voltage_max', '>=', 5.0, NULL, 10, 1.0, 'WARN', 1, N'Voltage THD over threshold'), " +
            "  ('THD_I', N'Current THD', 'HARMONIC', 'METER', 'thd_current_max', '>=', 20.0, NULL, 10, 2.0, 'WARN', 1, N'Current THD over threshold'); " +
            "END";
        try (Statement st = conn.createStatement()) {
            st.execute(seedIfEmptySql);
        }

        String ensureCoreSql =
            "INSERT INTO dbo.alarm_rule " +
            "(rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, threshold2, duration_sec, hysteresis, severity, enabled, description, updated_at) " +
            "SELECT v.rule_code, v.rule_name, v.category, v.target_scope, v.metric_key, v.operator, v.threshold1, v.threshold2, v.duration_sec, v.hysteresis, v.severity, 1, v.description, SYSUTCDATETIME() " +
            "FROM (VALUES " +
            "  ('OCR', N'OCR Over Current', 'PROTECTION', 'METER', 'current_max', '>=', CAST(100.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 3, CAST(5.0 AS DECIMAL(18,6)), 'ALARM', N'Over-current exceeds threshold'), " +
            "  ('OCGR', N'OCGR Ground Over Current', 'PROTECTION', 'METER', 'current_ground', '>=', CAST(30.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 2, CAST(3.0 AS DECIMAL(18,6)), 'ALARM', N'Ground current exceeds threshold'), " +
            "  ('OVR_DI', N'OVR Signal', 'PROTECTION', 'PLC', 'DI_OVR_ALL_ON', '=', CAST(1.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 0, CAST(NULL AS DECIMAL(18,6)), 'ALARM', N'OVR bit group all on'), " +
            "  ('TRIP_DI', N'TRIP Signal', 'PROTECTION', 'PLC', 'DI_TRIP', '=', CAST(1.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 0, CAST(NULL AS DECIMAL(18,6)), 'ALARM', N'DI trip signal on'), " +
            "  ('ELD_DI', N'ELD Leakage Signal', 'PROTECTION', 'PLC', 'DI_ELD_ON', '=', CAST(1.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 0, CAST(NULL AS DECIMAL(18,6)), 'ALARM', N'ELD leakage bit on'), " +
            "  ('TM_DI', N'TM Temperature Signal', 'PROTECTION', 'PLC', 'DI_TM_ON', '=', CAST(1.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 0, CAST(NULL AS DECIMAL(18,6)), 'ALARM', N'Transformer temperature alarm bit on'), " +
            "  ('LIGHT_DI', N'Warning Light Signal', 'PROTECTION', 'PLC', 'DI_LIGHT_ON', '=', CAST(1.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 0, CAST(NULL AS DECIMAL(18,6)), 'WARN', N'Warning light signal on'), " +
            "  ('PEAK_HIGH', N'Peak Power High', 'POWER_QUALITY', 'METER', 'PEAK', '>=', CAST(9000.0 AS DECIMAL(18,6)), CAST(NULL AS DECIMAL(18,6)), 10, CAST(100.0 AS DECIMAL(18,6)), 'WARN', N'Peak power exceeds threshold') " +
            ") AS v(rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, threshold2, duration_sec, hysteresis, severity, description) " +
            "WHERE NOT EXISTS (SELECT 1 FROM dbo.alarm_rule x WHERE x.rule_code = v.rule_code)";
        try (Statement st = conn.createStatement()) {
            st.executeUpdate(ensureCoreSql);
        }

        metricKeys = loadSystemMetricKeys(conn);
        Set<String> metricKeySet = new HashSet<>(metricKeys);
        groupedMetricKeys.put("전압값", new ArrayList<String>());
        groupedMetricKeys.put("전류값", new ArrayList<String>());
        groupedMetricKeys.put("불평형율", new ArrayList<String>());
        groupedMetricKeys.put("변동율", new ArrayList<String>());
        groupedMetricKeys.put("고조파왜형율", new ArrayList<String>());
        groupedMetricKeys.put("역률", new ArrayList<String>());
        groupedMetricKeys.put("주파수", new ArrayList<String>());
        groupedMetricKeys.put("전력피크", new ArrayList<String>());
        groupedMetricKeys.put("DI/보호", new ArrayList<String>());
        groupedMetricKeys.put("기타", new ArrayList<String>());
        for (String mk : metricKeys) {
            String g = classifyMetricKey(mk);
            List<String> bucket = groupedMetricKeys.get(g);
            if (bucket == null) bucket = groupedMetricKeys.get("기타");
            bucket.add(mk);
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

        String q =
            "SELECT rule_id, rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, threshold2, duration_sec, " +
            "       hysteresis, severity, source_token, message_template, enabled, description, updated_at " +
            "FROM dbo.alarm_rule ORDER BY rule_id";
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
                r.put("operator", rs.getString("operator"));
                r.put("threshold1", rs.getObject("threshold1"));
                r.put("threshold2", rs.getObject("threshold2"));
                r.put("duration_sec", rs.getInt("duration_sec"));
                r.put("hysteresis", rs.getObject("hysteresis"));
                r.put("severity", rs.getString("severity"));
                r.put("source_token", rs.getString("source_token"));
                r.put("message_template", rs.getString("message_template"));
                r.put("enabled", rs.getBoolean("enabled"));
                r.put("description", rs.getString("description"));
                r.put("updated_at", rs.getTimestamp("updated_at"));
                rows.add(r);
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
        .toolbar { display: grid; grid-template-columns: repeat(7, minmax(120px, 1fr)); gap: 6px; align-items: end; }
        .toolbar .full { grid-column: 1 / -1; }
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
        .rule-table td { font-size: 12px; vertical-align: middle; }
        .act-wrap { display: flex; gap: 4px; justify-content: center; flex-wrap: wrap; }
        .btn-sm { padding: 4px 8px; font-size: 11px; }
        .row-form { margin: 0; padding: 0; box-shadow: none; background: transparent; display: inline; }
        .rule-table tbody tr.pickable { cursor: pointer; }
        .rule-table tbody tr.pickable:hover { background: #f5f9ff; }
        .rule-table tbody tr.selected { background: #eaf3ff; }
        .is-disabled { opacity: 0.6; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🚨 알람 규칙 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/alarm_view.jsp'">알람 목록</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="note-box">
        알람 규칙을 관리합니다. 표의 행을 클릭하면 상단 입력창에서 수정됩니다.<br>
        2단계 규칙: <b>임계값1=ALARM, 임계값2=CRITICAL</b> 기준으로 판정됩니다. 임계값2를 비우면 단일 임계 규칙입니다.
    </div>

    <% if (message != null && !message.trim().isEmpty()) { %>
    <div class="ok-box"><%= h(message) %></div>
    <% } %>
    <% if (error != null && !error.trim().isEmpty()) { %>
    <div class="err-box"><%= h(error) %></div>
    <% } %>

    <form method="POST" id="ruleForm">
        <input type="hidden" name="action" id="actionField" value="add">
        <input type="hidden" name="rule_id" id="ruleIdField" value="">
        <div class="toolbar">
            <input id="f_rule_code" name="rule_code" placeholder="규칙 코드 (예: PF_LOW)" required class="mono">
            <input id="f_rule_name" name="rule_name" placeholder="규칙명" required>
            <input id="f_category" name="category" placeholder="분류" value="POWER_QUALITY" required class="mono">
            <input id="f_target_scope" name="target_scope" placeholder="적용범위" value="METER" required class="mono">
            <select id="f_metric_key" name="metric_key" required class="mono">
                <option value="">지표키 선택</option>
                <% for (Map.Entry<String, List<String>> ge : groupedMetricKeys.entrySet()) { %>
                <% if (ge.getValue() == null || ge.getValue().isEmpty()) continue; %>
                <optgroup label="<%= h(ge.getKey()) %>">
                <% for (String mk : ge.getValue()) { %>
                <option value="<%= h(mk) %>"><%= h(mk) %></option>
                <% } %>
                </optgroup>
                <% } %>
            </select>
            <select id="f_operator" name="operator" class="mono">
                <option value=">=">&gt;=</option>
                <option value=">">&gt;</option>
                <option value="<">&lt;</option>
                <option value="<=">&lt;=</option>
                <option value="=">=</option>
                <option value="BETWEEN">BETWEEN</option>
            </select>
            <select id="f_severity" name="severity" class="mono">
                <option value="WARN">WARN</option>
                <option value="ALARM">ALARM</option>
                <option value="CRITICAL">CRITICAL</option>
            </select>
            <input id="f_threshold1" type="number" step="0.0001" name="threshold1" placeholder="임계값1 (ALARM)">
            <input id="f_threshold2" type="number" step="0.0001" name="threshold2" placeholder="임계값2 (CRITICAL)">
            <input id="f_duration_sec" type="number" min="0" name="duration_sec" value="0" placeholder="지속시간(초)">
            <input id="f_hysteresis" type="number" step="0.0001" name="hysteresis" placeholder="히스테리시스">
            <input id="f_source_token" name="source_token" placeholder="연결 토큰/태그" class="mono">
            <input id="f_message_template" name="message_template" placeholder="메시지 템플릿">
            <input id="f_description" name="description" placeholder="설명" class="full">
            <div class="full form-actions">
                <button type="submit" id="submitBtn">규칙 추가</button>
                <button type="button" id="clearBtn">선택 해제</button>
            </div>
        </div>
    </form>

    <table class="rule-table">
        <thead>
        <tr>
            <th>규칙 ID</th>
            <th>규칙 코드</th>
            <th>규칙명</th>
            <th>분류</th>
            <th>적용범위</th>
            <th>지표키</th>
            <th>연산자</th>
            <th>임계값1(ALARM)</th>
            <th>임계값2(CRITICAL)</th>
            <th>지속시간(초)</th>
            <th>히스테리시스</th>
            <th>기본심각도(단일임계)</th>
            <th>연결토큰</th>
            <th>메시지템플릿</th>
            <th>사용여부</th>
            <th>설명</th>
            <th>수정시각</th>
            <th>작업</th>
        </tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
        <tr><td colspan="18">등록된 알람 규칙이 없습니다.</td></tr>
        <% } else { %>
        <% for (Map<String, Object> r : rows) { %>
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
            data-duration-sec="<%= h(r.get("duration_sec")) %>"
            data-hysteresis="<%= h(r.get("hysteresis")) %>"
            data-severity="<%= h(r.get("severity")) %>"
            data-source-token="<%= h(r.get("source_token")) %>"
            data-message-template="<%= h(r.get("message_template")) %>"
            data-description="<%= h(r.get("description")) %>">
            <td><%= r.get("rule_id") %></td>
            <td class="mono"><%= h(r.get("rule_code")) %></td>
            <td><%= h(r.get("rule_name")) %></td>
            <td class="mono"><%= h(r.get("category")) %></td>
            <td class="mono"><%= h(r.get("target_scope")) %></td>
            <td class="mono"><%= h(r.get("metric_key")) %></td>
            <td class="mono"><%= h(r.get("operator")) %></td>
            <td class="mono"><%= h(r.get("threshold1")) %></td>
            <td class="mono"><%= h(r.get("threshold2")) %></td>
            <td class="mono"><%= h(r.get("duration_sec")) %></td>
            <td class="mono"><%= h(r.get("hysteresis")) %></td>
            <td class="mono"><%= h(r.get("severity")) %></td>
            <td class="mono"><%= h(r.get("source_token")) %></td>
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
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
(function(){
  const form = document.getElementById('ruleForm');
  if (!form) return;

  const actionField = document.getElementById('actionField');
  const ruleIdField = document.getElementById('ruleIdField');
  const submitBtn = document.getElementById('submitBtn');
  const clearBtn = document.getElementById('clearBtn');

  const f = {
    ruleCode: document.getElementById('f_rule_code'),
    ruleName: document.getElementById('f_rule_name'),
    category: document.getElementById('f_category'),
    targetScope: document.getElementById('f_target_scope'),
    metricKey: document.getElementById('f_metric_key'),
    operator: document.getElementById('f_operator'),
    severity: document.getElementById('f_severity'),
    threshold1: document.getElementById('f_threshold1'),
    threshold2: document.getElementById('f_threshold2'),
    durationSec: document.getElementById('f_duration_sec'),
    hysteresis: document.getElementById('f_hysteresis'),
    sourceToken: document.getElementById('f_source_token'),
    messageTemplate: document.getElementById('f_message_template'),
    description: document.getElementById('f_description')
  };

  function syncSeverityMode() {
    const dual = f.threshold2.value !== '' && f.threshold2.value !== null;
    f.severity.disabled = dual;
    f.severity.classList.toggle('is-disabled', dual);
    f.severity.title = dual ? '임계값2가 있으면 단계(ALARM/CRITICAL)가 임계값으로 자동 판정됩니다.' : '';
  }

  function setAddMode() {
    actionField.value = 'add';
    ruleIdField.value = '';
    submitBtn.textContent = '규칙 추가';
    f.ruleCode.readOnly = false;
    document.querySelectorAll('.rule-table tbody tr.selected').forEach(tr => tr.classList.remove('selected'));
    syncSeverityMode();
  }

  function setUpdateModeFromRow(tr) {
    actionField.value = 'update';
    ruleIdField.value = tr.dataset.ruleId || '';
    submitBtn.textContent = '선택 규칙 수정';

    f.ruleCode.value = tr.dataset.ruleCode || '';
    f.ruleCode.readOnly = true;
    f.ruleName.value = tr.dataset.ruleName || '';
    f.category.value = tr.dataset.category || '';
    f.targetScope.value = tr.dataset.targetScope || '';
    f.metricKey.value = tr.dataset.metricKey || '';
    f.operator.value = tr.dataset.operator || '>=';
    f.severity.value = tr.dataset.severity || 'WARN';
    f.threshold1.value = tr.dataset.threshold1 || '';
    f.threshold2.value = tr.dataset.threshold2 || '';
    f.durationSec.value = tr.dataset.durationSec || '0';
    f.hysteresis.value = tr.dataset.hysteresis || '';
    f.sourceToken.value = tr.dataset.sourceToken || '';
    f.messageTemplate.value = tr.dataset.messageTemplate || '';
    f.description.value = tr.dataset.description || '';

    document.querySelectorAll('.rule-table tbody tr.selected').forEach(x => x.classList.remove('selected'));
    tr.classList.add('selected');
    syncSeverityMode();
  }

  document.querySelectorAll('.rule-table tbody tr.pickable').forEach(function(tr){
    tr.addEventListener('click', function(){
      setUpdateModeFromRow(tr);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  });

  f.threshold2.addEventListener('input', syncSeverityMode);

  clearBtn.addEventListener('click', function(){
    form.reset();
    setAddMode();
  });

  setAddMode();
})();
</script>
</body>
</html>
