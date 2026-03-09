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
private static final long DEFAULT_SCHEMA_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final Object METER_SCOPE_CACHE_LOCK = new Object();
private static final long DEFAULT_METER_SCOPE_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final int SCHEMA_MAX_TABLES = 60;
private static final int SCHEMA_MAX_COLUMNS_PER_TABLE = 40;
private static final int SCHEMA_MAX_CHARS = 16000;
private static volatile String schemaContextCache = "";
private static volatile long schemaContextCacheAt = 0L;
private static volatile long schemaCacheTtlMs = DEFAULT_SCHEMA_CACHE_TTL_MS;
private static volatile List<String> meterScopeValueCache = new ArrayList<String>();
private static volatile long meterScopeCacheAt = 0L;

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

private String normalizeOllamaUrl(String s) {
    String t = trimToNull(s);
    if (t == null) return null;
    while (t.endsWith("/")) t = t.substring(0, t.length() - 1);
    return t;
}

private Integer parsePositiveInt(String s) {
    if (s == null) return null;
    try {
        int n = Integer.parseInt(s.trim());
        if (n <= 0) return null;
        return Integer.valueOf(n);
    } catch (Exception ignore) {
        return null;
    }
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
    long ttlMs = schemaCacheTtlMs > 0 ? schemaCacheTtlMs : DEFAULT_SCHEMA_CACHE_TTL_MS;
    String cached = schemaContextCache;
    if (cached != null && !cached.isEmpty() && (now - schemaContextCacheAt) < ttlMs) {
        return cached;
    }
    synchronized (SCHEMA_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        long ttlMs2 = schemaCacheTtlMs > 0 ? schemaCacheTtlMs : DEFAULT_SCHEMA_CACHE_TTL_MS;
        if (schemaContextCache != null && !schemaContextCache.isEmpty() && (now2 - schemaContextCacheAt) < ttlMs2) {
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

private String normalizeScopeKey(String s) {
    if (s == null) return "";
    return s.toLowerCase(java.util.Locale.ROOT).replaceAll("[\\s_\\-]+", "");
}

private List<String> buildMeterScopeValuesFromDb() {
    LinkedHashSet<String> set = new LinkedHashSet<String>();
    String sql =
        "SELECT DISTINCT LTRIM(RTRIM(v)) AS v " +
        "FROM (" +
        "  SELECT building_name AS v FROM dbo.meters WHERE building_name IS NOT NULL " +
        "  UNION ALL " +
        "  SELECT usage_type AS v FROM dbo.meters WHERE usage_type IS NOT NULL " +
        ") t " +
        "WHERE LTRIM(RTRIM(v)) <> ''";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String v = trimToNull(rs.getString("v"));
                if (v == null) continue;
                if (normalizeScopeKey(v).length() < 2) continue;
                set.add(v);
            }
        }
    } catch (Exception ignore) {
    }
    ArrayList<String> out = new ArrayList<String>(set);
    java.util.Collections.sort(out, new java.util.Comparator<String>() {
        public int compare(String a, String b) {
            int la = normalizeScopeKey(a).length();
            int lb = normalizeScopeKey(b).length();
            if (la != lb) return lb - la;
            return a.compareToIgnoreCase(b);
        }
    });
    return out;
}

private List<String> getMeterScopeValuesCached() {
    long now = System.currentTimeMillis();
    List<String> cached = meterScopeValueCache;
    if (cached != null && !cached.isEmpty() && (now - meterScopeCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
        return cached;
    }
    synchronized (METER_SCOPE_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        if (meterScopeValueCache != null && !meterScopeValueCache.isEmpty() && (now2 - meterScopeCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
            return meterScopeValueCache;
        }
        List<String> fresh = buildMeterScopeValuesFromDb();
        meterScopeValueCache = fresh == null ? new ArrayList<String>() : fresh;
        meterScopeCacheAt = now2;
        return meterScopeValueCache;
    }
}

private List<String> findScopeTokensFromMeterMaster(String userMessage, int maxTokens) {
    ArrayList<String> out = new ArrayList<String>();
    String msg = normalizeScopeKey(userMessage);
    if (msg.isEmpty()) return out;
    List<String> master = getMeterScopeValuesCached();
    if (master == null || master.isEmpty()) return out;
    LinkedHashSet<String> uniq = new LinkedHashSet<String>();
    for (int i = 0; i < master.size(); i++) {
        String v = master.get(i);
        String nk = normalizeScopeKey(v);
        if (nk.length() < 2) continue;
        if (msg.contains(nk)) {
            uniq.add(v);
            if (uniq.size() >= maxTokens) break;
        }
    }
    out.addAll(uniq);
    return out;
}

private boolean wantsMeterSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean meterWord = m.contains("meter") || m.contains("미터") || m.contains("계측기");
    boolean meterIntentWord =
        m.contains("최근계측") || m.contains("최신계측")
        || m.contains("최근측정") || m.contains("최신측정")
        || m.contains("계측값") || m.contains("measurement") || m.contains("실시간상태")
        || m.contains("현재상태")
        || m.contains("전압값") || m.contains("전류값")
        || m.contains("역률") || m.contains("전력값") || m.contains("kw");
    boolean electricalWord =
        m.contains("전압") || m.contains("voltage")
        || m.contains("전류") || m.contains("current")
        || m.contains("전력") || m.contains("power")
        || m.contains("역률") || m.contains("pf");
    boolean recentWord =
        m.contains("최근") || m.contains("최신") || m.contains("실시간")
        || m.contains("current") || m.contains("latest");
    boolean statusWord = m.contains("상태") || m.contains("status");
    boolean hasMeterCode = m.matches(".*[a-z]{2,}_[a-z0-9_\\-]{2,}.*");
    boolean askForm = m.endsWith("?") || m.endsWith("는?") || m.endsWith("은?");
    boolean sqlLike = m.contains("select") || m.contains("where") || m.contains("join")
        || m.contains("query") || m.contains("sql") || m.contains("테이블") || m.contains("컬럼");
    if (sqlLike) return false;
    if (hasMeterCode && (statusWord || askForm)) return true;
    if (meterWord && statusWord) return true;
    if (meterWord && electricalWord) return true;
    if (electricalWord && recentWord && (m.contains("계측기") || meterWord)) return true;
    return meterIntentWord || (meterWord && (m.contains("값") || m.contains("value") || m.contains("status") || m.contains("상태")));
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

private boolean wantsVoltagePhaseAngle(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasVoltage = m.contains("전압") || m.contains("voltage");
    boolean hasPhase = m.contains("위상각") || m.contains("phaseangle") || m.contains("phase");
    return hasVoltage && hasPhase;
}

private boolean wantsCurrentPhaseAngle(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasCurrent = m.contains("전류") || m.contains("current");
    boolean hasPhase = m.contains("위상각") || m.contains("phaseangle") || m.contains("phase");
    return hasCurrent && hasPhase;
}

private boolean wantsPhaseCurrentValue(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasCurrent = m.contains("전류") || m.contains("current");
    boolean hasPhase = m.contains("a상") || m.contains("b상") || m.contains("c상")
        || m.contains("r상") || m.contains("s상") || m.contains("t상");
    return hasCurrent && hasPhase;
}

private boolean wantsPhaseVoltageValue(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasVoltage = m.contains("전압") || m.contains("voltage");
    boolean hasPhase = m.contains("a상") || m.contains("b상") || m.contains("c상")
        || m.contains("r상") || m.contains("s상") || m.contains("t상");
    return hasVoltage && hasPhase;
}

private boolean wantsLineVoltageValue(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasVoltage = m.contains("전압") || m.contains("voltage");
    boolean hasLine = m.contains("선간") || m.contains("linevoltage")
        || m.contains("vab") || m.contains("vbc") || m.contains("vca")
        || m.contains("ab상") || m.contains("bc상") || m.contains("ca상");
    return hasVoltage && hasLine;
}

private String extractPhaseLabel(String userMessage) {
    if (userMessage == null) return null;
    String m = normalizeForIntent(userMessage);
    if (m.contains("a상") || m.contains("r상")) return "A";
    if (m.contains("b상") || m.contains("s상")) return "B";
    if (m.contains("c상") || m.contains("t상")) return "C";
    return null;
}

private String extractLinePairLabel(String userMessage) {
    if (userMessage == null) return null;
    String m = normalizeForIntent(userMessage);
    if (m.contains("vab") || m.contains("ab상") || m.contains("a-b") || m.contains("rs") || m.contains("r-s")) return "AB";
    if (m.contains("vbc") || m.contains("bc상") || m.contains("b-c") || m.contains("st") || m.contains("s-t")) return "BC";
    if (m.contains("vca") || m.contains("ca상") || m.contains("c-a") || m.contains("tr") || m.contains("t-r")) return "CA";
    return null;
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
    boolean hasPanel = m.contains("패널") || m.contains("panel") || m.contains("판넬") || m.contains("계열");
    boolean hasStatus = m.contains("상태") || m.contains("status");
    boolean hasPanelCode = m.matches(".*(mdb|vcb|acb)[a-z0-9_\\-]*.*");
    boolean hasMeterScope = m.contains("계측기") || m.contains("meter");
    if (hasMeterScope && !hasPanel) return false;
    return (hasPanel || hasPanelCode) && hasStatus;
}

private boolean wantsAlarmSeveritySummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return (m.contains("알람") || m.contains("alarm")) &&
        (m.contains("심각도") || m.contains("severity")) &&
        (m.contains("건수") || m.contains("요약") || m.contains("count"));
}

private boolean wantsAlarmTypeSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasAlarm = m.contains("알람") || m.contains("alarm") || m.contains("경보");
    boolean hasType = m.contains("종류") || m.contains("유형") || m.contains("타입")
        || m.contains("type") || m.contains("무슨알람") || m.contains("어떤알람");
    boolean hasSeverity = m.contains("심각도") || m.contains("severity");
    return hasAlarm && hasType && !hasSeverity;
}

private boolean wantsAlarmCountSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasAlarm = m.contains("알람") || m.contains("alarm") || m.contains("경보");
    boolean hasCount = m.contains("건수") || m.contains("개수") || m.contains("갯수") || m.contains("count")
        || m.contains("몇건") || m.contains("몇개")
        || m.contains("알람의수") || m.contains("수는") || m.endsWith("수");
    boolean hasOccurred = m.contains("발생") || m.contains("trigger");
    return hasAlarm && (hasCount || hasOccurred || m.endsWith("수는?") || m.endsWith("수?"));
}

private boolean wantsTripAlarmOnly(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return m.contains("트립") || m.contains("trip") || m.contains("트림");
}

private String extractAlarmTypeToken(String userMessage) {
    if (userMessage == null) return null;
    if (wantsTripAlarmOnly(userMessage)) return "TRIP";
    String src = userMessage.trim();
    java.util.regex.Matcher m1 = java.util.regex.Pattern
        .compile("([A-Za-z][A-Za-z0-9_\\-]{1,15})\\s*알람", java.util.regex.Pattern.CASE_INSENSITIVE)
        .matcher(src);
    if (m1.find()) return m1.group(1).toUpperCase(java.util.Locale.ROOT);
    java.util.regex.Matcher m2 = java.util.regex.Pattern
        .compile("알람\\s*([A-Za-z][A-Za-z0-9_\\-]{1,15})", java.util.regex.Pattern.CASE_INSENSITIVE)
        .matcher(src);
    if (m2.find()) return m2.group(1).toUpperCase(java.util.Locale.ROOT);
    return null;
}

