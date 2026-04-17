<%@ page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="org.apache.poi.ss.usermodel.*" %>
<%@ page import="org.apache.poi.xssf.usermodel.XSSFWorkbook" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%
response.reset();
response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
response.setHeader("Content-Disposition", "attachment;filename=\"tenant_store_template.xlsx\"");

try (Workbook wb = new XSSFWorkbook();
     Connection conn = openDbConnection();
     Statement stmt = conn.createStatement()) {
    Sheet sheet = wb.createSheet("tenant_store");

    Font headerFont = wb.createFont();
    headerFont.setBold(true);

    CellStyle headerStyle = wb.createCellStyle();
    headerStyle.setFont(headerFont);
    headerStyle.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
    headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);

    CellStyle textStyle = wb.createCellStyle();
    textStyle.setDataFormat(wb.createDataFormat().getFormat("@"));

    String[] headers = new String[] {
        "store_code", "store_name", "business_number", "floor_name", "room_name", "zone_name",
        "category_name", "contact_name", "contact_phone", "status", "opened_on", "closed_on", "notes"
    };

    Row headerRow = sheet.createRow(0);
    for (int i = 0; i < headers.length; i++) {
        Cell cell = headerRow.createCell(i);
        cell.setCellValue(headers[i]);
        cell.setCellStyle(headerStyle);
    }

    String sql =
        "SELECT store_code, store_name, business_number, floor_name, room_name, zone_name, category_name, " +
        "contact_name, contact_phone, status, opened_on, closed_on, notes " +
        "FROM dbo.tenant_store ORDER BY store_code";
    int rowIdx = 1;
    try (ResultSet rs = stmt.executeQuery(sql)) {
        while (rs.next()) {
            Row row = sheet.createRow(rowIdx++);
            for (int i = 0; i < headers.length; i++) {
                Object v = rs.getObject(headers[i]);
                Cell c = row.createCell(i);
                if (v != null) c.setCellValue(String.valueOf(v));
                c.setCellStyle(textStyle);
            }
        }
    }

    for (int i = 0; i < headers.length; i++) {
        sheet.autoSizeColumn(i);
        int currentWidth = sheet.getColumnWidth(i);
        sheet.setColumnWidth(i, Math.min(currentWidth + 1024, 40 * 256));
    }

    try (ServletOutputStream os = response.getOutputStream()) {
        wb.write(os);
        os.flush();
    }
} catch (Exception e) {
    response.reset();
    response.setContentType("text/plain;charset=UTF-8");
    response.setHeader("Content-Disposition", "");
    out.println("Error generating XLSX: " + e.getMessage());
    e.printStackTrace(new java.io.PrintWriter(out));
}
%>
