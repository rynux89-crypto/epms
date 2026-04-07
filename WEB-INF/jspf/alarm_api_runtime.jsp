<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.util.concurrent.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="epms.alarm.AlarmFacade" %>
<%@ page import="epms.alarm.AlarmApiModels.AiRequestPayload" %>
<%@ page import="epms.alarm.AlarmApiModels.AiRow" %>
<%@ page import="epms.alarm.AlarmApiModels.CacheEntry" %>
<%@ page import="epms.alarm.AlarmApiModels.DiRequestPayload" %>
<%@ page import="epms.alarm.AlarmApiModels.DiRuleMeta" %>
<%@ page import="epms.alarm.AlarmApiModels.DiRuntimeContext" %>
<%@ page import="epms.alarm.AlarmApiModels.OpenCloseCount" %>
<%@ page import="epms.alarm.AlarmAiProcessingSupport" %>
<%@ page import="epms.alarm.AlarmAiMetricsSupport" %>
<%@ page import="epms.alarm.AlarmRuleDef" %>
<%@ page import="epms.alarm.AlarmProcessingResult" %>
<%@ include file="/includes/dbconfig.jspf" %>
<%@ include file="/includes/epms_parse.jspf" %>
<%@ include file="/includes/epms_json.jspf" %>
<%-- Shared utility helpers: parsing, formatting, token normalization --%>
<%@ include file="/includes/alarm_api_utils.jspf" %>
<%-- Shared DB helpers: schema, open/close lookup, insert/update --%>
<%@ include file="/includes/alarm_api_common_db.jspf" %>
<%-- DI runtime helpers: transition handling, rule lookup, description rendering --%>
<%@ include file="/includes/alarm_api_di_helpers.jspf" %>
<%!
    // ---------------------------------------------------------------------
    // Local runtime state and lightweight DTOs kept in the entrypoint file
    // ---------------------------------------------------------------------
    private static final ConcurrentHashMap<String, Integer> LAST_DI_VALUE_MAP = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> AI_PENDING_ON_MS = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> DI_PENDING_ON_MS = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, CacheEntry<Map<String, DiRuleMeta>>> DI_RULE_CACHE = new ConcurrentHashMap<>();
    private static final long DI_RULE_CACHE_TTL_MS = 30_000L;

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

            Map<String, String> tokenAlias = AlarmAiMetricsSupport.loadAiTokenColumnAlias(conn);
            Map<String, List<String>> metricCatalogTokens = AlarmAiMetricsSupport.loadMetricCatalogSourceTokens(conn);
            List<AlarmRuleDef> rules = AlarmFacade.loadEnabledAiRuleDefs(conn);
            if (rules.isEmpty()) return AlarmFacade.processingResult(0, 0, aiRows.size());

            epms.alarm.AlarmApiModels.AiPreparedMetrics prepared = AlarmAiMetricsSupport.prepareAiMetrics(conn, aiRows, measuredAt, tokenAlias);

            for (Map.Entry<Integer, Map<String, Double>> me : prepared.valueByMeterMetric.entrySet()) {
                int meterId = me.getKey().intValue();
                Map<String, Double> metricValues = me.getValue();
                Map<String, Double> previousValues = prepared.previousByMeter.get(String.valueOf(meterId));
                AlarmAiMetricsSupport.enrichAiDerivedMetrics(metricValues, previousValues);
            }
            AlarmProcessingResult delegated = AlarmAiProcessingSupport.processPreparedAiEvents(
                selAlarmOpen,
                selAlarmOpenAnyRule,
                insAlarm,
                clearAlarm,
                plcId,
                aiRows.size(),
                measuredAtMs,
                measuredAt,
                prepared,
                rules,
                metricCatalogTokens,
                AI_PENDING_ON_MS);
            opened += delegated.getOpened();
            closed += delegated.getClosed();
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
