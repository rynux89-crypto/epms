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
%>
<%
    request.setCharacterEncoding("UTF-8");

    final String SESSION_UPLOAD_B64 = "plcExcelImport.uploadB64";
    final String SESSION_UPLOAD_NAME = "plcExcelImport.uploadName";
    final String SESSION_UPLOAD_SOURCE = "plcExcelImport.uploadSource";

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<String> recentHistory = new ArrayList<>();
    String error = null;
    String resultText = null;
    String mode = "preview";
    Integer plcId = null;
    String byteOrder = "CDAB";
    int floatCount = 62;
    String excelPath = "docs/plc_mapping_template.xlsx";
    String runExcelPathUsed = null;
    String uploadNameUsed = null;
    String uploadSourceUsed = null;
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

            String floatCountStr = request.getParameter("float_count");
            if (floatCountStr != null && !floatCountStr.trim().isEmpty()) {
                try {
                    int parsed = Integer.parseInt(floatCountStr.trim());
                    if (parsed >= 1 && parsed <= 200) floatCount = parsed;
                } catch (Exception ignore) {}
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
                    String runExcelPath;
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
                        if (!p.isAbsolute()) {
                            String root = application.getRealPath("/");
                            if (root != null) p = Paths.get(root).resolve(excelPath);
                        }
                        runExcelPath = p.toString();
                        uploadSourceUsed = "path";
                    }
                    runExcelPathUsed = runExcelPath;

                    String scriptPath = Paths.get(rootPath).resolve("scripts").resolve("import_plc_mapping.ps1").toString();

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
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🤖 PLC Excel 자동 매핑 (AI + DI)</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        엑셀 파일을 선택하거나 서버 경로를 입력한 뒤 실행하면 아래 테이블이 자동 반영됩니다.<br/>
        대상 테이블: <span class="mono">plc_meter_map</span>, <span class="mono">plc_di_map</span>, <span class="mono">plc_di_tag_map</span><br/>
        PLC를 선택하지 않으면 엑셀의 PLC 컬럼(F2)에서 PLC를 자동 판별해 순차 적용합니다.<br/>
        미리보기: DB 변경 없이 결과 확인 / 적용: DB upsert 실행
    </div>

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
    <details>
        <summary class="muted">원본 결과(JSON) 보기</summary>
        <pre id="resultRaw"><%= h(resultText) %></pre>
    </details>
    <% } %>

    <form method="POST" id="importForm">
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

            <label for="excel_path">서버 경로</label>
            <input type="text" id="excel_path" name="excel_path" value="<%= h(excelPath) %>" class="mono">

            <label for="byte_order">Byte Order</label>
            <select id="byte_order" name="byte_order">
                <option value="ABCD" <%= "ABCD".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>ABCD</option>
                <option value="BADC" <%= "BADC".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>BADC</option>
                <option value="CDAB" <%= "CDAB".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>CDAB</option>
                <option value="DCBA" <%= "DCBA".equalsIgnoreCase(byteOrder) ? "selected" : "" %>>DCBA</option>
            </select>

            <label for="float_count">Float Count</label>
            <input type="number" id="float_count" name="float_count" min="1" max="200" value="<%= floatCount %>">

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
        <input type="hidden" name="mode_hidden" id="mode_hidden" value="preview">
    </form>

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
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>

<script>
(function(){
  const form = document.getElementById('importForm');
  const fileInput = document.getElementById('excel_file');
  const uploadName = document.getElementById('upload_name');
  const uploadB64 = document.getElementById('upload_b64');
  const modeHidden = document.getElementById('mode_hidden');
  const resultSummary = document.getElementById('resultSummary');
  const resultRaw = document.getElementById('resultRaw');
  const confirmDisable = document.getElementById('confirm_disable');
  const disableConfirmBox = document.getElementById('disableConfirmBox');
  let currentDisableSummary = null;

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
    resultSummary.innerHTML = html + perPlcInfo + warn + disableWarn + floatInfo + floatDistInfo + floatMeterInfo;
  }

  if (resultRaw) {
    const raw = resultRaw.textContent.trim();
    const s = raw.indexOf('{');
    const e = raw.lastIndexOf('}');
    if (s >= 0 && e > s) {
      const jsonText = raw.substring(s, e + 1);
      try {
        const obj = JSON.parse(jsonText);
        renderSummary(obj);
      } catch (ignore) {}
    }
  }

  form.addEventListener('submit', function(e){
    const submitter = e.submitter;
    if (modeHidden) {
      modeHidden.value = (submitter && submitter.value) ? submitter.value : (modeHidden.value || 'preview');
    }
    if (submitter && submitter.value === 'apply') {
      const disable = currentDisableSummary || {};
      const disableTotal = Number(disable.ai_disabled || 0) + Number(disable.di_map_disabled || 0) + Number(disable.di_tag_disabled || 0);
      if (disableTotal > 0 && (!confirmDisable || !confirmDisable.checked)) {
        e.preventDefault();
        alert('이번 적용은 기존 활성 매핑을 비활성화합니다. preview 결과를 확인한 뒤 체크박스를 선택해야 적용할 수 있습니다.');
        return;
      }
    }
    const f = fileInput.files && fileInput.files[0];
    if (!f) return;
    e.preventDefault();
    const reader = new FileReader();
    reader.onload = function(ev){
      uploadName.value = f.name || '';
      uploadB64.value = String(ev.target.result || '');
      form.submit();
    };
    reader.readAsDataURL(f);
  });
})();
</script>
</body>
</html>
