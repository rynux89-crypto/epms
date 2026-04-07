package epms.util;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.Reader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import javax.servlet.ServletContext;

public final class AgentSupport {
    private AgentSupport() {
    }

    public static final class RuntimeConfig {
        public String ollamaUrl;
        public String model;
        public String coderModel;
        public String aiModel;
        public String pqModel;
        public String alarmModel;
        public int ollamaConnectTimeoutMs;
        public int ollamaReadTimeoutMs;
        public long schemaCacheTtlMs;
    }

    public static final class HttpResponse {
        public int statusCode;
        public String body;
    }

    public enum QueryMode {
        DEFAULT,
        LLM_ONLY,
        RULE_ONLY
    }

    public static final class ParsedQuery {
        public QueryMode mode;
        public String userMessage;
        public boolean prefersNarrativeLlm;
    }

    public static String trimToNull(String s) {
        return EpmsWebUtil.trimToNull(s);
    }

    public static String normalizeOllamaUrl(String s) {
        String t = trimToNull(s);
        if (t == null) {
            return null;
        }
        while (t.endsWith("/")) {
            t = t.substring(0, t.length() - 1);
        }
        return t;
    }

    public static Integer parsePositiveInt(String s) {
        return EpmsWebUtil.parsePositiveInt(s);
    }

    public static ParsedQuery parseQuery(String rawMessage) {
        ParsedQuery parsed = new ParsedQuery();
        String message = trimToNull(rawMessage);
        if (message == null) {
            parsed.mode = QueryMode.DEFAULT;
            parsed.userMessage = "";
            parsed.prefersNarrativeLlm = false;
            return parsed;
        }

        parsed.mode = QueryMode.DEFAULT;
        parsed.userMessage = message.trim();
        String lower = parsed.userMessage.toLowerCase(java.util.Locale.ROOT);
        if (lower.startsWith("/llm ")) {
            parsed.mode = QueryMode.LLM_ONLY;
            parsed.userMessage = parsed.userMessage.substring(5).trim();
        } else if (lower.startsWith("/rule ")) {
            parsed.mode = QueryMode.RULE_ONLY;
            parsed.userMessage = parsed.userMessage.substring(6).trim();
        }
        parsed.prefersNarrativeLlm = prefersNarrativeLlm(parsed.userMessage);
        return parsed;
    }

    public static boolean prefersNarrativeLlm(String userMessage) {
        String m = normalizeIntent(userMessage);
        boolean hasNarrativeIntent =
            m.contains("해석") || m.contains("설명") || m.contains("요약")
            || m.contains("보고서") || m.contains("분석") || m.contains("평가")
            || m.contains("추론") || m.contains("진단") || m.contains("브리핑");
        boolean hasCombinedIntent =
            (m.contains("계측") || m.contains("상태") || m.contains("측정"))
            && (m.contains("알람") || m.contains("경보"));
        return hasNarrativeIntent && hasCombinedIntent;
    }

    public static Properties loadAgentModelConfig(ServletContext app) {
        Properties p = new Properties();
        if (app == null) {
            return p;
        }
        String epmsPath = app.getRealPath("/epms");
        if (epmsPath == null || epmsPath.isEmpty()) {
            return p;
        }
        File file = new File(epmsPath, "agent_model.properties");
        if (!file.exists() || !file.isFile()) {
            return p;
        }
        try (InputStream in = new FileInputStream(file);
             Reader reader = new InputStreamReader(in, StandardCharsets.UTF_8)) {
            p.load(reader);
        } catch (Exception ignore) {
        }
        return p;
    }

    public static long resolveSchemaCacheTtlMs(Properties modelConfig, long defaultSchemaCacheTtlMs) {
        String ttlMinutesRaw = trimToNull(modelConfig.getProperty("schema_cache_ttl_minutes"));
        Integer ttlMin = parsePositiveInt(ttlMinutesRaw);
        if (ttlMin == null) {
            return defaultSchemaCacheTtlMs;
        }
        int m = ttlMin.intValue();
        if (m < 1) {
            m = 1;
        }
        if (m > 1440) {
            m = 1440;
        }
        return m * 60L * 1000L;
    }

