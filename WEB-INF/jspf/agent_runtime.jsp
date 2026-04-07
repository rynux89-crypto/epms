﻿<%@ page import="java.io.*,java.net.*,java.util.*,java.sql.*,javax.naming.*,javax.sql.*" trimDirectiveWhitespaces="true" %>
<%@ page contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="epms.util.AgentRuntimeModels.AgentRequestContext,epms.util.AgentRuntimeModels.DirectAnswerRequest,epms.util.AgentRuntimeModels.CriticalDirectAnswerRequest,epms.util.AgentRuntimeModels.DirectAnswerResult,epms.util.AgentRuntimeModels.AgentExecutionContext,epms.util.AgentRuntimeModels.PlannerExecutionResult,epms.util.AgentRuntimeModels.SpecializedAnswerResult" %>

<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
response.setContentType("application/json;charset=UTF-8");
%>

<%!
private static final Object SCHEMA_CACHE_LOCK = new Object();
private static final long DEFAULT_SCHEMA_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final long DEFAULT_METER_SCOPE_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final int SCHEMA_MAX_TABLES = 60;
private static final int SCHEMA_MAX_COLUMNS_PER_TABLE = 40;
private static final int SCHEMA_MAX_CHARS = 16000;
private static volatile String schemaContextCache = "";
private static volatile long schemaContextCacheAt = 0L;
private static volatile long schemaCacheTtlMs = DEFAULT_SCHEMA_CACHE_TTL_MS;

private String trimToNull(String s) {
    return epms.util.AgentSupport.trimToNull(s);
}

private void applySchemaCacheTtl(long nextTtlMs) {
    long prevTtlMs = schemaCacheTtlMs;
    schemaCacheTtlMs = nextTtlMs;
    if (prevTtlMs != nextTtlMs) {
        schemaContextCacheAt = 0L;
    }
}

private boolean isAiDesignIntent(String userMessage) {
    if (userMessage == null) return false;
    String normalized = userMessage.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
    boolean hasAiRoute = epms.util.AgentModelRouter.detectRoute(userMessage) == epms.util.AgentModelRouter.Route.AI;
    boolean hasDesignIntent =
        normalized.contains("모델설계") ||
        normalized.contains("설계하려고") ||
        normalized.contains("설계하고") ||
        normalized.contains("추천모델") ||
        normalized.contains("평가지표") ||
        normalized.contains("학습방법") ||
        normalized.contains("이상탐지") ||
        normalized.contains("예지보전") ||
        normalized.contains("고장예측") ||
        normalized.contains("loadforecasting") ||
        normalized.contains("anomalydetection") ||
        normalized.contains("predictivemaintenance");
    return hasAiRoute && hasDesignIntent;
}

private boolean isBareEnergyValueQuestion(String userMessage) {
    if (userMessage == null) return false;
    String normalized = userMessage.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
    boolean asksEnergy =
        normalized.contains("전력량") || normalized.contains("사용량") || normalized.contains("energy") || normalized.contains("kwh");
    boolean asksCurrent =
        normalized.contains("현재") || normalized.contains("지금") || normalized.contains("latest") || normalized.contains("now");
    boolean hasTarget =
        epms.util.AgentQueryExtractSupport.extractMeterId(userMessage) != null
        || trimToNull(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null
        || (epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage) != null && !epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage).isEmpty())
        || normalized.contains("계측기")
        || normalized.contains("미터")
        || normalized.contains("meter")
        || normalized.contains("패널")
        || normalized.contains("panel")
        || normalized.contains("구역")
        || normalized.contains("동")
        || normalized.contains("라인")
        || normalized.contains("vcb")
        || normalized.contains("acb")
        || normalized.contains("mdb");
    boolean hasPeriod =
        epms.util.AgentQueryExtractSupport.extractTimeWindow(userMessage) != null
        || epms.util.AgentQueryExtractSupport.extractMonth(userMessage) != null;
    return asksEnergy && asksCurrent && !hasTarget && !hasPeriod;
}

