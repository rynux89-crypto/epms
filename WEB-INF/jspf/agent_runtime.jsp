﻿<%@ page import="java.io.*,java.net.*,java.util.*,java.sql.*,javax.naming.*,javax.sql.*" trimDirectiveWhitespaces="true" %>
<%@ page contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="epms.util.AgentRuntimeModels.AgentRequestContext,epms.util.AgentRuntimeModels.DirectAnswerRequest,epms.util.AgentRuntimeModels.DirectAnswerResult,epms.util.AgentRuntimeModels.AgentExecutionContext,epms.util.AgentRuntimeModels.PlannerExecutionResult,epms.util.AgentRuntimeModels.SpecializedAnswerResult" %>

<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
response.setContentType("application/json;charset=UTF-8");
%>

<%!
private static final String DB_JNDI_NAME = "java:comp/env/jdbc/epms";
private static final Object SCHEMA_CACHE_LOCK = new Object();
private static final long DEFAULT_SCHEMA_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final Object METER_SCOPE_CACHE_LOCK = new Object();
private static final Object USAGE_TYPE_CACHE_LOCK = new Object();
private static final Object USAGE_ALIAS_CACHE_LOCK = new Object();
private static final Object BUILDING_NAME_CACHE_LOCK = new Object();
private static final Object BUILDING_ALIAS_CACHE_LOCK = new Object();
private static final long DEFAULT_METER_SCOPE_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final int SCHEMA_MAX_TABLES = 60;
private static final int SCHEMA_MAX_COLUMNS_PER_TABLE = 40;
private static final int SCHEMA_MAX_CHARS = 16000;
private static volatile String schemaContextCache = "";
private static volatile long schemaContextCacheAt = 0L;
private static volatile long schemaCacheTtlMs = DEFAULT_SCHEMA_CACHE_TTL_MS;
private static volatile List<String> meterScopeValueCache = new ArrayList<String>();
private static volatile List<String> usageTypeValueCache = new ArrayList<String>();
private static volatile Map<String, String> usageAliasMapCache = new LinkedHashMap<String, String>();
private static volatile List<String> buildingNameValueCache = new ArrayList<String>();
private static volatile Map<String, String> buildingAliasMapCache = new LinkedHashMap<String, String>();
private static volatile long meterScopeCacheAt = 0L;
private static volatile long usageTypeCacheAt = 0L;
private static volatile long usageAliasCacheAt = 0L;
private static volatile long buildingNameCacheAt = 0L;
private static volatile long buildingAliasCacheAt = 0L;

private Connection openDbConnection() throws Exception {
    InitialContext ic = new InitialContext();
    DataSource ds = (DataSource) ic.lookup(DB_JNDI_NAME);
    return ds.getConnection();
}

private String trimToNull(String s) {
    return epms.util.AgentSupport.trimToNull(s);
}

private String normalizeOllamaUrl(String s) {
    return epms.util.AgentSupport.normalizeOllamaUrl(s);
}

private Integer parsePositiveInt(String s) {
    return epms.util.AgentSupport.parsePositiveInt(s);
}

private Properties loadAgentModelConfig(javax.servlet.ServletContext app) {
    return epms.util.AgentSupport.loadAgentModelConfig(app);
}

private long resolveSchemaCacheTtlMs(Properties modelConfig) {
    return epms.util.AgentSupport.resolveSchemaCacheTtlMs(modelConfig, DEFAULT_SCHEMA_CACHE_TTL_MS);
}

private void applySchemaCacheTtl(long nextTtlMs) {
    long prevTtlMs = schemaCacheTtlMs;
    schemaCacheTtlMs = nextTtlMs;
    if (prevTtlMs != nextTtlMs) {
        schemaContextCacheAt = 0L;
    }
}

private epms.util.AgentSupport.RuntimeConfig loadAgentRuntimeConfig(javax.servlet.ServletContext app) {
    return epms.util.AgentSupport.loadAgentRuntimeConfig(app, DEFAULT_SCHEMA_CACHE_TTL_MS);
}

private String resolveSpecializedModel(javax.servlet.ServletContext app, String propertyName, String envName, String fallbackModel) {
    return epms.util.AgentRuntimeFlowSupport.resolveSpecializedModel(app, propertyName, envName, fallbackModel);
}

private epms.util.AgentSupport.HttpResponse callOllamaEndpoint(String url, String method, String payload, int connectTimeoutMs, int readTimeoutMs) throws Exception {
    return epms.util.AgentSupport.callOllamaEndpoint(url, method, payload, connectTimeoutMs, readTimeoutMs);
}

private String routeFinalModel(String userMessage, String defaultModel, String aiModel, String pqModel, String alarmModel) {
    return epms.util.AgentRuntimeFlowSupport.routeFinalModel(userMessage, defaultModel, aiModel, pqModel, alarmModel);
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
        extractMeterId(userMessage) != null
        || trimToNull(extractMeterNameToken(userMessage)) != null
        || (extractPanelTokens(userMessage) != null && !extractPanelTokens(userMessage).isEmpty())
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
        extractTimeWindow(userMessage) != null
        || extractMonth(userMessage) != null;
    return asksEnergy && asksCurrent && !hasTarget && !hasPeriod;
}

private String fetchOllamaTagList(String ollamaUrl, int connectTimeoutMs, int readTimeoutMs) throws Exception {
    return epms.util.AgentSupport.fetchOllamaTagList(ollamaUrl, connectTimeoutMs, readTimeoutMs);
}

private AgentRequestContext buildAgentRequestContext(String userMessage) {
    Integer requestedMeterId = extractMeterId(userMessage);
    if (requestedMeterId == null) {
        requestedMeterId = resolveMeterIdByName(extractMeterNameToken(userMessage));
    }
    return epms.util.AgentRequestSupport.buildRequestContext(
        requestedMeterId,
        extractMeterScopeToken(userMessage),
        extractAlarmAreaToken(userMessage),
        findScopeTokensFromMeterMaster(userMessage, 4),
        extractMonth(userMessage),
        routedWantsPerMeterPowerSummary(userMessage),
        routedWantsMeterListSummary(userMessage),
        routedWantsPhaseCurrentValue(userMessage),
        routedWantsPhaseVoltageValue(userMessage),
        routedWantsLineVoltageValue(userMessage),
        routedWantsHarmonicSummary(userMessage),
        extractPanelTokens(userMessage),
        extractPhaseLabel(userMessage),
        extractLinePairLabel(userMessage)
    );
}

private DirectAnswerResult tryBuildDirectAnswer(String userMessage, boolean forceLlmOnly) throws Exception {
    if (forceLlmOnly) return null;

    String directIntentText = normalizeForIntent(userMessage);
    Integer directMeterId = extractMeterId(userMessage);
    if (directMeterId == null) {
        directMeterId = resolveMeterIdByName(extractMeterNameToken(userMessage));
    }
    TimeWindow directWindow = extractTimeWindow(userMessage);
    List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
    List<String> directPanelTokens = extractPanelTokens(userMessage);
    if (routedWantsPanelLatestStatus(userMessage) && (directPanelTokens == null || directPanelTokens.isEmpty())) {
        directPanelTokens = extractPanelTokensLoose(userMessage);
    }
    DirectAnswerRequest directReq = epms.util.AgentRequestSupport.buildDirectAnswerRequest(
        directIntentText,
        routedWantsTripAlarmOnly(userMessage),
        routedWantsAlarmCountSummary(userMessage),
        localWantsAlarmCountSummary(userMessage),
        routedWantsOpenAlarms(userMessage),
        localWantsOpenAlarms(userMessage),
        routedWantsOpenAlarmCountSummary(userMessage),
        localWantsOpenAlarmCountSummary(userMessage),
        localWantsScopedMonthlyEnergySummary(userMessage),
        directMeterId,
        extractMonth(userMessage),
        extractTopN(userMessage, 10, 50),
        extractDays(userMessage, 7, 90),
        extractExplicitDays(userMessage, 90),
        directWindow != null ? directWindow.fromTs : null,
        directWindow != null ? directWindow.toTs : null,
        directWindow != null ? directWindow.label : null,
        extractHzThreshold(userMessage),
        extractPfThreshold(userMessage),
        extractAlarmTypeToken(userMessage),
        extractAlarmAreaToken(userMessage),
        extractMeterScopeToken(userMessage),
        extractScopedAreaTokenFallback(userMessage),
        scopeHints,
        directPanelTokens,
        extractPhaseLabel(userMessage),
        extractLinePairLabel(userMessage),
        routedWantsPanelLatestStatus(userMessage)
    );

    DirectAnswerResult result = new DirectAnswerResult();
    if (directReq.directPfStandard) {
        result.dbContext = "[PF standard] IEEE";
        result.answer = buildPowerFactorStandardDirectAnswer(userMessage);
    } else if (isBareEnergyValueQuestion(userMessage)) {
        result.dbContext = "[Energy value] target required";
        result.answer = "전력량을 조회할 대상이 필요합니다. 예: 1번 계측기의 현재 전력량은?, EAST_VCB_MAIN의 현재 전력량은?";
    } else if (directReq.directScopedMonthlyEnergyIntent) {
        result.dbContext = getScopedMonthlyEnergyContext(directReq.directMeterScopeToken, directReq.directMonth);
        result.answer = buildScopedMonthlyEnergyDirectAnswer(result.dbContext);
    } else if (routedWantsVoltageAverageSummary(userMessage)) {
        Integer daysFallback = (directReq.directFromTs == null ? directReq.directExplicitDays : null);
        return epms.util.AgentDirectPowerHelper.voltageAverage(
            getVoltageAverageContext(directReq.directMeterId, directReq.directPanelTokens, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, daysFallback),
            directReq.directMeterId
        );
    } else if (routedWantsMonthlyFrequencySummary(userMessage)) {
        return epms.util.AgentDirectPowerHelper.frequency(
            getMonthlyAvgFrequencyContext(directReq.directMeterId, directReq.directMonth),
            directReq.directMeterId,
            directReq.directMonth
        );
    } else if (routedWantsMonthlyPeakPower(userMessage)) {
        return epms.util.AgentDirectPowerHelper.monthlyPeak(
            getMonthlyPeakPowerContext(directReq.directMeterId, directReq.directMonth)
        );
    } else if (routedWantsMonthlyPowerStats(userMessage)) {
        return epms.util.AgentDirectPowerHelper.monthlyPowerStats(
            getMonthlyPowerStatsContext(directReq.directMeterId, directReq.directMonth)
        );
    } else if (routedWantsBuildingPowerTopN(userMessage)) {
        return epms.util.AgentDirectPowerHelper.buildingPowerTop(
            getBuildingPowerTopNContext(directReq.directMonth, directReq.directTopN)
        );
    } else if (routedWantsVoltagePhaseAngle(userMessage)) {
        String ctx = getVoltagePhaseAngleContext(directReq.directMeterId);
        return epms.util.AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), "전압 위상각을 조회했습니다.");
    } else if (routedWantsReactiveEnergyValue(userMessage)) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectPowerHelper.energyDelta(
                getEnergyDeltaContext(directReq.directMeterId, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, true),
                true
            );
        } else {
            return epms.util.AgentDirectPowerHelper.energyValue(
                getLatestEnergyContext(directReq.directMeterId, directReq.directPanelTokens),
                true
            );
        }
    } else if (routedWantsEnergyValue(userMessage)) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectPowerHelper.energyDelta(
                getEnergyDeltaContext(directReq.directMeterId, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, false),
                false
            );
        } else {
            return epms.util.AgentDirectPowerHelper.energyValue(
                getLatestEnergyContext(directReq.directMeterId, directReq.directPanelTokens),
                false
            );
        }
    } else if (routedWantsActivePowerValue(userMessage)) {
        return epms.util.AgentDirectPowerHelper.powerValue(
            getRecentMeterContext(directReq.directMeterId, directReq.directPanelTokens),
            false
        );
    } else if (routedWantsReactivePowerValue(userMessage)) {
        return epms.util.AgentDirectPowerHelper.powerValue(
            getRecentMeterContext(directReq.directMeterId, directReq.directPanelTokens),
            true
        );
    } else if (routedWantsCurrentPhaseAngle(userMessage)) {
        String ctx = getCurrentPhaseAngleContext(directReq.directMeterId);
        return epms.util.AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), "전류 위상각을 조회했습니다.");
    } else if (routedWantsPhaseCurrentValue(userMessage)) {
        String ctx = getPhaseCurrentContext(directReq.directMeterId, directReq.directPhaseLabel);
        return epms.util.AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), "상전류를 조회했습니다.");
    } else if (routedWantsPhaseVoltageValue(userMessage)) {
        String ctx = getPhaseVoltageContext(directReq.directMeterId, directReq.directPhaseLabel);
        return epms.util.AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), "상전압을 조회했습니다.");
    } else if (routedWantsLineVoltageValue(userMessage)) {
        String ctx = getLineVoltageContext(directReq.directMeterId, directReq.directLinePairLabel);
        return epms.util.AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), "선간전압을 조회했습니다.");
    } else if (localWantsUsageMeterCountSummary(userMessage)) {
        String usageCountToken = extractUsageTokenFallback(userMessage);
        if (usageCountToken == null && normalizeForIntent(userMessage).contains("비상")) {
            usageCountToken = "비상";
        }
        result.dbContext = getMeterCountContext(usageCountToken);
        result.answer = epms.util.AgentDirectAnswerHelper.buildUsageMeterCountAnswer(result.dbContext, usageCountToken);
    } else if (routedWantsMeterCountSummary(userMessage) && !directReq.directAlarmCountIntent && !directReq.directOpenAlarmCountIntent) {
        String meterCountIntent = normalizeForIntent(userMessage);
        String meterCountScopeToken = shouldTreatAsGlobalMeterCount(userMessage, directReq.directMeterScopeToken) ? null : directReq.directMeterScopeToken;
        if (meterCountIntent.contains("시스템의계측기수") || meterCountIntent.contains("이시스템의계측기수")) {
            meterCountScopeToken = null;
        }
        result.dbContext = getMeterCountContext(meterCountScopeToken);
        result.answer = epms.util.AgentDirectAnswerHelper.buildMeterCountAnswer(result.dbContext);
    } else if (localWantsUsageMeterTopSummary(userMessage)) {
        result.dbContext = getUsageMeterTopNContext(directReq.directTopN);
        result.answer = buildUsageMeterTopDirectAnswer(result.dbContext);
    } else if (routedWantsUsageTypeListSummary(userMessage) || localWantsUsageTypeListSummary(userMessage)) {
        result.dbContext = getUsageTypeListContext(directReq.directTopN);
        result.answer = buildUsageTypeListDirectAnswer(result.dbContext);
    } else if (routedWantsMeterListSummary(userMessage) && !directReq.directAlarmCountIntent && !directReq.directOpenAlarmCountIntent) {
        String ctx = getMeterListContext(directReq.directMeterScopeToken, directReq.directTopN);
        return epms.util.AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), "계측기 목록을 조회했습니다.");
    } else if (routedWantsBuildingCountSummary(userMessage)) {
        result.dbContext = getBuildingCountContext();
        result.answer = epms.util.AgentDirectAnswerHelper.buildBuildingCountAnswer(result.dbContext);
    } else if (routedWantsUsageTypeCountSummary(userMessage)) {
        result.dbContext = getUsageTypeCountContext();
        result.answer = epms.util.AgentDirectAnswerHelper.buildUsageTypeCountAnswer(result.dbContext);
    } else if (routedWantsPanelCountSummary(userMessage)) {
        String panelCountScopeToken = shouldTreatAsGlobalPanelCount(userMessage, directReq.directMeterScopeToken) ? null : directReq.directMeterScopeToken;
        result.dbContext = getPanelCountContext(panelCountScopeToken);
        result.answer = epms.util.AgentDirectAnswerHelper.buildPanelCountAnswer(result.dbContext);
    } else if (routedWantsPanelLatestStatus(userMessage)) {
        result.dbContext = getPanelLatestStatusContext(directReq.directPanelTokens, directReq.directTopN);
        String userCtx = buildUserDbContext(result.dbContext);
        return epms.util.AgentDirectResultHelper.panelLatest(result.dbContext, userCtx);
    } else if (routedWantsAlarmMeterTopN(userMessage)) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectAlarmHelper.alarmMeterTop(
                getAlarmMeterTopNContext(directReq.directDays, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, directReq.directTopN)
            );
        } else {
            return epms.util.AgentDirectAlarmHelper.alarmMeterTop(
                getAlarmMeterTopNContext(directReq.directDays, null, null, null, directReq.directTopN)
            );
        }
    } else if (localWantsUsageAlarmTopSummary(userMessage)) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectAlarmHelper.usageAlarmTop(
                getUsageAlarmTopNContext(directReq.directDays, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, directReq.directTopN)
            );
        } else {
            return epms.util.AgentDirectAlarmHelper.usageAlarmTop(
                getUsageAlarmTopNContext(directReq.directDays, null, null, null, directReq.directTopN)
            );
        }
    } else if (routedWantsAlarmTypeSummary(userMessage)) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectAlarmHelper.alarmType(
                getAlarmTypeSummaryContext(directReq.directDays, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, directReq.directMeterId, directReq.directTripOnly, directReq.directTopN)
            );
        } else {
            return epms.util.AgentDirectAlarmHelper.alarmType(
                getAlarmTypeSummaryContext(directReq.directDays, null, null, null, directReq.directMeterId, directReq.directTripOnly, directReq.directTopN)
            );
        }
    } else if (directReq.directOpenAlarmCountIntent) {
        result.dbContext = getOpenAlarmCountContext(
            directReq.directFromTs,
            directReq.directToTs,
            directReq.directPeriodLabel,
            directReq.directMeterId,
            directReq.directAlarmTypeToken,
            directReq.directAlarmAreaToken
        );
        result.answer = epms.util.AgentDirectAnswerHelper.buildOpenAlarmCountAnswer(result.dbContext);
    } else if (routedWantsAlarmSeveritySummary(userMessage)) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectAlarmHelper.alarmSeverity(
                getAlarmSeveritySummaryContext(directReq.directDays, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel)
            );
        } else {
            return epms.util.AgentDirectAlarmHelper.alarmSeverity(
                getAlarmSeveritySummaryContext(directReq.directDays)
            );
        }
    } else if (directReq.directAlarmCountIntent && extractUsageTokenFallback(userMessage) != null) {
        String usageToken = extractUsageTokenFallback(userMessage);
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectAlarmHelper.usageAlarmCount(
                getUsageAlarmCountContext(usageToken, directReq.directDays, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel)
            );
        } else {
            return epms.util.AgentDirectAlarmHelper.usageAlarmCount(
                getUsageAlarmCountContext(usageToken, directReq.directDays, null, null, null)
            );
        }
    } else if (directReq.directAlarmCountIntent) {
        if (directReq.directFromTs != null) {
            result.dbContext = getAlarmCountContext(directReq.directDays, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel, directReq.directMeterId, directReq.directAlarmTypeToken, directReq.directAlarmAreaToken);
        } else {
            result.dbContext = getAlarmCountContext(directReq.directDays, null, null, null, directReq.directMeterId, directReq.directAlarmTypeToken, directReq.directAlarmAreaToken);
        }
        String userCtx = buildUserDbContext(result.dbContext);
        result.answer = (userCtx == null || userCtx.trim().isEmpty()) ? "알람 건수를 조회했습니다." : userCtx;
    } else if (directReq.directOpenAlarmsIntent) {
        if (directReq.directFromTs != null) {
            return epms.util.AgentDirectAlarmHelper.openAlarms(
                getOpenAlarmsContext(directReq.directTopN, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel)
            );
        } else {
            return epms.util.AgentDirectAlarmHelper.openAlarms(
                getOpenAlarmsContext(directReq.directTopN)
            );
        }
    } else if (routedWantsHarmonicExceed(userMessage)) {
        if (directReq.directFromTs != null) {
            result.dbContext = getHarmonicExceedListContext(null, null, directReq.directTopN, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel);
        } else {
            result.dbContext = getHarmonicExceedListContext(null, null, directReq.directTopN);
        }
        result.answer = buildHarmonicExceedDirectAnswer(result.dbContext);
    } else if (routedWantsFrequencyOutlier(userMessage)) {
        if (directReq.directFromTs != null) {
            result.dbContext = getFrequencyOutlierListContext(directReq.directHz, directReq.directTopN, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel);
        } else {
            result.dbContext = getFrequencyOutlierListContext(directReq.directHz, directReq.directTopN);
        }
        result.answer = buildFrequencyOutlierDirectAnswer(result.dbContext);
    } else if (routedWantsVoltageUnbalanceTopN(userMessage)) {
        if (directReq.directFromTs != null) {
            result.dbContext = getVoltageUnbalanceTopNContext(directReq.directTopN, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel);
        } else {
            result.dbContext = getVoltageUnbalanceTopNContext(directReq.directTopN);
        }
        result.answer = buildVoltageUnbalanceTopDirectAnswer(result.dbContext);
    } else if (routedWantsPowerFactorOutlier(userMessage)) {
        if (directReq.directFromTs != null) {
            result.dbContext = getPowerFactorOutlierListContext(directReq.directPf, directReq.directTopN, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel);
        } else {
            result.dbContext = getPowerFactorOutlierListContext(directReq.directPf, directReq.directTopN);
        }
        int pfNoSignalCount = directReq.directFromTs != null
            ? getPowerFactorNoSignalCount(directReq.directFromTs, directReq.directToTs)
            : getPowerFactorNoSignalCount();
        result.answer = buildPowerFactorOutlierDirectAnswer(result.dbContext, pfNoSignalCount);
        if ((result.dbContext.contains("none") || result.dbContext.contains("no data")) && pfNoSignalCount > 0) {
            int noSignalTopN = (directReq.directIntentText.contains("전체") || directReq.directIntentText.contains("전부") || directReq.directIntentText.contains("모두") || directReq.directIntentText.contains("all")) ? 50 : 10;
            String noSignalCtx = directReq.directFromTs != null
                ? getPowerFactorNoSignalListContext(noSignalTopN, directReq.directFromTs, directReq.directToTs, directReq.directPeriodLabel)
                : getPowerFactorNoSignalListContext(noSignalTopN, null, null, null);
            String snippet = buildPowerFactorNoSignalListSnippet(noSignalCtx);
            if (snippet != null && !snippet.trim().isEmpty()) {
                result.answer = result.answer + "\n\n" + snippet.trim();
            }
        }
    } else if (routedWantsHarmonicSummary(userMessage) && !routedWantsHarmonicExceed(userMessage)) {
        return epms.util.AgentDirectPowerHelper.harmonic(
            getHarmonicContext(directReq.directMeterId, directReq.directPanelTokens),
            directReq.directMeterId
        );
    } else if (routedWantsMeterSummary(userMessage) || routedWantsAlarmSummary(userMessage)) {
        boolean needMeterSummary = routedWantsMeterSummary(userMessage);
        boolean needAlarmSummary = routedWantsAlarmSummary(userMessage);
        String meterCtx = needMeterSummary ? getRecentMeterContext(directReq.directMeterId, directReq.directPanelTokens) : "";
        String alarmCtx = needAlarmSummary ? getRecentAlarmContext() : "";
        StringBuilder dbSb = new StringBuilder();
        if (meterCtx != null && !meterCtx.trim().isEmpty()) dbSb.append("Meter: ").append(meterCtx);
        if (alarmCtx != null && !alarmCtx.trim().isEmpty()) {
            if (dbSb.length() > 0) dbSb.append("\n");
            dbSb.append("Alarm: ").append(alarmCtx);
        }
        result.dbContext = dbSb.toString();

        if (result.dbContext == null || result.dbContext.trim().isEmpty()) {
            result.answer = "요청한 조회 결과를 찾지 못했습니다.";
        } else if (result.dbContext.contains("unavailable")) {
            result.answer = "현재 계측/알람 조회를 수행할 수 없습니다.";
        } else if (needMeterSummary && !needAlarmSummary) {
            if (result.dbContext.contains("no data")) {
                result.answer = "요청한 계측 데이터가 없습니다.";
            } else {
                String userCtx = buildUserDbContext(result.dbContext);
                result.answer = (userCtx == null || userCtx.trim().isEmpty())
                    ? "최근 계측값을 조회했습니다."
                    : userCtx;
            }
        } else if (!needMeterSummary && needAlarmSummary) {
            result.answer = epms.util.AgentDirectAlarmHelper.latestAlarms(alarmCtx).answer;
        } else {
            result.answer = buildDirectDbSummary(userMessage, meterCtx, alarmCtx);
            if (result.answer == null || result.answer.trim().isEmpty()) {
                result.answer = "최근 계측값과 알람을 조회했습니다.";
            }
        }
    }

    if (result.answer == null || result.dbContext == null) {
        return null;
    }
    return result;
}