    public static RuntimeConfig loadAgentRuntimeConfig(ServletContext app, long defaultSchemaCacheTtlMs) {
        RuntimeConfig cfg = new RuntimeConfig();

        String ollamaUrl = System.getenv("OLLAMA_URL");
        if (ollamaUrl == null || ollamaUrl.isEmpty()) {
            ollamaUrl = "http://localhost:11434";
        }
        ollamaUrl = normalizeOllamaUrl(ollamaUrl);

        String model = System.getenv("OLLAMA_MODEL");
        if (model == null || model.isEmpty()) {
            model = "qwen2.5:14b";
        }

        String coderModel = System.getenv("OLLAMA_MODEL_CODER");
        if (coderModel == null || coderModel.isEmpty()) {
            coderModel = "qwen2.5-coder:7b";
        }

        String aiModel = System.getenv("OLLAMA_MODEL_AI");
        if (aiModel == null || aiModel.isEmpty()) {
            aiModel = model;
        }

        String pqModel = System.getenv("OLLAMA_MODEL_PQ");
        if (pqModel == null || pqModel.isEmpty()) {
            pqModel = model;
        }

        String alarmModel = System.getenv("OLLAMA_MODEL_ALARM");
        if (alarmModel == null || alarmModel.isEmpty()) {
            alarmModel = model;
        }

        Properties modelConfig = loadAgentModelConfig(app);
        String configuredOllamaUrl = normalizeOllamaUrl(modelConfig.getProperty("ollama_url"));
        String configuredModel = trimToNull(modelConfig.getProperty("model"));
        String configuredCoderModel = trimToNull(modelConfig.getProperty("coder_model"));
        String configuredAiModel = trimToNull(modelConfig.getProperty("ai_model"));
        String configuredPqModel = trimToNull(modelConfig.getProperty("pq_model"));
        String configuredAlarmModel = trimToNull(modelConfig.getProperty("alarm_model"));
        if (configuredOllamaUrl != null) {
            ollamaUrl = configuredOllamaUrl;
        }
        if (configuredModel != null) {
            model = configuredModel;
        }
        if (configuredCoderModel != null) {
            coderModel = configuredCoderModel;
        }
        if (configuredAiModel != null) {
            aiModel = configuredAiModel;
        }
        if (configuredPqModel != null) {
            pqModel = configuredPqModel;
        }
        if (configuredAlarmModel != null) {
            alarmModel = configuredAlarmModel;
        }

        Integer connectSec = parsePositiveInt(trimToNull(modelConfig.getProperty("ollama_connect_timeout_seconds")));
        Integer readSec = parsePositiveInt(trimToNull(modelConfig.getProperty("ollama_read_timeout_seconds")));

        cfg.ollamaUrl = ollamaUrl;
        cfg.model = model;
        cfg.coderModel = coderModel;
        cfg.aiModel = trimToNull(aiModel) == null ? model : aiModel;
        cfg.pqModel = trimToNull(pqModel) == null ? model : pqModel;
        cfg.alarmModel = trimToNull(alarmModel) == null ? model : alarmModel;
        cfg.ollamaConnectTimeoutMs = clampSeconds(connectSec, 1, 60, 5) * 1000;
        cfg.ollamaReadTimeoutMs = clampSeconds(readSec, 3, 600, 60) * 1000;
        cfg.schemaCacheTtlMs = resolveSchemaCacheTtlMs(modelConfig, defaultSchemaCacheTtlMs);
        return cfg;
    }

    public static HttpResponse callOllamaEndpoint(String url, String method, String payload, int connectTimeoutMs, int readTimeoutMs) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setRequestMethod(method);
        conn.setConnectTimeout(connectTimeoutMs);
        conn.setReadTimeout(readTimeoutMs);

        if (payload != null) {
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            try (OutputStream os = conn.getOutputStream()) {
                byte[] input = payload.getBytes(StandardCharsets.UTF_8);
                os.write(input, 0, input.length);
            }
        }

