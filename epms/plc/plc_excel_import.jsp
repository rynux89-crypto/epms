<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="java.nio.file.*" %>
<%@ page import="java.util.Base64" %>
<%@ include file="../../includes/dbconn.jsp" %>
<%@ include file="../../includes/epms_html.jspf" %>
<%!
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

    private static int sumJsonIntField(String json, String fieldName) {
        if (json == null || json.isEmpty() || fieldName == null || fieldName.isEmpty()) return 0;
        int sum = 0;
        java.util.regex.Matcher m = java.util.regex.Pattern
            .compile("\"" + java.util.regex.Pattern.quote(fieldName) + "\"\\s*:\\s*(-?\\d+)")
            .matcher(json);
        while (m.find()) {
            try { sum += Integer.parseInt(m.group(1)); } catch (Exception ignore) {}
        }
        return sum;
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
                    if (ch < 0x20) {
                        out.append(String.format("\\u%04x", (int) ch));
                    } else {
                        out.append(ch);
                    }
            }
        }
        out.append('"');
        return out.toString();
    }

    private static String toJsonValue(Object v) {
        if (v == null) return "null";
        if (v instanceof String) return jsonEscape((String) v);
        if (v instanceof Number || v instanceof Boolean) return String.valueOf(v);
        if (v instanceof Map) {
            StringBuilder out = new StringBuilder();
            out.append('{');
            boolean first = true;
            for (Object eObj : ((Map<?, ?>) v).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) eObj;
                if (!first) out.append(',');
                first = false;
                out.append(jsonEscape(String.valueOf(e.getKey()))).append(':').append(toJsonValue(e.getValue()));
            }
            out.append('}');
            return out.toString();
        }
        if (v instanceof Iterable) {
            StringBuilder out = new StringBuilder();
            out.append('[');
            boolean first = true;
            for (Object item : (Iterable<?>) v) {
                if (!first) out.append(',');
                first = false;
                out.append(toJsonValue(item));
            }
            out.append(']');
            return out.toString();
        }
        return jsonEscape(String.valueOf(v));
    }
