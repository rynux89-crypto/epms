package epms.util;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentJsonHelper {
    private AgentJsonHelper() {
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
