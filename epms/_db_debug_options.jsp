<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*, java.util.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<!DOCTYPE html>
<html>
<head>
    <title>Database Meter Options Viewer</title>
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
    <h2>Meter Options from <code>meters</code> table</h2>
    <p class="meta">This shows the list of meters used to populate the dropdown in <code>meter_status.jsp</code>.</p>
<%
    try (Connection conn = openDbConnection()) {
        String sql = "SELECT meter_id, name, panel_name " +
                     "FROM meters " +
                     "WHERE UPPER(COALESCE(name, '')) LIKE '%VCB%' " +
                     "   OR UPPER(COALESCE(name, '')) LIKE '%ACB%' " +
                     "   OR UPPER(COALESCE(panel_name, '')) LIKE '%VCB%' " +
                     "   OR UPPER(COALESCE(panel_name, '')) LIKE '%ACB%' " +
                     "ORDER BY meter_id";

        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            try (ResultSet rs = ps.executeQuery()) {
%>
                    <table>
                        <thead>
                            <tr>
                                <th>Index</th>
                                <th>meter_id</th>
                                <th>name</th>
                                <th>panel_name</th>
                            </tr>
                        </thead>
                        <tbody>
<%
                    int index = 0;
                    while (rs.next()) {
%>
                            <tr>
                                <td><%= index %></td>
                                <td><strong><%= rs.getString("meter_id") %></strong></td>
                                <td><%= rs.getString("name") %></td>
                                <td><%= rs.getString("panel_name") %></td>
                            </tr>
<%
                        index++;
                    }
%>
                        </tbody>
                    </table>
<%
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