private DirectAnswerResult tryBuildDirectAnswer(String userMessage, boolean forceLlmOnly) throws Exception {
    if (forceLlmOnly) return null;

    String directIntentText = epms.util.AgentTextUtil.normalizeForIntent(userMessage);
    Integer directMeterId = epms.util.AgentQueryExtractSupport.extractMeterId(userMessage);
    if (directMeterId == null) {
        directMeterId = epms.util.AgentDbTools.resolveMeterIdByName(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage));
    }
    epms.util.AgentQueryExtractSupport.TimeWindow directWindow = epms.util.AgentQueryExtractSupport.extractTimeWindow(userMessage);
    List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
    List<String> directPanelTokens = epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage);
    if (epms.util.AgentQueryRouterCompat.wantsPanelLatestStatus(userMessage) && (directPanelTokens == null || directPanelTokens.isEmpty())) {
        directPanelTokens = epms.util.AgentQueryExtractSupport.extractPanelTokensLoose(userMessage);
    }
    DirectAnswerRequest directReq = epms.util.AgentRequestSupport.buildDirectAnswerRequest(
        directIntentText,
        epms.util.AgentQueryRouterCompat.wantsTripAlarmOnly(userMessage) || epms.util.AgentLocalIntentSupport.wantsTripAlarmOnly(userMessage),
        epms.util.AgentQueryIntentSupport.wantsAlarmCountSummary(userMessage),
        epms.util.AgentLocalIntentSupport.wantsAlarmCountSummary(userMessage),
        epms.util.AgentQueryIntentSupport.wantsOpenAlarms(userMessage),
        epms.util.AgentLocalIntentSupport.wantsOpenAlarms(userMessage),
        epms.util.AgentQueryIntentSupport.wantsOpenAlarmCountSummary(userMessage),
        epms.util.AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage),
        epms.util.AgentScopedIntentSupport.wantsScopedMonthlyEnergySummary(
            userMessage,
            epms.util.AgentQueryExtractSupport.extractMeterId(userMessage) != null || trimToNull(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null,
            ((findScopeTokensFromMeterMaster(userMessage, 1) != null && !findScopeTokensFromMeterMaster(userMessage, 1).isEmpty())
                || epms.util.AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage) != null)
        ),
        directMeterId,
        epms.util.AgentQueryExtractSupport.extractMonth(userMessage),
        epms.util.AgentQueryExtractSupport.extractTopN(userMessage, 10, 50),
        epms.util.AgentQueryExtractSupport.extractDays(userMessage, 7, 90),
        epms.util.AgentQueryExtractSupport.extractExplicitDays(userMessage, 90),
        directWindow != null ? directWindow.fromTs : null,
        directWindow != null ? directWindow.toTs : null,
        directWindow != null ? directWindow.label : null,
        epms.util.AgentQueryExtractSupport.extractHzThreshold(userMessage),
        epms.util.AgentQueryExtractSupport.extractPfThreshold(userMessage),
        epms.util.AgentQueryExtractSupport.extractAlarmTypeToken(userMessage),
        epms.util.AgentQueryExtractSupport.extractAlarmAreaToken(userMessage),
        epms.util.AgentQueryExtractSupport.extractMeterScopeToken(userMessage),
        epms.util.AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage),
        scopeHints,
        directPanelTokens,
        epms.util.AgentQueryExtractSupport.extractPhaseLabel(userMessage),
        epms.util.AgentQueryExtractSupport.extractLinePairLabel(userMessage),
        epms.util.AgentQueryRouterCompat.wantsPanelLatestStatus(userMessage)
    );
    boolean wantsReactiveEnergyValue = epms.util.AgentQueryRouterCompat.wantsReactiveEnergyValue(userMessage);
    boolean wantsEnergyValue = epms.util.AgentQueryRouterCompat.wantsEnergyValue(userMessage);
    boolean wantsActivePowerValue = epms.util.AgentQueryRouterCompat.wantsActivePowerValue(userMessage);
    boolean wantsReactivePowerValue = epms.util.AgentQueryRouterCompat.wantsReactivePowerValue(userMessage);
    boolean wantsVoltagePhaseAngle = epms.util.AgentQueryRouterCompat.wantsVoltagePhaseAngle(userMessage);
    boolean wantsCurrentPhaseAngle = epms.util.AgentQueryRouterCompat.wantsCurrentPhaseAngle(userMessage);
    boolean wantsPhaseCurrentValue = epms.util.AgentQueryRouterCompat.wantsPhaseCurrentValue(userMessage);
    boolean wantsPhaseVoltageValue = epms.util.AgentQueryRouterCompat.wantsPhaseVoltageValue(userMessage);
    boolean wantsLineVoltageValue = epms.util.AgentQueryRouterCompat.wantsLineVoltageValue(userMessage);
    boolean wantsVoltageAverage = epms.util.AgentQueryRouterCompat.wantsVoltageAverageSummary(userMessage);
    boolean wantsMonthlyFrequency = epms.util.AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage);
    boolean wantsMonthlyPeakPower = epms.util.AgentQueryIntentSupport.wantsMonthlyPeakPower(userMessage);
    boolean wantsMonthlyPowerStats = epms.util.AgentQueryIntentSupport.wantsMonthlyPowerStats(userMessage);
    boolean wantsBuildingPowerTop = epms.util.AgentQueryRouterCompat.wantsBuildingPowerTopN(userMessage);
    String usageCountToken = epms.util.AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage);
    boolean wantsUsageMeterCount = epms.util.AgentScopedIntentSupport.wantsUsageMeterCountSummary(userMessage, usageCountToken);
    if (wantsUsageMeterCount && usageCountToken == null && epms.util.AgentTextUtil.normalizeForIntent(userMessage).contains("비상")) {
        usageCountToken = "비상";
    }
    boolean wantsMeterCount = epms.util.AgentQueryIntentSupport.wantsMeterCountSummary(userMessage);
    String meterCountIntent = epms.util.AgentTextUtil.normalizeForIntent(userMessage);
    String meterCountScopeToken = epms.util.AgentScopeFallbackSupport.shouldTreatAsGlobalMeterCount(userMessage, directReq.directMeterScopeToken) ? null : directReq.directMeterScopeToken;
    if (wantsMeterCount && (meterCountIntent.contains("시스템의계측기수") || meterCountIntent.contains("이시스템의계측기수"))) {
        meterCountScopeToken = null;
    }
    boolean wantsUsageMeterTop = epms.util.AgentLocalIntentSupport.wantsUsageMeterTopSummary(userMessage);
    boolean wantsUsageTypeList = epms.util.AgentQueryIntentSupport.wantsUsageTypeListSummary(userMessage) || epms.util.AgentLocalIntentSupport.wantsUsageTypeListSummary(userMessage);
    boolean wantsMeterList = epms.util.AgentQueryIntentSupport.wantsMeterListSummary(userMessage);
    boolean wantsBuildingCount = epms.util.AgentQueryRouterCompat.wantsBuildingCountSummary(userMessage);
    boolean wantsUsageTypeCount = epms.util.AgentQueryIntentSupport.wantsUsageTypeCountSummary(userMessage);
    boolean wantsPanelCount = epms.util.AgentQueryRouterCompat.wantsPanelCountSummary(userMessage);
    String panelCountScopeToken = epms.util.AgentScopeFallbackSupport.shouldTreatAsGlobalPanelCount(userMessage, directReq.directMeterScopeToken) ? null : directReq.directMeterScopeToken;
    boolean wantsPanelLatestStatus = epms.util.AgentQueryRouterCompat.wantsPanelLatestStatus(userMessage);
    boolean wantsAlarmMeterTop = epms.util.AgentQueryIntentSupport.wantsAlarmMeterTopN(userMessage);
    boolean wantsUsageAlarmTop = epms.util.AgentLocalIntentSupport.wantsUsageAlarmTopSummary(userMessage);
    boolean wantsAlarmType = epms.util.AgentQueryRouterCompat.wantsAlarmTypeSummary(userMessage);
    boolean wantsOpenAlarmCount = directReq.directOpenAlarmCountIntent;
    boolean wantsAlarmSeverity = epms.util.AgentQueryRouterCompat.wantsAlarmSeveritySummary(userMessage);
    String usageAlarmToken = directReq.directAlarmCountIntent ? epms.util.AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage) : null;
    boolean wantsAlarmCount = directReq.directAlarmCountIntent;
    boolean wantsOpenAlarms = directReq.directOpenAlarmsIntent;
    boolean wantsHarmonicExceed = epms.util.AgentQueryIntentSupport.wantsHarmonicExceed(userMessage);
    boolean wantsFrequencyOutlier = epms.util.AgentQueryIntentSupport.wantsFrequencyOutlier(userMessage);
    boolean wantsVoltageUnbalanceTop = epms.util.AgentQueryIntentSupport.wantsVoltageUnbalanceTopN(userMessage);
    boolean wantsPowerFactorOutlier = epms.util.AgentQueryIntentSupport.wantsPowerFactorOutlier(userMessage);
    boolean wantsHarmonicSummary = epms.util.AgentQueryRouterCompat.wantsHarmonicSummary(userMessage) && !wantsHarmonicExceed;
    boolean wantsMeterSummary = epms.util.AgentQueryRouterCompat.wantsMeterSummary(userMessage);
    boolean wantsAlarmSummary = epms.util.AgentQueryIntentSupport.wantsAlarmSummary(userMessage);

    DirectAnswerResult result = new DirectAnswerResult();
    if (directReq.directPfStandard) {
        result.dbContext = "[PF standard] IEEE";
        String delegated = epms.util.AgentAnswerFormatter.buildPowerFactorStandardDirectAnswer(userMessage);
        result.answer = delegated != null
            ? delegated
            : epms.util.AgentCriticalDirectAnswerHelper.buildPowerFactorStandardDirectAnswer(userMessage);
    } else if (isBareEnergyValueQuestion(userMessage)) {
        result.dbContext = "[Energy value] target required";
        result.answer = "전력량을 조회할 대상이 필요합니다. 예: 1번 계측기의 현재 전력량은?, EAST_VCB_MAIN의 현재 전력량은?";
    } else if (directReq.directScopedMonthlyEnergyIntent) {
        return epms.util.AgentCriticalResultHelper.scopedMonthlyEnergy(
            epms.util.AgentDbTools.getScopedMonthlyEnergyContext(directReq.directMeterScopeToken, directReq.directMonth)
        );
    } else {
        DirectAnswerResult powerDelegated = epms.util.AgentDirectFlowHelper.tryBuildPowerPhaseAnswer(
            directReq,
            wantsVoltageAverage,
            wantsMonthlyFrequency,
            wantsMonthlyPeakPower,
            wantsMonthlyPowerStats,
            wantsBuildingPowerTop,
            wantsReactiveEnergyValue,
            wantsEnergyValue,
            wantsActivePowerValue,
            wantsReactivePowerValue,
            wantsVoltagePhaseAngle,
            wantsCurrentPhaseAngle,
            wantsPhaseCurrentValue,
            wantsPhaseVoltageValue,
            wantsLineVoltageValue
        );
        if (powerDelegated != null) {
            return powerDelegated;
        }
        DirectAnswerResult delegated = epms.util.AgentDirectFlowHelper.tryBuildCatalogAlarmOutlierAnswer(
            directReq,
            wantsUsageMeterCount,
            usageCountToken,
            wantsMeterCount,
            meterCountScopeToken,
            wantsUsageMeterTop,
            wantsUsageTypeList,
            wantsMeterList,
            wantsBuildingCount,
            wantsUsageTypeCount,
            wantsPanelCount,
            panelCountScopeToken,
            wantsPanelLatestStatus,
            wantsAlarmMeterTop,
            wantsUsageAlarmTop,
            wantsAlarmType,
            wantsOpenAlarmCount,
            wantsAlarmSeverity,
            wantsAlarmCount && usageAlarmToken != null,
            usageAlarmToken,
            wantsAlarmCount,
            wantsOpenAlarms,
            wantsHarmonicExceed,
            wantsFrequencyOutlier,
            wantsVoltageUnbalanceTop,
            wantsPowerFactorOutlier,
            wantsHarmonicSummary,
            wantsMeterSummary,
            wantsAlarmSummary
        );
        if (delegated != null) {
            return delegated;
        }
    }

    if (result.answer == null || result.dbContext == null) {
        return null;
    }
    return result;
}

