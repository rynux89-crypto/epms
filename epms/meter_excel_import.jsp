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
    private static final String[] METER_IMPORT_HEADERS = new String[] {
        "meter_id", "name", "building_name", "panel_name", "usage_type", "rated_voltage", "rated_current"
    };

    private static void appendImportHistory(Path logPath, String line) {
        try {
            Path parent = logPath.getParent();
            if (parent != null) Files.createDirectories(parent);
            Files.write(
                logPath,
                Arrays.asList(line),
                StandardCharsets.UTF_8,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND
            );
        } catch (Exception ignore) {}
    }

    private static String jsonEscape(String s) {
        if (s == null) return "null";
        StringBuilder out = new StringBuilder();
        out.append('"');
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            switch (ch) {
                case '\\': out.append("\\\\"); break;
                case '"': out.append("\\\""); break;
                case '\b': out.append("\\b"); break;
                case '\f': out.append("\\f"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (ch < 0x20) out.append(String.format("\\u%04x", (int) ch));
                    else out.append(ch);
            }
        }
        out.append('"');
        return out.toString();
    }

    private static String trimToNull(String s) {
        if (s == null) return null;
        String x = s.trim();
        return x.isEmpty() ? null : x;
    }

    private static String normalizeHeader(String s) {
        if (s == null) return "";
        return s.trim().toLowerCase(Locale.ROOT);
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

    private static List<String> parseCsvLine(String line) {
        List<String> out = new ArrayList<>();
        if (line == null) return out;
        StringBuilder cur = new StringBuilder();
        boolean inQuotes = false;
        for (int i = 0; i < line.length(); i++) {
            char ch = line.charAt(i);
            if (ch == '"') {
                if (inQuotes && i + 1 < line.length() && line.charAt(i + 1) == '"') {
                    cur.append('"');
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (ch == ',' && !inQuotes) {
                out.add(cur.toString());
                cur.setLength(0);
            } else {
                cur.append(ch);
            }
        }
        out.add(cur.toString());
        return out;
    }

    private static boolean hasAnyValue(Map<String, String> row) {
        if (row == null) return false;
        for (String v : row.values()) {
            if (trimToNull(v) != null) return true;
        }
        return false;
    }

    private static List<Map<String, String>> readCsvRows(Path path) throws Exception {
        List<Map<String, String>> rows = new ArrayList<>();
        List<String> headers = null;
        try (BufferedReader br = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            String line;
            while ((line = br.readLine()) != null) {
                if (headers == null) {
                    if (!line.isEmpty() && line.charAt(0) == '\uFEFF') line = line.substring(1);
                    List<String> raw = parseCsvLine(line);
                    headers = new ArrayList<>();
                    for (String h : raw) headers.add(normalizeHeader(h));
                    continue;
                }
                List<String> raw = parseCsvLine(line);
                Map<String, String> row = new LinkedHashMap<>();
                for (int i = 0; i < headers.size(); i++) {
                    String key = headers.get(i);
                    if (key.isEmpty()) continue;
                    row.put(key, i < raw.size() ? raw.get(i) : "");
                }
                if (hasAnyValue(row)) rows.add(row);
            }
        }
        return rows;
    }

    private static List<Map<String, String>> readXlsxRows(Path path) throws Exception {
        List<Map<String, String>> rows = new ArrayList<>();
        try (InputStream in = Files.newInputStream(path);
             Workbook wb = WorkbookFactory.create(in)) {
            if (wb.getNumberOfSheets() == 0) return rows;
            Sheet sheet = wb.getSheetAt(0);
            DataFormatter fmt = new DataFormatter(Locale.US);
            int firstRowNum = sheet.getFirstRowNum();
            Row headerRow = sheet.getRow(firstRowNum);
            if (headerRow == null) return rows;

            int lastCell = Math.max(0, headerRow.getLastCellNum());
            List<String> headers = new ArrayList<>();
            for (int c = 0; c < lastCell; c++) {
                Cell cell = headerRow.getCell(c, Row.MissingCellPolicy.RETURN_BLANK_AS_NULL);
                headers.add(normalizeHeader(cell == null ? "" : fmt.formatCellValue(cell)));
            }

            for (int r = firstRowNum + 1; r <= sheet.getLastRowNum(); r++) {
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

    private static List<Map<String, String>> readImportRows(Path path, String uploadName) throws Exception {
        String ext = resolveUploadSuffix(uploadName);
        if (".csv".equals(ext)) return readCsvRows(path);
        if (".xlsx".equals(ext)) return readXlsxRows(path);
        throw new IllegalArgumentException("지원하지 않는 파일 형식입니다: " + ext);
    }

    private static Double parseOptionalDouble(String value, int rowNo, String fieldName, List<String> errors) {
        String x = trimToNull(value);
        if (x == null) return null;
        try {
            return Double.valueOf(x.replace(",", ""));
        } catch (Exception e) {
            errors.add("Row " + rowNo + ": '" + fieldName + "' 값이 숫자가 아닙니다.");
            return null;
        }
    }

    private static Integer parseRequiredMeterId(String value, int rowNo, List<String> errors) {
        String x = trimToNull(value);
        if (x == null) return null;
        try {
            return Integer.valueOf(x.replace(",", ""));
        } catch (Exception e) {
            errors.add("Row " + rowNo + ": meter_id 값이 정수가 아닙니다.");
            return null;
        }
    }

    private static String buildResultJson(boolean ok, String mode, String filePath, int rowsTotal, int rowsProcessed, int inserts, int updates, List<String> errors, long durationMs) {
        StringBuilder s = new StringBuilder();
        s.append("{");
        s.append("\"ok\":").append(ok ? "true" : "false");
        s.append(",\"mode\":").append(jsonEscape(mode));
        s.append(",\"file_path\":").append(jsonEscape(filePath));
        s.append(",\"rows_total\":").append(rowsTotal);
        s.append(",\"rows_processed\":").append(rowsProcessed);
        s.append(",\"inserts\":").append(inserts);
        s.append(",\"updates\":").append(updates);
        s.append(",\"errors\":[");
        for (int i = 0; i < errors.size(); i++) {
            if (i > 0) s.append(",");
            s.append(jsonEscape(errors.get(i)));
        }
        s.append("]");
        s.append(",\"duration_ms\":").append(durationMs);
        s.append("}");
        return s.toString();
    }

    private static void bindMeterParams(PreparedStatement ps, String nameVal, String buildingNameVal, String panelNameVal, String usageTypeVal, Double ratedVoltageVal, Double ratedCurrentVal) throws Exception {
        ps.setString(1, nameVal);
        ps.setString(2, buildingNameVal);
        ps.setString(3, panelNameVal);
        ps.setString(4, usageTypeVal);
        if (ratedVoltageVal == null) ps.setNull(5, Types.DOUBLE); else ps.setDouble(5, ratedVoltageVal.doubleValue());
        if (ratedCurrentVal == null) ps.setNull(6, Types.DOUBLE); else ps.setDouble(6, ratedCurrentVal.doubleValue());
    }

    private static boolean insertMeterWithIdentity(Connection conn, Integer meterIdVal, String nameVal, String buildingNameVal, String panelNameVal, String usageTypeVal, Double ratedVoltageVal, Double ratedCurrentVal) throws Exception {
        String identityInsertSql =
            "INSERT INTO dbo.meters " +
            "(meter_id, name, building_name, panel_name, usage_type, rated_voltage, rated_current) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?)";
        Statement stmt = null;
        try {
            stmt = conn.createStatement();
            stmt.execute("SET IDENTITY_INSERT dbo.meters ON");
            try (PreparedStatement ps = conn.prepareStatement(identityInsertSql)) {
                ps.setInt(1, meterIdVal.intValue());
                ps.setString(2, nameVal);
                ps.setString(3, buildingNameVal);
                ps.setString(4, panelNameVal);
                ps.setString(5, usageTypeVal);
                if (ratedVoltageVal == null) ps.setNull(6, Types.DOUBLE); else ps.setDouble(6, ratedVoltageVal.doubleValue());
                if (ratedCurrentVal == null) ps.setNull(7, Types.DOUBLE); else ps.setDouble(7, ratedCurrentVal.doubleValue());
                return ps.executeUpdate() > 0;
            }
        } finally {
            if (stmt != null) {
                try { stmt.execute("SET IDENTITY_INSERT dbo.meters OFF"); } catch (Exception ignore) {}
                try { stmt.close(); } catch (Exception ignore) {}
            }
        }
    }
%>
<%
    String error = null;
    String resultText = null;
    String uploadNameUsed = null;
    Path importLogPath = null;
    String rootPath = application.getRealPath("/");
    if (rootPath == null) rootPath = new File(".").getCanonicalPath();

    try {
        importLogPath = Paths.get(rootPath).resolve("logs").resolve("meter_import_history.log");

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

                if (uploadB64 == null || uploadB64.trim().isEmpty()) {
                    throw new IllegalArgumentException("업로드된 파일이 없습니다.");
                }

                uploadNameUsed = (uploadName == null || uploadName.trim().isEmpty()) ? "meters.csv" : uploadName.trim();
                String uploadSuffix = resolveUploadSuffix(uploadNameUsed);

                String b64 = uploadB64.trim();
                int idx = b64.indexOf(',');
                if (idx >= 0) b64 = b64.substring(idx + 1);
                byte[] bytes = Base64.getDecoder().decode(b64);

                tempFile = Files.createTempFile("meter_import_upload_", uploadSuffix);
                Files.write(tempFile, bytes);

                List<Map<String, String>> rows = readImportRows(tempFile, uploadNameUsed);

                try (Connection conn = openDbConnection()) {
                    String updateSql =
                        "UPDATE dbo.meters " +
                        "SET name = ?, building_name = ?, panel_name = ?, usage_type = ?, rated_voltage = ?, rated_current = ? " +
                        "WHERE meter_id = ?";
                    String insertSql =
                        "INSERT INTO dbo.meters " +
                        "(name, building_name, panel_name, usage_type, rated_voltage, rated_current) " +
                        "VALUES (?, ?, ?, ?, ?, ?)";

                    for (int i = 0; i < rows.size(); i++) {
                        int rowNo = i + 2;
                        rowsProcessed++;
                        Map<String, String> row = rows.get(i);

                        String nameVal = trimToNull(row.get("name"));
                        String buildingNameVal = trimToNull(row.get("building_name"));
                        String panelNameVal = trimToNull(row.get("panel_name"));
                        String usageTypeVal = trimToNull(row.get("usage_type"));
                        Integer meterIdVal = parseRequiredMeterId(row.get("meter_id"), rowNo, errors);

                        int errorCountBefore = errors.size();
                        Double ratedVoltageVal = parseOptionalDouble(row.get("rated_voltage"), rowNo, "rated_voltage", errors);
                        Double ratedCurrentVal = parseOptionalDouble(row.get("rated_current"), rowNo, "rated_current", errors);
                        if (errors.size() > errorCountBefore) continue;

                        if (nameVal == null) {
                            errors.add("Row " + rowNo + ": 'name' is required and cannot be empty.");
                            continue;
                        }

                        if (trimToNull(row.get("meter_id")) != null && meterIdVal == null) {
                            continue;
                        }

                        if (meterIdVal != null) {
                            try (PreparedStatement ps = conn.prepareStatement(updateSql)) {
                                bindMeterParams(ps, nameVal, buildingNameVal, panelNameVal, usageTypeVal, ratedVoltageVal, ratedCurrentVal);
                                ps.setInt(7, meterIdVal.intValue());
                                int affected = ps.executeUpdate();
                                if (affected > 0) updates++;
                                else {
                                    boolean inserted = insertMeterWithIdentity(conn, meterIdVal, nameVal, buildingNameVal, panelNameVal, usageTypeVal, ratedVoltageVal, ratedCurrentVal);
                                    if (inserted) inserts++;
                                    else errors.add("Row " + rowNo + ": meter_id '" + meterIdVal + "' not found and explicit insert failed.");
                                }
                            } catch (Exception e) {
                                errors.add("Row " + rowNo + " (meter_id " + meterIdVal + "): UPSERT failed. Error: " + e.getMessage());
                            }
                        } else {
                            try (PreparedStatement ps = conn.prepareStatement(insertSql)) {
                                bindMeterParams(ps, nameVal, buildingNameVal, panelNameVal, usageTypeVal, ratedVoltageVal, ratedCurrentVal);
                                int affected = ps.executeUpdate();
                                if (affected > 0) inserts++;
                            } catch (Exception e) {
                                errors.add("Row " + rowNo + ": INSERT failed. Error: " + e.getMessage());
                            }
                        }
                    }
                }

                long durationMs = Math.max(0L, System.currentTimeMillis() - started);
                resultText = buildResultJson(true, "apply", tempFile.toString(), rows.size(), rowsProcessed, inserts, updates, errors, durationMs);

                String actor = request.getRemoteAddr();
                String logLine =
                    new Timestamp(System.currentTimeMillis()) +
                    " | upload_name=" + String.valueOf(uploadNameUsed) +
                    " | rows_total=" + rows.size() +
                    " | inserts=" + inserts +
                    " | updates=" + updates +
                    " | errors=" + errors.size() +
                    " | remote=" + actor;
                appendImportHistory(importLogPath, logLine);

            } catch (Exception e) {
                long durationMs = Math.max(0L, System.currentTimeMillis() - started);
                errors.add("A critical error occurred: " + e.getMessage());
                resultText = buildResultJson(false, "apply", tempFile == null ? "" : tempFile.toString(), 0, rowsProcessed, inserts, updates, errors, durationMs);
            } finally {
                if (tempFile != null) {
                    try { Files.deleteIfExists(tempFile); } catch (Exception ignore) {}
                }
            }
        }
    } catch (Exception e) {
        error = "페이지 처리 중 오류: " + e.getMessage();
    }
%>
<html>
<head>
    <title>계량기 엑셀/CSV 일괄 등록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 900px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; white-space: pre-wrap; }
        .toolbar { display: grid; grid-template-columns: 1fr; gap: 8px; align-items: center; margin-top: 10px; }
        .btn-group { display: flex; gap: 8px; }
        pre { background: #0b1020; color: #d8e6ff; border-radius: 8px; padding: 12px; white-space: pre-wrap; word-break: break-all; }
        .result-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 10px 0; }
        .result-card { border: 1px solid #dbe5f2; border-radius: 8px; padding: 10px; background: #f8fbff; }
        .result-card .k { font-size: 12px; color: #64748b; }
        .result-card .v { font-size: 18px; font-weight: 700; color: #1f3347; margin-top: 4px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        #loadingOverlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000; display: none; align-items: center; justify-content: center; }
        #loadingOverlay .spinner { width: 50px; height: 50px; border: 5px solid #f3f3f3; border-top: 5px solid #3498db; border-radius: 50%; animation: spin 1s linear infinite; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        #result-container { margin-top: 20px; padding-top: 20px; border-top: 1px solid #dbe5f2; }
    </style>
</head>
<body>
<div id="loadingOverlay"><div class="spinner"></div></div>
<div class="page-wrap">
    <div class="title-bar">
        <h2>계량기 엑셀/CSV 일괄 등록/수정</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='download_meter_template.jsp'">템플릿 다운로드</button>
            <button class="back-btn" onclick="location.href='meter_register.jsp'">목록으로 돌아가기</button>
        </div>
    </div>

    <div class="info-box">
        <b>1. 템플릿 다운로드:</b> 현재 등록된 모든 계량기 정보가 포함된 XLSX 템플릿을 다운로드합니다.<br/>
        <b>2. 파일 수정:</b> 템플릿에서 정보를 수정하거나 새 행을 추가합니다.<br/>
        &nbsp;&nbsp;&nbsp;• <b>수정 시</b> `meter_id`를 유지하고 다른 값만 바꿉니다.<br/>
        &nbsp;&nbsp;&nbsp;• <b>신규 등록 시</b> `meter_id`를 비우고 나머지 정보를 입력합니다.<br/>
        <b>3. 파일 업로드:</b> 수정한 `.xlsx` 또는 `.csv` 파일을 업로드하고 실행 버튼을 누릅니다.
    </div>

    <% if (error != null) { %>
    <div class="err-box"><%= h(error) %></div>
    <% } %>

    <form method="POST" id="importForm" action="<%= request.getRequestURI() %>" onsubmit="return handleFormSubmit(event);">
        <div class="toolbar">
            <label for="excel_file"><b>CSV/Excel 파일 선택</b></label>
            <input type="file" id="excel_file" accept=".csv,.xlsx" required>
            <div class="btn-group">
                <button type="submit">가져오기 실행</button>
            </div>
        </div>
        <input type="hidden" name="upload_name" id="upload_name">
        <input type="hidden" name="upload_b64" id="upload_b64">
    </form>

    <div id="result-container">
    <% if (resultText != null && !resultText.trim().isEmpty()) { %>
        <script>
            var resultJson = null;
            try {
                var rawText = `<%= resultText.replace("\\", "\\\\").replace("`", "\\`") %>`;
                var jsonStart = rawText.indexOf('{');
                var jsonEnd = rawText.lastIndexOf('}');
                if (jsonStart !== -1 && jsonEnd > jsonStart) {
                    var jsonStr = rawText.substring(jsonStart, jsonEnd + 1);
                    resultJson = JSON.parse(jsonStr);
                }
            } catch (e) {
                console.error("Failed to parse result JSON", e);
            }
        </script>

        <div class="ok-box">
            <% if (resultText.contains("\"ok\":true") && !resultText.contains("\"errors\":[\"")) { %>
                실행 완료
            <% } else if (resultText.contains("\"ok\":true")) { %>
                실행 완료 (오류 발생)
            <% } else { %>
                실행 실패
            <% } %>
        </div>

        <div class="info-box">
            처리 대상 파일: <span class="mono"><%= h(uploadNameUsed) %></span>
        </div>

        <div id="resultSummary"></div>

        <details>
            <summary class="muted">Import 원본 결과 보기</summary>
            <pre id="resultRaw"><%= h(resultText) %></pre>
        </details>
    <% } %>
    </div>
</div>

<script>
    function renderSummary(obj) {
        var summaryEl = document.getElementById('resultSummary');
        if (!summaryEl || !obj) return;

        var errors = Array.isArray(obj.errors) ? obj.errors : [];
        var errorHtml = '';
        if (errors.length > 0) {
            errorHtml = '<div class="err-box"><b>오류 (' + errors.length + '건)</b><br/>' +
                errors.slice(0, 20).map(function(e) { return '- ' + esc(e); }).join('<br/>') +
                (errors.length > 20 ? '<br/>... 등' : '') +
                '</div>';
        }

        summaryEl.innerHTML =
            '<div class="result-grid">' +
            '  <div class="result-card"><div class="k">총 행 수</div><div class="v">' + esc(obj.rows_total) + '</div></div>' +
            '  <div class="result-card"><div class="k">신규 등록</div><div class="v">' + esc(obj.inserts) + '</div></div>' +
            '  <div class="result-card"><div class="k">정보 수정</div><div class="v">' + esc(obj.updates) + '</div></div>' +
            '</div>' + errorHtml;
    }

    function esc(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function handleFormSubmit(event) {
        event.preventDefault();
        var form = event.target;
        var fileInput = document.getElementById('excel_file');
        var uploadName = document.getElementById('upload_name');
        var uploadB64 = document.getElementById('upload_b64');
        var loadingOverlay = document.getElementById('loadingOverlay');

        var file = fileInput.files && fileInput.files[0];
        if (!file) {
            alert('업로드할 파일을 선택해 주세요.');
            return false;
        }

        loadingOverlay.style.display = 'flex';

        var reader = new FileReader();
        reader.onload = function(e) {
            uploadName.value = file.name || '';
            uploadB64.value = String(e.target.result || '');
            form.submit();
        };
        reader.onerror = function() {
            loadingOverlay.style.display = 'none';
            alert('파일을 읽는 중 오류가 발생했습니다.');
        };
        reader.readAsDataURL(file);

        return false;
    }

    if (typeof resultJson !== 'undefined' && resultJson) {
        renderSummary(resultJson);
    }
</script>
</body>
</html>
