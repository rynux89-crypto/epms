<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="java.nio.file.*" %>
<%@ page import="java.util.Base64" %>
<%@ page import="org.apache.poi.ss.usermodel.*" %>
<%@ page import="org.apache.poi.ss.usermodel.WorkbookFactory" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static final String STORE_CODE_PREFIX = "STORE";
    private static String trimToNullImport(String s) {
        if (s == null) return null;
        String x = s.trim();
        return x.isEmpty() ? null : x;
    }
    private static String normalizeHeader(String s) {
        return s == null ? "" : s.trim().toLowerCase(Locale.ROOT);
    }
    private static String resolveUploadSuffix(String uploadName) {
        if (uploadName == null) return ".csv";
        String name = uploadName.trim().toLowerCase(Locale.ROOT);
        int dot = name.lastIndexOf('.');
        if (dot < 0 || dot == name.length() - 1) return ".csv";
        String ext = name.substring(dot);
        if (".csv".equals(ext) || ".xlsx".equals(ext)) return ext;
        return ".csv";
    }
    private static boolean hasAnyValue(Map<String, String> row) {
        for (String v : row.values()) if (trimToNullImport(v) != null) return true;
        return false;
    }
    private static List<String> parseCsvLine(String line) {
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        boolean inQuotes = false;
        for (int i = 0; i < line.length(); i++) {
            char ch = line.charAt(i);
            if (ch == '"') {
                if (inQuotes && i + 1 < line.length() && line.charAt(i + 1) == '"') {
                    cur.append('"'); i++;
                } else inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                out.add(cur.toString()); cur.setLength(0);
            } else cur.append(ch);
        }
        out.add(cur.toString());
        return out;
    }
    private static List<Map<String, String>> readCsvRows(Path path) throws Exception {
        List<Map<String, String>> rows = new ArrayList<>();
        List<String> headers = null;
        try (BufferedReader br = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            String line;
            while ((line = br.readLine()) != null) {
                if (headers == null) {
                    if (!line.isEmpty() && line.charAt(0) == '\uFEFF') line = line.substring(1);
                    headers = new ArrayList<>();
                    for (String h : parseCsvLine(line)) headers.add(normalizeHeader(h));
                    continue;
                }
                List<String> raw = parseCsvLine(line);
                Map<String, String> row = new LinkedHashMap<>();
                for (int i = 0; i < headers.size(); i++) {
                    String key = headers.get(i);
                    if (!key.isEmpty()) row.put(key, i < raw.size() ? raw.get(i) : "");
                }
                if (hasAnyValue(row)) rows.add(row);
            }
        }
        return rows;
    }
    private static List<Map<String, String>> readXlsxRows(Path path) throws Exception {
        List<Map<String, String>> rows = new ArrayList<>();
        try (InputStream in = Files.newInputStream(path); Workbook wb = WorkbookFactory.create(in)) {
            if (wb.getNumberOfSheets() == 0) return rows;
            Sheet sheet = wb.getSheetAt(0);
            DataFormatter fmt = new DataFormatter(Locale.US);
            Row headerRow = sheet.getRow(sheet.getFirstRowNum());
            if (headerRow == null) return rows;
            List<String> headers = new ArrayList<>();
            for (int c = 0; c < headerRow.getLastCellNum(); c++) {
                Cell cell = headerRow.getCell(c, Row.MissingCellPolicy.RETURN_BLANK_AS_NULL);
                headers.add(normalizeHeader(cell == null ? "" : fmt.formatCellValue(cell)));
            }
            for (int r = sheet.getFirstRowNum() + 1; r <= sheet.getLastRowNum(); r++) {
                Row excelRow = sheet.getRow(r);
                if (excelRow == null) continue;
                Map<String, String> row = new LinkedHashMap<>();
                for (int c = 0; c < headers.size(); c++) {
                    String key = headers.get(c);
                    if (key.isEmpty()) continue;
                    Cell cell = excelRow.getCell(c, Row.MissingCellPolicy.RETURN_BLANK_AS_NULL);
                    row.put(key, cell == null ? "" : fmt.formatCellValue(cell));
                }
                if (hasAnyValue(row)) rows.add(row);
            }
        }
        return rows;
    }
    private static String nextStoreCode(Connection conn) throws Exception {
        String sql =
            "SELECT TOP 1 store_code " +
            "FROM dbo.tenant_store " +
            "WHERE store_code LIKE '" + STORE_CODE_PREFIX + "%' " +
            "ORDER BY TRY_CONVERT(int, SUBSTRING(store_code, " + (STORE_CODE_PREFIX.length() + 1) + ", 20)) DESC, store_id DESC";
        int next = 1;
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                String code = rs.getString(1);
                if (code != null && code.startsWith(STORE_CODE_PREFIX)) {
                    try {
                        next = Integer.parseInt(code.substring(STORE_CODE_PREFIX.length())) + 1;
                    } catch (Exception ignore) {
                        next = 1;
                    }
                }
            }
        }
        return STORE_CODE_PREFIX + String.format(java.util.Locale.ROOT, "%04d", next);
    }