private DirectAnswerResult tryBuildCriticalDirectAnswer(String userMessage, boolean forceLlmOnly) throws Exception {
    if (forceLlmOnly) return null;

    boolean criticalHasMeterHint =
        epms.util.AgentQueryExtractSupport.extractMeterId(userMessage) != null
        || trimToNull(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null;
    epms.util.AgentQueryExtractSupport.TimeWindow criticalWindow = epms.util.AgentQueryExtractSupport.extractTimeWindow(userMessage);
    List<String> criticalPanelTokens = epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage);
    if (criticalPanelTokens == null || criticalPanelTokens.isEmpty()) {
        criticalPanelTokens = epms.util.AgentQueryExtractSupport.extractPanelTokensLoose(userMessage);
    }
    Integer criticalMeterId = epms.util.AgentQueryExtractSupport.extractMeterId(userMessage);
    if (criticalMeterId == null) {
        criticalMeterId = epms.util.AgentDbTools.resolveMeterIdByName(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage));
    }
    DirectAnswerRequest criticalAlarmSeed = epms.util.AgentRequestSupport.buildDirectAnswerRequest(
        epms.util.AgentTextUtil.normalizeForIntent(userMessage),
        epms.util.AgentLocalIntentSupport.wantsTripAlarmOnly(userMessage),
        false,
        false,
        false,
        false,
        false,
        epms.util.AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage),
        false,
        criticalMeterId,
        epms.util.AgentQueryExtractSupport.extractMonth(userMessage),
        epms.util.AgentQueryExtractSupport.extractTopN(userMessage, 5, 20),
        epms.util.AgentQueryExtractSupport.extractDays(userMessage, 7, 90),
        epms.util.AgentQueryExtractSupport.extractExplicitDays(userMessage, 90),
        criticalWindow != null ? criticalWindow.fromTs : null,
        criticalWindow != null ? criticalWindow.toTs : null,
        criticalWindow != null ? criticalWindow.label : null,
        null,
        null,
        epms.util.AgentQueryExtractSupport.extractAlarmTypeToken(userMessage),
        epms.util.AgentQueryExtractSupport.extractAlarmAreaToken(userMessage),
        null,
        epms.util.AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage),
        findScopeTokensFromMeterMaster(userMessage, 4),
        criticalPanelTokens,
        null,
        null,
        false
    );
    CriticalDirectAnswerRequest criticalReq = epms.util.AgentRequestSupport.buildCriticalDirectAnswerRequest(
        criticalAlarmSeed.directIntentText,
        criticalHasMeterHint,
        criticalAlarmSeed.directMonth,
        criticalAlarmSeed.directMeterId,
        criticalAlarmSeed.directTopN,
        criticalAlarmSeed.directMeterScopeToken,
        epms.util.AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage),
        criticalAlarmSeed.directAlarmTypeToken,
        criticalAlarmSeed.directAlarmAreaToken,
        criticalAlarmSeed.directFromTs,
        criticalAlarmSeed.directToTs,
        criticalAlarmSeed.directPeriodLabel,
        criticalPanelTokens
    );
    Integer harmonicCountTopN = epms.util.AgentQueryExtractSupport.extractTopN(userMessage, 200, 500);
    DirectAnswerResult criticalResult = epms.util.AgentCriticalFlowHelper.tryBuildCriticalAnswer(
        userMessage,
        criticalReq,
        harmonicCountTopN,
        epms.util.AgentScopedIntentSupport.wantsPanelMonthlyEnergySummary(
            userMessage,
            ((epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage) != null && !epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage).isEmpty())
                || (epms.util.AgentQueryExtractSupport.extractPanelTokensLoose(userMessage) != null && !epms.util.AgentQueryExtractSupport.extractPanelTokensLoose(userMessage).isEmpty()))
        ),
        epms.util.AgentScopedIntentSupport.wantsUsageMonthlyEnergySummary(
            userMessage,
            epms.util.AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage) != null
        ),
        epms.util.AgentLocalIntentSupport.wantsUsagePowerTopSummary(userMessage),
        epms.util.AgentLocalIntentSupport.wantsHarmonicExceedStandard(userMessage),
        epms.util.AgentLocalIntentSupport.wantsFrequencyOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsHarmonicOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsUnbalanceOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsVoltageOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsCurrentOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsCommunicationOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsAlarmTrendGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsPeakCauseGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsPowerFactorOpsGuide(userMessage),
        epms.util.AgentLocalIntentSupport.wantsPowerFactorThreshold(userMessage),
        epms.util.AgentLocalIntentSupport.wantsEpmsKnowledge(userMessage),
        epms.util.AgentLocalIntentSupport.wantsFrequencyOutlierStandard(userMessage),
        epms.util.AgentScopedIntentSupport.wantsMonthlyEnergyUsagePrompt(
            userMessage,
            epms.util.AgentQueryExtractSupport.extractMeterId(userMessage) != null
                || trimToNull(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null
                || !epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage).isEmpty()
                || !epms.util.AgentQueryExtractSupport.extractPanelTokensLoose(userMessage).isEmpty()
        ),
        epms.util.AgentLocalIntentSupport.wantsDisplayedVoltageMeaning(userMessage),
        epms.util.AgentLocalIntentSupport.wantsDisplayedMetricMeaning(userMessage),
        epms.util.AgentLocalIntentSupport.wantsPowerFactorStandard(userMessage),
        epms.util.AgentLocalIntentSupport.wantsCurrentUnbalanceCount(userMessage),
        epms.util.AgentLocalIntentSupport.wantsHarmonicExceedCount(userMessage),
        epms.util.AgentScopedIntentSupport.wantsScopedMonthlyEnergySummary(
            userMessage,
            epms.util.AgentQueryExtractSupport.extractMeterId(userMessage) != null || trimToNull(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null,
            ((findScopeTokensFromMeterMaster(userMessage, 1) != null && !findScopeTokensFromMeterMaster(userMessage, 1).isEmpty())
                || epms.util.AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage) != null)
        ),
        epms.util.AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage)
    );
    return criticalResult;
}

