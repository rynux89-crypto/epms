<%@ page import="java.io.*,java.net.*,java.util.*"
    contentType="text/html; charset=UTF-8"
    pageEncoding="UTF-8"
    trimDirectiveWhitespaces="true" %>
<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
%>
<%!
private String trimToNull(String s) {
    if (s == null) return null;
    String t = s.trim();
    return t.isEmpty() ? null : t;
}

private Integer parsePositiveInt(String s) {
    if (s == null) return null;
    try {
        int v = Integer.parseInt(s.trim());
        if (v <= 0) return null;
        return Integer.valueOf(v);
    } catch (Exception ignore) {
        return null;
    }
}

private String esc(String s) {
    if (s == null) return "";
    return s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;");
}

private File getModelConfigFile(javax.servlet.ServletContext app) {
    if (app == null) return null;
    String epmsPath = app.getRealPath("/epms");
    if (epmsPath == null || epmsPath.isEmpty()) return null;
    return new File(epmsPath, "agent_model.properties");
}

private Properties loadModelConfig(javax.servlet.ServletContext app) {
    Properties p = new Properties();
    File file = getModelConfigFile(app);
    if (file == null || !file.exists() || !file.isFile()) return p;
    try (InputStream in = new FileInputStream(file);
         Reader reader = new InputStreamReader(in, "UTF-8")) {
        p.load(reader);
    } catch (Exception ignore) {
    }
    return p;
}

private void saveModelConfig(javax.servlet.ServletContext app, String model, String coderModel, int schemaCacheTtlMinutes) throws Exception {
    File file = getModelConfigFile(app);
    if (file == null) throw new IOException("Config path unavailable");
    Properties p = new Properties();
    p.setProperty("model", model);
    p.setProperty("coder_model", coderModel);
    p.setProperty("schema_cache_ttl_minutes", String.valueOf(schemaCacheTtlMinutes));
    p.setProperty("updated_at", new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new java.util.Date()));
    try (OutputStream out = new FileOutputStream(file);
         Writer writer = new OutputStreamWriter(out, "UTF-8")) {
        p.store(writer, "Agent model selection");
    }
}

private List<String> parseModelNames(String json) {
    LinkedHashSet<String> set = new LinkedHashSet<String>();
    if (json == null) return new ArrayList<String>(set);
    java.util.regex.Matcher m = java.util.regex.Pattern
        .compile("\"name\"\\s*:\\s*\"([^\"]+)\"")
        .matcher(json);
    while (m.find()) {
        String name = trimToNull(m.group(1));
        if (name != null) set.add(name);
    }
    return new ArrayList<String>(set);
}

private List<String> fetchOllamaModels(String ollamaUrl) throws Exception {
    URL listUrl = new URL(ollamaUrl + "/api/tags");
    HttpURLConnection conn = (HttpURLConnection) listUrl.openConnection();
    conn.setRequestMethod("GET");
    conn.setConnectTimeout(3000);
    conn.setReadTimeout(5000);
    int code = conn.getResponseCode();
    if (code != 200) throw new IOException("Ollama status " + code);
    StringBuilder sb = new StringBuilder();
    try (BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream(), "UTF-8"))) {
        String line;
        while ((line = br.readLine()) != null) sb.append(line);
    }
    return parseModelNames(sb.toString());
}
%>
<%
String ollamaUrl = System.getenv("OLLAMA_URL");
if (ollamaUrl == null || ollamaUrl.isEmpty()) ollamaUrl = "http://localhost:11434";

String envModel = System.getenv("OLLAMA_MODEL");
if (envModel == null || envModel.isEmpty()) envModel = "qwen2.5:14b";
String envCoderModel = System.getenv("OLLAMA_MODEL_CODER");
if (envCoderModel == null || envCoderModel.isEmpty()) envCoderModel = "qwen2.5-coder:7b";

