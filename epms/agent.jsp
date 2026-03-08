﻿<%@ page import="java.io.*,java.net.*,java.util.*,java.sql.*,javax.naming.*,javax.sql.*" trimDirectiveWhitespaces="true" %>
<%@ page contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" %>

<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
response.setContentType("application/json;charset=UTF-8");
%>

<%!
private static final Map<String, List<Long>> rateLimitMap = new java.util.concurrent.ConcurrentHashMap<>();
private static final int RATE_LIMIT_WINDOW_MS = 60000;
private static final int RATE_LIMIT_MAX_REQUESTS = 10;
private static final String DB_JNDI_NAME = "java:comp/env/jdbc/epms";
private static final Object SCHEMA_CACHE_LOCK = new Object();
private static final long SCHEMA_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final int SCHEMA_MAX_TABLES = 60;
private static final int SCHEMA_MAX_COLUMNS_PER_TABLE = 40;
private static final int SCHEMA_MAX_CHARS = 16000;
private static volatile String schemaContextCache = "";
private static volatile long schemaContextCacheAt = 0L;

private boolean checkRateLimit(String clientIp) {
    long now = System.currentTimeMillis();
    
    // 메모리 관리: 맵이 너무 커지면 전체 초기화 (간단한 전략)
    if (rateLimitMap.size() > 5000) {
        synchronized(rateLimitMap) {
            if (rateLimitMap.size() > 5000) rateLimitMap.clear();
        }
    }

    List<Long> timestamps = rateLimitMap.compute(clientIp, (k, v) -> {
        if (v == null) v = new ArrayList<>();
        v.removeIf(t -> now - t > RATE_LIMIT_WINDOW_MS);
        v.add(now);
        return v;
    });

    return timestamps.size() <= RATE_LIMIT_MAX_REQUESTS;
}

private Connection openDbConnection() throws Exception {
    InitialContext ic = new InitialContext();
    DataSource ds = (DataSource) ic.lookup(DB_JNDI_NAME);
    return ds.getConnection();
}

private String trimToNull(String s) {
    if (s == null) return null;
    String t = s.trim();
    return t.isEmpty() ? null : t;
}

private Properties loadAgentModelConfig(javax.servlet.ServletContext app) {
    Properties p = new Properties();
    if (app == null) return p;
    String epmsPath = app.getRealPath("/epms");
    if (epmsPath == null || epmsPath.isEmpty()) return p;
    File file = new File(epmsPath, "agent_model.properties");
    if (!file.exists() || !file.isFile()) return p;
    try (InputStream in = new FileInputStream(file);
         Reader reader = new InputStreamReader(in, "UTF-8")) {
        p.load(reader);
    } catch (Exception ignore) {
    }
    return p;
}

private String buildSchemaContextFromDb() {
    String tableSql =
        "SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE " +
        "FROM INFORMATION_SCHEMA.TABLES " +
        "WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','sys') " +
        "ORDER BY TABLE_SCHEMA, TABLE_NAME";
    String columnSql =
        "SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE " +
        "FROM INFORMATION_SCHEMA.COLUMNS " +
        "WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','sys') " +
        "ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION";

    LinkedHashMap<String, String> tableTypeMap = new LinkedHashMap<String, String>();
    LinkedHashMap<String, ArrayList<String>> columnMap = new LinkedHashMap<String, ArrayList<String>>();

    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(tableSql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String schema = rs.getString("TABLE_SCHEMA");
                String table = rs.getString("TABLE_NAME");
                if (schema == null || table == null) continue;
                String key = schema + "." + table;
                tableTypeMap.put(key, rs.getString("TABLE_TYPE"));
                columnMap.put(key, new ArrayList<String>());
            }
        }
    } catch (Exception e) {
        return "[Schema] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }

    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(columnSql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String schema = rs.getString("TABLE_SCHEMA");
                String table = rs.getString("TABLE_NAME");
                String col = rs.getString("COLUMN_NAME");
                String dt = rs.getString("DATA_TYPE");
                if (schema == null || table == null || col == null) continue;
                String key = schema + "." + table;
                ArrayList<String> cols = columnMap.get(key);
                if (cols == null) continue;
                if (cols.size() >= SCHEMA_MAX_COLUMNS_PER_TABLE) continue;
                cols.add(col + "(" + (dt == null ? "?" : dt) + ")");
            }
        }
    } catch (Exception e) {
        return "[Schema] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }

    if (tableTypeMap.isEmpty()) return "[Schema] no table metadata";

    StringBuilder sb = new StringBuilder();
    sb.append("[Schema snapshot]\n");
    int tableCount = 0;
    for (Map.Entry<String, String> e : tableTypeMap.entrySet()) {
        if (tableCount >= SCHEMA_MAX_TABLES) break;
        String key = e.getKey();
        ArrayList<String> cols = columnMap.get(key);
        sb.append(key)
          .append(" [")
          .append(e.getValue() == null ? "TABLE" : e.getValue())
          .append("]: ");
        if (cols == null || cols.isEmpty()) {
            sb.append("(no columns)");
        } else {
            for (int i = 0; i < cols.size(); i++) {
                if (i > 0) sb.append(", ");
                sb.append(cols.get(i));
            }
        }
        sb.append('\n');
        tableCount++;
        if (sb.length() >= SCHEMA_MAX_CHARS) break;
    }
    if (tableTypeMap.size() > tableCount) {
        sb.append("... truncated tables: ").append(tableTypeMap.size() - tableCount).append('\n');
    }
    if (sb.length() > SCHEMA_MAX_CHARS) {
        return sb.substring(0, SCHEMA_MAX_CHARS) + "\n... truncated by size";
    }
    return sb.toString();
}

private String getSchemaContextCached() {
    long now = System.currentTimeMillis();
    String cached = schemaContextCache;
    if (cached != null && !cached.isEmpty() && (now - schemaContextCacheAt) < SCHEMA_CACHE_TTL_MS) {
        return cached;
    }
    synchronized (SCHEMA_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        if (schemaContextCache != null && !schemaContextCache.isEmpty() && (now2 - schemaContextCacheAt) < SCHEMA_CACHE_TTL_MS) {
            return schemaContextCache;
        }
        String fresh = buildSchemaContextFromDb();
        schemaContextCache = fresh == null ? "" : fresh;
        schemaContextCacheAt = now2;
        return schemaContextCache;
    }
}

private String clip(String s, int maxLen) {
    if (s == null) return "";
    String t = s.replace('\n', ' ').replace('\r', ' ').trim();
    if (t.length() <= maxLen) return t;
    return t.substring(0, maxLen) + "...";
}

private String fmtNum(double v) {
    if (Double.isNaN(v) || Double.isInfinite(v)) return "-";
    return String.format(java.util.Locale.US, "%.2f", v);
}

private boolean isZeroish(double v) {
    return Double.isNaN(v) || Double.isInfinite(v) || Math.abs(v) < 0.000001d;
}

private double chooseVoltage(double avgV, double lineV, double phaseV, double vab) {
    if (!isZeroish(avgV)) return avgV;
    if (!isZeroish(lineV)) return lineV;
    if (!isZeroish(phaseV)) return phaseV;
    return vab;
}

private String fmtTs(Timestamp ts) {
    if (ts == null) return "-";
    return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(ts);
}

private String escapeJsonString(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r");
}

private String normalizeForIntent(String text) {
    if (text == null) return "";
    return text.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
}

private boolean wantsMeterSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean meterWord = m.contains("meter") || m.contains("미터");
    boolean meterIntentWord =
        m.contains("최근계측") || m.contains("최신계측")
        || m.contains("최근측정") || m.contains("최신측정")
        || m.contains("계측값") || m.contains("measurement") || m.contains("실시간상태")
        || m.contains("전압값") || m.contains("전류값")
        || m.contains("역률") || m.contains("전력값") || m.contains("kw");
    boolean sqlLike = m.contains("select") || m.contains("where") || m.contains("join")
        || m.contains("query") || m.contains("sql") || m.contains("테이블") || m.contains("컬럼");
    if (sqlLike) return false;
    return meterIntentWord || (meterWord && (m.contains("값") || m.contains("value") || m.contains("status")));
}

private boolean wantsAlarmSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return m.contains("최근알람") || m.contains("최신알람")
        || m.contains("알람요약") || m.contains("경보요약")
        || m.contains("alarm") || m.contains("alert")
        || m.contains("이상내역");
}

private boolean wantsMonthlyFrequencySummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
    boolean hasAverage = m.contains("평균") || m.contains("avg") || m.contains("mean");
    boolean hasPeriod = m.contains("월") || m.contains("month");
    return hasFrequency && (hasAverage || hasPeriod);
}

private boolean wantsVoltageAverageSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasVoltage = m.contains("전압") || m.contains("voltage");
    boolean hasAvg = m.contains("평균") || m.contains("avg") || m.contains("mean");
    boolean hasDate = m.matches(".*[0-9]{4}[-./][0-9]{1,2}[-./][0-9]{1,2}.*");
    boolean hasPeriod = m.contains("오늘") || m.contains("어제") || m.contains("이번주") || m.contains("금주")
        || m.contains("이번달") || m.contains("금월") || m.contains("올해") || m.contains("금년")
        || m.contains("일주일") || m.contains("1주") || m.contains("최근7일")
        || m.contains("월") || m.contains("year") || m.contains("week") || m.contains("month")
        || m.matches(".*[0-9]+일.*") || hasDate;
    return hasVoltage && hasAvg && hasPeriod;
}

private boolean wantsPerMeterPowerSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean meterScope = m.contains("각계측기") || m.contains("모든계측기") || m.contains("계측기별")
        || (m.contains("각") && m.contains("계측기")) || (m.contains("all") && m.contains("meter"));
    boolean powerWord = m.contains("전력량") || m.contains("전력") || m.contains("사용전력")
        || m.contains("kw") || m.contains("kwh") || m.contains("power");
    return meterScope && powerWord;
}

private boolean wantsHarmonicSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
}

private boolean wantsMonthlyPowerStats(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return (m.contains("월") || m.contains("month")) &&
        (m.contains("전력") || m.contains("kw") || m.contains("power")) &&
        (m.contains("평균") || m.contains("최대") || m.contains("max") || m.contains("avg"));
}

