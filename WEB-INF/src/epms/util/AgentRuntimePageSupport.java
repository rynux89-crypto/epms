package epms.util;

import java.util.Collections;

import javax.servlet.ServletContext;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.jsp.JspWriter;

import epms.agent.AgentApiRequestSupport;
import epms.util.AgentRuntimeModels.AgentExecutionContext;
import epms.util.AgentRuntimeModels.AgentRequestContext;
import epms.util.AgentRuntimeModels.DirectAnswerResult;
import epms.util.AgentRuntimeModels.PlannerExecutionResult;
import epms.util.AgentRuntimeModels.RuntimeModelSelection;
import epms.util.AgentRuntimeModels.SpecializedAnswerResult;

public final class AgentRuntimePageSupport {
    private static final long DEFAULT_SCHEMA_CACHE_TTL_MS = 5L * 60L * 1000L;
    private static final int SCHEMA_MAX_TABLES = 60;
    private static final int SCHEMA_MAX_COLUMNS_PER_TABLE = 40;
    private static final int SCHEMA_MAX_CHARS = 16000;

    private AgentRuntimePageSupport() {
    }

    public static void handle(HttpServletRequest request, HttpServletResponse response, JspWriter out, ServletContext application) throws Exception {
        request.setCharacterEncoding("UTF-8");
        response.setCharacterEncoding("UTF-8");
        response.setContentType("application/json;charset=UTF-8");
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type");

        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            response.setStatus(200);
            return;
        }

        if (request.getAttribute(AgentApiRequestSupport.ATTR_USER_MESSAGE) == null) {
            if (!AgentApiRequestSupport.prepare(request, response, application)) {
                return;
            }
        }

        String userMessage = (String) request.getAttribute(AgentApiRequestSupport.ATTR_USER_MESSAGE);
        if (userMessage == null) {
            AgentOutputHelper.writeErrorJson(out, response, 400, "Invalid request context");
            return;
        }
        boolean forceLlmOnly = java.lang.Boolean.TRUE.equals(request.getAttribute(AgentApiRequestSupport.ATTR_FORCE_LLM_ONLY));
        boolean forceRuleOnly = java.lang.Boolean.TRUE.equals(request.getAttribute(AgentApiRequestSupport.ATTR_FORCE_RULE_ONLY));
        boolean preferNarrativeHint = java.lang.Boolean.TRUE.equals(request.getAttribute(AgentApiRequestSupport.ATTR_PREFERS_NARRATIVE_HINT));
        boolean preferNarrativeLlm = (preferNarrativeHint || AgentIntentSupport.prefersNarrativeLlm(userMessage)) && !forceLlmOnly && !forceRuleOnly;
        boolean forceAiNarrative = isAiDesignIntent(userMessage) && !forceLlmOnly && !forceRuleOnly;
        boolean bypassDirect = AgentResponseFlowHelper.shouldBypassDirect(forceLlmOnly, preferNarrativeLlm);
        boolean bypassSpecialized = AgentResponseFlowHelper.shouldBypassSpecialized(forceLlmOnly, preferNarrativeLlm);
        if (forceAiNarrative) {
            bypassDirect = true;
            bypassSpecialized = true;
        }

        boolean isAdmin = java.lang.Boolean.TRUE.equals(request.getAttribute(AgentApiRequestSupport.ATTR_IS_ADMIN));

        DirectAnswerResult criticalDirectResult = AgentRuntimeDirectSupport.tryBuildCriticalDirectAnswer(userMessage, forceLlmOnly);
        if (criticalDirectResult != null) {
            writeDirectResult(out, response, criticalDirectResult, isAdmin);
            return;
        }

        DirectAnswerResult directResult = AgentRuntimeDirectSupport.tryBuildDirectAnswer(userMessage, bypassDirect);
        if (directResult != null) {
            writeDirectResult(out, response, directResult, isAdmin);
            return;
        }

        if (forceRuleOnly) {
            String directDbContext = "[Rule mode] no direct match";
            String userDbContext = AgentUserContextHelper.buildUserContext(directDbContext);
            AgentOutputHelper.writeSuccessJson(
                out,
                response,
                AgentResponseFlowHelper.buildRuleOnlyFallbackMessage(),
                isAdmin ? directDbContext : "",
                userDbContext,
                isAdmin
            );
            return;
        }