private DirectAnswerResult tryBuildCriticalDirectAnswer(String userMessage, boolean forceLlmOnly) throws Exception {
    if (forceLlmOnly) return null;

    String criticalIntentText = normalizeForIntent(userMessage);
    boolean criticalHasMeterHint =
        extractMeterId(userMessage) != null
        || trimToNull(extractMeterNameToken(userMessage)) != null;
    if (!criticalHasMeterHint && criticalIntentText.contains("전체사용량") && userMessage != null && userMessage.contains("의")) {
        DirectAnswerResult result = new DirectAnswerResult();
        String scopeToken = extractScopedAreaTokenFallback(userMessage);
        result.dbContext = getScopedMonthlyEnergyContext(scopeToken, extractMonth(userMessage));
        result.answer = buildScopedMonthlyEnergyDirectAnswer(result.dbContext);
        return result;
    }

    if (localWantsPanelMonthlyEnergySummary(userMessage)) {
        DirectAnswerResult result = new DirectAnswerResult();
        List<String> panelTokens = extractPanelTokens(userMessage);
        if (panelTokens == null || panelTokens.isEmpty()) {
            panelTokens = extractPanelTokensLoose(userMessage);
        }
        result.dbContext = getPanelMonthlyEnergyContext(panelTokens, extractMonth(userMessage));
        result.answer = buildPanelMonthlyEnergyDirectAnswer(result.dbContext);
        return result;
    }

    if (localWantsUsageMonthlyEnergySummary(userMessage)) {
        DirectAnswerResult result = new DirectAnswerResult();
        String usageToken = extractUsageTokenFallback(userMessage);
        result.dbContext = getUsageMonthlyEnergyContext(usageToken, extractMonth(userMessage));
        result.answer = buildUsageMonthlyEnergyDirectAnswer(result.dbContext);
        return result;
    }

    if (localWantsUsagePowerTopSummary(userMessage)) {
        DirectAnswerResult result = new DirectAnswerResult();
        result.dbContext = getUsagePowerTopNContext(extractMonth(userMessage), extractTopN(userMessage, 5, 20));
        result.answer = buildUsagePowerTopDirectAnswer(result.dbContext);
        return result;
    }

    Integer criticalMonth = extractMonth(userMessage);
    DirectAnswerResult staticCriticalResult = epms.util.AgentCriticalDirectAnswerHelper.tryBuildStaticCriticalAnswer(
        userMessage,
        criticalMonth,
        localWantsHarmonicExceedStandard(userMessage),
        localWantsFrequencyOpsGuide(userMessage),
        localWantsHarmonicOpsGuide(userMessage),
        localWantsUnbalanceOpsGuide(userMessage),
        localWantsVoltageOpsGuide(userMessage),
        localWantsCurrentOpsGuide(userMessage),
        localWantsCommunicationOpsGuide(userMessage),
        localWantsAlarmTrendGuide(userMessage),
        localWantsPeakCauseGuide(userMessage),
        localWantsPowerFactorOpsGuide(userMessage),
        localWantsPowerFactorThreshold(userMessage),
        localWantsEpmsKnowledge(userMessage),
        localWantsFrequencyOutlierStandard(userMessage),
        localWantsMonthlyEnergyUsagePrompt(userMessage),
        localWantsDisplayedVoltageMeaning(userMessage),
        localWantsDisplayedMetricMeaning(userMessage),
        localWantsPowerFactorStandard(userMessage)
    );
    if (staticCriticalResult != null) {
        return staticCriticalResult;
    }

    if (localWantsCurrentUnbalanceCount(userMessage)) {
        DirectAnswerResult result = new DirectAnswerResult();
        TimeWindow directWindow = extractTimeWindow(userMessage);
        String countCtx = (directWindow != null)
            ? getCurrentUnbalanceCountContext(10.0d, directWindow.fromTs, directWindow.toTs, directWindow.label)
            : getCurrentUnbalanceCountContext(10.0d, null, null, null);
        result.dbContext = "";
        result.answer = buildCurrentUnbalanceCountDirectAnswer(countCtx);
        return result;
    }

    if (localWantsHarmonicExceedCount(userMessage)) {
        DirectAnswerResult result = new DirectAnswerResult();
        TimeWindow directWindow = extractTimeWindow(userMessage);
        Integer directTopN = extractTopN(userMessage, 200, 500);
        String countCtx;
        if (directWindow != null) {
            countCtx = getHarmonicExceedListContext(null, null, directTopN, directWindow.fromTs, directWindow.toTs, directWindow.label);
        } else {
            countCtx = getHarmonicExceedListContext(null, null, directTopN);
        }
        result.dbContext = "";
        result.answer = buildHarmonicExceedCountDirectAnswer(countCtx);
        return result;
    }

    if (localWantsScopedMonthlyEnergySummary(userMessage)) {
        DirectAnswerResult result = new DirectAnswerResult();
        List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
        String scopeToken = (scopeHints == null || scopeHints.isEmpty())
            ? extractScopedAreaTokenFallback(userMessage)
            : String.join(",", scopeHints);
        result.dbContext = getScopedMonthlyEnergyContext(scopeToken, criticalMonth);
        result.answer = buildScopedMonthlyEnergyDirectAnswer(result.dbContext);
        return result;
    }

    if (localWantsOpenAlarmCountSummary(userMessage)) {
        String intentText = normalizeForIntent(userMessage);
        boolean tripOnly = localWantsTripAlarmOnly(userMessage);
        String alarmTypeToken = tripOnly ? "TRIP" : extractAlarmTypeToken(userMessage);
        String alarmAreaToken = extractAlarmAreaToken(userMessage);
        if (alarmAreaToken == null || alarmAreaToken.trim().isEmpty()) {
            List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 4);
            if (scopeHints != null && !scopeHints.isEmpty()) {
                alarmAreaToken = String.join(",", scopeHints);
            }
        }
        TimeWindow directWindow = extractTimeWindow(userMessage);
        Integer meterId = extractMeterId(userMessage);
        if (meterId == null) {
            meterId = resolveMeterIdByName(extractMeterNameToken(userMessage));
        }

        DirectAnswerResult result = new DirectAnswerResult();
        result.dbContext = getOpenAlarmCountContext(
            directWindow != null ? directWindow.fromTs : null,
            directWindow != null ? directWindow.toTs : null,
            directWindow != null ? directWindow.label : null,
            meterId,
            alarmTypeToken,
            alarmAreaToken
        );
        if (result.dbContext.contains("unavailable")) {
            result.answer = "현재 열린 알람 수를 조회할 수 없습니다.";
        } else {
            java.util.regex.Matcher cm = java.util.regex.Pattern.compile("count=([0-9]+)").matcher(result.dbContext);
            int count = cm.find() ? Integer.parseInt(cm.group(1)) : 0;
            java.util.regex.Matcher tm = java.util.regex.Pattern.compile("type=([^;]+)").matcher(result.dbContext);
            java.util.regex.Matcher sm = java.util.regex.Pattern.compile("scope=([^;]+)").matcher(result.dbContext);
            String typeLabel = tm.find() ? trimToNull(tm.group(1)) : null;
            String scopeLabel = sm.find() ? trimToNull(sm.group(1)) : null;
            String subject = (typeLabel == null || typeLabel.isEmpty()) ? "열린 알람" : ("열린 " + typeLabel + " 알람");
            result.answer = (scopeLabel == null || scopeLabel.isEmpty())
                ? ("현재 " + subject + "은 총 " + count + "건입니다.")
                : (scopeLabel + " " + subject + "은 총 " + count + "건입니다.");
        }
        return result;
    }

    return null;
}

private AgentExecutionContext buildExecutionContext(String userMessage, AgentRequestContext reqCtx, String model, String coderModel) {
    return epms.util.AgentExecutionSupport.buildExecutionContext(
        reqCtx,
        extractTopN(userMessage, 10, 50),
        routedWantsMeterSummary(userMessage),
        routedWantsAlarmSummary(userMessage),
        routedWantsMonthlyFrequencySummary(userMessage),
        coderModel.equals(routeModel(userMessage, model, coderModel))
    );
}

private void applyClassifierHints(AgentExecutionContext ctx, String userMessage, String classifierRaw) {
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
    List<String> parsedPanelTokens = (cPanel == null || cPanel.trim().isEmpty()) ? Collections.<String>emptyList() : panelTokensFromRaw(cPanel);
    epms.util.AgentExecutionSupport.applyClassifierHints(
        ctx,
        cNeedsDb,
        cNeedsMeter,
        cNeedsAlarm,
        cNeedsFrequency,
        cNeedsPower,
        cNeedsMeterList,
        cNeedsPhaseCurrent,
        cNeedsPhaseVoltage,
        cNeedsLineVoltage,
        cNeedsHarmonic,
        cMeterId,
        cMonth,
        cMeterScope,
        cPhase,
        cLinePair,
        parsedPanelTokens,
        routedWantsPerMeterPowerSummary(userMessage),
        routedWantsMonthlyFrequencySummary(userMessage),
        findScopeTokensFromMeterMaster(userMessage, 4)
    );
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
        panelTokensFromRaw(planPanel),
        routedWantsMeterSummary(userMessage),
        routedWantsAlarmSummary(userMessage),
        routedWantsMonthlyFrequencySummary(userMessage),
        routedWantsPerMeterPowerSummary(userMessage),
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
        result.coderDraft = callOllamaOnce(ollamaUrl, coderModel, coderAnswerPrompt, ollamaConnectTimeoutMs, ollamaReadTimeoutMs, 0.2d);
    } else if (!runFlags.anyEnabled()) {
        execCtx.needsDb = false;
    }

    return result;
}

private String buildDbContext(AgentExecutionContext execCtx, PlannerExecutionResult plannerResult, String userMessage) {
    return epms.util.AgentPlannerContextSupport.buildDbContext(
        execCtx.needsDb,
        execCtx.needsHarmonic,
        routedWantsMonthlyFrequencySummary(userMessage),
        plannerResult
    );
}

private SpecializedAnswerResult tryBuildSpecializedAnswer(AgentExecutionContext execCtx, PlannerExecutionResult plannerResult) {
    if (execCtx.forceCoderFlow) return null;
    SpecializedAnswerResult result = new SpecializedAnswerResult();
    String harmonicAnswer = buildHarmonicDirectAnswer(plannerResult.harmonicCtx, execCtx.requestedMeterId);
    String frequencyAnswer = buildFrequencyDirectAnswer(plannerResult.frequencyCtx, execCtx.requestedMeterId, execCtx.requestedMonth);
    String powerAnswer = buildPerMeterPowerDirectAnswer(plannerResult.powerCtx);
    String meterListUserContext = buildUserDbContext(plannerResult.meterListCtx);
    String phaseCurrentUserContext = buildUserDbContext(plannerResult.phaseCurrentCtx);
    String phaseVoltageUserContext = buildUserDbContext(plannerResult.phaseVoltageCtx);
    String lineVoltageUserContext = buildUserDbContext(plannerResult.lineVoltageCtx);
    result.answer = epms.util.AgentSpecializedAnswerHelper.chooseAnswer(
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
    if (result.answer == null) return null;
    return result;
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

private List<String> buildUsageTypeValuesFromDb() {
    LinkedHashSet<String> set = new LinkedHashSet<String>();
    String sql =
        "SELECT DISTINCT LTRIM(RTRIM(ISNULL(usage_type,''))) AS usage_type " +
        "FROM dbo.meters " +
        "WHERE LTRIM(RTRIM(ISNULL(usage_type,''))) <> ''";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String v = trimToNull(rs.getString("usage_type"));
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

private List<String> getUsageTypeValuesCached() {
    long now = System.currentTimeMillis();
    List<String> cached = usageTypeValueCache;
    if (cached != null && !cached.isEmpty() && (now - usageTypeCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
        return cached;
    }
    synchronized (USAGE_TYPE_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        if (usageTypeValueCache != null && !usageTypeValueCache.isEmpty() && (now2 - usageTypeCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
            return usageTypeValueCache;
        }
        List<String> fresh = buildUsageTypeValuesFromDb();
        usageTypeValueCache = fresh == null ? new ArrayList<String>() : fresh;
        usageTypeCacheAt = now2;
        return usageTypeValueCache;
    }
}

private String findUsageTypeFromDb(String userMessage) {
    String msg = normalizeScopeKey(userMessage);
    if (msg.isEmpty()) return null;
    List<String> values = getUsageTypeValuesCached();
    if (values == null || values.isEmpty()) return null;
    for (int i = 0; i < values.size(); i++) {
        String v = values.get(i);
        String nv = normalizeScopeKey(v);
        if (nv.length() < 2) continue;
        if (msg.contains(nv)) return v;
    }
    return null;
}

private Map<String, String> buildUsageAliasMapFromDb() {
    LinkedHashMap<String, String> out = new LinkedHashMap<String, String>();
    String sql =
        "SELECT LTRIM(RTRIM(ISNULL(alias_keyword,''))) AS alias_keyword, " +
        "       LTRIM(RTRIM(ISNULL(usage_type,''))) AS usage_type " +
        "FROM dbo.usage_type_alias " +
        "WHERE LTRIM(RTRIM(ISNULL(alias_keyword,''))) <> '' " +
        "  AND LTRIM(RTRIM(ISNULL(usage_type,''))) <> '' " +
        "  AND ISNULL(is_active, 1) = 1";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String alias = trimToNull(rs.getString("alias_keyword"));
                String usageType = trimToNull(rs.getString("usage_type"));
                if (alias == null || usageType == null) continue;
                String key = normalizeScopeKey(alias);
                if (key.length() < 2) continue;
                out.put(key, usageType);
            }
        }
    } catch (Exception ignore) {
    }
    return out;
}

private Map<String, String> getUsageAliasMapCached() {
    long now = System.currentTimeMillis();
    Map<String, String> cached = usageAliasMapCache;
    if (cached != null && !cached.isEmpty() && (now - usageAliasCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
        return cached;
    }
    synchronized (USAGE_ALIAS_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        if (usageAliasMapCache != null && !usageAliasMapCache.isEmpty() && (now2 - usageAliasCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
            return usageAliasMapCache;
        }
        Map<String, String> fresh = buildUsageAliasMapFromDb();
        usageAliasMapCache = fresh == null ? new LinkedHashMap<String, String>() : fresh;
        usageAliasCacheAt = now2;
        return usageAliasMapCache;
    }
}

private String findUsageAliasFromDb(String userMessage) {
    String msg = normalizeScopeKey(userMessage);
    if (msg.isEmpty()) return null;
    Map<String, String> aliasMap = getUsageAliasMapCached();
    if (aliasMap == null || aliasMap.isEmpty()) return null;
    String bestUsage = null;
    int bestLen = -1;
    for (Map.Entry<String, String> e : aliasMap.entrySet()) {
        String alias = e.getKey();
        if (alias == null || alias.length() < 2) continue;
        if (msg.contains(alias) && alias.length() > bestLen) {
            bestUsage = e.getValue();
            bestLen = alias.length();
        }
    }
    return trimToNull(bestUsage);
}

private List<String> buildBuildingNameValuesFromDb() {
    LinkedHashSet<String> set = new LinkedHashSet<String>();
    String sql =
        "SELECT DISTINCT LTRIM(RTRIM(ISNULL(building_name,''))) AS building_name " +
        "FROM dbo.meters " +
        "WHERE LTRIM(RTRIM(ISNULL(building_name,''))) <> ''";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String v = trimToNull(rs.getString("building_name"));
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

private List<String> getBuildingNameValuesCached() {
    long now = System.currentTimeMillis();
    List<String> cached = buildingNameValueCache;
    if (cached != null && !cached.isEmpty() && (now - buildingNameCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
        return cached;
    }
    synchronized (BUILDING_NAME_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        if (buildingNameValueCache != null && !buildingNameValueCache.isEmpty() && (now2 - buildingNameCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
            return buildingNameValueCache;
        }
        List<String> fresh = buildBuildingNameValuesFromDb();
        buildingNameValueCache = fresh == null ? new ArrayList<String>() : fresh;
        buildingNameCacheAt = now2;
        return buildingNameValueCache;
    }
}

private String findBuildingNameFromDb(String userMessage) {
    String msg = normalizeScopeKey(userMessage);
    if (msg.isEmpty()) return null;
    List<String> values = getBuildingNameValuesCached();
    if (values == null || values.isEmpty()) return null;
    for (int i = 0; i < values.size(); i++) {
        String v = values.get(i);
        String nv = normalizeScopeKey(v);
        if (nv.length() < 2) continue;
        if (msg.contains(nv)) return v;
    }
    return null;
}

private Map<String, String> buildBuildingAliasMapFromDb() {
    LinkedHashMap<String, String> out = new LinkedHashMap<String, String>();
    String sql =
        "SELECT LTRIM(RTRIM(ISNULL(alias_keyword,''))) AS alias_keyword, " +
        "       LTRIM(RTRIM(ISNULL(building_name,''))) AS building_name " +
        "FROM dbo.building_alias " +
        "WHERE LTRIM(RTRIM(ISNULL(alias_keyword,''))) <> '' " +
        "  AND LTRIM(RTRIM(ISNULL(building_name,''))) <> '' " +
        "  AND ISNULL(is_active, 1) = 1";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String alias = trimToNull(rs.getString("alias_keyword"));
                String building = trimToNull(rs.getString("building_name"));
                if (alias == null || building == null) continue;
                String key = normalizeScopeKey(alias);
                if (key.length() < 2) continue;
                out.put(key, building);
            }
        }
    } catch (Exception ignore) {
    }
    return out;
}

private Map<String, String> getBuildingAliasMapCached() {
    long now = System.currentTimeMillis();
    Map<String, String> cached = buildingAliasMapCache;
    if (cached != null && !cached.isEmpty() && (now - buildingAliasCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
        return cached;
    }
    synchronized (BUILDING_ALIAS_CACHE_LOCK) {
        long now2 = System.currentTimeMillis();
        if (buildingAliasMapCache != null && !buildingAliasMapCache.isEmpty() && (now2 - buildingAliasCacheAt) < DEFAULT_METER_SCOPE_CACHE_TTL_MS) {
            return buildingAliasMapCache;
        }
        Map<String, String> fresh = buildBuildingAliasMapFromDb();
        buildingAliasMapCache = fresh == null ? new LinkedHashMap<String, String>() : fresh;
        buildingAliasCacheAt = now2;
        return buildingAliasMapCache;
    }
}

private String findBuildingAliasFromDb(String userMessage) {
    String msg = normalizeScopeKey(userMessage);
    if (msg.isEmpty()) return null;
    Map<String, String> aliasMap = getBuildingAliasMapCached();
    if (aliasMap == null || aliasMap.isEmpty()) return null;
    String bestBuilding = null;
    int bestLen = -1;
    for (Map.Entry<String, String> e : aliasMap.entrySet()) {
        String alias = e.getKey();
        if (alias == null || alias.length() < 2) continue;
        if (msg.contains(alias) && alias.length() > bestLen) {
            bestBuilding = e.getValue();
            bestLen = alias.length();
        }
    }
    return trimToNull(bestBuilding);
}

private boolean routedWantsMeterSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsMeterSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsAlarmSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsAlarmSummary", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsAlarmSummary(userMessage);
}

private boolean routedWantsMonthlyFrequencySummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsMonthlyFrequencySummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsMonthlyPeakPower(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsMonthlyPeakPower", userMessage);
    return delegated != null ? delegated.booleanValue() : localWantsMonthlyPeakPower(userMessage);
}

private boolean routedWantsPerMeterPowerSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPerMeterPowerSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsHarmonicSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsHarmonicSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsMeterListSummary(String userMessage) {
    if (userMessage != null) {
        String normalized = userMessage.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
        if (normalized.contains("고조파") || normalized.contains("harmonic") || normalized.contains("thd")
            || normalized.contains("왜형률") || normalized.contains("허형율")) {
            return false;
        }
    }
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsMeterListSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsMeterCountSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsMeterCountSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsPanelCountSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPanelCountSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsBuildingCountSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsBuildingCountSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsUsageTypeCountSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsUsageTypeCountSummary", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) && !hasAlarmIntent(userMessage);
}

private boolean routedWantsUsageTypeListSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsUsageTypeListSummary", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) && !hasAlarmIntent(userMessage);
}

private boolean routedWantsAlarmSeveritySummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsAlarmSeveritySummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsAlarmTypeSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsAlarmTypeSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsAlarmCountSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsAlarmCountSummary", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsAlarmCountSummary(userMessage);
}

private boolean routedWantsOpenAlarms(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsOpenAlarms", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsOpenAlarms(userMessage);
}

private boolean routedWantsOpenAlarmCountSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsOpenAlarmCountSummary", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsOpenAlarmCountSummary(userMessage);
}

private boolean routedWantsAlarmMeterTopN(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsAlarmMeterTopN", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsAlarmMeterTopN(userMessage);
}

private boolean routedWantsBuildingPowerTopN(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsBuildingPowerTopN", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsPanelLatestStatus(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPanelLatestStatus", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsHarmonicExceed(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsHarmonicExceed", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsFrequencyOutlier(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsFrequencyOutlier", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsVoltageUnbalanceTopN(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsVoltageUnbalanceTopN", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsPowerFactorOutlier(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPowerFactorOutlier", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsVoltageAverageSummary(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsVoltageAverageSummary", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsVoltagePhaseAngle(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsVoltagePhaseAngle", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsCurrentPhaseAngle(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsCurrentPhaseAngle", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsPhaseCurrentValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPhaseCurrentValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsActivePowerValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsActivePowerValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsReactivePowerValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsReactivePowerValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsEnergyValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsEnergyValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsReactiveEnergyValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsReactiveEnergyValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsPhaseVoltageValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPhaseVoltageValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsLineVoltageValue(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsLineVoltageValue", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsMonthlyPowerStats(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsMonthlyPowerStats", userMessage);
    return delegated != null ? delegated.booleanValue() : false;
}

private boolean routedWantsPowerFactorStandard(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsPowerFactorStandard", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsPowerFactorStandard(userMessage);
}

private boolean routedWantsTripAlarmOnly(String userMessage) {
    Boolean delegated = invokeAgentQueryRouterBoolean("wantsTripAlarmOnly", userMessage);
    return (delegated != null ? delegated.booleanValue() : false) || localWantsTripAlarmOnly(userMessage);
}

private boolean localWantsAlarmCountSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("\uACBD\uBCF4") || m.contains("alarm");
    boolean hasCount = m.contains("\uAC74\uC218") || m.contains("\uAC1C\uC218") || m.contains("\uAC2F\uC218")
        || m.contains("count") || m.contains("\uBA87\uAC74") || m.contains("\uBA87\uAC1C")
        || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC");
    boolean hasOccurred = m.contains("\uBC1C\uC0DD");
    return hasAlarm && (hasCount || hasOccurred || m.endsWith("\uC218\uB294?") || m.endsWith("\uC218?"));
}

private boolean localWantsUsageMeterCountSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    String usageToken = extractUsageTokenFallback(userMessage);
    boolean hasUsageToken = usageToken != null && !usageToken.trim().isEmpty();
    if (!hasUsageToken && !(m.contains("비상") || m.contains("비상전원"))) {
        return false;
    }
    boolean hasCount =
        m.contains("수는") || m.contains("몇개") || m.contains("개수") || m.contains("갯수")
        || m.contains("count") || m.endsWith("수") || m.endsWith("수는");
    boolean hasExcludedIntent =
        m.contains("알람") || m.contains("경보") || m.contains("목록") || m.contains("리스트")
        || m.contains("사용량") || m.contains("전력") || m.contains("피크") || m.contains("top")
        || m.contains("추이") || m.contains("원인") || m.contains("점검");
    return hasCount && !hasExcludedIntent;
}

private boolean localWantsAlarmSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("\uACBD\uBCF4") || m.contains("alarm") || m.contains("alert");
    boolean hasSummaryIntent =
        m.contains("\uD604\uC7AC") || m.contains("\uC0C1\uD0DC") || m.contains("\uCD5C\uADFC") || m.contains("\uCD5C\uC2E0")
        || m.contains("\uC694\uC57D") || m.contains("\uBCF4\uC5EC") || m.contains("\uC54C\uB824") || m.contains("\uBAA9\uB85D");
    return hasAlarm && hasSummaryIntent;
}

private boolean localWantsAlarmTrendGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm") || m.contains("alert");
    boolean hasTrend = m.contains("추이") || m.contains("흐름") || m.contains("경향") || m.contains("trend");
    boolean hasGuideIntent =
        m.contains("원인") || m.contains("점검") || m.contains("순서")
        || m.contains("절차") || m.contains("설명") || m.contains("분석")
        || m.contains("정리");
    return hasAlarm && hasTrend && hasGuideIntent;
}

private boolean localWantsFrequencyOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
    boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("threshold");
    return hasFrequency && hasGuideIntent && !asksThreshold;
}

private boolean localWantsHarmonicOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
    boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("threshold");
    return hasHarmonic && hasGuideIntent && !asksThreshold;
}

