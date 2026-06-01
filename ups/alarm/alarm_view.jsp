<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%
List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
String err = null;
try (Connection conn = openUpsDbConnection();
     PreparedStatement ps = conn.prepareStatement(
        "SELECT TOP 200 a.alarm_id, d.ups_name, a.severity, a.metric_key, a.alarm_message, a.occurred_at, a.cleared_at, a.status " +
        "FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ORDER BY a.occurred_at DESC")) {
    try (ResultSet rs = ps.executeQuery()) {
        ResultSetMetaData md = rs.getMetaData();
        while (rs.next()) {
            Map<String, Object> row = new HashMap<String, Object>();
            for (int i = 1; i <= md.getColumnCount(); i++) row.put(md.getColumnLabel(i), rs.getObject(i));
            rows.add(row);
        }
    }
} catch (Exception e) {
    err = e.getMessage();
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 알람</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div><h2>UPS 알람</h2><p class="muted">최근 알람 이력 200건을 표시합니다.</p></div>
        <div class="inline-actions"><button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button></div>
    </div>
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>
    <div class="panel">
        <table class="data-table">
            <thead><tr><th>ID</th><th>UPS</th><th>등급</th><th>지표</th><th>메시지</th><th>발생</th><th>해제</th><th>상태</th></tr></thead>
            <tbody>
            <% if (rows.isEmpty()) { %><tr><td colspan="8">알람 이력이 없습니다.</td></tr><% } %>
            <% for (Map<String, Object> r : rows) { %>
            <tr>
                <td><%= h(r.get("alarm_id")) %></td>
                <td><%= h(r.get("ups_name")) %></td>
                <td><%= h(r.get("severity")) %></td>
                <td><%= h(r.get("metric_key")) %></td>
                <td><%= h(r.get("alarm_message")) %></td>
                <td><%= h(r.get("occurred_at")) %></td>
                <td><%= h(r.get("cleared_at")) %></td>
                <td><%= h(r.get("status")) %></td>
            </tr>
            <% } %>
            </tbody>
        </table>
    </div>
</div>
</body>
</html>