Properties modelConfig = loadModelConfig(application);
String selectedModel = trimToNull(modelConfig.getProperty("model"));
String selectedCoderModel = trimToNull(modelConfig.getProperty("coder_model"));
Integer selectedSchemaCacheTtlMinutes = parsePositiveInt(trimToNull(modelConfig.getProperty("schema_cache_ttl_minutes")));
if (selectedSchemaCacheTtlMinutes == null) selectedSchemaCacheTtlMinutes = Integer.valueOf(5);
if (selectedModel == null) selectedModel = envModel;
if (selectedCoderModel == null) selectedCoderModel = envCoderModel;

String successMsg = null;
String errorMsg = null;
List<String> models = new ArrayList<String>();

try {
    models = fetchOllamaModels(ollamaUrl);
} catch (Exception e) {
    errorMsg = "Ollama 모델 목록 조회 실패: " + e.getMessage();
}

if ("POST".equalsIgnoreCase(request.getMethod())) {
    String action = trimToNull(request.getParameter("action"));
    if ("reset".equals(action)) {
        File file = getModelConfigFile(application);
        if (file != null && file.exists()) {
            if (!file.delete()) {
                errorMsg = "설정 파일 삭제 실패: " + file.getAbsolutePath();
            } else {
                selectedModel = envModel;
                selectedCoderModel = envCoderModel;
                selectedSchemaCacheTtlMinutes = Integer.valueOf(5);
                successMsg = "모델 설정을 기본값(환경변수)으로 되돌렸습니다. 즉시 반영됩니다.";
            }
        } else {
            selectedModel = envModel;
            selectedCoderModel = envCoderModel;
            selectedSchemaCacheTtlMinutes = Integer.valueOf(5);
            successMsg = "이미 기본값(환경변수) 상태입니다.";
        }
    } else {
        String nextModel = trimToNull(request.getParameter("model"));
        String nextCoderModel = trimToNull(request.getParameter("coder_model"));
        Integer nextSchemaCacheTtlMinutes = parsePositiveInt(trimToNull(request.getParameter("schema_cache_ttl_minutes")));
        if (nextModel == null || nextCoderModel == null || nextSchemaCacheTtlMinutes == null) {
            errorMsg = "모델과 스키마 캐시 시간을 모두 입력해 주세요.";
        } else if (nextSchemaCacheTtlMinutes.intValue() < 1 || nextSchemaCacheTtlMinutes.intValue() > 1440) {
            errorMsg = "스키마 캐시 시간은 1~1440분으로 입력해 주세요.";
        } else if (!models.isEmpty() && (!models.contains(nextModel) || !models.contains(nextCoderModel))) {
            errorMsg = "선택한 모델이 현재 Ollama 목록에 없습니다.";
        } else {
            try {
                saveModelConfig(application, nextModel, nextCoderModel, nextSchemaCacheTtlMinutes.intValue());
                selectedModel = nextModel;
                selectedCoderModel = nextCoderModel;
                selectedSchemaCacheTtlMinutes = nextSchemaCacheTtlMinutes;
                successMsg = "저장 완료: agent.jsp에 즉시 적용됩니다.";
            } catch (Exception e) {
                errorMsg = "저장 실패: " + e.getMessage();
            }
        }
    }
}
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Agent 모델 관리</title>
    <style>
        :root {
            --bg: #f6f8fb;
            --card: #ffffff;
            --text: #1c2330;
            --muted: #677186;
            --primary: #1565c0;
            --border: #d7deea;
            --ok-bg: #e8f5e9;
            --ok-text: #1b5e20;
            --err-bg: #ffebee;
            --err-text: #b71c1c;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: "Segoe UI", Arial, sans-serif;
            background: linear-gradient(160deg, #eef4ff 0%, var(--bg) 60%);
            color: var(--text);
        }
        .wrap {
            max-width: 840px;
            margin: 32px auto;
            padding: 0 16px;
        }
        .card {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 22px;
            box-shadow: 0 8px 24px rgba(22, 40, 80, 0.06);
        }
        h1 {
            margin: 0 0 8px 0;
            font-size: 24px;
        }
        .sub {
            margin: 0 0 20px 0;
            color: var(--muted);
            font-size: 14px;
        }
        .grid {
            display: grid;
            grid-template-columns: 180px 1fr;
            gap: 10px 14px;
            align-items: center;
            margin-bottom: 16px;
        }
        .label {
            color: var(--muted);
            font-size: 14px;
        }
        select {
            width: 100%;
            padding: 9px 10px;
            border: 1px solid var(--border);
            border-radius: 8px;
            font-size: 14px;
            background: #fff;
            color: var(--text);
        }
        .msg {
            margin: 14px 0;
            padding: 10px 12px;
            border-radius: 8px;
            font-size: 14px;
        }
        .ok { background: var(--ok-bg); color: var(--ok-text); }
        .err { background: var(--err-bg); color: var(--err-text); }
        .row {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
        }
        button {
            border: 0;
            border-radius: 8px;
            padding: 10px 14px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
        }
        .primary { background: var(--primary); color: #fff; }
        .ghost { background: #eef2f7; color: #2f3c50; }
        code {
            background: #f2f5fa;
            border: 1px solid #e0e6f0;
            border-radius: 6px;
            padding: 2px 6px;
            font-size: 13px;
        }
        @media (max-width: 720px) {
            .grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="wrap">
    <div class="card">
        <h1>Agent 모델 관리</h1>
        <p class="sub">Ollama 등록 모델에서 선택하면 저장 직후 <code>agent.jsp</code> 요청부터 즉시 적용됩니다.</p>

        <% if (successMsg != null) { %>
        <div class="msg ok"><%= esc(successMsg) %></div>
        <% } %>
        <% if (errorMsg != null) { %>
        <div class="msg err"><%= esc(errorMsg) %></div>
        <% } %>

        <div class="grid">
            <div class="label">Ollama URL</div>
            <div><code><%= esc(ollamaUrl) %></code></div>

            <div class="label">현재 적용 모델</div>
            <div><code><%= esc(selectedModel) %></code></div>

            <div class="label">현재 적용 코더 모델</div>
            <div><code><%= esc(selectedCoderModel) %></code></div>

            <div class="label">스키마 캐시 시간(분)</div>
            <div><code><%= selectedSchemaCacheTtlMinutes %></code></div>
        </div>

        <form method="post">
            <div class="grid">
                <label class="label" for="model">대화 모델</label>
                <select id="model" name="model" required>
                    <% for (String m : models) { %>
                    <option value="<%= esc(m) %>" <%= m.equals(selectedModel) ? "selected" : "" %>><%= esc(m) %></option>
                    <% } %>
                </select>

                <label class="label" for="coder_model">코더 모델</label>
                <select id="coder_model" name="coder_model" required>
                    <% for (String m : models) { %>
                    <option value="<%= esc(m) %>" <%= m.equals(selectedCoderModel) ? "selected" : "" %>><%= esc(m) %></option>
                    <% } %>
                </select>

                <label class="label" for="schema_cache_ttl_minutes">스키마 캐시 시간(분)</label>
                <input id="schema_cache_ttl_minutes"
                       name="schema_cache_ttl_minutes"
                       type="number"
                       min="1"
                       max="1440"
                       value="<%= selectedSchemaCacheTtlMinutes %>"
                       required
                       style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">
            </div>
            <div class="row">
                <button class="primary" type="submit">저장하고 즉시 적용</button>
            </div>
        </form>

        <form method="post" style="margin-top:8px;">
            <input type="hidden" name="action" value="reset">
            <div class="row">
                <button class="ghost" type="submit">기본값(환경변수)으로 복원</button>
            </div>
        </form>
    </div>
</div>
</body>
</html>