private boolean wantsBuildingPowerTopN(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasBuilding = m.contains("건물") || m.contains("building");
    boolean hasPower = m.contains("전력") || m.contains("전력량") || m.contains("사용전력")
        || m.contains("kw") || m.contains("kwh") || m.contains("power");
    boolean hasTop = m.contains("top") || m.contains("상위") || m.matches(".*[0-9]+개.*");
    boolean hasListIntent = m.contains("별") || m.contains("비교") || m.contains("목록") || m.contains("보여");
    return hasBuilding && hasPower && (hasTop || hasListIntent || m.endsWith("은?") || m.endsWith("?"));
}

private boolean wantsPanelLatestStatus(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return (m.contains("패널") || m.contains("panel") || m.contains("계열")) &&
        (m.contains("최신") || m.contains("최근")) &&
        (m.contains("상태") || m.contains("status"));
}

private boolean wantsAlarmSeveritySummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return (m.contains("알람") || m.contains("alarm")) &&
        (m.contains("심각도") || m.contains("severity")) &&
        (m.contains("건수") || m.contains("요약") || m.contains("count"));
}

private boolean wantsOpenAlarms(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return (m.contains("미해결") || m.contains("열린") || m.contains("open")) &&
        (m.contains("알람") || m.contains("alarm"));
}

private boolean wantsHarmonicExceed(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
    boolean hasOutlier = m.contains("초과") || m.contains("기준") || m.contains("threshold") || m.contains("over")
        || m.contains("이상") || m.contains("비정상") || m.contains("문제");
    boolean hasMeterScope = m.contains("계측기") || m.contains("meter") || m.contains("목록") || m.contains("리스트") || m.contains("보여");
    return hasHarmonic && (hasOutlier || hasMeterScope);
}

private boolean wantsFrequencyOutlier(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return (m.contains("주파수") || m.contains("frequency") || m.contains("hz")) &&
        (m.contains("이상") || m.contains("미만") || m.contains("초과") || m.contains("outlier"));
}

private boolean wantsVoltageUnbalanceTopN(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUnbalance =
        m.contains("불평형") || m.contains("불균형") ||
        m.contains("전압불평형") || m.contains("전압불균형") ||
        m.contains("unbalance");
    boolean hasListIntent =
        m.contains("top") || m.contains("상위") ||
        m.contains("보여줘") || m.contains("목록") || m.contains("리스트") ||
        m.matches(".*[0-9]+개.*");
    return hasUnbalance && (hasListIntent || m.contains("계측기"));
}

private boolean wantsPowerFactorOutlier(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
    boolean hasOutlier = m.contains("이상") || m.contains("비정상") || m.contains("문제")
        || m.contains("낮") || m.contains("high") || m.contains("low");
    boolean hasMeterScope = m.contains("계측기") || m.contains("meter") || m.contains("목록") || m.contains("보여");
    return hasPf && (hasOutlier || hasMeterScope);
}

private Double extractPfThreshold(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("([01](?:\\.[0-9]+)?)").matcher(src);
    if (m.find()) {
        try {
            double v = Double.parseDouble(m.group(1));
            if (v >= 0.0d && v <= 1.0d) return Double.valueOf(v);
        } catch (Exception ignore) {}
    }
    return null;
}

private int countDistinctMeterIds(String context) {
    if (context == null || context.isEmpty()) return 0;
    java.util.HashSet<String> ids = new java.util.HashSet<String>();
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(context);
    while (m.find()) {
        ids.add(m.group(1));
    }
    return ids.size();
}

private Integer extractTopN(String userMessage, int defVal, int maxVal) {
    if (userMessage == null) return Integer.valueOf(defVal);
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    java.util.regex.Matcher m1 = java.util.regex.Pattern.compile("top\\s*([0-9]{1,3})").matcher(src);
    if (m1.find()) {
        try {
            int n = Integer.parseInt(m1.group(1));
            if (n < 1) n = defVal;
            if (n > maxVal) n = maxVal;
            return Integer.valueOf(n);
        } catch (Exception ignore) {}
    }
    java.util.regex.Matcher m2 = java.util.regex.Pattern.compile("([0-9]{1,3})\\s*(개|건|위)").matcher(src);
    if (m2.find()) {
        try {
            int n = Integer.parseInt(m2.group(1));
            if (n < 1) n = defVal;
            if (n > maxVal) n = maxVal;
            return Integer.valueOf(n);
        } catch (Exception ignore) {}
    }
    return Integer.valueOf(defVal);
}

private Integer extractDays(String userMessage, int defVal, int maxVal) {
    if (userMessage == null) return Integer.valueOf(defVal);
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    if (src.contains("어제") || src.contains("yesterday")) return Integer.valueOf(1);
    if (src.contains("오늘") || src.contains("today")) return Integer.valueOf(0);
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("([0-9]{1,3})\\s*(일|day|days)").matcher(src);
    if (m.find()) {
        try {
            int d = Integer.parseInt(m.group(1));
            if (d < 1) d = defVal;
            if (d > maxVal) d = maxVal;
            return Integer.valueOf(d);
        } catch (Exception ignore) {}
    }
    return Integer.valueOf(defVal);
}

private Integer extractExplicitDays(String userMessage, int maxVal) {
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    if (src.contains("일주일") || src.contains("한주") || src.contains("1주") || src.contains("one week")) {
        return Integer.valueOf(7);
    }
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("([0-9]{1,3})\\s*(일|day|days)").matcher(src);
    if (m.find()) {
        try {
            int d = Integer.parseInt(m.group(1));
            if (d < 1) return null;
            if (d > maxVal) d = maxVal;
            return Integer.valueOf(d);
        } catch (Exception ignore) {}
    }
    return null;
}

private static class TimeWindow {
    Timestamp fromTs;
    Timestamp toTs;
    String label;
    TimeWindow(Timestamp fromTs, Timestamp toTs, String label) {
        this.fromTs = fromTs;
        this.toTs = toTs;
        this.label = label;
    }
}

private java.time.LocalDate extractExplicitDate(String userMessage) {
    if (userMessage == null) return null;
    java.util.regex.Matcher dm = java.util.regex.Pattern
        .compile("([0-9]{4})[-./]([0-9]{1,2})[-./]([0-9]{1,2})")
        .matcher(userMessage);
    if (dm.find()) {
        try {
            int y = Integer.parseInt(dm.group(1));
            int m = Integer.parseInt(dm.group(2));
            int d = Integer.parseInt(dm.group(3));
            return java.time.LocalDate.of(y, m, d);
        } catch (Exception ignore) {}
    }
    return null;
}

private TimeWindow extractTimeWindow(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    java.time.LocalDate today = java.time.LocalDate.now();
    java.time.LocalDate explicitDate = extractExplicitDate(userMessage);

    if (explicitDate != null) {
        return new TimeWindow(
            Timestamp.valueOf(explicitDate.atStartOfDay()),
            Timestamp.valueOf(explicitDate.plusDays(1).atStartOfDay()),
            explicitDate.toString()
        );
    }

    if (src.contains("어제") || src.contains("yesterday")) {
        java.time.LocalDate d = today.minusDays(1);
        return new TimeWindow(Timestamp.valueOf(d.atStartOfDay()), Timestamp.valueOf(d.plusDays(1).atStartOfDay()), d.toString());
    }
    if (src.contains("오늘") || src.contains("today")) {
        return new TimeWindow(Timestamp.valueOf(today.atStartOfDay()), Timestamp.valueOf(today.plusDays(1).atStartOfDay()), today.toString());
    }
    if (src.contains("이번주") || src.contains("금주") || src.contains("this week")) {
        java.time.LocalDate weekStart = today.with(java.time.DayOfWeek.MONDAY);
        return new TimeWindow(Timestamp.valueOf(weekStart.atStartOfDay()), Timestamp.valueOf(weekStart.plusDays(7).atStartOfDay()), weekStart.toString() + "~week");
    }
    if (src.contains("일주일") || src.contains("한주") || src.contains("1주") || src.contains("one week") || src.contains("최근7일")) {
        java.time.LocalDate from = today.minusDays(6);
        return new TimeWindow(Timestamp.valueOf(from.atStartOfDay()), Timestamp.valueOf(today.plusDays(1).atStartOfDay()), from.toString() + "~7d");
    }
    if (src.contains("이번달") || src.contains("금월") || src.contains("this month")) {
        java.time.LocalDate monthStart = today.withDayOfMonth(1);
        return new TimeWindow(Timestamp.valueOf(monthStart.atStartOfDay()), Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()), monthStart.toString().substring(0, 7));
    }
    if (src.contains("올해") || src.contains("금년") || src.contains("this year")) {
        java.time.LocalDate yearStart = today.withDayOfYear(1);
        return new TimeWindow(Timestamp.valueOf(yearStart.atStartOfDay()), Timestamp.valueOf(yearStart.plusYears(1).atStartOfDay()), String.valueOf(today.getYear()));
    }
    return null;
}

private Double extractHzThreshold(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("([0-9]{2,3}(?:\\.[0-9]+)?)\\s*hz").matcher(src);
    if (m.find()) {
        try { return Double.valueOf(m.group(1)); } catch (Exception ignore) {}
    }
    return null;
}

private Integer extractMonth(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    if (src.contains("이번달") || src.contains("금월") || src.contains("this month")) {
        return Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    }
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("([0-9]{1,2})\\s*월").matcher(src);
    if (m.find()) {
        try {
            int mm = Integer.parseInt(m.group(1));
            if (mm >= 1 && mm <= 12) return Integer.valueOf(mm);
        } catch (Exception ignore) {}
    }
    return null;
}

private Integer extractMeterId(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);

    java.util.regex.Matcher m1 = java.util.regex.Pattern.compile("(?:meter|미터)\\s*([0-9]{1,6})").matcher(src);
    if (m1.find()) {
        try { return Integer.valueOf(m1.group(1)); } catch (Exception ignore) {}
    }
    java.util.regex.Matcher m2 = java.util.regex.Pattern.compile("([0-9]{1,6})\\s*번").matcher(src);
    if (m2.find()) {
        try { return Integer.valueOf(m2.group(1)); } catch (Exception ignore) {}
    }
    return null;
}

private List<String> extractPanelTokens(String userMessage) {
    ArrayList<String> tokens = new ArrayList<String>();
    if (userMessage == null) return tokens;
    String msg = userMessage.trim();

    String candidate = null;
    java.util.regex.Matcher m = java.util.regex.Pattern
        .compile("(.+?)\\s*의\\s*(전압|전류|역률|전력|값|최근.*계측|최근.*측정|계측|측정)")
        .matcher(msg);
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
        if (p.length() < 2) continue;
        if ("meter".equalsIgnoreCase(p) || "미터".equals(p)) continue;
        if ("계측기".equals(p) || "각".equals(p) || "모든".equals(p) || "전체".equals(p)) continue;
        tokens.add(p.toUpperCase(java.util.Locale.ROOT));
    }
    return tokens;
}