%>
<%
    request.setCharacterEncoding("UTF-8");

    final String SESSION_UPLOAD_B64 = "plcExcelImport.uploadB64";
    final String SESSION_UPLOAD_NAME = "plcExcelImport.uploadName";
    final String SESSION_UPLOAD_SOURCE = "plcExcelImport.uploadSource";

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<Map<String, Object>> currentAiMappings = new ArrayList<>();
    List<String> recentHistory = new ArrayList<>();
    String error = null;
    String resultText = null;
    String mode = "preview";
    Integer plcId = null;
    String byteOrder = "CDAB";
    int floatCount = 62;
    String excelPath = "";
    String runExcelPathUsed = null;
    String uploadNameUsed = null;
    String uploadSourceUsed = null;
    String overrideJsonUsed = null;
    Path importLogPath = null;
    boolean confirmDisable = "Y".equalsIgnoreCase(request.getParameter("confirm_disable"));
    int previewDisableTotal = 0;

    Set<String> allowedByteOrders = new HashSet<>(Arrays.asList("ABCD", "BADC", "CDAB", "DCBA"));

    try {
        String rootPath = application.getRealPath("/");
        if (rootPath == null) rootPath = new File(".").getCanonicalPath();
        importLogPath = Paths.get(rootPath).resolve("logs").resolve("plc_excel_import_history.log");

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT plc_id, plc_ip, plc_port, unit_id, enabled FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("plc_id", rs.getInt("plc_id"));
                r.put("plc_ip", rs.getString("plc_ip"));
                r.put("plc_port", rs.getInt("plc_port"));
                r.put("unit_id", rs.getInt("unit_id"));
                r.put("enabled", rs.getBoolean("enabled"));
                plcList.add(r);
            }
        }

        if ("POST".equalsIgnoreCase(request.getMethod())) {
            String plcParam = request.getParameter("plc_id");
            try {
                if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim());
            } catch (Exception ignore) {}

            String modeParam = request.getParameter("mode");
            if (modeParam == null || modeParam.trim().isEmpty()) {
                modeParam = request.getParameter("mode_hidden");
            }
            if ("apply".equals(modeParam) || "preview".equals(modeParam)) {
                mode = modeParam;
            }

            String byteOrderParam = request.getParameter("byte_order");
            if (byteOrderParam != null) byteOrderParam = byteOrderParam.trim().toUpperCase(Locale.ROOT);
            if (byteOrderParam != null && allowedByteOrders.contains(byteOrderParam)) {
                byteOrder = byteOrderParam;
            }

            String excelPathParam = request.getParameter("excel_path");
            if (excelPathParam != null && !excelPathParam.trim().isEmpty()) {
                excelPath = excelPathParam.trim();
            }

            {
                Path tempFile = null;
                try {
                    String uploadB64 = request.getParameter("upload_b64");
                    String uploadName = request.getParameter("upload_name");
                    String overridesJson = request.getParameter("overrides_json");
                    String runExcelPath;
                    Path overrideFile = null;
                    boolean hasRequestUpload = uploadB64 != null && !uploadB64.trim().isEmpty();
                    if (hasRequestUpload) {
                        session.setAttribute(SESSION_UPLOAD_B64, uploadB64);
                        session.setAttribute(SESSION_UPLOAD_NAME, uploadName == null ? "" : uploadName.trim());
                        session.setAttribute(SESSION_UPLOAD_SOURCE, "request");
                    } else if ("apply".equals(mode)) {
                        Object savedB64 = session.getAttribute(SESSION_UPLOAD_B64);
                        Object savedName = session.getAttribute(SESSION_UPLOAD_NAME);
                        if (savedB64 instanceof String && !((String) savedB64).trim().isEmpty()) {
                            uploadB64 = (String) savedB64;
                            uploadName = savedName == null ? null : String.valueOf(savedName);
                            uploadSourceUsed = "session";
                        }
                    } else {
                        session.removeAttribute(SESSION_UPLOAD_B64);
                        session.removeAttribute(SESSION_UPLOAD_NAME);
                        session.removeAttribute(SESSION_UPLOAD_SOURCE);
                    }
                    uploadNameUsed = (uploadName == null || uploadName.trim().isEmpty()) ? null : uploadName.trim();

                    if (uploadB64 != null && !uploadB64.trim().isEmpty()) {
                        String b64 = uploadB64.trim();
                        int idx = b64.indexOf(',');
                        if (idx >= 0) b64 = b64.substring(idx + 1);
                        byte[] bytes = Base64.getDecoder().decode(b64);
                        String ext = ".xlsx";
                        if (uploadName != null) {
                            String lower = uploadName.toLowerCase(Locale.ROOT);
                            if (lower.endsWith(".xls")) ext = ".xls";
                        }
                        tempFile = Files.createTempFile("plc_map_upload_", ext);
                        Files.write(tempFile, bytes);
                        runExcelPath = tempFile.toString();
                        if (uploadSourceUsed == null) uploadSourceUsed = hasRequestUpload ? "request" : "session";
                    } else {
                        Path p = Paths.get(excelPath);
                        if (excelPath == null || excelPath.trim().isEmpty()) {
                            throw new IllegalArgumentException("파일 선택 없음");
                        }
                        if (!p.isAbsolute()) {
                            String root = application.getRealPath("/");
                            if (root != null) p = Paths.get(root).resolve(excelPath);
                        }
                        runExcelPath = p.toString();
                        uploadSourceUsed = "path";
                    }
                    runExcelPathUsed = runExcelPath;

                    String scriptPath = Paths.get(rootPath).resolve("scripts").resolve("import_plc_mapping.ps1").toString();
                    if (overridesJson != null && !overridesJson.trim().isEmpty()) {
                        overrideFile = Files.createTempFile("plc_map_override_", ".json");
                        Files.write(overrideFile, overridesJson.getBytes(StandardCharsets.UTF_8));
                        overrideJsonUsed = overrideFile.toString();
                    }

                    List<String> cmd = new ArrayList<>();
                    cmd.add("powershell");
                    cmd.add("-NoProfile");
                    cmd.add("-ExecutionPolicy");
                    cmd.add("Bypass");
                    cmd.add("-File");
                    cmd.add(scriptPath);
                    cmd.add("-ExcelPath");
                    cmd.add(runExcelPath);
                    if (plcId != null) {
                        cmd.add("-PlcId");
                        cmd.add(String.valueOf(plcId));
                    }
                    cmd.add("-ByteOrder");
                    cmd.add(byteOrder);
                    cmd.add("-FloatCount");
                    cmd.add(String.valueOf(floatCount));
                    if (overrideJsonUsed != null) {
                        cmd.add("-OverrideJsonPath");
                        cmd.add(overrideJsonUsed);
                    }
                    if ("apply".equals(mode)) cmd.add("-Apply");
                    if (confirmDisable) cmd.add("-AllowDisable");

                    ProcessBuilder pb = new ProcessBuilder(cmd);
                    pb.redirectErrorStream(true);
                    Process pr = pb.start();

                    StringBuilder outBuf = new StringBuilder();
                    try (BufferedReader br = new BufferedReader(new InputStreamReader(pr.getInputStream(), StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = br.readLine()) != null) outBuf.append(line).append('\n');
                    }

                    int exit = pr.waitFor();
                    if (exit == 0) {
                        resultText = outBuf.toString();
                        previewDisableTotal =
                            sumJsonIntField(resultText, "ai_disabled") +
                            sumJsonIntField(resultText, "di_map_disabled") +
                            sumJsonIntField(resultText, "di_tag_disabled");
                        if ("apply".equals(mode) && !"path".equals(uploadSourceUsed)) {
                            session.removeAttribute(SESSION_UPLOAD_B64);
                            session.removeAttribute(SESSION_UPLOAD_NAME);
                            session.removeAttribute(SESSION_UPLOAD_SOURCE);
                        }
                    } else {
                        error = "매핑 실행 실패(exit=" + exit + ")\n" + outBuf;
                    }

                    String actor = request.getRemoteAddr();
                    String logLine =
                        new Timestamp(System.currentTimeMillis()) +
                        " | mode=" + mode +
                        " | plc_id=" + (plcId == null ? "AUTO" : String.valueOf(plcId)) +
                        " | excel_path=" + String.valueOf(runExcelPathUsed) +
                        " | upload_name=" + String.valueOf(uploadNameUsed == null ? "-" : uploadNameUsed) +
                        " | upload_source=" + String.valueOf(uploadSourceUsed == null ? "-" : uploadSourceUsed) +
                        " | byte_order=" + byteOrder +
                        " | float_count=" + floatCount +
                        " | exit=" + exit +
                        " | remote=" + actor;
                    appendImportHistory(importLogPath, logLine);
                } catch (Exception e) {
                    error = "매핑 실행 중 오류: " + e.getMessage();
                } finally {
                    if (tempFile != null) {
                        try { Files.deleteIfExists(tempFile); } catch (Exception ignore) {}
                    }
                    if (overrideJsonUsed != null) {
                        try { Files.deleteIfExists(Paths.get(overrideJsonUsed)); } catch (Exception ignore) {}
                        overrideJsonUsed = null;
                    }
                }
            }
        }

        String currentMappingSql =
            "SELECT pm.plc_id, pm.meter_id, m.name AS item_name, m.panel_name, pm.start_address, pm.float_count, pm.metric_order " +
            "FROM dbo.plc_meter_map pm " +
            "LEFT JOIN dbo.meters m ON m.meter_id = pm.meter_id " +
            "WHERE pm.enabled = 1 " +
            (plcId != null ? "AND pm.plc_id = ? " : "") +
            "ORDER BY pm.plc_id, pm.meter_id";
        try (PreparedStatement ps = conn.prepareStatement(currentMappingSql)) {
            if (plcId != null) ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new LinkedHashMap<>();
                    int startAddress = rs.getInt("start_address");
                    String metricOrder = rs.getString("metric_order");
                    List<Map<String, Object>> tokenAddresses = new ArrayList<>();
                    if (metricOrder != null && !metricOrder.trim().isEmpty()) {
                        String[] tokens = metricOrder.split("\\s*,\\s*");
                        int regAddress = startAddress;
                        for (int i = 0; i < tokens.length; i++) {
                            String token = tokens[i] == null ? "" : tokens[i].trim();
                            if (token.isEmpty()) continue;
                            Map<String, Object> t = new LinkedHashMap<>();
                            t.put("float_index", i + 1);
                            t.put("token", token);
                            t.put("reg_address", regAddress);
                            tokenAddresses.add(t);
                            regAddress += 2;
                        }
                    }
                    r.put("plc_id", rs.getInt("plc_id"));
                    r.put("meter_id", rs.getInt("meter_id"));
                    r.put("item_name", rs.getString("item_name"));
                    r.put("panel_name", rs.getString("panel_name"));
                    r.put("start_address", startAddress);
                    r.put("float_count", rs.getInt("float_count"));
                    r.put("metric_order", metricOrder);
                    r.put("token_addresses", tokenAddresses);
                    currentAiMappings.add(r);
                }
            }
        }
    } catch (Exception e) {
        error = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }

    if (importLogPath != null) {
        try {
            if (Files.exists(importLogPath)) {
                List<String> lines = Files.readAllLines(importLogPath, StandardCharsets.UTF_8);
                for (int i = lines.size() - 1; i >= 0 && recentHistory.size() < 10; i--) {
                    String line = lines.get(i);
                    if (line != null && !line.trim().isEmpty()) recentHistory.add(line);
                }
            }
        } catch (Exception ignore) {}
    }
