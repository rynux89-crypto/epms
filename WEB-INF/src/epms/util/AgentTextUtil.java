package epms.util;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentTextUtil {
    private AgentTextUtil() {
    }

    public static String normalizeForIntent(String text) {
        if (text == null) return "";
        return text.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }

    public static String normalizeScopeKey(String s) {
        if (s == null) return "";
        return s.toLowerCase(Locale.ROOT).replaceAll("[\\s_\\-]+", "");
    }

    public static String unescapeJsonText(String s) {
        if (s == null) return "";
        return s.replaceAll("\\\\\\\"", "\"")
                .replaceAll("\\\\\\\\", "\\\\")
                .replaceAll("\\\\n", "\n")
                .replaceAll("\\\\r", "\r")
                .replaceAll("\\\\t", "\t");
    }

    public static String extractJsonStringField(String json, String field) {
        if (json == null || field == null) return null;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(field) + "\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"", Pattern.DOTALL);
            Matcher m = p.matcher(json);
            if (m.find()) return unescapeJsonText(m.group(1));
        } catch (Exception ignore) {
        }
        return null;
    }

    public static Integer extractJsonIntField(String json, String field) {
        if (json == null || field == null) return null;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(field) + "\"\\s*:\\s*(\\d+)");
            Matcher m = p.matcher(json);
            if (m.find()) return Integer.valueOf(m.group(1));
        } catch (Exception ignore) {
        }
        return null;
    }

    public static Boolean extractJsonBoolField(String json, String field) {
        if (json == null || field == null) return null;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(field) + "\"\\s*:\\s*(true|false)", Pattern.CASE_INSENSITIVE);
            Matcher m = p.matcher(json);
            if (m.find()) return Boolean.valueOf(m.group(1).toLowerCase(Locale.ROOT));
        } catch (Exception ignore) {
        }
        return null;
    }
}