private List<String> extractPanelTokensLoose(String userMessage) {
    ArrayList<String> tokens = new ArrayList<String>();
    if (userMessage == null) return tokens;
    java.util.regex.Matcher m = java.util.regex.Pattern
        .compile("([A-Za-z]{2,6}[ _\\-]?[0-9]{0,2}[A-Za-z]?)")
        .matcher(userMessage);
    while (m.find()) {
        String t = m.group(1);
        if (t == null) continue;
        t = t.trim();
        if (t.length() < 3) continue;
        String up = t.toUpperCase(java.util.Locale.ROOT);
        if (up.contains("MDB") || up.contains("VCB") || up.contains("ACB") || up.contains("PANEL")) {
            tokens.add(up.replaceAll("[\\s\\-]+", "_"));
            if (tokens.size() >= 3) break;
        }
    }
    return tokens;
}

private String getRecentMeterContext(Integer meterId, List<String> panelTokens) {
    String baseSelect =
        "SELECT TOP %d m.meter_id, m.name AS meter_name, ms.measured_at, " +
        "m.panel_name, ms.average_voltage, ms.line_voltage_avg, ms.phase_voltage_avg, ms.voltage_ab, ms.average_current, " +
        "COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c) / 3.0) AS power_factor, " +
        "ms.active_power_total, ms.quality_status " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id ";

    boolean filtered = (meterId != null);
    boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
    StringBuilder where = new StringBuilder();
    if (filtered) {
        where.append("WHERE m.meter_id = ? ");
    } else if (panelFiltered) {
        where.append("WHERE 1=1 ");
        for (int i = 0; i < panelTokens.size(); i++) {
            where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
        }
    }

    int topN = filtered ? 1 : (panelFiltered ? 1 : 3);
    String sql = String.format(baseSelect, topN)
        + where.toString()
        + "ORDER BY ms.measurement_id DESC";

    StringBuilder sb = new StringBuilder(filtered
        ? "[Latest meter readings: meter_id=" + meterId + "]"
        : (panelFiltered
            ? "[Latest meter readings: panel=" + panelTokens + "]"
            : "[Latest meter readings]"));
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        if (filtered) {
            ps.setInt(1, meterId.intValue());
        } else if (panelFiltered) {
            int pi = 1;
            for (int i = 0; i < panelTokens.size(); i++) {
                String t = panelTokens.get(i);
                String normalized = t.replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT);
                ps.setString(pi++, "%" + normalized + "%");
            }
        }
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            int i = 0;
            while (rs.next()) {
                i++;
                int rowMeterId = rs.getInt("meter_id");
                String meterName = clip(rs.getString("meter_name"), 40);
                String panelName = clip(rs.getString("panel_name"), 60);
                Timestamp measuredAt = rs.getTimestamp("measured_at");
                double avgV = rs.getDouble("average_voltage");
                double lineV = rs.getDouble("line_voltage_avg");
                double phaseV = rs.getDouble("phase_voltage_avg");
                double vab = rs.getDouble("voltage_ab");
                double v = chooseVoltage(avgV, lineV, phaseV, vab);
                double c = rs.getDouble("average_current");
                double pf = rs.getDouble("power_factor");
                double kw = rs.getDouble("active_power_total");
                String q = clip(rs.getString("quality_status"), 20);
                boolean noSignal = isZeroish(v) && isZeroish(c) && isZeroish(pf) && isZeroish(kw);

                sb.append(" ")
                  .append(i).append(")")
                  .append("meter_id=").append(rowMeterId).append(", ")
                  .append(meterName.isEmpty() ? "-" : meterName)
                  .append(", panel=").append(panelName.isEmpty() ? "-" : panelName)
                  .append(" @ ").append(fmtTs(measuredAt))
                  .append(" V=").append(fmtNum(v))
                  .append(", I=").append(fmtNum(c))
                  .append(", PF=").append(fmtNum(pf))
                  .append(", kW=").append(fmtNum(kw))
                  .append(", Q=").append(q.isEmpty() ? "-" : q);
                if (noSignal) sb.append(", STATE=NO_SIGNAL");
                sb
                  .append(";");
            }
            if (i == 0) {
                return filtered
                    ? ("[Latest meter readings: meter_id=" + meterId + "] no data")
                    : (panelFiltered
                        ? ("[Latest meter readings: panel=" + panelTokens + "] no data")
                        : "[Latest meter readings] no data");
            }
        }
    } catch (Exception e) {
        return (filtered
                ? ("[Latest meter readings: meter_id=" + meterId + "]")
                : (panelFiltered
                    ? ("[Latest meter readings: panel=" + panelTokens + "]")
                    : "[Latest meter readings]"))
            + " unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
    return sb.toString();
}

private String getRecentAlarmContext() {
    String unresolvedSql =
        "SELECT COUNT(1) AS cnt " +
        "FROM dbo.vw_alarm_log " +
        "WHERE cleared_at IS NULL";

    String latestSql =
        "SELECT TOP 5 severity, alarm_type, meter_name, triggered_at, cleared_at, description " +
        "FROM dbo.vw_alarm_log " +
        "ORDER BY triggered_at DESC";

    try (Connection conn = openDbConnection()) {
        int unresolved = 0;
        try (PreparedStatement ps = conn.prepareStatement(unresolvedSql)) {
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) unresolved = rs.getInt("cnt");
            }
        }

        StringBuilder sb = new StringBuilder("[Latest alarms]");
        sb.append(" unresolved=").append(unresolved).append(";");

        try (PreparedStatement ps = conn.prepareStatement(latestSql)) {
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                int i = 0;
                while (rs.next()) {
                    i++;
                    String sev = clip(rs.getString("severity"), 20);
                    String type = clip(rs.getString("alarm_type"), 40);
                    String meter = clip(rs.getString("meter_name"), 40);
                    Timestamp trig = rs.getTimestamp("triggered_at");
                    Timestamp clr = rs.getTimestamp("cleared_at");
                    String desc = clip(rs.getString("description"), 80);

                    sb.append(" ")
                      .append(i).append(")")
                      .append(sev.isEmpty() ? "-" : sev)
                      .append("/")
                      .append(type.isEmpty() ? "-" : type)
                      .append(" @ ").append(meter.isEmpty() ? "-" : meter)
                      .append(" t=").append(fmtTs(trig))
                      .append(", cleared=").append(clr == null ? "N" : "Y");
                    if (!desc.isEmpty()) sb.append(", desc=").append(desc);
                    sb.append(";");
                }
                if (i == 0) sb.append(" no recent alarm;");
            }
        }

        return sb.toString();
    } catch (Exception e) {
        return "[Latest alarms] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getMonthlyAvgFrequencyContext(Integer meterId, Integer month) {
    Integer targetMonth = month;
    int year = java.time.LocalDate.now().getYear();

    try (Connection conn = openDbConnection()) {
        if (targetMonth == null) {
            String ymSql =
                "SELECT TOP 1 YEAR(measured_at) AS yy, MONTH(measured_at) AS mm " +
                "FROM dbo.measurements " +
                (meterId != null ? "WHERE meter_id = ? " : "") +
                "ORDER BY measurement_id DESC";
            try (PreparedStatement ps = conn.prepareStatement(ymSql)) {
                if (meterId != null) ps.setInt(1, meterId.intValue());
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        year = rs.getInt("yy");
                        targetMonth = Integer.valueOf(rs.getInt("mm"));
                    }
                }
            }
        } else {
            String ySql =
                "SELECT TOP 1 YEAR(measured_at) AS yy " +
                "FROM dbo.measurements " +
                "WHERE MONTH(measured_at)=? " +
                (meterId != null ? "AND meter_id=? " : "") +
                "ORDER BY yy DESC";
            try (PreparedStatement ps = conn.prepareStatement(ySql)) {
                int pi = 1;
                ps.setInt(pi++, targetMonth.intValue());
                if (meterId != null) ps.setInt(pi++, meterId.intValue());
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) year = rs.getInt("yy");
                }
            }
        }

        if (targetMonth == null) return "[Monthly frequency avg] no data";

        String sql =
            "SELECT AVG(CAST(frequency AS float)) AS avg_hz, " +
            "MIN(CAST(frequency AS float)) AS min_hz, " +
            "MAX(CAST(frequency AS float)) AS max_hz, " +
            "COUNT(1) AS sample_count " +
            "FROM dbo.measurements " +
            "WHERE YEAR(measured_at)=? AND MONTH(measured_at)=? " +
            (meterId != null ? "AND meter_id=? " : "");
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            ps.setInt(pi++, year);
            ps.setInt(pi++, targetMonth.intValue());
            if (meterId != null) ps.setInt(pi++, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    long n = rs.getLong("sample_count");
                    if (n <= 0) {
                        return "[Monthly frequency avg] meter_id=" + (meterId == null ? "-" : meterId)
                            + ", period=" + year + "-" + String.format(java.util.Locale.US, "%02d", targetMonth.intValue())
                            + ", no data";
                    }
                    double avg = rs.getDouble("avg_hz");
                    double min = rs.getDouble("min_hz");
                    double max = rs.getDouble("max_hz");
                    return "[Monthly frequency avg] meter_id=" + (meterId == null ? "-" : meterId)
                        + ", period=" + year + "-" + String.format(java.util.Locale.US, "%02d", targetMonth.intValue())
                        + ", avg_hz=" + fmtNum(avg)
                        + ", min_hz=" + fmtNum(min)
                        + ", max_hz=" + fmtNum(max)
                        + ", samples=" + n;
                }
            }
        }
        return "[Monthly frequency avg] no data";
    } catch (Exception e) {
        return "[Monthly frequency avg] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPerMeterPowerContext() {
    String sql =
        "SELECT m.meter_id, m.name AS meter_name, m.panel_name, " +
        "x.measured_at, x.active_power_total, x.energy_consumed_total " +
        "FROM dbo.meters m " +
        "OUTER APPLY ( " +
        "  SELECT TOP 1 measured_at, active_power_total, energy_consumed_total " +
        "  FROM dbo.measurements ms " +
        "  WHERE ms.meter_id = m.meter_id " +
        "  ORDER BY ms.measured_at DESC " +
        ") x " +
        "ORDER BY m.meter_id";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(20);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Per-meter latest power]");
            int i = 0;
            int maxLines = 30;
            while (rs.next()) {
                i++;
                if (i <= maxLines) {
                    int meterId = rs.getInt("meter_id");
                    String meterName = clip(rs.getString("meter_name"), 40);
                    String panel = clip(rs.getString("panel_name"), 40);
                    Timestamp ts = rs.getTimestamp("measured_at");
                    double kw = rs.getDouble("active_power_total");
                    double kwh = rs.getDouble("energy_consumed_total");
                    sb.append(" ")
                      .append(i).append(")")
                      .append("meter_id=").append(meterId)
                      .append(", ").append(meterName.isEmpty() ? "-" : meterName)
                      .append(", panel=").append(panel.isEmpty() ? "-" : panel)
                      .append(", t=").append(fmtTs(ts))
                      .append(", kW=").append(fmtNum(kw))
                      .append(", kWh=").append(fmtNum(kwh))
                      .append(";");
                }
            }
            if (i == 0) return "[Per-meter latest power] no data";
            if (i > maxLines) sb.append(" ... total=").append(i).append(" meters");
            return sb.toString();
        }
    } catch (Exception e) {
        String msg = e.getMessage() == null ? "" : (" (" + clip(e.getMessage(), 80) + ")");
        return "[Per-meter latest power] unavailable: " + clip(e.getClass().getSimpleName(), 24) + msg;
    }
}

