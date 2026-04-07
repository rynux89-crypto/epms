package epms.util;

import javax.servlet.ServletContext;
import java.util.Properties;

public final class AgentRuntimeFlowSupport {
    private AgentRuntimeFlowSupport() {
    }

    public static String resolveSpecializedModel(
        ServletContext application,
        String propertyName,
        String envName,
        String fallbackModel
    ) {
        Properties modelConfig = AgentSupport.loadAgentModelConfig(application);
        String configured = AgentSupport.trimToNull(modelConfig.getProperty(propertyName));
        if (configured != null) {
            return configured;
        }
        String envValue = AgentSupport.trimToNull(System.getenv(envName));
        if (envValue != null) {
            return envValue;
        }
        return fallbackModel;
    }

    public static AgentRuntimeModels.RuntimeModelSelection resolveRuntimeModels(
        ServletContext application,
        long defaultSchemaCacheTtlMs
    ) {
        AgentSupport.RuntimeConfig runtimeConfig = AgentSupport.loadAgentRuntimeConfig(application, defaultSchemaCacheTtlMs);
        AgentRuntimeModels.RuntimeModelSelection selection = new AgentRuntimeModels.RuntimeModelSelection();
        selection.ollamaUrl = runtimeConfig.ollamaUrl;
        selection.model = runtimeConfig.model;
        selection.coderModel = runtimeConfig.coderModel;
        selection.aiModel = resolveSpecializedModel(application, "ai_model", "OLLAMA_MODEL_AI", selection.model);
        selection.pqModel = resolveSpecializedModel(application, "pq_model", "OLLAMA_MODEL_PQ", selection.model);
        selection.alarmModel = resolveSpecializedModel(application, "alarm_model", "OLLAMA_MODEL_ALARM", selection.model);
        selection.ollamaConnectTimeoutMs = runtimeConfig.ollamaConnectTimeoutMs;
        selection.ollamaReadTimeoutMs = runtimeConfig.ollamaReadTimeoutMs;
        selection.schemaCacheTtlMs = runtimeConfig.schemaCacheTtlMs;
        return selection;
    }

    public static String validateAvailableModels(
        String ollamaUrl,
        int connectTimeoutMs,
        int readTimeoutMs,
        String defaultModel,
        String coderModel,
        String aiModel,
        String pqModel,
        String alarmModel
    ) throws Exception {
        String tagJson = AgentSupport.fetchOllamaTagList(ollamaUrl, connectTimeoutMs, readTimeoutMs);
        assertModelExists(tagJson, defaultModel);
        assertModelExists(tagJson, coderModel);
        if (AgentSupport.trimToNull(aiModel) != null) {
            assertModelExists(tagJson, aiModel);
        }
        if (AgentSupport.trimToNull(pqModel) != null) {
            assertModelExists(tagJson, pqModel);
        }
        if (AgentSupport.trimToNull(alarmModel) != null) {
            assertModelExists(tagJson, alarmModel);
        }
        return tagJson;
    }

    public static String buildClassifierPrompt(String userMessage) {
        return "Classify if EPMS DB lookup is needed. "
            + "Return only one JSON object with keys: needs_db(boolean), needs_meter(boolean), needs_alarm(boolean), "
            + "needs_frequency(boolean), needs_power_by_meter(boolean), needs_meter_list(boolean), "
            + "needs_phase_current(boolean), needs_phase_voltage(boolean), needs_line_voltage(boolean), "
            + "needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null), "
            + "meter_scope(string|null), phase(string|null), line_pair(string|null). "
            + "No markdown. No explanation.\n\nUser: "
            + userMessage;
    }

    public static String buildFinalPrompt(boolean needsDb, String userMessage, String dbContext) {
        return AgentResponseFlowHelper.buildFinalPrompt(needsDb, userMessage, dbContext);
    }

    public static void validateAvailableModels(AgentRuntimeModels.RuntimeModelSelection models) throws Exception {
        validateAvailableModels(
            models.ollamaUrl,
            models.ollamaConnectTimeoutMs,
            models.ollamaReadTimeoutMs,
            models.model,
            models.coderModel,
            models.aiModel,
            models.pqModel,
            models.alarmModel
        );
    }

    public static String routeFinalModel(
        String userMessage,
        String defaultModel,
        String aiModel,
        String pqModel,
        String alarmModel
    ) {
        return AgentModelRouter.routeModel(userMessage, defaultModel, aiModel, pqModel, alarmModel);
    }

    public static String routeCoderModel(String userMessage, String defaultModel, String coderModel) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean isCoderTask =
            m.contains("sql") || m.contains("query") || m.contains("쿼리") ||
            m.contains("select") || m.contains("where") || m.contains("join") ||
            m.contains("groupby") || m.contains("orderby") ||
            m.contains("테이블") || m.contains("컬럼") || m.contains("column") ||
            m.contains("스키마") || m.contains("schema") ||
            m.contains("ddl") || m.contains("dml") ||
            m.contains("insert") || m.contains("update") || m.contains("delete");
        return isCoderTask ? coderModel : defaultModel;
    }

    public static String callOllamaOnce(
        String ollamaUrl,
        String model,
        String prompt,
        int connectTimeoutMs,
        int readTimeoutMs,
        double temperature
    ) throws Exception {
        String payload = "{\"model\":\"" + model + "\",\"prompt\":" + AgentOutputHelper.quoteJson(prompt) + ",\"stream\":false,\"temperature\":" + temperature + "}";
        AgentSupport.HttpResponse resp = AgentSupport.callOllamaEndpoint(
            ollamaUrl + "/api/generate",
            "POST",
            payload,
            connectTimeoutMs,
            readTimeoutMs
        );
        String body = resp.body == null ? "" : resp.body;
        if (resp.statusCode < 200 || resp.statusCode >= 400) {
            throw new RuntimeException("Ollama error " + resp.statusCode + ": " + clip(body, 300));
        }

        String responseText = AgentSupport.extractJsonStringField(body, "response");
        if (responseText == null || responseText.trim().isEmpty()) {
            return clip(body, 2000);
        }
        return responseText.trim();
    }

    private static void assertModelExists(String tagJson, String modelName) {
        if (modelName == null || modelName.isEmpty()) {
            return;
        }
        boolean exists = tagJson != null
            && (tagJson.contains("\"" + modelName + "\"") || tagJson.contains("\"" + modelName + ":"));
        if (!exists) {
            throw new IllegalArgumentException("Model not found: " + modelName);
        }
    }

    private static String clip(String text, int max) {
        if (text == null) return null;
        return text.length() <= max ? text : text.substring(0, max);
    }
}
