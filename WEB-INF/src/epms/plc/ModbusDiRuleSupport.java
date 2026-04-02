package epms.plc;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class ModbusDiRuleSupport {
    public static final class DiRuleMeta {
        public int ruleId;
        public String ruleCode;
        public String ruleName;
        public String metricKey;
        public String messageTemplate;
    }

    private ModbusDiRuleSupport() {
    }

    public static void ensureAlarmLogRuleColumns(Connection conn) throws Exception {
        Boolean cached = ModbusCacheSupport.alarmLogRuleColumnsOkRef().get();
        if (Boolean.TRUE.equals(cached)) return;
        if (conn == null) throw new SQLException("Connection is required to verify dbo.alarm_log schema.");

        String sql =
                "SELECT " +
                "CASE WHEN COL_LENGTH('dbo.alarm_log','rule_id') IS NOT NULL THEN 1 ELSE 0 END AS has_rule_id, " +
                "CASE WHEN COL_LENGTH('dbo.alarm_log','rule_code') IS NOT NULL THEN 1 ELSE 0 END AS has_rule_code, " +
                "CASE WHEN COL_LENGTH('dbo.alarm_log','metric_key') IS NOT NULL THEN 1 ELSE 0 END AS has_metric_key, " +
                "CASE WHEN COL_LENGTH('dbo.alarm_log','source_token') IS NOT NULL THEN 1 ELSE 0 END AS has_source_token";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                boolean ok =
                        rs.getInt("has_rule_id") == 1 &&
                        rs.getInt("has_rule_code") == 1 &&
                        rs.getInt("has_metric_key") == 1 &&
                        rs.getInt("has_source_token") == 1;
                if (ok) {
                    ModbusCacheSupport.alarmLogRuleColumnsOkRef().compareAndSet(null, Boolean.TRUE);
                    return;
                }
            }
        }
        ModbusCacheSupport.alarmLogRuleColumnsOkRef().set(Boolean.FALSE);
        throw new SQLException(
                "dbo.alarm_log is missing required DI rule columns. Apply docs/sql/add_alarm_log_rule_columns.sql before using DI alarm persistence."
        );
    }

    public static Map<String, DiRuleMeta> loadCachedDiRuleMeta(Connection conn) throws Exception {
        ModbusCacheSupport.CacheEntry<Map<String, DiRuleMeta>> ce = ModbusCacheSupport.<Map<String, DiRuleMeta>>diRuleCache().get("GLOBAL");
        if (ce != null) {
            return ce.data;
        }
        synchronized (ModbusCacheSupport.diRuleCache()) {
            ce = ModbusCacheSupport.<Map<String, DiRuleMeta>>diRuleCache().get("GLOBAL");
            if (ce != null) {
                return ce.data;
            }
            Map<String, DiRuleMeta> out = new HashMap<>();
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT rule_id, rule_code, rule_name, metric_key, message_template " +
                    "FROM dbo.alarm_rule " +
                    "WHERE target_scope = 'PLC' AND rule_code LIKE 'DI_%' AND enabled = 1");
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    DiRuleMeta m = new DiRuleMeta();
                    m.ruleId = rs.getInt("rule_id");
                    m.ruleCode = rs.getString("rule_code");
                    m.ruleName = rs.getString("rule_name");
                    m.metricKey = rs.getString("metric_key");
                    m.messageTemplate = rs.getString("message_template");
                    out.put(normKey(m.ruleCode), m);
                }
            }
            ModbusCacheSupport.<Map<String, DiRuleMeta>>diRuleCache().put("GLOBAL", new ModbusCacheSupport.CacheEntry<Map<String, DiRuleMeta>>(out));
            return out;
        }
    }

    public static String buildDiEventType(int bitNo, String tagName) {
        String tagKey = normalizeTagKey(tagName);
        if (isTripAlarmBit(tagName)) {
            String suffix = compactEventToken(tagKey, "DI", "TRIP", "TR", "ALARM");
            if ("TM".equals(suffix)) return "DI_TR_ALARM";
            return suffix.isEmpty() ? "DI_TRIP" : ("DI_TRIP_" + suffix);
        }
        if (isOcrAlarmBit(tagName)) {
            String suffix = compactEventToken(tagKey, "DI", "OCR");
            return suffix.isEmpty() ? "DI_OCR" : ("DI_OCR_" + suffix);
        }
        if (isOcgrAlarmBit(tagName)) {
            String suffix = compactEventToken(tagKey, "DI", "OCGR");
            return suffix.isEmpty() ? "DI_OCGR" : ("DI_OCGR_" + suffix);
        }
        if (tagKey.contains("ELD")) {
            String suffix = compactEventToken(tagKey, "DI", "ELD");
            if (suffix.matches("\\d+")) return "DI_ELD";
        }
        if (!tagKey.isEmpty()) {
            String suffix = compactEventToken(tagKey, "DI", "TAG");
            if ("ON1_OFF1_ST1".equals(suffix) || "ON2_OFF2_ST2".equals(suffix)) return "DI_ON_OFF";
            return suffix.isEmpty() ? "DI_TAG" : ("DI_TAG_" + suffix);
        }
        return "DI_BIT_" + bitNo;
    }

    public static String resolveDiRuleCode(String eventType, String tagName) {
        String ev = normKey(eventType);
        if (ev.startsWith("DI_TR_ALARM")) return "DI_TR_ALARM";
        if (ev.startsWith("DI_TRIP")) return "DI_TRIP";
        if (ev.startsWith("DI_OCR")) return "DI_OCR";
        if (ev.startsWith("DI_OCGR")) return "DI_OCGR";
        if (ev.startsWith("DI_ELD")) return "DI_ELD";
        if (ev.startsWith("DI_ON_OFF")) return "DI_ON_OFF";
        if (ev.startsWith("DI_BIT")) return "DI_BIT";
        if (ev.startsWith("DI_TAG_TM") || isTmAlarmBit(tagName)) return "DI_TM";
        if (ev.startsWith("DI_TAG_OVR") || isOvrAlarmBit(tagName)) return "DI_OVR";
        if (ev.startsWith("DI_TAG")) return "DI_TAG";
        return ev.isEmpty() ? "DI_TAG" : ev;
    }

    public static String renderDiDescription(
            DiRuleMeta ruleMeta,
            int plcId,
            int pointId,
            int diAddress,
            int bitNo,
            String tagName,
            String itemName,
            String panelName,
            String eventType) {
        String base = "PLC " + plcId + " DI ON: point=" + pointId +
                ", addr=" + diAddress + ", bit=" + bitNo +
                ", tag=" + tagName + ", item=" + itemName + ", panel=" + panelName;
        if (ruleMeta == null || ruleMeta.messageTemplate == null || ruleMeta.messageTemplate.trim().isEmpty()) return base;
        String mt = ruleMeta.messageTemplate;
        String ruleCodeText = ruleMeta.ruleCode == null ? "" : ruleMeta.ruleCode;
        String metricText = ruleMeta.metricKey == null ? "" : ruleMeta.metricKey;
        String sourceText = eventType == null ? "" : eventType;
        String tagText = tagName == null ? "" : tagName;
        String itemText = itemName == null ? "" : itemName;
        String panelText = panelName == null ? "" : panelName;
        String addressText = String.valueOf(diAddress);
        String bitText = String.valueOf(bitNo);
        String pointText = String.valueOf(pointId);

        mt = mt.replace("${rule_code}", ruleCodeText).replace("{rule_code}", ruleCodeText);
        mt = mt.replace("${metric}", metricText).replace("{metric}", metricText);
        mt = mt.replace("${metric_key}", metricText).replace("{metric_key}", metricText);
        mt = mt.replace("${source}", sourceText).replace("{source}", sourceText);
        mt = mt.replace("${source_token}", sourceText).replace("{source_token}", sourceText);
        mt = mt.replace("${tag}", tagText).replace("{tag}", tagText);
        mt = mt.replace("${item}", itemText).replace("{item}", itemText);
        mt = mt.replace("${panel}", panelText).replace("{panel}", panelText);
        mt = mt.replace("${address}", addressText).replace("{address}", addressText);
        mt = mt.replace("${bit}", bitText).replace("{bit}", bitText);
        mt = mt.replace("${point_id}", pointText).replace("{point_id}", pointText);
        return mt.trim().isEmpty() ? base : mt;
    }

    public static String buildDiAlarmDescLike(String itemName, String panelName) {
        String item = itemName == null ? "" : itemName.trim();
        String panel = panelName == null ? "" : panelName.trim();
        if (!item.isEmpty() && !panel.isEmpty()) return "%item=" + item + "%panel=" + panel + "%";
        if (!item.isEmpty()) return "%item=" + item + "%";
        if (!panel.isEmpty()) return "%panel=" + panel + "%";
        return null;
    }

    public static String getDiSeverity(String tagName) {
        String t = normKey(tagName);
        if (t.contains("ON1") && t.contains("OFF1")) return "NORMAL";
        if (t.contains("ON2") && t.contains("OFF2")) return "NORMAL";
        if (isTripAlarmBit(tagName) || isOcrAlarmBit(tagName) || isOcgrAlarmBit(tagName)
                || isTmAlarmBit(tagName) || isOvrAlarmBit(tagName) || isEldAlarmBit(tagName)) {
            return "ALARM";
        }
        return "NORMAL";
    }

    public static String normKey(String s) {
        return s == null ? "" : s.trim().toUpperCase(Locale.ROOT);
    }

    private static boolean isOcrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("OCGR") || t.contains("51G") || t.contains("GROUND")) return false;
        if (t.contains("OCR")) return true;
        if (t.contains("OVERCURRENT")) return true;
        if (t.contains("\\50") || t.contains("50")) return true;
        if (t.contains("\\51") || t.contains("51")) return true;
        return false;
    }

    private static boolean isOcgrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        return t.contains("OCGR") || t.contains("51G") || t.contains("GROUND");
    }

    private static boolean isTripAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        return t.contains("TR_ALARM") || t.contains("TRALARM") || t.contains("TRIP");
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

    private static boolean isOvrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("OCR") || t.contains("OCGR") || t.contains("51G") || t.contains("GROUND")) return false;
        if (t.contains("OVR")) return true;
        if (t.contains("\\59") || t.contains("59")) return true;
        return false;
    }

    private static String normalizeTagKey(String tagName) {
        if (tagName == null) return "";
        String t = tagName.trim().toUpperCase(Locale.ROOT);
        if (t.isEmpty()) return "";
        t = t.replaceAll("[^A-Z0-9]+", "_");
        t = t.replaceAll("_+", "_");
        t = t.replaceAll("^_+|_+$", "");
        if (t.length() > 64) t = t.substring(0, 64);
        return t;
    }

    private static String compactEventToken(String normalizedTagKey, String... dropTokens) {
        if (normalizedTagKey == null || normalizedTagKey.isEmpty()) return "";
        Set<String> drop = new HashSet<>();
        if (dropTokens != null) {
            for (String d : dropTokens) {
                if (d == null) continue;
                String x = d.trim().toUpperCase(Locale.ROOT);
                if (!x.isEmpty()) drop.add(x);
            }
        }
        LinkedHashSet<String> uniq = new LinkedHashSet<>();
        String[] parts = normalizedTagKey.split("_+");
        for (String p : parts) {
            if (p == null) continue;
            String x = p.trim().toUpperCase(Locale.ROOT);
            if (x.isEmpty() || drop.contains(x)) continue;
            uniq.add(x);
        }
        return uniq.isEmpty() ? "" : String.join("_", uniq);
    }
}