private boolean localWantsUnbalanceOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUnbalance = m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
    return hasUnbalance && hasGuideIntent;
}

private boolean localWantsVoltageOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasVoltage = m.contains("전압") || m.contains("voltage");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저")
        || m.contains("떨어") || m.contains("낮");
    boolean hasSimpleValueIntent = m.contains("값") || m.contains("조회") || m.contains("평균");
    return hasVoltage && hasGuideIntent && !hasSimpleValueIntent;
}

private boolean localWantsCurrentOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasCurrent = m.contains("전류") || m.contains("current");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저")
        || m.contains("튀") || m.contains("급변");
    boolean hasSimpleValueIntent = m.contains("값") || m.contains("조회") || m.contains("상전류");
    return hasCurrent && hasGuideIntent && !hasSimpleValueIntent;
}

private boolean localWantsCommunicationOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasComm =
        m.contains("통신") || m.contains("communication") || m.contains("comm")
        || m.contains("무신호") || m.contains("신호없음") || m.contains("데이터안들어옴");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저")
        || m.contains("끊") || m.contains("안됨");
    return hasComm && hasGuideIntent;
}

private boolean localWantsOpenAlarms(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasOpen = m.contains("\uBBF8\uD574\uACB0") || m.contains("\uC5F4\uB9B0") || m.contains("open");
    boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("\uACBD\uBCF4") || m.contains("alarm");
    return hasOpen && hasAlarm;
}

private boolean localWantsOpenAlarmCountSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasOpen = m.contains("\uBBF8\uD574\uACB0") || m.contains("\uC5F4\uB9B0") || m.contains("open");
    return hasOpen && localWantsAlarmCountSummary(userMessage);
}

private boolean localWantsAlarmMeterTopN(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
    boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
    boolean hasRanking =
        m.contains("top") || m.contains("상위") || m.contains("많은") || m.contains("가장많은")
        || m.contains("많이발생") || m.contains("자주") || m.contains("목록")
        || m.contains("보여") || m.contains("알려");
    boolean hasCountHint =
        m.contains("건수") || m.contains("개수") || m.contains("수") || m.contains("발생")
        || m.contains("있는계측기") || m.contains("계측기는") || m.endsWith("계측기") || m.endsWith("계측기는");
    return hasAlarm && hasMeter && hasRanking && hasCountHint;
}

private boolean localWantsMonthlyPeakPower(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPeak = m.contains("피크") || m.contains("peak") || m.contains("최대피크");
    boolean hasPower = m.contains("전력") || m.contains("power") || m.contains("kw");
    boolean hasPeriod = m.contains("월") || m.contains("달") || m.contains("month") || m.contains("이번달") || m.contains("금월");
    return hasPeak && (hasPower || !m.contains("전압")) && hasPeriod;
}

private boolean localWantsPeakCauseGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPeak = m.contains("피크") || m.contains("peak") || m.contains("최대피크");
    boolean hasCauseIntent =
        m.contains("이유") || m.contains("원인") || m.contains("정리")
        || m.contains("설명") || m.contains("해석") || m.contains("분석");
    return hasPeak && hasCauseIntent;
}

private boolean localWantsPowerFactorStandard(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPf = m.contains("\uC5ED\uB960") || m.contains("powerfactor") || m.contains("pf");
    boolean hasStandard = m.contains("\uAE30\uC900") || m.contains("\uAE30\uC900\uCE58") || m.contains("\uD45C\uC900") || m.contains("standard");
    boolean hasIeee = m.contains("ieee");
    return hasPf && hasStandard && hasIeee;
}

private boolean localWantsPowerFactorThreshold(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
    boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("기준치") || m.contains("threshold");
    boolean hasIeee = m.contains("ieee");
    return hasPf && asksThreshold && !hasIeee;
}

private boolean localWantsPowerFactorOpsGuide(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
    boolean hasGuideIntent =
        m.contains("운영자") || m.contains("담당자") || m.contains("알려")
        || m.contains("설명") || m.contains("원인") || m.contains("점검")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
    boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("기준치") || m.contains("threshold");
    return hasPf && hasGuideIntent && !asksThreshold;
}

private boolean localWantsEpmsKnowledge(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean asksEpms =
        m.contains("epms") ||
        m.contains("이에프엠에스") ||
        m.contains("전력감시") ||
        m.contains("에너지관리");
    boolean asksKnowledge =
        m.contains("잘알아") ||
        m.contains("알아") ||
        m.contains("무슨시스템") ||
        m.contains("뭐하는시스템") ||
        m.contains("설명해");
    return asksEpms && asksKnowledge;
}

private boolean localWantsFrequencyOutlierStandard(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
    boolean asksStandard = m.contains("기준") || m.contains("임계치") || m.contains("어떻게판단") || m.contains("판단")
        || m.contains("threshold") || m.contains("조건");
    return hasFrequency && asksStandard;
}

private boolean localWantsMonthlyEnergyUsagePrompt(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasEnergy =
        m.contains("\uC804\uB825\uB7C9") || m.contains("\uC0AC\uC6A9\uB7C9") || m.contains("\uB204\uC801")
        || m.contains("kwh") || m.contains("energy");
    boolean hasMonth =
        m.contains("\uC774\uBC88\uB2EC") || m.contains("\uAE08\uC6D4") || m.contains("thismonth")
        || m.contains("\uC6D4\uAC04");
    boolean hasMeterHint =
        extractMeterId(userMessage) != null
        || trimToNull(extractMeterNameToken(userMessage)) != null
        || !extractPanelTokens(userMessage).isEmpty()
        || !extractPanelTokensLoose(userMessage).isEmpty();
    return hasEnergy && hasMonth && !hasMeterHint;
}

private boolean localWantsScopedMonthlyEnergySummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasEnergy =
        m.contains("전력사용량") || m.contains("사용전력") || m.contains("전력량") || m.contains("사용량")
        || m.contains("kwh") || m.contains("energy");
    boolean hasTotal =
        m.contains("전체") || m.contains("총") || m.contains("합계") || m.contains("누적");
    boolean hasMeterHint =
        extractMeterId(userMessage) != null
        || trimToNull(extractMeterNameToken(userMessage)) != null;
    List<String> scopeHints = findScopeTokensFromMeterMaster(userMessage, 1);
    String localScope = extractScopedAreaTokenFallback(userMessage);
    return hasEnergy && hasTotal && !hasMeterHint &&
        ((scopeHints != null && !scopeHints.isEmpty()) || localScope != null);
}

private boolean localWantsPanelMonthlyEnergySummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasPanel = m.contains("패널") || m.contains("panel") || m.contains("판넬");
    boolean hasEnergy =
        m.contains("전력사용량") || m.contains("사용전력") || m.contains("전력량") || m.contains("사용량")
        || m.contains("kwh") || m.contains("energy");
    boolean hasTotal =
        m.contains("전체") || m.contains("총") || m.contains("합계") || m.contains("누적")
        || m.endsWith("은?") || m.endsWith("는?") || m.endsWith("?");
    List<String> panelTokens = extractPanelTokens(userMessage);
    if (panelTokens == null || panelTokens.isEmpty()) panelTokens = extractPanelTokensLoose(userMessage);
    return hasPanel && hasEnergy && hasTotal && panelTokens != null && !panelTokens.isEmpty();
}

private boolean localWantsUsageMonthlyEnergySummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
    boolean hasEnergy =
        m.contains("전력사용량") || m.contains("사용전력") || m.contains("전력량") || m.contains("사용량")
        || m.contains("kwh") || m.contains("energy");
    boolean hasTotal =
        m.contains("전체") || m.contains("총") || m.contains("합계") || m.contains("누적")
        || m.endsWith("은?") || m.endsWith("는?") || m.endsWith("?");
    String usageToken = extractUsageTokenFallback(userMessage);
    return hasUsage && hasEnergy && hasTotal && usageToken != null;
}

private boolean localWantsUsageTypeListSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
    boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
    boolean hasList =
        m.contains("리스트") || m.contains("목록") || m.contains("list")
        || m.contains("종류") || m.contains("항목") || m.contains("보여") || m.contains("알려");
    boolean hasTopIntent =
        m.contains("top") || m.contains("상위") || m.contains("가장많은")
        || m.contains("제일많은") || m.contains("많은");
    boolean hasCount =
        m.contains("몇개") || m.contains("개수") || m.contains("갯수")
        || m.contains("수는") || m.contains("총개수") || m.contains("count");
    boolean hasPowerIntent =
        m.contains("전력") || m.contains("전력량") || m.contains("사용량")
        || m.contains("kwh") || m.contains("kw") || m.contains("power");
    return hasUsage && hasList && !hasAlarm && !hasTopIntent && !hasCount && !hasPowerIntent;
}

private boolean localWantsUsagePowerTopSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUsage = m.contains("용도별") || m.contains("사용처별") || (m.contains("용도") && m.contains("별")) || m.contains("usage");
    boolean hasPower = m.contains("전력") || m.contains("전력량") || m.contains("사용량") || m.contains("kwh") || m.contains("power");
    boolean hasTop = m.contains("top") || m.contains("상위") || m.contains("비교") || m.contains("목록") || m.contains("보여");
    return hasUsage && hasPower && hasTop;
}

private boolean localWantsUsageMeterTopSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
    boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
    boolean hasTop =
        m.contains("가장많은") || m.contains("제일많은") || m.contains("가장많이")
        || m.contains("top") || m.contains("상위") || m.contains("많은");
    boolean hasCountIntent =
        m.contains("가진") || m.contains("보유") || m.contains("몇개") || m.contains("개수")
        || m.contains("갯수") || m.contains("수");
    boolean hasExcludedIntent =
        m.contains("전력") || m.contains("전력량") || m.contains("사용량")
        || m.contains("kwh") || m.contains("kw") || m.contains("power");
    return hasUsage && hasMeter && hasTop && hasCountIntent && !hasExcludedIntent;
}

private boolean localWantsUsageAlarmTopSummary(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
    boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
    boolean hasTop =
        m.contains("가장많은") || m.contains("제일많은") || m.contains("가장많이")
        || m.contains("top") || m.contains("상위") || m.contains("많은")
        || m.contains("목록") || m.contains("보여") || m.contains("알려");
    boolean hasCountIntent =
        m.contains("가진") || m.contains("보유") || m.contains("건수")
        || m.contains("개수") || m.contains("갯수") || m.contains("수")
        || m.endsWith("용도는") || m.endsWith("용도는?") || m.endsWith("용도?");
    return hasUsage && hasAlarm && hasTop && (hasCountIntent || m.contains("상위") || m.contains("top"));
}

private boolean hasAlarmIntent(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return m.contains("알람") || m.contains("경보") || m.contains("alarm");
}

private boolean localWantsHarmonicExceedCount(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
    boolean hasOutlier = m.contains("이상") || m.contains("초과") || m.contains("문제") || m.contains("비정상");
    boolean hasCount = m.contains("총몇개") || m.contains("몇개") || m.contains("몇건") || m.contains("건수")
        || m.contains("개수") || m.contains("갯수") || m.contains("count") || m.contains("총몇");
    return hasHarmonic && hasOutlier && hasCount;
}

private boolean localWantsHarmonicExceedStandard(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
    boolean asksStandard = m.contains("기준") || m.contains("기준값") || m.contains("임계치")
        || m.contains("threshold") || m.contains("조건");
    return hasHarmonic && asksStandard;
}

private boolean localWantsCurrentUnbalanceCount(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasCurrent = m.contains("전류") || m.contains("current");
    boolean hasUnbalance = m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance");
    boolean hasCount = m.contains("수는") || m.contains("몇개") || m.contains("몇건") || m.contains("개수")
        || m.contains("갯수") || m.contains("건수") || m.contains("count") || m.contains("총몇");
    return hasCurrent && hasUnbalance && hasCount;
}

private boolean localWantsDisplayedVoltageMeaning(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean asksVoltageMeaning =
        (m.contains("\uBCF4\uC5EC\uC8FC\uB294\uC804\uC555") || m.contains("\uBCF4\uC5EC\uC900\uC804\uC555") || m.contains("\uC804\uC555\uAC12") || m.contains("\uC804\uC555\uC740") || m.contains("\uC804\uC555\uC774"))
        && (m.contains("\uD3C9\uADE0") || m.contains("\uBB34\uC2A8\uAC12") || m.contains("\uC5B4\uB5A4\uAC12") || m.contains("\uAE30\uC900"));
    boolean asksDisplayedValue =
        (m.contains("\uC9C0\uAE08") || m.contains("\uBC29\uAE08") || m.contains("\uB2C8\uAC00") || m.contains("\uB124\uAC00") || m.contains("\uBCF4\uC5EC\uC900") || m.contains("\uBCF4\uC5EC\uC8FC\uB294"))
        && (m.contains("\uAC12") || m.contains("\uC804\uC555"));
    return asksVoltageMeaning || asksDisplayedValue;
}

private String buildDisplayedVoltageMeaningAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildDisplayedVoltageMeaningAnswer();
}

private boolean localWantsDisplayedMetricMeaning(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean asksContext =
        m.contains("\uC9C0\uAE08") || m.contains("\uBC29\uAE08") || m.contains("\uB2C8\uAC00") || m.contains("\uB124\uAC00")
        || m.contains("\uBCF4\uC5EC\uC900") || m.contains("\uBCF4\uC5EC\uC8FC\uB294");
    boolean asksMeaning =
        m.contains("\uBB34\uC2A8\uAC12") || m.contains("\uC5B4\uB5A4\uAC12") || m.contains("\uAE30\uC900")
        || m.contains("\uC758\uBBF8") || m.contains("\uD3C9\uADE0") || m.contains("\uACC4\uC0B0");
    boolean asksMetric =
        m.contains("\uC804\uB958") || m.contains("\uC5ED\uB960") || m.contains("\uC720\uD6A8\uC804\uB825")
        || m.contains("\uBB34\uD6A8\uC804\uB825") || m.contains("\uC8FC\uD30C\uC218")
        || m.contains("current") || m.contains("pf") || m.contains("powerfactor")
        || m.contains("activepower") || m.contains("reactivepower") || m.contains("frequency");
    return asksMetric && (asksMeaning || asksContext);
}

private boolean localPrefersNarrativeLlm(String userMessage) {
    String m = normalizeForIntent(userMessage);
    boolean hasNarrativeIntent =
        m.contains("해석") || m.contains("설명") || m.contains("요약")
        || m.contains("보고서") || m.contains("분석") || m.contains("평가")
        || m.contains("추론") || m.contains("진단") || m.contains("브리핑")
        || m.contains("알려") || m.contains("안내") || m.contains("체크리스트")
        || m.contains("항목") || m.contains("순서") || m.contains("절차")
        || m.contains("원인") || m.contains("점검");
    boolean hasCombinedIntent =
        (m.contains("계측") || m.contains("상태") || m.contains("측정"))
        && (m.contains("알람") || m.contains("경보"));
    boolean hasQualityOpsIntent =
        (m.contains("역률") || m.contains("powerfactor") || m.contains("pf")
            || m.contains("주파수") || m.contains("frequency")
            || m.contains("고조파") || m.contains("harmonic")
            || m.contains("불평형") || m.contains("unbalance"))
        && (m.contains("운영자") || m.contains("담당자")
            || m.contains("뭐부터") || m.contains("먼저")
            || m.contains("항목") || m.contains("순서")
            || m.contains("절차") || m.contains("점검")
            || m.contains("원인") || m.contains("대응"));
    return (hasNarrativeIntent && hasCombinedIntent) || (hasNarrativeIntent && hasQualityOpsIntent);
}

private String buildDisplayedMetricMeaningAnswer(String userMessage) {
    return epms.util.AgentCriticalDirectAnswerHelper.buildDisplayedMetricMeaningAnswer(userMessage);
}

private boolean localWantsTripAlarmOnly(String userMessage) {
    String m = normalizeForIntent(userMessage);
    return m.contains("\uD2B8\uB9BD") || m.contains("trip") || m.contains("\uD2B8\uB9BC");
}

private String buildPowerFactorStandardDirectAnswer(String userMessage) {
    String delegated = invokeAgentAnswerFormatter(
        "buildPowerFactorStandardDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { userMessage }
    );
    if (delegated != null) return delegated;
    return epms.util.AgentCriticalDirectAnswerHelper.buildPowerFactorStandardDirectAnswer(userMessage);
}

private String buildPowerFactorOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildPowerFactorOpsGuideDirectAnswer();
}

private String buildPeakCauseGuideDirectAnswer(Integer month) {
    return epms.util.AgentCriticalDirectAnswerHelper.buildPeakCauseGuideDirectAnswer(month);
}

private String buildAlarmTrendGuideDirectAnswer(Integer month) {
    return epms.util.AgentCriticalDirectAnswerHelper.buildAlarmTrendGuideDirectAnswer(month);
}

private String buildFrequencyOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildFrequencyOpsGuideDirectAnswer();
}

private String buildHarmonicOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildHarmonicOpsGuideDirectAnswer();
}

private String buildUnbalanceOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildUnbalanceOpsGuideDirectAnswer();
}

private String buildVoltageOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildVoltageOpsGuideDirectAnswer();
}

private String buildCurrentOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildCurrentOpsGuideDirectAnswer();
}

private String buildCommunicationOpsGuideDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildCommunicationOpsGuideDirectAnswer();
}

private String extractPhaseLabel(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractPhaseLabel", new Class<?>[] { String.class }, new Object[] { userMessage });
    return delegated instanceof String ? (String) delegated : null;
}

private String extractLinePairLabel(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractLinePairLabel", new Class<?>[] { String.class }, new Object[] { userMessage });
    return delegated instanceof String ? (String) delegated : null;
}

private String extractAlarmTypeToken(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractAlarmTypeToken", new Class<?>[] { String.class }, new Object[] { userMessage });
    return delegated instanceof String ? (String) delegated : null;
}