        RuntimeModelSelection runtimeModels = AgentRuntimeFlowSupport.resolveRuntimeModels(application, DEFAULT_SCHEMA_CACHE_TTL_MS);
        AgentSchemaCacheSupport.applySchemaCacheTtl(runtimeModels.schemaCacheTtlMs, DEFAULT_SCHEMA_CACHE_TTL_MS);

        try {
            try {
                AgentRuntimeFlowSupport.validateAvailableModels(runtimeModels);
            } catch (IllegalArgumentException e) {
                AgentOutputHelper.writeErrorJson(out, response, 400, e.getMessage());
                return;
            } catch (Exception e) {
                AgentOutputHelper.writeErrorJson(out, response, 502, "Cannot reach Ollama");
                return;
            }

            Integer requestedMeterId = AgentQueryExtractSupport.extractMeterId(userMessage);
            if (requestedMeterId == null) {
                requestedMeterId = AgentDbTools.resolveMeterIdByName(AgentQueryExtractSupport.extractMeterNameToken(userMessage));
            }
            AgentRequestContext reqCtx = AgentRequestSupport.buildRequestContext(
                requestedMeterId,
                AgentQueryExtractSupport.extractMeterScopeToken(userMessage),
                AgentQueryExtractSupport.extractAlarmAreaToken(userMessage),
                AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4),
                AgentQueryExtractSupport.extractMonth(userMessage),
                AgentQueryRouterCompat.wantsPerMeterPowerSummary(userMessage),
                AgentQueryIntentSupport.wantsMeterListSummary(userMessage),
                AgentQueryRouterCompat.wantsPhaseCurrentValue(userMessage),
                AgentQueryRouterCompat.wantsPhaseVoltageValue(userMessage),
                AgentQueryRouterCompat.wantsLineVoltageValue(userMessage),
                AgentQueryRouterCompat.wantsHarmonicSummary(userMessage),
                AgentQueryExtractSupport.extractPanelTokens(userMessage),
                AgentQueryExtractSupport.extractPhaseLabel(userMessage),
                AgentQueryExtractSupport.extractLinePairLabel(userMessage)
            );
            AgentExecutionContext execCtx = AgentExecutionSupport.buildExecutionContext(
                reqCtx,
                AgentQueryExtractSupport.extractTopN(userMessage, 10, 50),
                AgentQueryRouterCompat.wantsMeterSummary(userMessage),
                AgentQueryIntentSupport.wantsAlarmSummary(userMessage),
                AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
                runtimeModels.coderModel.equals(
                    AgentRuntimeFlowSupport.routeCoderModel(
                        userMessage,
                        runtimeModels.model,
                        runtimeModels.coderModel
                    )
                )
            );
            if (forceAiNarrative) {
                AgentExecutionSupport.clearDbNeeds(execCtx);
            }
            String schemaContext = AgentSchemaCacheSupport.getSchemaContextCached(
                DEFAULT_SCHEMA_CACHE_TTL_MS,
                SCHEMA_MAX_TABLES,
                SCHEMA_MAX_COLUMNS_PER_TABLE,
                SCHEMA_MAX_CHARS
            );

