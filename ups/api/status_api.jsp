<%@ page import="epms.ups.UpsApiService" %>
<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%
out.print(UpsApiService.statusJson());
%>