private PlannerExecutionResult executePlannerAndLoadContexts(
    AgentExecutionContext execCtx,
    String userMessage,
    String classifierRaw,
    String schemaContext,
    String ollamaUrl,
    String coderModel,
    int ollamaConnectTimeoutMs,
    int ollamaReadTimeoutMs
) throws Exception {
    PlannerExecutionResult result = new PlannerExecutionResult();
    if (!execCtx.needsDb) return result;

    String coderPrompt =
        "You are DB task planner. Return only one JSON object with keys: " +
        "task(\"meter\"|\"alarm\"|\"both\"|\"none\"), needs_frequency(boolean), needs_power_by_meter(boolean), needs_meter_list(boolean), needs_phase_current(boolean), needs_phase_voltage(boolean), needs_line_voltage(boolean), needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null), meter_scope(string|null), phase(string|null), line_pair(string|null). " +
        "No markdown. No explanation.\n\n" +
        "User: " + userMessage + "\n" +
        "Classifier JSON: " + classifierRaw + "\n\n" +
        "Schema Context:\n" + schemaContext;
    String coderRaw = epms.util.AgentRuntimeFlowSupport.callOllamaOnce(
        ollamaUrl,
        coderModel,
        coderPrompt,
        ollamaConnectTimeoutMs,
        ollamaReadTimeoutMs,
        0.1d
    );

    String task = epms.util.AgentSupport.extractJsonStringField(coderRaw, "task");
    Boolean planNeedsFrequency = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_frequency");
    Boolean planNeedsPower = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_power_by_meter");
    Boolean planNeedsMeterList = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_meter_list");
    Boolean planNeedsPhaseCurrent = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_phase_current");
    Boolean planNeedsPhaseVoltage = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_phase_voltage");
    Boolean planNeedsLineVoltage = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_line_voltage");
    Boolean planNeedsHarmonic = epms.util.AgentSupport.extractJsonBoolField(coderRaw, "needs_harmonic");
    Integer planMeterId = epms.util.AgentSupport.extractJsonIntField(coderRaw, "meter_id");
    Integer planMonth = epms.util.AgentSupport.extractJsonIntField(coderRaw, "month");
    String planPanel = epms.util.AgentSupport.extractJsonStringField(coderRaw, "panel");
    String planMeterScope = epms.util.AgentSupport.extractJsonStringField(coderRaw, "meter_scope");
    String planPhase = epms.util.AgentSupport.extractJsonStringField(coderRaw, "phase");
    String planLinePair = epms.util.AgentSupport.extractJsonStringField(coderRaw, "line_pair");
    epms.util.AgentRuntimeModels.PlannerRunFlags runFlags = epms.util.AgentExecutionSupport.applyPlannerDecision(
        execCtx,
        task,
        planNeedsFrequency,
        planNeedsPower,
        planNeedsMeterList,
        planNeedsPhaseCurrent,
        planNeedsPhaseVoltage,
        planNeedsLineVoltage,
        planNeedsHarmonic,
        planMeterId,
        planMonth,
        planMeterScope,
        planPhase,
        planLinePair,
        epms.util.AgentSupport.panelTokensFromRaw(planPanel),
        epms.util.AgentQueryRouterCompat.wantsMeterSummary(userMessage),
        epms.util.AgentQueryIntentSupport.wantsAlarmSummary(userMessage),
        epms.util.AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
        epms.util.AgentQueryRouterCompat.wantsPerMeterPowerSummary(userMessage),
        findScopeTokensFromMeterMaster(userMessage, 4)
    );

    result = epms.util.AgentPlannerLoadSupport.loadContexts(runFlags, execCtx);
    if (!runFlags.anyEnabled() && execCtx.forceCoderFlow) {
        String coderAnswerPrompt =
            "Answer the user's DB/SQL request directly. " +
            "Use SQL Server syntax if SQL is requested. " +
            "Return concise plain text, no markdown fences.\n\n" +
            "User: " + userMessage + "\n\n" +
            "Schema Context:\n" + schemaContext;
        result.coderDraft = epms.util.AgentRuntimeFlowSupport.callOllamaOnce(
            ollamaUrl,
            coderModel,
            coderAnswerPrompt,
            ollamaConnectTimeoutMs,
            ollamaReadTimeoutMs,
            0.2d
        );
    } else if (!runFlags.anyEnabled()) {
        execCtx.needsDb = false;
    }

    return result;
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
        String fresh = epms.util.AgentDbTools.buildSchemaContextFromDb(
            SCHEMA_MAX_TABLES,
            SCHEMA_MAX_COLUMNS_PER_TABLE,
            SCHEMA_MAX_CHARS
        );
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

private List<String> findScopeTokensFromMeterMaster(String userMessage, int maxTokens) {
    return epms.util.AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, maxTokens);
}