private String extractAlarmAreaToken(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.trim();
    java.util.regex.Matcher m0 = java.util.regex.Pattern
        .compile("(.+?)\\s*(?:과|와)?\\s*관련된\\s*계측기")
        .matcher(src);
    if (m0.find()) {
        String token0 = trimToNull(m0.group(1));
        if (token0 != null) {
            token0 = token0.replaceAll("[\"'`]", "").trim();
            String n0 = normalizeForIntent(token0);
            if (token0.length() >= 2
                && !n0.contains("ocr")
                && !n0.contains("trip")
                && !n0.contains("트립")
                && !n0.contains("트림")) {
                return token0;
            }
        }
    }
    java.util.regex.Matcher m00 = java.util.regex.Pattern
        .compile("(.+?)\\s*계측기\\s*의\\s*알람")
        .matcher(src);
    if (m00.find()) {
        String token00 = trimToNull(m00.group(1));
        if (token00 != null) {
            token00 = token00.replaceAll("[\"'`]", "").trim();
            String n00 = normalizeForIntent(token00);
            if (token00.length() >= 2
                && !n00.contains("ocr")
                && !n00.contains("trip")
                && !n00.contains("트립")
                && !n00.contains("트림")) {
                return token00;
            }
        }
    }
    java.util.regex.Matcher m = java.util.regex.Pattern
        .compile("(.+?)\\s*의\\s*알람")
        .matcher(src);
    if (!m.find()) return null;
    String token = trimToNull(m.group(1));
    if (token == null) return null;
    token = token.replaceAll("[\"'`]", "").trim();
    if (token.length() < 2) return null;
    String n = normalizeForIntent(token);
    if (n.contains("ocr") || n.contains("trip") || n.contains("트립") || n.contains("트림")) return null;
    if (n.contains("계측기") || n.contains("meter")) return null;
    return token;
}

private List<String> splitAlarmAreaTokens(String areaToken) {
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
        String n = normalizeForIntent(p);
        if (n.length() < 2) continue;
        if ("알람".equals(n) || "계측기".equals(n) || "관련된".equals(n)) continue;
        uniq.add(p);
    }
    out.addAll(uniq);
    if (out.isEmpty()) out.add(norm);
    return out;
}

private boolean wantsMeterListSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasList = m.contains("리스트") || m.contains("목록") || m.contains("list");
    boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter") || m.contains("게츠기");
    boolean hasScoped = m.contains("관련된") || m.contains("의");
    boolean askMeter =
        (hasMeter && (m.endsWith("는?") || m.endsWith("은?") || m.endsWith("?"))) ||
        m.contains("계측기는") || m.contains("계측기?") ||
        m.contains("미터는") || m.contains("meter?");
    return (hasList && (hasMeter || hasScoped)) || (hasMeter && hasScoped && askMeter);
}

private String extractMeterScopeToken(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.trim();
    java.util.regex.Matcher m0 = java.util.regex.Pattern
        .compile("(.+?)\\s*(?:과|와)?\\s*관련된\\s*(?:계측기|게츠기|미터)")
        .matcher(src);
    if (m0.find()) return trimToNull(m0.group(1));
    java.util.regex.Matcher m1 = java.util.regex.Pattern
        .compile("(.+?)\\s*(?:계측기|게츠기|미터)\\s*(?:리스트|목록)")
        .matcher(src);
    if (m1.find()) return trimToNull(m1.group(1));
    java.util.regex.Matcher m2 = java.util.regex.Pattern
        .compile("(.+?)\\s*의\\s*(?:계측기|게츠기|미터)")
        .matcher(src);
    if (m2.find()) return trimToNull(m2.group(1));
    return null;
}

private String getMeterListContext(String scopeToken, Integer topN) {
    List<String> tokens = splitAlarmAreaTokens(scopeToken);
    int n = topN != null ? topN.intValue() : 20;
    if (n < 1) n = 20;
    if (n > 100) n = 100;
    StringBuilder sql = new StringBuilder(
        "SELECT TOP " + n + " meter_id, name, panel_name, building_name, usage_type FROM dbo.meters WHERE 1=1 "
    );
    for (int i = 0; i < tokens.size(); i++) {
        sql.append("AND (UPPER(ISNULL(name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(panel_name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(building_name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(usage_type,'')) LIKE ?) ");
    }
    sql.append("ORDER BY meter_id ASC");
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
        int pi = 1;
        for (int i = 0; i < tokens.size(); i++) {
            String t = "%" + tokens.get(i).toUpperCase(java.util.Locale.ROOT) + "%";
            ps.setString(pi++, t);
            ps.setString(pi++, t);
            ps.setString(pi++, t);
            ps.setString(pi++, t);
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Meter list]");
            if (tokens != null && !tokens.isEmpty()) sb.append(" scope=").append(String.join(",", tokens));
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("name"), 40))
                  .append(", panel=").append(clip(rs.getString("panel_name"), 40))
                  .append(", building=").append(clip(rs.getString("building_name"), 30))
                  .append(", usage=").append(clip(rs.getString("usage_type"), 30))
                  .append(";");
            }
            if (i == 0) return "[Meter list] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Meter list] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
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

private String extractMeterNameToken(String userMessage) {
    if (userMessage == null) return null;
    String src = userMessage.trim();
    java.util.regex.Matcher m0 = java.util.regex.Pattern
        .compile("^(?:/llm|/rule)?\\s*([A-Za-z][A-Za-z0-9_\\-]{2,})\\s*의")
        .matcher(src);
    if (m0.find()) return trimToNull(m0.group(1));
    java.util.regex.Matcher m1 = java.util.regex.Pattern
        .compile("(?:계측기|meter)\\s*([A-Za-z][A-Za-z0-9_\\-]{2,})", java.util.regex.Pattern.CASE_INSENSITIVE)
        .matcher(src);
    if (m1.find()) return trimToNull(m1.group(1));
    java.util.regex.Matcher m2 = java.util.regex.Pattern
        .compile("([A-Za-z]{2,}[A-Za-z0-9]*_[A-Za-z0-9_\\-]{2,})")
        .matcher(src);
    if (m2.find()) return trimToNull(m2.group(1));
    return null;
}

private Integer resolveMeterIdByName(String meterNameToken) {
    String token = trimToNull(meterNameToken);
    if (token == null) return null;
    String normalized = token.replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT);
    if (normalized.length() < 3) return null;
    String sql =
        "SELECT TOP 1 meter_id " +
        "FROM dbo.meters " +
        "WHERE UPPER(REPLACE(REPLACE(REPLACE(name,'_',''),'-',''),' ','')) = ? " +
        "   OR UPPER(REPLACE(REPLACE(REPLACE(name,'_',''),'-',''),' ','')) LIKE ? " +
        "ORDER BY CASE WHEN UPPER(REPLACE(REPLACE(REPLACE(name,'_',''),'-',''),' ','')) = ? THEN 0 ELSE 1 END, meter_id ASC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setString(1, normalized);
        ps.setString(2, "%" + normalized + "%");
        ps.setString(3, normalized);
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return Integer.valueOf(rs.getInt("meter_id"));
        }
    } catch (Exception ignore) {
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
        p = p.replaceAll("(?i)panel", "");
        p = p.replace("패널", "").replace("판넬", "");
        p = p.trim();
        if (p.length() < 2) continue;
        if ("meter".equalsIgnoreCase(p) || "미터".equals(p)) continue;
        if ("panel".equalsIgnoreCase(p) || "패널".equals(p)) continue;
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
        "ms.active_power_total, ms.reactive_power_total, ms.frequency, ms.quality_status " +
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
                double kvar = rs.getDouble("reactive_power_total");
                double hz = rs.getDouble("frequency");
                String q = clip(rs.getString("quality_status"), 20);
                boolean noSignal = isZeroish(v) && isZeroish(c) && isZeroish(pf) && isZeroish(kw) && isZeroish(kvar);

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
                  .append(", kVAr=").append(fmtNum(kvar))
                  .append(", Hz=").append(fmtNum(hz))
                  .append(", QS=").append(q.isEmpty() ? "-" : q);
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
    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    for (int i = 0; i < panelTokens.size(); i++) where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
    String sql =
        "WITH latest AS ( " +
        " SELECT m.meter_id, m.name, m.panel_name, ms.measured_at, " +
        " ms.average_voltage, ms.line_voltage_avg, ms.phase_voltage_avg, ms.voltage_ab, " +
        " ms.average_current, " +
        " COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) AS power_factor, " +
        " ms.frequency, ms.active_power_total, ms.reactive_power_total, " +
        " ROW_NUMBER() OVER (PARTITION BY m.meter_id ORDER BY ms.measured_at DESC) AS rn " +
        " FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        where.toString() +
        "), tree_edges AS ( " +
        " SELECT t.parent_meter_id, t.child_meter_id, ISNULL(t.sort_order, 999999) AS sort_order " +
        " FROM dbo.meter_tree t " +
        " WHERE t.is_active = 1 " +
        " AND EXISTS (SELECT 1 FROM latest l1 WHERE l1.rn=1 AND l1.meter_id = t.parent_meter_id) " +
        " AND EXISTS (SELECT 1 FROM latest l2 WHERE l2.rn=1 AND l2.meter_id = t.child_meter_id) " +
        "), ranked AS ( " +
        " SELECT *, " +
        " CASE " +
        "   WHEN EXISTS (SELECT 1 FROM tree_edges te WHERE te.parent_meter_id = latest.meter_id) " +
        "        AND NOT EXISTS (SELECT 1 FROM tree_edges te WHERE te.child_meter_id = latest.meter_id) THEN 1 " +
        "   ELSE 0 END AS is_tree_main, " +
        " CASE " +
        "   WHEN EXISTS (SELECT 1 FROM tree_edges te WHERE te.parent_meter_id = latest.meter_id) " +
        "        AND NOT EXISTS (SELECT 1 FROM tree_edges te WHERE te.child_meter_id = latest.meter_id) THEN 0 " +
        "   WHEN NOT EXISTS (SELECT 1 FROM tree_edges te WHERE te.child_meter_id = latest.meter_id) THEN 1 " +
        "   WHEN EXISTS (SELECT 1 FROM tree_edges te WHERE te.parent_meter_id = latest.meter_id) THEN 2 " +
        "   ELSE 3 END AS main_rank, " +
        " COUNT(*) OVER() AS panel_meter_count " +
        " FROM latest WHERE rn=1 " +
        ") " +
        "SELECT TOP 1 meter_id, name, panel_name, measured_at, average_voltage, line_voltage_avg, phase_voltage_avg, voltage_ab, " +
        "is_tree_main, " +
        "average_current, power_factor, frequency, active_power_total, reactive_power_total, panel_meter_count " +
        "FROM ranked ORDER BY main_rank ASC, measured_at DESC, meter_id ASC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        for (int i = 0; i < panelTokens.size(); i++) {
            ps.setString(pi++, "%" + panelTokens.get(i).replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT) + "%");
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) return "[Panel latest status] no data";
            int meterId = rs.getInt("meter_id");
            String meterName = clip(rs.getString("name"), 30);
            String panelName = clip(rs.getString("panel_name"), 30);
            Timestamp ts = rs.getTimestamp("measured_at");
            double v = chooseVoltage(rs.getDouble("average_voltage"), rs.getDouble("line_voltage_avg"), rs.getDouble("phase_voltage_avg"), rs.getDouble("voltage_ab"));
            double c = rs.getDouble("average_current");
            double pf = rs.getDouble("power_factor");
            double hz = rs.getDouble("frequency");
            double kw = rs.getDouble("active_power_total");
            double kvar = rs.getDouble("reactive_power_total");
            int isTreeMain = rs.getInt("is_tree_main");
            int meterCount = rs.getInt("panel_meter_count");
            return "[Panel latest status] panel=" + panelTokens
                + "; meter_count=" + meterCount
                + "; is_tree_main=" + isTreeMain
                + "; main_meter_id=" + meterId
                + ", " + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                + ", t=" + fmtTs(ts)
                + ", V=" + fmtNum(v)
                + ", I=" + fmtNum(c)
                + ", PF=" + fmtNum(pf)
                + ", Hz=" + fmtNum(hz)
                + ", kW=" + fmtNum(kw)
                + ", kVAr=" + fmtNum(kvar)
                + ";";
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

private String getAlarmTypeSummaryContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer meterId, boolean tripOnly, Integer topN) {
    int d = days != null ? days.intValue() : 7;
    int n = topN != null ? topN.intValue() : 20;
    if (n < 1) n = 20;
    if (n > 50) n = 50;
    boolean byRange = (fromTs != null || toTs != null);
    String meterName = getMeterNameById(meterId);
    boolean byMeter = (meterId != null && meterName != null && !meterName.isEmpty());
    String scope = tripOnly ? "trip" : "all";

    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    if (byMeter) where.append("AND meter_name = ? ");
    if (tripOnly) where.append("AND UPPER(ISNULL(alarm_type,'')) LIKE '%TRIP%' ");
    if (byRange) {
        if (fromTs != null) where.append("AND triggered_at >= ? ");
        if (toTs != null) where.append("AND triggered_at < ? ");
    } else {
        where.append("AND triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
    }

    String sql =
        "SELECT TOP " + n + " ISNULL(NULLIF(LTRIM(RTRIM(alarm_type)),''), '(미분류)') AS alarm_type, COUNT(1) AS cnt " +
        "FROM dbo.vw_alarm_log " +
        where.toString() +
        "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(alarm_type)),''), '(미분류)') " +
        "ORDER BY cnt DESC, alarm_type ASC";

    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (byMeter) ps.setString(pi++, meterName);
        if (byRange) {
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
        } else {
            ps.setInt(pi++, d);
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Alarm types] ");
            if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
            else sb.append("days=").append(d).append(";");
            sb.append(" scope=").append(scope).append(";");
            if (byMeter) sb.append(" meter_id=").append(meterId.intValue()).append("; meter_name=").append(meterName).append(";");

            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append(clip(rs.getString("alarm_type"), 40))
                  .append("=")
                  .append(rs.getLong("cnt"))
                  .append(";");
            }
            if (i == 0) return "[Alarm types] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Alarm types] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getAlarmCountContext(Integer days) {
    return getAlarmCountContext(days, null, null, null, null, null, null);
}

private String getAlarmCountContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    return getAlarmCountContext(days, fromTs, toTs, periodLabel, null, null, null);
}

private String getMeterNameById(Integer meterId) {
    if (meterId == null) return null;
    String sql = "SELECT TOP 1 name FROM dbo.meters WHERE meter_id = ?";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return trimToNull(rs.getString("name"));
        }
    } catch (Exception ignore) {
    }
    return null;
}

