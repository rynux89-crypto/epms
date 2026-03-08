<%@ include file="../includes/header.jsp" %>
<div class="container">
    <h2><%= request.getAttribute("pageTitle") %></h2>
    <div class="content">
        <jsp:include page="<%= request.getAttribute("contentPage") %>" />
    </div>
</div>
<%@ include file="../includes/footer.jsp" %>