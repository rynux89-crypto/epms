<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%
    String query = request.getQueryString();
    String target = "/api/modbus";
    if (query != null && !query.trim().isEmpty()) {
        target += "?" + query;
    }
    request.getRequestDispatcher(target).forward(request, response);
%>