        HttpResponse resp = new HttpResponse();
        resp.statusCode = conn.getResponseCode();
        InputStream is = (resp.statusCode >= 200 && resp.statusCode < 400) ? conn.getInputStream() : conn.getErrorStream();
        resp.body = readHttpBody(is);
        return resp;
    }

    public static String fetchOllamaTagList(String ollamaUrl, int connectTimeoutMs, int readTimeoutMs) throws Exception {
        HttpResponse resp = callOllamaEndpoint(ollamaUrl + "/api/tags", "GET", null, connectTimeoutMs, readTimeoutMs);
        if (resp.statusCode != 200) {
            throw new IOException("Ollama unavailable");
        }
        return resp.body == null ? "" : resp.body;
    }

    private static int clampSeconds(Integer value, int min, int max, int fallback) {
        if (value == null) {
            return fallback;
        }
        int s = value.intValue();
        if (s < min) {
            s = min;
        }
        if (s > max) {
            s = max;
        }
        return s;
    }

    private static String readHttpBody(InputStream is) throws Exception {
        if (is == null) {
            return "";
        }
        StringBuilder body = new StringBuilder();
        try (BufferedReader br = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
            String l;
            while ((l = br.readLine()) != null) {
                body.append(l);
            }
        }
        return body.toString();
    }

    public static List<String> panelTokensFromRaw(String panel) {
        ArrayList<String> tokens = new ArrayList<String>();
        if (panel == null) return tokens;
        String candidate = panel.replaceAll("[\"'`]", " ").trim();
        if (candidate.isEmpty()) return tokens;
        String[] parts = candidate.split("[\\s_\\-]+");
        for (int i = 0; i < parts.length; i++) {
            String p = parts[i];
            if (p == null) continue;
            p = p.trim();
            p = p.replaceAll("(?i)panel", "");
            p = p.replace("패널", "").replace("판넬", "");
            p = p.trim();
            if (p.length() < 2) continue;
            if ("meter".equalsIgnoreCase(p) || "미터".equals(p)) continue;
            tokens.add(p.toUpperCase(java.util.Locale.ROOT));
        }
        return tokens;
    }

    public static String unescapeJsonText(String s) {
        if (s == null) return "";
        StringBuilder out = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch != '\\' || i + 1 >= s.length()) {
                out.append(ch);
                continue;
            }
            char next = s.charAt(++i);
            switch (next) {
                case '"':
                    out.append('"');
                    break;
                case '\\':
                    if (i + 5 < s.length() && s.charAt(i + 1) == 'u') {
                        String hex = s.substring(i + 2, i + 6);
                        try {
                            out.append((char) Integer.parseInt(hex, 16));
                            i += 5;
                            break;
                        } catch (Exception ignore) {
                        }
                    }
                    out.append('\\');
                    break;
                case '/':
                    out.append('/');
                    break;
                case 'b':
                    out.append('\b');
                    break;
                case 'f':
                    out.append('\f');
                    break;
                case 'n':
                    out.append('\n');
                    break;
                case 'r':
                    out.append('\r');
                    break;
                case 't':
                    out.append('\t');
                    break;
                case 'u':
                    if (i + 4 < s.length()) {
                        String hex = s.substring(i + 1, i + 5);
                        try {
                            out.append((char) Integer.parseInt(hex, 16));
                            i += 4;
                            break;
                        } catch (Exception ignore) {
                        }
                    }
                    out.append('\\').append('u');
                    break;
                default:
                    out.append(next);
                    break;
            }
        }
        return out.toString();
    }

    public static String extractJsonStringField(String json, String field) {
        if (json == null || field == null) return null;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(field) + "\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"", java.util.regex.Pattern.DOTALL);
            java.util.regex.Matcher m = p.matcher(json);
            if (m.find()) return unescapeJsonText(m.group(1));
        } catch (Exception ignore) {
        }
        return null;
    }

    public static Integer extractJsonIntField(String json, String field) {
        if (json == null || field == null) return null;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(field) + "\"\\s*:\\s*(\\d+)");
            java.util.regex.Matcher m = p.matcher(json);
            if (m.find()) return Integer.valueOf(m.group(1));
        } catch (Exception ignore) {
        }
        return null;
    }

    public static Boolean extractJsonBoolField(String json, String field) {
        if (json == null || field == null) return null;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(field) + "\"\\s*:\\s*(true|false)", java.util.regex.Pattern.CASE_INSENSITIVE);
            java.util.regex.Matcher m = p.matcher(json);
            if (m.find()) return Boolean.valueOf(m.group(1).toLowerCase(java.util.Locale.ROOT));
        } catch (Exception ignore) {
        }
        return null;
    }

    private static String normalizeIntent(String s) {
        if (s == null) {
            return "";
        }
        return s.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
    }
}
