package epms.util;

import java.util.List;

import epms.util.AgentRuntimeModels.AgentExecutionContext;
import epms.util.AgentRuntimeModels.PlannerExecutionResult;
import epms.util.AgentRuntimeModels.PlannerRunFlags;

public final class AgentPlannerExecutionFlowSupport {
    private AgentPlannerExecutionFlowSupport() {
    }

    public static PlannerExecutionResult executePlannerAndLoadContexts(
            AgentExecutionContext execCtx,
            String userMessage,
            String classifierRaw,
            String schemaContext,
            String ollamaUrl,
            String coderModel,
            int ollamaConnectTimeoutMs,
            int ollamaReadTimeoutMs,
            List<String> fallbackScopeHints) throws Exception {
        PlannerExecutionResult result = new PlannerExecutionResult();
        if (execCtx == null || !execCtx.needsDb) {
            return result;
        }

        String coderPrompt =
            "You are DB task planner. Return only one JSON object with keys: " +
            "task(\"meter\"|\"alarm\"|\"both\"|\"none\"), needs_frequency(boolean), needs_power_by_meter(boolean), needs_meter_list(boolean), needs_phase_current(boolean), needs_phase_voltage(boolean), needs_line_voltage(boolean), needs_harmonic(boolean), meter_id(number|null), month(number|null), panel(string|null), meter_scope(string|null), phase(string|null), line_pair(string|null). " +
            "No markdown. No explanation.\n\n" +
            "User: " + userMessage + "\n" +
            "Classifier JSON: " + classifierRaw + "\n\n" +
            "Schema Context:\n" + schemaContext;
        String coderRaw = AgentRuntimeFlowSupport.callOllamaOnce(
            ollamaUrl,
            coderModel,
            coderPrompt,
            ollamaConnectTimeoutMs,
            ollamaReadTimeoutMs,
            0.1d
        );

        String task = AgentSupport.extractJsonStringField(coderRaw, "task");
        Boolean planNeedsFrequency = AgentSupport.extractJsonBoolField(coderRaw, "needs_frequency");
        Boolean planNeedsPower = AgentSupport.extractJsonBoolField(coderRaw, "needs_power_by_meter");
        Boolean planNeedsMeterList = AgentSupport.extractJsonBoolField(coderRaw, "needs_meter_list");
        Boolean planNeedsPhaseCurrent = AgentSupport.extractJsonBoolField(coderRaw, "needs_phase_current");
        Boolean planNeedsPhaseVoltage = AgentSupport.extractJsonBoolField(coderRaw, "needs_phase_voltage");
        Boolean planNeedsLineVoltage = AgentSupport.extractJsonBoolField(coderRaw, "needs_line_voltage");
        Boolean planNeedsHarmonic = AgentSupport.extractJsonBoolField(coderRaw, "needs_harmonic");
        Integer planMeterId = AgentSupport.extractJsonIntField(coderRaw, "meter_id");
        Integer planMonth = AgentSupport.extractJsonIntField(coderRaw, "month");
        String planPanel = AgentSupport.extractJsonStringField(coderRaw, "panel");
        String planMeterScope = AgentSupport.extractJsonStringField(coderRaw, "meter_scope");
        String planPhase = AgentSupport.extractJsonStringField(coderRaw, "phase");
        String planLinePair = AgentSupport.extractJsonStringField(coderRaw, "line_pair");

        PlannerRunFlags runFlags = AgentExecutionSupport.applyPlannerDecision(
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
            AgentSupport.panelTokensFromRaw(planPanel),
            AgentQueryRouterCompat.wantsMeterSummary(userMessage),
            AgentQueryIntentSupport.wantsAlarmSummary(userMessage),
            AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage),
            AgentQueryRouterCompat.wantsPerMeterPowerSummary(userMessage),
            fallbackScopeHints
        );

        result = AgentPlannerLoadSupport.loadContexts(runFlags, execCtx);
        if (!runFlags.anyEnabled() && execCtx.forceCoderFlow) {
            String coderAnswerPrompt =
                "Answer the user's DB/SQL request directly. " +
                "Use SQL Server syntax if SQL is requested. " +
                "Return concise plain text, no markdown fences.\n\n" +
                "User: " + userMessage + "\n\n" +
                "Schema Context:\n" + schemaContext;
            result.coderDraft = AgentRuntimeFlowSupport.callOllamaOnce(
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
}
