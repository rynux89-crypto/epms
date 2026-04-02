<%@ include file="./dbconfig.jspf" %>
<%
    // Legacy compatibility include.
    // New/updated JSP pages should prefer:
    // try (Connection conn = openDbConnection()) { ... }
    Connection conn = null;
    try {
        conn = openDbConnection();
    } catch(Exception e) {
        throw new RuntimeException("DB connection failed (JNDI: " + DB_JNDI_NAME + "): " + e.getMessage(), e);
    }
%>
