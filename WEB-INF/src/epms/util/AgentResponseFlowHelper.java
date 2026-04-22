package epms.util;

import java.util.ArrayList;
import java.util.List;

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
        return "RULE 모드: 직접 규칙으로 매칭되는 결과가 없습니다. 같은 질문을 `/llm` 모드로 다시 시도해 주세요.";
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

    private static String buildNarrativePrompt(String userMessage, String dbContext) {
        StringBuilder sb = new StringBuilder();
        sb.append("You are an EPMS operations assistant for facility operators. ");
        sb.append("Answer in Korean. Be practical, specific, and concise. ");
        sb.append("Do not return a one-line vague answer. ");
        sb.append("Do not give generic textbook explanations unless the user asked for theory. ");
        sb.append("For alarm, PQ, power quality, abnormal condition, cause, meaning, interpretation, or action questions, answer in exactly this structure:\n\n");
        sb.append("원인 후보:\n");
        sb.append("- concrete cause candidates based on the context or likely EPMS patterns\n\n");
        sb.append("추가 확인 데이터:\n");
        sb.append("- what measurements, alarms, trend data, or related meters/panels should be checked next\n\n");
        sb.append("우선 점검/조치:\n");
        sb.append("- immediate practical checks or actions for an operator\n\n");
        sb.append("참고:\n");
        sb.append("- cautions, assumptions, or limits of the current evidence\n\n");
        sb.append("Rules:\n");
        sb.append("- Each section must contain at least one bullet.\n");
        sb.append("- If evidence is limited, say that clearly in 참고, but still provide useful next checks.\n");
        sb.append("- If DB context exists, ground the answer on that context and do not invent measurements that are not present.\n");
        sb.append("- If DB context shows no data or no signal, say that first and then suggest what to verify.\n");
        sb.append("- If no DB context is available, still provide likely operational causes and what EPMS data should be checked next.\n");
        sb.append("- Avoid long introductions and avoid saying only 'cannot determine'.\n\n");
        sb.append("User: ").append(userMessage);
        if (dbContext != null && !dbContext.isEmpty()) {
            sb.append("\n\nDB Context:\n").append(dbContext);
        }
        return sb.toString();
    }

    public static String buildFinalPrompt(boolean needsDb, String userMessage, String dbContext) {
        boolean prefersNarrative = AgentIntentSupport.prefersNarrativeLlm(userMessage)
            || AgentQueryRouter.prefersNarrativeLlm(userMessage);
        if (prefersNarrative) {
            return buildNarrativePrompt(userMessage, dbContext);
        }
        if (needsDb && dbContext != null && !dbContext.isEmpty()) {
            return "You are an EPMS expert assistant. "
                + "Answer in Korean, concise, and grounded only on provided DB context. "
                + "If context indicates no signal, clearly say no signal.\n\n"
                + "User: " + userMessage + "\n\nDB Context:\n" + dbContext;
        }
        return "You are an EPMS expert assistant. "
            + "Answer in Korean briefly and accurately.\n\nUser: " + userMessage;
    }

    public static String finalizeNarrativeAnswer(String userMessage, String answer, String userDbContext) {
        String safeAnswer = answer == null ? "" : answer.trim();
        if (safeAnswer.isEmpty()) return safeAnswer;
        boolean prefersNarrative = AgentIntentSupport.prefersNarrativeLlm(userMessage)
            || AgentQueryRouter.prefersNarrativeLlm(userMessage);
        if (!prefersNarrative) return safeAnswer;
        if (hasStructuredSections(safeAnswer)) return safeAnswer;

        List<String> causeBullets = extractCauseBullets(safeAnswer);
        if (causeBullets.isEmpty()) {
            causeBullets.add(safeAnswer);
        }

        List<String> dataBullets = extractDataBullets(userDbContext, userMessage);
        List<String> actionBullets = buildActionBullets(userMessage);
        List<String> noteBullets = buildNoteBullets(userDbContext);

        StringBuilder out = new StringBuilder();
        appendSection(out, "원인 후보", causeBullets);
        appendSection(out, "추가 확인 데이터", dataBullets);
        appendSection(out, "우선 점검/조치", actionBullets);
        appendSection(out, "참고", noteBullets);
        return out.toString().trim();
    }

    private static boolean hasStructuredSections(String text) {
        return text.contains("원인 후보") && text.contains("추가 확인 데이터")
            && text.contains("우선 점검") && text.contains("참고");
    }

    private static List<String> extractCauseBullets(String answer) {
        ArrayList<String> bullets = new ArrayList<String>();
        if (answer == null) return bullets;
        String normalized = answer.replace("\r", "\n");
        String[] lines = normalized.split("\n+");
        for (String rawLine : lines) {
            String line = rawLine == null ? "" : rawLine.trim();
            if (line.isEmpty()) continue;
            if (line.endsWith(":")) continue;
            if (line.startsWith("-")) line = line.substring(1).trim();
            if (line.matches("^[0-9]+\\..*")) line = line.replaceFirst("^[0-9]+\\.", "").trim();
            if (line.isEmpty()) continue;
            bullets.add(line);
            if (bullets.size() >= 4) break;
        }
        return bullets;
    }

    private static List<String> extractDataBullets(String userDbContext, String userMessage) {
        ArrayList<String> bullets = new ArrayList<String>();
        String ctx = userDbContext == null ? "" : userDbContext.trim();
        if (!ctx.isEmpty()) {
            String[] lines = ctx.split("\n");
            for (String rawLine : lines) {
                String line = rawLine == null ? "" : rawLine.trim();
                if (line.isEmpty()) continue;
                if (line.startsWith("- [")) {
                    bullets.add("최근 알람 상세: " + line.substring(2).trim());
                    if (bullets.size() >= 2) break;
                } else if (line.contains("미해결 알람")) {
                    bullets.add(line);
                }
            }
        }
        if (bullets.isEmpty()) {
            bullets.add("알람 발생 시각 전후의 전압, 전류, 역률, 주파수 추이를 확인해 주세요.");
            bullets.add("같은 판넬 또는 인접 계측기의 동시 알람 여부를 확인해 주세요.");
        }
        if (AgentIntentSupport.hasMeasurementAnomalyIntent(userMessage)) {
            bullets.add("이상치 기준을 초과한 항목의 임계값과 지속 시간을 함께 확인해 주세요.");
        }
        return bullets;
    }

    private static List<String> buildActionBullets(String userMessage) {
        ArrayList<String> bullets = new ArrayList<String>();
        if (AgentIntentSupport.hasAlarmIntent(userMessage)) {
            bullets.add("최근 미해결 알람부터 발생 시각과 설비 상태를 대조해 주세요.");
            bullets.add("동일 계측기에서 반복 발생한 알람 유형이 있는지 우선 확인해 주세요.");
        }
        if (AgentIntentSupport.hasMeasurementAnomalyIntent(userMessage)) {
            bullets.add("임계값 초과 항목의 센서 이상 여부와 실제 설비 상태를 함께 점검해 주세요.");
        }
        if (bullets.isEmpty()) {
            bullets.add("관련 로그와 최근 추세 데이터를 먼저 확인한 뒤 원인 범위를 좁혀 주세요.");
        }
        return bullets;
    }

    private static List<String> buildNoteBullets(String userDbContext) {
        ArrayList<String> bullets = new ArrayList<String>();
        if (userDbContext != null && !userDbContext.trim().isEmpty()) {
            bullets.add("현재 답변은 최근 EPMS 조회 결과를 바탕으로 한 1차 해석입니다.");
        } else {
            bullets.add("현재 답변은 구체적인 DB 문맥 없이 작성된 일반 운영 가이드입니다.");
        }
        bullets.add("정확한 원인 확정은 현장 상태, 보호계전기 로그, 이벤트 시각 비교가 추가로 필요할 수 있습니다.");
        return bullets;
    }

    private static void appendSection(StringBuilder out, String title, List<String> bullets) {
        if (out.length() > 0) out.append("\n\n");
        out.append(title).append(":\n");
        if (bullets == null || bullets.isEmpty()) {
            out.append("- 확인 가능한 정보가 아직 부족합니다.");
            return;
        }
        for (String bullet : bullets) {
            String line = bullet == null ? "" : bullet.trim();
            if (line.isEmpty()) continue;
            out.append("- ").append(line).append("\n");
        }
        if (out.charAt(out.length() - 1) == '\n') {
            out.setLength(out.length() - 1);
        }
    }
}
