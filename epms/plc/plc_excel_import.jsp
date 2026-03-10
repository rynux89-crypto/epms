<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="java.nio.file.*" %>
<%@ page import="java.util.Base64" %>
<%@ include file="../../includes/dbconn.jsp" %>
<%@ include file="../../includes/epms_html.jspf" %>
<%
    request.setCharacterEncoding("UTF-8");

    List<Map<String, Object>> plcList = new ArrayList<>();
    String error = null;
    String resultText = null;
    String mode = "preview";
    Integer plcId = null;
    String byteOrder = "CDAB";
    int floatCount = 62;
    String excelPath = "docs/plc_mapping_template.xlsx";

    Set<String> allowedByteOrders = new HashSet<>(Arrays.asList("ABCD", "BADC", "CDAB", "DCBA"));

    try {
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
                    } else {
                        Path p = Paths.get(excelPath);
                        if (!p.isAbsolute()) {
                            String root = application.getRealPath("/");
                            if (root != null) p = Paths.get(root).resolve(excelPath);
                        }
                        runExcelPath = p.toString();
                    }

                    String rootPath = application.getRealPath("/");
                    if (rootPath == null) rootPath = new File(".").getCanonicalPath();
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
                    } else {
                        error = "매핑 실행 실패(exit=" + exit + ")\n" + outBuf;
                    }
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
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>PLC Excel 자동 매핑 (AI + DI)</h2>
        <div style="display:flex; gap:8px;">
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

            <div class="row-full btn-group">
                <button type="submit" name="mode" value="preview">미리보기</button>
                <button type="submit" name="mode" value="apply">적용</button>
            </div>
        </div>
        <input type="hidden" name="upload_name" id="upload_name">
        <input type="hidden" name="upload_b64" id="upload_b64">
        <input type="hidden" name="mode_hidden" id="mode_hidden" value="preview">
    </form>
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

  function esc(s){
    return String(s == null ? '' : s)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  }

  function renderSummary(obj){
    if (!resultSummary || !obj || !obj.ok) return;
    const unmatched = Array.isArray(obj.ai_unmatched) ? obj.ai_unmatched : [];
    const html =
      '<div class="info-box">미리보기는 DB를 변경하지 않습니다. 적용 버튼을 누르면 실제 반영됩니다.</div>' +
      '<div class="result-grid">' +
      '<div class="result-card"><div class="k">대상 PLC</div><div class="v">' + esc(obj.plc_id) + '</div></div>' +
      '<div class="result-card"><div class="k">AI 매핑 예정</div><div class="v">' + esc(obj.ai_rows) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">DI 주소맵 예정</div><div class="v">' + esc(obj.di_map_rows) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">DI 태그맵 예정</div><div class="v">' + esc(obj.di_tag_rows) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">Float Count(적용)</div><div class="v">' + esc(obj.float_count_used) + '</div></div>' +
      '<div class="result-card"><div class="k">AI 미매칭</div><div class="v">' + esc(unmatched.length) + ' 건</div></div>' +
      '<div class="result-card"><div class="k">실행 모드</div><div class="v">' + esc(obj.mode) + '</div></div>' +
      '</div>';

    let warn = '';
    if (unmatched.length > 0) {
      warn = '<div class="warn-box"><b>확인 필요:</b> AI 미매칭 항목이 있습니다.<br/>' +
        unmatched.slice(0, 10).map(function(x){ return '- ' + esc(x); }).join('<br/>') +
        (unmatched.length > 10 ? '<br/>... 외 ' + esc(unmatched.length - 10) + '건' : '') +
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
    resultSummary.innerHTML = html + warn + floatInfo + floatDistInfo + floatMeterInfo;
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