private String extractAlarmAreaToken(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractAlarmAreaToken", new Class<?>[] { String.class }, new Object[] { userMessage });
    return delegated instanceof String ? (String) delegated : null;
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

private String extractMeterScopeToken(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractMeterScopeToken", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof String) return (String) delegated;
    return extractScopedAreaTokenFallback(userMessage);
}

private boolean shouldTreatAsGlobalMeterCount(String userMessage, String scopeToken) {
    String m = normalizeForIntent(userMessage);
    boolean asksCount =
        m.contains("계측기수") || m.contains("미터수") || m.contains("metercount")
        || m.contains("총계측기") || m.contains("전체계측기")
        || m.contains("지금계측기의수") || m.contains("현재계측기의수")
        || m.contains("계측기의수") || m.contains("계측기몇개")
        || m.contains("계측기개수") || m.contains("계측기갯수")
        || m.contains("시스템의계측기수") || m.contains("이시스템의계측기수")
        || m.contains("현재시스템의계측기수") || m.contains("지금이시스템의계측기수");
    boolean onlyGenericScope = isGenericGlobalCountScope(scopeToken, new String[] {
        "계측기", "미터", "meter", "시스템", "이시스템", "현재시스템", "지금", "현재"
    });
    boolean hasSpecificScope =
        m.contains("동관") || m.contains("서관") || m.contains("남관") || m.contains("북관")
        || m.contains("건물") || m.contains("패널") || m.contains("panel")
        || m.contains("용도") || m.contains("사용처");
    return asksCount && onlyGenericScope && !hasSpecificScope;
}

private boolean shouldTreatAsGlobalPanelCount(String userMessage, String scopeToken) {
    String m = normalizeForIntent(userMessage);
    boolean asksCount =
        m.contains("패널수") || m.contains("panelcount")
        || m.contains("총패널") || m.contains("전체패널")
        || m.contains("지금패널의수") || m.contains("현재패널의수")
        || m.contains("패널의수") || m.contains("패널몇개")
        || m.contains("패널개수") || m.contains("패널갯수")
        || m.contains("시스템의패널수") || m.contains("이시스템의패널수")
        || m.contains("현재시스템의패널수") || m.contains("지금이시스템의패널수");
    boolean onlyGenericScope = isGenericGlobalCountScope(scopeToken, new String[] {
        "패널", "panel", "판넬", "시스템", "이시스템", "현재시스템", "지금", "현재"
    });
    boolean hasSpecificScope =
        m.contains("동관") || m.contains("서관") || m.contains("남관") || m.contains("북관")
        || m.contains("건물") || m.contains("용도") || m.contains("사용처");
    return asksCount && onlyGenericScope && !hasSpecificScope;
}

private boolean isGenericGlobalCountScope(String scopeToken, String[] genericTokens) {
    String scope = trimToNull(scopeToken);
    if (scope == null) return true;
    java.util.HashSet<String> allowed = new java.util.HashSet<String>();
    for (int i = 0; i < genericTokens.length; i++) {
        allowed.add(genericTokens[i]);
    }
    String[] parts = scope.split("\\s*(?:,|/|\\\\|의|관련|\\s+)\\s*");
    boolean sawToken = false;
    for (int i = 0; i < parts.length; i++) {
        String n = normalizeForIntent(parts[i]);
        if (n == null || n.isEmpty()) continue;
        sawToken = true;
        if (!allowed.contains(n)) return false;
    }
    return true;
}

private String extractScopedAreaTokenFallback(String userMessage) {
    String raw = trimToNull(userMessage);
    if (raw == null) return null;
    String aliasMatched = findBuildingAliasFromDb(raw);
    if (aliasMatched != null) return aliasMatched;
    String dbMatched = findBuildingNameFromDb(raw);
    if (dbMatched != null) return dbMatched;
    java.util.regex.Matcher possessive = java.util.regex.Pattern.compile("([가-힣A-Za-z0-9_\\-]{2,20})\\s*의").matcher(raw);
    while (possessive.find()) {
        String token = trimToNull(possessive.group(1));
        if (token == null) continue;
        String n = normalizeForIntent(token);
        if (n.length() < 2) continue;
        if ("이번달".equals(n) || "금월".equals(n) || "전체".equals(n) || "전력".equals(n) || "사용량".equals(n)) continue;
        return token;
    }
    java.util.regex.Matcher bare = java.util.regex.Pattern.compile("([가-힣A-Za-z0-9_\\-]{2,20})\\s*(관련|전체|전력|사용량)").matcher(raw);
    if (bare.find()) {
        String token = trimToNull(bare.group(1));
        if (token != null && normalizeForIntent(token).length() >= 2) return token;
    }
    return null;
}

private String extractUsageTokenFallback(String userMessage) {
    String raw = trimToNull(userMessage);
    if (raw == null) return null;
    String aliasMatched = findUsageAliasFromDb(raw);
    if (aliasMatched != null) return aliasMatched;
    String dbMatched = findUsageTypeFromDb(raw);
    if (dbMatched != null) return dbMatched;
    String norm = normalizeForIntent(raw);
    if (norm.contains("동력")) return "전열";
    if (norm.contains("조명")) return "전등";
    if (norm.contains("비상전원")) return "비상";
    if (norm.contains("무정전")) return "UPS";
    if (norm.contains("발전기")) return "Generator";
    java.util.regex.Matcher m1 = java.util.regex.Pattern.compile("([가-힣A-Za-z0-9_\\-]{2,20})\\s*용도").matcher(raw);
    if (m1.find()) {
        String token = trimToNull(m1.group(1));
        if (token != null && normalizeForIntent(token).length() >= 2) return token;
    }
    java.util.regex.Matcher m2 = java.util.regex.Pattern.compile("용도\\s*([가-힣A-Za-z0-9_\\-]{2,20})").matcher(raw);
    if (m2.find()) {
        String token = trimToNull(m2.group(1));
        if (token != null && normalizeForIntent(token).length() >= 2) return token;
    }
    return null;
}

private String invokeAgentDbTool(String methodName, Class<?>[] argTypes, Object[] args) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentDbTools");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        Object out = m.invoke(null, args);
        return out == null ? null : String.valueOf(out);
    } catch (Throwable ignore) {
    }
    try {
        Class<?> cls = Class.forName("epms.util.AgentDbToolsCompat");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        Object out = m.invoke(null, args);
        return out == null ? null : String.valueOf(out);
    } catch (Throwable ignore) {
        return null;
    }
}

private Object invokeAgentQueryParser(String methodName, Class<?>[] argTypes, Object[] args) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentQueryParser");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        return m.invoke(null, args);
    } catch (Throwable ignore) {
    }
    try {
        Class<?> cls = Class.forName("epms.util.AgentQueryParserCompat");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        return m.invoke(null, args);
    } catch (Throwable ignore) {
        return null;
    }
}

private Boolean invokeAgentQueryRouterBoolean(String methodName, String userMessage) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentQueryRouter");
        java.lang.reflect.Method m = cls.getMethod(methodName, String.class);
        Object out = m.invoke(null, userMessage);
        if (out instanceof Boolean) return (Boolean) out;
    } catch (Throwable ignore) {
    }
    try {
        Class<?> cls = Class.forName("epms.util.AgentQueryRouterCompat");
        java.lang.reflect.Method m = cls.getMethod(methodName, String.class);
        Object out = m.invoke(null, userMessage);
        if (out instanceof Boolean) return (Boolean) out;
    } catch (Throwable ignore) {
    }
    return null;
}

private Object invokeAgentSpecializedHelper(String methodName, Class<?>[] argTypes, Object[] args) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentSpecializedAnswerHelper");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        return m.invoke(null, args);
    } catch (Throwable ignore) {
        return null;
    }
}

private Object invokeAgentResponseFlowHelper(String methodName, Class<?>[] argTypes, Object[] args) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentResponseFlowHelper");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        return m.invoke(null, args);
    } catch (Throwable ignore) {
        return null;
    }
}

private Object invokeAgentOutputHelper(String methodName, Class<?>[] argTypes, Object[] args) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentOutputHelper");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        return m.invoke(null, args);
    } catch (Throwable ignore) {
        return null;
    }
}

private boolean shouldBypassDirect(boolean forceLlmOnly, boolean preferNarrativeLlm) {
    Object delegated = invokeAgentResponseFlowHelper(
        "shouldBypassDirect",
        new Class<?>[] { boolean.class, boolean.class },
        new Object[] { Boolean.valueOf(forceLlmOnly), Boolean.valueOf(preferNarrativeLlm) }
    );
    return delegated instanceof Boolean
        ? ((Boolean) delegated).booleanValue()
        : (forceLlmOnly || preferNarrativeLlm);
}

private boolean shouldBypassSpecialized(boolean forceLlmOnly, boolean preferNarrativeLlm) {
    Object delegated = invokeAgentResponseFlowHelper(
        "shouldBypassSpecialized",
        new Class<?>[] { boolean.class, boolean.class },
        new Object[] { Boolean.valueOf(forceLlmOnly), Boolean.valueOf(preferNarrativeLlm) }
    );
    return delegated instanceof Boolean
        ? ((Boolean) delegated).booleanValue()
        : (forceLlmOnly || preferNarrativeLlm);
}

private String finalizeDirectAnswer(String answer, String dbContext, int meterCount) {
    Object delegated = invokeAgentResponseFlowHelper(
        "finalizeDirectAnswer",
        new Class<?>[] { String.class, String.class, int.class },
        new Object[] { answer, dbContext, Integer.valueOf(meterCount) }
    );
    if (delegated instanceof String) return (String) delegated;
    boolean skipMeterCountSuffix = dbContext.startsWith("[Alarm count]") || dbContext.startsWith("[Panel latest status]");
    if (!skipMeterCountSuffix && meterCount > 0 && (answer == null || answer.indexOf('\n') < 0)) {
        return answer + " (해당 계측기 " + meterCount + "개)";
    }
    return answer;
}

private String getRuleOnlyFallbackMessage() {
    Object delegated = invokeAgentResponseFlowHelper("buildRuleOnlyFallbackMessage", new Class<?>[0], new Object[0]);
    return delegated instanceof String
        ? (String) delegated
        : "RULE 모드: 직접 규칙에 매칭된 결과가 없습니다. 같은 질문을 /llm 으로 시도해 주세요.";
}

private String buildFinalPrompt(boolean needsDb, String userMessage, String dbContext) {
    return epms.util.AgentRuntimeFlowSupport.buildFinalPrompt(needsDb, userMessage, dbContext);
}

private String buildSuccessJsonPayload(String finalAnswer, String rawDbContext, String userDbContext, boolean isAdmin) {
    Object delegated = invokeAgentOutputHelper(
        "buildSuccessJson",
        new Class<?>[] { String.class, String.class, String.class, boolean.class },
        new Object[] { finalAnswer, rawDbContext, userDbContext, Boolean.valueOf(isAdmin) }
    );
    return delegated instanceof String ? (String) delegated : null;
}

private String buildErrorJsonPayload(String errorMessage) {
    Object delegated = invokeAgentOutputHelper(
        "buildErrorJson",
        new Class<?>[] { String.class },
        new Object[] { errorMessage }
    );
    if (delegated instanceof String) return (String) delegated;
    return "{\"error\":" + jsonEscape(errorMessage) + "}";
}

private String invokeAgentAnswerFormatter(String methodName, Class<?>[] argTypes, Object[] args) {
    try {
        Class<?> cls = Class.forName("epms.util.AgentAnswerFormatter");
        java.lang.reflect.Method m = cls.getMethod(methodName, argTypes);
        Object out = m.invoke(null, args);
        return out == null ? null : String.valueOf(out);
    } catch (Throwable ignore) {
        return null;
    }
}

private String getMeterListContext(String scopeToken, Integer topN) {
    String delegated = invokeAgentDbTool("getMeterListContext", new Class<?>[] { String.class, Integer.class }, new Object[] { scopeToken, topN });
    if (delegated != null) return delegated;
    return localGetMeterListContext(scopeToken, topN);
}

private String localGetMeterListContext(String scopeToken, Integer topN) {
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

private String getMeterCountContext(String scopeToken) {
    String delegated = invokeAgentDbTool("getMeterCountContext", new Class<?>[] { String.class }, new Object[] { scopeToken });
    if (delegated != null) return delegated;
    return localGetMeterCountContext(scopeToken);
}

private String localGetMeterCountContext(String scopeToken) {
    List<String> tokens = splitAlarmAreaTokens(scopeToken);
    StringBuilder sql = new StringBuilder("SELECT COUNT(*) FROM dbo.meters WHERE 1=1 ");
    for (int i = 0; i < tokens.size(); i++) {
        sql.append("AND (UPPER(ISNULL(name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(panel_name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(building_name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(usage_type,'')) LIKE ?) ");
    }
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
            int count = rs.next() ? rs.getInt(1) : 0;
            StringBuilder sb = new StringBuilder("[Meter count]");
            if (tokens != null && !tokens.isEmpty()) sb.append(" scope=").append(String.join(",", tokens));
            sb.append("; count=").append(count);
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Meter count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPanelCountContext(String scopeToken) {
    String delegated = invokeAgentDbTool("getPanelCountContext", new Class<?>[] { String.class }, new Object[] { scopeToken });
    if (delegated != null) return delegated;
    return localGetPanelCountContext(scopeToken);
}

private String localGetPanelCountContext(String scopeToken) {
    List<String> tokens = splitAlarmAreaTokens(scopeToken);
    StringBuilder sql = new StringBuilder(
        "SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ISNULL(panel_name,''))), '')) FROM dbo.meters WHERE LTRIM(RTRIM(ISNULL(panel_name,''))) <> '' "
    );
    for (int i = 0; i < tokens.size(); i++) {
        sql.append("AND (UPPER(ISNULL(name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(panel_name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(building_name,'')) LIKE ? ");
        sql.append("OR UPPER(ISNULL(usage_type,'')) LIKE ?) ");
    }
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
            int count = rs.next() ? rs.getInt(1) : 0;
            StringBuilder sb = new StringBuilder("[Panel count]");
            if (tokens != null && !tokens.isEmpty()) sb.append(" scope=").append(String.join(",", tokens));
            sb.append("; count=").append(count);
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Panel count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getBuildingCountContext() {
    String delegated = invokeAgentDbTool("getBuildingCountContext", new Class<?>[0], new Object[0]);
    if (delegated != null) return delegated;
    return localGetBuildingCountContext();
}

private String localGetBuildingCountContext() {
    String sql = "SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ISNULL(building_name,''))), '')) FROM dbo.meters WHERE LTRIM(RTRIM(ISNULL(building_name,''))) <> ''";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            int count = rs.next() ? rs.getInt(1) : 0;
            return "[Building count]; count=" + count;
        }
    } catch (Exception e) {
        return "[Building count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getUsageTypeCountContext() {
    String delegated = invokeAgentDbTool("getUsageTypeCountContext", new Class<?>[0], new Object[0]);
    if (delegated != null) return delegated;
    return localGetUsageTypeCountContext();
}

private String localGetUsageTypeCountContext() {
    String sql = "SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ISNULL(usage_type,''))), '')) FROM dbo.meters WHERE LTRIM(RTRIM(ISNULL(usage_type,''))) <> ''";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            int count = rs.next() ? rs.getInt(1) : 0;
            return "[Usage count]; count=" + count;
        }
    } catch (Exception e) {
        return "[Usage count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getUsageTypeListContext(Integer topN) {
    String delegated = invokeAgentDbTool("getUsageTypeListContext", new Class<?>[] { Integer.class }, new Object[] { topN });
    if (delegated != null) return delegated;
    return localGetUsageTypeListContext(topN);
}

private String localGetUsageTypeListContext(Integer topN) {
    int n = topN != null ? topN.intValue() : 50;
    if (n < 1) n = 50;
    if (n > 100) n = 100;
    String sql =
        "SELECT TOP " + n + " LTRIM(RTRIM(ISNULL(usage_type,''))) AS usage_type " +
        "FROM dbo.meters " +
        "WHERE LTRIM(RTRIM(ISNULL(usage_type,''))) <> '' " +
        "GROUP BY LTRIM(RTRIM(ISNULL(usage_type,''))) " +
        "ORDER BY LTRIM(RTRIM(ISNULL(usage_type,''))) ASC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Usage type list];");
            int i = 0;
            while (rs.next()) {
                String usageType = trimToNull(rs.getString("usage_type"));
                if (usageType == null) continue;
                i++;
                sb.append(" ").append(i).append(")").append(clip(usageType, 40)).append(";");
            }
            if (i == 0) return "[Usage type list] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Usage type list] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getUsageMeterTopNContext(Integer topN) {
    int n = topN != null ? topN.intValue() : 5;
    if (n < 1) n = 5;
    if (n > 20) n = 20;
    String sql =
        "SELECT TOP " + n + " " +
        "  ISNULL(NULLIF(LTRIM(RTRIM(usage_type)), ''), '미분류') AS usage_type, " +
        "  COUNT(*) AS meter_count " +
        "FROM dbo.meters " +
        "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(usage_type)), ''), '미분류') " +
        "ORDER BY COUNT(*) DESC, ISNULL(NULLIF(LTRIM(RTRIM(usage_type)), ''), '미분류') ASC";
    try (Connection conn = openDbConnection();
         PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Usage meter top];");
            int i = 0;
            while (rs.next()) {
                i++;
                String usageType = trimToNull(rs.getString("usage_type"));
                if (usageType == null) usageType = "미분류";
                sb.append(" ").append(i).append(")")
                  .append(clip(usageType, 40))
                  .append(": count=")
                  .append(rs.getInt("meter_count"))
                  .append(";");
            }
            if (i == 0) return "[Usage meter top] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Usage meter top] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private Double extractPfThreshold(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractPfThreshold", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof Double) return (Double) delegated;
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
    Object delegated = invokeAgentQueryParser("extractTopN", new Class<?>[] { String.class, int.class, int.class }, new Object[] { userMessage, Integer.valueOf(defVal), Integer.valueOf(maxVal) });
    if (delegated instanceof Integer) return (Integer) delegated;
    if (userMessage == null) return Integer.valueOf(defVal);
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    if (src.contains("전체") || src.contains("전부") || src.contains("모두") || src.contains("all")) {
        return Integer.valueOf(maxVal);
    }
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
    Object delegated = invokeAgentQueryParser("extractDays", new Class<?>[] { String.class, int.class, int.class }, new Object[] { userMessage, Integer.valueOf(defVal), Integer.valueOf(maxVal) });
    if (delegated instanceof Integer) return (Integer) delegated;
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
    Object delegated = invokeAgentQueryParser("extractExplicitDays", new Class<?>[] { String.class, int.class }, new Object[] { userMessage, Integer.valueOf(maxVal) });
    if (delegated instanceof Integer) return (Integer) delegated;
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
    Object delegated = invokeAgentQueryParser("extractExplicitDate", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof java.time.LocalDate) return (java.time.LocalDate) delegated;
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
    Object delegated = invokeAgentQueryParser("extractTimeWindow", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated != null) {
        try {
            java.lang.Class<?> cls = delegated.getClass();
            java.lang.reflect.Field fromField = cls.getField("fromTs");
            java.lang.reflect.Field toField = cls.getField("toTs");
            java.lang.reflect.Field labelField = cls.getField("label");
            Timestamp fromTs = (Timestamp) fromField.get(delegated);
            Timestamp toTs = (Timestamp) toField.get(delegated);
            String label = (String) labelField.get(delegated);
            return new TimeWindow(fromTs, toTs, label);
        } catch (Throwable ignore) {
        }
    }
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
    java.util.regex.Matcher ym = java.util.regex.Pattern.compile("([0-9]{4})\\s*년\\s*([0-9]{1,2})\\s*월").matcher(src);
    if (ym.find()) {
        try {
            int yy = Integer.parseInt(ym.group(1));
            int mm = Integer.parseInt(ym.group(2));
            if (mm >= 1 && mm <= 12) {
                java.time.LocalDate monthStart = java.time.LocalDate.of(yy, mm, 1);
                return new TimeWindow(
                    Timestamp.valueOf(monthStart.atStartOfDay()),
                    Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()),
                    String.format(java.util.Locale.ROOT, "%04d-%02d", yy, mm)
                );
            }
        } catch (Exception ignore) {}
    }
    java.util.regex.Matcher monthOnly = java.util.regex.Pattern.compile("(^|[^0-9])([0-9]{1,2})\\s*월(?:\\s*달)?").matcher(src);
    if (monthOnly.find()) {
        try {
            int mm = Integer.parseInt(monthOnly.group(2));
            if (mm >= 1 && mm <= 12) {
                int yy = today.getYear();
                java.time.LocalDate monthStart = java.time.LocalDate.of(yy, mm, 1);
                return new TimeWindow(
                    Timestamp.valueOf(monthStart.atStartOfDay()),
                    Timestamp.valueOf(monthStart.plusMonths(1).atStartOfDay()),
                    String.format(java.util.Locale.ROOT, "%04d-%02d", yy, mm)
                );
            }
        } catch (Exception ignore) {}
    }
    if (src.contains("올해") || src.contains("금년") || src.contains("this year")) {
        java.time.LocalDate yearStart = today.withDayOfYear(1);
        return new TimeWindow(Timestamp.valueOf(yearStart.atStartOfDay()), Timestamp.valueOf(yearStart.plusYears(1).atStartOfDay()), String.valueOf(today.getYear()));
    }
    return null;
}

private Double extractHzThreshold(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractHzThreshold", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof Double) return (Double) delegated;
    if (userMessage == null) return null;
    String src = userMessage.toLowerCase(java.util.Locale.ROOT);
    java.util.regex.Matcher m = java.util.regex.Pattern.compile("([0-9]{2,3}(?:\\.[0-9]+)?)\\s*hz").matcher(src);
    if (m.find()) {
        try { return Double.valueOf(m.group(1)); } catch (Exception ignore) {}
    }
    return null;
}

private Integer extractMonth(String userMessage) {
    Object delegated = invokeAgentQueryParser("extractMonth", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof Integer) return (Integer) delegated;
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
    Object delegated = invokeAgentQueryParser("extractMeterId", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof Integer) return (Integer) delegated;
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
    Object delegated = invokeAgentQueryParser("extractPanelTokens", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof List<?>) return (List<String>) delegated;
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
    Object delegated = invokeAgentQueryParser("extractPanelTokensLoose", new Class<?>[] { String.class }, new Object[] { userMessage });
    if (delegated instanceof List<?>) return (List<String>) delegated;
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
    String delegated = invokeAgentDbTool(
        "getRecentMeterContext",
        new Class<?>[] { Integer.class, String.class },
        new Object[] { meterId, panelTokens == null ? null : String.join(",", panelTokens) }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getMonthlyAvgFrequencyContext",
        new Class<?>[] { Integer.class, Integer.class },
        new Object[] { meterId, month }
    );
    if (delegated != null) return delegated;
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

private String getLatestEnergyContext(Integer meterId, List<String> panelTokens) {
    String delegated = invokeAgentDbTool(
        "getLatestEnergyContext",
        new Class<?>[] { Integer.class, String.class },
        new Object[] { meterId, panelTokens == null ? null : String.join(",", panelTokens) }
    );
    if (delegated != null) return delegated;
    String baseSelect =
        "SELECT TOP %d m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
        "ms.active_power_total, ms.energy_consumed_total, ms.reactive_energy_total " +
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
    String sql = String.format(baseSelect, topN) + where.toString() + "ORDER BY ms.measurement_id DESC";
    StringBuilder sb = new StringBuilder(filtered
        ? "[Latest energy: meter_id=" + meterId + "]"
        : (panelFiltered ? "[Latest energy: panel=" + panelTokens + "]" : "[Latest energy]"));
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        if (filtered) {
            ps.setInt(1, meterId.intValue());
        } else if (panelFiltered) {
            int pi = 1;
            for (int i = 0; i < panelTokens.size(); i++) {
                String normalized = panelTokens.get(i).replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT);
                ps.setString(pi++, "%" + normalized + "%");
            }
        }
        ps.setQueryTimeout(5);
        try (ResultSet rs = ps.executeQuery()) {
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 40))
                  .append(", panel=").append(clip(rs.getString("panel_name"), 60))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(", kW=").append(fmtNum(rs.getDouble("active_power_total")))
                  .append(", kWh=").append(fmtNum(rs.getDouble("energy_consumed_total")))
                  .append(", kVArh=").append(fmtNum(rs.getDouble("reactive_energy_total")))
                  .append(";");
            }
            if (i == 0) {
                return filtered
                    ? ("[Latest energy: meter_id=" + meterId + "] no data")
                    : (panelFiltered ? ("[Latest energy: panel=" + panelTokens + "] no data") : "[Latest energy] no data");
            }
        }
    } catch (Exception e) {
        return (filtered
                ? ("[Latest energy: meter_id=" + meterId + "]")
                : (panelFiltered ? ("[Latest energy: panel=" + panelTokens + "]") : "[Latest energy]"))
            + " unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
    return sb.toString();
}

