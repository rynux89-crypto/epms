package epms.util;

import java.sql.Timestamp;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentQueryExtractSupport {
    private AgentQueryExtractSupport() {}

    public static final class TimeWindow {
        public final Timestamp fromTs;
        public final Timestamp toTs;
        public final String label;

        public TimeWindow(Timestamp fromTs, Timestamp toTs, String label) {
            this.fromTs = fromTs;
            this.toTs = toTs;
            this.label = label;
        }
    }

    public static String extractPhaseLabel(String userMessage) {
        String delegated = AgentQueryParser.extractPhaseLabel(userMessage);
        return delegated != null ? delegated : AgentQueryParserCompat.extractPhaseLabel(userMessage);
    }

    public static String extractLinePairLabel(String userMessage) {
        String delegated = AgentQueryParser.extractLinePairLabel(userMessage);
        return delegated != null ? delegated : AgentQueryParserCompat.extractLinePairLabel(userMessage);
    }

    public static String extractAlarmTypeToken(String userMessage) {
        String delegated = AgentQueryParser.extractAlarmTypeToken(userMessage);
        return delegated != null ? delegated : AgentQueryParserCompat.extractAlarmTypeToken(userMessage);
    }

    public static String extractAlarmAreaToken(String userMessage) {
        String delegated = AgentQueryParser.extractAlarmAreaToken(userMessage);
        return delegated != null ? delegated : AgentQueryParserCompat.extractAlarmAreaToken(userMessage);
    }

    public static List<String> splitAlarmAreaTokens(String areaToken) {
        ArrayList<String> out = new ArrayList<String>();
        String raw = trimToNull(areaToken);
        if (raw == null) return out;
        String norm = raw.replaceAll("[\"'`]", " ").trim();
        if (norm.isEmpty()) return out;
        String[] parts = norm.split("\\s*(?:의|과|와|및|그리고|,|/|\\\\|\\s+)\\s*");
        LinkedHashSet<String> uniq = new LinkedHashSet<String>();
        for (int i = 0; i < parts.length; i++) {
            String p = trimToNull(parts[i]);
            if (p == null) continue;
            String n = AgentTextUtil.normalizeForIntent(p);
            if (n.length() < 2) continue;
            if ("알람".equals(n) || "계측기".equals(n) || "관련된".equals(n)) continue;
            uniq.add(p);
        }
        out.addAll(uniq);
        if (out.isEmpty()) out.add(norm);
        return out;
    }

    public static String extractMeterScopeToken(String userMessage) {
        String delegated = AgentQueryParser.extractMeterScopeToken(userMessage);
        if (delegated != null) return delegated;
        delegated = AgentQueryParserCompat.extractMeterScopeToken(userMessage);
        if (delegated != null) return delegated;
        return AgentScopeFallbackSupport.extractMeterScopeToken(userMessage);
    }

    public static Double extractPfThreshold(String userMessage) {
        Double delegated = AgentQueryParser.extractPfThreshold(userMessage);
        if (delegated != null) return delegated;
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

    public static Integer extractTopN(String userMessage, int defVal, int maxVal) {
        Integer delegated = AgentQueryParser.extractTopN(userMessage, defVal, maxVal);
        if (delegated != null) return delegated;
        if (userMessage == null) return Integer.valueOf(defVal);
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("전체") || src.contains("전부") || src.contains("모두") || src.contains("all")) {
            return Integer.valueOf(maxVal);
        }
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
        Matcher m2 = Pattern.compile("([0-9]{1,3})\\s*(개|건|위)").matcher(src);
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
        Integer delegated = AgentQueryParser.extractDays(userMessage, defVal, maxVal);
        if (delegated != null) return delegated;
        if (userMessage == null) return Integer.valueOf(defVal);
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("어제") || src.contains("yesterday")) return Integer.valueOf(1);
        if (src.contains("오늘") || src.contains("today")) return Integer.valueOf(0);
        Matcher m = Pattern.compile("([0-9]{1,3})\\s*(일|day|days)").matcher(src);
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
        Integer delegated = AgentQueryParser.extractExplicitDays(userMessage, maxVal);
        if (delegated != null) return delegated;
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("일주일") || src.contains("한주") || src.contains("1주") || src.contains("one week")) {
            return Integer.valueOf(7);
        }
        Matcher m = Pattern.compile("([0-9]{1,3})\\s*(일|day|days)").matcher(src);
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

    public static LocalDate extractExplicitDate(String userMessage) {
        LocalDate delegated = AgentQueryParser.extractExplicitDate(userMessage);
        if (delegated != null) return delegated;
        if (userMessage == null) return null;
        Matcher dm = Pattern.compile("([0-9]{4})[-./]([0-9]{1,2})[-./]([0-9]{1,2})").matcher(userMessage);
        if (dm.find()) {
            try {
                int y = Integer.parseInt(dm.group(1));
                int m = Integer.parseInt(dm.group(2));
                int d = Integer.parseInt(dm.group(3));
                return LocalDate.of(y, m, d);
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static TimeWindow extractTimeWindow(String userMessage) {
        AgentQueryParser.ParsedTimeWindow delegated = AgentQueryParser.extractTimeWindow(userMessage);
        if (delegated != null) {
            return new TimeWindow(delegated.fromTs, delegated.toTs, delegated.label);
        }
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        LocalDate today = LocalDate.now();
        LocalDate explicitDate = extractExplicitDate(userMessage);

        if (explicitDate != null) {
            return new TimeWindow(
                Timestamp.valueOf(explicitDate.atStartOfDay()),
                Timestamp.valueOf(explicitDate.plusDays(1).atStartOfDay()),
                explicitDate.toString()
            );
        }

        if (src.contains("어제") || src.contains("yesterday")) {
            LocalDate d = today.minusDays(1);
            return new TimeWindow(Timestamp.valueOf(d.atStartOfDay()), Timestamp.valueOf(d.plusDays(1).atStartOfDay()), d.toString());
        }
        if (src.contains("오늘") || src.contains("today")) {
            return new TimeWindow(Timestamp.valueOf(today.atStartOfDay()), Timestamp.valueOf(today.plusDays(1).atStartOfDay()), today.toString());
        }
        if (src.contains("이번주") || src.contains("금주") || src.contains("this week")) {
            LocalDate weekStart = today.with(DayOfWeek.MONDAY);
            return new TimeWindow(Timestamp.valueOf(weekStart.atStartOfDay()), Timestamp.valueOf(weekStart.plusDays(7).atStartOfDay()), weekStart.toString() + "~week");
        }
        if (src.contains("일주일") || src.contains("한주") || src.contains("1주") || src.contains("one week") || src.contains("최근7일")) {
            LocalDate from = today.minusDays(6);
            return new TimeWindow(Timestamp.valueOf(from.atStartOfDay()), Timestamp.valueOf(today.plusDays(1).atStartOfDay()), from.toString() + "~7d");
        }
        if (src.contains("이번달") || src.contains("금월") || src.contains("this month")) {
            LocalDate monthStart = today.withDayOfMonth(1);
            return new TimeWindow(Timestamp.valueOf(monthStart.atStartOfDay()), Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()), monthStart.toString().substring(0, 7));
        }
        Matcher ym = Pattern.compile("([0-9]{4})\\s*년\\s*([0-9]{1,2})\\s*월").matcher(src);
        if (ym.find()) {
            try {
                int yy = Integer.parseInt(ym.group(1));
                int mm = Integer.parseInt(ym.group(2));
                if (mm >= 1 && mm <= 12) {
                    LocalDate monthStart = LocalDate.of(yy, mm, 1);
                    return new TimeWindow(
                        Timestamp.valueOf(monthStart.atStartOfDay()),
                        Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()),
                        String.format(Locale.ROOT, "%04d-%02d", yy, mm)
                    );
                }
            } catch (Exception ignore) {
            }
        }
        Matcher monthOnly = Pattern.compile("(^|[^0-9])([0-9]{1,2})\\s*월(?:\\s*달)?").matcher(src);
        if (monthOnly.find()) {
            try {
                int mm = Integer.parseInt(monthOnly.group(2));
                if (mm >= 1 && mm <= 12) {
                    int yy = today.getYear();
                    LocalDate monthStart = LocalDate.of(yy, mm, 1);
                    return new TimeWindow(
                        Timestamp.valueOf(monthStart.atStartOfDay()),
                        Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()),
                        String.format(Locale.ROOT, "%04d-%02d", yy, mm)
                    );
                }
            } catch (Exception ignore) {
            }
        }
        if (src.contains("올해") || src.contains("금년") || src.contains("this year")) {
            LocalDate yearStart = today.withDayOfYear(1);
            return new TimeWindow(Timestamp.valueOf(yearStart.atStartOfDay()), Timestamp.valueOf(yearStart.plusYears(1).atStartOfDay()), String.valueOf(today.getYear()));
        }
        return null;
    }

    public static Double extractHzThreshold(String userMessage) {
        Double delegated = AgentQueryParser.extractHzThreshold(userMessage);
        if (delegated != null) return delegated;
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

    public static Integer extractMonth(String userMessage) {
        Integer delegated = AgentQueryParser.extractMonth(userMessage);
        if (delegated != null) return delegated;
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);
        if (src.contains("이번달") || src.contains("금월") || src.contains("this month")) {
            return Integer.valueOf(LocalDate.now().getMonthValue());
        }
        Matcher m = Pattern.compile("([0-9]{1,2})\\s*월").matcher(src);
        if (m.find()) {
            try {
                int mm = Integer.parseInt(m.group(1));
                if (mm >= 1 && mm <= 12) return Integer.valueOf(mm);
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static Integer extractMeterId(String userMessage) {
        Integer delegated = AgentQueryParser.extractMeterId(userMessage);
        if (delegated != null) return delegated;
        if (userMessage == null) return null;
        String src = userMessage.toLowerCase(Locale.ROOT);

        Matcher m1 = Pattern.compile("(?:meter|미터)\\s*([0-9]{1,6})").matcher(src);
        if (m1.find()) {
            try {
                return Integer.valueOf(m1.group(1));
            } catch (Exception ignore) {
            }
        }
        Matcher m2 = Pattern.compile("([0-9]{1,6})\\s*번").matcher(src);
        if (m2.find()) {
            try {
                return Integer.valueOf(m2.group(1));
            } catch (Exception ignore) {
            }
        }
        return null;
    }

    public static String extractMeterNameToken(String userMessage) {
        if (userMessage == null) return null;
        String src = userMessage.trim();
        Matcher m0 = Pattern.compile("^(?:/llm|/rule)?\\s*([A-Za-z][A-Za-z0-9_\\-]{2,})\\s*의").matcher(src);
        if (m0.find()) return trimToNull(m0.group(1));
        Matcher m1 = Pattern.compile("(?:계측기|meter)\\s*([A-Za-z][A-Za-z0-9_\\-]{2,})", Pattern.CASE_INSENSITIVE).matcher(src);
        if (m1.find()) return trimToNull(m1.group(1));
        Matcher m2 = Pattern.compile("([A-Za-z]{2,}[A-Za-z0-9]*_[A-Za-z0-9_\\-]{2,})").matcher(src);
        if (m2.find()) return trimToNull(m2.group(1));
        return null;
    }

    public static List<String> extractPanelTokens(String userMessage) {
        List<String> delegated = AgentQueryParser.extractPanelTokens(userMessage);
        if (delegated != null && !delegated.isEmpty()) return delegated;
        ArrayList<String> tokens = new ArrayList<String>();
        if (userMessage == null) return tokens;
        String msg = userMessage.trim();

        String candidate = null;
        Matcher m = Pattern.compile("(.+?)\\s*의\\s*(전압|전류|역률|전력|값|최근.*계측|최근.*측정|계측|측정)").matcher(msg);
        if (m.find()) {
            candidate = m.group(1);
        }
        if ((candidate == null || candidate.trim().isEmpty()) && msg.contains("의")) {
            String[] split = msg.split("\\s*의\\s*", 2);
            if (split.length > 0) {
                candidate = split[0];
            }
        }
        if (candidate == null || candidate.trim().isEmpty()) {
            return tokens;
        }

        candidate = candidate.replaceAll("[\"'`]", " ").trim();
        if (candidate.isEmpty()) return tokens;

        String[] parts = candidate.split("[\\s_\\-]+");
        for (int i = 0; i < parts.length; i++) {
            String p = parts[i];
            if (p == null) continue;
            p = p.trim();
            p = p.replaceAll("(?i)panel", "");
            p = p.replace("패널", "").replace("판넬", "");
            p = p.trim();
            if (p.length() < 2) continue;
            if ("meter".equalsIgnoreCase(p) || "미터".equals(p)) continue;
            if ("panel".equalsIgnoreCase(p) || "패널".equals(p)) continue;
            if ("계측기".equals(p) || "각".equals(p) || "모든".equals(p) || "전체".equals(p)) continue;
            tokens.add(p.toUpperCase(Locale.ROOT));
        }
        return tokens;
    }

    public static List<String> extractPanelTokensLoose(String userMessage) {
        List<String> delegated = AgentQueryParser.extractPanelTokensLoose(userMessage);
        if (delegated != null && !delegated.isEmpty()) return delegated;
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

    private static String trimToNull(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
