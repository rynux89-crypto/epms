package epms.util;

import java.util.Locale;

public final class AgentIntentSupport {
    private AgentIntentSupport() {
    }

    private static String rawLower(String userMessage) {
        return userMessage == null ? "" : userMessage.toLowerCase(Locale.ROOT);
    }

    private static boolean containsAny(String text, String... tokens) {
        if (text == null || text.isEmpty() || tokens == null) return false;
        for (String token : tokens) {
            if (token != null && !token.isEmpty() && text.contains(token)) return true;
        }
        return false;
    }

    public static boolean hasAlarmIntent(String userMessage) {
        String raw = rawLower(userMessage);
        return containsAny(raw, "\uC54C\uB78C", "\uACBD\uBCF4", "alarm", "alert");
    }

    public static boolean hasMeasurementAnomalyIntent(String userMessage) {
        String raw = rawLower(userMessage);
        boolean hasHarmonic = containsAny(raw, "\uACE0\uC870\uD30C", "harmonic", "thd");
        boolean hasFrequency = containsAny(raw, "\uC8FC\uD30C\uC218", "frequency", "hz");
        boolean hasVoltageUnbalance = containsAny(raw, "\uC804\uC555 \uBD88\uD3C9\uD615", "\uC804\uC555 \uBD88\uADE0\uD615", "voltage unbalance", "voltage imbalance");
        boolean hasCurrentUnbalance = containsAny(raw, "\uC804\uB958 \uBD88\uD3C9\uD615", "\uC804\uB958 \uBD88\uADE0\uD615", "current unbalance", "current imbalance");
        boolean hasPowerFactor = containsAny(raw, "\uC5ED\uB960", "power factor", "powerfactor", "pf");
        boolean hasOutlier = containsAny(raw, "\uC774\uC0C1", "\uCD08\uACFC", "\uBB38\uC81C", "\uBE44\uC815\uC0C1", "\uBBF8\uB9CC", "outlier", "over", "abnormal");
        return (hasHarmonic || hasFrequency || hasVoltageUnbalance || hasCurrentUnbalance || hasPowerFactor) && hasOutlier;
    }

    public static boolean prefersNarrativeLlm(String userMessage) {
        String raw = rawLower(userMessage);
        boolean hasNarrativeIntent = containsAny(
            raw,
            "\uC124\uBA85", "\uD574\uC11D", "\uC694\uC57D", "\uBD84\uC11D", "\uD3C9\uAC00",
            "\uC9C4\uB2E8", "\uC548\uB0B4", "\uCCB4\uD06C\uB9AC\uC2A4\uD2B8", "\uD56D\uBAA9",
            "\uC21C\uC11C", "\uC810\uAC80", "\uC6D0\uC778", "\uC774\uC720", "\uC758\uBBF8",
            "\uC601\uD5A5", "\uC870\uCE58", "\uB300\uC751", "\uBC29\uBC95", "\uC5B4\uB5BB\uAC8C",
            "\uBB34\uC5C7", "\uCD94\uC815", "\uD310\uB2E8", "\uAD8C\uC7A5", "\uCD94\uCC9C",
            "explain", "summary", "analyze", "analysis", "why", "reason", "meaning",
            "impact", "guide", "checklist", "recommend", "recommended", "how"
        );
        if (!hasNarrativeIntent) return false;

        boolean hasAlarmOrQualityIntent =
            hasAlarmIntent(userMessage)
            || hasMeasurementAnomalyIntent(userMessage)
            || containsAny(raw, "pq", "power quality", "\uC804\uB825\uD488\uC9C8");

        boolean hasOpsIntent = containsAny(
            raw,
            "\uC6B4\uC601", "\uB300\uCC98", "\uD56D\uBAA9", "\uC21C\uC11C", "\uC810\uAC80",
            "\uAE30\uC900", "\uBC29\uBC95", "\uC5B4\uB5BB\uAC8C", "\uBB34\uC5C7",
            "operations", "operate", "guide", "how", "reason", "cause", "check", "checklist"
        );

        boolean hasCombinedIntent = containsAny(raw, "\uACC4\uCE21", "\uC0C1\uD0DC", "\uCE21\uC815")
            && hasAlarmIntent(userMessage);

        return hasAlarmOrQualityIntent || (hasCombinedIntent && hasOpsIntent);
    }
}
