<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%
    String qs = request.getQueryString();
    if (qs == null || qs.trim().isEmpty()) {
        response.sendRedirect("event_detail.jsp");
    } else {
        response.sendRedirect("event_detail.jsp?" + qs);
    }
%>
