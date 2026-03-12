<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.util.concurrent.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%!
    private static final ConcurrentHashMap<String, Integer> LAST_DI_VALUE_MAP = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> AI_PENDING_ON_MS = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> DI_PENDING_ON_MS = new ConcurrentHashMap<>();

    private static class AlarmRule {
        int ruleId;
        String ruleCode;
        String targetScope;
        String metricKey;
        String sourceToken;
        String messageTemplate;
        String operator;
        Double threshold1;
        Double threshold2;
        int durationSec;
        Double hysteresis;
        String severity;
    }

    private static class AiRow {
        int meterId;
        String token;
        double value;
    }

    private static class DiRequestPayload {
        int plcId;
        Timestamp measuredAt;
        List<Map<String, Object>> rows = Collections.emptyList();
    }

    private static class DiGroupMapRule {
        String groupKey;
        String metricKey;
        String matchType;
        String matchValue;
        int priority;
    }

    private static class DiGroupRule {
        String metricKey;
        String matchMode;
        Integer countThreshold;
    }

    private static class DiGroupState {
        int pointId;
        String metricKey;
        int bitCount;
        int onCount;
        String itemName;
        String panelName;
        List<String> samples = new ArrayList<>();
    }

    private static class AiRequestPayload {
        int plcId;
        Timestamp measuredAt;
        List<AiRow> rows = Collections.emptyList();
    }

    private static class OpenCloseCount {
        int opened;
        int closed;
    }

    private static Connection createConn() throws Exception {
        return openDbConnection();
    }

    private static void ensureAlarmSchema(Connection conn) {
        if (conn == null) return;
        String sql =
            "IF COL_LENGTH('dbo.alarm_log','rule_id') IS NULL ALTER TABLE dbo.alarm_log ADD rule_id INT NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','rule_code') IS NULL ALTER TABLE dbo.alarm_log ADD rule_code VARCHAR(50) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','metric_key') IS NULL ALTER TABLE dbo.alarm_log ADD metric_key VARCHAR(100) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','source_token') IS NULL ALTER TABLE dbo.alarm_log ADD source_token VARCHAR(120) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','measured_value') IS NULL ALTER TABLE dbo.alarm_log ADD measured_value FLOAT NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','operator') IS NULL ALTER TABLE dbo.alarm_log ADD operator VARCHAR(10) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','threshold1') IS NULL ALTER TABLE dbo.alarm_log ADD threshold1 FLOAT NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','threshold2') IS NULL ALTER TABLE dbo.alarm_log ADD threshold2 FLOAT NULL;";
        try (Statement st = conn.createStatement()) {
            st.execute(sql);
        } catch (Exception ignore) {
        }
    }

    private static boolean isOcrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("OCGR") || t.contains("51G")) return false;
        if (t.contains("OCR")) return true;
        if (t.contains("\\50") || t.contains("\u20A950")) return true;
        if (t.contains("\\51") || t.contains("\u20A951")) return true;
        return false;
    }

    private static boolean isOcgrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("OCGR")) return true;
        if (t.contains("51G")) return true;
        return false;
    }

    private static boolean isOvrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("OCR") || t.contains("OCGR") || t.contains("51G")) return false;
        if (t.contains("OVR")) return true;
        if (t.contains("\\59") || t.contains("\u20A959")) return true;
        return false;
    }

    private static boolean isTripAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("TR_ALARM")) return true;
        if (t.contains("TRALARM")) return true;
        if (t.contains("TRIP")) return true;
        return false;
    }

    private static boolean isEldAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        return t.contains("ELD");
    }

    private static boolean isTmAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        return t.contains("\\TM") || t.contains("_TM") || t.endsWith("TM") || t.contains("TEMP");
    }

    private static boolean isLightAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        return t.contains("WLIGHT") || t.contains("LIGHT");
    }

    private static String normalizeMatchText(String s) {
        if (s == null) return "";
        return s.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "").trim();
    }

    private static String b64urlDecode(String s) {
        if (s == null || s.isEmpty()) return "";
        try {
            int mod = s.length() % 4;
            if (mod == 2) s = s + "==";
            else if (mod == 3) s = s + "=";
            else if (mod == 1) return "";
            byte[] bytes = Base64.getUrlDecoder().decode(s);
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    private static List<Map<String, Object>> parseRows(String raw) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (raw == null || raw.trim().isEmpty()) return out;
        String[] rows = raw.split(";");
        for (String line : rows) {
            if (line == null || line.trim().isEmpty()) continue;
            String[] p = line.split("\\|", -1);
            if (p.length < 7) continue;
            Map<String, Object> r = new HashMap<>();
            r.put("point_id", parseIntSafe(p[0], 0));
            r.put("di_address", parseIntSafe(p[1], 0));
            r.put("bit_no", parseIntSafe(p[2], 0));
            r.put("value", parseIntSafe(p[3], 0));
            r.put("tag_name", b64urlDecode(p[4]));
            r.put("item_name", b64urlDecode(p[5]));
            r.put("panel_name", b64urlDecode(p[6]));
            out.add(r);
        }
        return out;
    }

    private static List<AiRow> parseAiRows(String raw) {
        List<AiRow> out = new ArrayList<>();
        if (raw == null || raw.trim().isEmpty()) return out;
        String[] rows = raw.split(";");
        for (String line : rows) {
            if (line == null || line.trim().isEmpty()) continue;
            String[] p = line.split("\\|", -1);
            if (p.length < 3) continue;
            AiRow r = new AiRow();
            r.meterId = parseIntSafe(p[0], 0);
            r.token = b64urlDecode(p[1]);
            Double v = parseDoubleSafe(p[2]);
            if (r.meterId <= 0 || r.token == null || r.token.trim().isEmpty() || v == null) continue;
            r.value = v.doubleValue();
            out.add(r);
        }
        return out;
    }

    private static Long findOpenEventId(PreparedStatement ps, int deviceId, String eventType) throws Exception {
        ps.setInt(1, deviceId);
        ps.setString(2, eventType);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return rs.getLong(1);
        }
        return null;
    }

    private static Long findOpenAlarmId(PreparedStatement ps, int meterId, String alarmType) throws Exception {
        ps.setInt(1, meterId);
        ps.setString(2, alarmType);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return rs.getLong(1);
        }
        return null;
    }

    private static int closeOpenEvent(PreparedStatement close, Timestamp measuredAt, Long eventId) throws Exception {
        if (eventId == null) return 0;
        close.setTimestamp(1, measuredAt);
        close.setTimestamp(2, measuredAt);
        close.setTimestamp(3, measuredAt);
        close.setLong(4, eventId.longValue());
        return close.executeUpdate();
    }

    private static void clearOpenAlarm(PreparedStatement clearAlarm, Timestamp measuredAt, Long alarmId) throws Exception {
        if (alarmId == null) return;
        clearAlarm.setTimestamp(1, measuredAt);
        clearAlarm.setLong(2, alarmId.longValue());
        clearAlarm.executeUpdate();
    }

    private static int insertDeviceEvent(PreparedStatement ins, int deviceId, String eventType, Timestamp measuredAt, String severity, String description) throws Exception {
        ins.setInt(1, deviceId);
        ins.setString(2, eventType);
        ins.setTimestamp(3, measuredAt);
        ins.setString(4, severity);
        ins.setString(5, description);
        return ins.executeUpdate();
    }

    private static void insertDiAlarm(PreparedStatement insAlarm, int deviceId, String eventType, String severity, Timestamp measuredAt, String description) throws Exception {
        insAlarm.setInt(1, deviceId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        insAlarm.setNull(6, Types.INTEGER);
        insAlarm.setNull(7, Types.VARCHAR);
        insAlarm.setNull(8, Types.VARCHAR);
        insAlarm.setNull(9, Types.VARCHAR);
        insAlarm.setNull(10, Types.FLOAT);
        insAlarm.setNull(11, Types.VARCHAR);
        insAlarm.setNull(12, Types.FLOAT);
        insAlarm.setNull(13, Types.FLOAT);
        insAlarm.executeUpdate();
    }

    private static void insertAiAlarm(PreparedStatement insAlarm, int meterId, String eventType, String severity, Timestamp measuredAt, String description, AlarmRule rule, double value) throws Exception {
        insAlarm.setInt(1, meterId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        insAlarm.setInt(6, rule.ruleId);
        insAlarm.setString(7, rule.ruleCode);
        insAlarm.setString(8, rule.metricKey);
        insAlarm.setString(9, (rule.sourceToken == null || rule.sourceToken.trim().isEmpty()) ? rule.metricKey : rule.sourceToken);
        insAlarm.setDouble(10, value);
        insAlarm.setString(11, rule.operator);
        if (rule.threshold1 == null) insAlarm.setNull(12, Types.FLOAT); else insAlarm.setDouble(12, rule.threshold1.doubleValue());
        if (rule.threshold2 == null) insAlarm.setNull(13, Types.FLOAT); else insAlarm.setDouble(13, rule.threshold2.doubleValue());
        insAlarm.executeUpdate();
    }


    private static int closeStaleAiStages(
            PreparedStatement selOpenAnyRule,
            PreparedStatement close,
            PreparedStatement selAlarmOpen,
            PreparedStatement clearAlarm,
            int meterId,
            String rulePrefix,
            String targetEventType,
            Timestamp measuredAt) throws Exception {
        int closed = 0;
        selOpenAnyRule.setInt(1, meterId);
        selOpenAnyRule.setString(2, rulePrefix + "%");
        List<Long> closeIds = new ArrayList<>();
        List<String> closeTypes = new ArrayList<>();
        try (ResultSet rs = selOpenAnyRule.executeQuery()) {
            while (rs.next()) {
                long eid = rs.getLong("event_id");
                String et = rs.getString("event_type");
                if (targetEventType == null || et == null || !targetEventType.equals(et)) {
                    closeIds.add(Long.valueOf(eid));
                    closeTypes.add(et);
                }
            }
        }
        for (Long eid : closeIds) {
            closed += closeOpenEvent(close, measuredAt, eid);
        }
        for (String et : closeTypes) {
            if (et == null || et.trim().isEmpty()) continue;
            clearOpenAlarm(clearAlarm, measuredAt, findOpenAlarmId(selAlarmOpen, meterId, et));
        }
        return closed;
    }

    private static boolean evalOpen(String operator, Double t1, Double t2, double value) {
        String op = operator == null ? ">=" : operator.trim().toUpperCase(Locale.ROOT);
        if ("BETWEEN".equals(op)) {
            if (t1 == null || t2 == null) return false;
            double lo = Math.min(t1.doubleValue(), t2.doubleValue());
            double hi = Math.max(t1.doubleValue(), t2.doubleValue());
            return value >= lo && value <= hi;
        }
        if (t1 == null) return false;
        double x = t1.doubleValue();
        if (">=".equals(op)) return value >= x;
        if (">".equals(op)) return value > x;
        if ("<=".equals(op)) return value <= x;
        if ("<".equals(op)) return value < x;
        if ("=".equals(op)) return value == x;
        if ("!=".equals(op) || "<>".equals(op)) return value != x;
        return false;
    }

    private static boolean shouldCloseOpenEvent(AlarmRule r, double value) {
        double h = (r.hysteresis == null) ? 0.0d : Math.abs(r.hysteresis.doubleValue());
        if (h <= 0.0d) return !evalOpen(r.operator, r.threshold1, r.threshold2, value);

        String op = r.operator == null ? ">=" : r.operator.trim().toUpperCase(Locale.ROOT);
        if ("BETWEEN".equals(op)) {
            if (r.threshold1 == null || r.threshold2 == null) return true;
            double lo = Math.min(r.threshold1.doubleValue(), r.threshold2.doubleValue());
            double hi = Math.max(r.threshold1.doubleValue(), r.threshold2.doubleValue());
            return value < (lo - h) || value > (hi + h);
        }
        if (r.threshold1 == null) return true;
        double x = r.threshold1.doubleValue();

        if (">=".equals(op) || ">".equals(op)) return value < (x - h);
        if ("<=".equals(op) || "<".equals(op)) return value > (x + h);
        if ("=".equals(op)) return Math.abs(value - x) > h;
        if ("!=".equals(op) || "<>".equals(op)) return Math.abs(value - x) <= h;
        return !evalOpen(op, r.threshold1, r.threshold2, value);
    }

    private static Double maxAbs(Collection<Double> values) {
        if (values == null || values.isEmpty()) return null;
        Double out = null;
        for (Double v : values) {
            if (v == null) continue;
            double a = Math.abs(v.doubleValue());
            if (out == null || a > out.doubleValue()) out = Double.valueOf(a);
        }
        return out;
    }

    private static boolean looksLikeVoltageKey(String k) {
        if (k == null) return false;
        if (k.startsWith("V1N") || k.startsWith("V2N") || k.startsWith("V3N")) return true;
        if (k.startsWith("V12") || k.startsWith("V23") || k.startsWith("V31")) return true;
        if (k.startsWith("VVA") || k.equals("VA")) return true;
        if (k.startsWith("VOLTAGE_") || k.contains("PHASE_VOLTAGE") || k.contains("LINE_VOLTAGE")) return true;
        return false;
    }

    private static boolean looksLikeCurrentKey(String k) {
        if (k == null) return false;
        if (k.equals("A1") || k.equals("A2") || k.equals("A3") || k.equals("AA") || k.equals("AN")) return true;
        if (k.startsWith("CURRENT_") || k.contains("AVERAGE_CURRENT")) return true;
        return false;
    }

    private static boolean looksLikeThdKey(String k) {
        if (k == null) return false;
        if (k.contains("THD")) return true;
        // Existing mapping often uses H_*_1 for THD of each phase.
        if (k.matches("^H_[VI][A-Z0-9_]*_1$")) return true;
        return false;
    }

    private static boolean looksLikeVoltageThdKey(String k) {
        if (k == null) return false;
        if (k.contains("THD_V") || k.contains("THD_VOLTAGE")) return true;
        if (k.matches("^H_V[A-Z0-9_]*_1$")) return true;
        return false;
    }

    private static boolean looksLikeCurrentThdKey(String k) {
        if (k == null) return false;
        if (k.contains("THD_I") || k.contains("THD_CURRENT")) return true;
        if (k.matches("^H_I[A-Z0-9_]*_1$")) return true;
        return false;
    }

    private static boolean looksLikeVoltageVariationKey(String k) {
        if (k == null) return false;
        return k.contains("VOLTAGE_VARIATION") || k.startsWith("V_VAR");
    }

    private static boolean looksLikeCurrentVariationKey(String k) {
        if (k == null) return false;
        return k.contains("CURRENT_VARIATION") || k.startsWith("I_VAR");
    }

    private static void enrichGroupedMetrics(Map<String, Double> metricValues) {
        if (metricValues == null || metricValues.isEmpty()) return;

        List<Double> voltage = new ArrayList<>();
        List<Double> current = new ArrayList<>();
        List<Double> thd = new ArrayList<>();
        List<Double> thdVoltage = new ArrayList<>();
        List<Double> thdCurrent = new ArrayList<>();
        List<Double> unbalance = new ArrayList<>();
        List<Double> voltageVariation = new ArrayList<>();
        List<Double> currentVariation = new ArrayList<>();
        List<Double> variation = new ArrayList<>();

        Double pf = null;
        Double hz = null;
        Double peak = null;

        for (Map.Entry<String, Double> e : metricValues.entrySet()) {
            String k = e.getKey();
            Double v = e.getValue();
            if (k == null || v == null) continue;

            if (looksLikeVoltageKey(k)) voltage.add(v);
            if (looksLikeCurrentKey(k)) current.add(v);
            if (looksLikeThdKey(k)) thd.add(v);
            if (looksLikeVoltageThdKey(k)) thdVoltage.add(v);
            if (looksLikeCurrentThdKey(k)) thdCurrent.add(v);

            if (k.contains("UNBALANCE")) unbalance.add(v);
            if (looksLikeVoltageVariationKey(k)) voltageVariation.add(v);
            if (looksLikeCurrentVariationKey(k)) currentVariation.add(v);
            if (k.contains("VARIATION") || k.endsWith("_VAR")) variation.add(v);

            if ("PF".equals(k) || "POWER_FACTOR".equals(k) || "PF_TOTAL".equals(k)) pf = v;
            if ("HZ".equals(k) || "FREQUENCY".equals(k)) hz = v;
            if ("PEAK".equals(k) || "MAX_POWER".equals(k)) peak = v;
        }

        Double vMax = maxAbs(voltage);
        Double iMax = maxAbs(current);
        Double thdMax = maxAbs(thd);
        Double thdVoltageMax = maxAbs(thdVoltage);
        Double thdCurrentMax = maxAbs(thdCurrent);
        Double unbMax = maxAbs(unbalance);
        Double vVarMax = maxAbs(voltageVariation);
        Double iVarMax = maxAbs(currentVariation);
        Double varMax = maxAbs(variation);

        if (vMax != null) {
            metricValues.put("VOLTAGE", vMax);
            metricValues.put("VOLTAGE_MAX", vMax);
        }
        if (iMax != null) {
            metricValues.put("CURRENT", iMax);
            metricValues.put("CURRENT_MAX", iMax);
        }
        if (thdMax != null) {
            metricValues.put("THD", thdMax);
            metricValues.put("THD_MAX", thdMax);
            metricValues.put("HARMONIC_THD", thdMax);
        }
        if (thdVoltageMax != null) {
            metricValues.put("THD_VOLTAGE", thdVoltageMax);
            metricValues.put("THD_VOLTAGE_MAX", thdVoltageMax);
        }
        if (thdCurrentMax != null) {
            metricValues.put("THD_CURRENT", thdCurrentMax);
            metricValues.put("THD_CURRENT_MAX", thdCurrentMax);
        }
        if (unbMax != null) {
            metricValues.put("UNBALANCE", unbMax);
            metricValues.put("UNBALANCE_MAX", unbMax);
        }
        if (vVarMax != null) {
            metricValues.put("V_VARIATION", vVarMax);
            metricValues.put("VOLTAGE_VARIATION", vVarMax);
        }
        if (iVarMax != null) {
            metricValues.put("I_VARIATION", iVarMax);
            metricValues.put("CURRENT_VARIATION", iVarMax);
        }
        if (varMax != null) {
            metricValues.put("VARIATION", varMax);
            metricValues.put("VARIATION_MAX", varMax);
        }
        if (pf != null) {
            metricValues.put("POWER_FACTOR", pf);
            metricValues.put("PF_GROUP", pf);
        }
        if (hz != null) {
            metricValues.put("FREQUENCY_GROUP", hz);
            metricValues.put("HZ_GROUP", hz);
        }
        if (peak != null) {
            metricValues.put("PEAK", peak);
            metricValues.put("MAX_POWER", peak);
            metricValues.put("PEAK_POWER", peak);
        }
    }

    private static String evalAiStage(AlarmRule r, double value) {
        if (r == null || r.threshold1 == null) return null;
        String op = r.operator == null ? ">=" : r.operator.trim().toUpperCase(Locale.ROOT);

        // Single-threshold mode: keep legacy behavior (one severity per rule).
        if (r.threshold2 == null) {
            boolean hit = evalOpen(op, r.threshold1, null, value);
            if (!hit) return null;
            String sev = (r.severity == null || r.severity.trim().isEmpty()) ? "WARN" : r.severity.trim().toUpperCase(Locale.ROOT);
            return sev;
        }

        // Two-threshold mode: one rule -> ALARM / CRITICAL 2-step alarm levels + normal.
        // For >=/>: threshold1=ALARM, threshold2=CRITICAL (threshold2 should be higher).
        // For <=/<: threshold1=ALARM, threshold2=CRITICAL (threshold2 should be lower).
        double t1 = r.threshold1.doubleValue();
        double t2 = r.threshold2.doubleValue();
        if (">=".equals(op) || ">".equals(op)) {
            if (value >= t2) return "CRITICAL";
            if (value >= t1) return "ALARM";
            return null;
        }
        if ("<=".equals(op) || "<".equals(op)) {
            if (value <= t2) return "CRITICAL";
            if (value <= t1) return "ALARM";
            return null;
        }

        // Unsupported operators (e.g. BETWEEN): fallback to single-stage behavior.
        boolean hit = evalOpen(op, r.threshold1, r.threshold2, value);
        if (!hit) return null;
        String sev = (r.severity == null || r.severity.trim().isEmpty()) ? "WARN" : r.severity.trim().toUpperCase(Locale.ROOT);
        return sev;
    }

    private static Map<String, String> loadAiTokenColumnAlias(Connection conn) {
        Map<String, String> map = new HashMap<>();
        String sql = "SELECT token, measurement_column FROM dbo.plc_ai_measurements_match";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String token = rs.getString("token");
                String col = rs.getString("measurement_column");
                if (token == null || col == null) continue;
                String t = token.trim().toUpperCase(Locale.ROOT);
                String c = col.trim().toUpperCase(Locale.ROOT);
                if (!t.isEmpty() && !c.isEmpty()) map.put(t, c);
            }
        } catch (Exception ignore) {
        }
        return map;
    }

    private static List<AlarmRule> loadEnabledAiRules(Connection conn) throws Exception {
        List<AlarmRule> out = new ArrayList<>();
        String sql =
            "IF OBJECT_ID('dbo.metric_catalog','U') IS NOT NULL " +
            "SELECT r.rule_id, r.rule_code, r.target_scope, r.metric_key, r.source_token, r.message_template, r.operator, r.threshold1, r.threshold2, r.duration_sec, r.hysteresis, r.severity " +
            "FROM dbo.alarm_rule r " +
            "JOIN dbo.metric_catalog mc ON mc.metric_key = r.metric_key " +
            "WHERE r.enabled = 1 " +
            "  AND UPPER(r.target_scope) IN ('METER','AI') " +
            "  AND mc.enabled = 1 " +
            "  AND UPPER(ISNULL(mc.source_type,'AI')) IN ('AI','SYSTEM') " +
            "ORDER BY r.rule_id " +
            "ELSE " +
            "SELECT rule_id, rule_code, target_scope, metric_key, source_token, message_template, operator, threshold1, threshold2, duration_sec, hysteresis, severity " +
            "FROM dbo.alarm_rule " +
            "WHERE enabled = 1 AND UPPER(target_scope) IN ('METER','AI') " +
            "ORDER BY rule_id";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                AlarmRule r = new AlarmRule();
                r.ruleId = rs.getInt("rule_id");
                r.ruleCode = rs.getString("rule_code");
                r.targetScope = rs.getString("target_scope");
                r.metricKey = rs.getString("metric_key");
                r.sourceToken = rs.getString("source_token");
                r.messageTemplate = rs.getString("message_template");
                r.operator = rs.getString("operator");
                Object t1 = rs.getObject("threshold1");
                Object t2 = rs.getObject("threshold2");
                Object hy = rs.getObject("hysteresis");
                r.threshold1 = (t1 instanceof Number) ? ((Number)t1).doubleValue() : null;
                r.threshold2 = (t2 instanceof Number) ? ((Number)t2).doubleValue() : null;
                r.durationSec = rs.getInt("duration_sec");
                r.hysteresis = (hy instanceof Number) ? ((Number)hy).doubleValue() : null;
                r.severity = rs.getString("severity");
                if (r.ruleCode == null || r.ruleCode.trim().isEmpty()) continue;
                if (r.metricKey == null || r.metricKey.trim().isEmpty()) continue;
                out.add(r);
            }
        }
        return out;
    }

    private static List<AlarmRule> loadEnabledDiRules(Connection conn) throws Exception {
        List<AlarmRule> out = new ArrayList<>();
        String sql =
            "SELECT rule_id, rule_code, target_scope, metric_key, source_token, message_template, operator, threshold1, threshold2, duration_sec, hysteresis, severity " +
            "FROM dbo.alarm_rule " +
            "WHERE enabled = 1 AND UPPER(target_scope) = 'PLC' " +
            "ORDER BY rule_id";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                AlarmRule r = new AlarmRule();
                r.ruleId = rs.getInt("rule_id");
                r.ruleCode = rs.getString("rule_code");
                r.targetScope = rs.getString("target_scope");
                r.metricKey = rs.getString("metric_key");
                r.sourceToken = rs.getString("source_token");
                r.messageTemplate = rs.getString("message_template");
                r.operator = rs.getString("operator");
                Object t1 = rs.getObject("threshold1");
                Object t2 = rs.getObject("threshold2");
                Object hy = rs.getObject("hysteresis");
                r.threshold1 = (t1 instanceof Number) ? ((Number)t1).doubleValue() : null;
                r.threshold2 = (t2 instanceof Number) ? ((Number)t2).doubleValue() : null;
                r.durationSec = rs.getInt("duration_sec");
                r.hysteresis = (hy instanceof Number) ? ((Number)hy).doubleValue() : null;
                r.severity = rs.getString("severity");
                if (r.ruleCode == null || r.ruleCode.trim().isEmpty()) continue;
                if (r.metricKey == null || r.metricKey.trim().isEmpty()) continue;
                out.add(r);
            }
        }
        return out;
    }

    private static List<DiGroupMapRule> loadEnabledDiGroupMapRules(Connection conn) {
        List<DiGroupMapRule> out = new ArrayList<>();
        String sql =
            "IF OBJECT_ID('dbo.di_signal_group_map','U') IS NOT NULL " +
            "SELECT group_key, metric_key, match_type, match_value, priority " +
            "FROM dbo.di_signal_group_map WHERE enabled = 1 ORDER BY priority, group_map_id";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                DiGroupMapRule r = new DiGroupMapRule();
                r.groupKey = rs.getString("group_key");
                r.metricKey = rs.getString("metric_key");
                r.matchType = rs.getString("match_type");
                r.matchValue = rs.getString("match_value");
                r.priority = rs.getInt("priority");
                if (r.metricKey == null || r.metricKey.trim().isEmpty()) continue;
                out.add(r);
            }
        } catch (Exception ignore) {
        }
        return out;
    }

    private static Map<String, DiGroupRule> loadEnabledDiGroupRules(Connection conn) {
        Map<String, DiGroupRule> out = new HashMap<>();
        String sql =
            "IF OBJECT_ID('dbo.di_group_rule_map','U') IS NOT NULL " +
            "SELECT metric_key, match_mode, count_threshold FROM dbo.di_group_rule_map WHERE enabled = 1";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                DiGroupRule r = new DiGroupRule();
                r.metricKey = rs.getString("metric_key");
                r.matchMode = rs.getString("match_mode");
                Object x = rs.getObject("count_threshold");
                r.countThreshold = (x instanceof Number) ? Integer.valueOf(((Number)x).intValue()) : null;
                if (r.metricKey == null || r.metricKey.trim().isEmpty()) continue;
                out.put(r.metricKey.trim().toUpperCase(Locale.ROOT), r);
            }
        } catch (Exception ignore) {
        }
        return out;
    }

    private static boolean matchesDiGroupRule(Map<String, Object> row, DiGroupMapRule rule) {
        if (row == null || rule == null) return false;
        String matchType = rule.matchType == null ? "" : rule.matchType.trim().toUpperCase(Locale.ROOT);
        String matchValue = normalizeMatchText(rule.matchValue);
        if (matchValue.isEmpty()) return false;
        if ("TAG_NAME".equals(matchType)) return normalizeMatchText(String.valueOf(row.get("tag_name") == null ? "" : row.get("tag_name"))).contains(matchValue);
        if ("ITEM_NAME".equals(matchType)) return normalizeMatchText(String.valueOf(row.get("item_name") == null ? "" : row.get("item_name"))).contains(matchValue);
        if ("PANEL_NAME".equals(matchType)) return normalizeMatchText(String.valueOf(row.get("panel_name") == null ? "" : row.get("panel_name"))).contains(matchValue);
        if ("POINT_ID".equals(matchType)) return String.valueOf(((Number)row.get("point_id")).intValue()).equals(matchValue);
        if ("ADDRESS_BIT".equals(matchType)) {
            String key = ((Number)row.get("di_address")).intValue() + ":" + ((Number)row.get("bit_no")).intValue();
            return key.equals(matchValue) || key.equals(matchValue.replace('.', ':'));
        }
        return false;
    }

    private static boolean evalDiGroupActive(DiGroupRule groupRule, DiGroupState state) {
        if (state == null || state.bitCount <= 0) return false;
        String mode = groupRule == null || groupRule.matchMode == null ? "ANY_ON" : groupRule.matchMode.trim().toUpperCase(Locale.ROOT);
        if ("ALL_ON".equals(mode)) return state.onCount == state.bitCount;
        if ("COUNT_GE".equals(mode)) {
            int threshold = (groupRule == null || groupRule.countThreshold == null || groupRule.countThreshold.intValue() <= 0) ? 1 : groupRule.countThreshold.intValue();
            return state.onCount >= threshold;
        }
        return state.onCount >= 1;
    }

    private static void insertDiRuleAlarm(PreparedStatement insAlarm, int deviceId, String eventType, String severity, Timestamp measuredAt, String description, AlarmRule rule, double value) throws Exception {
        insAlarm.setInt(1, deviceId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        insAlarm.setInt(6, rule.ruleId);
        insAlarm.setString(7, rule.ruleCode);
        insAlarm.setString(8, rule.metricKey);
        insAlarm.setString(9, (rule.sourceToken == null || rule.sourceToken.trim().isEmpty()) ? rule.metricKey : rule.sourceToken);
        insAlarm.setDouble(10, value);
        insAlarm.setString(11, rule.operator);
        if (rule.threshold1 == null) insAlarm.setNull(12, Types.FLOAT); else insAlarm.setDouble(12, rule.threshold1.doubleValue());
        if (rule.threshold2 == null) insAlarm.setNull(13, Types.FLOAT); else insAlarm.setDouble(13, rule.threshold2.doubleValue());
        insAlarm.executeUpdate();
    }

    private static int[] processAiEvents(int plcId, List<AiRow> aiRows, Timestamp measuredAt) throws Exception {
        int opened = 0;
        int closed = 0;
        if (aiRows == null || aiRows.isEmpty()) return new int[]{0, 0};

        long measuredAtMs = measuredAt.getTime();
        String selOpenSql =
            "SELECT TOP 1 event_id FROM dbo.device_events " +
            "WHERE device_id = ? AND event_type = ? AND restored_time IS NULL " +
            "ORDER BY event_id DESC";
        String insSql =
            "INSERT INTO dbo.device_events (device_id, event_type, event_time, severity, description) " +
            "VALUES (?, ?, ?, ?, ?)";
        String closeSql =
            "UPDATE dbo.device_events " +
            "SET restored_time = ?, duration_seconds = DATEDIFF(SECOND, event_time, ?), " +
            "    downtime_minutes = DATEDIFF(SECOND, event_time, ?) / 60.0 " +
            "WHERE event_id = ?";
        String selOpenAnyRuleSql =
            "SELECT event_id, event_type FROM dbo.device_events " +
            "WHERE device_id = ? AND event_type LIKE ? AND restored_time IS NULL";
        String selAlarmOpenSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String insAlarmSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token, measured_value, operator, threshold1, threshold2) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        String clearAlarmSql =
            "UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?";

        try (Connection conn = createConn();
             PreparedStatement selOpen = conn.prepareStatement(selOpenSql);
             PreparedStatement ins = conn.prepareStatement(insSql);
             PreparedStatement close = conn.prepareStatement(closeSql);
             PreparedStatement selOpenAnyRule = conn.prepareStatement(selOpenAnyRuleSql);
             PreparedStatement selAlarmOpen = conn.prepareStatement(selAlarmOpenSql);
             PreparedStatement insAlarm = conn.prepareStatement(insAlarmSql);
             PreparedStatement clearAlarm = conn.prepareStatement(clearAlarmSql)) {

            ensureAlarmSchema(conn);

            Map<String, String> tokenAlias = loadAiTokenColumnAlias(conn);
            List<AlarmRule> rules = loadEnabledAiRules(conn);
            if (rules.isEmpty()) return new int[]{0, 0};

            Map<Integer, Map<String, Double>> valueByMeterMetric = new HashMap<>();
            for (AiRow row : aiRows) {
                Map<String, Double> mm = valueByMeterMetric.computeIfAbsent(row.meterId, k -> new HashMap<>());
                String token = row.token.trim().toUpperCase(Locale.ROOT);
                mm.put(token, row.value);
                String alias = tokenAlias.get(token);
                if (alias != null && !alias.isEmpty()) mm.put(alias, row.value);
            }
            for (Map<String, Double> mm : valueByMeterMetric.values()) {
                enrichGroupedMetrics(mm);
            }

            for (Map.Entry<Integer, Map<String, Double>> me : valueByMeterMetric.entrySet()) {
                int meterId = me.getKey().intValue();
                Map<String, Double> metricValues = me.getValue();

                for (AlarmRule rule : rules) {
                    String metricKey = rule.metricKey.trim().toUpperCase(Locale.ROOT);
                    Double vObj = metricValues.get(metricKey);
                    if (vObj == null) continue;
                    double value = vObj.doubleValue();
                    String stage = evalAiStage(rule, value); // null / WARN / ALARM / CRITICAL
                    String rulePrefix = "AI_RULE_" + rule.ruleCode.trim().toUpperCase(Locale.ROOT);
                    String targetEventType = (stage == null) ? null : (rulePrefix + "_" + stage);

                    // Close stale stages for this rule first (e.g. ALARM -> CRITICAL transition).
                    closed += closeStaleAiStages(selOpenAnyRule, close, selAlarmOpen, clearAlarm, meterId, rulePrefix, targetEventType, measuredAt);

                    if (targetEventType == null) {
                        AI_PENDING_ON_MS.remove(plcId + ":" + meterId + ":" + rulePrefix);
                        continue;
                    }

                    Long openEventId = findOpenEventId(selOpen, meterId, targetEventType);
                    if (openEventId != null) {
                        AI_PENDING_ON_MS.remove(plcId + ":" + meterId + ":" + rulePrefix);
                        continue;
                    }

                    String pendingKey = plcId + ":" + meterId + ":" + rulePrefix + ":" + stage;
                    long startMs;
                    Long prev = AI_PENDING_ON_MS.putIfAbsent(pendingKey, measuredAtMs);
                    if (prev == null) startMs = measuredAtMs;
                    else startMs = prev.longValue();

                    int holdSec = Math.max(0, rule.durationSec);
                    if (holdSec > 0) {
                        long holdMs = holdSec * 1000L;
                        if (measuredAtMs - startMs < holdMs) continue;
                    }

                    String desc =
                        "PLC " + plcId + " AI alarm: meter=" + meterId +
                        ", rule=" + rule.ruleCode +
                        ", stage=" + stage +
                        ", metric=" + rule.metricKey +
                        ", source=" + (rule.sourceToken == null ? rule.metricKey : rule.sourceToken) +
                        ", value=" + String.format(Locale.US, "%.6f", value) +
                        ", op=" + (rule.operator == null ? "" : rule.operator) +
                        ", t1=" + (rule.threshold1 == null ? "null" : String.valueOf(rule.threshold1)) +
                        ", t2=" + (rule.threshold2 == null ? "null" : String.valueOf(rule.threshold2));
                    if (rule.messageTemplate != null && !rule.messageTemplate.trim().isEmpty()) {
                        String mt = rule.messageTemplate;
                        mt = mt.replace("{metric_key}", rule.metricKey == null ? "" : rule.metricKey);
                        mt = mt.replace("{value}", String.format(Locale.US, "%.6f", value));
                        mt = mt.replace("{stage}", stage == null ? "" : stage);
                        mt = mt.replace("{source_token}", rule.sourceToken == null ? "" : rule.sourceToken);
                        if (!mt.trim().isEmpty()) desc = mt + " | " + desc;
                    }

                    opened += insertDeviceEvent(ins, meterId, targetEventType, measuredAt, stage, desc);

                    Long openAlarmId = findOpenAlarmId(selAlarmOpen, meterId, targetEventType);
                    if (openAlarmId == null) {
                        insertAiAlarm(insAlarm, meterId, targetEventType, stage, measuredAt, desc, rule, value);
                    }
                    AI_PENDING_ON_MS.remove(pendingKey);
                }
            }
        }

        return new int[]{opened, closed};
    }

    private static int[] processDiEvents(int plcId, List<Map<String, Object>> diRows, Timestamp measuredAt) throws Exception {
        int opened = 0;
        int closed = 0;
        if (diRows == null || diRows.isEmpty()) return new int[]{0, 0};

        String selOpenSql =
            "SELECT TOP 1 event_id FROM dbo.device_events " +
            "WHERE device_id = ? AND event_type = ? AND restored_time IS NULL " +
            "ORDER BY event_id DESC";
        String insSql =
            "INSERT INTO dbo.device_events (device_id, event_type, event_time, severity, description) " +
            "VALUES (?, ?, ?, ?, ?)";
        String closeSql =
            "UPDATE dbo.device_events " +
            "SET restored_time = ?, duration_seconds = DATEDIFF(SECOND, event_time, ?), " +
            "    downtime_minutes = DATEDIFF(SECOND, event_time, ?) / 60.0 " +
            "WHERE event_id = ?";
        String selAlarmOpenSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String insAlarmSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token, measured_value, operator, threshold1, threshold2) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        String clearAlarmSql =
            "UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?";

        try (Connection conn = createConn();
             PreparedStatement selOpen = conn.prepareStatement(selOpenSql);
             PreparedStatement ins = conn.prepareStatement(insSql);
             PreparedStatement close = conn.prepareStatement(closeSql);
             PreparedStatement selAlarmOpen = conn.prepareStatement(selAlarmOpenSql);
             PreparedStatement insAlarm = conn.prepareStatement(insAlarmSql);
             PreparedStatement clearAlarm = conn.prepareStatement(clearAlarmSql)) {

            ensureAlarmSchema(conn);

            List<AlarmRule> diRules = loadEnabledDiRules(conn);
            Map<String, AlarmRule> diRuleByMetric = new HashMap<>();
            for (AlarmRule r : diRules) {
                diRuleByMetric.put(r.metricKey.trim().toUpperCase(Locale.ROOT), r);
            }
            List<DiGroupMapRule> dbGroupMapRules = loadEnabledDiGroupMapRules(conn);
            Map<String, DiGroupRule> dbGroupRules = loadEnabledDiGroupRules(conn);
            Map<String, DiGroupState> dbGroupStates = new LinkedHashMap<>();
            Set<String> dbGroupMetricKeys = new HashSet<>();
            for (DiGroupMapRule gm : dbGroupMapRules) {
                if (gm.metricKey != null && !gm.metricKey.trim().isEmpty()) {
                    dbGroupMetricKeys.add(gm.metricKey.trim().toUpperCase(Locale.ROOT));
                }
            }

            for (Map<String, Object> row : diRows) {
                int pointId = ((Number)row.get("point_id")).intValue();
                int diAddress = ((Number)row.get("di_address")).intValue();
                int bitNo = ((Number)row.get("bit_no")).intValue();
                int value = ((Number)row.get("value")).intValue();
                String tagName = String.valueOf(row.get("tag_name") == null ? "" : row.get("tag_name"));
                String itemName = String.valueOf(row.get("item_name") == null ? "" : row.get("item_name"));
                String panelName = String.valueOf(row.get("panel_name") == null ? "" : row.get("panel_name"));

                boolean matchedByDbGroup = false;
                for (DiGroupMapRule gm : dbGroupMapRules) {
                    if (!matchesDiGroupRule(row, gm)) continue;
                    matchedByDbGroup = true;
                    String metricKey = gm.metricKey == null ? "" : gm.metricKey.trim().toUpperCase(Locale.ROOT);
                    String groupStateKey = pointId + "|" + metricKey;
                    DiGroupState gs = dbGroupStates.get(groupStateKey);
                    if (gs == null) {
                        gs = new DiGroupState();
                        gs.pointId = pointId;
                        gs.metricKey = metricKey;
                        gs.itemName = itemName;
                        gs.panelName = panelName;
                        dbGroupStates.put(groupStateKey, gs);
                    }
                    gs.bitCount++;
                    if (value == 1) gs.onCount++;
                    if (gs.samples.size() < 8) {
                        gs.samples.add("addr=" + diAddress + ", bit=" + bitNo + ", tag=" + tagName);
                    }
                }
                if (matchedByDbGroup) {
                    LAST_DI_VALUE_MAP.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, value);
                    continue;
                }

                // If a corresponding DI_GROUP_* mapping exists, do not fall back to legacy hardcoded path.
                // This keeps DI evaluation on the DB-driven group/rule path when the project defines that group.
                if ((isTripAlarmBit(tagName) && dbGroupMetricKeys.contains("DI_GROUP_TRIP")) ||
                    (isEldAlarmBit(tagName) && dbGroupMetricKeys.contains("DI_GROUP_ELD")) ||
                    (isTmAlarmBit(tagName) && dbGroupMetricKeys.contains("DI_GROUP_TM")) ||
                    (isOcrAlarmBit(tagName) && dbGroupMetricKeys.contains("DI_GROUP_OCR")) ||
                    (isOcgrAlarmBit(tagName) && dbGroupMetricKeys.contains("DI_GROUP_OCGR")) ||
                    (isOvrAlarmBit(tagName) && dbGroupMetricKeys.contains("DI_GROUP_OVR"))) {
                    LAST_DI_VALUE_MAP.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, value);
                    continue;
                }

                // LIGHT is treated as a DO bit in this project and should not generate DI alarms.
                if (isLightAlarmBit(tagName)) {
                    LAST_DI_VALUE_MAP.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, value);
                    continue;
                }

                // No DB DI group matched. Keep last sampled bit state, but do not create alarms.
                LAST_DI_VALUE_MAP.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, value);
            }

            for (DiGroupState state : dbGroupStates.values()) {
                AlarmRule rule = diRuleByMetric.get(state.metricKey);
                if (rule == null) continue;
                DiGroupRule groupRule = dbGroupRules.get(state.metricKey);
                boolean active = evalDiGroupActive(groupRule, state);
                double evalValue = active ? 1.0d : 0.0d;
                boolean shouldOpen = evalOpen(rule.operator, rule.threshold1, rule.threshold2, evalValue);
                String eventType = "DI_RULE_" + rule.ruleCode.trim().toUpperCase(Locale.ROOT);
                Long openEventId = findOpenEventId(selOpen, state.pointId, eventType);

                if (!shouldOpen) {
                    DI_PENDING_ON_MS.remove(plcId + ":" + state.pointId + ":" + eventType);
                    if (openEventId != null && shouldCloseOpenEvent(rule, evalValue)) {
                        closed += closeOpenEvent(close, measuredAt, openEventId);
                        clearOpenAlarm(clearAlarm, measuredAt, findOpenAlarmId(selAlarmOpen, state.pointId, eventType));
                    }
                    continue;
                }

                if (openEventId != null) {
                    DI_PENDING_ON_MS.remove(plcId + ":" + state.pointId + ":" + eventType);
                    continue;
                }

                String pendingKey = plcId + ":" + state.pointId + ":" + eventType;
                long nowMs = measuredAt.getTime();
                long startMs = DI_PENDING_ON_MS.containsKey(pendingKey) ? DI_PENDING_ON_MS.get(pendingKey).longValue() : nowMs;
                DI_PENDING_ON_MS.putIfAbsent(pendingKey, Long.valueOf(nowMs));
                int holdSec = Math.max(0, rule.durationSec);
                if (holdSec > 0 && (nowMs - startMs) < (holdSec * 1000L)) {
                    continue;
                }

                String desc =
                    "PLC " + plcId + " DI grouped alarm: point=" + state.pointId +
                    ", rule=" + rule.ruleCode +
                    ", metric=" + rule.metricKey +
                    ", on=" + state.onCount + "/" + state.bitCount +
                    ", panel=" + state.panelName +
                    ", item=" + state.itemName +
                    ", samples=" + String.join(" ; ", state.samples);
                if (rule.messageTemplate != null && !rule.messageTemplate.trim().isEmpty()) {
                    String mt = rule.messageTemplate;
                    mt = mt.replace("{metric_key}", rule.metricKey == null ? "" : rule.metricKey);
                    mt = mt.replace("{value}", String.format(Locale.US, "%.0f", evalValue));
                    mt = mt.replace("{source_token}", rule.sourceToken == null ? "" : rule.sourceToken);
                    if (!mt.trim().isEmpty()) desc = mt + " | " + desc;
                }

                String sev = (rule.severity == null || rule.severity.trim().isEmpty()) ? "ALARM" : rule.severity.trim().toUpperCase(Locale.ROOT);
                opened += insertDeviceEvent(ins, state.pointId, eventType, measuredAt, sev, desc);
                Long openAlarmId = findOpenAlarmId(selAlarmOpen, state.pointId, eventType);
                if (openAlarmId == null) {
                    insertDiRuleAlarm(insAlarm, state.pointId, eventType, sev, measuredAt, desc, rule, evalValue);
                }
                DI_PENDING_ON_MS.remove(pendingKey);
            }

        }
        return new int[]{opened, closed};
    }

    private static DiRequestPayload parseDiRequest(javax.servlet.http.HttpServletRequest req) {
        DiRequestPayload payload = new DiRequestPayload();
        payload.plcId = parseIntSafe(req.getParameter("plc_id"), 0);
        long measuredAtMs = parseLongSafe(req.getParameter("measured_at_ms"), System.currentTimeMillis());
        payload.measuredAt = new Timestamp(measuredAtMs);
        payload.rows = parseRows(req.getParameter("rows"));
        return payload;
    }

    private static AiRequestPayload parseAiRequest(javax.servlet.http.HttpServletRequest req) {
        AiRequestPayload payload = new AiRequestPayload();
        payload.plcId = parseIntSafe(req.getParameter("plc_id"), 0);
        long measuredAtMs = parseLongSafe(req.getParameter("measured_at_ms"), System.currentTimeMillis());
        payload.measuredAt = new Timestamp(measuredAtMs);
        payload.rows = parseAiRows(req.getParameter("rows"));
        return payload;
    }

    private static void writeJsonError(javax.servlet.jsp.JspWriter out, String message) throws java.io.IOException {
        out.print("{\"ok\":false,\"error\":\"" + escJson(message) + "\"}");
    }

    private static void writeJsonCounts(javax.servlet.jsp.JspWriter out, int opened, int closed, int rows) throws java.io.IOException {
        out.print("{\"ok\":true,\"opened\":" + opened + ",\"closed\":" + closed + ",\"rows\":" + rows + "}");
    }
