package epms.util;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.sql.Timestamp;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentQueryParser {
    private AgentQueryParser() {
    }

    public static final class ParsedTimeWindow {
        public final Timestamp fromTs;
        public final Timestamp toTs;
        public final String label;

        public ParsedTimeWindow(Timestamp fromTs, Timestamp toTs, String label) {
            this.fromTs = fromTs;
            this.toTs = toTs;
            this.label = label;
        }
    }

    public static String extractPhaseLabel(String userMessage) {
        if (userMessage == null) return null;
        String m = normalize(userMessage);
        if (m.contains("\u0061\uc0c1") || m.contains("\u0072\uc0c1")) return "A";
        if (m.contains("\u0062\uc0c1") || m.contains("\u0073\uc0c1")) return "B";
        if (m.contains("\u0063\uc0c1") || m.contains("\u0074\uc0c1")) return "C";
        return null;
    }

    public static String extractLinePairLabel(String userMessage) {
        if (userMessage == null) return null;
        String m = normalize(userMessage);
        if (m.contains("vab") || m.contains("ab\uc0c1") || m.contains("a-b") || m.contains("rs") || m.contains("r-s")) return "AB";
        if (m.contains("vbc") || m.contains("bc\uc0c1") || m.contains("b-c") || m.contains("st") || m.contains("s-t")) return "BC";
        if (m.contains("vca") || m.contains("ca\uc0c1") || m.contains("c-a") || m.contains("tr") || m.contains("t-r")) return "CA";
        return null;
    }

    public static String extractAlarmTypeToken(String userMessage) {
        if (userMessage == null) return null;
        if (wantsTripAlarmOnly(userMessage)) return "TRIP";
        String src = userMessage.trim();
        Matcher m1 = Pattern.compile("([A-Za-z][A-Za-z0-9_\\-]{1,15})\\s*\uc54c\ub78c", Pattern.CASE_INSENSITIVE).matcher(src);
        if (m1.find()) return m1.group(1).toUpperCase(Locale.ROOT);
        Matcher m2 = Pattern.compile("\uc54c\ub78c\\s*([A-Za-z][A-Za-z0-9_\\-]{1,15})", Pattern.CASE_INSENSITIVE).matcher(src);
        if (m2.find()) return m2.group(1).toUpperCase(Locale.ROOT);
        return null;
    }

    public static String extractAlarmAreaToken(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.trim();
        Matcher m0 = Pattern.compile("(.+?)\\s*(?:\uacfc|\uc640)?\\s*\uad00\ub828\ub41c\\s*\uacc4\uce21\uae30").matcher(src);
        if (m0.find()) {
            String token0 = EpmsWebUtil.trimToNull(m0.group(1));
            if (token0 != null) {
                token0 = token0.replaceAll("[\"'`]", "").trim();
                String n0 = normalize(token0);
                if (token0.length() >= 2 && !n0.contains("ocr") && !n0.contains("trip") && !n0.contains("\ud2b8\ub9bd") && !n0.contains("\ud2b8\ub9bc")) {
                    return token0;
                }
            }
        }
        Matcher m00 = Pattern.compile("(.+?)\\s*\uacc4\uce21\uae30\\s*\uc758\\s*\uc54c\ub78c").matcher(src);
        if (m00.find()) {
            String token00 = EpmsWebUtil.trimToNull(m00.group(1));
            if (token00 != null) {
                token00 = token00.replaceAll("[\"'`]", "").trim();
                String n00 = normalize(token00);
                if (token00.length() >= 2 && !n00.contains("ocr") && !n00.contains("trip") && !n00.contains("\ud2b8\ub9bd") && !n00.contains("\ud2b8\ub9bc")) {
                    return token00;
                }
            }
        }
        Matcher m = Pattern.compile("(.+?)\\s*\uc758\\s*\uc54c\ub78c").matcher(src);
        if (!m.find()) return null;
        String token = EpmsWebUtil.trimToNull(m.group(1));
        if (token == null) return null;
        token = token.replaceAll("[\"'`]", "").trim();
        if (token.length() < 2) return null;
        String n = normalize(token);
        if (n.contains("ocr") || n.contains("trip") || n.contains("\ud2b8\ub9bd") || n.contains("\ud2b8\ub9bc")) return null;
        if (n.contains("\uacc4\uce21\uae30") || n.contains("meter")) return null;
        return token;
    }

    public static String extractMeterScopeToken(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.trim();
        Matcher m0 = Pattern.compile("(.+?)\\s*(?:\uacfc|\uc640)?\\s*\uad00\ub828\ub41c\\s*(?:\uacc4\uce21\uae30|\uac8c\uce20\uae30|\ubbf8\ud130)").matcher(src);
        if (m0.find()) return EpmsWebUtil.trimToNull(m0.group(1));
        Matcher m1 = Pattern.compile("(.+?)\\s*(?:\uacc4\uce21\uae30|\uac8c\uce20\uae30|\ubbf8\ud130)\\s*(?:\ub9ac\uc2a4\ud2b8|\ubaa9\ub85d)").matcher(src);
        if (m1.find()) return EpmsWebUtil.trimToNull(m1.group(1));
        Matcher m2 = Pattern.compile("(.+?)\\s*\uc758\\s*(?:\uacc4\uce21\uae30|\uac8c\uce20\uae30|\ubbf8\ud130)").matcher(src);
        if (m2.find()) return EpmsWebUtil.trimToNull(m2.group(1));
        return null;
    }

    public static Integer extractTopN(String userMessage, int defVal, int maxVal) {
        if (userMessage == null) return Integer.valueOf(defVal);
        String src = userMessage.toLowerCase(Locale.ROOT);
        Matcher m1 = Pattern.compile("top\\s*([0-9]{1,3})").matcher(src);
        if (m1.find()) {
            try {
                int n = Integer.parseInt(m1.group(1));
                if (n < 1) n = defVal;
                if (n > maxVal) n = maxVal;
                return Integer.valueOf(n);
            } catch (Exception ignore) {
            }
        }
        Matcher m2 = Pattern.compile("([0-9]{1,3})\\s*(\uac1c|\uac74|\uc704)").matcher(src);
        if (m2.find()) {
            try {
                int n = Integer.parseInt(m2.group(1));
                if (n < 1) n = defVal;
                if (n > maxVal) n = maxVal;
                return Integer.valueOf(n);
            } catch (Exception ignore) {
            }
        }
        return Integer.valueOf(defVal);
    }

    public static Integer extractDays(String userMessage, int defVal, int maxVal) {
        if (userMessage == null) return Integer.valueOf(defVal);
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("\uc5b4\uc81c") || src.contains("yesterday")) return Integer.valueOf(1);
        if (src.contains("\uc624\ub298") || src.contains("today")) return Integer.valueOf(0);
        Matcher m = Pattern.compile("([0-9]{1,3})\\s*(\uc77c|day|days)").matcher(src);
        if (m.find()) {
            try {
                int d = Integer.parseInt(m.group(1));
                if (d < 1) d = defVal;
                if (d > maxVal) d = maxVal;
                return Integer.valueOf(d);
            } catch (Exception ignore) {
            }
        }
        return Integer.valueOf(defVal);
    }

    public static Integer extractExplicitDays(String userMessage, int maxVal) {
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("\uc77c\uc8fc\uc77c") || src.contains("\ud55c\uc8fc") || src.contains("1\uc8fc") || src.contains("one week")) {
            return Integer.valueOf(7);
        }
        Matcher m = Pattern.compile("([0-9]{1,3})\\s*(\uc77c|day|days)").matcher(src);
        if (m.find()) {
            try {
                int d = Integer.parseInt(m.group(1));
                if (d < 1) return null;
                if (d > maxVal) d = maxVal;
                return Integer.valueOf(d);
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static Integer extractMonth(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("\uc774\ubc88\ub2ec") || src.contains("\uae08\uc6d4") || src.contains("this month")) {
            return Integer.valueOf(java.time.LocalDate.now().getMonthValue());
        }
        Matcher m = Pattern.compile("([0-9]{1,2})\\s*\uc6d4").matcher(src);
        if (m.find()) {
            try {
                int mm = Integer.parseInt(m.group(1));
                if (mm >= 1 && mm <= 12) return Integer.valueOf(mm);
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static java.time.LocalDate extractExplicitDate(String userMessage) {
        if (userMessage == null) return null;
        Matcher dm = Pattern.compile("([0-9]{4})[-./]([0-9]{1,2})[-./]([0-9]{1,2})").matcher(userMessage);
        if (dm.find()) {
            try {
                int y = Integer.parseInt(dm.group(1));
                int m = Integer.parseInt(dm.group(2));
                int d = Integer.parseInt(dm.group(3));
                return java.time.LocalDate.of(y, m, d);
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static ParsedTimeWindow extractTimeWindow(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        java.time.LocalDate today = java.time.LocalDate.now();
        java.time.LocalDate explicitDate = extractExplicitDate(userMessage);

        if (explicitDate != null) {
            return new ParsedTimeWindow(
                Timestamp.valueOf(explicitDate.atStartOfDay()),
                Timestamp.valueOf(explicitDate.plusDays(1).atStartOfDay()),
                explicitDate.toString()
            );
        }
        if (src.contains("\uc5b4\uc81c") || src.contains("yesterday")) {
            java.time.LocalDate d = today.minusDays(1);
            return new ParsedTimeWindow(Timestamp.valueOf(d.atStartOfDay()), Timestamp.valueOf(d.plusDays(1).atStartOfDay()), d.toString());
        }
        if (src.contains("\uc624\ub298") || src.contains("today")) {
            return new ParsedTimeWindow(Timestamp.valueOf(today.atStartOfDay()), Timestamp.valueOf(today.plusDays(1).atStartOfDay()), today.toString());
        }
        if (src.contains("\uc774\ubc88\uc8fc") || src.contains("\uae08\uc8fc") || src.contains("this week")) {
            java.time.LocalDate weekStart = today.with(java.time.DayOfWeek.MONDAY);
            return new ParsedTimeWindow(Timestamp.valueOf(weekStart.atStartOfDay()), Timestamp.valueOf(weekStart.plusDays(7).atStartOfDay()), weekStart.toString() + "~week");
        }
        if (src.contains("\uc77c\uc8fc\uc77c") || src.contains("\ud55c\uc8fc") || src.contains("1\uc8fc") || src.contains("one week") || src.contains("\ucd5c\uadfc7\uc77c")) {
            java.time.LocalDate from = today.minusDays(6);
            return new ParsedTimeWindow(Timestamp.valueOf(from.atStartOfDay()), Timestamp.valueOf(today.plusDays(1).atStartOfDay()), from.toString() + "~7d");
        }
        if (src.contains("\uc774\ubc88\ub2ec") || src.contains("\uae08\uc6d4") || src.contains("this month")) {
            java.time.LocalDate monthStart = today.withDayOfMonth(1);
            return new ParsedTimeWindow(Timestamp.valueOf(monthStart.atStartOfDay()), Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()), monthStart.toString().substring(0, 7));
        }
        if (src.contains("\uc62c\ud574") || src.contains("\uae08\ub144") || src.contains("this year")) {
            java.time.LocalDate yearStart = today.withDayOfYear(1);
            return new ParsedTimeWindow(Timestamp.valueOf(yearStart.atStartOfDay()), Timestamp.valueOf(yearStart.plusYears(1).atStartOfDay()), String.valueOf(today.getYear()));
        }
        return null;
    }

    public static Integer extractMeterId(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        Matcher m1 = Pattern.compile("(?:meter|\ubbf8\ud130)\\s*([0-9]{1,6})").matcher(src);
        if (m1.find()) {
            try {
                return Integer.valueOf(m1.group(1));
            } catch (Exception ignore) {
            }
        }
        Matcher m2 = Pattern.compile("([0-9]{1,6})\\s*\ubc88").matcher(src);
        if (m2.find()) {
            try {
                return Integer.valueOf(m2.group(1));
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static Double extractHzThreshold(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        Matcher m = Pattern.compile("([0-9]{2,3}(?:\\.[0-9]+)?)\\s*hz").matcher(src);
        if (m.find()) {
            try {
                return Double.valueOf(m.group(1));
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static Double extractPfThreshold(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        Matcher m = Pattern.compile("([01](?:\\.[0-9]+)?)").matcher(src);
        if (m.find()) {
            try {
                double v = Double.parseDouble(m.group(1));
                if (v >= 0.0d && v <= 1.0d) return Double.valueOf(v);
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static List<String> extractPanelTokens(String userMessage) {
        ArrayList<String> tokens = new ArrayList<String>();
        if (userMessage == null) return tokens;
        String msg = userMessage.trim();
        String candidate = null;
        Matcher m = Pattern.compile("(.+?)\\s*\uc758\\s*(\uc804\uc555|\uc804\ub958|\uc5ed\ub960|\uc804\ub825|\uac12|\ucd5c\uadfc.*\uacc4\uce21|\ucd5c\uadfc.*\uce21\uc815|\uacc4\uce21|\uce21\uc815)").matcher(msg);
        if (m.find()) {
            candidate = m.group(1);
        }
        if ((candidate == null || candidate.trim().isEmpty()) && msg.contains("\uc758")) {
            String[] split = msg.split("\\s*\uc758\\s*", 2);
            if (split.length > 0) candidate = split[0];
        }
        if (candidate == null || candidate.trim().isEmpty()) return tokens;
        candidate = candidate.replaceAll("[\"'`]", " ").trim();
        if (candidate.isEmpty()) return tokens;

        String[] parts = candidate.split("[\\s_\\-]+");
        for (String p : parts) {
            if (p == null) continue;
            p = p.trim();
            p = p.replaceAll("(?i)panel", "");
            p = p.replace("\ud328\ub110", "").replace("\ud310\ub12c", "");
            p = p.trim();
            if (p.length() < 2) continue;
            if ("meter".equalsIgnoreCase(p) || "\ubbf8\ud130".equals(p)) continue;
            if ("panel".equalsIgnoreCase(p) || "\ud328\ub110".equals(p)) continue;
            if ("\uacc4\uce21\uae30".equals(p) || "\uac01".equals(p) || "\ubaa8\ub4e0".equals(p) || "\uc804\uccb4".equals(p)) continue;
            tokens.add(p.toUpperCase(Locale.ROOT));
        }
        return tokens;
    }

    public static List<String> extractPanelTokensLoose(String userMessage) {
        ArrayList<String> tokens = new ArrayList<String>();
        if (userMessage == null) return tokens;
        Matcher m = Pattern.compile("([A-Za-z]{2,6}[ _\\-]?[0-9]{0,2}[A-Za-z]?)").matcher(userMessage);
        while (m.find()) {
            String t = m.group(1);
            if (t == null) continue;
            t = t.trim();
            if (t.length() < 3) continue;
            String up = t.toUpperCase(Locale.ROOT);
            if (up.contains("MDB") || up.contains("VCB") || up.contains("ACB") || up.contains("PANEL")) {
                tokens.add(up.replaceAll("[\\s\\-]+", "_"));
                if (tokens.size() >= 3) break;
            }
        }
        return tokens;
    }

    private static boolean wantsTripAlarmOnly(String userMessage) {
        String m = normalize(userMessage);
        return m.contains("\ud2b8\ub9bd") || m.contains("trip") || m.contains("\ud2b8\ub9bc");
    }

    private static String normalize(String text) {
        if (text == null) return "";
        return text.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }
}