private String getVoltageAverageContext(Integer meterId, List<String> panelTokens, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer recentDays) {
    String expr =
        "COALESCE(ms.average_voltage, ms.line_voltage_avg, ms.phase_voltage_avg, ms.voltage_ab, ms.voltage_phase_a)";
    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    boolean filtered = (meterId != null);
    boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
    if (filtered) {
        where.append("AND m.meter_id = ? ");
    } else if (panelFiltered) {
        for (int i = 0; i < panelTokens.size(); i++) {
            where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
        }
    }
    if (fromTs != null) where.append("AND ms.measured_at >= ? ");
    if (toTs != null) where.append("AND ms.measured_at < ? ");
    if (fromTs == null && toTs == null && recentDays != null && recentDays.intValue() > 0) {
        where.append("AND ms.measured_at >= DATEADD(DAY, -?, GETDATE()) ");
    }

    int topN = filtered ? 1 : (panelFiltered ? 3 : 5);
    String sql =
        "SELECT TOP " + topN + " m.meter_id, m.name AS meter_name, m.panel_name, " +
        "AVG(CAST(CASE WHEN " + expr + " > 0 THEN " + expr + " ELSE NULL END AS float)) AS avg_v, " +
        "MIN(CAST(CASE WHEN " + expr + " > 0 THEN " + expr + " ELSE NULL END AS float)) AS min_v, " +
        "MAX(CAST(CASE WHEN " + expr + " > 0 THEN " + expr + " ELSE NULL END AS float)) AS max_v, " +
        "COUNT(CASE WHEN " + expr + " > 0 THEN 1 END) AS sample_count " +
        "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        where.toString() +
        "GROUP BY m.meter_id, m.name, m.panel_name " +
        "ORDER BY m.meter_id ASC";

    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (filtered) {
            ps.setInt(pi++, meterId.intValue());
        } else if (panelFiltered) {
            for (int i = 0; i < panelTokens.size(); i++) {
                String t = panelTokens.get(i).replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT);
                ps.setString(pi++, "%" + t + "%");
            }
        }
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        if (fromTs == null && toTs == null && recentDays != null && recentDays.intValue() > 0) {
            ps.setInt(pi++, recentDays.intValue());
        }
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Voltage avg]");
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
            else if (recentDays != null && recentDays.intValue() > 0) sb.append(" days=").append(recentDays.intValue());
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                long n = rs.getLong("sample_count");
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 24))
                  .append(", panel=").append(clip(rs.getString("panel_name"), 24))
                  .append(", avg_v=").append(n > 0 ? fmtNum(rs.getDouble("avg_v")) : "-")
                  .append(", min_v=").append(n > 0 ? fmtNum(rs.getDouble("min_v")) : "-")
                  .append(", max_v=").append(n > 0 ? fmtNum(rs.getDouble("max_v")) : "-")
                  .append(", samples=").append(n)
                  .append(";");
            }
            if (i == 0) return "[Voltage avg] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Voltage avg] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String buildVoltageAverageDirectAnswer(String voltageCtx, Integer meterId) {
    if (voltageCtx == null || voltageCtx.trim().isEmpty()) {
        return "기간 평균 전압 데이터를 찾지 못했습니다.";
    }
    if (voltageCtx.contains("no data")) {
        return "요청 기간 전압 평균 데이터가 없습니다.";
    }
    if (voltageCtx.contains("unavailable")) {
        return "전압 평균 조회를 현재 수행할 수 없습니다.";
    }
    String period = null;
    java.util.regex.Matcher p = java.util.regex.Pattern.compile("period=([^;]+)").matcher(voltageCtx);
    if (p.find()) period = p.group(1);
    java.util.regex.Matcher avg = java.util.regex.Pattern.compile("avg_v=([0-9.\\-]+)").matcher(voltageCtx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("min_v=([0-9.\\-]+)").matcher(voltageCtx);
    java.util.regex.Matcher mx = java.util.regex.Pattern.compile("max_v=([0-9.\\-]+)").matcher(voltageCtx);
    java.util.regex.Matcher sn = java.util.regex.Pattern.compile("samples=([0-9]+)").matcher(voltageCtx);
    String a = avg.find() ? avg.group(1) : "-";
    String nmin = mn.find() ? mn.group(1) : "-";
    String nmax = mx.find() ? mx.group(1) : "-";
    String s = sn.find() ? sn.group(1) : "-";
    String scope = period == null ? "지정 기간" : period;
    if (meterId != null) {
        return "meter_id=" + meterId + "의 " + scope + " 평균 전압은 " + a + "V 입니다. (최소 " + nmin + ", 최대 " + nmax + ", 샘플 " + s + ")";
    }
    return scope + " 전압 평균 조회 결과입니다.";
}

private String buildPerMeterPowerDirectAnswer(String powerCtx) {
    if (powerCtx == null || powerCtx.trim().isEmpty()) {
        return "계측기별 전력량 데이터를 찾지 못했습니다.";
    }
    if (powerCtx.contains("no data")) {
        return "계측기별 전력량 데이터가 없습니다.";
    }
    if (powerCtx.contains("unavailable")) {
        return "계측기별 전력량 조회를 현재 수행할 수 없습니다.";
    }
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("total=([0-9]+)\\s+meters").matcher(powerCtx);
    if (m.find()) {
        return "각 계측기의 최신 전력량을 조회했습니다. 총 " + m.group(1) + "개 계측기이며, 상위 30개를 표시합니다.";
    }
    return "각 계측기의 최신 전력량(kW/kWh)을 조회했습니다.";
}

private String getHarmonicContext(Integer meterId, List<String> panelTokens) {
    String base =
        "SELECT TOP 1 meter_id, meter_name, panel_name, measured_at, " +
        "thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
        "thd_current_a, thd_current_b, thd_current_c, " +
        "voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
        "current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a " +
        "FROM dbo.vw_harmonic_measurements ";

    boolean filtered = (meterId != null);
    boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
    StringBuilder where = new StringBuilder();
    if (filtered) {
        where.append("WHERE meter_id = ? ");
    } else if (panelFiltered) {
        where.append("WHERE 1=1 ");
        for (int i = 0; i < panelTokens.size(); i++) {
            where.append("AND UPPER(REPLACE(REPLACE(panel_name,'_',''),' ','')) LIKE ? ");
        }
    }
    String sql = base + where.toString() + "ORDER BY measured_at DESC";

    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        if (filtered) {
            ps.setInt(1, meterId.intValue());
        } else if (panelFiltered) {
            int pi = 1;
            for (int i = 0; i < panelTokens.size(); i++) {
                String t = panelTokens.get(i).replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT);
                ps.setString(pi++, "%" + t + "%");
            }
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) {
                return "[Harmonic summary] " + (meterId != null ? ("meter_id=" + meterId + ", ") : "") + "no data";
            }
            int rowMeterId = rs.getInt("meter_id");
            String meterName = clip(rs.getString("meter_name"), 40);
            String panel = clip(rs.getString("panel_name"), 40);
            Timestamp ts = rs.getTimestamp("measured_at");
            return "[Harmonic summary] meter_id=" + rowMeterId
                + ", meter=" + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panel.isEmpty() ? "-" : panel)
                + ", t=" + fmtTs(ts)
                + ", THD_V(A/B/C)=" + fmtNum(rs.getDouble("thd_voltage_a")) + "/" + fmtNum(rs.getDouble("thd_voltage_b")) + "/" + fmtNum(rs.getDouble("thd_voltage_c"))
                + ", THD_I(A/B/C)=" + fmtNum(rs.getDouble("thd_current_a")) + "/" + fmtNum(rs.getDouble("thd_current_b")) + "/" + fmtNum(rs.getDouble("thd_current_c"))
                + ", Vh(3/5/7/9/11)_A=" + fmtNum(rs.getDouble("voltage_h3_a")) + "/" + fmtNum(rs.getDouble("voltage_h5_a")) + "/" + fmtNum(rs.getDouble("voltage_h7_a")) + "/" + fmtNum(rs.getDouble("voltage_h9_a")) + "/" + fmtNum(rs.getDouble("voltage_h11_a"))
                + ", Ih(3/5/7/9/11)_A=" + fmtNum(rs.getDouble("current_h3_a")) + "/" + fmtNum(rs.getDouble("current_h5_a")) + "/" + fmtNum(rs.getDouble("current_h7_a")) + "/" + fmtNum(rs.getDouble("current_h9_a")) + "/" + fmtNum(rs.getDouble("current_h11_a"));
        }
    } catch (Exception e) {
        return "[Harmonic summary] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String buildHarmonicDirectAnswer(String harmonicCtx, Integer meterId) {
    if (harmonicCtx == null || harmonicCtx.trim().isEmpty()) return "고조파 데이터를 찾지 못했습니다.";
    if (harmonicCtx.contains("no data")) {
        return (meterId == null ? "" : ("meter_id=" + meterId + "의 ")) + "고조파 데이터가 없습니다.";
    }
    if (harmonicCtx.contains("unavailable")) {
        return "고조파 조회를 현재 수행할 수 없습니다.";
    }
    java.util.regex.Matcher tv = java.util.regex.Pattern.compile("THD_V\\(A/B/C\\)=([0-9.\\-]+)/([0-9.\\-]+)/([0-9.\\-]+)").matcher(harmonicCtx);
    java.util.regex.Matcher ti = java.util.regex.Pattern.compile("THD_I\\(A/B/C\\)=([0-9.\\-]+)/([0-9.\\-]+)/([0-9.\\-]+)").matcher(harmonicCtx);
    java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(harmonicCtx);
    String m = mid.find() ? mid.group(1) : (meterId == null ? "-" : String.valueOf(meterId));
    String tvs = tv.find() ? (tv.group(1) + "/" + tv.group(2) + "/" + tv.group(3)) : "-";
    String tis = ti.find() ? (ti.group(1) + "/" + ti.group(2) + "/" + ti.group(3)) : "-";
    return "meter_id=" + m + "의 최신 고조파 상태입니다. THD 전압(A/B/C)=" + tvs + ", THD 전류(A/B/C)=" + tis + ".";
}

