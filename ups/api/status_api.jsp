<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_json.jspf" %>
<%
StringBuilder json = new StringBuilder();
json.append("{\"ok\":true,\"items\":[");
boolean first = true;
try (Connection conn = openUpsDbConnection();
     PreparedStatement ps = conn.prepareStatement(
        "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.last_comm_status, m.measured_at, m.load_percent, m.battery_charge_percent " +
        "FROM dbo.ups_device d OUTER APPLY (SELECT TOP 1 * FROM dbo.ups_measurement m WHERE m.ups_id = d.ups_id ORDER BY m.measured_at DESC) m " +
        "WHERE d.enabled = 1 ORDER BY d.ups_name")) {
    try (ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            if (!first) json.append(',');
            first = false;
            json.append('{')
                .append("\"ups_id\":").append(rs.getInt("ups_id")).append(',')
                .append("\"ups_name\":\"").append(escJson(rs.getString("ups_name"))).append("\",")
                .append("\"location\":\"").append(escJson(rs.getString("location"))).append("\",")
                .append("\"ip_address\":\"").append(escJson(rs.getString("ip_address"))).append("\",")
                .append("\"last_comm_status\":\"").append(escJson(rs.getString("last_comm_status"))).append("\",")
                .append("\"measured_at\":\"").append(escJson(String.valueOf(rs.getObject("measured_at")))).append("\",")
                .append("\"load_percent\":").append(rs.getObject("load_percent") == null ? "null" : rs.getObject("load_percent")).append(',')
                .append("\"battery_charge_percent\":").append(rs.getObject("battery_charge_percent") == null ? "null" : rs.getObject("battery_charge_percent"))
                .append('}');
        }
    }
    json.append("]}");
} catch (Exception e) {
    json.setLength(0);
    json.append("{\"ok\":false,\"error\":\"").append(escJson(e.getMessage())).append("\"}");
}
out.print(json.toString());
%>