private String findUsageTypeFromDb(String userMessage) {
    return epms.util.AgentMetadataLookupSupport.findUsageTypeFromDb(userMessage);
}

private String findUsageAliasFromDb(String userMessage) {
    return epms.util.AgentMetadataLookupSupport.findUsageAliasFromDb(userMessage);
}

private String findBuildingNameFromDb(String userMessage) {
    return epms.util.AgentMetadataLookupSupport.findBuildingNameFromDb(userMessage);
}

private String findBuildingAliasFromDb(String userMessage) {
    return epms.util.AgentMetadataLookupSupport.findBuildingAliasFromDb(userMessage);
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

if (request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_USER_MESSAGE) == null) {
    if (!epms.agent.AgentApiRequestSupport.prepare(request, response, application)) {
        return;
    }
}

String userMessage = (String) request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_USER_MESSAGE);
if (userMessage == null) {
    epms.util.AgentOutputHelper.writeErrorJson(out, response, 400, "Invalid request context");
    return;
}
boolean forceLlmOnly = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_FORCE_LLM_ONLY));
boolean forceRuleOnly = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_FORCE_RULE_ONLY));
boolean preferNarrativeHint = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_PREFERS_NARRATIVE_HINT));
boolean preferNarrativeLlm = (preferNarrativeHint || epms.util.AgentIntentSupport.prefersNarrativeLlm(userMessage)) && !forceLlmOnly && !forceRuleOnly;
boolean forceAiNarrative = isAiDesignIntent(userMessage) && !forceLlmOnly && !forceRuleOnly;
boolean bypassDirect = epms.util.AgentResponseFlowHelper.shouldBypassDirect(forceLlmOnly, preferNarrativeLlm);
boolean bypassSpecialized = epms.util.AgentResponseFlowHelper.shouldBypassSpecialized(forceLlmOnly, preferNarrativeLlm);
if (forceAiNarrative) {
    bypassDirect = true;
    bypassSpecialized = true;
}