%>
<%
String error = null;
String resultText = null;
String uploadNameUsed = null;
String rootPath = application.getRealPath("/");
if (rootPath == null) rootPath = new File(".").getCanonicalPath();
Path importLogPath = Paths.get(rootPath).resolve("logs").resolve("tenant_store_import_history.log");

try {
    if ("POST".equalsIgnoreCase(request.getMethod())) {
        Path tempFile = null;
        long started = System.currentTimeMillis();
        int rowsProcessed = 0;
        int inserts = 0;
        int updates = 0;
        List<String> errors = new ArrayList<>();
        try {
            String uploadB64 = request.getParameter("upload_b64");
            String uploadName = request.getParameter("upload_name");
            if (uploadB64 == null || uploadB64.trim().isEmpty()) throw new IllegalArgumentException("업로드된 파일이 없습니다.");

            uploadNameUsed = (uploadName == null || uploadName.trim().isEmpty()) ? "tenant_store.xlsx" : uploadName.trim();
            String b64 = uploadB64.trim();
            int idx = b64.indexOf(',');
            if (idx >= 0) b64 = b64.substring(idx + 1);
            byte[] bytes = Base64.getDecoder().decode(b64);

            tempFile = Files.createTempFile("tenant_store_import_", resolveUploadSuffix(uploadNameUsed));
            Files.write(tempFile, bytes);
            List<Map<String, String>> rows = ".xlsx".equals(resolveUploadSuffix(uploadNameUsed)) ? readXlsxRows(tempFile) : readCsvRows(tempFile);

            try (Connection conn = openDbConnection()) {
                String updateSql =
                    "UPDATE dbo.tenant_store SET store_name=?, business_number=?, floor_name=?, room_name=?, zone_name=?, category_name=?, contact_name=?, contact_phone=?, status=?, opened_on=?, closed_on=?, notes=?, updated_at=sysdatetime() WHERE store_code=?";
                String insertSql =
                    "INSERT INTO dbo.tenant_store (store_code, store_name, business_number, floor_name, room_name, zone_name, category_name, contact_name, contact_phone, status, opened_on, closed_on, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

                for (int i = 0; i < rows.size(); i++) {
                    int rowNo = i + 2;
                    rowsProcessed++;
                    Map<String, String> row = rows.get(i);
                    String storeCode = trimToNullImport(row.get("store_code"));
                    String storeName = trimToNullImport(row.get("store_name"));
                    String businessNumber = trimToNullImport(row.get("business_number"));
                    String floorName = trimToNullImport(row.get("floor_name"));
                    String roomName = trimToNullImport(row.get("room_name"));
                    String zoneName = trimToNullImport(row.get("zone_name"));
                    String categoryName = trimToNullImport(row.get("category_name"));
                    String contactName = trimToNullImport(row.get("contact_name"));
                    String contactPhone = trimToNullImport(row.get("contact_phone"));
                    String status = trimToNullImport(row.get("status"));
                    java.sql.Date openedOn = null;
                    java.sql.Date closedOn = null;
                    String notes = trimToNullImport(row.get("notes"));

                    if (storeName == null) {
                        errors.add("Row " + rowNo + ": store_name은 필수입니다.");
                        continue;
                    }
                    if (storeCode == null) storeCode = nextStoreCode(conn);
                    if (status == null) status = "ACTIVE";
                    try {
                        String x = trimToNullImport(row.get("opened_on"));
                        if (x != null) openedOn = java.sql.Date.valueOf(x);
                    } catch (Exception e) {
                        errors.add("Row " + rowNo + ": opened_on 형식은 YYYY-MM-DD 이어야 합니다.");
                        continue;
                    }
                    try {
                        String x = trimToNullImport(row.get("closed_on"));
                        if (x != null) closedOn = java.sql.Date.valueOf(x);
                    } catch (Exception e) {
                        errors.add("Row " + rowNo + ": closed_on 형식은 YYYY-MM-DD 이어야 합니다.");
                        continue;
                    }

                    try (PreparedStatement ps = conn.prepareStatement(updateSql)) {
                        ps.setString(1, storeName);
                        ps.setString(2, businessNumber);
                        ps.setString(3, floorName);
                        ps.setString(4, roomName);
                        ps.setString(5, zoneName);
                        ps.setString(6, categoryName);
                        ps.setString(7, contactName);
                        ps.setString(8, contactPhone);
                        ps.setString(9, status);
                        if (openedOn == null) ps.setNull(10, Types.DATE); else ps.setDate(10, openedOn);
                        if (closedOn == null) ps.setNull(11, Types.DATE); else ps.setDate(11, closedOn);
                        ps.setString(12, notes);
                        ps.setString(13, storeCode);
                        int affected = ps.executeUpdate();
                        if (affected > 0) {
                            updates++;
                        } else {
                            try (PreparedStatement ins = conn.prepareStatement(insertSql)) {
                                ins.setString(1, storeCode);
                                ins.setString(2, storeName);
                                ins.setString(3, businessNumber);
                                ins.setString(4, floorName);
                                ins.setString(5, roomName);
                                ins.setString(6, zoneName);
                                ins.setString(7, categoryName);
                                ins.setString(8, contactName);
                                ins.setString(9, contactPhone);
                                ins.setString(10, status);
                                if (openedOn == null) ins.setNull(11, Types.DATE); else ins.setDate(11, openedOn);
                                if (closedOn == null) ins.setNull(12, Types.DATE); else ins.setDate(12, closedOn);
                                ins.setString(13, notes);
                                ins.executeUpdate();
                                inserts++;
                            }
                        }
                    } catch (Exception e) {
                        errors.add("Row " + rowNo + ": " + e.getMessage());
                    }
                }
            }

            resultText =
                "rows_processed=" + rowsProcessed +
                ", inserts=" + inserts +
                ", updates=" + updates +
                ", errors=" + errors.size() +
                ", duration_ms=" + Math.max(0L, System.currentTimeMillis() - started) +
                (errors.isEmpty() ? "" : "\n" + String.join("\n", errors));

            try {
                Path parent = importLogPath.getParent();
                if (parent != null) Files.createDirectories(parent);
                Files.write(importLogPath, Arrays.asList(new Timestamp(System.currentTimeMillis()) + " | upload_name=" + uploadNameUsed + " | processed=" + rowsProcessed + " | inserts=" + inserts + " | updates=" + updates + " | errors=" + errors.size()), StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (Exception ignore) {}
        } catch (Exception e) {
            error = e.getMessage();
        } finally {
            if (tempFile != null) try { Files.deleteIfExists(tempFile); } catch (Exception ignore) {}
        }
    }
} catch (Exception e) {
    error = e.getMessage();
}
%>
<html>
<head>
    <title>매장 Excel/CSV 일괄 등록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:980px;margin:14px auto;padding:0 12px}
        .page-wrap{max-width:840px;margin:0 auto;display:grid;gap:12px}
        .info-box,.ok-box,.err-box{margin:0;padding:12px 14px;border-radius:8px}
        .info-box{background:#eef6ff;border:1px solid #cfe2ff;color:#1d4f91;font-size:13px}.ok-box{background:#ebfff1;border:1px solid #b7ebc6;color:#0f7a2a;font-size:13px;font-weight:700}.err-box{background:#fff1f1;border:1px solid #ffc9c9;color:#b42318;font-size:13px;font-weight:700;white-space:pre-wrap}
        .toolbar{display:grid;grid-template-columns:1fr;gap:8px;align-items:center}.btn-group{display:flex;gap:6px}
        .panel-box{padding:12px;border:1px solid #d9dfe8;border-radius:6px;background:#fff}
        pre{margin:0;padding:12px;border:1px solid #d9dfe8;border-radius:6px;background:#fafbfc;white-space:pre-wrap}
        #loadingOverlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.5);z-index:1000;display:none;align-items:center;justify-content:center}#loadingOverlay .spinner{width:50px;height:50px;border:5px solid #f3f3f3;border-top:5px solid #3498db;border-radius:50%;animation:spin 1s linear infinite}@keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(360deg)}}
    </style>
</head>
<body>
<div id="loadingOverlay"><div class="spinner"></div></div>
<div class="page-wrap">
    <div class="title-bar">
        <h2>매장 Excel/CSV 일괄 등록/수정</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='download_tenant_store_template.jsp'">템플릿 다운로드</button>
            <button class="back-btn" onclick="location.href='tenant_store_manage.jsp'">매장 관리로</button>
        </div>
    </div>
    <div class="info-box">
        1. 템플릿을 내려받아 `store_code` 기준으로 기존 매장은 수정, 없는 코드는 신규 등록합니다.<br/>
        2. 날짜는 `YYYY-MM-DD` 형식으로 입력합니다.<br/>
        3. `.xlsx` 또는 `.csv` 파일을 업로드하면 한 번에 반영됩니다.
    </div>
    <% if (error != null) { %><div class="err-box"><%= h(error) %></div><% } %>
    <form method="POST" id="importForm" action="<%= request.getRequestURI() %>" onsubmit="return handleFormSubmit(event);">
        <div class="toolbar">
            <label for="excel_file"><b>CSV/Excel 파일 선택</b></label>
            <input type="file" id="excel_file" accept=".csv,.xlsx" required>
            <div class="btn-group"><button type="submit">업로드 실행</button></div>
        </div>
        <input type="hidden" name="upload_name" id="upload_name">
        <input type="hidden" name="upload_b64" id="upload_b64">
    </form>
    <% if (resultText != null && !resultText.trim().isEmpty()) { %>
    <div class="ok-box">업로드 처리 완료</div>
    <pre><%= h(resultText) %></pre>
    <% } %>
</div>
<script>
function handleFormSubmit(event){
    event.preventDefault();
    var form=event.target;
    var fileInput=document.getElementById('excel_file');
    var uploadName=document.getElementById('upload_name');
    var uploadB64=document.getElementById('upload_b64');
    var loadingOverlay=document.getElementById('loadingOverlay');
    var file=fileInput.files&&fileInput.files[0];
    if(!file){alert('업로드할 파일을 선택해 주세요.');return false;}
    loadingOverlay.style.display='flex';
    var reader=new FileReader();
    reader.onload=function(e){uploadName.value=file.name||'';uploadB64.value=String(e.target.result||'');form.submit();};
    reader.onerror=function(){loadingOverlay.style.display='none';alert('파일을 읽는 중 오류가 발생했습니다.');};
    reader.readAsDataURL(file);
    return false;
}
</script>
</body>
</html>