private String getMonthlyPowerStatsContext(Integer meterId, Integer month) {
    if (meterId == null) return "[Monthly power stats] meter_id required";
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    String sql =
        "SELECT AVG(CAST(active_power_total AS float)) AS avg_kw, MAX(CAST(active_power_total AS float)) AS max_kw, COUNT(1) AS sample_count " +
        "FROM dbo.measurements WHERE meter_id=? AND YEAR(measured_at)=? AND MONTH(measured_at)=?";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setInt(2, yy);
        ps.setInt(3, mm.intValue());
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                long n = rs.getLong("sample_count");
                if (n <= 0) return "[Monthly power stats] meter_id=" + meterId + ", period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) + ", no data";
                return "[Monthly power stats] meter_id=" + meterId + ", period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) +
                    ", avg_kw=" + fmtNum(rs.getDouble("avg_kw")) + ", max_kw=" + fmtNum(rs.getDouble("max_kw")) + ", samples=" + n;
            }
        }
    } catch (Exception e) {
        return "[Monthly power stats] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
    return "[Monthly power stats] no data";
}

private String getBuildingPowerTopNContext(Integer month, Integer topN) {
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    int n = topN != null ? topN.intValue() : 5;
    String sql =
        "SELECT TOP " + n + " m.building_name, " +
        "SUM(CAST(ms.active_power_total AS float)) / NULLIF(COUNT(*),0) AS avg_kw, " +
        "SUM(CAST(ms.energy_consumed_total AS float)) AS sum_kwh " +
        "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        "WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
        "GROUP BY m.building_name ORDER BY avg_kw DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, yy);
        ps.setInt(2, mm.intValue());
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Building power TOP] period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) + ";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append(clip(rs.getString("building_name"), 30))
                  .append(": avg_kw=").append(fmtNum(rs.getDouble("avg_kw")))
                  .append(", sum_kwh=").append(fmtNum(rs.getDouble("sum_kwh"))).append(";");
            }
            if (i == 0) return "[Building power TOP] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Building power TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPanelLatestStatusContext(List<String> panelTokens, Integer topN) {
    if (panelTokens == null || panelTokens.isEmpty()) return "[Panel latest status] panel token required";
    int n = topN != null ? topN.intValue() : 5;
    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    for (int i = 0; i < panelTokens.size(); i++) where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
    String sql =
        "SELECT TOP " + n + " m.meter_id, m.name, m.panel_name, ms.measured_at, ms.active_power_total, ms.frequency, ms.voltage_unbalance_rate, ms.quality_status " +
        "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " + where.toString() +
        "ORDER BY ms.measured_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        for (int i = 0; i < panelTokens.size(); i++) {
            ps.setString(pi++, "%" + panelTokens.get(i).replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT) + "%");
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Panel latest status] panel=" + panelTokens + ";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("name"), 30))
                  .append(", panel=").append(clip(rs.getString("panel_name"), 30))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(", kW=").append(fmtNum(rs.getDouble("active_power_total")))
                  .append(", Hz=").append(fmtNum(rs.getDouble("frequency")))
                  .append(", unb=").append(fmtNum(rs.getDouble("voltage_unbalance_rate")))
                  .append(", q=").append(clip(rs.getString("quality_status"), 16))
                  .append(";");
            }
            if (i == 0) return "[Panel latest status] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Panel latest status] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getAlarmSeveritySummaryContext(Integer days) {
    return getAlarmSeveritySummaryContext(days, null, null, null);
}

private String getAlarmSeveritySummaryContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    int d = days != null ? days.intValue() : 7;
    String sql;
    boolean byRange = (fromTs != null || toTs != null);
    if (byRange) {
        StringBuilder sb = new StringBuilder(
            "SELECT severity, COUNT(1) AS cnt FROM dbo.vw_alarm_log WHERE 1=1 "
        );
        if (fromTs != null) sb.append("AND triggered_at >= ? ");
        if (toTs != null) sb.append("AND triggered_at < ? ");
        sb.append("GROUP BY severity ORDER BY cnt DESC");
        sql = sb.toString();
    } else {
        sql =
            "SELECT severity, COUNT(1) AS cnt FROM dbo.vw_alarm_log " +
            "WHERE triggered_at >= DATEADD(DAY, -?, GETDATE()) GROUP BY severity ORDER BY cnt DESC";
    }
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (byRange) {
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
        } else {
            ps.setInt(pi++, d);
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Alarm severity summary] ");
            if (byRange) {
                sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
            } else {
                sb.append("days=").append(d).append(";");
            }
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(clip(rs.getString("severity"), 20)).append("=").append(rs.getLong("cnt")).append(";");
            }
            if (i == 0) return "[Alarm severity summary] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Alarm severity summary] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getOpenAlarmsContext(Integer topN) {
    return getOpenAlarmsContext(topN, null, null, null);
}

private String getOpenAlarmsContext(Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    int n = topN != null ? topN.intValue() : 10;
    StringBuilder where = new StringBuilder("WHERE cleared_at IS NULL ");
    if (fromTs != null) where.append("AND triggered_at >= ? ");
    if (toTs != null) where.append("AND triggered_at < ? ");
    String sql =
        "SELECT TOP " + n + " severity, alarm_type, meter_name, triggered_at, description " +
        "FROM dbo.vw_alarm_log " + where.toString() + "ORDER BY triggered_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Open alarms]");
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append(clip(rs.getString("severity"), 12)).append("/")
                  .append(clip(rs.getString("alarm_type"), 24))
                  .append(" @ ").append(clip(rs.getString("meter_name"), 24))
                  .append(", t=").append(fmtTs(rs.getTimestamp("triggered_at")))
                  .append(", desc=").append(clip(rs.getString("description"), 40))
                  .append(";");
            }
            if (i == 0) return "[Open alarms] none";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Open alarms] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getHarmonicExceedListContext(Double thdV, Double thdI, Integer topN) {
    return getHarmonicExceedListContext(thdV, thdI, topN, null, null, null);
}

private String getHarmonicExceedListContext(Double thdV, Double thdI, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    double v = thdV != null ? thdV.doubleValue() : 3.0d;
    double i = thdI != null ? thdI.doubleValue() : 20.0d;
    int n = topN != null ? topN.intValue() : 10;
    StringBuilder where = new StringBuilder(
        "WHERE (thd_voltage_a > ? OR thd_voltage_b > ? OR thd_voltage_c > ? OR thd_current_a > ? OR thd_current_b > ? OR thd_current_c > ?) "
    );
    if (fromTs != null) where.append("AND measured_at >= ? ");
    if (toTs != null) where.append("AND measured_at < ? ");
    String sql =
        "WITH filtered AS ( " +
        "SELECT meter_id, meter_name, panel_name, measured_at, " +
        "thd_voltage_a, thd_voltage_b, thd_voltage_c, thd_current_a, thd_current_b, thd_current_c, " +
        "ROW_NUMBER() OVER (PARTITION BY meter_id ORDER BY measured_at DESC) AS rn " +
        "FROM dbo.vw_harmonic_measurements " + where.toString() +
        ") " +
        "SELECT TOP " + n + " meter_id, meter_name, panel_name, measured_at, " +
        "thd_voltage_a, thd_voltage_b, thd_voltage_c, thd_current_a, thd_current_b, thd_current_c " +
        "FROM filtered WHERE rn=1 ORDER BY measured_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        ps.setDouble(pi++, v); ps.setDouble(pi++, v); ps.setDouble(pi++, v);
        ps.setDouble(pi++, i); ps.setDouble(pi++, i); ps.setDouble(pi++, i);
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Harmonic exceed] thdV>" + fmtNum(v) + ", thdI>" + fmtNum(i));
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(", period=").append(periodLabel);
            sb.append(";");
            int idx = 0;
            while (rs.next()) {
                idx++;
                sb.append(" ").append(idx).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 24))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(", TV=").append(fmtNum(rs.getDouble("thd_voltage_a"))).append("/").append(fmtNum(rs.getDouble("thd_voltage_b"))).append("/").append(fmtNum(rs.getDouble("thd_voltage_c")))
                  .append(", TI=").append(fmtNum(rs.getDouble("thd_current_a"))).append("/").append(fmtNum(rs.getDouble("thd_current_b"))).append("/").append(fmtNum(rs.getDouble("thd_current_c")))
                  .append(";");
            }
            if (idx == 0) return "[Harmonic exceed] none";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Harmonic exceed] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getFrequencyOutlierListContext(Double thresholdHz, Integer topN) {
    return getFrequencyOutlierListContext(thresholdHz, topN, null, null, null);
}

private String getFrequencyOutlierListContext(Double thresholdHz, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    double hz = thresholdHz != null ? thresholdHz.doubleValue() : 59.5d;
    int n = topN != null ? topN.intValue() : 10;
    StringBuilder where = new StringBuilder("WHERE (ms.frequency < ? OR ms.frequency > ?) ");
    if (fromTs != null) where.append("AND ms.measured_at >= ? ");
    if (toTs != null) where.append("AND ms.measured_at < ? ");
    String sql =
        "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, ms.frequency " +
        "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        where.toString() + "ORDER BY ms.measured_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        ps.setDouble(pi++, hz);
        ps.setDouble(pi++, 60.5d);
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Frequency outlier] threshold<" + fmtNum(hz) + " or >60.50");
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(", period=").append(periodLabel);
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 24))
                  .append(", Hz=").append(fmtNum(rs.getDouble("frequency")))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(";");
            }
            if (i == 0) return "[Frequency outlier] none";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Frequency outlier] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getVoltageUnbalanceTopNContext(Integer topN) {
    return getVoltageUnbalanceTopNContext(topN, null, null, null);
}

