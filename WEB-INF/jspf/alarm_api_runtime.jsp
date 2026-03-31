<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.util.concurrent.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="epms.alarm.AlarmFacade" %>
<%@ page import="epms.alarm.AlarmRuleDef" %>
<%@ page import="epms.alarm.AlarmProcessingResult" %>
<%@ include file="/includes/dbconfig.jspf" %>
<%@ include file="/includes/epms_parse.jspf" %>
<%@ include file="/includes/epms_json.jspf" %>
<%-- Shared utility helpers: parsing, formatting, token normalization --%>
<%@ include file="/includes/alarm_api_utils.jspf" %>
<%-- Shared DB helpers: schema, open/close lookup, insert/update --%>
<%@ include file="/includes/alarm_api_common_db.jspf" %>
<%-- AI metric preparation and derived-metric calculators --%>
<%@ include file="/includes/alarm_api_ai_metrics.jspf" %>
<%-- DI runtime helpers: transition handling, rule lookup, description rendering --%>
<%@ include file="/includes/alarm_api_di_helpers.jspf" %>
<%-- Legacy compatibility helpers kept separate from the main runtime path --%>
<%@ include file="/includes/alarm_api_legacy.jspf" %>
<%!
    // ---------------------------------------------------------------------
    // Local runtime state and lightweight DTOs kept in the entrypoint file
    // ---------------------------------------------------------------------
    private static final ConcurrentHashMap<String, Integer> LAST_DI_VALUE_MAP = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> AI_PENDING_ON_MS = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> DI_PENDING_ON_MS = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, CacheEntry<Map<String, DiRuleMeta>>> DI_RULE_CACHE = new ConcurrentHashMap<>();
    private static final long DI_RULE_CACHE_TTL_MS = 30_000L;

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

    private static class AiRequestPayload {
        int plcId;
        Timestamp measuredAt;
        List<AiRow> rows = Collections.emptyList();
    }

    private static class OpenCloseCount {
        int opened;
        int closed;
    }

    private static class CacheEntry<T> {
        final T data;
        final long loadedAtMs;
        CacheEntry(T data) {
            this.data = data;
            this.loadedAtMs = System.currentTimeMillis();
        }
    }

    private static class DiRuleMeta {
        int ruleId;
        String ruleCode;
        String ruleName;
        String metricKey;
        String messageTemplate;
    }

    private static class AiPreparedMetrics {
        Map<Integer, Map<String, Double>> valueByMeterMetric = Collections.emptyMap();
        Map<String, Map<String, Double>> previousByMeter = Collections.emptyMap();
    }

    private static class DiRuntimeContext {
        Map<String, Integer> meterIdByName = Collections.emptyMap();
        Map<String, DiRuleMeta> diRuleMetaMap = Collections.emptyMap();
    }

    // ---------------------------------------------------------------------
    // DI tag classification helpers
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // AI rule evaluation helpers
    // ---------------------------------------------------------------------
    private static String escapeLikeLiteral(String s) {
        if (s == null || s.isEmpty()) return "";
        return s.replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_")
                .replace("[", "\\[");
    }

    private static int closeStaleAiAlarmStages(
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement clearAlarm,
            int meterId,
            String rulePrefix,
            String targetAlarmType,
            Timestamp measuredAt) throws Exception {
        int closed = 0;
        selAlarmOpenAnyRule.setInt(1, meterId);
        selAlarmOpenAnyRule.setString(2, escapeLikeLiteral(rulePrefix) + "\\_%");
        List<Long> closeIds = new ArrayList<>();
        List<String> closeTypes = new ArrayList<>();
        try (ResultSet rs = selAlarmOpenAnyRule.executeQuery()) {
            while (rs.next()) {
                long alarmId = rs.getLong("alarm_id");
                String alarmType = rs.getString("alarm_type");
                if (targetAlarmType == null || alarmType == null || !targetAlarmType.equals(alarmType)) {
                    closeIds.add(Long.valueOf(alarmId));
                    closeTypes.add(alarmType);
                }
            }
        }
        for (int i = 0; i < closeIds.size(); i++) {
            Long alarmId = closeIds.get(i);
            String alarmType = closeTypes.get(i);
            clearOpenAlarm(clearAlarm, measuredAt, alarmId);
            if (alarmType != null && !alarmType.trim().isEmpty()) {
                AlarmFacade.queueClearAiAlarm(meterId, alarmType, "non-target ai alarm cleared");
            }
            closed++;
        }
        return closed;
    }

    // ---------------------------------------------------------------------
    // AI rule execution helpers
    // ---------------------------------------------------------------------
    // AI alarm processing is organized in three layers:
    // 1) per-source evaluation, 2) per-meter rule scan, 3) request orchestration.
    private static OpenCloseCount processSingleAiSource(
            PreparedStatement selAlarmOpen,
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement insAlarm,
            PreparedStatement clearAlarm,
            int plcId,
            int meterId,
            long measuredAtMs,
            Timestamp measuredAt,
            AlarmRuleDef rule,
            String metricKey,
            String sourceKey,
            double value) throws Exception {
        OpenCloseCount out = new OpenCloseCount();
        String stage = AlarmFacade.evalStage(rule, value);
        String rulePrefix = AlarmFacade.buildAiEventType(rule.getRuleCode(), metricKey, sourceKey, "").replaceAll("_+$", "");
        String targetAlarmType = (stage == null) ? null : AlarmFacade.buildAiEventType(rule.getRuleCode(), metricKey, sourceKey, stage);

        if (targetAlarmType != null) {
            if (AlarmFacade.isAiAlarmOpen(meterId, targetAlarmType, measuredAtMs)) {
                AI_PENDING_ON_MS.remove(plcId + ":" + meterId + ":" + rulePrefix);
                return out;
            }
            Long openAlarmId = findOpenAlarmId(selAlarmOpen, meterId, targetAlarmType);
            if (openAlarmId != null) {
                AlarmFacade.rememberAiAlarmOpen(meterId, targetAlarmType, stage, Double.valueOf(value), measuredAtMs);
                AI_PENDING_ON_MS.remove(plcId + ":" + meterId + ":" + rulePrefix);
                return out;
            }
        }

        out.closed += closeStaleAiAlarmStages(selAlarmOpenAnyRule, clearAlarm, meterId, rulePrefix + "_", targetAlarmType, measuredAt);

        if (targetAlarmType == null) {
            AI_PENDING_ON_MS.remove(plcId + ":" + meterId + ":" + rulePrefix);
            return out;
        }

        String pendingKey = plcId + ":" + meterId + ":" + rulePrefix + ":" + stage;
        long startMs;
        Long prev = AI_PENDING_ON_MS.putIfAbsent(pendingKey, measuredAtMs);
        if (prev == null) startMs = measuredAtMs;
        else startMs = prev.longValue();

        int holdSec = Math.max(0, rule.getDurationSec());
        if (holdSec > 0) {
            long holdMs = holdSec * 1000L;
            if (measuredAtMs - startMs < holdMs) return out;
        }

        String resolvedSource = sourceKey.isEmpty() ? metricKey : sourceKey;
        String desc = "PLC " + plcId + " AI alarm: meter=" + meterId +
            ", rule=" + rule.getRuleCode() +
            ", stage=" + stage +
            ", metric=" + rule.getMetricKey() +
            ", source=" + resolvedSource +
            ", value=" + formatDecimal2(value) +
            ", op=" + (rule.getOperator() == null ? "" : rule.getOperator()) +
            ", t1=" + (rule.getThreshold1() == null ? "null" : formatDecimal2(rule.getThreshold1())) +
            ", t2=" + (rule.getThreshold2() == null ? "null" : formatDecimal2(rule.getThreshold2()));
        desc = AlarmFacade.renderAiMessage(rule, meterId, stage, resolvedSource, value, desc);
        Long openAlarmId = findOpenAlarmId(selAlarmOpen, meterId, targetAlarmType);
        if (openAlarmId == null) {
            insertAiAlarm(insAlarm, meterId, targetAlarmType, stage, measuredAt, desc, rule, value, resolvedSource);
            AlarmFacade.rememberAiAlarmOpen(meterId, targetAlarmType, stage, Double.valueOf(value), measuredAtMs);
            out.opened++;
        } else {
            AlarmFacade.rememberAiAlarmOpen(meterId, targetAlarmType, stage, Double.valueOf(value), measuredAtMs);
        }
        AI_PENDING_ON_MS.remove(pendingKey);
        return out;
    }

    private static OpenCloseCount processAiMeterRules(
            PreparedStatement selAlarmOpen,
            PreparedStatement selAlarmOpenAnyRule,
            PreparedStatement insAlarm,
            PreparedStatement clearAlarm,
            int plcId,
            int meterId,
            long measuredAtMs,
            Timestamp measuredAt,
            Map<String, Double> metricValues,
            List<AlarmRuleDef> rules,
            Map<String, List<String>> metricCatalogTokens) throws Exception {
        OpenCloseCount out = new OpenCloseCount();
        for (AlarmRuleDef rule : rules) {
            String metricKey = normKey(rule.getMetricKey());
            LinkedHashMap<String, Double> sourceValues = resolveAiRuleSourceValues(rule, metricCatalogTokens, metricValues);
            if (sourceValues.isEmpty()) continue;

            for (Map.Entry<String, Double> sourceEntry : sourceValues.entrySet()) {
                OpenCloseCount c = processSingleAiSource(
                    selAlarmOpen,
                    selAlarmOpenAnyRule,
                    insAlarm,
                    clearAlarm,
                    plcId,
                    meterId,
                    measuredAtMs,
                    measuredAt,
                    rule,
                    metricKey,
                    sourceEntry.getKey(),
                    sourceEntry.getValue().doubleValue());
                out.opened += c.opened;
                out.closed += c.closed;
            }
        }
        return out;
    }
    // ---------------------------------------------------------------------
    // Request-level AI / DI processors
    // Main orchestration layer: load context, evaluate rows, persist results.
    // ---------------------------------------------------------------------
    private static AlarmProcessingResult processAiEvents(int plcId, List<AiRow> aiRows, Timestamp measuredAt) throws Exception {
        int opened = 0;
        int closed = 0;
        if (aiRows == null || aiRows.isEmpty()) return AlarmFacade.processingResult(0, 0, 0);

        long measuredAtMs = measuredAt.getTime();
        String selAlarmOpenSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String selAlarmOpenAnyRuleSql =
            "SELECT alarm_id, alarm_type FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type LIKE ? ESCAPE '\\' AND cleared_at IS NULL";
        String insAlarmSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token, measured_value, operator, threshold1, threshold2) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        String clearAlarmSql =
            "UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?";

        try (Connection conn = createConn();
             PreparedStatement selAlarmOpen = conn.prepareStatement(selAlarmOpenSql);
             PreparedStatement selAlarmOpenAnyRule = conn.prepareStatement(selAlarmOpenAnyRuleSql);
             PreparedStatement insAlarm = conn.prepareStatement(insAlarmSql);
             PreparedStatement clearAlarm = conn.prepareStatement(clearAlarmSql)) {

            ensureAlarmSchema(conn);

            Map<String, String> tokenAlias = loadAiTokenColumnAlias(conn);
            Map<String, List<String>> metricCatalogTokens = loadMetricCatalogSourceTokens(conn);
            List<AlarmRuleDef> rules = AlarmFacade.loadEnabledAiRuleDefs(conn);
            if (rules.isEmpty()) return AlarmFacade.processingResult(0, 0, aiRows.size());

            AiPreparedMetrics prepared = prepareAiMetrics(conn, aiRows, measuredAt, tokenAlias);

            for (Map.Entry<Integer, Map<String, Double>> me : prepared.valueByMeterMetric.entrySet()) {
                int meterId = me.getKey().intValue();
                Map<String, Double> metricValues = me.getValue();
                Map<String, Double> previousValues = prepared.previousByMeter.get(String.valueOf(meterId));
                enrichAiDerivedMetrics(metricValues, previousValues);
                OpenCloseCount c = processAiMeterRules(
                    selAlarmOpen,
                    selAlarmOpenAnyRule,
                    insAlarm,
                    clearAlarm,
                    plcId,
                    meterId,
                    measuredAtMs,
                    measuredAt,
                    metricValues,
                    rules,
                    metricCatalogTokens);
                opened += c.opened;
                closed += c.closed;
            }
        }

        return AlarmFacade.processingResult(opened, closed, aiRows.size());
    }

    private static AlarmProcessingResult processDiEvents(int plcId, List<Map<String, Object>> diRows, Timestamp measuredAt) throws Exception {
        int opened = 0;
        int closed = 0;
        if (diRows == null || diRows.isEmpty()) return AlarmFacade.processingResult(0, 0, 0);

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
        String selAlarmOpenAllSql =
            "SELECT alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        String insAlarmSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
        String clearAlarmSql =
            "UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?";

        try (Connection conn = createConn();
             PreparedStatement selOpen = conn.prepareStatement(selOpenSql);
             PreparedStatement ins = conn.prepareStatement(insSql);
             PreparedStatement close = conn.prepareStatement(closeSql);
             PreparedStatement selAlarmOpen = conn.prepareStatement(selAlarmOpenSql);
             PreparedStatement selAlarmOpenAll = conn.prepareStatement(selAlarmOpenAllSql);
             PreparedStatement insAlarm = conn.prepareStatement(insAlarmSql);
             PreparedStatement clearAlarm = conn.prepareStatement(clearAlarmSql)) {

            ensureAlarmSchema(conn);
            DiRuntimeContext diContext = loadDiRuntimeContext(conn);

            for (Map<String, Object> row : diRows) {
                OpenCloseCount c = processSingleDiRow(
                    selOpen, ins, close, selAlarmOpen, selAlarmOpenAll, insAlarm, clearAlarm,
                    diContext.meterIdByName, diContext.diRuleMetaMap, plcId, measuredAt, row);
                opened += c.opened;
                closed += c.closed;
            }

        }
        return AlarmFacade.processingResult(opened, closed, diRows.size());
    }

    // ---------------------------------------------------------------------
    // API request parsing / response helpers
    // Small request/response helpers stay here because they are endpoint-only.
    // ---------------------------------------------------------------------
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

    private static void writeJsonCounts(javax.servlet.jsp.JspWriter out, AlarmProcessingResult result) throws java.io.IOException {
        AlarmProcessingResult safe = (result == null) ? AlarmFacade.processingResult(0, 0, 0) : result;
        out.print("{\"ok\":true,\"opened\":" + safe.getOpened() + ",\"closed\":" + safe.getClosed() + ",\"rows\":" + safe.getInspected() + "," + AlarmFacade.getQueuedWriteSummaryJson() + "}");
    }
