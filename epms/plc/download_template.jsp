<%@ page import="java.io.*" %>
<%@ page import="java.nio.file.Files" %>
<%@ page import="java.nio.file.Path" %>
<%@ page import="java.nio.file.Paths" %>
<%
    String templateRelativePath = "/docs/plc_mapping_template.xlsx";
    String fileName = "plc_mapping_template.xlsx";

    try {
        String realPath = application.getRealPath(templateRelativePath);
        
        Path filePath = Paths.get(realPath);

        if (Files.exists(filePath) && !Files.isDirectory(filePath)) {
            response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
            response.setHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");
            response.setContentLengthLong(Files.size(filePath));

            try (InputStream in = Files.newInputStream(filePath); OutputStream os = response.getOutputStream()) {
                byte[] buffer = new byte[4096];
                int bytesRead;
                while ((bytesRead = in.read(buffer)) != -1) {
                    os.write(buffer, 0, bytesRead);
                }
            }
        } else {
            response.setContentType("text/html;charset=UTF-8");
            out.println("<html><body>");
            out.println("<h1>File Not Found</h1>");
            out.println("<p>Template file not found at path: " + templateRelativePath + "</p>");
            if (realPath != null) {
                out.println("<p>Real path resolved to: " + realPath + "</p>");
            } else {
                out.println("<p>Real path could not be resolved. The application might be running in a compressed archive.</p>");
            }
            out.println("</body></html>");
        }
    } catch (Exception e) {
        response.setContentType("text/html;charset=UTF-8");
        out.println("<html><body>");
        out.println("<h1>Error Downloading File</h1>");
        out.println("<p>" + e.getMessage() + "</p>");
        out.println("<pre>");
        e.printStackTrace(new java.io.PrintWriter(out));
        out.println("</pre>");
        out.println("</body></html>");
    }
%>
