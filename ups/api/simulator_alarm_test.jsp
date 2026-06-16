<%@ page import="epms.ups.UpsApiService" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
if (!isUpsTestApiAllowed(request)) {
    response.setStatus(403);
    out.print("{\"ok\":false,\"error\":\"forbidden\"}");
    return;
}
out.print(UpsApiService.simulatorAlarmTestJson(request.getParameter("code"), request.getParameter("active")));
%>
