<%@ page import="java.sql.*" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_json.jspf" %>
<%!
    private String cleanScenario(String raw) {
        if (raw == null) return "";
        String s = raw.trim().toLowerCase(java.util.Locale.ROOT);
        if ("normal".equals(s) || "battery".equals(s) || "low_battery".equals(s) ||
            "overload".equals(s) || "input_fault".equals(s) || "output_fault".equals(s) ||
            "bypass_fault".equals(s) || "power_module_fault".equals(s) || "critical".equals(s)) return s;
        return "";
    }

    private String scenarioLabel(String s) {
        if ("normal".equals(s)) return "정상";
        if ("battery".equals(s)) return "배터리 운전";
        if ("low_battery".equals(s)) return "배터리 부족";
        if ("overload".equals(s)) return "과부하";
        if ("input_fault".equals(s)) return "입력 이상";
        if ("output_fault".equals(s)) return "출력 이상";
        if ("bypass_fault".equals(s)) return "바이패스 이상";
        if ("power_module_fault".equals(s)) return "파워 모듈 이상";
        if ("critical".equals(s)) return "중요 알람";
        return s;
    }
%>
<%
request.setCharacterEncoding("UTF-8");
if (!isUpsTestApiAllowed(request)) {
    response.setStatus(403);
    out.print("{\"ok\":false,\"error\":\"forbidden\"}");
    return;
}
String before = cleanScenario(request.getParameter("before"));
String after = cleanScenario(request.getParameter("after"));
StringBuilder json = new StringBuilder();

if (after.isEmpty()) {
    json.append("{\"ok\":false,\"error\":\"invalid scenario event\"}");
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

    String metricKey = "ups_operation_mode";
    String ruleCode = "UPS_SCENARIO_CHANGE";
    String message = before.isEmpty()
        ? scenarioLabel(after)
        : scenarioLabel(before) + " -> " + scenarioLabel(after);
    try (PreparedStatement dup = conn.prepareStatement(
            "SELECT TOP 1 1 FROM dbo.ups_alarm_log " +
            "WHERE ups_id=? AND rule_code=? AND alarm_message=? AND status='EVENT' " +
            "AND occurred_at >= DATEADD(second, -15, sysdatetime())")) {
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