private String getVoltageUnbalanceTopNContext(Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    int n = topN != null ? topN.intValue() : 10;
    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    if (fromTs != null) where.append("AND ms.measured_at >= ? ");
    if (toTs != null) where.append("AND ms.measured_at < ? ");
    String sql =
        "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, ms.measured_at, ms.voltage_unbalance_rate " +
        "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        where.toString() + "ORDER BY ms.voltage_unbalance_rate DESC, ms.measured_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Voltage unbalance TOP " + n + "]");
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 24))
                  .append(", unb=").append(fmtNum(rs.getDouble("voltage_unbalance_rate")))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(";");
            }
            if (i == 0) return "[Voltage unbalance TOP] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Voltage unbalance TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPowerFactorOutlierListContext(Double pfThreshold, Integer topN) {
    return getPowerFactorOutlierListContext(pfThreshold, topN, null, null, null);
}

private String getPowerFactorOutlierListContext(Double pfThreshold, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    double th = pfThreshold != null ? pfThreshold.doubleValue() : 0.9d;
    int n = topN != null ? topN.intValue() : 10;
    StringBuilder srcWhere = new StringBuilder("WHERE 1=1 ");
    if (fromTs != null) srcWhere.append("AND ms.measured_at >= ? ");
    if (toTs != null) srcWhere.append("AND ms.measured_at < ? ");
    String sql =
        "WITH latest AS (" +
        " SELECT ms.*, ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
        " FROM dbo.measurements ms " + srcWhere.toString() +
        ") " +
        "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
        "COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) AS pf " +
        "FROM latest ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        "WHERE ms.rn=1 " +
        "AND COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) > 0 " +
        "AND COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) < ? " +
        "ORDER BY pf ASC, ms.measured_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setDouble(pi++, th);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Power factor outlier] pf<" + fmtNum(th));
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(", period=").append(periodLabel);
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 24))
                  .append(", panel=").append(clip(rs.getString("panel_name"), 24))
                  .append(", pf=").append(fmtNum(rs.getDouble("pf")))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(";");
            }
            if (i == 0) return "[Power factor outlier] none";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Power factor outlier] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private int getPowerFactorNoSignalCount() {
    return getPowerFactorNoSignalCount(null, null);
}

private int getPowerFactorNoSignalCount(Timestamp fromTs, Timestamp toTs) {
    StringBuilder srcWhere = new StringBuilder("WHERE 1=1 ");
    if (fromTs != null) srcWhere.append("AND ms.measured_at >= ? ");
    if (toTs != null) srcWhere.append("AND ms.measured_at < ? ");
    String sql =
        "WITH latest AS (" +
        " SELECT ms.*, ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
        " FROM dbo.measurements ms " + srcWhere.toString() +
        ") " +
        "SELECT COUNT(*) AS cnt " +
        "FROM latest ms " +
        "WHERE ms.rn=1 " +
        "AND (" +
        " COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) IS NULL " +
        " OR COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) = 0" +
        ")";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return rs.getInt("cnt");
            return 0;
        }
    } catch (Exception e) {
        return -1;
    }
}

private String buildFrequencyDirectAnswer(String frequencyCtx, Integer meterId, Integer month) {
    if (frequencyCtx == null || frequencyCtx.trim().isEmpty()) {
        return "월 평균 주파수 정보를 찾지 못했습니다.";
    }
    String ctx = frequencyCtx.trim();
    String period = null;
    java.util.regex.Matcher p = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    if (p.find()) period = p.group(1);
    if (period == null) period = "-";

    if (ctx.contains("no data")) {
        return "meter_id=" + (meterId == null ? "-" : meterId) + "의 " + period + " 평균 주파수 데이터가 없습니다.";
    }
    java.util.regex.Matcher a = java.util.regex.Pattern.compile("avg_hz=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher n = java.util.regex.Pattern.compile("samples=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("min_hz=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher mx = java.util.regex.Pattern.compile("max_hz=([0-9.\\-]+)").matcher(ctx);
    String avg = a.find() ? a.group(1) : "-";
    String samples = n.find() ? n.group(1) : "-";
    String min = mn.find() ? mn.group(1) : "-";
    String max = mx.find() ? mx.group(1) : "-";
    return "meter_id=" + (meterId == null ? "-" : meterId) + "의 " + period
        + " 평균 주파수는 " + avg + "Hz 입니다. (최소 " + min + ", 최대 " + max + ", 샘플 " + samples + ")";
}

private String buildDirectDbSummary(String userMessage, String meterCtx, String alarmCtx) {
    boolean meter = wantsMeterSummary(userMessage);
    boolean alarm = wantsAlarmSummary(userMessage);
    if (!meter && !alarm) return null;

    StringBuilder sb = new StringBuilder();
    if (meter) sb.append("최근 계측 요약: ").append(meterCtx);
    if (alarm) {
        if (sb.length() > 0) sb.append("\n");
        sb.append("최근 알람 요약: ").append(alarmCtx);
    }
    return sb.toString();
}

private List<String> panelTokensFromRaw(String panel) {
    ArrayList<String> tokens = new ArrayList<String>();
    if (panel == null) return tokens;
    String candidate = panel.replaceAll("[\"'`]", " ").trim();
    if (candidate.isEmpty()) return tokens;
    String[] parts = candidate.split("[\\s_\\-]+");
    for (int i = 0; i < parts.length; i++) {
        String p = parts[i];
        if (p == null) continue;
        p = p.trim();
        if (p.length() < 2) continue;
        if ("meter".equalsIgnoreCase(p) || "미터".equals(p)) continue;
        tokens.add(p.toUpperCase(java.util.Locale.ROOT));
    }
    return tokens;
}

private String unescapeJsonText(String s) {
    if (s == null) return "";
    return s.replaceAll("\\\\\\\"", "\"")
            .replaceAll("\\\\\\\\", "\\\\")
            .replaceAll("\\\\n", "\n")
            .replaceAll("\\\\r", "\r")
            .replaceAll("\\\\t", "\t");
}

private String extractJsonStringField(String json, String field) {
    if (json == null || field == null) return null;
    try {
        java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(field) + "\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"", java.util.regex.Pattern.DOTALL);
        java.util.regex.Matcher m = p.matcher(json);
        if (m.find()) return unescapeJsonText(m.group(1));
    } catch (Exception ignore) {}
    return null;
}

private Integer extractJsonIntField(String json, String field) {
    if (json == null || field == null) return null;
    try {
        java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(field) + "\"\\s*:\\s*(\\d+)");
        java.util.regex.Matcher m = p.matcher(json);
        if (m.find()) return Integer.valueOf(m.group(1));
    } catch (Exception ignore) {}
    return null;
}

private Boolean extractJsonBoolField(String json, String field) {
    if (json == null || field == null) return null;
    try {
        java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(field) + "\"\\s*:\\s*(true|false)", java.util.regex.Pattern.CASE_INSENSITIVE);
        java.util.regex.Matcher m = p.matcher(json);
        if (m.find()) return Boolean.valueOf(m.group(1).toLowerCase(java.util.Locale.ROOT));
    } catch (Exception ignore) {}
    return null;
}

private boolean modelExistsInTagList(String tagJson, String modelName) {
    if (tagJson == null || modelName == null || modelName.isEmpty()) return false;
    return tagJson.contains("\"" + modelName + "\"") || tagJson.contains("\"" + modelName + ":");
}

private String callOllamaOnce(String ollamaUrl, String model, String prompt, int connectTimeoutMs, int readTimeoutMs, double temperature) throws Exception {
    URL apiUrl = new URL(ollamaUrl + "/api/generate");
    HttpURLConnection conn = (HttpURLConnection) apiUrl.openConnection();
    conn.setRequestMethod("POST");
    conn.setDoOutput(true);
    conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
    conn.setConnectTimeout(connectTimeoutMs);
    conn.setReadTimeout(readTimeoutMs);

    String payload = "{\"model\":\"" + model + "\",\"prompt\":" + jsonEscape(prompt) + ",\"stream\":false,\"temperature\":" + temperature + "}";
    try (OutputStream os = conn.getOutputStream()) {
        byte[] input = payload.getBytes("utf-8");
        os.write(input, 0, input.length);
    }

    int responseCode = conn.getResponseCode();
    InputStream is = (responseCode >= 200 && responseCode < 400) ? conn.getInputStream() : conn.getErrorStream();
    StringBuilder respBody = new StringBuilder();
    try (BufferedReader br = new BufferedReader(new InputStreamReader(is, "utf-8"))) {
        String line;
        while ((line = br.readLine()) != null) {
            respBody.append(line);
        }
    }
    String body = respBody.toString();
    if (responseCode < 200 || responseCode >= 400) {
        throw new RuntimeException("Ollama error " + responseCode + ": " + clip(body, 300));
    }

    String responseText = extractJsonStringField(body, "response");
    if (responseText == null || responseText.trim().isEmpty()) {
        return clip(body, 2000);
    }
    return responseText.trim();
}

private String routeModel(String userMessage, String defaultModel, String coderModel) {
    String m = normalizeForIntent(userMessage);
    boolean isCoderTask =
        m.contains("sql") || m.contains("query") || m.contains("쿼리") ||
        m.contains("select") || m.contains("where") || m.contains("join") ||
        m.contains("groupby") || m.contains("orderby") ||
        m.contains("테이블") || m.contains("컬럼") || m.contains("column") ||
        m.contains("스키마") || m.contains("schema") ||
        m.contains("ddl") || m.contains("dml") ||
        m.contains("insert") || m.contains("update") || m.contains("delete");
    return isCoderTask ? coderModel : defaultModel;
}

private String jsonEscape(String s) {
    if (s == null) return "\"\"";
    StringBuilder sb = new StringBuilder();
    sb.append('"');
    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);
        switch (c) {
            case '"': sb.append("\\\""); break;
            case '\\': sb.append("\\\\"); break;
            case '\b': sb.append("\\b"); break;
            case '\f': sb.append("\\f"); break;
            case '\n': sb.append("\\n"); break;
            case '\r': sb.append("\\r"); break;
            case '\t': sb.append("\\t"); break;
            default:
                if (c < 0x20) sb.append(String.format("\\u%04x", (int)c));
                else sb.append(c);
        }
    }
    sb.append('"');
    return sb.toString();
}

private boolean isValidInput(String input) {
    return input != null && !input.isEmpty() && input.length() <= 2000;
}
%>
<%
response.setContentType("application/json;charset=UTF-8");

