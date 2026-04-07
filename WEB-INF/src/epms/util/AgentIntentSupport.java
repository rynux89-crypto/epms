package epms.util;

public final class AgentIntentSupport {
    private AgentIntentSupport() {
    }

    public static boolean hasAlarmIntent(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        return m.contains("알람") || m.contains("경보") || m.contains("alarm");
    }

    public static boolean hasMeasurementAnomalyIntent(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd") || m.contains("왜형률") || m.contains("허형율");
        boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
        boolean hasVoltageUnbalance = (m.contains("전압") || m.contains("voltage")) && (m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance"));
        boolean hasCurrentUnbalance = (m.contains("전류") || m.contains("current")) && (m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance"));
        boolean hasPowerFactor = m.contains("역률") || m.contains("pf") || m.contains("powerfactor");
        boolean hasOutlier = m.contains("이상") || m.contains("이상치") || m.contains("초과") || m.contains("문제") || m.contains("비정상") || m.contains("미만");
        return (hasHarmonic || hasFrequency || hasVoltageUnbalance || hasCurrentUnbalance || hasPowerFactor) && hasOutlier;
    }

    public static boolean prefersNarrativeLlm(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasNarrativeIntent =
            m.contains("해석") || m.contains("설명") || m.contains("요약")
            || m.contains("보고서") || m.contains("분석") || m.contains("평가")
            || m.contains("추론") || m.contains("진단") || m.contains("브리핑")
            || m.contains("알려") || m.contains("안내") || m.contains("체크리스트")
            || m.contains("항목") || m.contains("순서") || m.contains("절차")
            || m.contains("원인") || m.contains("점검");
        boolean hasCombinedIntent =
            (m.contains("계측") || m.contains("상태") || m.contains("측정"))
            && (m.contains("알람") || m.contains("경보"));
        boolean hasQualityOpsIntent =
            (m.contains("역률") || m.contains("powerfactor") || m.contains("pf")
                || m.contains("주파수") || m.contains("frequency")
                || m.contains("고조파") || m.contains("harmonic")
                || m.contains("불평형") || m.contains("unbalance"))
            && (m.contains("운영자") || m.contains("담당자")
                || m.contains("뭐부터") || m.contains("먼저")
                || m.contains("항목") || m.contains("순서")
                || m.contains("절차") || m.contains("점검")
                || m.contains("원인") || m.contains("대응"));
        return (hasNarrativeIntent && hasCombinedIntent) || (hasNarrativeIntent && hasQualityOpsIntent);
    }
}