            String classifierRaw = "{}";
            if (!forceAiNarrative) {
                classifierRaw = AgentRuntimeFlowSupport.classifyNeedsDb(userMessage, runtimeModels);
                String cPanel = AgentSupport.extractJsonStringField(classifierRaw, "panel");
                AgentExecutionSupport.applyClassifierHints(
                    execCtx,
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_db"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_meter"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_alarm"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_frequency"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_power_by_meter"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_meter_list"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_phase_current"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_phase_voltage"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_line_voltage"),
                    AgentSupport.extractJsonBoolField(classifierRaw, "needs_harmonic"),
                    AgentSupport.extractJsonIntField(classifierRaw, "meter_id"),
                    AgentSupport.extractJsonIntField(classifierRaw, "month"),
                    AgentSupport.extractJsonStringField(classifierRaw, "meter_scope"),
                    AgentSupport.extractJsonStringField(classifierRaw, "phase"),
                    AgentSupport.extractJsonStringField(classifierRaw, "line_pair"),
                    (cPanel == null || cPanel.trim().isEmpty()) ? Collections.<String>emptyList() : AgentSupport.panelTokensFromRaw(cPanel),
                    AgentQueryRouterCompat.wantsPerMeterPowerSummary(userMessage),
                    AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
                    AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4)
                );
            }

            PlannerExecutionResult plannerResult = forceAiNarrative
                ? new PlannerExecutionResult()
                : AgentPlannerExecutionFlowSupport.executePlannerAndLoadContexts(
                    execCtx,
                    userMessage,
                    classifierRaw,
                    schemaContext,
                    runtimeModels.ollamaUrl,
                    runtimeModels.coderModel,
                    runtimeModels.ollamaConnectTimeoutMs,
                    runtimeModels.ollamaReadTimeoutMs,
                    AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4)
                );
            String dbContext = AgentPlannerContextSupport.buildDbContext(
                execCtx.needsDb,
                execCtx.needsHarmonic,
                AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
                plannerResult
            );

            if (!bypassSpecialized) {
                SpecializedAnswerResult specializedAnswer = new SpecializedAnswerResult();
                String harmonicAnswer = AgentDirectPowerHelper.harmonic(plannerResult.harmonicCtx, execCtx.requestedMeterId).answer;
                String frequencyAnswer = AgentDirectPowerHelper.frequency(plannerResult.frequencyCtx, execCtx.requestedMeterId, execCtx.requestedMonth).answer;
                String powerAnswer = AgentAnswerFormatter.buildPerMeterPowerDirectAnswer(plannerResult.powerCtx);
                String meterListUserContext = AgentUserContextHelper.buildUserContext(plannerResult.meterListCtx);
                String phaseCurrentUserContext = AgentUserContextHelper.buildUserContext(plannerResult.phaseCurrentCtx);
                String phaseVoltageUserContext = AgentUserContextHelper.buildUserContext(plannerResult.phaseVoltageCtx);
                String lineVoltageUserContext = AgentUserContextHelper.buildUserContext(plannerResult.lineVoltageCtx);
                specializedAnswer.answer = AgentSpecializedAnswerHelper.chooseAnswer(
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
                if (specializedAnswer.answer != null) {
                    String userDbContext = AgentUserContextHelper.buildUserContext(dbContext);
                    AgentOutputHelper.writeSuccessJson(out, response, specializedAnswer.answer, isAdmin ? dbContext : "", userDbContext, isAdmin);
                    return;
                }
            }

            String finalAnswer = AgentRuntimeFlowSupport.generateFinalAnswer(
                userMessage,
                dbContext,
                execCtx.needsDb,
                runtimeModels
            );
            String userDbContext = AgentUserContextHelper.buildUserContext(dbContext);
            AgentOutputHelper.writeSuccessJson(out, response, finalAnswer, isAdmin ? dbContext : "", userDbContext, isAdmin);

        } catch (Exception e) {
            AgentOutputHelper.writeErrorJson(out, response, 500, e.getClass().getSimpleName() + ": " + (e.getMessage() != null ? e.getMessage() : "Unknown"));
        }
    }

    private static void writeDirectResult(JspWriter out, HttpServletResponse response, DirectAnswerResult result, boolean isAdmin) throws Exception {
        int meterCount = AgentDirectResultHelper.countDistinctMeterIds(result.dbContext);
        result.answer = AgentResponseFlowHelper.finalizeDirectAnswer(result.answer, result.dbContext, meterCount);
        String userDbContext = AgentUserContextHelper.buildUserContext(result.dbContext);
        AgentOutputHelper.writeSuccessJson(out, response, result.answer, isAdmin ? result.dbContext : "", userDbContext, isAdmin);
    }

    private static boolean isAiDesignIntent(String userMessage) {
        if (userMessage == null) return false;
        String normalized = userMessage.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
        boolean hasAiRoute = AgentModelRouter.detectRoute(userMessage) == AgentModelRouter.Route.AI;
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
}