boolean isAdmin = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_IS_ADMIN));

DirectAnswerResult criticalDirectResult = tryBuildCriticalDirectAnswer(userMessage, forceLlmOnly);
if (criticalDirectResult != null) {
    int meterCount = epms.util.AgentDirectResultHelper.countDistinctMeterIds(criticalDirectResult.dbContext);
    criticalDirectResult.answer = epms.util.AgentResponseFlowHelper.finalizeDirectAnswer(criticalDirectResult.answer, criticalDirectResult.dbContext, meterCount);
    String userDbContext = epms.util.AgentUserContextHelper.buildUserContext(criticalDirectResult.dbContext);
    epms.util.AgentOutputHelper.writeSuccessJson(out, response, criticalDirectResult.answer, isAdmin ? criticalDirectResult.dbContext : "", userDbContext, isAdmin);
    return;
}

DirectAnswerResult directResult = tryBuildDirectAnswer(userMessage, bypassDirect);
if (directResult != null) {
    int meterCount = epms.util.AgentDirectResultHelper.countDistinctMeterIds(directResult.dbContext);
    directResult.answer = epms.util.AgentResponseFlowHelper.finalizeDirectAnswer(directResult.answer, directResult.dbContext, meterCount);
    String userDbContext = epms.util.AgentUserContextHelper.buildUserContext(directResult.dbContext);
    epms.util.AgentOutputHelper.writeSuccessJson(out, response, directResult.answer, isAdmin ? directResult.dbContext : "", userDbContext, isAdmin);
    return;
}

