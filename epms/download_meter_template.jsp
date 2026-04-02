<%@ page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.io.*" %>
<%@ page import="org.apache.poi.ss.usermodel.*" %>
<%@ page import="org.apache.poi.xssf.usermodel.XSSFWorkbook" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%
    response.reset();
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment;filename=\"meter_template.xlsx\"");

    try (Workbook wb = new XSSFWorkbook();
         Connection conn = openDbConnection();
         Statement stmt = conn.createStatement()) {

        Sheet sheet = wb.createSheet("meters");

        Font headerFont = wb.createFont();
        headerFont.setBold(true);

        CellStyle headerStyle = wb.createCellStyle();
        headerStyle.setFont(headerFont);
        headerStyle.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
        headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);

        CellStyle textStyle = wb.createCellStyle();
        textStyle.setDataFormat(wb.createDataFormat().getFormat("@"));

        CellStyle numberStyle = wb.createCellStyle();
        numberStyle.setDataFormat(wb.createDataFormat().getFormat("0.############"));

        String[] headers = new String[] {
            "meter_id", "name", "building_name", "panel_name", "usage_type", "rated_voltage", "rated_current"
        };

        Row headerRow = sheet.createRow(0);
        for (int i = 0; i < headers.length; i++) {
            Cell cell = headerRow.createCell(i);
            cell.setCellValue(headers[i]);
            cell.setCellStyle(headerStyle);
        }

        String sql = "SELECT meter_id, name, building_name, panel_name, usage_type, rated_voltage, rated_current FROM dbo.meters ORDER BY meter_id";
        int rowIdx = 1;
        try (ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                Row row = sheet.createRow(rowIdx++);

                Object meterId = rs.getObject("meter_id");
                Object name = rs.getObject("name");
                Object buildingName = rs.getObject("building_name");
                Object panelName = rs.getObject("panel_name");
                Object usageType = rs.getObject("usage_type");
                Object ratedVoltage = rs.getObject("rated_voltage");
                Object ratedCurrent = rs.getObject("rated_current");

                Cell c0 = row.createCell(0);
                if (meterId != null) c0.setCellValue(String.valueOf(meterId));
                c0.setCellStyle(textStyle);

                Cell c1 = row.createCell(1);
                if (name != null) c1.setCellValue(String.valueOf(name));
                c1.setCellStyle(textStyle);

                Cell c2 = row.createCell(2);
                if (buildingName != null) c2.setCellValue(String.valueOf(buildingName));
                c2.setCellStyle(textStyle);

                Cell c3 = row.createCell(3);
                if (panelName != null) c3.setCellValue(String.valueOf(panelName));
                c3.setCellStyle(textStyle);

                Cell c4 = row.createCell(4);
                if (usageType != null) c4.setCellValue(String.valueOf(usageType));
                c4.setCellStyle(textStyle);

                Cell c5 = row.createCell(5);
                if (ratedVoltage instanceof Number) {
                    c5.setCellValue(((Number) ratedVoltage).doubleValue());
                    c5.setCellStyle(numberStyle);
                } else if (ratedVoltage != null) {
                    c5.setCellValue(String.valueOf(ratedVoltage));
                    c5.setCellStyle(textStyle);
                }

                Cell c6 = row.createCell(6);
                if (ratedCurrent instanceof Number) {
                    c6.setCellValue(((Number) ratedCurrent).doubleValue());
                    c6.setCellStyle(numberStyle);
                } else if (ratedCurrent != null) {
                    c6.setCellValue(String.valueOf(ratedCurrent));
                    c6.setCellStyle(textStyle);
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
