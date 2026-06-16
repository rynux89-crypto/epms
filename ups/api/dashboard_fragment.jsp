<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
epms.ups.UpsDashboardModel dashModel = epms.ups.UpsDashboardViewService.build(request.getParameter("ups_id"));
epms.ups.UpsDashboardFragmentRenderModel fragmentModel = new epms.ups.UpsDashboardFragmentRenderModel(dashModel);
%>
<% if (dashModel.err != null) { %><div class="err-box"><%= h(dashModel.err) %></div><% } %>

<%@ include file="../includes/dashboard/kpi_cards.jspf" %>

<%@ include file="../includes/dashboard/main_cards.jspf" %>

<%@ include file="../includes/dashboard/bottom_cards.jspf" %>