private String getEnergyDeltaContext(Integer meterId, Timestamp fromTs, Timestamp toTs, String periodLabel, boolean reactive) {
    String delegated = invokeAgentDbTool(
        "getEnergyDeltaContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class, boolean.class },
        new Object[] { meterId, fromTs, toTs, periodLabel, Boolean.valueOf(reactive) }
    );
    if (delegated != null) return delegated;
    if (meterId == null) {
        return reactive ? "[Reactive energy delta] meter_id required" : "[Energy delta] meter_id required";
    }
    if (fromTs == null || toTs == null) {
        return reactive ? "[Reactive energy delta] period required" : "[Energy delta] period required";
    }
    String column = reactive ? "reactive_energy_total" : "energy_consumed_total";
    String prefix = reactive ? "[Reactive energy delta]" : "[Energy delta]";
    String sql =
        "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, CAST(ms." + column + " AS float) AS energy_val " +
        "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        "WHERE m.meter_id=? AND ms.measured_at >= ? AND ms.measured_at < ? AND ms." + column + " IS NOT NULL " +
        "ORDER BY ms.measured_at %s, ms.measurement_id %s";
    try (Connection conn = openDbConnection()) {
        String meterName = null;
        String panelName = null;
        Timestamp firstTs = null;
        Timestamp lastTs = null;
        Double firstVal = null;
        Double lastVal = null;
        try (PreparedStatement ps = conn.prepareStatement(String.format(sql, "ASC", "ASC"))) {
            ps.setInt(1, meterId.intValue());
            ps.setTimestamp(2, fromTs);
            ps.setTimestamp(3, toTs);
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    meterName = clip(rs.getString("meter_name"), 40);
                    panelName = clip(rs.getString("panel_name"), 60);
                    firstTs = rs.getTimestamp("measured_at");
                    firstVal = Double.valueOf(rs.getDouble("energy_val"));
                }
            }
        }
        try (PreparedStatement ps = conn.prepareStatement(String.format(sql, "DESC", "DESC"))) {
            ps.setInt(1, meterId.intValue());
            ps.setTimestamp(2, fromTs);
            ps.setTimestamp(3, toTs);
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    if (meterName == null) meterName = clip(rs.getString("meter_name"), 40);
                    if (panelName == null) panelName = clip(rs.getString("panel_name"), 60);
                    lastTs = rs.getTimestamp("measured_at");
                    lastVal = Double.valueOf(rs.getDouble("energy_val"));
                }
            }
        }
        if (firstVal == null || lastVal == null) {
            return prefix + " meter_id=" + meterId + ", period=" + (periodLabel == null ? "-" : periodLabel) + ", no data";
        }
        double delta = Math.max(0.0d, lastVal.doubleValue() - firstVal.doubleValue());
        return prefix + " meter_id=" + meterId
            + ", meter=" + (meterName == null || meterName.isEmpty() ? "-" : meterName)
            + ", panel=" + (panelName == null || panelName.isEmpty() ? "-" : panelName)
            + ", period=" + (periodLabel == null ? "-" : periodLabel)
            + ", delta=" + fmtNum(delta)
            + ", start_t=" + fmtTs(firstTs)
            + ", end_t=" + fmtTs(lastTs)
            + ", start_v=" + fmtNum(firstVal.doubleValue())
            + ", end_v=" + fmtNum(lastVal.doubleValue());
    } catch (Exception e) {
        return prefix + " unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getVoltageAverageContext(Integer meterId, List<String> panelTokens, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer recentDays) {
    String delegated = invokeAgentDbTool(
        "getVoltageAverageContext",
        new Class<?>[] { Integer.class, String.class, Timestamp.class, Timestamp.class, String.class, Integer.class },
        new Object[] { meterId, panelTokens == null ? null : String.join(",", panelTokens), fromTs, toTs, periodLabel, recentDays }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentAnswerFormatter(
        "buildVoltageAverageDirectAnswer",
        new Class<?>[] { String.class, Integer.class },
        new Object[] { voltageCtx, meterId }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentAnswerFormatter(
        "buildPerMeterPowerDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { powerCtx }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentAnswerFormatter(
        "buildHarmonicDirectAnswer",
        new Class<?>[] { String.class, Integer.class },
        new Object[] { harmonicCtx, meterId }
    );
    if (delegated != null) return delegated;
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

private String getMonthlyPeakPowerContext(Integer meterId, Integer month) {
    String delegated = invokeAgentDbTool(
        "getMonthlyPeakPowerContext",
        new Class<?>[] { Integer.class, Integer.class },
        new Object[] { meterId, month }
    );
    if (delegated != null) return delegated;
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    StringBuilder sql = new StringBuilder();
    sql.append("SELECT TOP 1 ms.meter_id, ISNULL(NULLIF(LTRIM(RTRIM(m.name)), ''), '-') AS meter_name, ");
    sql.append("ISNULL(NULLIF(LTRIM(RTRIM(m.panel_name)), ''), '-') AS panel_name, ");
    sql.append("ms.measured_at, CAST(ms.active_power_total AS float) AS peak_kw ");
    sql.append("FROM dbo.measurements ms ");
    sql.append("LEFT JOIN dbo.meters m ON m.meter_id = ms.meter_id ");
    sql.append("WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? ");
    if (meterId != null) {
        sql.append("AND ms.meter_id=? ");
    }
    sql.append("ORDER BY CAST(ms.active_power_total AS float) DESC, ms.measured_at ASC");
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
        int pi = 1;
        ps.setInt(pi++, yy);
        ps.setInt(pi++, mm.intValue());
        if (meterId != null) ps.setInt(pi++, meterId.intValue());
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            String period = String.format(java.util.Locale.US, "%04d-%02d", yy, mm.intValue());
            if (!rs.next()) {
                return "[Monthly peak power] period=" + period + (meterId != null ? "; meter_id=" + meterId.intValue() : "") + "; no data";
            }
            return "[Monthly peak power] period=" + period
                + "; meter_id=" + rs.getInt("meter_id")
                + "; meter_name=" + clip(rs.getString("meter_name"), 60)
                + "; panel=" + clip(rs.getString("panel_name"), 60)
                + "; peak_kw=" + fmtNum(rs.getDouble("peak_kw"))
                + "; t=" + fmtTs(rs.getTimestamp("measured_at"));
        }
    } catch (Exception e) {
        return "[Monthly peak power] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getBuildingPowerTopNContext(Integer month, Integer topN) {
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    int n = topN != null ? topN.intValue() : 5;
    String sql =
        "WITH leaf_meters AS ( " +
        "  SELECT m.meter_id, ISNULL(NULLIF(LTRIM(RTRIM(m.building_name)), ''), '미분류') AS building_name " +
        "  FROM dbo.meters m " +
        "  WHERE NOT EXISTS ( " +
        "    SELECT 1 FROM dbo.meter_tree t " +
        "    WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
        "  ) " +
        "), month_samples AS ( " +
        "  SELECT lm.building_name, ms.meter_id, ms.measurement_id, ms.measured_at, " +
        "         CAST(ms.active_power_total AS float) AS active_kw, " +
        "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
        "  FROM dbo.measurements ms " +
        "  INNER JOIN leaf_meters lm ON lm.meter_id = ms.meter_id " +
        "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
        "), month_energy AS ( " +
        "  SELECT building_name, meter_id, " +
        "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
        "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
        "  FROM month_samples GROUP BY building_name, meter_id " +
        "), building_avg AS ( " +
        "  SELECT building_name, AVG(active_kw) AS avg_kw " +
        "  FROM month_samples GROUP BY building_name " +
        "), building_sum AS ( " +
        "  SELECT building_name, " +
        "         SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 ELSE end_kwh - start_kwh END) AS sum_kwh " +
        "  FROM month_energy GROUP BY building_name " +
        "), building_agg AS ( " +
        "  SELECT a.building_name, a.avg_kw, ISNULL(s.sum_kwh, 0) AS sum_kwh " +
        "  FROM building_avg a LEFT JOIN building_sum s ON s.building_name = a.building_name " +
        ") " +
        "SELECT TOP " + n + " building_name, avg_kw, sum_kwh " +
        "FROM building_agg ORDER BY sum_kwh DESC, avg_kw DESC, building_name ASC";
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

private String getScopedMonthlyEnergyContext(String scopeToken, Integer month) {
    List<String> tokens = splitAlarmAreaTokens(scopeToken);
    if (tokens == null || tokens.isEmpty()) return "[Scoped monthly energy] scope required";
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    StringBuilder scopeWhere = new StringBuilder("(");
    for (int i = 0; i < tokens.size(); i++) {
        if (i > 0) scopeWhere.append(" OR ");
        scopeWhere.append("UPPER(ISNULL(m.building_name,'')) LIKE ? OR UPPER(ISNULL(m.usage_type,'')) LIKE ?");
    }
    scopeWhere.append(")");
    String sql =
        "WITH selected_leaf_meters AS ( " +
        "  SELECT DISTINCT m.meter_id " +
        "  FROM dbo.meters m " +
        "  WHERE " + scopeWhere.toString() + " " +
        "    AND NOT EXISTS ( " +
        "      SELECT 1 FROM dbo.meter_tree t " +
        "      WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
        "    ) " +
        "), month_samples AS ( " +
        "  SELECT ms.meter_id, ms.measurement_id, ms.measured_at, " +
        "         CAST(ms.active_power_total AS float) AS active_kw, " +
        "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
        "  FROM dbo.measurements ms " +
        "  INNER JOIN selected_leaf_meters slm ON slm.meter_id = ms.meter_id " +
        "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
        "), month_energy AS ( " +
        "  SELECT meter_id, " +
        "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
        "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
        "  FROM month_samples GROUP BY meter_id " +
        ") " +
        "SELECT " +
        "  (SELECT COUNT(*) FROM selected_leaf_meters) AS leaf_meter_count, " +
        "  (SELECT COUNT(*) FROM month_energy) AS measured_meter_count, " +
        "  (SELECT COUNT(*) FROM month_energy WHERE start_kwh IS NOT NULL AND end_kwh IS NOT NULL AND end_kwh < start_kwh) AS negative_delta_count, " +
        "  (SELECT AVG(active_kw) FROM month_samples) AS avg_kw, " +
        "  (SELECT SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 WHEN end_kwh < start_kwh THEN 0 ELSE end_kwh - start_kwh END) FROM month_energy) AS sum_kwh";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        for (int i = 0; i < tokens.size(); i++) {
            String token = tokens.get(i).toUpperCase(java.util.Locale.ROOT);
            ps.setString(pi++, "%" + token + "%");
            ps.setString(pi++, "%" + token + "%");
        }
        ps.setInt(pi++, yy);
        ps.setInt(pi++, mm.intValue());
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                int leafMeterCount = rs.getInt("leaf_meter_count");
                int measuredMeterCount = rs.getInt("measured_meter_count");
                if (leafMeterCount <= 0) {
                    return "[Scoped monthly energy] scope=" + String.join(",", tokens) + "; period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) + "; no data";
                }
                return "[Scoped monthly energy] scope=" + String.join(",", tokens)
                    + "; period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue())
                    + "; leaf_meter_count=" + leafMeterCount
                    + "; measured_meter_count=" + measuredMeterCount
                    + "; negative_delta_count=" + rs.getInt("negative_delta_count")
                    + "; avg_kw=" + fmtNum(rs.getDouble("avg_kw"))
                    + "; sum_kwh=" + fmtNum(rs.getDouble("sum_kwh"));
            }
        }
    } catch (Exception e) {
        return "[Scoped monthly energy] scope=" + String.join(",", tokens) + "; unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
    return "[Scoped monthly energy] no data";
}

private String getPanelMonthlyEnergyContext(List<String> panelTokens, Integer month) {
    if (panelTokens == null || panelTokens.isEmpty()) return "[Panel monthly energy] panel token required";
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    StringBuilder panelWhere = new StringBuilder("(");
    for (int i = 0; i < panelTokens.size(); i++) {
        if (i > 0) panelWhere.append(" OR ");
        panelWhere.append("UPPER(REPLACE(REPLACE(ISNULL(m.panel_name,''),'_',''),' ','')) LIKE ?");
    }
    panelWhere.append(")");
    String sql =
        "WITH selected_leaf_meters AS ( " +
        "  SELECT DISTINCT m.meter_id " +
        "  FROM dbo.meters m " +
        "  WHERE " + panelWhere.toString() + " " +
        "    AND NOT EXISTS ( " +
        "      SELECT 1 FROM dbo.meter_tree t " +
        "      WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
        "    ) " +
        "), month_samples AS ( " +
        "  SELECT ms.meter_id, ms.measurement_id, ms.measured_at, " +
        "         CAST(ms.active_power_total AS float) AS active_kw, " +
        "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
        "  FROM dbo.measurements ms " +
        "  INNER JOIN selected_leaf_meters slm ON slm.meter_id = ms.meter_id " +
        "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
        "), month_energy AS ( " +
        "  SELECT meter_id, " +
        "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
        "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
        "  FROM month_samples GROUP BY meter_id " +
        ") " +
        "SELECT " +
        "  (SELECT COUNT(*) FROM selected_leaf_meters) AS leaf_meter_count, " +
        "  (SELECT COUNT(*) FROM month_energy) AS measured_meter_count, " +
        "  (SELECT COUNT(*) FROM month_energy WHERE start_kwh IS NOT NULL AND end_kwh IS NOT NULL AND end_kwh < start_kwh) AS negative_delta_count, " +
        "  (SELECT AVG(active_kw) FROM month_samples) AS avg_kw, " +
        "  (SELECT SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 WHEN end_kwh < start_kwh THEN 0 ELSE end_kwh - start_kwh END) FROM month_energy) AS sum_kwh";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        for (int i = 0; i < panelTokens.size(); i++) {
            String normalized = panelTokens.get(i).replaceAll("[\\s_\\-]+", "").toUpperCase(java.util.Locale.ROOT);
            ps.setString(pi++, "%" + normalized + "%");
        }
        ps.setInt(pi++, yy);
        ps.setInt(pi++, mm.intValue());
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                int leafMeterCount = rs.getInt("leaf_meter_count");
                int measuredMeterCount = rs.getInt("measured_meter_count");
                if (leafMeterCount <= 0) {
                    return "[Panel monthly energy] panel=" + panelTokens + "; period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) + "; no data";
                }
                return "[Panel monthly energy] panel=" + panelTokens
                    + "; period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue())
                    + "; leaf_meter_count=" + leafMeterCount
                    + "; measured_meter_count=" + measuredMeterCount
                    + "; negative_delta_count=" + rs.getInt("negative_delta_count")
                    + "; avg_kw=" + fmtNum(rs.getDouble("avg_kw"))
                    + "; sum_kwh=" + fmtNum(rs.getDouble("sum_kwh"));
            }
        }
    } catch (Exception e) {
        return "[Panel monthly energy] panel=" + panelTokens + "; unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
    return "[Panel monthly energy] no data";
}

private String getUsageMonthlyEnergyContext(String usageToken, Integer month) {
    String token = trimToNull(usageToken);
    if (token == null) return "[Usage monthly energy] usage token required";
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    String sql =
        "WITH selected_leaf_meters AS ( " +
        "  SELECT DISTINCT m.meter_id " +
        "  FROM dbo.meters m " +
        "  WHERE UPPER(ISNULL(m.usage_type,'')) LIKE ? " +
        "    AND NOT EXISTS ( " +
        "      SELECT 1 FROM dbo.meter_tree t " +
        "      WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
        "    ) " +
        "), month_samples AS ( " +
        "  SELECT ms.meter_id, ms.measurement_id, ms.measured_at, " +
        "         CAST(ms.active_power_total AS float) AS active_kw, " +
        "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
        "  FROM dbo.measurements ms " +
        "  INNER JOIN selected_leaf_meters slm ON slm.meter_id = ms.meter_id " +
        "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
        "), month_energy AS ( " +
        "  SELECT meter_id, " +
        "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
        "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
        "  FROM month_samples GROUP BY meter_id " +
        ") " +
        "SELECT " +
        "  (SELECT COUNT(*) FROM selected_leaf_meters) AS leaf_meter_count, " +
        "  (SELECT COUNT(*) FROM month_energy) AS measured_meter_count, " +
        "  (SELECT COUNT(*) FROM month_energy WHERE start_kwh IS NOT NULL AND end_kwh IS NOT NULL AND end_kwh < start_kwh) AS negative_delta_count, " +
        "  (SELECT AVG(active_kw) FROM month_samples) AS avg_kw, " +
        "  (SELECT SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 WHEN end_kwh < start_kwh THEN 0 ELSE end_kwh - start_kwh END) FROM month_energy) AS sum_kwh";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        ps.setString(pi++, "%" + token.toUpperCase(java.util.Locale.ROOT) + "%");
        ps.setInt(pi++, yy);
        ps.setInt(pi++, mm.intValue());
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                int leafMeterCount = rs.getInt("leaf_meter_count");
                int measuredMeterCount = rs.getInt("measured_meter_count");
                if (leafMeterCount <= 0) {
                    return "[Usage monthly energy] usage=" + token + "; period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) + "; no data";
                }
                return "[Usage monthly energy] usage=" + token
                    + "; period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue())
                    + "; leaf_meter_count=" + leafMeterCount
                    + "; measured_meter_count=" + measuredMeterCount
                    + "; negative_delta_count=" + rs.getInt("negative_delta_count")
                    + "; avg_kw=" + fmtNum(rs.getDouble("avg_kw"))
                    + "; sum_kwh=" + fmtNum(rs.getDouble("sum_kwh"));
            }
        }
    } catch (Exception e) {
        return "[Usage monthly energy] usage=" + token + "; unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
    return "[Usage monthly energy] no data";
}

private String getUsagePowerTopNContext(Integer month, Integer topN) {
    Integer mm = month != null ? month : Integer.valueOf(java.time.LocalDate.now().getMonthValue());
    int yy = java.time.LocalDate.now().getYear();
    int n = topN != null ? topN.intValue() : 5;
    String sql =
        "WITH leaf_meters AS ( " +
        "  SELECT m.meter_id, ISNULL(NULLIF(LTRIM(RTRIM(m.usage_type)), ''), '미분류') AS usage_type " +
        "  FROM dbo.meters m " +
        "  WHERE NOT EXISTS ( " +
        "    SELECT 1 FROM dbo.meter_tree t " +
        "    WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
        "  ) " +
        "), month_samples AS ( " +
        "  SELECT lm.usage_type, ms.meter_id, ms.measurement_id, ms.measured_at, " +
        "         CAST(ms.active_power_total AS float) AS active_kw, " +
        "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
        "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
        "  FROM dbo.measurements ms " +
        "  INNER JOIN leaf_meters lm ON lm.meter_id = ms.meter_id " +
        "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
        "), month_energy AS ( " +
        "  SELECT usage_type, meter_id, " +
        "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
        "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
        "  FROM month_samples GROUP BY usage_type, meter_id " +
        "), usage_avg AS ( " +
        "  SELECT usage_type, AVG(active_kw) AS avg_kw " +
        "  FROM month_samples GROUP BY usage_type " +
        "), usage_sum AS ( " +
        "  SELECT usage_type, SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 ELSE end_kwh - start_kwh END) AS sum_kwh " +
        "  FROM month_energy GROUP BY usage_type " +
        "), usage_agg AS ( " +
        "  SELECT a.usage_type, a.avg_kw, ISNULL(s.sum_kwh, 0) AS sum_kwh " +
        "  FROM usage_avg a LEFT JOIN usage_sum s ON s.usage_type = a.usage_type " +
        ") " +
        "SELECT TOP " + n + " usage_type, avg_kw, sum_kwh FROM usage_agg ORDER BY sum_kwh DESC, avg_kw DESC, usage_type ASC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, yy);
        ps.setInt(2, mm.intValue());
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Usage power TOP] period=" + yy + "-" + String.format(java.util.Locale.US, "%02d", mm.intValue()) + ";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append(clip(rs.getString("usage_type"), 30))
                  .append(": avg_kw=").append(fmtNum(rs.getDouble("avg_kw")))
                  .append(", sum_kwh=").append(fmtNum(rs.getDouble("sum_kwh"))).append(";");
            }
            if (i == 0) return "[Usage power TOP] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Usage power TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPanelLatestStatusContext(List<String> panelTokens, Integer topN) {
    String delegated = invokeAgentDbTool(
        "getPanelLatestStatusContext",
        new Class<?>[] { String.class, Integer.class },
        new Object[] { panelTokens == null ? null : String.join(",", panelTokens), topN }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getAlarmSeveritySummaryContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class },
        new Object[] { days, fromTs, toTs, periodLabel }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getAlarmTypeSummaryContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class, Integer.class, boolean.class, Integer.class },
        new Object[] { days, fromTs, toTs, periodLabel, meterId, Boolean.valueOf(tripOnly), topN }
    );
    if (delegated != null) return delegated;
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