%>
<html>
<head>
    <title>PLC Excel Auto Mapping</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1100px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; white-space: pre-wrap; }
        .toolbar { display: grid; grid-template-columns: 140px 1fr; gap: 8px; align-items: center; margin-top: 10px; }
        .toolbar .row-full { grid-column: 1 / -1; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        pre { background: #0b1020; color: #d8e6ff; border-radius: 8px; padding: 12px; white-space: pre-wrap; word-break: break-all; }
        .btn-group { display: flex; gap: 8px; }
        .result-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 10px 0; }
        .result-card { border: 1px solid #dbe5f2; border-radius: 8px; padding: 10px; background: #f8fbff; }
        .result-card .k { font-size: 12px; color: #64748b; }
        .result-card .v { font-size: 18px; font-weight: 700; color: #1f3347; margin-top: 4px; }
        .muted { font-size: 12px; color: #64748b; }
        .warn-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff7ed; border: 1px solid #fed7aa; color: #9a3412; font-size: 13px; }
        .history-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #f8fafc; border: 1px solid #d9e2ec; color: #334155; font-size: 12px; }
        .history-box ul { margin: 8px 0 0; padding-left: 18px; }
        .history-box li { margin: 4px 0; word-break: break-all; }
        .confirm-box { margin-top: 10px; padding: 10px 12px; border-radius: 8px; background: #fff7ed; border: 1px solid #fdba74; color: #9a3412; font-size: 13px; }
        .confirm-check { display: flex; gap: 8px; align-items: center; margin-top: 6px; }
        .decision-box { margin: 12px 0; padding: 12px; border-radius: 8px; background: #f8fbff; border: 1px solid #cfe2ff; }
        .decision-check { display: flex; gap: 8px; align-items: center; margin: 10px 0; }
        .preview-list { display: grid; gap: 10px; margin-top: 12px; }
        .preview-split { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; align-items: start; }
        .preview-meter { border: 1px solid #dbe5f2; border-radius: 8px; background: #fff; }
        .preview-meter summary { cursor: pointer; padding: 10px 12px; font-weight: 700; color: #1f3347; }
        .preview-meter-body { padding: 0 12px 12px; }
        .preview-meta { margin: 4px 0 10px; font-size: 12px; color: #64748b; }
        .preview-table { width: 100%; border-collapse: collapse; font-size: 12px; table-layout: fixed; }
        .preview-table th, .preview-table td { border: 1px solid #dbe5f2; padding: 6px 8px; text-align: left; }
        .preview-table th { background: #f1f5f9; color: #334155; }
        .table-scroll { max-height: 420px; overflow: auto; border: 1px solid #dbe5f2; border-radius: 8px; background: #fff; }
        .table-scroll .preview-table { border: 0; }
        .table-scroll .preview-table th { position: sticky; top: 0; z-index: 1; }
        .addr-input { width: 100%; min-width: 0; box-sizing: border-box; }
        .section-title { margin: 12px 0 6px; font-size: 16px; font-weight: 700; color: #1f3347; }
        .apply-off { background: #f8fafc; color: #94a3b8; }
        .filter-box { display: grid; grid-template-columns: repeat(4, minmax(120px, 1fr)); gap: 8px; margin: 8px 0 10px; }
        .filter-box input { width: 100%; }
        .token-pick-box { display: flex; flex-wrap: wrap; gap: 8px 12px; margin: 8px 0 10px; padding: 10px 12px; border: 1px solid #dbe5f2; border-radius: 8px; background: #fff; }
        .token-pick-box label { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; }
        .fold-box { margin: 12px 0; border: 1px solid #dbe5f2; border-radius: 8px; background: #fff; }
        .fold-box summary { cursor: pointer; padding: 10px 12px; font-weight: 700; color: #1f3347; }
        .fold-box-body { padding: 0 12px 12px; }

        .row-added td { background-color: #e8f5e9; }
        .row-modified td { background-color: #fff8e1; }
        .row-unchanged td { background-color: #f8fafc; color: #64748b; }
        .row-unchanged .addr-input { color: #6c757d; }

        #loadingOverlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000; display: none; align-items: center; justify-content: center; }
        #loadingOverlay .spinner { width: 50px; height: 50px; border: 5px solid #f3f3f3; border-top: 5px solid #3498db; border-radius: 50%; animation: spin 1s linear infinite; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

        #result-container { margin-top: 20px; padding-top: 20px; border-top: 1px solid #dbe5f2; }

        @media (max-width: 980px) { .preview-split { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
<div id="loadingOverlay"><div class="spinner"></div></div>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🤖 PLC Excel 자동 매핑 (AI + DI)</h2>
        <div class="inline-actions">
            <a href="download_template.jsp" class="back-btn" style="text-decoration: none;">템플릿 다운로드</a>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        엑셀 파일을 선택한 뒤 실행하면 아래 테이블이 자동 반영됩니다.<br/>
        대상 테이블: <span class="mono">plc_meter_map</span>, <span class="mono">plc_di_map</span>, <span class="mono">plc_di_tag_map</span><br/>
        PLC를 선택하지 않으면 엑셀의 PLC 컬럼(F2)에서 PLC를 자동 판별해 순차 적용합니다.<br/>
        미리보기: DB 변경 없이 결과 확인 / 적용: DB upsert 실행
    </div>

    <% if (error != null && !"POST".equalsIgnoreCase(request.getMethod())) { %>
    <div class="err-box"><%= h(error) %></div>
    <% } %>

    <form method="POST" id="importForm" action="<%= request.getRequestURI() %>">
        <div class="toolbar">
            <label for="plc_id">PLC (선택)</label>
            <select id="plc_id" name="plc_id">
                <option value="">자동(엑셀 기준)</option>
                <% for (Map<String, Object> p : plcList) { %>
                <% String v = String.valueOf(p.get("plc_id")); %>
                <option value="<%= v %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                    PLC <%= p.get("plc_id") %> - <%= h(p.get("plc_ip")) %>:<%= p.get("plc_port") %> (unit <%= p.get("unit_id") %>)
                </option>
                <% } %>
            </select>

            <label for="excel_file">엑셀 파일</label>
            <input type="file" id="excel_file" accept=".xlsx,.xls">

            <label for="excel_path">서버 경로(선택)</label>
            <input type="text" id="excel_path" name="excel_path" value="<%= h(excelPath) %>" class="mono" placeholder="필요할 때만 직접 입력">

            <label for="byte_order">Byte Order</label>
            <select id="byte_order" name="byte_order">
                <option value="ABCD" <%= "ABCD".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>ABCD</option>
                <option value="BADC" <%= "BADC".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>BADC</option>
                <option value="CDAB" <%= "CDAB".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>CDAB</option>
                <option value="DCBA" <%= "DCBA".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>DCBA</option>
            </select>
            <div class="row-full confirm-box" id="disableConfirmBox" style="display:<%= previewDisableTotal > 0 ? "block" : "none" %>;">
                기존 활성 매핑이 비활성화될 수 있습니다. preview 결과를 확인한 뒤, 정말 의도한 변경일 때만 적용하세요.
                <label class="confirm-check">
                    <input type="checkbox" id="confirm_disable" name="confirm_disable" value="Y" <%= confirmDisable ? "checked" : "" %>>
                    삭제성 변경을 확인했고, 그대로 적용합니다.
                </label>
            </div>

            <div class="row-full btn-group">
                <button type="submit" name="mode" value="preview">미리보기</button>
                <button type="submit" name="mode" value="apply">적용</button>
            </div>
        </div>
        <input type="hidden" name="upload_name" id="upload_name">
        <input type="hidden" name="upload_b64" id="upload_b64">
        <input type="hidden" name="overrides_json" id="overrides_json">
        <input type="hidden" name="mode_hidden" id="mode_hidden" value="preview">
    </form>

    <div id="result-container">
    <% if ("POST".equalsIgnoreCase(request.getMethod())) { %>
        <% if (error != null) { %>
        <div class="err-box"><%= h(error) %></div>
        <% } %>

        <% if (resultText != null) { %>
        <div class="ok-box"><%= "apply".equals(mode) ? "적용 완료" : "미리보기 완료" %></div>
        <div class="info-box">
            실제 실행 엑셀 경로: <span class="mono"><%= h(runExcelPathUsed == null ? "-" : runExcelPathUsed) %></span><br/>
            업로드 파일명: <span class="mono"><%= h(uploadNameUsed == null ? "-" : uploadNameUsed) %></span><br/>
            파일 사용 방식: <span class="mono"><%= h(uploadSourceUsed == null ? "-" : uploadSourceUsed) %></span>
        </div>
        <div id="resultSummary"></div>
        <div id="tokenAddressPreview"></div>
        <div id="postPreviewDecision"></div>
        <details>
            <summary class="muted">원본 결과(JSON) 보기</summary>
            <pre id="resultRaw"><%= h(resultText) %></pre>
        </details>
        <% } %>

        <div id="currentMappingPreview"></div>

        <% if (!recentHistory.isEmpty()) { %>
        <div class="history-box">
            <b>최근 실행 이력</b>
            <ul>
                <% for (String line : recentHistory) { %>
                <li class="mono"><%= h(line) %></li>
                <% } %>
            </ul>
        </div>
        <% } %>
    <% } %>
    </div>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>

<script>
function initializeScript() {
  const form = document.getElementById('importForm');
  if (!form) return;

  const fileInput = document.getElementById('excel_file');
  const excelPathInput = document.getElementById('excel_path');
  const uploadName = document.getElementById('upload_name');
  const uploadB64 = document.getElementById('upload_b64');
  const overridesJson = document.getElementById('overrides_json');
  const modeHidden = document.getElementById('mode_hidden');
  const resultSummary = document.getElementById('resultSummary');
  const postPreviewDecision = document.getElementById('postPreviewDecision');
  const currentMappingPreview = document.getElementById('currentMappingPreview');
  const tokenAddressPreview = document.getElementById('tokenAddressPreview');
  const resultRaw = document.getElementById('resultRaw');
  const confirmDisable = document.getElementById('confirm_disable');
  const disableConfirmBox = document.getElementById('disableConfirmBox');
  const currentMappings = <%= toJsonValue(currentAiMappings) %>;
  const resultTextB64 = <%= toJsonValue(resultText == null ? null : Base64.getEncoder().encodeToString(resultText.getBytes(StandardCharsets.UTF_8))) %>;
  const selectedPlcId = <%= toJsonValue(plcId) %>;
  let currentDisableSummary = null;
  const currentMappingIndex = new Map();

  (Array.isArray(currentMappings) ? currentMappings : []).forEach(function(row){
    const meterKey = Number(row.plc_id) + '|' + Number(row.meter_id);
    const byFloatIndex = new Map();
    (Array.isArray(row.token_addresses) ? row.token_addresses : []).forEach(function(t){
      byFloatIndex.set(Number(t.float_index), t);
    });
    currentMappingIndex.set(meterKey, byFloatIndex);
  });

  function emptyDisableSummary(){
    return {
      ai_disabled: 0,
      di_map_disabled: 0,
      di_tag_disabled: 0,
      existing_eld_tag_enabled: 0,
      new_eld_tag_count: 0,
      ai_disabled_samples: [],
      di_map_disabled_samples: [],
      di_tag_disabled_samples: []
    };
  }

  function mergeDisableSummary(target, source){
    const src = source || {};
    target.ai_disabled += Number(src.ai_disabled || 0);
    target.di_map_disabled += Number(src.di_map_disabled || 0);
    target.di_tag_disabled += Number(src.di_tag_disabled || 0);
    target.existing_eld_tag_enabled += Number(src.existing_eld_tag_enabled || 0);
    target.new_eld_tag_count += Number(src.new_eld_tag_count || 0);
    target.ai_disabled_samples = target.ai_disabled_samples.concat(Array.isArray(src.ai_disabled_samples) ? src.ai_disabled_samples : []);
    target.di_map_disabled_samples = target.di_map_disabled_samples.concat(Array.isArray(src.di_map_disabled_samples) ? src.di_map_disabled_samples : []);
    target.di_tag_disabled_samples = target.di_tag_disabled_samples.concat(Array.isArray(src.di_tag_disabled_samples) ? src.di_tag_disabled_samples : []);
    return target;
  }

  function resolveDisableSummary(obj){
    if (!obj) return emptyDisableSummary();
    if (obj.disable_summary) {
      return mergeDisableSummary(emptyDisableSummary(), obj.disable_summary);
    }
    if (Array.isArray(obj.per_plc)) {
      return obj.per_plc.reduce(function(acc, row){
        return mergeDisableSummary(acc, row && row.disable_summary ? row.disable_summary : null);
      }, emptyDisableSummary());
    }
    return emptyDisableSummary();
  }

  function esc(s){
    return String(s == null ? '' : s)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  }

  function renderSummary(obj){
    if (!resultSummary || !obj || !obj.ok) return;
    const unmatched = Array.isArray(obj.ai_unmatched) ? obj.ai_unmatched : [];
    const disable = resolveDisableSummary(obj);
    currentDisableSummary = disable;
    const disableTotal = Number(disable.ai_disabled || 0) + Number(disable.di_map_disabled || 0) + Number(disable.di_tag_disabled || 0);
    const html =
      '<div class="info-box">미리보기는 DB를 변경하지 않습니다. 적용 버튼을 누르면 실제 반영됩니다.</div>' +
      '<div class="result-grid">' +
      '<div class="result-card"><div class="k">대상 PLC</div><div class="v">' + esc(obj.plc_id) + '</div></div>' +
      '<div class="result-card"><div class="k">AI 매핑 예정</div><div class="v">' + esc(obj.ai_rows) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">DI 주소맵 예정</div><div class="v">' + esc(obj.di_map_rows) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">DI 태그맵 예정</div><div class="v">' + esc(obj.di_tag_rows) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">Float Count(적용)</div><div class="v">' + esc(obj.float_count_used) + '</div></div>' +
      '<div class="result-card"><div class="k">AI 미매칭</div><div class="v">' + esc(unmatched.length) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">비활성 예정</div><div class="v">' + esc(disableTotal) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">실행 모드</div><div class="v">' + esc(obj.mode) + '</div></div>' +
      '</div>';

    let perPlcInfo = '';
    if (Array.isArray(obj.per_plc) && obj.per_plc.length > 0) {
      perPlcInfo = '<div class="info-box"><b>PLC별 요약:</b><br/>' +
        obj.per_plc.map(function(p){
          const ds = p && p.disable_summary ? p.disable_summary : {};
          const dsTotal = Number(ds.ai_disabled || 0) + Number(ds.di_map_disabled || 0) + Number(ds.di_tag_disabled || 0);
          return 'PLC ' + esc(p.plc_id) +
            ': AI ' + esc(p.ai_rows || 0) +
            ', DI 주소맵 ' + esc(p.di_map_rows || 0) +
            ', DI 태그맵 ' + esc(p.di_tag_rows || 0) +
            ', 비활성 예정 ' + esc(dsTotal);
        }).join('<br/>') +
        '</div>';
    }

    let warn = '';
    if (unmatched.length > 0) {
      warn = '<div class="warn-box"><b>확인 필요:</b> AI 미매칭 항목이 있습니다.<br/>' +
        unmatched.slice(0, 10).map(function(x){ return '- ' + esc(x); }).join('<br/>') +
        (unmatched.length > 10 ? '<br/>... 외 ' + esc(unmatched.length - 10) + '건' : '') +
        '</div>';
    }
    let disableWarn = '';
    if (disableTotal > 0) {
      const samples = []
        .concat(Array.isArray(disable.ai_disabled_samples) ? disable.ai_disabled_samples.slice(0, 5) : [])
        .concat(Array.isArray(disable.di_map_disabled_samples) ? disable.di_map_disabled_samples.slice(0, 5) : [])
        .concat(Array.isArray(disable.di_tag_disabled_samples) ? disable.di_tag_disabled_samples.slice(0, 8) : []);
      disableWarn =
        '<div class="warn-box"><b>삭제성 변경 감지:</b> 기존 활성 매핑이 비활성화됩니다.' +
        '<br/>AI: ' + esc(disable.ai_disabled || 0) +
        ', DI 주소맵: ' + esc(disable.di_map_disabled || 0) +
        ', DI 태그맵: ' + esc(disable.di_tag_disabled || 0) +
        '<br/>기존 ELD 태그: ' + esc(disable.existing_eld_tag_enabled || 0) +
        ', 새 ELD 태그: ' + esc(disable.new_eld_tag_count || 0) +
        (samples.length ? '<br/><br/>' + samples.map(function(x){ return '- ' + esc(x); }).join('<br/>') : '') +
        '</div>';
    }
    let floatInfo = '';
    if (obj.float_count_used === 'VARIES' && obj.float_count_by_plc) {
      const lines = Object.keys(obj.float_count_by_plc)
        .sort(function(a,b){ return Number(a) - Number(b); })
        .map(function(k){ return 'PLC ' + esc(k) + ': ' + esc(obj.float_count_by_plc[k]); });
      if (lines.length > 0) {
        floatInfo = '<div class="info-box"><b>PLC별 Float Count:</b><br/>' + lines.join('<br/>') + '</div>';
      }
    }
    let floatDistInfo = '';
    if (obj.ai_float_distribution) {
      const distKeys = Object.keys(obj.ai_float_distribution)
        .sort(function(a,b){ return Number(a) - Number(b); });
      if (distKeys.length > 0) {
        const lines = distKeys.map(function(k){
          return 'float_count ' + esc(k) + ': ' + esc(obj.ai_float_distribution[k]) + ' meter';
        });
        floatDistInfo = '<div class="info-box"><b>AI Float Count 분포:</b><br/>' + lines.join('<br/>') + '</div>';
      }
    }
    let floatMeterInfo = '';
    if (obj.ai_float_meter_ids) {
      const keys = Object.keys(obj.ai_float_meter_ids)
        .sort(function(a,b){ return Number(a) - Number(b); });
      if (keys.length > 0) {
        const lines = keys.map(function(k){
          const ids = Array.isArray(obj.ai_float_meter_ids[k]) ? obj.ai_float_meter_ids[k] : [];
          return 'float_count ' + esc(k) + ': meter_id [' + esc(ids.join(', ')) + ']';
        });
        floatMeterInfo = '<div class="info-box"><b>AI Float Count별 meter_id:</b><br/>' + lines.join('<br/>') + '</div>';
      }
    }
    if (disableConfirmBox) {
      disableConfirmBox.style.display = disableTotal > 0 ? 'block' : 'none';
    }
    if (resultSummary) {
        resultSummary.innerHTML = html + perPlcInfo + warn + disableWarn + floatInfo + floatDistInfo + floatMeterInfo;
    }
  }

  function flattenAiPreviewRows(obj){
    const out = [];
    if (!obj) return out;
    if (Array.isArray(obj.ai_rows_preview)) {
      obj.ai_rows_preview.forEach(function(row){
        out.push({ plc_id: obj.plc_id, row: row });
      });
    }
    if (Array.isArray(obj.per_plc)) {
      obj.per_plc.forEach(function(p){
        if (!p || !Array.isArray(p.ai_rows_preview)) return;
        p.ai_rows_preview.forEach(function(row){
          out.push({ plc_id: p.plc_id, row: row });
        });
      });
    }
    return out;
  }

  function renderPostPreviewDecision(mode){
    if (!postPreviewDecision) return;
    if (mode !== 'preview') {
      postPreviewDecision.innerHTML = '';
      return;
    }
    postPreviewDecision.innerHTML =
      '<div class="decision-box">' +
      '<b>DB 반영 여부 선택</b><br/>' +
      '미리보기 결과를 확인한 뒤 아래에서 반영 여부를 선택하세요.' +
      '<label class="decision-check">' +
      '<input type="checkbox" id="applyDecisionCheck">' +
      '현재 preview 내용을 DB에 반영합니다.' +
      '</label>' +
      '<div class="btn-group" style="margin-top:10px;">' +
      '<button type="button" id="dismissPreviewBtn">반영 안 함</button>' +
      '<button type="button" id="applyAfterPreviewBtn">DB 반영</button>' +
      '</div>' +
      '</div>';
    const dismissBtn = document.getElementById('dismissPreviewBtn');
    const applyBtn = document.getElementById('applyAfterPreviewBtn');
    const applyDecisionCheck = document.getElementById('applyDecisionCheck');
    if (dismissBtn) {
      dismissBtn.addEventListener('click', function(){
        postPreviewDecision.innerHTML = '<div class="info-box">미리보기만 수행했고 DB에는 반영하지 않았습니다.</div>';
      });
    }
    if (applyBtn) {
      applyBtn.addEventListener('click', function(){
        if (applyDecisionCheck && !applyDecisionCheck.checked) {
          alert('DB 반영 체크박스를 선택한 뒤 진행하세요.');
          return;
        }
        if (confirmDisable && currentDisableSummary) {
          const disableTotal = Number(currentDisableSummary.ai_disabled || 0) + Number(currentDisableSummary.di_map_disabled || 0) + Number(currentDisableSummary.di_tag_disabled || 0);
          if (disableTotal > 0 && !confirmDisable.checked) {
            alert('삭제성 변경이 있으므로 체크박스를 선택한 뒤 DB 반영을 진행하세요.');
            return;
          }
        }
        if (overridesJson) {
          overridesJson.value = JSON.stringify(collectOverrides());
        }
        modeHidden.value = 'apply';
        form.requestSubmit(applyBtn);
      });
    }
  }

  function collectOverrides(){
    const byMeter = new Map();
    document.querySelectorAll('.addr-input').forEach(function(input){
      const plcId = Number(input.getAttribute('data-plc'));
      const meterId = Number(input.getAttribute('data-meter'));
      const floatIndex = Number(input.getAttribute('data-float-index'));
      const token = input.getAttribute('data-token');
      const tokenCheckbox = document.querySelector('.token-apply-input[data-token="' + CSS.escape(token) + '"]');
      const applyChecked = !tokenCheckbox || !!tokenCheckbox.checked;
      const key = plcId + '|' + meterId;
      if (!byMeter.has(key)) {
        byMeter.set(key, { plc_id: plcId, meter_id: meterId, token_addresses: [] });
      }
      const currentByIndex = currentMappingIndex.get(key);
      const currentTokenRow = currentByIndex ? currentByIndex.get(floatIndex) : null;
      const finalToken = applyChecked ? token : (currentTokenRow && currentTokenRow.token ? currentTokenRow.token : token);
      const finalAddress = applyChecked ? Number(input.value) : (currentTokenRow && currentTokenRow.reg_address != null ? Number(currentTokenRow.reg_address) : Number(input.value));
      byMeter.get(key).token_addresses.push({
        float_index: floatIndex,
        token: finalToken,
        reg_address: finalAddress
      });
    });
    return Array.from(byMeter.values()).map(function(row){
      row.token_addresses.sort(function(a, b){ return a.float_index - b.float_index; });
      return row;
    });
  }

  function syncTokenSelection(token, checked){
    document.querySelectorAll('.addr-input[data-token="' + CSS.escape(token) + '"]').forEach(function(input){
      const plcId = input.getAttribute('data-plc');
      const meterId = input.getAttribute('data-meter');
      const floatIndex = input.getAttribute('data-float-index');
      const tr = input.closest('tr');
      const currentByIndex = currentMappingIndex.get(plcId + '|' + meterId);
      const currentTokenRow = currentByIndex ? currentByIndex.get(Number(floatIndex)) : null;
      if (!checked && currentTokenRow && currentTokenRow.reg_address != null) {
        input.value = currentTokenRow.reg_address;
      }
      input.disabled = !checked;
      if (tr) tr.classList.toggle('apply-off', !checked);
    });
  }

  function renderTokenSelector(rows){
    const tokenSet = new Set();
    rows.forEach(function(entry){
      const tokenRows = Array.isArray(entry.row && entry.row.token_addresses) ? entry.row.token_addresses : [];
      tokenRows.forEach(function(t){
        if (t && t.token) tokenSet.add(String(t.token));
      });
    });
    const tokens = Array.from(tokenSet).sort();
    if (!tokens.length) return '';
    return '<div class="token-pick-box">' +
      tokens.map(function(token){
        return '<label><input type="checkbox" class="token-apply-input" data-token="' + esc(token) + '" checked> <span class="mono">' + esc(token) + '</span></label>';
      }).join('') +
      '</div>';
  }

  function bindTokenSelector(){
    document.querySelectorAll('.token-apply-input').forEach(function(cb){
      cb.addEventListener('change', function(){
        syncTokenSelection(cb.getAttribute('data-token'), cb.checked);
      });
      syncTokenSelection(cb.getAttribute('data-token'), cb.checked);
    });
  }

  function renderTableFilters(prefix){
    return '<div class="filter-box">' +
      '<input type="text" class="table-filter" data-target="' + prefix + '" data-key="plc" placeholder="plc_id 검색">' +
      '<input type="text" class="table-filter" data-target="' + prefix + '" data-key="meter" placeholder="meter_id 검색">' +
      '<input type="text" class="table-filter" data-target="' + prefix + '" data-key="item" placeholder="item_name 검색">' +
      '<input type="text" class="table-filter" data-target="' + prefix + '" data-key="panel" placeholder="panel_name 검색">' +
      '</div>';
  }

  function applyTableFilters(target){
    const filters = {};
    document.querySelectorAll('.table-filter[data-target="' + target + '"]').forEach(function(f){
      filters[f.getAttribute('data-key')] = String(f.value || '').trim().toLowerCase();
    });
    document.querySelectorAll('tr[data-table="' + target + '"]').forEach(function(tr){
      const ok =
        (!filters.plc || String(tr.getAttribute('data-plc') || '').toLowerCase().includes(filters.plc)) &&
        (!filters.meter || String(tr.getAttribute('data-meter') || '').toLowerCase().includes(filters.meter)) &&
        (!filters.item || String(tr.getAttribute('data-item') || '').toLowerCase().includes(filters.item)) &&
        (!filters.panel || String(tr.getAttribute('data-panel') || '').toLowerCase().includes(filters.panel));
      tr.style.display = ok ? '' : 'none';
    });
  }

  function renderTokenAddressPreview(obj){
    if (!tokenAddressPreview) return;
    const rows = flattenAiPreviewRows(obj);
    if (!rows.length) {
      const unmatched = Array.isArray(obj && obj.ai_unmatched) ? obj.ai_unmatched : [];
      const aiRows = Number(obj && obj.ai_rows ? obj.ai_rows : 0);
      const aiCandidates = Number(obj && obj.ai_candidates ? obj.ai_candidates : 0);
      let reason = 'AI preview 대상이 없습니다.';
      if (aiCandidates <= 0) {
        reason = '엑셀에서 현재 PLC 대상 AI 행을 찾지 못했습니다.';
      } else if (aiRows <= 0 && unmatched.length > 0) {
        reason = '엑셀 행은 찾았지만 meter 매칭에 실패해 preview를 만들지 못했습니다.';
      } else if (aiRows <= 0) {
        reason = 'AI mapping row가 생성되지 않았습니다.';
      }
      tokenAddressPreview.innerHTML =
        '<div class="section-title">Token / Address Preview</div>' +
        '<div class="warn-box"><b>표시할 preview가 없습니다.</b><br/>' +
        esc(reason) +
        '<br/>ai_candidates: ' + esc(aiCandidates) +
        ', ai_rows: ' + esc(aiRows) +
        ', ai_unmatched: ' + esc(unmatched.length) +
        (unmatched.length ? '<br/><br/>' + unmatched.slice(0, 10).map(function(x){ return '- ' + esc(x); }).join('<br/>') : '') +
        '</div>';
      return;
    }
    const body = rows.map(function(entry){
      const row = entry.row || {};
      const tokenRows = Array.isArray(row.token_addresses) ? row.token_addresses : [];
      return tokenRows.map(function(t){
        const meterKey = Number(entry.plc_id) + '|' + Number(row.meter_id);
        const currentMeterTokens = currentMappingIndex.get(meterKey);
        const currentTokenRow = currentMeterTokens ? currentMeterTokens.get(Number(t.float_index)) : null;

        let rowClass = 'row-added';
        let currentAddress = 'N/A';
        let isUnchanged = false;

        if (currentTokenRow) {
            currentAddress = currentTokenRow.reg_address;
            if (Number(currentAddress) === Number(t.reg_address)) {
                rowClass = 'row-unchanged';
                isUnchanged = true;
            } else {
                rowClass = 'row-modified';
            }
        }

        return '<tr class="' + rowClass + '" data-table="preview" data-plc="' + esc(entry.plc_id) + '" data-meter="' + esc(row.meter_id) + '" data-item="' + esc(row.item_name || '-') + '" data-panel="' + esc(row.panel_name || '-') + '">' +
          '<td class="mono">' + esc(entry.plc_id) + '</td>' +
          '<td class="mono">' + esc(row.meter_id) + '</td>' +
          '<td>' + esc(row.item_name || '-') + '</td>' +
          '<td>' + esc(row.panel_name || '-') + '</td>' +
          '<td class="mono">' + esc(t.float_index) + '</td>' +
          '<td class="mono">' + esc(t.token) + '</td>' +
          '<td class="mono">' + esc(currentAddress) + '</td>' +
          '<td class="mono"><input type="number" class="addr-input mono" data-plc="' + esc(entry.plc_id) + '" data-meter="' + esc(row.meter_id) + '" data-token="' + esc(t.token) + '" data-float-index="' + esc(t.float_index) + '" value="' + esc(t.reg_address) + '" ' + (isUnchanged ? 'readonly' : '') + '></td>' +
          '</tr>';
      }).join('');
    }).join('');
    tokenAddressPreview.innerHTML =
      '<div class="section-title">Token / Address Preview</div>' +
      '<div class="info-box">' +
      '아래 목록에서 변경사항을 확인하세요. ' +
      '<span style="background-color: #e8f5e9; padding: 2px; border-radius: 3px;">초록색 행</span>은 새로 추가, ' +
      '<span style="background-color: #fff8e1; padding: 2px; border-radius: 3px;">노란색 행</span>은 주소값이 변경된 항목, ' +
      '<span style="background-color: #f8fafc; padding: 2px; border-radius: 3px;">회색 행</span>은 기존 DB와 동일한 항목입니다.' +
      '</div>' +
      renderTokenSelector(rows) +
      renderTableFilters('preview') +
      '<div class="table-scroll">' +
      '<table class="preview-table">' +
      '<thead><tr><th>plc_id</th><th>meter_id</th><th>item_name</th><th>panel_name</th><th>float_index</th><th>token</th><th>현재 주소</th><th>새 주소</th></tr></thead>' +
      '<tbody>' + body + '</tbody>' +
      '</table>' +
      '</div>';
    bindTokenSelector();
    applyTableFilters('preview');
  }

  function renderCurrentMappingPreview(obj){
    if (!currentMappingPreview) return;
    const targetPlcIds = new Set();
    if (obj && obj.plc_id) targetPlcIds.add(Number(obj.plc_id));
    if (obj && Array.isArray(obj.per_plc)) {
      obj.per_plc.forEach(function(p){
        if (p && p.plc_id != null) targetPlcIds.add(Number(p.plc_id));
      });
    }
    const rows = Array.isArray(currentMappings) ? currentMappings.filter(function(row){
      if (!targetPlcIds.size) return true;
      return targetPlcIds.has(Number(row.plc_id));
    }) : [];
    if (!rows.length) {
      currentMappingPreview.innerHTML =
        '<div class="section-title">현재 DB 매핑</div>' +
        '<div class="info-box">표시할 현재 매핑이 없습니다.</div>';
      return;
    }
    const body = rows.map(function(row){
      const tokenRows = Array.isArray(row.token_addresses) ? row.token_addresses : [];
      return tokenRows.map(function(t){
        return '<tr data-table="current" data-plc="' + esc(row.plc_id) + '" data-meter="' + esc(row.meter_id) + '" data-item="' + esc(row.item_name || '-') + '" data-panel="' + esc(row.panel_name || '-') + '">' +
          '<td class="mono">' + esc(row.plc_id) + '</td>' +
          '<td class="mono">' + esc(row.meter_id) + '</td>' +
          '<td>' + esc(row.item_name || '-') + '</td>' +
          '<td>' + esc(row.panel_name || '-') + '</td>' +
          '<td class="mono">' + esc(t.float_index) + '</td>' +
          '<td class="mono">' + esc(t.token) + '</td>' +
          '<td class="mono">' + esc(t.reg_address) + '</td>' +
          '</tr>';
      }).join('');
    }).join('');
    currentMappingPreview.innerHTML =
      '<details class="fold-box" open>' +
      '<summary>기존 DB 매핑과 비교</summary>' +
      '<div class="fold-box-body">' +
      '<div class="info-box">현재 <span class="mono">plc_meter_map.metric_order</span> 기준 token / register address 입니다.</div>' +
      renderTableFilters('current') +
      '<div class="table-scroll">' +
      '<table class="preview-table">' +
      '<thead><tr><th>plc_id</th><th>meter_id</th><th>item_name</th><th>panel_name</th><th>float_index</th><th>token</th><th>reg_address</th></tr></thead>' +
      '<tbody>' + body + '</tbody>' +
      '</table>' +
      '</div>' +
      '</div>' +
      '</details>';
    applyTableFilters('current');
  }

  // --- Main execution ---
  renderCurrentMappingPreview(null);

  if (resultTextB64) {
    if (selectedPlcId == null) {
      if (tokenAddressPreview) {
        tokenAddressPreview.innerHTML =
          '<div class="section-title">Token / Address Preview</div>' +
          '<div class="info-box">현재는 <b>AUTO(엑셀 기준)</b> 모드입니다. 이 모드에서는 전체 PLC preview 결과가 너무 커질 수 있어 token/address 상세표를 표시하지 않습니다.<br/>' +
          '상단에서 특정 PLC를 선택한 뒤 다시 <b>미리보기</b>를 실행하면 상세 비교표를 볼 수 있습니다.</div>';
      }
      if (postPreviewDecision) {
        postPreviewDecision.innerHTML =
          '<div class="decision-box"><b>안내</b><br/>AUTO 모드에서는 상세 preview 없이 요약만 보여줍니다. 실제 token/address 비교나 선택 반영은 PLC를 선택한 뒤 진행하세요.</div>';
      }
      renderCurrentMappingPreview(null);
      return;
    }
    let raw = '';
    try {
      const bytes = Uint8Array.from(atob(String(resultTextB64)), function(c){ return c.charCodeAt(0); });
      raw = new TextDecoder('utf-8').decode(bytes).replace(/^\uFEFF/, '').trim();
    } catch (decodeErr) {
      if (resultSummary) {
        resultSummary.innerHTML = '<div class="err-box">미리보기 결과 디코딩에 실패했습니다.</div>';
      }
      console.error('Failed to decode result JSON', decodeErr);
      raw = '';
    }
    const s = raw.indexOf('{');
    const e = raw.lastIndexOf('}');
    if (s >= 0 && e > s) {
      const jsonText = raw.substring(s, e + 1);
      try {
        const obj = JSON.parse(jsonText);
        const mode = obj.mode || '<%= h(mode) %>';
        renderSummary(obj);
        renderPostPreviewDecision(mode);
        renderCurrentMappingPreview(obj);
        renderTokenAddressPreview(obj);
      } catch (ignore) {
          console.error("Failed to parse result JSON", ignore);
          if (resultSummary) {
            resultSummary.innerHTML = '<div class="err-box">미리보기 결과 JSON 파싱에 실패했습니다. 원본 결과(JSON) 보기를 확인하세요.</div>';
          }
      }
    }
  }

  document.addEventListener('input', function(e){
    const t = e.target;
    if (t && t.classList && t.classList.contains('table-filter')) {
      applyTableFilters(t.getAttribute('data-target'));
    }
  });

  form.addEventListener('submit', function(e){
    e.preventDefault();
    const loadingOverlay = document.getElementById('loadingOverlay');
    const submitter = e.submitter;
    const submittedMode = (submitter && submitter.name === 'mode') ? submitter.value : 'preview';

    if (modeHidden) {
      modeHidden.value = submittedMode;
    }
    if (submittedMode === 'apply') {
      const disable = currentDisableSummary || {};
      const disableTotal = Number(disable.ai_disabled || 0) + Number(disable.di_map_disabled || 0) + Number(disable.di_tag_disabled || 0);
      if (disableTotal > 0 && (!confirmDisable || !confirmDisable.checked)) {
        alert('이번 적용은 기존 활성 매핑을 비활성화합니다. preview 결과를 확인한 뒤 체크박스를 선택해야 적용할 수 있습니다.');
        return;
      }
    }
    if (submittedMode === 'apply' && overridesJson) {
      overridesJson.value = JSON.stringify(collectOverrides());
    }
    
    const f = fileInput.files && fileInput.files[0];
    const excelPathValue = excelPathInput ? String(excelPathInput.value || '').trim() : '';
    if (!f && !excelPathValue) {
      alert('파일 선택 없음');
      if (fileInput) fileInput.focus();
      return;
    }
    const runAjaxSubmit = function() {
        loadingOverlay.style.display = 'flex';
        const formData = new FormData(form);
        fetch(form.action, {
            method: 'POST',
            body: formData
        })
        .then(response => response.text())
        .then(html => {
            const parser = new DOMParser();
            const doc = parser.parseFromString(html, 'text/html');
            const newPageWrap = doc.querySelector('.page-wrap');
            if (newPageWrap) {
                document.querySelector('.page-wrap').innerHTML = newPageWrap.innerHTML;
                const newScript = doc.querySelector('script');
                if (newScript) {
                   // Re-run the script to initialize event handlers and render previews
                   // A bit of a hack, but necessary in this architecture
                   try {
                       eval(newScript.innerText);
                   } catch(e) {
                       console.error("Error re-initializing script:", e);
                   }
                }
            } else {
                 document.getElementById('result-container').innerHTML = '<div class="err-box">응답 처리 중 오류가 발생했습니다. 페이지를 새로고침하세요.</div>';
            }
        })
        .catch(err => {
            console.error('Fetch error:', err);
            document.getElementById('result-container').innerHTML = '<div class="err-box">요청 실패: ' + err.message + '</div>';
        })
        .finally(() => {
            loadingOverlay.style.display = 'none';
        });
    };

    if (f) {
        const reader = new FileReader();
        reader.onload = function(ev){
          uploadName.value = f.name || '';
          uploadB64.value = String(ev.target.result || '');
          runAjaxSubmit();
        };
        reader.readAsDataURL(f);
    } else {
        uploadName.value = '';
        uploadB64.value = '';
        runAjaxSubmit();
    }
  });
}

// Initial call
initializeScript();
</script>
</body>
</html>

