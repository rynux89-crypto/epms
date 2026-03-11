package epms.util;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentQueryParserCompat {
    private AgentQueryParserCompat() {
    }

    public static String extractPhaseLabel(String userMessage) {
        if (userMessage == null) return null;
        String m = normalize(userMessage);
        if (m.contains("a상") || m.contains("r상")) return "A";
        if (m.contains("b상") || m.contains("s상")) return "B";
        if (m.contains("c상") || m.contains("t상")) return "C";
        return null;
    }

    public static String extractLinePairLabel(String userMessage) {
        if (userMessage == null) return null;
        String m = normalize(userMessage);
        if (m.contains("vab") || m.contains("ab상") || m.contains("a-b") || m.contains("rs") || m.contains("r-s")) return "AB";
        if (m.contains("vbc") || m.contains("bc상") || m.contains("b-c") || m.contains("st") || m.contains("s-t")) return "BC";
        if (m.contains("vca") || m.contains("ca상") || m.contains("c-a") || m.contains("tr") || m.contains("t-r")) return "CA";
        return null;
    }

    public static String extractAlarmTypeToken(String userMessage) {
        if (userMessage == null) return null;
        if (wantsTripAlarmOnly(userMessage)) return "TRIP";
        String src = userMessage.trim();
        Matcher m1 = Pattern.compile("([A-Za-z][A-Za-z0-9_\\-]{1,15})\\s*알람", Pattern.CASE_INSENSITIVE).matcher(src);
        if (m1.find()) return m1.group(1).toUpperCase(Locale.ROOT);
        Matcher m2 = Pattern.compile("알람\\s*([A-Za-z][A-Za-z0-9_\\-]{1,15})", Pattern.CASE_INSENSITIVE).matcher(src);
        if (m2.find()) return m2.group(1).toUpperCase(Locale.ROOT);
        return null;
    }

    public static String extractAlarmAreaToken(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.trim();
        Matcher m0 = Pattern.compile("(.+?)\\s*(?:과|와)?\\s*관련된\\s*계측기").matcher(src);
        if (m0.find()) {
            String token0 = EpmsWebUtil.trimToNull(m0.group(1));
            if (token0 != null) {
                token0 = token0.replaceAll("[\"'`]", "").trim();
                String n0 = normalize(token0);
                if (token0.length() >= 2 && !n0.contains("ocr") && !n0.contains("trip") && !n0.contains("트립") && !n0.contains("트림")) {
                    return token0;
                }
            }
        }
        Matcher m00 = Pattern.compile("(.+?)\\s*계측기\\s*의\\s*알람").matcher(src);
        if (m00.find()) {
            String token00 = EpmsWebUtil.trimToNull(m00.group(1));
            if (token00 != null) {
                token00 = token00.replaceAll("[\"'`]", "").trim();
                String n00 = normalize(token00);
                if (token00.length() >= 2 && !n00.contains("ocr") && !n00.contains("trip") && !n00.contains("트립") && !n00.contains("트림")) {
                    return token00;
                }
            }
        }
        Matcher m = Pattern.compile("(.+?)\\s*의\\s*알람").matcher(src);
        if (!m.find()) return null;
        String token = EpmsWebUtil.trimToNull(m.group(1));
        if (token == null) return null;
        token = token.replaceAll("[\"'`]", "").trim();
        if (token.length() < 2) return null;
        String n = normalize(token);
        if (n.contains("ocr") || n.contains("trip") || n.contains("트립") || n.contains("트림")) return null;
        if (n.contains("계측기") || n.contains("meter")) return null;
        return token;
    }

    public static String extractMeterScopeToken(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.trim();
        Matcher m0 = Pattern.compile("(.+?)\\s*(?:과|와)?\\s*관련된\\s*(?:계측기|게츠기|미터)").matcher(src);
        if (m0.find()) return EpmsWebUtil.trimToNull(m0.group(1));
        Matcher m1 = Pattern.compile("(.+?)\\s*(?:계측기|게츠기|미터)\\s*(?:리스트|목록)").matcher(src);
        if (m1.find()) return EpmsWebUtil.trimToNull(m1.group(1));
        Matcher m2 = Pattern.compile("(.+?)\\s*의\\s*(?:계측기|게츠기|미터)").matcher(src);
        if (m2.find()) return EpmsWebUtil.trimToNull(m2.group(1));
        return null;
    }

    private static boolean wantsTripAlarmOnly(String userMessage) {
        String m = normalize(userMessage);
        return m.contains("트립") || m.contains("trip") || m.contains("트림");
    }

    private static String normalize(String text) {
        if (text == null) return "";
        return text.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }
}