private String getAlarmMeterTopNContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer topN) {
    String delegated = invokeAgentDbTool(
        "getAlarmMeterTopNContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class, Integer.class },
        new Object[] { days, fromTs, toTs, periodLabel, topN }
    );
    if (delegated != null) return delegated;
    int d = days != null ? days.intValue() : 7;
    int n = topN != null ? topN.intValue() : 10;
    if (n < 1) n = 10;
    if (n > 50) n = 50;
    boolean byRange = (fromTs != null || toTs != null);

    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    if (byRange) {
        if (fromTs != null) where.append("AND triggered_at >= ? ");
        if (toTs != null) where.append("AND triggered_at < ? ");
    } else {
        where.append("AND triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
    }

    String sql =
        "SELECT TOP " + n + " ISNULL(NULLIF(LTRIM(RTRIM(meter_name)), ''), '(미분류 계측기)') AS meter_name, COUNT(1) AS cnt " +
        "FROM dbo.vw_alarm_log " + where.toString() +
        "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(meter_name)), ''), '(미분류 계측기)') " +
        "ORDER BY cnt DESC, meter_name ASC";

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
            StringBuilder sb = new StringBuilder("[Alarm meter TOP] ");
            if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
            else sb.append("days=").append(d).append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append(clip(rs.getString("meter_name"), 80))
                  .append("=")
                  .append(rs.getLong("cnt"))
                  .append(";");
            }
            if (i == 0) return "[Alarm meter TOP] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Alarm meter TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getUsageAlarmTopNContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer topN) {
    int d = days != null ? days.intValue() : 7;
    int n = topN != null ? topN.intValue() : 10;
    if (n < 1) n = 10;
    if (n > 50) n = 50;
    boolean byRange = (fromTs != null || toTs != null);

    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    if (byRange) {
        if (fromTs != null) where.append("AND al.triggered_at >= ? ");
        if (toTs != null) where.append("AND al.triggered_at < ? ");
    } else {
        where.append("AND al.triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
    }

    String sql =
        "SELECT TOP " + n + " " +
        "  ISNULL(NULLIF(LTRIM(RTRIM(m.usage_type)), ''), '미분류') AS usage_type, " +
        "  COUNT(1) AS cnt " +
        "FROM dbo.vw_alarm_log al " +
        "LEFT JOIN dbo.meters m ON m.name = al.meter_name " +
        where.toString() +
        "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(m.usage_type)), ''), '미분류') " +
        "ORDER BY cnt DESC, usage_type ASC";

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
            StringBuilder sb = new StringBuilder("[Usage alarm TOP] ");
            if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
            else sb.append("days=").append(d).append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append(clip(rs.getString("usage_type"), 40))
                  .append("=")
                  .append(rs.getLong("cnt"))
                  .append(";");
            }
            if (i == 0) return "[Usage alarm TOP] no data";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Usage alarm TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getUsageAlarmCountContext(String usageToken, Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    String token = trimToNull(usageToken);
    if (token == null) return "[Usage alarm count] usage token required";
    int d = days != null ? days.intValue() : 7;
    boolean byRange = (fromTs != null || toTs != null);

    StringBuilder sql = new StringBuilder(
        "SELECT COUNT(1) AS cnt " +
        "FROM dbo.vw_alarm_log al " +
        "LEFT JOIN dbo.meters m ON m.name = al.meter_name " +
        "WHERE UPPER(ISNULL(m.usage_type,'')) LIKE ? "
    );
    if (byRange) {
        if (fromTs != null) sql.append("AND al.triggered_at >= ? ");
        if (toTs != null) sql.append("AND al.triggered_at < ? ");
    } else {
        sql.append("AND al.triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
    }

    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
        int pi = 1;
        ps.setString(pi++, "%" + token.toUpperCase(java.util.Locale.ROOT) + "%");
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
                if (byRange) return "[Usage alarm count] usage=" + token + "; period=" + (periodLabel == null ? "-" : periodLabel) + "; count=" + cnt;
                return "[Usage alarm count] usage=" + token + "; days=" + d + "; count=" + cnt;
            }
        }
        return "[Usage alarm count] no data";
    } catch (Exception e) {
        return "[Usage alarm count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
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
    String delegated = invokeAgentDbTool(
        "getAlarmCountContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class, Integer.class, String.class, String.class },
        new Object[] { days, fromTs, toTs, periodLabel, meterId, alarmTypeToken, areaToken }
    );
    if (delegated != null) return delegated;
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
        StringBuilder sb = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al LEFT JOIN dbo.meters m ON m.name = al.meter_name WHERE 1=1 ");
        if (byMeter) sb.append("AND al.meter_name = ? ");
        if (token != null) sb.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
        if (areaTokens != null && !areaTokens.isEmpty()) {
            for (int i = 0; i < areaTokens.size(); i++) {
                sb.append("AND (UPPER(ISNULL(al.meter_name,'')) LIKE ? ");
                sb.append("OR UPPER(ISNULL(m.panel_name,'')) LIKE ? ");
                sb.append("OR UPPER(ISNULL(m.usage_type,'')) LIKE ?) ");
            }
        }
        if (fromTs != null) sb.append("AND al.triggered_at >= ? ");
        if (toTs != null) sb.append("AND al.triggered_at < ? ");
        sql = sb.toString();
    } else {
        StringBuilder sb = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al LEFT JOIN dbo.meters m ON m.name = al.meter_name WHERE 1=1 ");
        if (byMeter) sb.append("AND al.meter_name = ? ");
        if (token != null) sb.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
        if (areaTokens != null && !areaTokens.isEmpty()) {
            for (int i = 0; i < areaTokens.size(); i++) {
                sb.append("AND (UPPER(ISNULL(al.meter_name,'')) LIKE ? ");
                sb.append("OR UPPER(ISNULL(m.panel_name,'')) LIKE ? ");
                sb.append("OR UPPER(ISNULL(m.usage_type,'')) LIKE ?) ");
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
    String delegated = invokeAgentDbTool(
        "getOpenAlarmsContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class },
        new Object[] { topN, fromTs, toTs, periodLabel }
    );
    if (delegated != null) return delegated;
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

private String getOpenAlarmCountContext(Timestamp fromTs, Timestamp toTs, String periodLabel, Integer meterId, String alarmTypeToken, String areaToken) {
    String delegated = invokeAgentDbTool(
        "getOpenAlarmCountContext",
        new Class<?>[] { Timestamp.class, Timestamp.class, String.class, Integer.class, String.class, String.class },
        new Object[] { fromTs, toTs, periodLabel, meterId, alarmTypeToken, areaToken }
    );
    if (delegated != null) return delegated;
    String meterName = getMeterNameById(meterId);
    boolean byMeter = (meterId != null && meterName != null && !meterName.isEmpty());
    String token = trimToNull(alarmTypeToken);
    String area = trimToNull(areaToken);
    List<String> areaTokens = splitAlarmAreaTokens(area);
    if (token != null) token = token.toUpperCase(java.util.Locale.ROOT);
    boolean byRange = (fromTs != null || toTs != null);
    StringBuilder sql = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al WHERE al.cleared_at IS NULL ");
    if (byMeter) sql.append("AND al.meter_name = ? ");
    if (token != null) sql.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
    if (areaTokens != null && !areaTokens.isEmpty()) {
        for (int i = 0; i < areaTokens.size(); i++) {
            sql.append("AND (UPPER(ISNULL(al.meter_name,'')) LIKE ? ");
            sql.append("OR EXISTS (SELECT 1 FROM dbo.meters m WHERE m.name = al.meter_name AND UPPER(ISNULL(m.panel_name,'')) LIKE ?)) ");
        }
    }
    if (byRange) {
        if (fromTs != null) sql.append("AND al.triggered_at >= ? ");
        if (toTs != null) sql.append("AND al.triggered_at < ? ");
    }
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
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
        }
        ps.setQueryTimeout(8);
        try (ResultSet rs = ps.executeQuery()) {
            int count = rs.next() ? rs.getInt(1) : 0;
            StringBuilder sb = new StringBuilder("[Open alarm count]");
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
            if (token != null) sb.append("; type=").append(token);
            if (area != null && !area.isEmpty()) sb.append("; scope=").append(area);
            sb.append("; count=").append(count);
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Open alarm count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getHarmonicExceedListContext(Double thdV, Double thdI, Integer topN) {
    return getHarmonicExceedListContext(thdV, thdI, topN, null, null, null);
}

private String getHarmonicExceedListContext(Double thdV, Double thdI, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    String delegated = invokeAgentDbTool(
        "getHarmonicExceedListContext",
        new Class<?>[] { Double.class, Double.class, Integer.class, Timestamp.class, Timestamp.class, String.class },
        new Object[] { thdV, thdI, topN, fromTs, toTs, periodLabel }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getFrequencyOutlierListContext",
        new Class<?>[] { Double.class, Integer.class, Timestamp.class, Timestamp.class, String.class },
        new Object[] { thresholdHz, topN, fromTs, toTs, periodLabel }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getVoltageUnbalanceTopNContext",
        new Class<?>[] { Integer.class, Timestamp.class, Timestamp.class, String.class },
        new Object[] { topN, fromTs, toTs, periodLabel }
    );
    if (delegated != null) return delegated;
    int n = topN != null ? topN.intValue() : 10;
    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    if (fromTs != null) where.append("AND ms.measured_at >= ? ");
    if (toTs != null) where.append("AND ms.measured_at < ? ");
    String sql =
        "WITH src AS ( " +
        "  SELECT m.meter_id, m.name AS meter_name, ms.measured_at, " +
        "         CAST(ms.voltage_unbalance_rate AS float) AS voltage_unbalance_rate, " +
        "         CAST(ms.voltage_phase_a AS float) AS va, " +
        "         CAST(ms.voltage_phase_b AS float) AS vb, " +
        "         CAST(ms.voltage_phase_c AS float) AS vc, " +
        "         ROW_NUMBER() OVER (PARTITION BY m.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn " +
        "  FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        where.toString() +
        "), calc AS ( " +
        "  SELECT meter_id, meter_name, measured_at, " +
        "         CASE " +
        "           WHEN voltage_unbalance_rate IS NOT NULL AND voltage_unbalance_rate > 0 THEN voltage_unbalance_rate " +
        "           WHEN va IS NULL OR vb IS NULL OR vc IS NULL THEN NULL " +
        "           WHEN ((va + vb + vc) / 3.0) <= 0 THEN NULL " +
        "           ELSE 100.0 * ( " +
        "             CASE " +
        "               WHEN ABS(va - ((va + vb + vc) / 3.0)) >= ABS(vb - ((va + vb + vc) / 3.0)) AND ABS(va - ((va + vb + vc) / 3.0)) >= ABS(vc - ((va + vb + vc) / 3.0)) THEN ABS(va - ((va + vb + vc) / 3.0)) " +
        "               WHEN ABS(vb - ((va + vb + vc) / 3.0)) >= ABS(vc - ((va + vb + vc) / 3.0)) THEN ABS(vb - ((va + vb + vc) / 3.0)) " +
        "               ELSE ABS(vc - ((va + vb + vc) / 3.0)) " +
        "             END " +
        "           ) / ((va + vb + vc) / 3.0) " +
        "         END AS effective_unb " +
        "  FROM src WHERE rn = 1 " +
        ") " +
        "SELECT TOP " + n + " meter_id, meter_name, measured_at, effective_unb " +
        "FROM calc WHERE effective_unb IS NOT NULL ORDER BY effective_unb DESC, measured_at DESC";
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
                  .append(", unb=").append(fmtNum(rs.getDouble("effective_unb")))
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

private String getCurrentUnbalanceCountContext(Double thresholdPct, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    double th = thresholdPct != null ? thresholdPct.doubleValue() : 10.0d;
    StringBuilder where = new StringBuilder("WHERE 1=1 ");
    if (fromTs != null) where.append("AND ms.measured_at >= ? ");
    if (toTs != null) where.append("AND ms.measured_at < ? ");
    String sql =
        "WITH latest AS ( " +
        "  SELECT m.meter_id, m.name AS meter_name, ms.measured_at, " +
        "         CAST(ms.current_phase_a AS float) AS ia, " +
        "         CAST(ms.current_phase_b AS float) AS ib, " +
        "         CAST(ms.current_phase_c AS float) AS ic, " +
        "         ROW_NUMBER() OVER (PARTITION BY m.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn " +
        "  FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        where.toString() +
        "), calc AS ( " +
        "  SELECT meter_id, meter_name, measured_at, ia, ib, ic, " +
        "         ((ISNULL(ia,0) + ISNULL(ib,0) + ISNULL(ic,0)) / 3.0) AS avg_i " +
        "  FROM latest WHERE rn = 1 " +
        "), filtered AS ( " +
        "  SELECT meter_id, meter_name, measured_at, " +
        "         CASE WHEN avg_i <= 0 THEN NULL ELSE " +
        "           (100.0 * (" +
        "             CASE " +
        "               WHEN ABS(ISNULL(ia,0) - avg_i) >= ABS(ISNULL(ib,0) - avg_i) AND ABS(ISNULL(ia,0) - avg_i) >= ABS(ISNULL(ic,0) - avg_i) THEN ABS(ISNULL(ia,0) - avg_i) " +
        "               WHEN ABS(ISNULL(ib,0) - avg_i) >= ABS(ISNULL(ic,0) - avg_i) THEN ABS(ISNULL(ib,0) - avg_i) " +
        "               ELSE ABS(ISNULL(ic,0) - avg_i) " +
        "             END" +
        "           ) / avg_i) END AS current_unbalance_pct " +
        "  FROM calc " +
        ") " +
        "SELECT COUNT(*) AS meter_count " +
        "FROM filtered WHERE current_unbalance_pct > ?";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setDouble(pi++, th);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            int count = rs.next() ? rs.getInt("meter_count") : 0;
            StringBuilder sb = new StringBuilder("[Current unbalance count] threshold=").append(fmtNum(th));
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append("; period=").append(periodLabel);
            sb.append("; count=").append(count);
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Current unbalance count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String getPowerFactorOutlierListContext(Double pfThreshold, Integer topN) {
    return getPowerFactorOutlierListContext(pfThreshold, topN, null, null, null);
}

private String getPowerFactorOutlierListContext(Double pfThreshold, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    String delegated = invokeAgentDbTool(
        "getPowerFactorOutlierListContext",
        new Class<?>[] { Double.class, Integer.class, Timestamp.class, Timestamp.class, String.class },
        new Object[] { pfThreshold, topN, fromTs, toTs, periodLabel }
    );
    if (delegated != null) return delegated;
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

private String getPowerFactorNoSignalListContext(int topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
    int n = topN > 0 ? topN : 10;
    StringBuilder srcWhere = new StringBuilder("WHERE 1=1 ");
    if (fromTs != null) srcWhere.append("AND ms.measured_at >= ? ");
    if (toTs != null) srcWhere.append("AND ms.measured_at < ? ");
    String sql =
        "WITH latest AS (" +
        " SELECT ms.*, ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
        " FROM dbo.measurements ms " + srcWhere.toString() +
        ") " +
        "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at " +
        "FROM latest ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
        "WHERE ms.rn=1 " +
        "AND (" +
        " COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) IS NULL " +
        " OR COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) = 0" +
        ") " +
        "ORDER BY ms.measured_at DESC";
    try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
        int pi = 1;
        if (fromTs != null) ps.setTimestamp(pi++, fromTs);
        if (toTs != null) ps.setTimestamp(pi++, toTs);
        ps.setQueryTimeout(10);
        try (ResultSet rs = ps.executeQuery()) {
            StringBuilder sb = new StringBuilder("[Power factor no signal]");
            if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
            sb.append(";");
            int i = 0;
            while (rs.next()) {
                i++;
                sb.append(" ").append(i).append(")")
                  .append("meter_id=").append(rs.getInt("meter_id"))
                  .append(", ").append(clip(rs.getString("meter_name"), 24))
                  .append(", panel=").append(clip(rs.getString("panel_name"), 24))
                  .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                  .append(";");
            }
            if (i == 0) return "[Power factor no signal] none";
            return sb.toString();
        }
    } catch (Exception e) {
        return "[Power factor no signal] unavailable: " + clip(e.getClass().getSimpleName(), 24);
    }
}

private String buildPowerFactorNoSignalListSnippet(String ctx) {
    if (ctx == null || ctx.trim().isEmpty() || ctx.contains("none") || ctx.contains("unavailable")) return null;
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.ArrayList<String> items = new java.util.ArrayList<String>();
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*t=([^;]+);"
    ).matcher(ctx);
    while (row.find()) {
        String meterId = trimToNull(row.group(1));
        String meterName = trimToNull(row.group(2));
        String panel = trimToNull(row.group(3));
        String ts = trimToNull(row.group(4));
        if (meterId == null || meterName == null) continue;
        String item = meterName + "(" + meterId + ")";
        if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
        if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
        items.add(item);
    }
    if (items.isEmpty()) return null;
    StringBuilder out = new StringBuilder();
    if (period == null || period.isEmpty()) out.append("신호없음 계측기 예시:\n");
    else out.append(period).append(" 신호없음 계측기 예시:\n");
    for (int i = 0; i < items.size(); i++) {
        out.append("- ").append(items.get(i));
        if (i + 1 < items.size()) out.append("\n");
    }
    return out.toString();
}

private String getVoltagePhaseAngleContext(Integer meterId) {
    String delegated = invokeAgentDbTool(
        "getVoltagePhaseAngleContext",
        new Class<?>[] { Integer.class },
        new Object[] { meterId }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getCurrentPhaseAngleContext",
        new Class<?>[] { Integer.class },
        new Object[] { meterId }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getPhaseCurrentContext",
        new Class<?>[] { Integer.class, String.class },
        new Object[] { meterId, phase }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getPhaseVoltageContext",
        new Class<?>[] { Integer.class, String.class },
        new Object[] { meterId, phase }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentDbTool(
        "getLineVoltageContext",
        new Class<?>[] { Integer.class, String.class },
        new Object[] { meterId, pair }
    );
    if (delegated != null) return delegated;
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
    String delegated = invokeAgentAnswerFormatter(
        "buildFrequencyDirectAnswer",
        new Class<?>[] { String.class, Integer.class, Integer.class },
        new Object[] { frequencyCtx, meterId, month }
    );
    if (delegated != null) return delegated;
    if (frequencyCtx == null || frequencyCtx.trim().isEmpty()) {
        return "월 평균 주파수 정보를 찾지 못했습니다.";
    }
    String ctx = frequencyCtx.trim();
    String period = null;
    java.util.regex.Matcher p = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    if (p.find()) period = p.group(1);
    if (period == null) period = "-";

    String subject = (meterId == null ? "전체 계측기의" : (meterId + "번 계측기의"));
    if (ctx.contains("no data")) {
        return subject + " " + period + " 평균 주파수 데이터가 없습니다.";
    }
    java.util.regex.Matcher a = java.util.regex.Pattern.compile("avg_hz=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher n = java.util.regex.Pattern.compile("samples=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("min_hz=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher mx = java.util.regex.Pattern.compile("max_hz=([0-9.\\-]+)").matcher(ctx);
    String avg = a.find() ? a.group(1) : "-";
    String samples = n.find() ? n.group(1) : "-";
    String min = mn.find() ? mn.group(1) : "-";
    String max = mx.find() ? mx.group(1) : "-";
    StringBuilder out = new StringBuilder();
    out.append(subject).append(" ").append(period).append(" 평균 주파수입니다.\n\n")
       .append("핵심 값:\n")
       .append("- 평균 주파수: ").append(avg).append("Hz\n")
       .append("- 최소: ").append(min).append("Hz\n")
       .append("- 최대: ").append(max).append("Hz\n")
       .append("- 샘플 수: ").append(samples);
    return out.toString();
}

private String buildPowerValueDirectAnswer(String meterCtx, boolean reactive) {
    String delegated = invokeAgentAnswerFormatter(
        "buildPowerValueDirectAnswer",
        new Class<?>[] { String.class, boolean.class },
        new Object[] { meterCtx, Boolean.valueOf(reactive) }
    );
    if (delegated != null) return delegated;
    if (meterCtx == null || meterCtx.trim().isEmpty()) {
        return reactive ? "무효전력 데이터를 찾지 못했습니다." : "유효전력 데이터를 찾지 못했습니다.";
    }
    if (meterCtx.contains("unavailable")) {
        return reactive ? "무효전력을 현재 조회할 수 없습니다." : "유효전력을 현재 조회할 수 없습니다.";
    }
    if (meterCtx.contains("no data")) {
        return reactive ? "요청한 계측기의 무효전력 데이터가 없습니다." : "요청한 계측기의 유효전력 데이터가 없습니다.";
    }
    java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(meterCtx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter_id=[0-9]+,\\s*([^,;]+),").matcher(meterCtx);
    java.util.regex.Matcher ts = java.util.regex.Pattern.compile("@\\s*([0-9\\-:\\s]+)\\s*V=").matcher(meterCtx);
    java.util.regex.Matcher kw = java.util.regex.Pattern.compile("kW=([0-9.\\-]+)").matcher(meterCtx);
    java.util.regex.Matcher kvar = java.util.regex.Pattern.compile("kVAr=([0-9.\\-]+)").matcher(meterCtx);
    String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
    String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
    String time = ts.find() ? trimToNull(ts.group(1)) : null;
    String value = reactive
        ? (kvar.find() ? trimToNull(kvar.group(1)) : null)
        : (kw.find() ? trimToNull(kw.group(1)) : null);
    if (meterId == null || value == null) {
        return reactive ? "요청한 계측기의 무효전력 데이터가 없습니다." : "요청한 계측기의 유효전력 데이터가 없습니다.";
    }
    String label = meterId + "번 계측기";
    if (meterName != null && !meterName.isEmpty() && !"-".equals(meterName)) label += "(" + meterName + ")";
    String unit = reactive ? "kVAr" : "kW";
    String subject = reactive ? "무효전력" : "유효전력";
    StringBuilder out = new StringBuilder();
    out.append(label).append(" ").append(subject).append(" 조회 결과입니다.\n\n")
       .append("핵심 값:\n")
       .append("- ").append(subject).append(": ").append(value).append(unit);
    if (time != null && !time.isEmpty()) {
        out.append("\n\n메타 정보:\n")
           .append("- 측정 시각: ").append(clip(time, 19));
    }
    return out.toString();
}

private String buildEnergyValueDirectAnswer(String energyCtx, boolean reactive) {
    String delegated = invokeAgentAnswerFormatter(
        "buildEnergyValueDirectAnswer",
        new Class<?>[] { String.class, boolean.class },
        new Object[] { energyCtx, Boolean.valueOf(reactive) }
    );
    if (delegated != null) return delegated;
    if (energyCtx == null || energyCtx.trim().isEmpty()) {
        return reactive ? "무효전력량 데이터를 찾지 못했습니다." : "전력량 데이터를 찾지 못했습니다.";
    }
    if (energyCtx.contains("unavailable")) {
        return reactive ? "무효전력량을 현재 조회할 수 없습니다." : "전력량을 현재 조회할 수 없습니다.";
    }
    if (energyCtx.contains("no data")) {
        return reactive ? "요청한 계측기의 무효전력량 데이터가 없습니다." : "요청한 계측기의 전력량 데이터가 없습니다.";
    }
    java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(energyCtx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter_id=[0-9]+,\\s*([^,;]+),").matcher(energyCtx);
    java.util.regex.Matcher ts = java.util.regex.Pattern.compile("t=([0-9\\-:\\s]+)").matcher(energyCtx);
    java.util.regex.Matcher kwh = java.util.regex.Pattern.compile("kWh=([0-9.\\-]+)").matcher(energyCtx);
    java.util.regex.Matcher kvarh = java.util.regex.Pattern.compile("kVArh=([0-9.\\-]+)").matcher(energyCtx);
    String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
    String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
    String time = ts.find() ? trimToNull(ts.group(1)) : null;
    String value = reactive
        ? (kvarh.find() ? trimToNull(kvarh.group(1)) : null)
        : (kwh.find() ? trimToNull(kwh.group(1)) : null);
    if (meterId == null || value == null) {
        return reactive ? "요청한 계측기의 무효전력량 데이터가 없습니다." : "요청한 계측기의 전력량 데이터가 없습니다.";
    }
    String label = meterId + "번 계측기";
    if (meterName != null && !meterName.isEmpty() && !"-".equals(meterName)) label += "(" + meterName + ")";
    String subject = reactive ? "무효전력량" : "전력량";
    String unit = reactive ? "kVArh" : "kWh";
    StringBuilder out = new StringBuilder();
    out.append(label).append(" ").append(subject).append(" 조회 결과입니다.\n\n")
       .append("핵심 값:\n")
       .append("- ").append(subject).append(": ").append(value).append(unit);
    if (time != null && !time.isEmpty()) {
        out.append("\n\n메타 정보:\n")
           .append("- 측정 시각: ").append(clip(time, 19));
    }
    return out.toString();
}

private String buildEnergyDeltaDirectAnswer(String ctx, boolean reactive) {
    String delegated = invokeAgentAnswerFormatter(
        "buildEnergyDeltaDirectAnswer",
        new Class<?>[] { String.class, boolean.class },
        new Object[] { ctx, Boolean.valueOf(reactive) }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return reactive ? "무효전력량 증가 데이터를 찾지 못했습니다." : "전력량 증가 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return reactive ? "무효전력량 증가량을 현재 조회할 수 없습니다." : "전력량 증가량을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
    if (ctx.contains("period required")) return "기간을 지정해 주세요.";
    if (ctx.contains("no data")) {
        return reactive ? "요청한 기간의 무효전력량 데이터가 없습니다." : "요청한 기간의 전력량 데이터가 없습니다.";
    }
    java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter=([^,]+)").matcher(ctx);
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^,]+)").matcher(ctx);
    java.util.regex.Matcher dm = java.util.regex.Pattern.compile("delta=([0-9.\\-]+)").matcher(ctx);
    String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
    String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    String delta = dm.find() ? trimToNull(dm.group(1)) : null;
    if (meterId == null || delta == null) {
        return reactive ? "요청한 기간의 무효전력량 데이터가 없습니다." : "요청한 기간의 전력량 데이터가 없습니다.";
    }
    String label = meterId + "번 계측기";
    if (meterName != null && !meterName.isEmpty() && !"-".equals(meterName)) label += "(" + meterName + ")";
    String subject = reactive ? "무효전력량 증가량" : "전력량 증가량";
    String unit = reactive ? "kVArh" : "kWh";
    String periodText = (period == null || period.isEmpty() || "-".equals(period)) ? "지정 기간" : period;
    return label + " " + periodText + " " + subject + " 조회 결과입니다.\n\n"
        + "핵심 값:\n- " + subject + ": " + delta + unit;
}

private String buildAlarmSeverityDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildAlarmSeverityDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return "심각도별 알람 집계 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "심각도별 알람 집계를 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "심각도별 알람 집계 데이터가 없습니다.";
    }

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    java.util.regex.Matcher dm = java.util.regex.Pattern.compile("days=([0-9]+)").matcher(ctx);
    String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
    String daysLabel = dm.find() ? dm.group(1) : null;

    java.util.regex.Matcher row = java.util.regex.Pattern.compile("(?:^|;)\\s*([^=;\\[\\]]+)=([0-9]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String sev = trimToNull(row.group(1));
        String cnt = trimToNull(row.group(2));
        if (sev == null || cnt == null) continue;
        if ("days".equalsIgnoreCase(sev) || "count".equalsIgnoreCase(sev) || "period".equalsIgnoreCase(sev)) continue;
        parts.add(sev + " " + cnt + "건");
    }
    if (parts.isEmpty()) {
        return "심각도별 알람 집계 데이터가 없습니다.";
    }

    StringBuilder out = new StringBuilder();
    if (periodLabel != null && !periodLabel.isEmpty()) {
        out.append(periodLabel).append(" 심각도별 알람 집계입니다.\n");
    } else if (daysLabel != null && !daysLabel.isEmpty()) {
        out.append("최근 ").append(daysLabel).append("일 심각도별 알람 집계입니다.\n");
    } else {
        out.append("심각도별 알람 집계입니다.\n");
    }
    for (int i = 0; i < parts.size(); i++) {
        out.append("- ").append(parts.get(i));
        if (i + 1 < parts.size()) out.append("\n");
    }
    return out.toString();
}

private String buildAlarmTypeDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildAlarmTypeDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return "알람 종류별 집계 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "알람 종류별 집계를 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "알람 종류별 집계 데이터가 없습니다.";
    }

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    java.util.regex.Matcher dm = java.util.regex.Pattern.compile("days=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher sm = java.util.regex.Pattern.compile("scope=([^;]+)").matcher(ctx);
    String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
    String daysLabel = dm.find() ? trimToNull(dm.group(1)) : null;
    String scopeLabel = sm.find() ? trimToNull(sm.group(1)) : null;

    java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^=;]+)=([0-9]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String type = trimToNull(row.group(1));
        String cnt = trimToNull(row.group(2));
        if (type == null || cnt == null) continue;
        parts.add(type + " " + cnt + "건");
    }
    if (parts.isEmpty()) {
        return "알람 종류별 집계 데이터가 없습니다.";
    }

    StringBuilder out = new StringBuilder();
    if (periodLabel != null && !periodLabel.isEmpty()) {
        out.append(periodLabel).append(" ");
    } else if (daysLabel != null && !daysLabel.isEmpty()) {
        out.append("최근 ").append(daysLabel).append("일 ");
    }
    if ("trip".equalsIgnoreCase(scopeLabel)) {
        out.append("TRIP 알람 종류별 집계입니다.\n");
    } else {
        out.append("알람 종류별 집계입니다.\n");
    }
    for (int i = 0; i < parts.size(); i++) {
        out.append("- ").append(parts.get(i));
        if (i + 1 < parts.size()) out.append("\n");
    }
    return out.toString();
}

private String buildAlarmMeterTopDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildAlarmMeterTopDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return "계측기별 알람 집계 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "계측기별 알람 집계를 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "조건에 맞는 계측기별 알람 집계 데이터가 없습니다.";
    }

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    java.util.regex.Matcher dm = java.util.regex.Pattern.compile("days=([0-9]+)").matcher(ctx);
    String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
    String daysLabel = dm.find() ? trimToNull(dm.group(1)) : null;
    java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^=;]+)=([0-9]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String meter = trimToNull(row.group(1));
        String cnt = trimToNull(row.group(2));
        if (meter == null || cnt == null) continue;
        parts.add(meter + " - " + cnt + "건");
    }
    if (parts.isEmpty()) {
        return "조건에 맞는 계측기별 알람 집계 데이터가 없습니다.";
    }

    StringBuilder out = new StringBuilder();
    if (periodLabel != null && !periodLabel.isEmpty()) {
        out.append(periodLabel).append(" 알람 발생 건수가 많은 계측기 목록입니다.\n");
    } else if (daysLabel != null && !daysLabel.isEmpty()) {
        out.append("최근 ").append(daysLabel).append("일 알람 발생 건수가 많은 계측기 목록입니다.\n");
    } else {
        out.append("알람 발생 건수가 많은 계측기 목록입니다.\n");
    }
    for (int i = 0; i < parts.size(); i++) {
        out.append(i + 1).append(". ").append(parts.get(i));
        if (i + 1 < parts.size()) out.append("\n");
    }
    return out.toString();
}

