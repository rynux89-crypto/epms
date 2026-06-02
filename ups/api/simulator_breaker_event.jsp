<%@ page import="java.sql.*" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_json.jspf" %>
<%!
    private String cleanBreakerName(String raw) {
        if (raw == null) return "";
        String s = raw.trim().toUpperCase(java.util.Locale.ROOT);
        if ("UIB".equals(s) || "UOB".equals(s) || "SSIB".equals(s) || "BF2".equals(s) || "MBB".equals(s) || "BB".equals(s)) return s;
        return "";
    }

    private String cleanState(String raw) {
        if (raw == null) return "";
        String s = raw.trim().toLowerCase(java.util.Locale.ROOT);
        if ("1".equals(s) || "true".equals(s) || "closed".equals(s) || "close".equals(s) || "on".equals(s)) return "Close";
        if ("0".equals(s) || "false".equals(s) || "open".equals(s) || "off".equals(s)) return "Open";
        return "";
    }
%>
<%
request.setCharacterEncoding("UTF-8");
if (!isUpsTestApiAllowed(request)) {
    response.setStatus(403);
    out.print("{\"ok\":false,\"error\":\"forbidden\"}");
    return;
}
String name = cleanBreakerName(request.getParameter("name"));
String before = cleanState(request.getParameter("before"));
String after = cleanState(request.getParameter("after"));
StringBuilder json = new StringBuilder();

if (name.isEmpty() || before.isEmpty() || after.isEmpty()) {
    json.append("{\"ok\":false,\"error\":\"invalid breaker event\"}");
    out.print(json.toString());
    return;
}
if (before.equals(after)) {
    json.append("{\"ok\":true,\"inserted\":false}");
    out.print(json.toString());
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
        json.append("{\"ok\":false,\"error\":\"simulator UPS is not registered\"}");
        out.print(json.toString());
        return;
    }

    String metricKey = "BB".equals(name) ? "battery_breaker_status" : "switchgear_status";
    String ruleCode = "BREAKER_" + name + "_CHANGE";
    String message = "차단기 " + name + " " + before + " -> " + after;
    try (PreparedStatement dup = conn.prepareStatement(
            "SELECT TOP 1 1 FROM dbo.ups_alarm_log " +
            "WHERE ups_id=? AND rule_code=? AND alarm_message=? AND status='EVENT' " +
            "AND occurred_at >= DATEADD(second, -3, sysdatetime())")) {
        dup.setInt(1, upsId.intValue());
        dup.setString(2, ruleCode);
        dup.setString(3, message);
        try (ResultSet rs = dup.executeQuery()) {
            if (rs.next()) {
                json.append("{\"ok\":true,\"inserted\":false,\"duplicate\":true}");
                out.print(json.toString());
                return;
            }
        }
    }
    try (PreparedStatement ps = conn.prepareStatement(
            "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
            "VALUES (?, ?, ?, 'INFO', ?, sysdatetime(), 'EVENT')")) {
        ps.setInt(1, upsId.intValue());
        ps.setString(2, ruleCode);
        ps.setString(3, metricKey);
        ps.setString(4, message);
        ps.executeUpdate();
    }
    json.append("{\"ok\":true,\"inserted\":true}");
} catch (Exception e) {
    json.setLength(0);
    json.append("{\"ok\":false,\"error\":\"").append(escJson(e.getMessage())).append("\"}");
}
out.print(json.toString());
%>