response.setHeader("Access-Control-Allow-Origin", "*");
response.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
response.setHeader("Access-Control-Allow-Headers", "Content-Type");

if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
    response.setStatus(200);
    return;
}

String clientIp = request.getHeader("X-Forwarded-For");
if (clientIp == null || clientIp.isEmpty()) {
    clientIp = request.getRemoteAddr();
}

if (!checkRateLimit(clientIp)) {
    response.setStatus(429);
    out.print("{\"error\":\"Rate limit exceeded. Maximum 10 requests per minute.\"}");
    return;
}

if (!"POST".equalsIgnoreCase(request.getMethod())) {
    response.setStatus(405);
    out.print("{\"error\":\"Method not allowed\"}");
    return;
}

String body = "";
try (BufferedReader reader = request.getReader()) {
    String line;
    StringBuilder sb = new StringBuilder();
    while ((line = reader.readLine()) != null) {
        sb.append(line).append('\n');
    }
    body = sb.toString();
} catch (Exception e) {
    response.setStatus(400);
    out.print("{\"error\":\"Failed to read request\"}");
    return;
}

String userMessage = "";
try {
    java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"message\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"", java.util.regex.Pattern.DOTALL);
    java.util.regex.Matcher m = p.matcher(body);
    if (m.find()) {
        userMessage = m.group(1);
        userMessage = userMessage.replaceAll("\\\\\\\"", "\"")
                                 .replaceAll("\\\\\\\\", "\\\\")
                                 .replaceAll("\\\\n", "\n")
                                 .replaceAll("\\\\r", "\r")
                                 .replaceAll("\\\\t", "\t");
    }
} catch (Exception e) {
}

if (!isValidInput(userMessage)) {
    response.setStatus(400);
    out.print("{\"error\":\"Invalid message\"}");
    return;
}

Integer directMeterId = extractMeterId(userMessage);
Integer directMonth = extractMonth(userMessage);
Integer directTopN = extractTopN(userMessage, 10, 50);
Integer directDays = extractDays(userMessage, 7, 90);
Integer directExplicitDays = extractExplicitDays(userMessage, 90);
TimeWindow directWindow = extractTimeWindow(userMessage);
Double directHz = extractHzThreshold(userMessage);
Double directPf = extractPfThreshold(userMessage);
List<String> directPanelTokens = extractPanelTokens(userMessage);
if (wantsPanelLatestStatus(userMessage) && (directPanelTokens == null || directPanelTokens.isEmpty())) {
    directPanelTokens = extractPanelTokensLoose(userMessage);
}

String directDbContext = null;
String directAnswer = null;

