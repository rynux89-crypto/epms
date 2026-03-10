package epms.util;

import java.util.Locale;

public final class EpmsWebUtil {
    private EpmsWebUtil() {
    }

    public static String h(Object value) {
        if (value == null) {
            return "";
        }
        String s = String.valueOf(value);
        StringBuilder out = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '&': out.append("&amp;"); break;
                case '<': out.append("&lt;"); break;
                case '>': out.append("&gt;"); break;
                case '"': out.append("&quot;"); break;
                case '\'': out.append("&#39;"); break;
                default: out.append(c);
            }
        }
        return out.toString();
    }

    public static String trimToNull(String s) {
        if (s == null) {
            return null;
        }
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }

    public static Integer parsePositiveInt(String s) {
        String t = trimToNull(s);
        if (t == null) {
            return null;
        }
        try {
            int v = Integer.parseInt(t);
            return v > 0 ? Integer.valueOf(v) : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    public static Integer parseNullableInt(String s) {
        String t = trimToNull(s);
        if (t == null) {
            return null;
        }
        try {
            return Integer.valueOf(Integer.parseInt(t));
        } catch (Exception ignore) {
            return null;
        }
    }

    public static Double parseNullableDouble(String s) {
        String t = trimToNull(s);
        if (t == null) {
            return null;
        }
        try {
            return Double.valueOf(Double.parseDouble(t));
        } catch (Exception ignore) {
            return null;
        }
    }

    public static boolean parseBoolSafe(String s) {
        String t = trimToNull(s);
        if (t == null) {
            return false;
        }
        String n = t.toLowerCase(Locale.ROOT);
        return "1".equals(n) || "true".equals(n) || "y".equals(n) || "yes".equals(n) || "on".equals(n);
    }

    public static int parseIntSafe(String s, int def) {
        try {
            return Integer.parseInt(s);
        } catch (Exception e) {
            return def;
        }
    }

    public static long parseLongSafe(String s, long def) {
        try {
            return Long.parseLong(s);
        } catch (Exception e) {
            return def;
        }
    }

    public static Double parseDoubleSafe(String s) {
        try {
            return Double.valueOf(s);
        } catch (Exception e) {
            return null;
        }
    }

    public static String jsq(String s) {
        if (s == null) {
            return "";
        }
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\r", " ")
                .replace("\n", " ");
    }

    public static String escJson(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\b': b.append("\\b"); break;
                case '\f': b.append("\\f"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        b.append(String.format("\\u%04x", (int) c));
                    } else {
                        b.append(c);
                    }
            }
        }
        return b.toString();
    }
}