private String getAlarmCountContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer meterId, String alarmTypeToken, String areaToken) {
    int d = days != null ? days.intValue() : 7;
    boolean byRange = (fromTs != null || toTs != null);
    String meterName = getMeterNameById(meterId);
    boolean byMeter = (meterId != null && meterName != null && !meterName.isEmpty());
    String token = trimToNull(alarmTypeToken);
    String area = trimToNull(areaToken);
    List<String> areaTokens = splitAlarmAreaTokens(area);
    if (token != null) token = token.toUpperCase(java.util.Locale.ROOT);
    String scope = (token == null) ? "all" : ("type:" + token);
    String sql;
    if (byRange) {
        StringBuilder sb = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al WHERE 1=1 ");
        if (byMeter) sb.append("AND al.meter_name = ? ");
        if (token != null) sb.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
        if (areaTokens != null && !areaTokens.isEmpty()) {
            for (int i = 0; i < areaTokens.size(); i++) {
                sb.append("AND (UPPER(ISNULL(al.meter_name,'')) LIKE ? ");
                sb.append("OR EXISTS (SELECT 1 FROM dbo.meters m WHERE m.name = al.meter_name AND UPPER(ISNULL(m.panel_name,'')) LIKE ?)) ");
            }
        }
        if (fromTs != null) sb.append("AND al.triggered_at >= ? ");
        if (toTs != null) sb.append("AND al.triggered_at < ? ");
        sql = sb.toString();
    } else {
        StringBuilder sb = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al WHERE 1=1 ");
        if (byMeter) sb.append("AND al.meter_name = ? ");
        if (token != null) sb.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
        if (areaTokens != null && !areaTokens.isEmpty()) {
            for (int i = 0; i < areaTokens.size(); i++) {
                sb.append("AND (UPPER(ISNULL(al.meter_name,'')) LIKE ? ");
                sb.append("OR EXISTS (SELECT 1 FROM dbo.meters m WHERE m.name = al.meter_name AND UPPER(ISNULL(m.panel_name,'')) LIKE ?)) ");
            }
        }
        sb.append("AND al.triggered_at >= DATEADD(DAY, -?, GETDATE())");
        sql = sb.toString();
    }
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (byMeter) ps.setString(pi++, meterName);
        if (token != null) ps.setString(pi++, "%" + token + "%");
        if (areaTokens != null && !areaTokens.isEmpty()) {
            for (int i = 0; i < areaTokens.size(); i++) {
                String a = "%" + areaTokens.get(i).toUpperCase(java.util.Locale.ROOT) + "%";
                ps.setString(pi++, a);
                ps.setString(pi++, a);
            }
        }
        if (byRange) {
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
        } else {
            ps.setInt(pi++, d);
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                long cnt = rs.getLong("cnt");
                String meterTag = byMeter ? ("; meter_id=" + meterId.intValue() + "; meter_name=" + meterName) : "";
                String areaTag = (areaTokens == null || areaTokens.isEmpty()) ? "" : ("; area=" + String.join(",", areaTokens));
                if (byRange) return "[Alarm count] period=" + (periodLabel == null ? "-" : periodLabel) + "; scope=" + scope + areaTag + meterTag + "; count=" + cnt;
                return "[Alarm count] days=" + d + "; scope=" + scope + areaTag + meterTag + "; count=" + cnt;
            }
        }
        return "[Alarm count] no data";
    } catch (Exception e) {
        return "[Alarm count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
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

private String getVoltagePhaseAngleContext(Integer meterId) {
    if (meterId == null) return "[Voltage phase angle] meter_id required";
    String sql =
        "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
        "ms.voltage_phase_a, ms.voltage_phase_b, ms.voltage_phase_c " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "WHERE m.meter_id = ? " +
        "ORDER BY ms.measurement_id DESC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) return "[Voltage phase angle] meter_id=" + meterId + ", no data";
            String meterName = clip(rs.getString("meter_name"), 40);
            String panelName = clip(rs.getString("panel_name"), 40);
            String ts = fmtTs(rs.getTimestamp("measured_at"));
            double va = rs.getDouble("voltage_phase_a");
            if (rs.wasNull()) va = Double.NaN;
            double vb = rs.getDouble("voltage_phase_b");
            if (rs.wasNull()) vb = Double.NaN;
            double vc = rs.getDouble("voltage_phase_c");
            if (rs.wasNull()) vc = Double.NaN;
            return "[Voltage phase angle] meter_id=" + meterId
                + ", meter=" + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                + ", t=" + ts
                + ", Va=" + fmtNum(va)
                + ", Vb=" + fmtNum(vb)
                + ", Vc=" + fmtNum(vc);
        }
    } catch (Exception e) {
        return "[Voltage phase angle] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getCurrentPhaseAngleContext(Integer meterId) {
    if (meterId == null) return "[Current phase angle] meter_id required";
    String sql =
        "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
        "ms.current_phase_a, ms.current_phase_b, ms.current_phase_c " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "WHERE m.meter_id = ? " +
        "ORDER BY ms.measurement_id DESC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) return "[Current phase angle] meter_id=" + meterId + ", no data";
            String meterName = clip(rs.getString("meter_name"), 40);
            String panelName = clip(rs.getString("panel_name"), 40);
            String ts = fmtTs(rs.getTimestamp("measured_at"));
            double ia = rs.getDouble("current_phase_a");
            if (rs.wasNull()) ia = Double.NaN;
            double ib = rs.getDouble("current_phase_b");
            if (rs.wasNull()) ib = Double.NaN;
            double ic = rs.getDouble("current_phase_c");
            if (rs.wasNull()) ic = Double.NaN;
            return "[Current phase angle] meter_id=" + meterId
                + ", meter=" + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                + ", t=" + ts
                + ", Ia=" + fmtNum(ia)
                + ", Ib=" + fmtNum(ib)
                + ", Ic=" + fmtNum(ic);
        }
    } catch (Exception e) {
        return "[Current phase angle] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPhaseCurrentContext(Integer meterId, String phase) {
    String p = trimToNull(phase);
    if (meterId == null) return "[Phase current] meter_id required";
    if (p == null) return "[Phase current] phase required";
    p = p.toUpperCase(java.util.Locale.ROOT);
    String col = "A".equals(p) ? "current_a" : ("B".equals(p) ? "current_b" : ("C".equals(p) ? "current_c" : null));
    if (col == null) return "[Phase current] invalid phase";
    String sql =
        "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " + col + " AS phase_current " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "WHERE m.meter_id = ? " +
        "ORDER BY ms.measurement_id DESC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) return "[Phase current] meter_id=" + meterId + ", phase=" + p + ", no data";
            String meterName = clip(rs.getString("meter_name"), 40);
            String panelName = clip(rs.getString("panel_name"), 40);
            String ts = fmtTs(rs.getTimestamp("measured_at"));
            double i = rs.getDouble("phase_current");
            if (rs.wasNull()) i = Double.NaN;
            return "[Phase current] meter_id=" + meterId
                + ", meter=" + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                + ", t=" + ts
                + ", phase=" + p
                + ", I=" + fmtNum(i);
        }
    } catch (Exception e) {
        return "[Phase current] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPhaseVoltageContext(Integer meterId, String phase) {
    String p = trimToNull(phase);
    if (meterId == null) return "[Phase voltage] meter_id required";
    if (p == null) return "[Phase voltage] phase required";
    p = p.toUpperCase(java.util.Locale.ROOT);
    String col = "A".equals(p) ? "voltage_phase_a" : ("B".equals(p) ? "voltage_phase_b" : ("C".equals(p) ? "voltage_phase_c" : null));
    if (col == null) return "[Phase voltage] invalid phase";
    String sql =
        "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " + col + " AS phase_voltage " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "WHERE m.meter_id = ? " +
        "ORDER BY ms.measurement_id DESC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) return "[Phase voltage] meter_id=" + meterId + ", phase=" + p + ", no data";
            String meterName = clip(rs.getString("meter_name"), 40);
            String panelName = clip(rs.getString("panel_name"), 40);
            String ts = fmtTs(rs.getTimestamp("measured_at"));
            double v = rs.getDouble("phase_voltage");
            if (rs.wasNull()) v = Double.NaN;
            return "[Phase voltage] meter_id=" + meterId
                + ", meter=" + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                + ", t=" + ts
                + ", phase=" + p
                + ", V=" + fmtNum(v);
        }
    } catch (Exception e) {
        return "[Phase voltage] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getLineVoltageContext(Integer meterId, String pair) {
    if (meterId == null) return "[Line voltage] meter_id required";
    String p = trimToNull(pair);
    if (p != null) p = p.toUpperCase(java.util.Locale.ROOT);
    if (p != null && !("AB".equals(p) || "BC".equals(p) || "CA".equals(p))) p = null;
    String sql =
        "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
        "ms.voltage_ab, ms.voltage_bc, ms.voltage_ca " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "WHERE m.meter_id = ? " +
        "ORDER BY ms.measurement_id DESC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, meterId.intValue());
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) return "[Line voltage] meter_id=" + meterId + ", pair=" + (p == null ? "ALL" : p) + ", no data";
            String meterName = clip(rs.getString("meter_name"), 40);
            String panelName = clip(rs.getString("panel_name"), 40);
            String ts = fmtTs(rs.getTimestamp("measured_at"));
            double vab = rs.getDouble("voltage_ab");
            if (rs.wasNull()) vab = Double.NaN;
            double vbc = rs.getDouble("voltage_bc");
            if (rs.wasNull()) vbc = Double.NaN;
            double vca = rs.getDouble("voltage_ca");
            if (rs.wasNull()) vca = Double.NaN;
            return "[Line voltage] meter_id=" + meterId
                + ", meter=" + (meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                + ", t=" + ts
                + ", pair=" + (p == null ? "ALL" : p)
                + ", Vab=" + fmtNum(vab)
                + ", Vbc=" + fmtNum(vbc)
                + ", Vca=" + fmtNum(vca);
        }
    } catch (Exception e) {
        return "[Line voltage] unavailable: " + clip(e.getClass().getSimpleName(), 24);
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

private String buildUserDbContext(String dbContext) {
    String ctx = dbContext == null ? "" : dbContext.trim();
    if (ctx.isEmpty()) return "";

    if (ctx.contains("[Latest meter readings")) {
        if (ctx.contains("unavailable")) return "계측 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("no data")) return "요청한 조건의 계측 데이터가 없습니다.";

        java.util.regex.Matcher m = java.util.regex.Pattern.compile(
            "meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^@;]+)\\s*@\\s*([0-9\\-:\\s]+)\\s*V=([0-9.\\-]+),\\s*I=([0-9.\\-]+),\\s*PF=([0-9.\\-]+),\\s*kW=([0-9.\\-]+)(?:,\\s*kVAr=([0-9.\\-]+))?(?:,\\s*Hz=([0-9.\\-]+))?",
            java.util.regex.Pattern.CASE_INSENSITIVE
        ).matcher(ctx);
        if (m.find()) {
            String meterId = m.group(1);
            String meterName = clip(m.group(2), 40);
            String panelName = clip(m.group(3), 40);
            String ts = clip(m.group(4), 19);
            String v = m.group(5);
            String i = m.group(6);
            String pf = m.group(7);
            String kw = m.group(8);
            String kvar = m.group(9);
            String hz = m.group(10);
            boolean noSignal = ctx.contains("STATE=NO_SIGNAL");
            StringBuilder out = new StringBuilder();
            out.append(meterId).append("번 계측기");
            if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
                out.append("(").append(meterName.trim()).append(")");
            }
            out.append("의 현재 상태는 다음과 같습니다:\n\n")
               .append("- 전압(V): ").append(v).append("V\n")
               .append("- 전류(I): ").append(i).append("A\n")
               .append("- 역률(PF): ").append(pf).append("\n");
            if (hz != null && !hz.trim().isEmpty()) {
                out.append("- 주파수(Hz): ").append(hz).append("Hz\n");
            }
            out.append("- 유효전력(kW): ").append(kw).append("kW\n");
            if (kvar != null && !kvar.trim().isEmpty()) {
                out.append("- 무효전력(kVAr): ").append(kvar).append("kVAr\n");
            }
            out.append("\n측정 시각: ").append(ts);
            if (panelName != null && !panelName.trim().isEmpty() && !"-".equals(panelName.trim())) {
                out.append("\n패널: ").append(panelName.trim());
            }
            if (noSignal) {
                out.append("\n현재 상태는 신호 없음(NO_SIGNAL)으로, 데이터 미수신 가능성이 큽니다.");
            }
            return out.toString();
        }
    }

    if (ctx.contains("[Latest alarms]")) {
        if (ctx.contains("unavailable")) return "알람 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("no recent alarm")) return "최근 알람이 없습니다.";
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("unresolved=([0-9]+)").matcher(ctx);
        if (m.find()) {
            return "최근 알람 요약입니다. 현재 미해결 알람은 " + m.group(1) + "건입니다.";
        }
    }
    if (ctx.contains("[Alarm count]")) {
        if (ctx.contains("unavailable")) return "알람 건수를 현재 조회할 수 없습니다.";
        java.util.regex.Matcher p = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
        java.util.regex.Matcher d = java.util.regex.Pattern.compile("days=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher s = java.util.regex.Pattern.compile("scope=([^;]+)").matcher(ctx);
        java.util.regex.Matcher a = java.util.regex.Pattern.compile("area=([^;]+)").matcher(ctx);
        java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher c = java.util.regex.Pattern.compile("count=([0-9]+)").matcher(ctx);
        String period = p.find() ? p.group(1) : null;
        String days = d.find() ? d.group(1) : null;
        String scopeRaw = s.find() ? s.group(1) : "all";
        String area = a.find() ? a.group(1) : null;
        String meterId = mid.find() ? mid.group(1) : null;
        String cnt = c.find() ? c.group(1) : "0";
        String scope = "";
        if (meterId != null) scope += meterId + "번 계측기 ";
        if (area != null && !area.trim().isEmpty()) scope += area.trim() + " ";
        String alarmLabel = "알람";
        if (scopeRaw != null && scopeRaw.toLowerCase(java.util.Locale.ROOT).startsWith("type:")) {
            String t = scopeRaw.substring(5).trim();
            if (!t.isEmpty()) alarmLabel = t + " 알람";
        }
        if (period != null && !period.trim().isEmpty() && !"-".equals(period.trim())) {
            return scope + period + " 발생 " + alarmLabel + "은 " + cnt + "건입니다.";
        }
        if (days != null) {
            return scope + "최근 " + days + "일 발생 " + alarmLabel + "은 " + cnt + "건입니다.";
        }
        return scope + "발생 " + alarmLabel + "은 " + cnt + "건입니다.";
    }
    if (ctx.contains("[Alarm types]")) {
        if (ctx.contains("unavailable")) return "알람 종류를 현재 조회할 수 없습니다.";
        if (ctx.contains("no data")) return "알람 종류 데이터가 없습니다.";
        java.util.regex.Matcher p = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
        java.util.regex.Matcher d = java.util.regex.Pattern.compile("days=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher s = java.util.regex.Pattern.compile("scope=([^;]+)").matcher(ctx);
        java.util.regex.Matcher item = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^=;]+)=([0-9]+);").matcher(ctx);
        String period = p.find() ? p.group(1) : null;
        String days = d.find() ? d.group(1) : null;
        String scopeRaw = s.find() ? s.group(1) : "all";
        boolean tripOnly = "trip".equalsIgnoreCase(scopeRaw);
        StringBuilder out = new StringBuilder();
        if (period != null && !period.trim().isEmpty() && !"-".equals(period.trim())) {
            out.append(period).append(" ");
        } else if (days != null) {
            out.append("최근 ").append(days).append("일 ");
        }
        out.append(tripOnly ? "트립 알람 종류는 다음과 같습니다:\n" : "알람 종류는 다음과 같습니다:\n");
        int i = 0;
        while (item.find() && i < 10) {
            i++;
            out.append("- ").append(item.group(1).trim()).append(": ").append(item.group(2)).append("건\n");
        }
        if (i == 0) return tripOnly ? "트립 알람 종류를 찾지 못했습니다." : "알람 종류를 찾지 못했습니다.";
        return out.toString().trim();
    }
    if (ctx.contains("[Meter list]")) {
        if (ctx.contains("unavailable")) return "계측기 목록을 현재 조회할 수 없습니다.";
        if (ctx.contains("no data")) return "조건에 맞는 계측기 목록이 없습니다.";
        java.util.regex.Matcher sc = java.util.regex.Pattern.compile("scope=([^;]+)").matcher(ctx);
        java.util.regex.Matcher row = java.util.regex.Pattern.compile(
            "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*)(?:,\\s*building=([^,;]*))?(?:,\\s*usage=([^;]*))?;"
        ).matcher(ctx);
        String scope = sc.find() ? sc.group(1) : null;
        StringBuilder out = new StringBuilder();
        if (scope != null && !scope.trim().isEmpty()) {
            out.append(scope.trim()).append(" 관련 계측기 목록입니다:\n");
        } else {
            out.append("계측기 목록입니다:\n");
        }
        int i = 0;
        while (row.find() && i < 20) {
            i++;
            String panel = row.group(3) == null ? "-" : row.group(3).trim();
            String building = row.group(4) == null ? "-" : row.group(4).trim();
            String usage = row.group(5) == null ? "-" : row.group(5).trim();
            out.append("- ").append(row.group(1)).append("번(").append(row.group(2).trim()).append("), 패널 ").append(panel);
            if (!"-".equals(building) || !"-".equals(usage)) {
                out.append(" [").append(building).append(" / ").append(usage).append("]");
            }
            out.append("\n");
        }
        if (i == 0) return "조건에 맞는 계측기 목록을 찾지 못했습니다.";
        return out.toString().trim();
    }
    if (ctx.contains("[Panel latest status]")) {
        if (ctx.contains("unavailable")) return "패널 상태를 현재 조회할 수 없습니다.";
        if (ctx.contains("no data")) return "요청한 패널 상태 데이터가 없습니다.";
        java.util.regex.Matcher panel = java.util.regex.Pattern.compile("panel=\\[([^\\]]+)\\]").matcher(ctx);
        java.util.regex.Matcher mc = java.util.regex.Pattern.compile("meter_count=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher tm = java.util.regex.Pattern.compile("is_tree_main=([01])").matcher(ctx);
        java.util.regex.Matcher row = java.util.regex.Pattern.compile(
            "main_meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]+),\\s*t=([0-9\\-:\\s]+),\\s*V=([0-9.\\-]+),\\s*I=([0-9.\\-]+),\\s*PF=([0-9.\\-]+),\\s*Hz=([0-9.\\-]+),\\s*kW=([0-9.\\-]+),\\s*kVAr=([0-9.\\-]+)",
            java.util.regex.Pattern.CASE_INSENSITIVE
        ).matcher(ctx);
        String panelName = panel.find() ? panel.group(1) : "-";
        int meterCount = mc.find() ? Integer.parseInt(mc.group(1)) : countDistinctMeterIds(ctx);
        boolean treeMain = tm.find() && "1".equals(tm.group(1));
        if (row.find()) {
            String meterId = row.group(1);
            String meterName = clip(row.group(2), 30);
            String panelLabel = clip(row.group(3), 30);
            String ts = clip(row.group(4), 19);
            String v = row.group(5);
            String i = row.group(6);
            String pf = row.group(7);
            String hz = row.group(8);
            String kw = row.group(9);
            String kvar = row.group(10);
            String scope = meterCount > 0 ? (" (계측기 " + meterCount + "개)") : "";
            String viewPanel = (panelLabel == null || panelLabel.isEmpty() || "-".equals(panelLabel)) ? panelName : panelLabel;
            String meterRole = treeMain ? "메인 계측기" : "대표 계측기";
            StringBuilder out = new StringBuilder();
            out.append(viewPanel).append(" 패널 ").append(meterRole).append(" ");
            out.append(meterId).append("번");
            if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
                out.append("(").append(meterName).append(")");
            }
            out.append("의 현재 상태는 다음과 같습니다");
            out.append(scope).append(":\n\n")
               .append("- 전압(V): ").append(v).append("V\n")
               .append("- 전류(I): ").append(i).append("A\n")
               .append("- 역률(PF): ").append(pf).append("\n")
               .append("- 주파수(Hz): ").append(hz).append("Hz\n")
               .append("- 유효전력(kW): ").append(kw).append("kW\n")
               .append("- 무효전력(kVAr): ").append(kvar).append("kVAr\n\n")
               .append("측정 시각: ").append(ts).append("\n")
               .append("패널: ").append(viewPanel);
            return out.toString();
        }
        return panelName + " 패널 상태를 조회했습니다.";
    }
    if (ctx.contains("[Voltage phase angle]")) {
        if (ctx.contains("unavailable")) return "전압 위상각 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("no data")) return "요청한 계측기의 전압 위상각 데이터가 없습니다.";
        java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter=([^,]+)").matcher(ctx);
        java.util.regex.Matcher pn = java.util.regex.Pattern.compile("panel=([^,]+)").matcher(ctx);
        java.util.regex.Matcher ts = java.util.regex.Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        java.util.regex.Matcher va = java.util.regex.Pattern.compile("Va=([0-9.\\-]+)").matcher(ctx);
        java.util.regex.Matcher vb = java.util.regex.Pattern.compile("Vb=([0-9.\\-]+)").matcher(ctx);
        java.util.regex.Matcher vc = java.util.regex.Pattern.compile("Vc=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String a = va.find() ? va.group(1) : "-";
        String b = vb.find() ? vb.group(1) : "-";
        String c = vc.find() ? vc.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
            out.append("(").append(meterName.trim()).append(")");
        }
        out.append("의 전압 위상각은 다음과 같습니다:\n\n")
           .append("- Va: ").append(a).append("°\n")
           .append("- Vb: ").append(b).append("°\n")
           .append("- Vc: ").append(c).append("°\n\n")
           .append("측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) {
            out.append("\n패널: ").append(panel.trim());
        }
        return out.toString();
    }
    if (ctx.contains("[Current phase angle]")) {
        if (ctx.contains("unavailable")) return "전류 위상각 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("no data")) return "요청한 계측기의 전류 위상각 데이터가 없습니다.";
        java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter=([^,]+)").matcher(ctx);
        java.util.regex.Matcher pn = java.util.regex.Pattern.compile("panel=([^,]+)").matcher(ctx);
        java.util.regex.Matcher ts = java.util.regex.Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        java.util.regex.Matcher ia = java.util.regex.Pattern.compile("Ia=([0-9.\\-]+)").matcher(ctx);
        java.util.regex.Matcher ib = java.util.regex.Pattern.compile("Ib=([0-9.\\-]+)").matcher(ctx);
        java.util.regex.Matcher ic = java.util.regex.Pattern.compile("Ic=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String a = ia.find() ? ia.group(1) : "-";
        String b = ib.find() ? ib.group(1) : "-";
        String c = ic.find() ? ic.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
            out.append("(").append(meterName.trim()).append(")");
        }
        out.append("의 전류 위상각은 다음과 같습니다:\n\n")
           .append("- Ia: ").append(a).append("°\n")
           .append("- Ib: ").append(b).append("°\n")
           .append("- Ic: ").append(c).append("°\n\n")
           .append("측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) {
            out.append("\n패널: ").append(panel.trim());
        }
        return out.toString();
    }
    if (ctx.contains("[Phase current]")) {
        if (ctx.contains("unavailable")) return "상전류 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("phase required") || ctx.contains("invalid phase")) return "A/B/C 상을 지정해 주세요.";
        if (ctx.contains("no data")) return "요청한 계측기의 상전류 데이터가 없습니다.";
        java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter=([^,]+)").matcher(ctx);
        java.util.regex.Matcher pn = java.util.regex.Pattern.compile("panel=([^,]+)").matcher(ctx);
        java.util.regex.Matcher ts = java.util.regex.Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        java.util.regex.Matcher ph = java.util.regex.Pattern.compile("phase=([ABC])").matcher(ctx);
        java.util.regex.Matcher iv = java.util.regex.Pattern.compile("I=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String phase = ph.find() ? ph.group(1) : "-";
        String curr = iv.find() ? iv.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
            out.append("(").append(meterName.trim()).append(")");
        }
        out.append("의 ").append(phase).append("상 전류는 ").append(curr).append("A 입니다.\n")
           .append("측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) {
            out.append("\n패널: ").append(panel.trim());
        }
        return out.toString();
    }
    if (ctx.contains("[Phase voltage]")) {
        if (ctx.contains("unavailable")) return "상전압 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("phase required") || ctx.contains("invalid phase")) return "A/B/C 상을 지정해 주세요.";
        if (ctx.contains("no data")) return "요청한 계측기의 상전압 데이터가 없습니다.";
        java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter=([^,]+)").matcher(ctx);
        java.util.regex.Matcher pn = java.util.regex.Pattern.compile("panel=([^,]+)").matcher(ctx);
        java.util.regex.Matcher ts = java.util.regex.Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        java.util.regex.Matcher ph = java.util.regex.Pattern.compile("phase=([ABC])").matcher(ctx);
        java.util.regex.Matcher vv = java.util.regex.Pattern.compile("V=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String phase = ph.find() ? ph.group(1) : "-";
        String volt = vv.find() ? vv.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
            out.append("(").append(meterName.trim()).append(")");
        }
        out.append("의 ").append(phase).append("상 전압은 ").append(volt).append("V 입니다.\n")
           .append("측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) {
            out.append("\n패널: ").append(panel.trim());
        }
        return out.toString();
    }
    if (ctx.contains("[Line voltage]")) {
        if (ctx.contains("unavailable")) return "선간전압 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("no data")) return "요청한 계측기의 선간전압 데이터가 없습니다.";
        java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter=([^,]+)").matcher(ctx);
        java.util.regex.Matcher pn = java.util.regex.Pattern.compile("panel=([^,]+)").matcher(ctx);
        java.util.regex.Matcher ts = java.util.regex.Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        java.util.regex.Matcher pr = java.util.regex.Pattern.compile("pair=([A-Z]+)").matcher(ctx);
        java.util.regex.Matcher vabm = java.util.regex.Pattern.compile("Vab=([0-9.\\-]+)").matcher(ctx);
        java.util.regex.Matcher vbcm = java.util.regex.Pattern.compile("Vbc=([0-9.\\-]+)").matcher(ctx);
        java.util.regex.Matcher vcam = java.util.regex.Pattern.compile("Vca=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String pair = pr.find() ? pr.group(1) : "ALL";
        String vab = vabm.find() ? vabm.group(1) : "-";
        String vbc = vbcm.find() ? vbcm.group(1) : "-";
        String vca = vcam.find() ? vcam.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
            out.append("(").append(meterName.trim()).append(")");
        }
        if ("AB".equals(pair)) {
            out.append("의 AB 선간전압은 ").append(vab).append("V 입니다.\n");
        } else if ("BC".equals(pair)) {
            out.append("의 BC 선간전압은 ").append(vbc).append("V 입니다.\n");
        } else if ("CA".equals(pair)) {
            out.append("의 CA 선간전압은 ").append(vca).append("V 입니다.\n");
        } else {
            out.append("의 선간전압은 다음과 같습니다:\n")
               .append("- AB: ").append(vab).append("V\n")
               .append("- BC: ").append(vbc).append("V\n")
               .append("- CA: ").append(vca).append("V\n");
        }
        out.append("측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) {
            out.append("\n패널: ").append(panel.trim());
        }
        return out.toString();
    }

    String fallback = ctx
        .replace("STATE=NO_SIGNAL", "신호없음")
        .replace("meter_id=", "계측기 ")
        .replace("no data", "데이터 없음")
        .replace("unavailable", "조회 불가");
    return clip(fallback, 600);
}

