package epms.util;

public final class AgentScopedIntentSupport {
    private AgentScopedIntentSupport() {
    }

    public static boolean wantsUsageMeterCountSummary(String userMessage, String usageToken) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUsageToken = usageToken != null && !usageToken.trim().isEmpty();
        if (!hasUsageToken && !(m.contains("비상") || m.contains("비상전원"))) {
            return false;
        }
        boolean hasCount = m.contains("수는") || m.contains("몇개") || m.contains("개수") || m.contains("갯수")
            || m.contains("count") || m.endsWith("수") || m.endsWith("수는");
        boolean hasExcludedIntent = m.contains("알람") || m.contains("경보") || m.contains("목록") || m.contains("리스트")
            || m.contains("사용량") || m.contains("전력") || m.contains("피크") || m.contains("top")
            || m.contains("추이") || m.contains("원인") || m.contains("점검");
        return hasCount && !hasExcludedIntent;
    }

    public static boolean wantsAlarmSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm") || m.contains("alert");
        boolean hasSummaryIntent = m.contains("현재") || m.contains("상태") || m.contains("최근") || m.contains("최신")
            || m.contains("요약") || m.contains("보여") || m.contains("알려") || m.contains("목록");
        return hasAlarm && hasSummaryIntent;
    }

    public static boolean wantsMonthlyEnergyUsagePrompt(String userMessage, boolean hasMeterHint) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasEnergy = m.contains("전력량") || m.contains("사용량") || m.contains("누적")
            || m.contains("kwh") || m.contains("energy");
        boolean hasMonth = m.contains("이번달") || m.contains("금월") || m.contains("thismonth")
            || m.contains("월간");
        return hasEnergy && hasMonth && !hasMeterHint;
    }

    public static boolean wantsScopedMonthlyEnergySummary(String userMessage, boolean hasMeterHint, boolean hasScopeHint) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasEnergy = m.contains("전력사용량") || m.contains("사용전력") || m.contains("전력량") || m.contains("사용량")
            || m.contains("kwh") || m.contains("energy");
        boolean hasTotal = m.contains("전체") || m.contains("총") || m.contains("합계") || m.contains("누적");
        return hasEnergy && hasTotal && !hasMeterHint && hasScopeHint;
    }

    public static boolean wantsPanelMonthlyEnergySummary(String userMessage, boolean hasPanelTokens) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        String raw = userMessage == null ? "" : userMessage.toLowerCase(java.util.Locale.ROOT);
        boolean hasPanel = m.contains("패널") || m.contains("panel") || m.contains("판넬");
        boolean hasEnergy = m.contains("전력사용량") || m.contains("사용전력") || m.contains("전력량") || m.contains("사용량")
            || m.contains("kwh") || m.contains("energy");
        boolean hasTotal = m.contains("전체") || m.contains("총") || m.contains("합계") || m.contains("누적")
            || m.endsWith("은?") || m.endsWith("는?") || m.endsWith("?");
        if (!hasPanel) hasPanel = raw.contains("패널") || raw.contains("panel");
        if (!hasEnergy) hasEnergy = raw.contains("전력량") || raw.contains("사용량") || raw.contains("energy") || raw.contains("kwh");
        if (!hasTotal) hasTotal = raw.contains("전체") || raw.contains("총") || raw.contains("합계");
        return hasPanel && hasEnergy && hasTotal && hasPanelTokens;
    }

    public static boolean wantsUsageMonthlyEnergySummary(String userMessage, boolean hasUsageToken) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
        boolean hasEnergy = m.contains("전력사용량") || m.contains("사용전력") || m.contains("전력량") || m.contains("사용량")
            || m.contains("kwh") || m.contains("energy");
        boolean hasTotal = m.contains("전체") || m.contains("총") || m.contains("합계") || m.contains("누적")
            || m.endsWith("은?") || m.endsWith("는?") || m.endsWith("?");
        return hasUsage && hasEnergy && hasTotal && hasUsageToken;
    }
}
