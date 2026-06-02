<%@ page import="java.sql.*" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_json.jspf" %>
<%!
    private String cleanRuleCode(String raw) {
        if (raw == null) return "";
        String s = raw.trim().toUpperCase(java.util.Locale.ROOT);
        return s.matches("[A-Z0-9_]{2,80}") ? s : "";
    }

    private boolean activeParam(String raw) {
        if (raw == null) return false;
        String s = raw.trim().toLowerCase(java.util.Locale.ROOT);
        return "1".equals(s) || "true".equals(s) || "yes".equals(s) || "on".equals(s) || "active".equals(s);
    }

    private String displayValue(Object raw) {
        if (raw == null) return "TEST";
        try {
            java.math.BigDecimal value = raw instanceof java.math.BigDecimal
                ? (java.math.BigDecimal)raw
                : new java.math.BigDecimal(String.valueOf(raw));
            return value.setScale(1, java.math.RoundingMode.HALF_UP).toPlainString();
        } catch (Exception ignore) {
            return String.valueOf(raw);
        }
    }

    private String renderMessage(String template, Object threshold) {
        String msg = template == null || template.trim().isEmpty() ? "시뮬레이터 알람 테스트" : template;
        String value = displayValue(threshold);
        msg = msg.replace("{value}", value).replace("{threshold}", value).replace("{metric}", "");
        return msg.length() > 500 ? msg.substring(0, 500) : msg;
    }
%>
<%
request.setCharacterEncoding("UTF-8");
if (!isUpsTestApiAllowed(request)) {
    response.setStatus(403);
    out.print("{\"ok\":false,\"error\":\"forbidden\"}");
    return;
}
String ruleCode = cleanRuleCode(request.getParameter("code"));
boolean active = activeParam(request.getParameter("active"));
StringBuilder json = new StringBuilder();

if (ruleCode.isEmpty()) {
    out.print("{\"ok\":false,\"error\":\"invalid rule code\"}");
    return;
}

try (Connection conn = openUpsDbConnection()) {
    Integer upsId = null;
    try (PreparedStatement find = conn.prepareStatement(
            "SELECT TOP 1 ups_id FROM dbo.ups_device WHERE ip_address='127.0.0.1' AND modbus_port=1502 AND unit_id=1 ORDER BY ups_id")) {
        try (ResultSet rs = find.executeQuery()) {
            if (rs.next()) upsId = Integer.valueOf(rs.getInt("ups_id"));
        }
    }
    if (upsId == null) {
        out.print("{\"ok\":false,\"error\":\"simulator UPS is not registered\"}");
        return;
    }

    String metricKey = null;
    String severity = null;
    String message = null;
    try (PreparedStatement rule = conn.prepareStatement(
            "SELECT TOP 1 metric_key, severity, message_template, threshold_value FROM dbo.ups_alarm_rule WHERE rule_code=?")) {
        rule.setString(1, ruleCode);
        try (ResultSet rs = rule.executeQuery()) {
            if (rs.next()) {
                metricKey = rs.getString("metric_key");
                severity = rs.getString("severity");
                message = renderMessage(rs.getString("message_template"), rs.getObject("threshold_value"));
            }
        }
    }
    if (metricKey == null) {
        out.print("{\"ok\":false,\"error\":\"alarm rule not found\"}");
        return;
    }

    if (active) {
        try (PreparedStatement exists = conn.prepareStatement(
                "SELECT TOP 1 1 FROM dbo.ups_alarm_log WHERE ups_id=? AND rule_code=? AND status='ACTIVE'")) {
            exists.setInt(1, upsId.intValue());
            exists.setString(2, ruleCode);
            try (ResultSet rs = exists.executeQuery()) {
                if (rs.next()) {
                    out.print("{\"ok\":true,\"inserted\":false,\"alreadyActive\":true}");
                    return;
                }
            }
        }
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
                "VALUES (?, ?, ?, ?, ?, sysdatetime(), 'ACTIVE')")) {
            ps.setInt(1, upsId.intValue());
            ps.setString(2, ruleCode);
            ps.setString(3, metricKey);
            ps.setString(4, severity == null ? "WARNING" : severity);
            ps.setString(5, message);
            ps.executeUpdate();
        }
        json.append("{\"ok\":true,\"inserted\":true,\"status\":\"ACTIVE\"}");
    } else {
        int updated = 0;
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.ups_alarm_log SET status='CLEARED', cleared_at=sysdatetime() " +
                "WHERE ups_id=? AND rule_code=? AND status='ACTIVE'")) {
            ps.setInt(1, upsId.intValue());
            ps.setString(2, ruleCode);
            updated = ps.executeUpdate();
        }
        json.append("{\"ok\":true,\"cleared\":").append(updated).append(",\"status\":\"CLEARED\"}");
    }
} catch (Exception e) {
    json.setLength(0);
    json.append("{\"ok\":false,\"error\":\"").append(escJson(e.getMessage())).append("\"}");
}
out.print(json.toString());
%>
