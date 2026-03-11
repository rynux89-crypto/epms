package epms.util;

public final class AgentResponseFlowHelper {
    private AgentResponseFlowHelper() {
    }

    public static boolean shouldBypassDirect(boolean forceLlmOnly, boolean preferNarrativeLlm) {
        return forceLlmOnly || preferNarrativeLlm;
    }

    public static boolean shouldBypassSpecialized(boolean forceLlmOnly, boolean preferNarrativeLlm) {
        return forceLlmOnly || preferNarrativeLlm;
    }

    public static String buildRuleOnlyFallbackMessage() {
        return "RULE 모드: 직접 규칙에 매칭된 결과가 없습니다. 같은 질문을 /llm 으로 시도해 주세요.";
    }

    public static String finalizeDirectAnswer(String answer, String dbContext, int meterCount) {
        String safeAnswer = answer == null ? "" : answer;
        String safeContext = dbContext == null ? "" : dbContext;
        boolean skipMeterCountSuffix =
            safeContext.startsWith("[Alarm count]") || safeContext.startsWith("[Panel latest status]");
        if (!skipMeterCountSuffix && meterCount > 0 && safeAnswer.indexOf('\n') < 0) {
            return safeAnswer + " (해당 계측기 " + meterCount + "개)";
        }
        return safeAnswer;
    }

    public static String buildFinalPrompt(boolean needsDb, String userMessage, String dbContext) {
        if (needsDb && dbContext != null && !dbContext.isEmpty()) {
            return "You are an EPMS expert assistant. "
                + "Answer in Korean, concise, and grounded only on provided DB context. "
                + "If context indicates no signal, clearly say no signal.\n\n"
                + "User: " + userMessage + "\n\nDB Context:\n" + dbContext;
        }
        return "You are an EPMS expert assistant. "
            + "Answer in Korean briefly and accurately.\n\nUser: " + userMessage;
    }
}