if (forceRuleOnly) {
    String directDbContext = "[Rule mode] no direct match";
    String userDbContext = epms.util.AgentUserContextHelper.buildUserContext(directDbContext);
    epms.util.AgentOutputHelper.writeSuccessJson(
        out,
        response,
        epms.util.AgentResponseFlowHelper.buildRuleOnlyFallbackMessage(),
        isAdmin ? directDbContext : "",
        userDbContext,
        isAdmin
    );
    return;
}

epms.util.AgentRuntimeModels.RuntimeModelSelection runtimeModels =
    epms.util.AgentRuntimeFlowSupport.resolveRuntimeModels(application, DEFAULT_SCHEMA_CACHE_TTL_MS);
applySchemaCacheTtl(runtimeModels.schemaCacheTtlMs);

try {
    try {
        epms.util.AgentRuntimeFlowSupport.validateAvailableModels(runtimeModels);
    } catch (IllegalArgumentException e) {
        epms.util.AgentOutputHelper.writeErrorJson(out, response, 400, e.getMessage());
        return;
    } catch (Exception e) {
        epms.util.AgentOutputHelper.writeErrorJson(out, response, 502, "Cannot reach Ollama");
        return;
    }

    Integer requestedMeterId = epms.util.AgentQueryExtractSupport.extractMeterId(userMessage);
    if (requestedMeterId == null) {
        requestedMeterId = epms.util.AgentDbTools.resolveMeterIdByName(epms.util.AgentQueryExtractSupport.extractMeterNameToken(userMessage));
    }
    AgentRequestContext reqCtx = epms.util.AgentRequestSupport.buildRequestContext(
        requestedMeterId,
        epms.util.AgentQueryExtractSupport.extractMeterScopeToken(userMessage),
        epms.util.AgentQueryExtractSupport.extractAlarmAreaToken(userMessage),
        findScopeTokensFromMeterMaster(userMessage, 4),
        epms.util.AgentQueryExtractSupport.extractMonth(userMessage),
        epms.util.AgentQueryRouterCompat.wantsPerMeterPowerSummary(userMessage),
        epms.util.AgentQueryIntentSupport.wantsMeterListSummary(userMessage),
        epms.util.AgentQueryRouterCompat.wantsPhaseCurrentValue(userMessage),
        epms.util.AgentQueryRouterCompat.wantsPhaseVoltageValue(userMessage),
        epms.util.AgentQueryRouterCompat.wantsLineVoltageValue(userMessage),
        epms.util.AgentQueryRouterCompat.wantsHarmonicSummary(userMessage),
        epms.util.AgentQueryExtractSupport.extractPanelTokens(userMessage),
        epms.util.AgentQueryExtractSupport.extractPhaseLabel(userMessage),
        epms.util.AgentQueryExtractSupport.extractLinePairLabel(userMessage)
    );
    AgentExecutionContext execCtx = epms.util.AgentExecutionSupport.buildExecutionContext(
        reqCtx,
        epms.util.AgentQueryExtractSupport.extractTopN(userMessage, 10, 50),
        epms.util.AgentQueryRouterCompat.wantsMeterSummary(userMessage),
        epms.util.AgentQueryIntentSupport.wantsAlarmSummary(userMessage),
        epms.util.AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
        runtimeModels.coderModel.equals(
            epms.util.AgentRuntimeFlowSupport.routeCoderModel(
                userMessage,
                runtimeModels.model,
                runtimeModels.coderModel
            )
        )
    );
    if (forceAiNarrative) {
        epms.util.AgentExecutionSupport.clearDbNeeds(execCtx);
    }
    String schemaContext = getSchemaContextCached();

    // Stage 1: qwen2.5:14b classifies whether DB lookup is required.
    String classifierRaw = "{}";
    if (!forceAiNarrative) {
        classifierRaw = epms.util.AgentRuntimeFlowSupport.classifyNeedsDb(userMessage, runtimeModels);
        String cPanel = epms.util.AgentSupport.extractJsonStringField(classifierRaw, "panel");
        epms.util.AgentExecutionSupport.applyClassifierHints(
            execCtx,
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_db"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_meter"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_alarm"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_frequency"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_power_by_meter"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_meter_list"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_phase_current"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_phase_voltage"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_line_voltage"),
            epms.util.AgentSupport.extractJsonBoolField(classifierRaw, "needs_harmonic"),
            epms.util.AgentSupport.extractJsonIntField(classifierRaw, "meter_id"),
            epms.util.AgentSupport.extractJsonIntField(classifierRaw, "month"),
            epms.util.AgentSupport.extractJsonStringField(classifierRaw, "meter_scope"),
            epms.util.AgentSupport.extractJsonStringField(classifierRaw, "phase"),
            epms.util.AgentSupport.extractJsonStringField(classifierRaw, "line_pair"),
            (cPanel == null || cPanel.trim().isEmpty()) ? Collections.<String>emptyList() : epms.util.AgentSupport.panelTokensFromRaw(cPanel),
            epms.util.AgentQueryRouterCompat.wantsPerMeterPowerSummary(userMessage),
            epms.util.AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
            findScopeTokensFromMeterMaster(userMessage, 4)
        );
    }

    PlannerExecutionResult plannerResult = forceAiNarrative
        ? new PlannerExecutionResult()
        : executePlannerAndLoadContexts(
            execCtx,
            userMessage,
            classifierRaw,
            schemaContext,
            runtimeModels.ollamaUrl,
            runtimeModels.coderModel,
            runtimeModels.ollamaConnectTimeoutMs,
            runtimeModels.ollamaReadTimeoutMs
        );
    String dbContext = epms.util.AgentPlannerContextSupport.buildDbContext(
        execCtx.needsDb,
        execCtx.needsHarmonic,
        epms.util.AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
        plannerResult
    );

    SpecializedAnswerResult specializedAnswer = null;
    if (!bypassSpecialized) {
        specializedAnswer = new SpecializedAnswerResult();
        String harmonicAnswer = epms.util.AgentDirectPowerHelper.harmonic(plannerResult.harmonicCtx, execCtx.requestedMeterId).answer;
        String frequencyAnswer = epms.util.AgentDirectPowerHelper.frequency(plannerResult.frequencyCtx, execCtx.requestedMeterId, execCtx.requestedMonth).answer;
        String powerAnswer = epms.util.AgentAnswerFormatter.buildPerMeterPowerDirectAnswer(plannerResult.powerCtx);
        String meterListUserContext = epms.util.AgentUserContextHelper.buildUserContext(plannerResult.meterListCtx);
        String phaseCurrentUserContext = epms.util.AgentUserContextHelper.buildUserContext(plannerResult.phaseCurrentCtx);
        String phaseVoltageUserContext = epms.util.AgentUserContextHelper.buildUserContext(plannerResult.phaseVoltageCtx);
        String lineVoltageUserContext = epms.util.AgentUserContextHelper.buildUserContext(plannerResult.lineVoltageCtx);
        specializedAnswer.answer = epms.util.AgentSpecializedAnswerHelper.chooseAnswer(
            execCtx.forceCoderFlow,
            execCtx.needsHarmonic,
            execCtx.needsFrequency,
            execCtx.needsPerMeterPower,
            execCtx.needsMeterList,
            execCtx.needsPhaseCurrent,
            execCtx.needsPhaseVoltage,
            execCtx.needsLineVoltage,
            plannerResult.harmonicCtx,
            plannerResult.frequencyCtx,
            plannerResult.powerCtx,
            plannerResult.meterListCtx,
            plannerResult.phaseCurrentCtx,
            plannerResult.phaseVoltageCtx,
            plannerResult.lineVoltageCtx,
            harmonicAnswer,
            frequencyAnswer,
            powerAnswer,
            meterListUserContext,
            phaseCurrentUserContext,
            phaseVoltageUserContext,
            lineVoltageUserContext
        );
        if (specializedAnswer.answer == null) {
            specializedAnswer = null;
        }
    }
    if (specializedAnswer != null) {
        String userDbContext = epms.util.AgentUserContextHelper.buildUserContext(dbContext);
        epms.util.AgentOutputHelper.writeSuccessJson(out, response, specializedAnswer.answer, isAdmin ? dbContext : "", userDbContext, isAdmin);
        return;
    }

    // Stage 3: qwen2.5:14b creates final user-facing answer.
    String finalAnswer = epms.util.AgentRuntimeFlowSupport.generateFinalAnswer(
        userMessage,
        dbContext,
        execCtx.needsDb,
        runtimeModels
    );
    String userDbContext = epms.util.AgentUserContextHelper.buildUserContext(dbContext);
    epms.util.AgentOutputHelper.writeSuccessJson(out, response, finalAnswer, isAdmin ? dbContext : "", userDbContext, isAdmin);

} catch (Exception e) {
    epms.util.AgentOutputHelper.writeErrorJson(out, response, 500, e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "Unknown"));
}
%>