%>
<%
    // -----------------------------------------------------------------
    // API entrypoint
    // -----------------------------------------------------------------
    response.setContentType("application/json; charset=UTF-8");
    request.setCharacterEncoding("UTF-8");

    String action = (request.getAttribute("alarmApi.action") instanceof String)
        ? String.valueOf(request.getAttribute("alarmApi.action"))
        : request.getParameter("action");
    boolean validatedByServlet = Boolean.TRUE.equals(request.getAttribute("alarmApi.validated"));
    if (action == null || action.trim().isEmpty()) {
        writeJsonError(out, "action is required");
        return;
    }

    if ("health".equalsIgnoreCase(action)) {
        out.print("{\"ok\":true,\"info\":\"alarm api alive\",\"aiRuleCacheSize\":" + AlarmFacade.getAiRuleCacheSize() +
            ",\"aiOpenStateSize\":" + AlarmFacade.getAiOpenStateSize() +
            ",\"diEventStateSize\":" + AlarmFacade.getDiEventStateSize() +
            ",\"diAlarmStateSize\":" + AlarmFacade.getDiAlarmStateSize() +
            "," + AlarmFacade.getQueuedWriteSummaryJson() + "}");
        return;
    }

    if ("process_di".equalsIgnoreCase(action)) {
        if (!validatedByServlet && !"POST".equalsIgnoreCase(request.getMethod())) {
            writeJsonError(out, "POST method is required");
            return;
        }

        DiRequestPayload diReq = parseDiRequest(request);
        if (!validatedByServlet && diReq.plcId <= 0) {
            writeJsonError(out, "plc_id is required");
            return;
        }

        try {
            AlarmProcessingResult result = processDiEvents(diReq.plcId, diReq.rows, diReq.measuredAt);
            writeJsonCounts(out, result);
        } catch (Exception e) {
            writeJsonError(out, e.getMessage());
        }
        return;
    }

    if ("process_ai".equalsIgnoreCase(action)) {
        if (!validatedByServlet && !"POST".equalsIgnoreCase(request.getMethod())) {
            writeJsonError(out, "POST method is required");
            return;
        }

        AiRequestPayload aiReq = parseAiRequest(request);
        if (!validatedByServlet && aiReq.plcId <= 0) {
            writeJsonError(out, "plc_id is required");
            return;
        }

        try {
            AlarmProcessingResult result = processAiEvents(aiReq.plcId, aiReq.rows, aiReq.measuredAt);
            writeJsonCounts(out, result);
        } catch (Exception e) {
            writeJsonError(out, e.getMessage());
        }
        return;
    }

    writeJsonError(out, "unknown action");
%>
