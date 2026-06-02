<%@ page import="java.sql.*" %>
<%@ page import="epms.ups.UpsCollectorService" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_json.jspf" %>
<%!
    private int countTable(Connection conn, String tableName) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM " + tableName);
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }
%>
<%
if (!isUpsTestApiAllowed(request)) {
    response.setStatus(403);
    out.print("{\"ok\":false,\"error\":\"forbidden\"}");
    return;
}
StringBuilder json = new StringBuilder();
int beforeMeasurements = 0;
int afterMeasurements = 0;
int beforeComm = 0;
int afterComm = 0;
try (Connection conn = openUpsDbConnection()) {
    beforeMeasurements = countTable(conn, "dbo.ups_measurement");
    beforeComm = countTable(conn, "dbo.ups_comm_status");
}
try {
    long started = System.currentTimeMillis();
    application.setAttribute("ups.collector.lastStartAt", new java.sql.Timestamp(started));
    new UpsCollectorService().pollEnabledDevices();
    try (Connection conn = openUpsDbConnection()) {
        afterMeasurements = countTable(conn, "dbo.ups_measurement");
        afterComm = countTable(conn, "dbo.ups_comm_status");
    }
    application.setAttribute("ups.collector.status", "OK");
    application.setAttribute("ups.collector.lastSuccessAt", new java.sql.Timestamp(System.currentTimeMillis()));
    application.setAttribute("ups.collector.lastDurationMs", Long.valueOf(System.currentTimeMillis() - started));
    application.removeAttribute("ups.collector.lastError");
    json.append("{\"ok\":true")
        .append(",\"measurement_before\":").append(beforeMeasurements)
        .append(",\"measurement_after\":").append(afterMeasurements)
        .append(",\"measurement_inserted\":").append(afterMeasurements - beforeMeasurements)
        .append(",\"comm_before\":").append(beforeComm)
        .append(",\"comm_after\":").append(afterComm)
        .append("}");
} catch (Exception e) {
    application.setAttribute("ups.collector.status", "ERROR");
    application.setAttribute("ups.collector.lastErrorAt", new java.sql.Timestamp(System.currentTimeMillis()));
    application.setAttribute("ups.collector.lastError", e.getMessage());
    json.setLength(0);
    json.append("{\"ok\":false")
        .append(",\"measurement_before\":").append(beforeMeasurements)
        .append(",\"comm_before\":").append(beforeComm)
        .append(",\"error\":\"").append(escJson(e.getMessage())).append("\"}");
}
out.print(json.toString());
%>
