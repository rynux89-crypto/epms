package epms.alarm;

import epms.alarm.AlarmApiModels.CacheEntry;
import epms.alarm.AlarmApiModels.DiRuleMeta;
import epms.alarm.AlarmApiModels.DiRuntimeContext;
import epms.alarm.AlarmApiModels.OpenCloseCount;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public final class AlarmDiProcessingSupport {
    private AlarmDiProcessingSupport() {
    }

    public static DiRuntimeContext loadDiRuntimeContext(
            Connection conn,
            ConcurrentHashMap<String, CacheEntry<Map<String, DiRuleMeta>>> diRuleCache,
            long diRuleCacheTtlMs) throws Exception {
        DiRuntimeContext ctx = new DiRuntimeContext();
        ctx.meterIdByName = loadMeterIdByExactName(conn);
        ctx.diRuleMetaMap = loadCachedDiRuleMeta(conn, diRuleCache, diRuleCacheTtlMs);
        return ctx;
    }

    public static OpenCloseCount processSingleDiRow(
            PreparedStatement selOpen,
            PreparedStatement ins,
            PreparedStatement close,
            PreparedStatement selAlarmOpen,
            PreparedStatement selAlarmOpenAll,
            PreparedStatement insAlarm,
            PreparedStatement clearAlarm,
            Map<String, Integer> meterIdByName,
            Map<String, DiRuleMeta> diRuleMetaMap,
            int plcId,
            Timestamp measuredAt,
            Map<String, Object> row,
            ConcurrentHashMap<String, Integer> lastDiValueMap) throws Exception {
        OpenCloseCount out = new OpenCloseCount();
        int pointId = ((Number) row.get("point_id")).intValue();
        int diAddress = ((Number) row.get("di_address")).intValue();
        int bitNo = ((Number) row.get("bit_no")).intValue();
        int value = ((Number) row.get("value")).intValue();
        String tagName = String.valueOf(row.get("tag_name") == null ? "" : row.get("tag_name"));
        String itemName = String.valueOf(row.get("item_name") == null ? "" : row.get("item_name"));
        String panelName = String.valueOf(row.get("panel_name") == null ? "" : row.get("panel_name"));

        if (isLightAlarmBit(tagName)) {
            lastDiValueMap.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, Integer.valueOf(value));
            return out;
        }

        int deviceId = pointId;
        int alarmMeterId = resolveDiAlarmMeterId(meterIdByName, itemName);
        Integer eventMeterId = alarmMeterId > 0 ? Integer.valueOf(alarmMeterId) : null;
        int eventEntityId = alarmMeterId > 0 ? alarmMeterId : deviceId;
        String eventType = buildDiEventType(bitNo, tagName);
        String diRuleCode = resolveDiRuleCode(eventType, tagName);
        DiRuleMeta diRuleMeta = diRuleMetaMap == null ? null : diRuleMetaMap.get(normKey(diRuleCode));
        boolean diRuleEnabled = diRuleMeta != null && diRuleMeta.ruleId > 0;
        String diKey = plcId + ":" + pointId + ":" + diAddress + ":" + bitNo;
        Integer prev = lastDiValueMap.get(diKey);
        String desc = renderDiDescription(diRuleMeta, plcId, pointId, diAddress, bitNo, tagName, itemName, panelName, eventType);
        String sev = getDiSeverity(tagName);

        if (prev == null) {
            if (value == 1) {
                openDiAlarmIfNeeded(selOpen, ins, selAlarmOpen, insAlarm, eventMeterId, eventEntityId, alarmMeterId, eventType, sev, measuredAt, desc, diRuleMeta, diRuleEnabled, out);
            } else {
                closeDiAlarmIfOpen(selOpen, close, selAlarmOpenAll, clearAlarm, eventEntityId, alarmMeterId, eventType, measuredAt, out);
            }
            lastDiValueMap.put(diKey, Integer.valueOf(value));
            return out;
        }

        if (prev.intValue() == 0 && value == 1) {
            openDiAlarmIfNeeded(selOpen, ins, selAlarmOpen, insAlarm, eventMeterId, eventEntityId, alarmMeterId, eventType, sev, measuredAt, desc, diRuleMeta, diRuleEnabled, out);
        } else if (prev.intValue() == 1 && value == 0) {
            closeDiAlarmIfOpen(selOpen, close, selAlarmOpenAll, clearAlarm, eventEntityId, alarmMeterId, eventType, measuredAt, out);
        }
        lastDiValueMap.put(diKey, Integer.valueOf(value));
        return out;
    }

    private static void openDiAlarmIfNeeded(
            PreparedStatement selOpen,
            PreparedStatement ins,
            PreparedStatement selAlarmOpen,
            PreparedStatement insAlarm,
            Integer meterId,
            int eventEntityId,
            int alarmMeterId,
            String eventType,
            String severity,
            Timestamp measuredAt,
            String description,
            DiRuleMeta diRuleMeta,
            boolean diRuleEnabled,
            OpenCloseCount out) throws Exception {
        if (!diRuleEnabled) return;
        Long openEventId = null;
        if (!AlarmFacade.isDiEventOpen(eventEntityId, eventType, measuredAt.getTime())) {
            openEventId = AlarmPersistenceSupport.findOpenEventId(selOpen, eventEntityId, eventType);
            if (openEventId != null) {
                AlarmFacade.rememberDiEventOpen(eventEntityId, eventType, severity, measuredAt.getTime());
            }
        } else {
            openEventId = Long.valueOf(-1L);
        }
        if (openEventId == null) {
            out.opened += AlarmPersistenceSupport.insertDeviceEvent(ins, meterId, eventEntityId, eventType, measuredAt, severity, description);
        }
        if (alarmMeterId > 0 && ("ALARM".equalsIgnoreCase(severity) || "CRITICAL".equalsIgnoreCase(severity))) {
            Long openAlarmId = null;
            if (!AlarmFacade.isDiAlarmOpen(alarmMeterId, eventType, measuredAt.getTime())) {
                openAlarmId = AlarmPersistenceSupport.findOpenAlarmId(selAlarmOpen, alarmMeterId, eventType);
                if (openAlarmId != null) {
                    AlarmFacade.rememberDiAlarmOpen(alarmMeterId, eventType, severity, measuredAt.getTime());
                }
            } else {
                openAlarmId = Long.valueOf(-1L);
            }
            if (openAlarmId == null) {
                insertSimpleAlarm(insAlarm, alarmMeterId, eventType, severity, measuredAt, description, diRuleMeta, eventType);
            }
        }
    }

    private static void closeDiAlarmIfOpen(
            PreparedStatement selOpen,
            PreparedStatement close,
            PreparedStatement selAlarmOpenAll,
            PreparedStatement clearAlarm,
            int eventEntityId,
            int alarmMeterId,
            String eventType,
            Timestamp measuredAt,
            OpenCloseCount out) throws Exception {
        Long openEventId = AlarmPersistenceSupport.findOpenEventId(selOpen, eventEntityId, eventType);
        if (openEventId != null) {
            int changed = AlarmPersistenceSupport.closeOpenEvent(close, measuredAt, openEventId);
            out.closed += changed;
            if (changed > 0) {
                AlarmFacade.clearDiEventOpen(eventEntityId, eventType);
                AlarmFacade.queueCloseDiEvent(eventEntityId, eventType, "device event restored");
            }
        }
        if (alarmMeterId > 0) {
            for (Long alarmId : AlarmPersistenceSupport.findOpenAlarmIds(selAlarmOpenAll, alarmMeterId, eventType)) {
                AlarmPersistenceSupport.clearOpenAlarm(clearAlarm, measuredAt, alarmId);
                AlarmFacade.clearDiAlarmOpen(alarmMeterId, eventType);
                AlarmFacade.queueClearDiAlarm(alarmMeterId, eventType, "alarm restored");
            }
        }
    }

    private static Map<String, Integer> loadMeterIdByExactName(Connection conn) throws Exception {
        Map<String, Integer> out = new HashMap<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, name FROM dbo.meters WHERE name IS NOT NULL AND LTRIM(RTRIM(name)) <> ''");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String k = normKey(rs.getString("name"));
                if (!k.isEmpty() && !out.containsKey(k)) out.put(k, Integer.valueOf(rs.getInt("meter_id")));
            }
        }
        return out;
    }

    private static int resolveDiAlarmMeterId(Map<String, Integer> meterIdByName, String itemName) {
        if (meterIdByName != null) {
            Integer exact = meterIdByName.get(normKey(itemName));
            if (exact != null && exact.intValue() > 0) return exact.intValue();
        }
        return 0;
    }

    private static String getDiSeverity(String tagName) {
        String t = normKey(tagName);
        if (t.contains("ON1") && t.contains("OFF1")) return "NORMAL";
        if (t.contains("ON2") && t.contains("OFF2")) return "NORMAL";
        if (isTripAlarmBit(tagName) || isOcrAlarmBit(tagName) || isOcgrAlarmBit(tagName)
                || isTmAlarmBit(tagName) || isOvrAlarmBit(tagName) || isEldAlarmBit(tagName)) {
            return "ALARM";
        }
        return "NORMAL";
    }

    private static String buildDiEventType(int bitNo, String tagName) {
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

    private static String resolveDiRuleCode(String eventType, String tagName) {
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

    private static Map<String, DiRuleMeta> loadCachedDiRuleMeta(
            Connection conn,
            ConcurrentHashMap<String, CacheEntry<Map<String, DiRuleMeta>>> diRuleCache,
            long diRuleCacheTtlMs) throws Exception {
        if (diRuleCache == null) return Collections.emptyMap();
        final String key = "GLOBAL";
        CacheEntry<Map<String, DiRuleMeta>> ce = diRuleCache.get(key);
        if (isCacheValid(ce, diRuleCacheTtlMs)) return ce.data;
        synchronized (diRuleCache) {
            ce = diRuleCache.get(key);
            if (isCacheValid(ce, diRuleCacheTtlMs)) return ce.data;
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
            diRuleCache.put(key, new CacheEntry<>(out));
            return out;
        }
    }

    private static String renderDiDescription(
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
        mt = mt.replace("${addr}", addressText).replace("{addr}", addressText);
        mt = mt.replace("${bit}", bitText).replace("{bit}", bitText);
        mt = mt.replace("${point_id}", pointText).replace("{point_id}", pointText);
        return mt.trim().isEmpty() ? base : mt;
    }

    private static void insertSimpleAlarm(
            PreparedStatement insAlarm,
            int meterId,
            String eventType,
            String severity,
            Timestamp measuredAt,
            String description,
            DiRuleMeta ruleMeta,
            String sourceToken) throws Exception {
        insAlarm.setInt(1, meterId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        if (ruleMeta == null || ruleMeta.ruleId <= 0) insAlarm.setNull(6, Types.INTEGER); else insAlarm.setInt(6, ruleMeta.ruleId);
        insAlarm.setString(7, ruleMeta == null ? null : ruleMeta.ruleCode);
        insAlarm.setString(8, ruleMeta == null ? null : ruleMeta.metricKey);
        insAlarm.setString(9, sourceToken);
        insAlarm.setNull(10, Types.FLOAT);
        insAlarm.setNull(11, Types.VARCHAR);
        insAlarm.setNull(12, Types.FLOAT);
        insAlarm.setNull(13, Types.FLOAT);
        insAlarm.executeUpdate();
        AlarmFacade.queueOpenDiAlarm(meterId, eventType, severity, description);
    }

    private static boolean isCacheValid(CacheEntry<?> ce, long ttlMs) {
        return ce != null && (ttlMs <= 0L || (System.currentTimeMillis() - ce.loadedAtMs) < ttlMs);
    }

    private static String normKey(String s) {
        return s == null ? "" : s.trim().toUpperCase(Locale.ROOT);
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
        Set<String> drop = new LinkedHashSet<>();
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

    private static boolean isOcrAlarmBit(String tagName) {
        String t = normalizeMatchText(tagName);
        if (t.contains("OCGR") || t.contains("51G")) return false;
        return t.contains("OCR") || t.contains("\\50") || t.contains("\u20A950") || t.contains("\\51") || t.contains("\u20A951");
    }

    private static boolean isOcgrAlarmBit(String tagName) {
        String t = normalizeMatchText(tagName);
        return t.contains("OCGR") || t.contains("51G");
    }

    private static boolean isOvrAlarmBit(String tagName) {
        String t = normalizeMatchText(tagName);
        if (t.contains("OCR") || t.contains("OCGR") || t.contains("51G")) return false;
        return t.contains("OVR") || t.contains("\\59") || t.contains("\u20A959");
    }

    private static boolean isTripAlarmBit(String tagName) {
        String t = normalizeMatchText(tagName);
        return t.contains("TR_ALARM") || t.contains("TRALARM") || t.contains("TRIP");
    }

    private static boolean isEldAlarmBit(String tagName) {
        return normalizeMatchText(tagName).contains("ELD");
    }

    private static boolean isTmAlarmBit(String tagName) {
        String t = normalizeMatchText(tagName);
        return t.contains("\\TM") || t.contains("_TM") || t.endsWith("TM") || t.contains("TEMP");
    }

    private static boolean isLightAlarmBit(String tagName) {
        String t = normalizeMatchText(tagName);
        return t.contains("WLIGHT") || t.contains("LIGHT");
    }

    private static String normalizeMatchText(String s) {
        if (s == null) return "";
        return s.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "").trim();
    }
}
