<%@ include file="./dbconfig.jspf" %>
<%
    Connection conn = null;
    try {
        conn = openDbConnection();
    } catch(Exception e) {
        throw new RuntimeException("DB connection failed (JNDI: " + DB_JNDI_NAME + "): " + e.getMessage(), e);
    }
%>
