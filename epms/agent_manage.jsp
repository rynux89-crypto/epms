<%@ page import="java.io.*,java.net.*,java.util.*"
    contentType="text/html; charset=UTF-8"
    pageEncoding="UTF-8"
    trimDirectiveWhitespaces="true" %>
<%@ include file="../includes/epms_html.jspf" %>
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

private static class AgentManageState {
    String ollamaUrl;
    String selectedModel;
    String selectedCoderModel;
    Integer selectedSchemaCacheTtlMinutes;
    Integer selectedConnectTimeoutSeconds;
    Integer selectedReadTimeoutSeconds;
    Integer selectedChatWidthPx;
    Integer selectedChatMaxHeightVh;
    Integer selectedChatFontSizePx;
    String successMsg;
    String errorMsg;
    List<String> models = new ArrayList<String>();
}

private static class AgentManageRequest {
    String action;
    String ollamaUrl;
    String model;
    String coderModel;
    Integer schemaCacheTtlMinutes;
    Integer connectTimeoutSeconds;
    Integer readTimeoutSeconds;
    Integer chatWidthPx;
    Integer chatMaxHeightVh;
    Integer chatFontSizePx;
}

private String normalizeOllamaUrl(String s) {
    String t = trimToNull(s);
    if (t == null) return null;
    while (t.endsWith("/")) t = t.substring(0, t.length() - 1);
    return t;
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

private void saveModelConfig(javax.servlet.ServletContext app, String ollamaUrl, String model, String coderModel, int schemaCacheTtlMinutes, int ollamaConnectTimeoutSeconds, int ollamaReadTimeoutSeconds, int chatWidthPx, int chatMaxHeightVh, int chatFontSizePx) throws Exception {
    File file = getModelConfigFile(app);
    if (file == null) throw new IOException("Config path unavailable");
    Properties p = new Properties();
    p.setProperty("ollama_url", ollamaUrl);
    p.setProperty("model", model);
    p.setProperty("coder_model", coderModel);
    p.setProperty("schema_cache_ttl_minutes", String.valueOf(schemaCacheTtlMinutes));
    p.setProperty("ollama_connect_timeout_seconds", String.valueOf(ollamaConnectTimeoutSeconds));
    p.setProperty("ollama_read_timeout_seconds", String.valueOf(ollamaReadTimeoutSeconds));
    p.setProperty("chat_width_px", String.valueOf(chatWidthPx));
    p.setProperty("chat_max_height_vh", String.valueOf(chatMaxHeightVh));
    p.setProperty("chat_font_size_px", String.valueOf(chatFontSizePx));
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

private AgentManageState buildAgentManageState(javax.servlet.ServletContext application) {
    AgentManageState state = new AgentManageState();
    String envOllamaUrl = System.getenv("OLLAMA_URL");
    if (envOllamaUrl == null || envOllamaUrl.isEmpty()) envOllamaUrl = "http://localhost:11434";
    state.ollamaUrl = normalizeOllamaUrl(envOllamaUrl);

    String envModel = System.getenv("OLLAMA_MODEL");
    if (envModel == null || envModel.isEmpty()) envModel = "qwen2.5:14b";
    String envCoderModel = System.getenv("OLLAMA_MODEL_CODER");
    if (envCoderModel == null || envCoderModel.isEmpty()) envCoderModel = "qwen2.5-coder:7b";

    Properties modelConfig = loadModelConfig(application);
    String configuredOllamaUrl = normalizeOllamaUrl(modelConfig.getProperty("ollama_url"));
    if (configuredOllamaUrl != null) state.ollamaUrl = configuredOllamaUrl;
    state.selectedModel = trimToNull(modelConfig.getProperty("model"));
    state.selectedCoderModel = trimToNull(modelConfig.getProperty("coder_model"));
    state.selectedSchemaCacheTtlMinutes = parsePositiveInt(trimToNull(modelConfig.getProperty("schema_cache_ttl_minutes")));
    if (state.selectedSchemaCacheTtlMinutes == null) state.selectedSchemaCacheTtlMinutes = Integer.valueOf(5);
    state.selectedConnectTimeoutSeconds = parsePositiveInt(trimToNull(modelConfig.getProperty("ollama_connect_timeout_seconds")));
    if (state.selectedConnectTimeoutSeconds == null) state.selectedConnectTimeoutSeconds = Integer.valueOf(5);
    state.selectedReadTimeoutSeconds = parsePositiveInt(trimToNull(modelConfig.getProperty("ollama_read_timeout_seconds")));
    if (state.selectedReadTimeoutSeconds == null) state.selectedReadTimeoutSeconds = Integer.valueOf(60);
    state.selectedChatWidthPx = parsePositiveInt(trimToNull(modelConfig.getProperty("chat_width_px")));
    if (state.selectedChatWidthPx == null) state.selectedChatWidthPx = Integer.valueOf(360);
    state.selectedChatMaxHeightVh = parsePositiveInt(trimToNull(modelConfig.getProperty("chat_max_height_vh")));
    if (state.selectedChatMaxHeightVh == null) state.selectedChatMaxHeightVh = Integer.valueOf(60);
    state.selectedChatFontSizePx = parsePositiveInt(trimToNull(modelConfig.getProperty("chat_font_size_px")));
    if (state.selectedChatFontSizePx == null) state.selectedChatFontSizePx = Integer.valueOf(13);
    if (state.selectedModel == null) state.selectedModel = envModel;
    if (state.selectedCoderModel == null) state.selectedCoderModel = envCoderModel;
    return state;
}

private AgentManageRequest buildAgentManageRequest(javax.servlet.http.HttpServletRequest request) {
    AgentManageRequest req = new AgentManageRequest();
    req.action = trimToNull(request.getParameter("action"));
    req.ollamaUrl = normalizeOllamaUrl(request.getParameter("ollama_url"));
    req.model = trimToNull(request.getParameter("model"));
    req.coderModel = trimToNull(request.getParameter("coder_model"));
    req.schemaCacheTtlMinutes = parsePositiveInt(trimToNull(request.getParameter("schema_cache_ttl_minutes")));
    req.connectTimeoutSeconds = parsePositiveInt(trimToNull(request.getParameter("ollama_connect_timeout_seconds")));
    req.readTimeoutSeconds = parsePositiveInt(trimToNull(request.getParameter("ollama_read_timeout_seconds")));
    req.chatWidthPx = parsePositiveInt(trimToNull(request.getParameter("chat_width_px")));
    req.chatMaxHeightVh = parsePositiveInt(trimToNull(request.getParameter("chat_max_height_vh")));
    req.chatFontSizePx = parsePositiveInt(trimToNull(request.getParameter("chat_font_size_px")));
    return req;
}

private void applyDefaultAgentManageState(AgentManageState state) {
    String envOllamaUrl = System.getenv("OLLAMA_URL");
    if (envOllamaUrl == null || envOllamaUrl.isEmpty()) envOllamaUrl = "http://localhost:11434";
    state.ollamaUrl = normalizeOllamaUrl(envOllamaUrl);

    String envModel = System.getenv("OLLAMA_MODEL");
    if (envModel == null || envModel.isEmpty()) envModel = "qwen2.5:14b";
    String envCoderModel = System.getenv("OLLAMA_MODEL_CODER");
    if (envCoderModel == null || envCoderModel.isEmpty()) envCoderModel = "qwen2.5-coder:7b";

    state.selectedModel = envModel;
    state.selectedCoderModel = envCoderModel;
    state.selectedSchemaCacheTtlMinutes = Integer.valueOf(5);
    state.selectedConnectTimeoutSeconds = Integer.valueOf(5);
    state.selectedReadTimeoutSeconds = Integer.valueOf(60);
    state.selectedChatWidthPx = Integer.valueOf(360);
    state.selectedChatMaxHeightVh = Integer.valueOf(60);
    state.selectedChatFontSizePx = Integer.valueOf(13);
}

private String validateAgentManageRequest(AgentManageRequest req, List<String> models) {
    if (req.ollamaUrl == null || req.model == null || req.coderModel == null ||
        req.schemaCacheTtlMinutes == null || req.connectTimeoutSeconds == null ||
        req.readTimeoutSeconds == null || req.chatWidthPx == null ||
        req.chatMaxHeightVh == null || req.chatFontSizePx == null) {
        return "모델, 스키마 캐시 시간, 타임아웃, 채팅 UI 값을 모두 입력해 주세요.";
    }
    if (!req.ollamaUrl.startsWith("http://") && !req.ollamaUrl.startsWith("https://")) {
        return "Ollama URL은 http:// 또는 https:// 로 시작해야 합니다.";
    }
    if (req.schemaCacheTtlMinutes.intValue() < 1 || req.schemaCacheTtlMinutes.intValue() > 1440) {
        return "스키마 캐시 시간은 1~1440분으로 입력해 주세요.";
    }
    if (req.connectTimeoutSeconds.intValue() < 1 || req.connectTimeoutSeconds.intValue() > 60) {
        return "연결 타임아웃은 1~60초로 입력해 주세요.";
    }
    if (req.readTimeoutSeconds.intValue() < 3 || req.readTimeoutSeconds.intValue() > 600) {
        return "응답 타임아웃은 3~600초로 입력해 주세요.";
    }
    if (req.chatWidthPx.intValue() < 300 || req.chatWidthPx.intValue() > 560) {
        return "챗창 폭은 300~560px 범위로 입력해 주세요.";
    }
    if (req.chatMaxHeightVh.intValue() < 40 || req.chatMaxHeightVh.intValue() > 90) {
        return "챗창 최대 높이는 40~90vh 범위로 입력해 주세요.";
    }
    if (req.chatFontSizePx.intValue() < 12 || req.chatFontSizePx.intValue() > 20) {
        return "챗 글자 크기는 12~20px 범위로 입력해 주세요.";
    }
    if (!models.isEmpty() && (!models.contains(req.model) || !models.contains(req.coderModel))) {
        return "선택한 모델이 현재 Ollama 목록에 없습니다.";
    }
    return null;
}
%>
<%
AgentManageState state = buildAgentManageState(application);

try {
    state.models = fetchOllamaModels(state.ollamaUrl);
} catch (Exception e) {
    state.errorMsg = "Ollama 모델 목록 조회 실패: " + e.getMessage();
}

if ("POST".equalsIgnoreCase(request.getMethod())) {
    AgentManageRequest formReq = buildAgentManageRequest(request);
    if ("reset".equals(formReq.action)) {
        File file = getModelConfigFile(application);
        if (file != null && file.exists()) {
            if (!file.delete()) {
                state.errorMsg = "설정 파일 삭제 실패: " + file.getAbsolutePath();
            } else {
                applyDefaultAgentManageState(state);
                state.successMsg = "모델 설정을 기본값(환경변수)으로 복원했습니다. 즉시 반영됩니다.";
            }
        } else {
            applyDefaultAgentManageState(state);
            state.successMsg = "이미 기본값(환경변수) 상태입니다.";
        }
    } else {
        if (formReq.ollamaUrl != null && !formReq.ollamaUrl.equals(state.ollamaUrl)) {
            try {
                state.models = fetchOllamaModels(formReq.ollamaUrl);
            } catch (Exception e) {
                state.errorMsg = "Ollama model list fetch failed: " + e.getMessage();
            }
        }
        if (state.errorMsg == null) {
            state.errorMsg = validateAgentManageRequest(formReq, state.models);
        }
        if (state.errorMsg == null) {
            try {
                saveModelConfig(
                    application,
                    formReq.ollamaUrl,
                    formReq.model,
                    formReq.coderModel,
                    formReq.schemaCacheTtlMinutes.intValue(),
                    formReq.connectTimeoutSeconds.intValue(),
                    formReq.readTimeoutSeconds.intValue(),
                    formReq.chatWidthPx.intValue(),
                    formReq.chatMaxHeightVh.intValue(),
                    formReq.chatFontSizePx.intValue()
                );
                state.selectedModel = formReq.model;
                state.selectedCoderModel = formReq.coderModel;
                state.selectedSchemaCacheTtlMinutes = formReq.schemaCacheTtlMinutes;
                state.selectedConnectTimeoutSeconds = formReq.connectTimeoutSeconds;
                state.selectedReadTimeoutSeconds = formReq.readTimeoutSeconds;
                state.selectedChatWidthPx = formReq.chatWidthPx;
                state.selectedChatMaxHeightVh = formReq.chatMaxHeightVh;
                state.selectedChatFontSizePx = formReq.chatFontSizePx;
                state.ollamaUrl = formReq.ollamaUrl;
                state.successMsg = "저장 완료: agent.jsp에 즉시 적용됩니다.";
            } catch (Exception e) {
                state.errorMsg = "저장 실패: " + e.getMessage();
            }
        } else {
            state.successMsg = null;
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
        .split-panels {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 14px;
            margin-bottom: 16px;
        }
        .panel-box {
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 14px;
            background: #fff;
            box-shadow: 0 4px 14px rgba(22, 40, 80, 0.04);
        }
        .panel-title {
            margin: 0 0 10px 0;
            font-size: 15px;
            font-weight: 700;
            color: #22324a;
        }
        .section-title {
            margin: 2px 0 8px 0;
            color: var(--muted);
            font-size: 13px;
            font-weight: 600;
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
            .split-panels { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="wrap">
    <div class="card">
        <h1>Agent 모델 관리</h1>
        <p class="sub">Ollama 등록 모델에서 선택하면 저장 직후 <code>agent.jsp</code> 요청부터 즉시 적용됩니다.</p>

        <% if (state.successMsg != null) { %>
        <div class="msg ok"><%= h(state.successMsg) %></div>
        <% } %>
        <% if (state.errorMsg != null) { %>
        <div class="msg err"><%= h(state.errorMsg) %></div>
        <% } %>

        <form method="post">
            <div class="split-panels">
                <div class="panel-box">
                    <h3 class="panel-title">AI 모델 설정</h3>
                    <div class="section-title">현재 적용값</div>
                    <div class="grid">
                        <div class="label">Ollama URL</div>
                        <div><code><%= h(state.ollamaUrl) %></code></div>
                        <div class="label">대화 모델</div>
                        <div><code><%= h(state.selectedModel) %></code></div>
                        <div class="label">코더 모델</div>
                        <div><code><%= h(state.selectedCoderModel) %></code></div>
                        <div class="label">스키마 캐시(분)</div>
                        <div><code><%= state.selectedSchemaCacheTtlMinutes %></code></div>
                        <div class="label">연결 타임아웃(초)</div>
                        <div><code><%= state.selectedConnectTimeoutSeconds %></code></div>
                        <div class="label">응답 타임아웃(초)</div>
                        <div><code><%= state.selectedReadTimeoutSeconds %></code></div>
                    </div>
                    <div class="section-title">변경값 입력</div>
                    <div class="grid">
                        <label class="label" for="ollama_url">Ollama URL</label>
                        <input id="ollama_url"
                               name="ollama_url"
                               type="text"
                               value="<%= h(state.ollamaUrl) %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">
                        <label class="label" for="model">대화 모델</label>
                        <select id="model" name="model" required>
                            <% for (String m : state.models) { %>
                            <option value="<%= h(m) %>" <%= m.equals(state.selectedModel) ? "selected" : "" %>><%= h(m) %></option>
                            <% } %>
                        </select>

                        <label class="label" for="coder_model">코더 모델</label>
                        <select id="coder_model" name="coder_model" required>
                            <% for (String m : state.models) { %>
                            <option value="<%= h(m) %>" <%= m.equals(state.selectedCoderModel) ? "selected" : "" %>><%= h(m) %></option>
                            <% } %>
                        </select>

                        <label class="label" for="schema_cache_ttl_minutes">스키마 캐시 시간(분)</label>
                        <input id="schema_cache_ttl_minutes"
                               name="schema_cache_ttl_minutes"
                               type="number"
                               min="1"
                               max="1440"
                               value="<%= state.selectedSchemaCacheTtlMinutes %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">

                        <label class="label" for="ollama_connect_timeout_seconds">연결 타임아웃(초)</label>
                        <input id="ollama_connect_timeout_seconds"
                               name="ollama_connect_timeout_seconds"
                               type="number"
                               min="1"
                               max="60"
                               value="<%= state.selectedConnectTimeoutSeconds %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">

                        <label class="label" for="ollama_read_timeout_seconds">응답 타임아웃(초)</label>
                        <input id="ollama_read_timeout_seconds"
                               name="ollama_read_timeout_seconds"
                               type="number"
                               min="3"
                               max="600"
                               value="<%= state.selectedReadTimeoutSeconds %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">
                    </div>
                </div>

                <div class="panel-box">
                    <h3 class="panel-title">채팅창 설정</h3>
                    <div class="section-title">현재 적용값</div>
                    <div class="grid">
                        <div class="label">채팅창 폭(px)</div>
                        <div><code><%= state.selectedChatWidthPx %></code></div>
                        <div class="label">채팅창 최대 높이(vh)</div>
                        <div><code><%= state.selectedChatMaxHeightVh %></code></div>
                        <div class="label">채팅 글자 크기(px)</div>
                        <div><code><%= state.selectedChatFontSizePx %></code></div>
                    </div>
                    <div class="section-title">변경값 입력</div>
                    <div class="grid">
                        <label class="label" for="chat_width_px">채팅창 폭(px)</label>
                        <input id="chat_width_px"
                               name="chat_width_px"
                               type="number"
                               min="300"
                               max="560"
                               value="<%= state.selectedChatWidthPx %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">

                        <label class="label" for="chat_max_height_vh">채팅창 최대 높이(vh)</label>
                        <input id="chat_max_height_vh"
                               name="chat_max_height_vh"
                               type="number"
                               min="40"
                               max="90"
                               value="<%= state.selectedChatMaxHeightVh %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">

                        <label class="label" for="chat_font_size_px">채팅 글자 크기(px)</label>
                        <input id="chat_font_size_px"
                               name="chat_font_size_px"
                               type="number"
                               min="12"
                               max="20"
                               value="<%= state.selectedChatFontSizePx %>"
                               required
                               style="width:100%;padding:9px 10px;border:1px solid var(--border);border-radius:8px;font-size:14px;background:#fff;color:var(--text);">
                    </div>
                </div>
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