if (wantsVoltageAverageSummary(userMessage)) {
    Timestamp fromTs = directWindow != null ? directWindow.fromTs : null;
    Timestamp toTs = directWindow != null ? directWindow.toTs : null;
    String periodLabel = directWindow != null ? directWindow.label : null;
    Integer daysFallback = (directWindow == null ? directExplicitDays : null);
    directDbContext = getVoltageAverageContext(directMeterId, directPanelTokens, fromTs, toTs, periodLabel, daysFallback);
    directAnswer = buildVoltageAverageDirectAnswer(directDbContext, directMeterId);
} else if (wantsMonthlyPowerStats(userMessage)) {
    directDbContext = getMonthlyPowerStatsContext(directMeterId, directMonth);
    directAnswer = directDbContext.contains("no data")
        ? "요청한 월 전력 통계 데이터가 없습니다."
        : "월 평균/최대 전력 통계를 조회했습니다.";
} else if (wantsBuildingPowerTopN(userMessage)) {
    directDbContext = getBuildingPowerTopNContext(directMonth, directTopN);
    directAnswer = directDbContext.contains("no data")
        ? "건물별 전력 TOP 데이터가 없습니다."
        : "건물별 전력 TOP 조회 결과입니다.";
} else if (wantsPanelLatestStatus(userMessage)) {
    directDbContext = getPanelLatestStatusContext(directPanelTokens, directTopN);
    directAnswer = directDbContext.contains("no data")
        ? "패널 최신 상태 데이터가 없습니다."
        : "패널 최신 상태를 조회했습니다.";
} else if (wantsAlarmSeveritySummary(userMessage)) {
    if (directWindow != null) {
        directDbContext = getAlarmSeveritySummaryContext(directDays, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getAlarmSeveritySummaryContext(directDays);
    }
    directAnswer = directDbContext.contains("no data")
        ? "심각도별 알람 집계 데이터가 없습니다."
        : "알람 심각도별 건수 요약입니다.";
} else if (wantsOpenAlarms(userMessage)) {
    if (directWindow != null) {
        directDbContext = getOpenAlarmsContext(directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getOpenAlarmsContext(directTopN);
    }
    directAnswer = directDbContext.contains("none")
        ? "현재 미해결 알람이 없습니다."
        : "현재 미해결 알람 목록입니다.";
} else if (wantsHarmonicExceed(userMessage)) {
    if (directWindow != null) {
        directDbContext = getHarmonicExceedListContext(null, null, directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
        directAnswer = directDbContext.contains("none")
            ? "지정 기간 고조파 이상 계측기가 없습니다."
            : "지정 기간 고조파 이상 계측기 목록입니다.";
    } else {
        directDbContext = getHarmonicExceedListContext(null, null, directTopN);
        directAnswer = directDbContext.contains("none")
            ? "고조파 이상 계측기가 없습니다."
            : "고조파 이상 계측기 목록입니다.";
    }
} else if (wantsFrequencyOutlier(userMessage)) {
    if (directWindow != null) {
        directDbContext = getFrequencyOutlierListContext(directHz, directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getFrequencyOutlierListContext(directHz, directTopN);
    }
    directAnswer = directDbContext.contains("none")
        ? "주파수 이상치가 없습니다."
        : "주파수 이상치 목록입니다.";
} else if (wantsVoltageUnbalanceTopN(userMessage)) {
    if (directWindow != null) {
        directDbContext = getVoltageUnbalanceTopNContext(directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getVoltageUnbalanceTopNContext(directTopN);
    }
    directAnswer = directDbContext.contains("no data")
        ? "전압 불평형 데이터가 없습니다."
        : "전압 불평형 상위 목록입니다.";
} else if (wantsPowerFactorOutlier(userMessage)) {
    if (directWindow != null) {
        directDbContext = getPowerFactorOutlierListContext(directPf, directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getPowerFactorOutlierListContext(directPf, directTopN);
    }
    int pfNoSignalCount = directWindow != null
        ? getPowerFactorNoSignalCount(directWindow.fromTs, directWindow.toTs)
        : getPowerFactorNoSignalCount();
    directAnswer = directDbContext.contains("none")
        ? "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다."
        : "역률 이상(유효신호 기준, 임계 미만) 계측기 목록입니다.";
    if (pfNoSignalCount >= 0) {
        directAnswer = directAnswer + " (신호없음 " + pfNoSignalCount + "개 별도)";
    }
}

if (directAnswer != null && directDbContext != null) {
    int meterCount = countDistinctMeterIds(directDbContext);
    if (meterCount > 0) {
        directAnswer = directAnswer + " (해당 계측기 " + meterCount + "개)";
    }
    String line = "{\"response\":\"" + escapeJsonString(directAnswer) + "\",\"done\":true}\n";
    response.setStatus(200);
    out.print("{\"provider_response\":");
    out.print(jsonEscape(line));
    out.print(",\"db_context\":");
    out.print(jsonEscape(directDbContext));
    out.print("}");
    return;
}

String ollamaUrl = System.getenv("OLLAMA_URL");
if (ollamaUrl == null || ollamaUrl.isEmpty()) {
    ollamaUrl = "http://localhost:11434";
}

String model = System.getenv("OLLAMA_MODEL");
if (model == null || model.isEmpty()) {
    model = "qwen2.5:14b";
}
String coderModel = System.getenv("OLLAMA_MODEL_CODER");
if (coderModel == null || coderModel.isEmpty()) {
    coderModel = "qwen2.5-coder:7b";
}
Properties modelConfig = loadAgentModelConfig(application);
String configuredModel = trimToNull(modelConfig.getProperty("model"));
String configuredCoderModel = trimToNull(modelConfig.getProperty("coder_model"));
if (configuredModel != null) model = configuredModel;
if (configuredCoderModel != null) coderModel = configuredCoderModel;

try {
    String listStr = "";
    try {
        URL listUrl = new URL(ollamaUrl + "/api/tags");
        HttpURLConnection listConn = (HttpURLConnection) listUrl.openConnection();
        listConn.setRequestMethod("GET");
        listConn.setConnectTimeout(3000);
        listConn.setReadTimeout(3000);
        int listCode = listConn.getResponseCode();

        if (listCode != 200) {
            response.setStatus(502);
            out.print("{\"error\":\"Ollama unavailable\"}");
            return;
        }

        StringBuilder listBody = new StringBuilder();
        try (BufferedReader br = new BufferedReader(new InputStreamReader(listConn.getInputStream(), "utf-8"))) {
            String l;
            while ((l = br.readLine()) != null) {
                listBody.append(l);
            }
        }
        listStr = listBody.toString();

        if (!modelExistsInTagList(listStr, model)) {
            response.setStatus(400);
            out.print("{\"error\":\"Model not found: " + model + "\"}");
            return;
        }
        if (!modelExistsInTagList(listStr, coderModel)) {
            response.setStatus(400);
            out.print("{\"error\":\"Model not found: " + coderModel + "\"}");
            return;
        }
    } catch (Exception e) {
        response.setStatus(502);
        out.print("{\"error\":\"Cannot reach Ollama\"}");
        return;
    }

    Integer requestedMeterId = extractMeterId(userMessage);
    Integer requestedMonth = extractMonth(userMessage);
    boolean needsPerMeterPower = wantsPerMeterPowerSummary(userMessage);
    boolean needsHarmonic = wantsHarmonicSummary(userMessage);
    List<String> panelTokens = needsPerMeterPower ? new ArrayList<String>() : extractPanelTokens(userMessage);
    String schemaContext = getSchemaContextCached();

    // Stage 1: qwen2.5:14b classifies whether DB lookup is required.
    String classifierPrompt =
        "Classify if EPMS DB lookup is needed. " +
        "Return only one JSON object with keys: needs_db(boolean), needs_meter(boolean), needs_alarm(boolean), needs_frequency(boolean), needs_power_by_meter(boolean), needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null). " +
        "No markdown. No explanation.\n\nUser: " + userMessage;
    String classifierRaw = callOllamaOnce(ollamaUrl, model, classifierPrompt, 5000, 30000, 0.1d);

    boolean needsMeter = wantsMeterSummary(userMessage);
    boolean needsAlarm = wantsAlarmSummary(userMessage);
    boolean needsFrequency = wantsMonthlyFrequencySummary(userMessage);
    boolean forceCoderFlow = coderModel.equals(routeModel(userMessage, model, coderModel));
    boolean needsDb = needsMeter || needsAlarm || needsFrequency || needsPerMeterPower || needsHarmonic;
    Boolean cNeedsDb = extractJsonBoolField(classifierRaw, "needs_db");
    Boolean cNeedsMeter = extractJsonBoolField(classifierRaw, "needs_meter");
    Boolean cNeedsAlarm = extractJsonBoolField(classifierRaw, "needs_alarm");
    Boolean cNeedsFrequency = extractJsonBoolField(classifierRaw, "needs_frequency");
    Boolean cNeedsPower = extractJsonBoolField(classifierRaw, "needs_power_by_meter");
    Boolean cNeedsHarmonic = extractJsonBoolField(classifierRaw, "needs_harmonic");
    Integer cMeterId = extractJsonIntField(classifierRaw, "meter_id");
    Integer cMonth = extractJsonIntField(classifierRaw, "month");
    String cPanel = extractJsonStringField(classifierRaw, "panel");
    if (cNeedsDb != null) needsDb = needsDb || cNeedsDb.booleanValue();
    needsDb = needsDb || forceCoderFlow;
    if (cNeedsMeter != null) needsMeter = needsMeter || cNeedsMeter.booleanValue();
    if (cNeedsAlarm != null) needsAlarm = needsAlarm || cNeedsAlarm.booleanValue();
    if (cNeedsFrequency != null) needsFrequency = needsFrequency || cNeedsFrequency.booleanValue();
    if (cNeedsPower != null) needsPerMeterPower = needsPerMeterPower || cNeedsPower.booleanValue();
    if (cNeedsHarmonic != null) needsHarmonic = needsHarmonic || cNeedsHarmonic.booleanValue();
    if (needsHarmonic && !wantsMonthlyFrequencySummary(userMessage)) needsFrequency = false;
    if (cMeterId != null) requestedMeterId = cMeterId;
    if (cMonth != null && cMonth.intValue() >= 1 && cMonth.intValue() <= 12) requestedMonth = cMonth;
    if ((panelTokens == null || panelTokens.isEmpty()) && cPanel != null && !cPanel.trim().isEmpty()) {
        panelTokens = panelTokensFromRaw(cPanel);
    }

    String meterCtx = "";
    String alarmCtx = "";
    String frequencyCtx = "";
    String powerCtx = "";
    String harmonicCtx = "";
    String dbContext = "";
    String coderDraft = "";

    // Stage 2: qwen2.5-coder:7b interprets DB task (bounded task schema).
    if (needsDb) {
        String coderPrompt =
            "You are DB task planner. Return only one JSON object with keys: " +
            "task(\"meter\"|\"alarm\"|\"both\"|\"none\"), needs_frequency(boolean), needs_power_by_meter(boolean), needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null). " +
            "No markdown. No explanation.\n\n" +
            "User: " + userMessage + "\n" +
            "Classifier JSON: " + classifierRaw + "\n\n" +
            "Schema Context:\n" + schemaContext;
        String coderRaw = callOllamaOnce(ollamaUrl, coderModel, coderPrompt, 5000, 30000, 0.1d);

        String task = extractJsonStringField(coderRaw, "task");
        Boolean planNeedsFrequency = extractJsonBoolField(coderRaw, "needs_frequency");
        Boolean planNeedsPower = extractJsonBoolField(coderRaw, "needs_power_by_meter");
        Boolean planNeedsHarmonic = extractJsonBoolField(coderRaw, "needs_harmonic");
        Integer planMeterId = extractJsonIntField(coderRaw, "meter_id");
        Integer planMonth = extractJsonIntField(coderRaw, "month");
        String planPanel = extractJsonStringField(coderRaw, "panel");
        boolean runMeter = needsMeter;
        boolean runAlarm = needsAlarm;
        boolean runFrequency = needsFrequency;
        boolean runPower = needsPerMeterPower;
        boolean runHarmonic = needsHarmonic;

        if (task != null) {
            String t = task.trim().toLowerCase(java.util.Locale.ROOT);
            if ("meter".equals(t)) { runMeter = true; runAlarm = false; }
            else if ("alarm".equals(t)) { runMeter = false; runAlarm = true; }
            else if ("both".equals(t)) { runMeter = true; runAlarm = true; }
            else if ("none".equals(t)) { runMeter = false; runAlarm = false; }
        }
        if (needsFrequency && !wantsMeterSummary(userMessage)) runMeter = false;
        if (needsFrequency && !wantsAlarmSummary(userMessage)) runAlarm = false;
        if (needsPerMeterPower && !wantsMeterSummary(userMessage)) runMeter = false;
        if (needsPerMeterPower && !wantsAlarmSummary(userMessage)) runAlarm = false;
        if (needsHarmonic && !wantsMeterSummary(userMessage)) runMeter = false;
        if (needsHarmonic && !wantsAlarmSummary(userMessage)) runAlarm = false;
        if (needsHarmonic && !wantsMonthlyFrequencySummary(userMessage)) runFrequency = false;
        if (planMeterId != null) requestedMeterId = planMeterId;
        if (planMonth != null && planMonth.intValue() >= 1 && planMonth.intValue() <= 12) requestedMonth = planMonth;
        if (planNeedsFrequency != null) runFrequency = runFrequency || planNeedsFrequency.booleanValue();
        if (planNeedsPower != null) runPower = runPower || planNeedsPower.booleanValue();
        if (planNeedsHarmonic != null) runHarmonic = runHarmonic || planNeedsHarmonic.booleanValue();
        if (needsHarmonic && !wantsMonthlyFrequencySummary(userMessage)) runFrequency = false;
        if ((panelTokens == null || panelTokens.isEmpty()) && planPanel != null && !planPanel.trim().isEmpty()) {
            panelTokens = panelTokensFromRaw(planPanel);
        }

        if (runMeter) meterCtx = getRecentMeterContext(requestedMeterId, panelTokens);
        if (runAlarm) alarmCtx = getRecentAlarmContext();
        if (runFrequency) frequencyCtx = getMonthlyAvgFrequencyContext(requestedMeterId, requestedMonth);
        if (runPower) powerCtx = getPerMeterPowerContext();
        if (runHarmonic) harmonicCtx = getHarmonicContext(requestedMeterId, panelTokens);
        if (!runMeter && !runAlarm && !runFrequency && !runPower && !runHarmonic && forceCoderFlow) {
            String coderAnswerPrompt =
                "Answer the user's DB/SQL request directly. " +
                "Use SQL Server syntax if SQL is requested. " +
                "Return concise plain text, no markdown fences.\n\n" +
                "User: " + userMessage + "\n\n" +
                "Schema Context:\n" + schemaContext;
            coderDraft = callOllamaOnce(ollamaUrl, coderModel, coderAnswerPrompt, 5000, 45000, 0.2d);
        } else if (!runMeter && !runAlarm && !runFrequency && !runPower && !runHarmonic) {
            needsDb = false;
        }
    }

    if (needsDb) {
        if (needsHarmonic && !wantsMonthlyFrequencySummary(userMessage)) {
            frequencyCtx = "";
        }
        StringBuilder dbSb = new StringBuilder();
        if (meterCtx != null && !meterCtx.trim().isEmpty()) dbSb.append("Meter: ").append(meterCtx);
        if (alarmCtx != null && !alarmCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("Alarm: ").append(alarmCtx);
        }
        if (frequencyCtx != null && !frequencyCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("Frequency: ").append(frequencyCtx);
        }
        if (powerCtx != null && !powerCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("PowerByMeter: ").append(powerCtx);
        }
        if (harmonicCtx != null && !harmonicCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("Harmonic: ").append(harmonicCtx);
        }
        if (coderDraft != null && !coderDraft.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("CoderDraft: ").append(coderDraft);
        }
        dbContext = dbSb.toString();
    }

    if (needsHarmonic && harmonicCtx != null && !harmonicCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildHarmonicDirectAnswer(harmonicCtx, requestedMeterId);
        String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";
        response.setStatus(200);
        out.print("{\"provider_response\":");
        out.print(jsonEscape(line));
        out.print(",\"db_context\":");
        out.print(jsonEscape(dbContext));
        out.print("}");
        return;
    }
    if (needsFrequency && frequencyCtx != null && !frequencyCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildFrequencyDirectAnswer(frequencyCtx, requestedMeterId, requestedMonth);
        String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";
        response.setStatus(200);
        out.print("{\"provider_response\":");
        out.print(jsonEscape(line));
        out.print(",\"db_context\":");
        out.print(jsonEscape(dbContext));
        out.print("}");
        return;
    }
    if (needsPerMeterPower && powerCtx != null && !powerCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildPerMeterPowerDirectAnswer(powerCtx);
        String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";
        response.setStatus(200);
        out.print("{\"provider_response\":");
        out.print(jsonEscape(line));
        out.print(",\"db_context\":");
        out.print(jsonEscape(dbContext));
        out.print("}");
        return;
    }

    // Stage 3: qwen2.5:14b creates final user-facing answer.
    String finalPrompt;
    if (needsDb && dbContext != null && !dbContext.isEmpty()) {
        finalPrompt =
            "You are an EPMS expert assistant. " +
            "Answer in Korean, concise, and grounded only on provided DB context. " +
            "If context indicates no signal, clearly say no signal.\n\n" +
            "User: " + userMessage + "\n\nDB Context:\n" + dbContext;
    } else {
        finalPrompt =
            "You are an EPMS expert assistant. " +
            "Answer in Korean briefly and accurately.\n\nUser: " + userMessage;
    }
    String finalAnswer = callOllamaOnce(ollamaUrl, model, finalPrompt, 5000, 60000, 0.4d);
    String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";

    response.setStatus(200);
    out.print("{\"provider_response\":");
    out.print(jsonEscape(line));
    out.print(",\"db_context\":");
    out.print(jsonEscape(dbContext));
    out.print("}");

} catch (Exception e) {
    response.setStatus(500);
    out.print("{\"error\":\"" + e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "Unknown") + "\"}");
}
%>