%>
<%
    response.setContentType("application/json; charset=UTF-8");
    request.setCharacterEncoding("UTF-8");

    String action = request.getParameter("action");
    if (action == null || action.trim().isEmpty()) {
        writeJsonError(out, "action is required");
        return;
    }

    if ("health".equalsIgnoreCase(action)) {
        out.print("{\"ok\":true,\"info\":\"alarm api alive\"}");
        return;
    }

    if ("process_di".equalsIgnoreCase(action)) {
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            writeJsonError(out, "POST method is required");
            return;
        }

        DiRequestPayload diReq = parseDiRequest(request);
        if (diReq.plcId <= 0) {
            writeJsonError(out, "plc_id is required");
            return;
        }

        try {
            int[] result = processDiEvents(diReq.plcId, diReq.rows, diReq.measuredAt);
            writeJsonCounts(out, result[0], result[1], diReq.rows.size());
        } catch (Exception e) {
            writeJsonError(out, e.getMessage());
        }
        return;
    }

    if ("process_ai".equalsIgnoreCase(action)) {
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            writeJsonError(out, "POST method is required");
            return;
        }

        AiRequestPayload aiReq = parseAiRequest(request);
        if (aiReq.plcId <= 0) {
            writeJsonError(out, "plc_id is required");
            return;
        }

        try {
            int[] result = processAiEvents(aiReq.plcId, aiReq.rows, aiReq.measuredAt);
            writeJsonCounts(out, result[0], result[1], aiReq.rows.size());
        } catch (Exception e) {
            writeJsonError(out, e.getMessage());
        }
        return;
    }

    writeJsonError(out, "unknown action");
%>
