﻿<%@ page import="java.io.*,java.net.*,java.util.*,java.sql.*,javax.naming.*,javax.sql.*" trimDirectiveWhitespaces="true" %>
<%@ page contentType="application/json; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="epms.util.AgentRuntimeModels.AgentRequestContext,epms.util.AgentRuntimeModels.DirectAnswerRequest,epms.util.AgentRuntimeModels.CriticalDirectAnswerRequest,epms.util.AgentRuntimeModels.DirectAnswerResult,epms.util.AgentRuntimeModels.AgentExecutionContext,epms.util.AgentRuntimeModels.PlannerExecutionResult,epms.util.AgentRuntimeModels.SpecializedAnswerResult" %>

<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");
response.setContentType("application/json;charset=UTF-8");
%>

<%!
private static final long DEFAULT_SCHEMA_CACHE_TTL_MS = 5L * 60L * 1000L;
private static final int SCHEMA_MAX_TABLES = 60;
private static final int SCHEMA_MAX_COLUMNS_PER_TABLE = 40;
private static final int SCHEMA_MAX_CHARS = 16000;

private String trimToNull(String s) {
    return epms.util.AgentSupport.trimToNull(s);
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

DirectAnswerResult criticalDirectResult = epms.util.AgentRuntimeDirectSupport.tryBuildCriticalDirectAnswer(userMessage, forceLlmOnly);
if (criticalDirectResult != null) {
    int meterCount = epms.util.AgentDirectResultHelper.countDistinctMeterIds(criticalDirectResult.dbContext);
    criticalDirectResult.answer = epms.util.AgentResponseFlowHelper.finalizeDirectAnswer(criticalDirectResult.answer, criticalDirectResult.dbContext, meterCount);
    String userDbContext = epms.util.AgentUserContextHelper.buildUserContext(criticalDirectResult.dbContext);
    epms.util.AgentOutputHelper.writeSuccessJson(out, response, criticalDirectResult.answer, isAdmin ? criticalDirectResult.dbContext : "", userDbContext, isAdmin);
    return;
}

DirectAnswerResult directResult = epms.util.AgentRuntimeDirectSupport.tryBuildDirectAnswer(userMessage, bypassDirect);
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
epms.util.AgentSchemaCacheSupport.applySchemaCacheTtl(runtimeModels.schemaCacheTtlMs, DEFAULT_SCHEMA_CACHE_TTL_MS);

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
        epms.util.AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4),
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
    String schemaContext = epms.util.AgentSchemaCacheSupport.getSchemaContextCached(
        DEFAULT_SCHEMA_CACHE_TTL_MS,
        SCHEMA_MAX_TABLES,
        SCHEMA_MAX_COLUMNS_PER_TABLE,
        SCHEMA_MAX_CHARS
    );

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
            epms.util.AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4)
        );
    }

    PlannerExecutionResult plannerResult = forceAiNarrative
        ? new PlannerExecutionResult()
        : epms.util.AgentPlannerExecutionFlowSupport.executePlannerAndLoadContexts(
            execCtx,
            userMessage,
            classifierRaw,
            schemaContext,
            runtimeModels.ollamaUrl,
            runtimeModels.coderModel,
            runtimeModels.ollamaConnectTimeoutMs,
            runtimeModels.ollamaReadTimeoutMs,
            epms.util.AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4)
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
