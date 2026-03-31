package epms.alarm;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;

public final class AlarmEventTypeUtil {
    private AlarmEventTypeUtil() {
    }

    public static String normKey(String s) {
        return s == null ? "" : s.trim().toUpperCase(Locale.ROOT);
    }

    public static String normalizeTagKey(String tagName) {
        if (tagName == null) {
            return "";
        }
        String t = tagName.trim().toUpperCase(Locale.ROOT);
        if (t.isEmpty()) {
            return "";
        }
        t = t.replaceAll("[^A-Z0-9]+", "_");
        t = t.replaceAll("_+", "_");
        t = t.replaceAll("^_+|_+$", "");
        if (t.length() > 64) {
            t = t.substring(0, 64);
        }
        return t;
    }

    public static List<String> splitSourceTokens(String raw) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        if (raw == null) {
            return new ArrayList<>(out);
        }
        String normalized = raw.replace('\n', ',').replace('\r', ',').replace(';', ',');
        String[] parts = normalized.split(",");
        for (String p : parts) {
            String token = normKey(p);
            if (!token.isEmpty()) {
                out.add(token);
            }
        }
        return new ArrayList<>(out);
    }

    public static String buildAiEventType(String ruleCode, String metricKey, String sourceKey, String stage) {
        String prefix = "AI_RULE_" + normKey(ruleCode);
        String source = normKey(sourceKey);
        String metric = normKey(metricKey);
        if (!source.isEmpty() && !source.equals(metric)) {
            String suffix = normalizeTagKey(source);
            if (!suffix.isEmpty() && !suffix.equals(normKey(ruleCode))) {
                prefix += "_" + suffix;
            }
        }
        return prefix + "_" + stage;
    }
}
