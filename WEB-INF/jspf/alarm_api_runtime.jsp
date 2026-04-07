<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%
response.setContentType("application/json; charset=UTF-8");
response.setCharacterEncoding("UTF-8");
out.print("{\"ok\":false,\"error\":\"alarm_api_runtime.jsp is retired; use /api/alarm or epms/alarm_api.jsp\"}");
%>
