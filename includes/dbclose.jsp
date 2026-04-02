<%
    // Legacy compatibility include.
    // New/updated JSP pages should prefer try-with-resources instead of
    // publishing JDBC objects into page/request scope.
    // Try to close commonly published JDBC resources first when pages
    // expose them through page/request scope.
    String[] resourceNames = new String[] {
        "rs", "rs1", "rs2",
        "ps", "ps1", "ps2",
        "pstmt", "pstmt1", "pstmt2",
        "stmt", "stmt1", "stmt2",
        "cs", "cs1", "cs2"
    };
    for (String resourceName : resourceNames) {
        closeQuietlyObject(pageContext.findAttribute(resourceName));
    }
    closeQuietly(conn);
%>