private boolean isAdminRequest(javax.servlet.http.HttpServletRequest request, javax.servlet.ServletContext app) {
    if (request == null) return false;
    try {
        javax.servlet.http.HttpSession session = request.getSession(false);
        if (session != null) {
            Object role = session.getAttribute("role");
            if (role != null && "ADMIN".equalsIgnoreCase(String.valueOf(role).trim())) {
                return true;
            }
            Object isAdmin = session.getAttribute("isAdmin");
            if (isAdmin instanceof Boolean && ((Boolean) isAdmin).booleanValue()) {
                return true;
            }
        }
    } catch (Exception ignore) {}

    String headerToken = trimToNull(request.getHeader("X-EPMS-ADMIN-TOKEN"));
    if (headerToken == null) return false;
    Properties p = loadAgentModelConfig(app);
    String configuredToken = trimToNull(p.getProperty("admin_token"));
    if (configuredToken == null) return false;
    return configuredToken.equals(headerToken);
}

private void writeSuccessJson(javax.servlet.jsp.JspWriter out, javax.servlet.http.HttpServletResponse response, String finalAnswer, String dbContext, boolean isAdmin) throws java.io.IOException {
    String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";
    String userDbContext = buildUserDbContext(dbContext);
    String rawDbContext = isAdmin ? dbContext : "";
    response.setStatus(200);
    out.print("{\"provider_response\":");
    out.print(jsonEscape(line));
    out.print(",\"db_context\":");
    out.print(jsonEscape(rawDbContext));
    out.print(",\"db_context_user\":");
    out.print(jsonEscape(userDbContext));
    out.print(",\"is_admin\":");
    out.print(isAdmin ? "true" : "false");
    out.print("}");
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
        p = p.replaceAll("(?i)panel", "");
        p = p.replace("패널", "").replace("판넬", "");
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

private String sanitizeUngroundedJudgement(String answer, String dbContext) {
    String a = answer == null ? "" : answer;
    if (a.trim().isEmpty()) return a;
    String ctx = dbContext == null ? "" : dbContext;
    String low = a.toLowerCase(java.util.Locale.ROOT);
    boolean hasJudgement =
        low.contains("이상 징후") ||
        low.contains("이상징후") ||
        low.contains("발견되지 않았") ||
        low.contains("정상입니다") ||
        low.contains("문제 없습니다") ||
        low.contains("abnormal") ||
        low.contains("no anomaly");
    if (!hasJudgement) return a;

    // 근거 컨텍스트(명시적 이상치/경보 컨텍스트)가 없으면 판단 문구를 중립화
    String c = ctx.toLowerCase(java.util.Locale.ROOT);
    boolean grounded =
        c.contains("[frequency outlier]") ||
        c.contains("[power factor outlier]") ||
        c.contains("[harmonic exceed]") ||
        c.contains("[voltage unbalance top") ||
        c.contains("[latest alarms]") ||
        c.contains("[open alarms]") ||
        c.contains("[alarm count]");
    if (grounded) return a;

    String[] lines = a.split("\\r?\\n");
    StringBuilder out = new StringBuilder();
    for (int i = 0; i < lines.length; i++) {
        String line = lines[i];
        String l = line.toLowerCase(java.util.Locale.ROOT);
        boolean isJudgementLine =
            l.contains("이상 징후") ||
            l.contains("이상징후") ||
            l.contains("발견되지 않았") ||
            l.contains("정상입니다") ||
            l.contains("문제 없습니다") ||
            l.contains("abnormal") ||
            l.contains("no anomaly");
        if (isJudgementLine) continue;
        if (out.length() > 0) out.append('\n');
        out.append(line);
    }
    if (out.length() == 0) return "현재 제공된 값만으로는 이상 여부를 단정할 수 없습니다.";
    if (!out.toString().contains("이상 여부를 단정")) {
        out.append("\n\n현재 제공된 값만으로는 이상 여부를 단정할 수 없습니다.");
    }
    return out.toString();
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

boolean forceLlmOnly = false;
boolean forceRuleOnly = false;
try {
    String um = userMessage == null ? "" : userMessage.trim();
    if (um.toLowerCase(java.util.Locale.ROOT).startsWith("/llm ")) {
        forceLlmOnly = true;
        userMessage = um.substring(5).trim();
    } else if (um.toLowerCase(java.util.Locale.ROOT).startsWith("/rule ")) {
        forceRuleOnly = true;
        userMessage = um.substring(6).trim();
    }
} catch (Exception ignore) {
}

boolean isAdmin = isAdminRequest(request, application);

Integer directMeterId = extractMeterId(userMessage);
if (directMeterId == null) {
    directMeterId = resolveMeterIdByName(extractMeterNameToken(userMessage));
}
Integer directMonth = extractMonth(userMessage);
Integer directTopN = extractTopN(userMessage, 10, 50);
Integer directDays = extractDays(userMessage, 7, 90);
Integer directExplicitDays = extractExplicitDays(userMessage, 90);
TimeWindow directWindow = extractTimeWindow(userMessage);
Double directHz = extractHzThreshold(userMessage);
Double directPf = extractPfThreshold(userMessage);
boolean directTripOnly = wantsTripAlarmOnly(userMessage);
String directAlarmTypeToken = extractAlarmTypeToken(userMessage);
if (directTripOnly && (directAlarmTypeToken == null || directAlarmTypeToken.trim().isEmpty())) {
    directAlarmTypeToken = "TRIP";
}
String directAlarmAreaToken = extractAlarmAreaToken(userMessage);
if (directAlarmAreaToken == null || directAlarmAreaToken.trim().isEmpty()) {
    List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
    if (scopeHints != null && !scopeHints.isEmpty()) {
        directAlarmAreaToken = String.join(",", scopeHints);
    }
}
String directMeterScopeToken = extractMeterScopeToken(userMessage);
if ((directMeterScopeToken == null || directMeterScopeToken.trim().isEmpty()) &&
    directAlarmAreaToken != null && !directAlarmAreaToken.trim().isEmpty()) {
    directMeterScopeToken = directAlarmAreaToken;
}
List<String> directPanelTokens = extractPanelTokens(userMessage);
if (wantsPanelLatestStatus(userMessage) && (directPanelTokens == null || directPanelTokens.isEmpty())) {
    directPanelTokens = extractPanelTokensLoose(userMessage);
}

String directDbContext = null;
String directAnswer = null;

if (!forceLlmOnly && wantsVoltageAverageSummary(userMessage)) {
    Timestamp fromTs = directWindow != null ? directWindow.fromTs : null;
    Timestamp toTs = directWindow != null ? directWindow.toTs : null;
    String periodLabel = directWindow != null ? directWindow.label : null;
    Integer daysFallback = (directWindow == null ? directExplicitDays : null);
    directDbContext = getVoltageAverageContext(directMeterId, directPanelTokens, fromTs, toTs, periodLabel, daysFallback);
    directAnswer = buildVoltageAverageDirectAnswer(directDbContext, directMeterId);
} else if (!forceLlmOnly && wantsMonthlyPowerStats(userMessage)) {
    directDbContext = getMonthlyPowerStatsContext(directMeterId, directMonth);
    directAnswer = directDbContext.contains("no data")
        ? "요청한 월 전력 통계 데이터가 없습니다."
        : "월 평균/최대 전력 통계를 조회했습니다.";
} else if (!forceLlmOnly && wantsBuildingPowerTopN(userMessage)) {
    directDbContext = getBuildingPowerTopNContext(directMonth, directTopN);
    directAnswer = directDbContext.contains("no data")
        ? "건물별 전력 TOP 데이터가 없습니다."
        : "건물별 전력 TOP 조회 결과입니다.";
} else if (!forceLlmOnly && wantsVoltagePhaseAngle(userMessage)) {
    directDbContext = getVoltagePhaseAngleContext(directMeterId);
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty())
        ? "전압 위상각을 조회했습니다."
        : userCtx;
} else if (!forceLlmOnly && wantsCurrentPhaseAngle(userMessage)) {
    directDbContext = getCurrentPhaseAngleContext(directMeterId);
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty())
        ? "전류 위상각을 조회했습니다."
        : userCtx;
} else if (!forceLlmOnly && wantsPhaseCurrentValue(userMessage)) {
    directDbContext = getPhaseCurrentContext(directMeterId, extractPhaseLabel(userMessage));
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty()) ? "상전류를 조회했습니다." : userCtx;
} else if (!forceLlmOnly && wantsPhaseVoltageValue(userMessage)) {
    directDbContext = getPhaseVoltageContext(directMeterId, extractPhaseLabel(userMessage));
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty()) ? "상전압을 조회했습니다." : userCtx;
} else if (!forceLlmOnly && wantsLineVoltageValue(userMessage)) {
    directDbContext = getLineVoltageContext(directMeterId, extractLinePairLabel(userMessage));
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty()) ? "선간전압을 조회했습니다." : userCtx;
} else if (!forceLlmOnly && wantsMeterListSummary(userMessage)) {
    directDbContext = getMeterListContext(directMeterScopeToken, directTopN);
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty()) ? "계측기 목록을 조회했습니다." : userCtx;
} else if (!forceLlmOnly && wantsPanelLatestStatus(userMessage)) {
    directDbContext = getPanelLatestStatusContext(directPanelTokens, directTopN);
    if (directDbContext.contains("no data")) {
        directAnswer = "패널 최신 상태 데이터가 없습니다.";
    } else {
        String userCtx = buildUserDbContext(directDbContext);
        directAnswer = (userCtx == null || userCtx.trim().isEmpty())
            ? "패널 최신 상태를 조회했습니다."
            : userCtx;
    }
} else if (!forceLlmOnly && wantsAlarmTypeSummary(userMessage)) {
    if (directWindow != null) {
        directDbContext = getAlarmTypeSummaryContext(directDays, directWindow.fromTs, directWindow.toTs, directWindow.label, directMeterId, directTripOnly, directTopN);
    } else {
        directDbContext = getAlarmTypeSummaryContext(directDays, null, null, null, directMeterId, directTripOnly, directTopN);
    }
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty()) ? "알람 종류를 조회했습니다." : userCtx;
} else if (!forceLlmOnly && wantsAlarmCountSummary(userMessage)) {
    if (directWindow != null) {
        directDbContext = getAlarmCountContext(directDays, directWindow.fromTs, directWindow.toTs, directWindow.label, directMeterId, directAlarmTypeToken, directAlarmAreaToken);
    } else {
        directDbContext = getAlarmCountContext(directDays, null, null, null, directMeterId, directAlarmTypeToken, directAlarmAreaToken);
    }
    String userCtx = buildUserDbContext(directDbContext);
    directAnswer = (userCtx == null || userCtx.trim().isEmpty()) ? "알람 건수를 조회했습니다." : userCtx;
} else if (!forceLlmOnly && wantsAlarmSeveritySummary(userMessage)) {
    if (directWindow != null) {
        directDbContext = getAlarmSeveritySummaryContext(directDays, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getAlarmSeveritySummaryContext(directDays);
    }
    directAnswer = directDbContext.contains("no data")
        ? "심각도별 알람 집계 데이터가 없습니다."
        : "알람 심각도별 건수 요약입니다.";
} else if (!forceLlmOnly && wantsOpenAlarms(userMessage)) {
    if (directWindow != null) {
        directDbContext = getOpenAlarmsContext(directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getOpenAlarmsContext(directTopN);
    }
    directAnswer = directDbContext.contains("none")
        ? "현재 미해결 알람이 없습니다."
        : "현재 미해결 알람 목록입니다.";
} else if (!forceLlmOnly && wantsHarmonicExceed(userMessage)) {
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
} else if (!forceLlmOnly && wantsFrequencyOutlier(userMessage)) {
    if (directWindow != null) {
        directDbContext = getFrequencyOutlierListContext(directHz, directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getFrequencyOutlierListContext(directHz, directTopN);
    }
    directAnswer = directDbContext.contains("none")
        ? "주파수 이상치가 없습니다."
        : "주파수 이상치 목록입니다.";
} else if (!forceLlmOnly && wantsVoltageUnbalanceTopN(userMessage)) {
    if (directWindow != null) {
        directDbContext = getVoltageUnbalanceTopNContext(directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
    } else {
        directDbContext = getVoltageUnbalanceTopNContext(directTopN);
    }
    directAnswer = directDbContext.contains("no data")
        ? "전압 불평형 데이터가 없습니다."
        : "전압 불평형 상위 목록입니다.";
} else if (!forceLlmOnly && wantsPowerFactorOutlier(userMessage)) {
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
} else if (!forceLlmOnly && (wantsMeterSummary(userMessage) || wantsAlarmSummary(userMessage))) {
    boolean needMeterSummary = wantsMeterSummary(userMessage);
    boolean needAlarmSummary = wantsAlarmSummary(userMessage);
    String meterCtx = needMeterSummary ? getRecentMeterContext(directMeterId, directPanelTokens) : "";
    String alarmCtx = needAlarmSummary ? getRecentAlarmContext() : "";
    StringBuilder dbSb = new StringBuilder();
    if (meterCtx != null && !meterCtx.trim().isEmpty()) dbSb.append("Meter: ").append(meterCtx);
    if (alarmCtx != null && !alarmCtx.trim().isEmpty()) {
        if (dbSb.length() > 0) dbSb.append("\n");
        dbSb.append("Alarm: ").append(alarmCtx);
    }
    directDbContext = dbSb.toString();

    if (directDbContext == null || directDbContext.trim().isEmpty()) {
        directAnswer = "요청한 조회 결과를 찾지 못했습니다.";
    } else if (directDbContext.contains("unavailable")) {
        directAnswer = "현재 계측/알람 조회를 수행할 수 없습니다.";
    } else if (needMeterSummary && !needAlarmSummary) {
        if (directDbContext.contains("no data")) {
            directAnswer = "요청한 계측 데이터가 없습니다.";
        } else {
            String userCtx = buildUserDbContext(directDbContext);
            directAnswer = (userCtx == null || userCtx.trim().isEmpty())
                ? "최근 계측값을 조회했습니다."
                : userCtx;
        }
    } else if (!needMeterSummary && needAlarmSummary) {
        directAnswer = directDbContext.contains("no recent alarm")
            ? "최근 알람이 없습니다."
            : "최근 알람을 조회했습니다.";
    } else {
        directAnswer = "최근 계측값과 알람을 조회했습니다.";
    }
}

if (directAnswer != null && directDbContext != null) {
    int meterCount = countDistinctMeterIds(directDbContext);
    boolean skipMeterCountSuffix = directDbContext.startsWith("[Alarm count]") || directDbContext.startsWith("[Panel latest status]");
    if (!skipMeterCountSuffix && meterCount > 0 && (directAnswer == null || directAnswer.indexOf('\n') < 0)) {
        directAnswer = directAnswer + " (해당 계측기 " + meterCount + "개)";
    }
    writeSuccessJson(out, response, directAnswer, directDbContext, isAdmin);
    return;
}

if (forceRuleOnly) {
    writeSuccessJson(
        out,
        response,
        "RULE 모드: 직접 규칙에 매칭된 결과가 없습니다. 같은 질문을 /llm 으로 시도해 주세요.",
        "[Rule mode] no direct match",
        isAdmin
    );
    return;
}

String ollamaUrl = System.getenv("OLLAMA_URL");
if (ollamaUrl == null || ollamaUrl.isEmpty()) {
    ollamaUrl = "http://localhost:11434";
}
ollamaUrl = normalizeOllamaUrl(ollamaUrl);

String model = System.getenv("OLLAMA_MODEL");
if (model == null || model.isEmpty()) {
    model = "qwen2.5:14b";
}
String coderModel = System.getenv("OLLAMA_MODEL_CODER");
if (coderModel == null || coderModel.isEmpty()) {
    coderModel = "qwen2.5-coder:7b";
}
Properties modelConfig = loadAgentModelConfig(application);
String configuredOllamaUrl = normalizeOllamaUrl(modelConfig.getProperty("ollama_url"));
if (configuredOllamaUrl != null) ollamaUrl = configuredOllamaUrl;
String configuredModel = trimToNull(modelConfig.getProperty("model"));
String configuredCoderModel = trimToNull(modelConfig.getProperty("coder_model"));
if (configuredModel != null) model = configuredModel;
if (configuredCoderModel != null) coderModel = configuredCoderModel;

int ollamaConnectTimeoutMs = 5000;
int ollamaReadTimeoutMs = 60000;
Integer connectSec = parsePositiveInt(trimToNull(modelConfig.getProperty("ollama_connect_timeout_seconds")));
Integer readSec = parsePositiveInt(trimToNull(modelConfig.getProperty("ollama_read_timeout_seconds")));
if (connectSec != null) {
    int s = connectSec.intValue();
    if (s < 1) s = 1;
    if (s > 60) s = 60;
    ollamaConnectTimeoutMs = s * 1000;
}
if (readSec != null) {
    int s = readSec.intValue();
    if (s < 3) s = 3;
    if (s > 600) s = 600;
    ollamaReadTimeoutMs = s * 1000;
}
String ttlMinutesRaw = trimToNull(modelConfig.getProperty("schema_cache_ttl_minutes"));
long prevTtlMs = schemaCacheTtlMs;
long nextTtlMs = DEFAULT_SCHEMA_CACHE_TTL_MS;
Integer ttlMin = parsePositiveInt(ttlMinutesRaw);
if (ttlMin != null) {
    int m = ttlMin.intValue();
    if (m < 1) m = 1;
    if (m > 1440) m = 1440;
    nextTtlMs = m * 60L * 1000L;
}
schemaCacheTtlMs = nextTtlMs;
if (prevTtlMs != nextTtlMs) {
    schemaContextCacheAt = 0L;
}

try {
    String listStr = "";
    try {
        URL listUrl = new URL(ollamaUrl + "/api/tags");
        HttpURLConnection listConn = (HttpURLConnection) listUrl.openConnection();
        listConn.setRequestMethod("GET");
        listConn.setConnectTimeout(ollamaConnectTimeoutMs);
        listConn.setReadTimeout(ollamaReadTimeoutMs);
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
    if (requestedMeterId == null) {
        requestedMeterId = resolveMeterIdByName(extractMeterNameToken(userMessage));
    }
    String requestedMeterScope = extractMeterScopeToken(userMessage);
    if (requestedMeterScope == null || requestedMeterScope.trim().isEmpty()) {
        requestedMeterScope = extractAlarmAreaToken(userMessage);
    }
    if (requestedMeterScope == null || requestedMeterScope.trim().isEmpty()) {
        List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
        if (scopeHints != null && !scopeHints.isEmpty()) {
            requestedMeterScope = String.join(",", scopeHints);
        }
    }
    Integer requestedMonth = extractMonth(userMessage);
    boolean needsPerMeterPower = wantsPerMeterPowerSummary(userMessage);
    boolean needsMeterList = wantsMeterListSummary(userMessage);
    boolean needsPhaseCurrent = wantsPhaseCurrentValue(userMessage);
    boolean needsPhaseVoltage = wantsPhaseVoltageValue(userMessage);
    boolean needsLineVoltage = wantsLineVoltageValue(userMessage);
    boolean needsHarmonic = wantsHarmonicSummary(userMessage);
    List<String> panelTokens = needsPerMeterPower ? new ArrayList<String>() : extractPanelTokens(userMessage);
    String schemaContext = getSchemaContextCached();

    // Stage 1: qwen2.5:14b classifies whether DB lookup is required.
    String classifierPrompt =
        "Classify if EPMS DB lookup is needed. " +
        "Return only one JSON object with keys: needs_db(boolean), needs_meter(boolean), needs_alarm(boolean), needs_frequency(boolean), needs_power_by_meter(boolean), needs_meter_list(boolean), needs_phase_current(boolean), needs_phase_voltage(boolean), needs_line_voltage(boolean), needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null), meter_scope(string|null), phase(string|null), line_pair(string|null). " +
        "No markdown. No explanation.\n\nUser: " + userMessage;
    String classifierRaw = callOllamaOnce(ollamaUrl, model, classifierPrompt, ollamaConnectTimeoutMs, ollamaReadTimeoutMs, 0.1d);

    boolean needsMeter = wantsMeterSummary(userMessage);
    boolean needsAlarm = wantsAlarmSummary(userMessage);
    boolean needsFrequency = wantsMonthlyFrequencySummary(userMessage);
    boolean forceCoderFlow = coderModel.equals(routeModel(userMessage, model, coderModel));
    boolean needsDb = needsMeter || needsAlarm || needsFrequency || needsPerMeterPower || needsMeterList || needsPhaseCurrent || needsPhaseVoltage || needsLineVoltage || needsHarmonic;
    Boolean cNeedsDb = extractJsonBoolField(classifierRaw, "needs_db");
    Boolean cNeedsMeter = extractJsonBoolField(classifierRaw, "needs_meter");
    Boolean cNeedsAlarm = extractJsonBoolField(classifierRaw, "needs_alarm");
    Boolean cNeedsFrequency = extractJsonBoolField(classifierRaw, "needs_frequency");
    Boolean cNeedsPower = extractJsonBoolField(classifierRaw, "needs_power_by_meter");
    Boolean cNeedsMeterList = extractJsonBoolField(classifierRaw, "needs_meter_list");
    Boolean cNeedsPhaseCurrent = extractJsonBoolField(classifierRaw, "needs_phase_current");
    Boolean cNeedsPhaseVoltage = extractJsonBoolField(classifierRaw, "needs_phase_voltage");
    Boolean cNeedsLineVoltage = extractJsonBoolField(classifierRaw, "needs_line_voltage");
    Boolean cNeedsHarmonic = extractJsonBoolField(classifierRaw, "needs_harmonic");
    Integer cMeterId = extractJsonIntField(classifierRaw, "meter_id");
    Integer cMonth = extractJsonIntField(classifierRaw, "month");
    String cPanel = extractJsonStringField(classifierRaw, "panel");
    String cMeterScope = extractJsonStringField(classifierRaw, "meter_scope");
    String cPhase = extractJsonStringField(classifierRaw, "phase");
    String cLinePair = extractJsonStringField(classifierRaw, "line_pair");
    if (cNeedsDb != null) needsDb = needsDb || cNeedsDb.booleanValue();
    needsDb = needsDb || forceCoderFlow;
    if (cNeedsMeter != null) needsMeter = needsMeter || cNeedsMeter.booleanValue();
    if (cNeedsAlarm != null) needsAlarm = needsAlarm || cNeedsAlarm.booleanValue();
    if (cNeedsFrequency != null) needsFrequency = needsFrequency || cNeedsFrequency.booleanValue();
    if (cNeedsPower != null) needsPerMeterPower = needsPerMeterPower || cNeedsPower.booleanValue();
    if (cNeedsMeterList != null) needsMeterList = needsMeterList || cNeedsMeterList.booleanValue();
    if (cNeedsPhaseCurrent != null) needsPhaseCurrent = needsPhaseCurrent || cNeedsPhaseCurrent.booleanValue();
    if (cNeedsPhaseVoltage != null) needsPhaseVoltage = needsPhaseVoltage || cNeedsPhaseVoltage.booleanValue();
    if (cNeedsLineVoltage != null) needsLineVoltage = needsLineVoltage || cNeedsLineVoltage.booleanValue();
    if (cNeedsHarmonic != null) needsHarmonic = needsHarmonic || cNeedsHarmonic.booleanValue();
    if (needsMeterList && !wantsPerMeterPowerSummary(userMessage)) needsPerMeterPower = false;
    if (needsHarmonic && !wantsMonthlyFrequencySummary(userMessage)) needsFrequency = false;
    if (cMeterId != null) requestedMeterId = cMeterId;
    if (cMonth != null && cMonth.intValue() >= 1 && cMonth.intValue() <= 12) requestedMonth = cMonth;
    if ((panelTokens == null || panelTokens.isEmpty()) && cPanel != null && !cPanel.trim().isEmpty()) {
        panelTokens = panelTokensFromRaw(cPanel);
    }
    if ((requestedMeterScope == null || requestedMeterScope.trim().isEmpty()) && cMeterScope != null && !cMeterScope.trim().isEmpty()) {
        requestedMeterScope = cMeterScope;
    }
    String requestedPhase = extractPhaseLabel(userMessage);
    if ((requestedPhase == null || requestedPhase.trim().isEmpty()) && cPhase != null && !cPhase.trim().isEmpty()) {
        requestedPhase = cPhase;
    }
    String requestedLinePair = extractLinePairLabel(userMessage);
    if ((requestedLinePair == null || requestedLinePair.trim().isEmpty()) && cLinePair != null && !cLinePair.trim().isEmpty()) {
        requestedLinePair = cLinePair;
    }
    if (requestedMeterScope == null || requestedMeterScope.trim().isEmpty()) {
        List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
        if (scopeHints != null && !scopeHints.isEmpty()) {
            requestedMeterScope = String.join(",", scopeHints);
        }
    }

    String meterCtx = "";
    String alarmCtx = "";
    String frequencyCtx = "";
    String powerCtx = "";
    String meterListCtx = "";
    String phaseCurrentCtx = "";
    String phaseVoltageCtx = "";
    String lineVoltageCtx = "";
    String harmonicCtx = "";
    String dbContext = "";
    String coderDraft = "";

    // Stage 2: qwen2.5-coder:7b interprets DB task (bounded task schema).
    if (needsDb) {
        String coderPrompt =
            "You are DB task planner. Return only one JSON object with keys: " +
            "task(\"meter\"|\"alarm\"|\"both\"|\"none\"), needs_frequency(boolean), needs_power_by_meter(boolean), needs_meter_list(boolean), needs_phase_current(boolean), needs_phase_voltage(boolean), needs_line_voltage(boolean), needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null), meter_scope(string|null), phase(string|null), line_pair(string|null). " +
            "No markdown. No explanation.\n\n" +
            "User: " + userMessage + "\n" +
            "Classifier JSON: " + classifierRaw + "\n\n" +
            "Schema Context:\n" + schemaContext;
        String coderRaw = callOllamaOnce(ollamaUrl, coderModel, coderPrompt, ollamaConnectTimeoutMs, ollamaReadTimeoutMs, 0.1d);

        String task = extractJsonStringField(coderRaw, "task");
        Boolean planNeedsFrequency = extractJsonBoolField(coderRaw, "needs_frequency");
        Boolean planNeedsPower = extractJsonBoolField(coderRaw, "needs_power_by_meter");
        Boolean planNeedsMeterList = extractJsonBoolField(coderRaw, "needs_meter_list");
        Boolean planNeedsPhaseCurrent = extractJsonBoolField(coderRaw, "needs_phase_current");
        Boolean planNeedsPhaseVoltage = extractJsonBoolField(coderRaw, "needs_phase_voltage");
        Boolean planNeedsLineVoltage = extractJsonBoolField(coderRaw, "needs_line_voltage");
        Boolean planNeedsHarmonic = extractJsonBoolField(coderRaw, "needs_harmonic");
        Integer planMeterId = extractJsonIntField(coderRaw, "meter_id");
        Integer planMonth = extractJsonIntField(coderRaw, "month");
        String planPanel = extractJsonStringField(coderRaw, "panel");
        String planMeterScope = extractJsonStringField(coderRaw, "meter_scope");
        String planPhase = extractJsonStringField(coderRaw, "phase");
        String planLinePair = extractJsonStringField(coderRaw, "line_pair");
        boolean runMeter = needsMeter;
        boolean runAlarm = needsAlarm;
        boolean runFrequency = needsFrequency;
        boolean runPower = needsPerMeterPower;
        boolean runMeterList = needsMeterList;
        boolean runPhaseCurrent = needsPhaseCurrent;
        boolean runPhaseVoltage = needsPhaseVoltage;
        boolean runLineVoltage = needsLineVoltage;
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
        if (planNeedsMeterList != null) runMeterList = runMeterList || planNeedsMeterList.booleanValue();
        if (planNeedsPhaseCurrent != null) runPhaseCurrent = runPhaseCurrent || planNeedsPhaseCurrent.booleanValue();
        if (planNeedsPhaseVoltage != null) runPhaseVoltage = runPhaseVoltage || planNeedsPhaseVoltage.booleanValue();
        if (planNeedsLineVoltage != null) runLineVoltage = runLineVoltage || planNeedsLineVoltage.booleanValue();
        if (planNeedsHarmonic != null) runHarmonic = runHarmonic || planNeedsHarmonic.booleanValue();
        if (runMeterList && !wantsPerMeterPowerSummary(userMessage)) runPower = false;
        if (needsHarmonic && !wantsMonthlyFrequencySummary(userMessage)) runFrequency = false;
        if ((panelTokens == null || panelTokens.isEmpty()) && planPanel != null && !planPanel.trim().isEmpty()) {
            panelTokens = panelTokensFromRaw(planPanel);
        }
        if ((requestedMeterScope == null || requestedMeterScope.trim().isEmpty()) && planMeterScope != null && !planMeterScope.trim().isEmpty()) {
            requestedMeterScope = planMeterScope;
        }
        if ((requestedPhase == null || requestedPhase.trim().isEmpty()) && planPhase != null && !planPhase.trim().isEmpty()) {
            requestedPhase = planPhase;
        }
        if ((requestedLinePair == null || requestedLinePair.trim().isEmpty()) && planLinePair != null && !planLinePair.trim().isEmpty()) {
            requestedLinePair = planLinePair;
        }
        if (requestedMeterScope == null || requestedMeterScope.trim().isEmpty()) {
            List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
            if (scopeHints != null && !scopeHints.isEmpty()) {
                requestedMeterScope = String.join(",", scopeHints);
            }
        }

        if (runMeter) meterCtx = getRecentMeterContext(requestedMeterId, panelTokens);
        if (runAlarm) alarmCtx = getRecentAlarmContext();
        if (runFrequency) frequencyCtx = getMonthlyAvgFrequencyContext(requestedMeterId, requestedMonth);
        if (runPower) powerCtx = getPerMeterPowerContext();
        if (runMeterList) meterListCtx = getMeterListContext(requestedMeterScope, directTopN);
        if (runPhaseCurrent) phaseCurrentCtx = getPhaseCurrentContext(requestedMeterId, requestedPhase);
        if (runPhaseVoltage) phaseVoltageCtx = getPhaseVoltageContext(requestedMeterId, requestedPhase);
        if (runLineVoltage) lineVoltageCtx = getLineVoltageContext(requestedMeterId, requestedLinePair);
        if (runHarmonic) harmonicCtx = getHarmonicContext(requestedMeterId, panelTokens);
        if (!runMeter && !runAlarm && !runFrequency && !runPower && !runMeterList && !runPhaseCurrent && !runPhaseVoltage && !runLineVoltage && !runHarmonic && forceCoderFlow) {
            String coderAnswerPrompt =
                "Answer the user's DB/SQL request directly. " +
                "Use SQL Server syntax if SQL is requested. " +
                "Return concise plain text, no markdown fences.\n\n" +
                "User: " + userMessage + "\n\n" +
                "Schema Context:\n" + schemaContext;
            coderDraft = callOllamaOnce(ollamaUrl, coderModel, coderAnswerPrompt, ollamaConnectTimeoutMs, ollamaReadTimeoutMs, 0.2d);
        } else if (!runMeter && !runAlarm && !runFrequency && !runPower && !runMeterList && !runPhaseCurrent && !runPhaseVoltage && !runLineVoltage && !runHarmonic) {
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
        if (meterListCtx != null && !meterListCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("MeterList: ").append(meterListCtx);
        }
        if (phaseCurrentCtx != null && !phaseCurrentCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("PhaseCurrent: ").append(phaseCurrentCtx);
        }
        if (phaseVoltageCtx != null && !phaseVoltageCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("PhaseVoltage: ").append(phaseVoltageCtx);
        }
        if (lineVoltageCtx != null && !lineVoltageCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("LineVoltage: ").append(lineVoltageCtx);
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
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
        return;
    }
    if (needsFrequency && frequencyCtx != null && !frequencyCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildFrequencyDirectAnswer(frequencyCtx, requestedMeterId, requestedMonth);
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
        return;
    }
    if (needsPerMeterPower && powerCtx != null && !powerCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildPerMeterPowerDirectAnswer(powerCtx);
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
        return;
    }
    if (needsMeterList && meterListCtx != null && !meterListCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildUserDbContext(meterListCtx);
        if (finalAnswer == null || finalAnswer.trim().isEmpty()) finalAnswer = "계측기 목록을 조회했습니다.";
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
        return;
    }
    if (needsPhaseCurrent && phaseCurrentCtx != null && !phaseCurrentCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildUserDbContext(phaseCurrentCtx);
        if (finalAnswer == null || finalAnswer.trim().isEmpty()) finalAnswer = "상전류를 조회했습니다.";
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
        return;
    }
    if (needsPhaseVoltage && phaseVoltageCtx != null && !phaseVoltageCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildUserDbContext(phaseVoltageCtx);
        if (finalAnswer == null || finalAnswer.trim().isEmpty()) finalAnswer = "상전압을 조회했습니다.";
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
        return;
    }
    if (needsLineVoltage && lineVoltageCtx != null && !lineVoltageCtx.trim().isEmpty() && !forceCoderFlow) {
        String finalAnswer = buildUserDbContext(lineVoltageCtx);
        if (finalAnswer == null || finalAnswer.trim().isEmpty()) finalAnswer = "선간전압을 조회했습니다.";
        writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);
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
    String finalAnswer = callOllamaOnce(ollamaUrl, model, finalPrompt, ollamaConnectTimeoutMs, ollamaReadTimeoutMs, 0.4d);
    finalAnswer = sanitizeUngroundedJudgement(finalAnswer, dbContext);
    writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);

} catch (Exception e) {
    response.setStatus(500);
    out.print("{\"error\":\"" + e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "Unknown") + "\"}");
}
%>