private String buildUsageAlarmTopDirectAnswer(String ctx) {
    return epms.util.AgentAnswerFormatter.buildUsageAlarmTopDirectAnswer(ctx);
}

private String buildUsageAlarmCountDirectAnswer(String ctx) {
    return epms.util.AgentAnswerFormatter.buildUsageAlarmCountDirectAnswer(ctx);
}

private String buildUsageTypeListDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildUsageTypeListDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return "용도 목록 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "용도 목록을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "등록된 용도 목록이 없습니다.";
    }

    java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^;]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String usage = trimToNull(row.group(1));
        if (usage == null) continue;
        parts.add(usage);
    }
    if (parts.isEmpty()) {
        return "등록된 용도 목록이 없습니다.";
    }

    StringBuilder out = new StringBuilder();
    out.append("등록된 용도 목록입니다.\n");
    for (int i = 0; i < parts.size(); i++) {
        out.append("- ").append(parts.get(i));
        if (i + 1 < parts.size()) out.append("\n");
    }
    return out.toString();
}

private String buildBuildingPowerTopDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildBuildingPowerTopDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return "건물별 전력 TOP 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "건물별 전력 TOP을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "건물별 전력 TOP 데이터가 없습니다.";
    }
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    String period = pm.find() ? pm.group(1) : "-";
    java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^:;]+):\\s*avg_kw=([0-9.\\-]+),\\s*sum_kwh=([0-9.\\-]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String building = trimToNull(row.group(1));
        String avgKw = trimToNull(row.group(2));
        String sumKwh = trimToNull(row.group(3));
        if (building == null || avgKw == null || sumKwh == null) continue;
        parts.add(building + " 평균전력 " + avgKw + "kW, 누적 " + sumKwh + "kWh");
    }
    if (parts.isEmpty()) {
        return "건물별 전력 TOP 데이터가 없습니다.";
    }
    return period + " 건물별 전력 TOP은 " + String.join(" / ", parts) + "입니다.";
}

private String buildScopedMonthlyEnergyDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) {
        return "구역별 전력 사용량 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("scope required")) {
        return "건물이나 구역을 지정해 주세요. 예: 동관의 전체 사용량은?";
    }
    if (ctx.contains("unavailable")) {
        return "구역별 전력 사용량을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "요청한 구역의 전력 사용량 데이터가 없습니다.";
    }
    java.util.regex.Matcher sm = java.util.regex.Pattern.compile("scope=([^;]+)").matcher(ctx);
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    java.util.regex.Matcher lm = java.util.regex.Pattern.compile("leaf_meter_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mm = java.util.regex.Pattern.compile("measured_meter_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher nm = java.util.regex.Pattern.compile("negative_delta_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher am = java.util.regex.Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher km = java.util.regex.Pattern.compile("sum_kwh=([0-9.\\-]+)").matcher(ctx);
    String scope = sm.find() ? trimToNull(sm.group(1)) : null;
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    String leafMeterCount = lm.find() ? trimToNull(lm.group(1)) : "0";
    String measuredMeterCount = mm.find() ? trimToNull(mm.group(1)) : "0";
    String negativeDeltaCount = nm.find() ? trimToNull(nm.group(1)) : "0";
    String avgKw = am.find() ? trimToNull(am.group(1)) : "-";
    String sumKwh = km.find() ? trimToNull(km.group(1)) : "-";
    String label = (scope == null || scope.isEmpty()) ? "해당 구역" : scope;
    String prefix = (period == null || period.isEmpty()) ? (label + " 전체 사용량 조회 결과입니다.") : (label + " " + period + " 전력 사용량입니다.");
    String result = prefix + "\n\n핵심 값:\n- 누적 전력량: " + sumKwh + "kWh\n- 평균전력: " + avgKw + "kW\n\n메타 정보:\n- 최종 리프 계측기 수: " + leafMeterCount + "개\n- 데이터 집계 리프 수: " + measuredMeterCount + "개";
    if (!"0".equals(negativeDeltaCount)) result += "\n- 리셋 의심 리프 수: " + negativeDeltaCount + "개";
    return result;
}

private String buildPanelMonthlyEnergyDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) {
        return "패널 전력 사용량 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("panel token required")) {
        return "패널명을 지정해 주세요. 예: MDB_3C 패널 전체 사용량은?";
    }
    if (ctx.contains("unavailable")) {
        return "패널 전력 사용량을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "요청한 패널의 전력 사용량 데이터가 없습니다.";
    }
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("panel=([^;]+)").matcher(ctx);
    java.util.regex.Matcher tm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    java.util.regex.Matcher lm = java.util.regex.Pattern.compile("leaf_meter_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mm = java.util.regex.Pattern.compile("measured_meter_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher nm = java.util.regex.Pattern.compile("negative_delta_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher am = java.util.regex.Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher km = java.util.regex.Pattern.compile("sum_kwh=([0-9.\\-]+)").matcher(ctx);
    String panel = pm.find() ? trimToNull(pm.group(1)) : null;
    String period = tm.find() ? trimToNull(tm.group(1)) : null;
    String leafMeterCount = lm.find() ? trimToNull(lm.group(1)) : "0";
    String measuredMeterCount = mm.find() ? trimToNull(mm.group(1)) : "0";
    String negativeDeltaCount = nm.find() ? trimToNull(nm.group(1)) : "0";
    String avgKw = am.find() ? trimToNull(am.group(1)) : "-";
    String sumKwh = km.find() ? trimToNull(km.group(1)) : "-";
    String label = (panel == null || panel.isEmpty()) ? "해당 패널" : panel;
    String prefix = (period == null || period.isEmpty()) ? (label + " 전력 사용량 조회 결과입니다.") : (label + " " + period + " 전력 사용량입니다.");
    String result = prefix + "\n\n핵심 값:\n- 누적 전력량: " + sumKwh + "kWh\n- 평균전력: " + avgKw + "kW\n\n메타 정보:\n- 최종 리프 계측기 수: " + leafMeterCount + "개\n- 데이터 집계 리프 수: " + measuredMeterCount + "개";
    if (!"0".equals(negativeDeltaCount)) result += "\n- 리셋 의심 리프 수: " + negativeDeltaCount + "개";
    return result;
}

private String buildUsageMonthlyEnergyDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) {
        return "용도별 전력 사용량 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("usage token required")) {
        return "용도를 지정해 주세요. 예: 동력 용도 전체 사용량은?";
    }
    if (ctx.contains("unavailable")) {
        return "용도별 전력 사용량을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "요청한 용도의 전력 사용량 데이터가 없습니다.";
    }
    java.util.regex.Matcher um = java.util.regex.Pattern.compile("usage=([^;]+)").matcher(ctx);
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    java.util.regex.Matcher lm = java.util.regex.Pattern.compile("leaf_meter_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mm = java.util.regex.Pattern.compile("measured_meter_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher nm = java.util.regex.Pattern.compile("negative_delta_count=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher am = java.util.regex.Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher km = java.util.regex.Pattern.compile("sum_kwh=([0-9.\\-]+)").matcher(ctx);
    String usage = um.find() ? trimToNull(um.group(1)) : null;
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    String leafMeterCount = lm.find() ? trimToNull(lm.group(1)) : "0";
    String measuredMeterCount = mm.find() ? trimToNull(mm.group(1)) : "0";
    String negativeDeltaCount = nm.find() ? trimToNull(nm.group(1)) : "0";
    String avgKw = am.find() ? trimToNull(am.group(1)) : "-";
    String sumKwh = km.find() ? trimToNull(km.group(1)) : "-";
    String label = (usage == null || usage.isEmpty()) ? "해당 용도" : usage + " 용도";
    String prefix = (period == null || period.isEmpty()) ? (label + " 전력 사용량 조회 결과입니다.") : (label + " " + period + " 전력 사용량입니다.");
    String result = prefix + "\n\n핵심 값:\n- 누적 전력량: " + sumKwh + "kWh\n- 평균전력: " + avgKw + "kW\n\n메타 정보:\n- 최종 리프 계측기 수: " + leafMeterCount + "개\n- 데이터 집계 리프 수: " + measuredMeterCount + "개";
    if (!"0".equals(negativeDeltaCount)) result += "\n- 리셋 의심 리프 수: " + negativeDeltaCount + "개";
    return result;
}

private String buildUsagePowerTopDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) {
        return "용도별 전력 TOP 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "용도별 전력 TOP을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "용도별 전력 TOP 데이터가 없습니다.";
    }
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    String period = pm.find() ? pm.group(1) : "-";
    java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^:;]+):\\s*avg_kw=([0-9.\\-]+),\\s*sum_kwh=([0-9.\\-]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String usage = trimToNull(row.group(1));
        String avgKw = trimToNull(row.group(2));
        String sumKwh = trimToNull(row.group(3));
        if (usage == null || avgKw == null || sumKwh == null) continue;
        parts.add(usage + " 평균전력 " + avgKw + "kW, 누적 " + sumKwh + "kWh");
    }
    if (parts.isEmpty()) {
        return "용도별 전력 TOP 데이터가 없습니다.";
    }
    return period + " 용도별 전력 TOP은 " + String.join(" / ", parts) + "입니다.";
}

private String buildUsageMeterTopDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) {
        return "용도별 계측기 수 TOP 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "용도별 계측기 수 TOP을 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "용도별 계측기 수 TOP 데이터가 없습니다.";
    }
    java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^:;]+):\\s*count=([0-9]+);").matcher(ctx);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    while (row.find()) {
        String usage = trimToNull(row.group(1));
        String count = trimToNull(row.group(2));
        if (usage == null || count == null) continue;
        parts.add(usage + " " + count + "개");
    }
    if (parts.isEmpty()) {
        return "용도별 계측기 수 TOP 데이터가 없습니다.";
    }
    return "계측기를 가장 많이 가진 용도는 " + String.join(" / ", parts) + "입니다.";
}

private String buildVoltageUnbalanceTopDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildVoltageUnbalanceTopDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) {
        return "전압 불평형 상위 데이터를 찾지 못했습니다.";
    }
    if (ctx.contains("unavailable")) {
        return "전압 불평형 상위를 현재 조회할 수 없습니다.";
    }
    if (ctx.contains("no data")) {
        return "전압 불평형 데이터가 없습니다.";
    }
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*unb=([0-9.\\-]+),\\s*t=([^;]+);"
    ).matcher(ctx);
    while (row.find()) {
        String meterId = trimToNull(row.group(1));
        String meterName = trimToNull(row.group(2));
        String unb = trimToNull(row.group(3));
        String ts = trimToNull(row.group(4));
        if (meterId == null || meterName == null || unb == null) continue;
        String item = meterName + "(" + meterId + ") " + unb + "%";
        if (ts != null && !ts.isEmpty()) item += " @ " + clip(ts, 19);
        parts.add(item);
    }
    if (parts.isEmpty()) {
        return "전압 불평형 데이터가 없습니다.";
    }
    String prefix = (period == null || period.isEmpty()) ? "전압 불평형 상위는 " : (period + " 전압 불평형 상위는 ");
    return prefix + String.join(" / ", parts) + "입니다.";
}

private String buildHarmonicExceedDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildHarmonicExceedDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) {
        boolean delegatedLooksEmpty = delegated.contains("고조파 이상 계측기가 없습니다");
        boolean ctxLooksPopulated = ctx != null && ctx.contains("meter_id=") && !ctx.contains("none") && !ctx.contains("no data");
        if (!delegatedLooksEmpty || !ctxLooksPopulated) {
            return delegated;
        }
    }
    if (ctx == null || ctx.trim().isEmpty()) return "고조파 이상 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "고조파 이상 데이터를 현재 조회할 수 없습니다.";
    if (ctx.contains("none") || ctx.contains("no data")) return "고조파 이상 계측기가 없습니다.";

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.ArrayList<String> items = new java.util.ArrayList<String>();
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),(?:\\s*panel=([^,;]*),)?\\s*t=([^,;]+),\\s*TV=([0-9./\\-]+),\\s*TI=([0-9./\\-]+);"
    ).matcher(ctx);
    while (row.find()) {
        String meterId = trimToNull(row.group(1));
        String meterName = trimToNull(row.group(2));
        String panel = trimToNull(row.group(3));
        String ts = trimToNull(row.group(4));
        String thdV = trimToNull(row.group(5));
        String thdI = trimToNull(row.group(6));
        if (meterId == null || meterName == null) continue;
        String item = meterName + "(" + meterId + ")";
        if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
        item += " / THD_V " + thdV + " / THD_I " + thdI;
        if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
        items.add(item);
    }
    if (items.isEmpty()) return "고조파 이상 계측기가 없습니다.";
    StringBuilder out = new StringBuilder();
    if (period == null || period.isEmpty()) out.append("고조파 이상 계측기 목록입니다.\n");
    else out.append(period).append(" 고조파 이상 계측기 목록입니다.\n");
    for (int i = 0; i < items.size(); i++) {
        out.append("- ").append(items.get(i));
        if (i + 1 < items.size()) out.append("\n");
    }
    return out.toString();
}

private String buildHarmonicExceedCountDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) return "고조파 이상 건수를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "고조파 이상 건수를 현재 조회할 수 없습니다.";
    if (ctx.contains("none") || ctx.contains("no data")) return "고조파 이상 계측기는 0개입니다.";
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.regex.Matcher row = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
    int count = 0;
    while (row.find()) count++;
    if (count <= 0) return "고조파 이상 계측기는 0개입니다.";
    if (period == null || period.isEmpty()) return "고조파 이상 계측기는 총 " + count + "개입니다.";
    return period + " 고조파 이상 계측기는 총 " + count + "개입니다.";
}

private String buildHarmonicExceedStandardDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildHarmonicExceedStandardDirectAnswer();
}

private String buildPowerFactorThresholdDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildPowerFactorThresholdDirectAnswer();
}

private String buildEpmsKnowledgeDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildEpmsKnowledgeDirectAnswer();
}

private String buildFrequencyOutlierStandardDirectAnswer() {
    return epms.util.AgentCriticalDirectAnswerHelper.buildFrequencyOutlierStandardDirectAnswer();
}

private String buildCurrentUnbalanceCountDirectAnswer(String ctx) {
    if (ctx == null || ctx.trim().isEmpty()) return "전류 불평형 계측기 수를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "전류 불평형 계측기 수를 현재 조회할 수 없습니다.";
    java.util.regex.Matcher tm = java.util.regex.Pattern.compile("threshold=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    java.util.regex.Matcher cm = java.util.regex.Pattern.compile("count=([0-9]+)").matcher(ctx);
    String threshold = tm.find() ? trimToNull(tm.group(1)) : "10.00";
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    String count = cm.find() ? trimToNull(cm.group(1)) : "0";
    if (period == null || period.isEmpty()) {
        return "전류 불평형 10% 초과 계측기는 총 " + count + "개입니다.".replace("10", threshold);
    }
    return period + " 기준 전류 불평형 " + threshold + "% 초과 계측기는 총 " + count + "개입니다.";
}

private String buildPowerFactorOutlierDirectAnswer(String ctx, int noSignalCount) {
    String delegated = invokeAgentAnswerFormatter(
        "buildPowerFactorOutlierDirectAnswer",
        new Class<?>[] { String.class, int.class },
        new Object[] { ctx, Integer.valueOf(noSignalCount) }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) return "역률 이상 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "역률 이상 데이터를 현재 조회할 수 없습니다.";
    if (ctx.contains("none") || ctx.contains("no data")) {
        if (noSignalCount >= 0) return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다. (신호없음 " + noSignalCount + "개 별도)";
        return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다.";
    }

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.ArrayList<String> items = new java.util.ArrayList<String>();
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*pf=([0-9.\\-]+),\\s*t=([^;]+);"
    ).matcher(ctx);
    while (row.find()) {
        String meterId = trimToNull(row.group(1));
        String meterName = trimToNull(row.group(2));
        String panel = trimToNull(row.group(3));
        String pf = trimToNull(row.group(4));
        String ts = trimToNull(row.group(5));
        if (meterId == null || meterName == null || pf == null) continue;
        String item = meterName + "(" + meterId + ")";
        if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
        item += " / PF " + pf;
        if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
        items.add(item);
    }
    if (items.isEmpty()) {
        if (noSignalCount >= 0) return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다. (신호없음 " + noSignalCount + "개 별도)";
        return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다.";
    }
    StringBuilder out = new StringBuilder();
    if (period == null || period.isEmpty()) out.append("역률 이상 계측기 목록입니다.\n");
    else out.append(period).append(" 역률 이상 계측기 목록입니다.\n");
    for (int i = 0; i < items.size(); i++) {
        out.append("- ").append(items.get(i));
        if (i + 1 < items.size()) out.append("\n");
    }
    if (noSignalCount >= 0) {
        out.append("\n\n메타 정보:\n- 신호없음 별도 계측기: ").append(noSignalCount).append("개");
    }
    return out.toString();
}

private String buildFrequencyOutlierDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildFrequencyOutlierDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) return "주파수 이상치 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "주파수 이상치 데이터를 현재 조회할 수 없습니다.";
    if (ctx.contains("none") || ctx.contains("no data")) return "주파수 이상치가 없습니다.";

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.ArrayList<String> items = new java.util.ArrayList<String>();
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*Hz=([0-9.\\-]+),\\s*t=([^;]+);"
    ).matcher(ctx);
    while (row.find()) {
        String meterId = trimToNull(row.group(1));
        String meterName = trimToNull(row.group(2));
        String panel = trimToNull(row.group(3));
        String hz = trimToNull(row.group(4));
        String ts = trimToNull(row.group(5));
        if (meterId == null || meterName == null || hz == null) continue;
        String item = meterName + "(" + meterId + ")";
        if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
        item += " / " + hz + "Hz";
        if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
        items.add(item);
    }
    if (items.isEmpty()) return "주파수 이상치가 없습니다.";
    StringBuilder out = new StringBuilder();
    if (period == null || period.isEmpty()) out.append("주파수 이상치 목록입니다.\n");
    else out.append(period).append(" 주파수 이상치 목록입니다.\n");
    for (int i = 0; i < items.size(); i++) {
        out.append("- ").append(items.get(i));
        if (i + 1 < items.size()) out.append("\n");
    }
    return out.toString();
}

private String buildMonthlyPowerStatsDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildMonthlyPowerStatsDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) return "월 전력 통계 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "월 전력 통계를 현재 조회할 수 없습니다.";
    if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
    if (ctx.contains("no data")) return "요청한 월 전력 통계 데이터가 없습니다.";

    java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    java.util.regex.Matcher am = java.util.regex.Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher mm = java.util.regex.Pattern.compile("max_kw=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher sm = java.util.regex.Pattern.compile("samples=([0-9]+)").matcher(ctx);
    String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    String avgKw = am.find() ? trimToNull(am.group(1)) : null;
    String maxKw = mm.find() ? trimToNull(mm.group(1)) : null;
    String samples = sm.find() ? trimToNull(sm.group(1)) : null;
    if (meterId == null || period == null || avgKw == null || maxKw == null) {
        return "요청한 월 전력 통계 데이터가 없습니다.";
    }
    StringBuilder out = new StringBuilder();
    out.append(meterId).append("번 계측기 ").append(period).append(" 월 전력 통계입니다.\n\n")
       .append("핵심 값:\n")
       .append("- 평균전력: ").append(avgKw).append("kW\n")
       .append("- 최대전력: ").append(maxKw).append("kW");
    if (samples != null && !samples.isEmpty()) {
        out.append("\n\n메타 정보:\n")
           .append("- 표본 수: ").append(samples).append("건");
    }
    return out.toString();
}

private String buildMonthlyPeakPowerDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildMonthlyPeakPowerDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) return "월 최대 피크 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "월 최대 피크를 현재 조회할 수 없습니다.";
    if (ctx.contains("no data")) return "요청한 월 최대 피크 데이터가 없습니다.";

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
    java.util.regex.Matcher mid = java.util.regex.Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
    java.util.regex.Matcher mn = java.util.regex.Pattern.compile("meter_name=([^;]+)").matcher(ctx);
    java.util.regex.Matcher pn = java.util.regex.Pattern.compile("panel=([^;]+)").matcher(ctx);
    java.util.regex.Matcher pk = java.util.regex.Pattern.compile("peak_kw=([0-9.\\-]+)").matcher(ctx);
    java.util.regex.Matcher tm = java.util.regex.Pattern.compile("t=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
    String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
    String panel = pn.find() ? trimToNull(pn.group(1)) : null;
    String peakKw = pk.find() ? trimToNull(pk.group(1)) : null;
    String measuredAt = tm.find() ? trimToNull(tm.group(1)) : null;
    if (period == null || peakKw == null) return "요청한 월 최대 피크 데이터가 없습니다.";

    StringBuilder out = new StringBuilder();
    out.append(period).append(" 최대 피크 전력 조회 결과입니다.\n\n")
       .append("핵심 값:\n")
       .append("- 최대 피크: ").append(peakKw).append("kW");
    if (meterId != null && meterName != null) {
        out.append("\n- 계측기: ").append(meterName).append(" (").append(meterId).append(")");
    }
    if (panel != null && !panel.isEmpty() && !"-".equals(panel)) {
        out.append("\n- 패널: ").append(panel);
    }
    if (measuredAt != null && !measuredAt.isEmpty()) {
        out.append("\n- 시각: ").append(measuredAt);
    }
    return out.toString();
}

private String shortenAlarmDescription(String desc) {
    String text = trimToNull(desc);
    if (text == null) return null;
    java.util.regex.Matcher tag = java.util.regex.Pattern.compile("tag=([^,]+)").matcher(text);
    java.util.regex.Matcher point = java.util.regex.Pattern.compile("point=([0-9]+)").matcher(text);
    java.util.regex.Matcher addr = java.util.regex.Pattern.compile("addr=([0-9]+)").matcher(text);
    java.util.regex.Matcher bit = java.util.regex.Pattern.compile("bit=([0-9]+)").matcher(text);
    java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
    if (tag.find()) parts.add(clip(trimToNull(tag.group(1)), 20));
    if (point.find()) parts.add("point " + point.group(1));
    if (addr.find()) parts.add("addr " + addr.group(1));
    if (bit.find()) parts.add("bit " + bit.group(1));
    if (!parts.isEmpty()) return String.join(", ", parts);
    text = text.replace("PLC 1 DI ON:", "").replace("PLC 1 DI OFF:", "").trim();
    return clip(text, 36);
}

private String compactAlarmList(java.util.List<String[]> rows, String prefix) {
    if (rows == null || rows.isEmpty()) return prefix + "없습니다.";
    String firstSev = trimToNull(rows.get(0)[0]);
    String firstType = trimToNull(rows.get(0)[1]);
    boolean sameHeader = firstType != null;
    for (int i = 1; i < rows.size(); i++) {
        String sev = trimToNull(rows.get(i)[0]);
        String type = trimToNull(rows.get(i)[1]);
        if (!java.util.Objects.equals(firstSev, sev) || !java.util.Objects.equals(firstType, type)) {
            sameHeader = false;
            break;
        }
    }
    java.util.ArrayList<String> items = new java.util.ArrayList<String>();
    for (int i = 0; i < rows.size(); i++) {
        String[] row = rows.get(i);
        String sev = trimToNull(row[0]);
        String type = trimToNull(row[1]);
        String meter = trimToNull(row[2]);
        String ts = trimToNull(row[3]);
        String state = trimToNull(row[4]);
        String desc = trimToNull(row[5]);
        String item;
        if (sameHeader) {
            item = (meter == null ? "-" : meter);
            if (ts != null) item += " " + clip(ts, 19);
            if (state != null && !state.isEmpty()) item += " [" + state + "]";
        } else {
            item = (sev == null ? "-" : sev) + "/" + (type == null ? "-" : type) + " @ " + (meter == null ? "-" : meter);
            if (ts != null) item += " " + clip(ts, 19);
            if (state != null && !state.isEmpty()) item += " [" + state + "]";
        }
        if (desc != null && !desc.isEmpty()) item += " - " + desc;
        items.add(item);
    }
    if (sameHeader) {
        String header = (firstSev == null ? "-" : firstSev) + "/" + firstType;
        return prefix + header + " " + rows.size() + "건으로, " + String.join(" / ", items) + "입니다.";
    }
    java.util.LinkedHashMap<String, java.util.ArrayList<String>> grouped = new java.util.LinkedHashMap<String, java.util.ArrayList<String>>();
    for (int i = 0; i < rows.size(); i++) {
        String[] row = rows.get(i);
        String sev = trimToNull(row[0]);
        String type = trimToNull(row[1]);
        String meter = trimToNull(row[2]);
        String ts = trimToNull(row[3]);
        String state = trimToNull(row[4]);
        String desc = trimToNull(row[5]);
        String header = (sev == null ? "-" : sev) + "/" + (type == null ? "-" : type);
        java.util.ArrayList<String> bucket = grouped.get(header);
        if (bucket == null) {
            bucket = new java.util.ArrayList<String>();
            grouped.put(header, bucket);
        }
        String item = (meter == null ? "-" : meter);
        if (ts != null) item += " " + clip(ts, 19);
        if (state != null && !state.isEmpty()) item += " [" + state + "]";
        if (desc != null && !desc.isEmpty()) item += " - " + desc;
        bucket.add(item);
    }
    java.util.ArrayList<String> groups = new java.util.ArrayList<String>();
    for (java.util.Map.Entry<String, java.util.ArrayList<String>> e : grouped.entrySet()) {
        java.util.ArrayList<String> bucket = e.getValue();
        groups.add(e.getKey() + " " + bucket.size() + "건: " + String.join(" / ", bucket));
    }
    return prefix + String.join(" ; ", groups) + "입니다.";
}

private String buildLatestAlarmsDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildLatestAlarmsDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) return "최근 알람 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "알람 데이터를 현재 조회할 수 없습니다.";
    if (ctx.contains("no recent alarm")) return "최근 알람이 없습니다.";

    java.util.regex.Matcher um = java.util.regex.Pattern.compile("unresolved=([0-9]+)").matcher(ctx);
    String unresolved = um.find() ? um.group(1) : null;
    java.util.ArrayList<String[]> rowsOut = new java.util.ArrayList<String[]>();
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)([^/;]+)/([^@;]+) @ ([^,;]+) t=([0-9\\-:\\s]+),\\s*cleared=([YN])(?:,\\s*desc=([^;]+))?;"
    ).matcher(ctx);
    while (row.find()) {
        String sev = trimToNull(row.group(1));
        String type = trimToNull(row.group(2));
        String meter = trimToNull(row.group(3));
        String ts = trimToNull(row.group(4));
        String cleared = trimToNull(row.group(5));
        String desc = trimToNull(row.group(6));
        if (type == null || meter == null) continue;
        String shortDesc = shortenAlarmDescription(desc);
        rowsOut.add(new String[] {
            sev,
            type,
            meter,
            ts,
            "Y".equalsIgnoreCase(cleared) ? "해결" : "미해결",
            shortDesc
        });
    }
    if (rowsOut.isEmpty()) {
        if (unresolved != null) return "최근 알람 요약입니다. 현재 미해결 알람은 " + unresolved + "건입니다.";
        return "최근 알람이 없습니다.";
    }
    StringBuilder out = new StringBuilder();
    if (unresolved != null) {
        out.append("현재 미해결 알람은 ").append(unresolved).append("건입니다.\n\n");
    } else {
        out.append("최근 알람 요약입니다.\n\n");
    }
    out.append("최근 알람:\n");
    int limit = Math.min(rowsOut.size(), 3);
    for (int i = 0; i < limit; i++) {
        String[] rowData = rowsOut.get(i);
        String sev = trimToNull(rowData[0]);
        String type = trimToNull(rowData[1]);
        String meter = trimToNull(rowData[2]);
        String ts = trimToNull(rowData[3]);
        String state = trimToNull(rowData[4]);
        String desc = trimToNull(rowData[5]);
        out.append("- ");
        if (sev != null && !sev.isEmpty()) out.append("[").append(sev).append("] ");
        out.append(type == null ? "-" : type);
        out.append(" / ").append(meter == null ? "-" : meter);
        if (ts != null && !ts.isEmpty()) out.append(" / ").append(clip(ts, 19));
        if (state != null && !state.isEmpty()) out.append(" / ").append(state);
        if (desc != null && !desc.isEmpty()) out.append(" / ").append(desc);
        if (i + 1 < limit) out.append("\n");
    }
    if (rowsOut.size() > limit) {
        out.append("\n\n그 외 ").append(rowsOut.size() - limit).append("건의 최근 알람이 더 있습니다.");
    }
    return out.toString();
}

private String buildOpenAlarmsDirectAnswer(String ctx) {
    String delegated = invokeAgentAnswerFormatter(
        "buildOpenAlarmsDirectAnswer",
        new Class<?>[] { String.class },
        new Object[] { ctx }
    );
    if (delegated != null) return delegated;
    if (ctx == null || ctx.trim().isEmpty()) return "열린 알람 데이터를 찾지 못했습니다.";
    if (ctx.contains("unavailable")) return "열린 알람 데이터를 현재 조회할 수 없습니다.";
    if (ctx.contains("none") || ctx.contains("no data")) return "현재 미해결 알람이 없습니다.";

    java.util.regex.Matcher pm = java.util.regex.Pattern.compile("period=([^;]+)").matcher(ctx);
    String period = pm.find() ? trimToNull(pm.group(1)) : null;
    java.util.ArrayList<String[]> rowsOut = new java.util.ArrayList<String[]>();
    java.util.regex.Matcher row = java.util.regex.Pattern.compile(
        "\\s[0-9]+\\)([^/;]+)/([^@;]+) @ ([^,;]+),\\s*t=([0-9\\-:\\s]+),\\s*desc=([^;]+);"
    ).matcher(ctx);
    while (row.find()) {
        String sev = trimToNull(row.group(1));
        String type = trimToNull(row.group(2));
        String meter = trimToNull(row.group(3));
        String ts = trimToNull(row.group(4));
        String desc = trimToNull(row.group(5));
        if (type == null || meter == null) continue;
        String shortDesc = shortenAlarmDescription(desc);
        rowsOut.add(new String[] { sev, type, meter, ts, null, shortDesc });
    }
    if (rowsOut.isEmpty()) return "현재 미해결 알람이 없습니다.";
    StringBuilder out = new StringBuilder();
    if (period == null || period.isEmpty()) {
        out.append("현재 미해결 알람 목록입니다.\n");
    } else {
        out.append(period).append(" 미해결 알람 목록입니다.\n");
    }
    int limit = Math.min(rowsOut.size(), 5);
    for (int i = 0; i < limit; i++) {
        String[] rowData = rowsOut.get(i);
        String sev = trimToNull(rowData[0]);
        String type = trimToNull(rowData[1]);
        String meter = trimToNull(rowData[2]);
        String ts = trimToNull(rowData[3]);
        String desc = trimToNull(rowData[5]);
        out.append("- ");
        if (sev != null && !sev.isEmpty()) out.append("[").append(sev).append("] ");
        out.append(type == null ? "-" : type);
        out.append(" / ").append(meter == null ? "-" : meter);
        if (ts != null && !ts.isEmpty()) out.append(" / ").append(clip(ts, 19));
        if (desc != null && !desc.isEmpty()) out.append(" / ").append(desc);
        if (i + 1 < limit) out.append("\n");
    }
    if (rowsOut.size() > limit) {
        out.append("\n\n그 외 ").append(rowsOut.size() - limit).append("건의 미해결 알람이 더 있습니다.");
    }
    return out.toString();
}

private String buildDirectDbSummary(String userMessage, String meterCtx, String alarmCtx) {
    boolean meter = routedWantsMeterSummary(userMessage);
    boolean alarm = routedWantsAlarmSummary(userMessage);
    if (!meter && !alarm) return null;

    StringBuilder sb = new StringBuilder();
    if (meter) {
        String meterText = buildUserDbContext(meterCtx);
        if (meterText == null || meterText.trim().isEmpty()) meterText = "최근 계측값을 조회했습니다.";
        sb.append(meterText);
    }
    if (alarm) {
        String alarmText = buildLatestAlarmsDirectAnswer(alarmCtx);
        if (alarmText == null || alarmText.trim().isEmpty()) alarmText = "최근 알람이 없습니다.";
        if (sb.length() > 0) sb.append("\n\n");
        sb.append(alarmText);
    }
    return sb.toString();
}

private String buildUserDbContext(String dbContext) {
    String ctx = dbContext == null ? "" : dbContext.trim();
    if (ctx.isEmpty()) return "";
    if (ctx.contains("[Power factor outlier]")) {
        int noSignalCount = getPowerFactorNoSignalCount();
        String answer = buildPowerFactorOutlierDirectAnswer(ctx, noSignalCount);
        if ((ctx.contains("none") || ctx.contains("no data")) && noSignalCount > 0) {
            String noSignalCtx = getPowerFactorNoSignalListContext(10, null, null, null);
            String snippet = buildPowerFactorNoSignalListSnippet(noSignalCtx);
            if (snippet != null && !snippet.trim().isEmpty()) {
                answer = answer + "\n\n" + snippet.trim();
            }
        }
        return answer;
    }

    String delegated = invokeAgentAnswerFormatter(
        "buildUserDbContext",
        new Class<?>[] { String.class },
        new Object[] { dbContext }
    );
    if (delegated != null) return delegated;
    if (ctx.contains("[Harmonic exceed standard]")) return buildHarmonicExceedStandardDirectAnswer();
    if (ctx.contains("[EPMS knowledge]")) return buildEpmsKnowledgeDirectAnswer();
    if (ctx.contains("[Frequency outlier standard]")) return buildFrequencyOutlierStandardDirectAnswer();
    if (ctx.contains("[PF threshold]")) return buildPowerFactorThresholdDirectAnswer();
    if (ctx.contains("[Current unbalance count]")) return buildCurrentUnbalanceCountDirectAnswer(ctx);
    if (ctx.contains("[Scoped monthly energy]")) return buildScopedMonthlyEnergyDirectAnswer(ctx);
    if (ctx.contains("[Panel monthly energy]")) return buildPanelMonthlyEnergyDirectAnswer(ctx);
    if (ctx.contains("[Usage monthly energy]")) return buildUsageMonthlyEnergyDirectAnswer(ctx);
    if (ctx.contains("[Usage power TOP]")) return buildUsagePowerTopDirectAnswer(ctx);
    if (ctx.contains("[Building power TOP]")) return buildBuildingPowerTopDirectAnswer(ctx);
    if (ctx.contains("[Alarm meter TOP]")) return buildAlarmMeterTopDirectAnswer(ctx);
    if (ctx.contains("[Usage type list]")) return buildUsageTypeListDirectAnswer(ctx);
    if (ctx.contains("[Monthly peak power]")) return buildMonthlyPeakPowerDirectAnswer(ctx);

    String fallback = ctx
        .replace("STATE=NO_SIGNAL", "신호없음")
        .replace("meter_id=", "계측기 ")
        .replace("no data", "데이터 없음")
        .replace("unavailable", "조회 불가");
    return clip(fallback, 600);
}

private void writeSuccessJson(javax.servlet.jsp.JspWriter out, javax.servlet.http.HttpServletResponse response, String finalAnswer, String dbContext, boolean isAdmin) throws java.io.IOException {
    String userDbContext = buildUserDbContext(dbContext);
    String rawDbContext = isAdmin ? dbContext : "";
    response.setStatus(200);
    String builtPayload = buildSuccessJsonPayload(finalAnswer, rawDbContext, userDbContext, isAdmin);
    if (builtPayload != null) {
        out.print(builtPayload);
        return;
    }
    String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";
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

private void writeErrorJson(javax.servlet.jsp.JspWriter out, javax.servlet.http.HttpServletResponse response, int statusCode, String errorMessage) throws java.io.IOException {
    response.setStatus(statusCode);
    out.print(buildErrorJsonPayload(errorMessage));
}

private List<String> panelTokensFromRaw(String panel) {
    return epms.util.AgentSupport.panelTokensFromRaw(panel);
}

private String unescapeJsonText(String s) {
    return epms.util.AgentSupport.unescapeJsonText(s);
}

private String extractJsonStringField(String json, String field) {
    return epms.util.AgentSupport.extractJsonStringField(json, field);
}

private Integer extractJsonIntField(String json, String field) {
    return epms.util.AgentSupport.extractJsonIntField(json, field);
}

private Boolean extractJsonBoolField(String json, String field) {
    return epms.util.AgentSupport.extractJsonBoolField(json, field);
}

private String callOllamaOnce(String ollamaUrl, String model, String prompt, int connectTimeoutMs, int readTimeoutMs, double temperature) throws Exception {
    String payload = "{\"model\":\"" + model + "\",\"prompt\":" + jsonEscape(prompt) + ",\"stream\":false,\"temperature\":" + temperature + "}";
    epms.util.AgentSupport.HttpResponse resp = callOllamaEndpoint(
        ollamaUrl + "/api/generate",
        "POST",
        payload,
        connectTimeoutMs,
        readTimeoutMs
    );
    String body = resp.body == null ? "" : resp.body;
    if (resp.statusCode < 200 || resp.statusCode >= 400) {
        throw new RuntimeException("Ollama error " + resp.statusCode + ": " + clip(body, 300));
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
    return epms.util.AgentAnswerGuardSupport.sanitizeUngroundedJudgement(answer, dbContext);
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
    writeErrorJson(out, response, 400, "Invalid request context");
    return;
}
boolean forceLlmOnly = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_FORCE_LLM_ONLY));
boolean forceRuleOnly = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_FORCE_RULE_ONLY));
boolean preferNarrativeHint = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_PREFERS_NARRATIVE_HINT));
boolean preferNarrativeLlm = (preferNarrativeHint || localPrefersNarrativeLlm(userMessage)) && !forceLlmOnly && !forceRuleOnly;
boolean forceAiNarrative = isAiDesignIntent(userMessage) && !forceLlmOnly && !forceRuleOnly;
boolean bypassDirect = shouldBypassDirect(forceLlmOnly, preferNarrativeLlm);
boolean bypassSpecialized = shouldBypassSpecialized(forceLlmOnly, preferNarrativeLlm);
if (forceAiNarrative) {
    bypassDirect = true;
    bypassSpecialized = true;
}

boolean isAdmin = java.lang.Boolean.TRUE.equals(request.getAttribute(epms.agent.AgentApiRequestSupport.ATTR_IS_ADMIN));

DirectAnswerResult criticalDirectResult = tryBuildCriticalDirectAnswer(userMessage, forceLlmOnly);
if (criticalDirectResult != null) {
    int meterCount = countDistinctMeterIds(criticalDirectResult.dbContext);
    criticalDirectResult.answer = finalizeDirectAnswer(criticalDirectResult.answer, criticalDirectResult.dbContext, meterCount);
    writeSuccessJson(out, response, criticalDirectResult.answer, criticalDirectResult.dbContext, isAdmin);
    return;
}

DirectAnswerResult directResult = tryBuildDirectAnswer(userMessage, bypassDirect);
if (directResult != null) {
    int meterCount = countDistinctMeterIds(directResult.dbContext);
    directResult.answer = finalizeDirectAnswer(directResult.answer, directResult.dbContext, meterCount);
    writeSuccessJson(out, response, directResult.answer, directResult.dbContext, isAdmin);
    return;
}

if (forceRuleOnly) {
    writeSuccessJson(
        out,
        response,
        getRuleOnlyFallbackMessage(),
        "[Rule mode] no direct match",
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
        writeErrorJson(out, response, 400, e.getMessage());
        return;
    } catch (Exception e) {
        writeErrorJson(out, response, 502, "Cannot reach Ollama");
        return;
    }

    AgentRequestContext reqCtx = buildAgentRequestContext(userMessage);
    AgentExecutionContext execCtx = buildExecutionContext(userMessage, reqCtx, runtimeModels.model, runtimeModels.coderModel);
    if (forceAiNarrative) {
        epms.util.AgentExecutionSupport.clearDbNeeds(execCtx);
    }
    String schemaContext = getSchemaContextCached();

    // Stage 1: qwen2.5:14b classifies whether DB lookup is required.
    String classifierRaw = "{}";
    if (!forceAiNarrative) {
        String classifierPrompt = epms.util.AgentRuntimeFlowSupport.buildClassifierPrompt(userMessage);
        classifierRaw = callOllamaOnce(
            runtimeModels.ollamaUrl,
            runtimeModels.model,
            classifierPrompt,
            runtimeModels.ollamaConnectTimeoutMs,
            runtimeModels.ollamaReadTimeoutMs,
            0.1d
        );
        applyClassifierHints(execCtx, userMessage, classifierRaw);
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
    String dbContext = buildDbContext(execCtx, plannerResult, userMessage);

    SpecializedAnswerResult specializedAnswer = bypassSpecialized ? null : tryBuildSpecializedAnswer(execCtx, plannerResult);
    if (specializedAnswer != null) {
        writeSuccessJson(out, response, specializedAnswer.answer, dbContext, isAdmin);
        return;
    }

    // Stage 3: qwen2.5:14b creates final user-facing answer.
    String finalPrompt = buildFinalPrompt(execCtx.needsDb, userMessage, dbContext);
    String finalModel = routeFinalModel(
        userMessage,
        runtimeModels.model,
        runtimeModels.aiModel,
        runtimeModels.pqModel,
        runtimeModels.alarmModel
    );
    String finalAnswer = callOllamaOnce(
        runtimeModels.ollamaUrl,
        finalModel,
        finalPrompt,
        runtimeModels.ollamaConnectTimeoutMs,
        runtimeModels.ollamaReadTimeoutMs,
        0.4d
    );
    finalAnswer = sanitizeUngroundedJudgement(finalAnswer, dbContext);
    writeSuccessJson(out, response, finalAnswer, dbContext, isAdmin);

} catch (Exception e) {
    writeErrorJson(out, response, 500, e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "Unknown"));
}
%>
