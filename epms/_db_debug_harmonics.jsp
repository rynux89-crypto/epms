<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*, java.util.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<!DOCTYPE html>
<html>
<head>
    <title>Database Harmonic Data Viewer</title>
    <style>
        body { font-family: sans-serif; padding: 20px; }
        table { border-collapse: collapse; margin-top: 15px; }
        th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
        th { background-color: #f2f2f2; }
        .container { border: 1px solid #ddd; padding: 15px; border-radius: 8px; }
        h2 { color: #333; }
        .meta { font-size: 0.9em; color: #555; }
    </style>
</head>
<body>

<div class="container">
    <h2>Raw Harmonic Data from <code>vw_harmonic_measurements</code></h2>

<%
    String meterId = request.getParameter("meter_id");
    if (meterId == null || meterId.trim().isEmpty()) {
        out.println("<p style='color:red;'><b>Error:</b> Please provide a 'meter_id' parameter in the URL.</p>");
        return;
    }
%>
    <p class="meta">
        Querying for <strong>meter_id = <%= meterId %></strong><br>
        <code>SELECT TOP 1 * FROM vw_harmonic_measurements WHERE meter_id = ? ORDER BY measured_at DESC</code>
    </p>
<%
    try (Connection conn = openDbConnection()) {
        String sql = "SELECT TOP 1 * FROM vw_harmonic_measurements WHERE meter_id = ? ORDER BY measured_at DESC";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, meterId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    ResultSetMetaData rsmd = rs.getMetaData();
                    int columnCount = rsmd.getColumnCount();
%>
                    <table>
                        <thead>
                            <tr>
                                <th>Column Name</th>
                                <th>Value</th>
                            </tr>
                        </thead>
                        <tbody>
<%
                    for (int i = 1; i <= columnCount; i++) {
                        String colName = rsmd.getColumnName(i);
                        Object colValue = rs.getObject(i);
%>
                            <tr>
                                <td><%= colName %></td>
                                <td><%= (colValue != null ? colValue.toString() : "NULL") %></td>
                            </tr>
<%
                    }
%>
                        </tbody>
                    </table>
<%
                } else {
                    out.println("<p style='font-weight:bold;color:#b42318;'>No data found for the specified meter_id.</p>");
                }
            }
        }
    } catch (Exception e) {
        out.println("<p style='color:red;'><b>An exception occurred:</b><br><pre>" + e.toString() + "</pre></p>");
        e.printStackTrace();
    }
%>
</div>

</body>
</html>
