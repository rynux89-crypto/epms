package epms.util;

import java.util.ArrayList;
import java.util.List;

public final class AgentExecutionSupport {
    private AgentExecutionSupport() {
    }

    public static AgentRuntimeModels.AgentExecutionContext buildExecutionContext(
            AgentRuntimeModels.AgentRequestContext reqCtx,
            Integer requestedTopN,
            boolean needsMeter,
            boolean needsAlarm,
            boolean needsFrequency,
            boolean forceCoderFlow) {
        AgentRuntimeModels.AgentExecutionContext ctx = new AgentRuntimeModels.AgentExecutionContext();
        ctx.requestedMeterId = reqCtx.requestedMeterId;
        ctx.requestedMeterScope = reqCtx.requestedMeterScope;
        ctx.requestedMonth = reqCtx.requestedMonth;
        ctx.requestedTopN = requestedTopN;
        ctx.requestedPhase = reqCtx.requestedPhase;
        ctx.requestedLinePair = reqCtx.requestedLinePair;
        ctx.panelTokens = reqCtx.panelTokens;
        ctx.needsMeter = needsMeter;
        ctx.needsAlarm = needsAlarm;
        ctx.needsFrequency = needsFrequency;
        ctx.needsPerMeterPower = reqCtx.needsPerMeterPower;
        ctx.needsMeterList = reqCtx.needsMeterList;
        ctx.needsPhaseCurrent = reqCtx.needsPhaseCurrent;
        ctx.needsPhaseVoltage = reqCtx.needsPhaseVoltage;
        ctx.needsLineVoltage = reqCtx.needsLineVoltage;
        ctx.needsHarmonic = reqCtx.needsHarmonic;
        ctx.forceCoderFlow = forceCoderFlow;
        ctx.needsDb = ctx.needsMeter || ctx.needsAlarm || ctx.needsFrequency || ctx.needsPerMeterPower
                || ctx.needsMeterList || ctx.needsPhaseCurrent || ctx.needsPhaseVoltage || ctx.needsLineVoltage || ctx.needsHarmonic;
        return ctx;
    }

    public static void clearDbNeeds(AgentRuntimeModels.AgentExecutionContext ctx) {
        if (ctx == null) return;
        ctx.needsMeter = false;
        ctx.needsAlarm = false;
        ctx.needsFrequency = false;
        ctx.needsPerMeterPower = false;
        ctx.needsMeterList = false;
        ctx.needsPhaseCurrent = false;
        ctx.needsPhaseVoltage = false;
        ctx.needsLineVoltage = false;
        ctx.needsHarmonic = false;
        ctx.needsDb = false;
    }

    public static void applyClassifierHints(
            AgentRuntimeModels.AgentExecutionContext ctx,
            Boolean cNeedsDb,
            Boolean cNeedsMeter,
            Boolean cNeedsAlarm,
            Boolean cNeedsFrequency,
            Boolean cNeedsPower,
            Boolean cNeedsMeterList,
            Boolean cNeedsPhaseCurrent,
            Boolean cNeedsPhaseVoltage,
            Boolean cNeedsLineVoltage,
            Boolean cNeedsHarmonic,
            Integer cMeterId,
            Integer cMonth,
            String cMeterScope,
            String cPhase,
            String cLinePair,
            List<String> parsedPanelTokens,
            boolean wantsPerMeterPowerSummary,
            boolean wantsMonthlyFrequencySummary,
            List<String> fallbackScopeHints) {
        if (ctx == null) return;
        if (cNeedsDb != null) ctx.needsDb = ctx.needsDb || cNeedsDb.booleanValue();
        ctx.needsDb = ctx.needsDb || ctx.forceCoderFlow;
        if (cNeedsMeter != null) ctx.needsMeter = ctx.needsMeter || cNeedsMeter.booleanValue();
        if (cNeedsAlarm != null) ctx.needsAlarm = ctx.needsAlarm || cNeedsAlarm.booleanValue();
        if (cNeedsFrequency != null) ctx.needsFrequency = ctx.needsFrequency || cNeedsFrequency.booleanValue();
        if (cNeedsPower != null) ctx.needsPerMeterPower = ctx.needsPerMeterPower || cNeedsPower.booleanValue();
        if (cNeedsMeterList != null) ctx.needsMeterList = ctx.needsMeterList || cNeedsMeterList.booleanValue();
        if (cNeedsPhaseCurrent != null) ctx.needsPhaseCurrent = ctx.needsPhaseCurrent || cNeedsPhaseCurrent.booleanValue();
        if (cNeedsPhaseVoltage != null) ctx.needsPhaseVoltage = ctx.needsPhaseVoltage || cNeedsPhaseVoltage.booleanValue();
        if (cNeedsLineVoltage != null) ctx.needsLineVoltage = ctx.needsLineVoltage || cNeedsLineVoltage.booleanValue();
        if (cNeedsHarmonic != null) ctx.needsHarmonic = ctx.needsHarmonic || cNeedsHarmonic.booleanValue();
        if (ctx.needsMeterList && !wantsPerMeterPowerSummary) ctx.needsPerMeterPower = false;
        if (ctx.needsHarmonic && !wantsMonthlyFrequencySummary) ctx.needsFrequency = false;
        if (cMeterId != null) ctx.requestedMeterId = cMeterId;
        if (cMonth != null && cMonth.intValue() >= 1 && cMonth.intValue() <= 12) ctx.requestedMonth = cMonth;
        if ((ctx.panelTokens == null || ctx.panelTokens.isEmpty()) && parsedPanelTokens != null && !parsedPanelTokens.isEmpty()) {
            ctx.panelTokens = new ArrayList<String>(parsedPanelTokens);
        }
        if (isBlank(ctx.requestedMeterScope) && !isBlank(cMeterScope)) ctx.requestedMeterScope = cMeterScope;
        if (isBlank(ctx.requestedPhase) && !isBlank(cPhase)) ctx.requestedPhase = cPhase;
        if (isBlank(ctx.requestedLinePair) && !isBlank(cLinePair)) ctx.requestedLinePair = cLinePair;
        if (isBlank(ctx.requestedMeterScope) && fallbackScopeHints != null && !fallbackScopeHints.isEmpty()) {
            ctx.requestedMeterScope = String.join(",", fallbackScopeHints);
        }
    }

    public static AgentRuntimeModels.PlannerRunFlags applyPlannerDecision(
            AgentRuntimeModels.AgentExecutionContext ctx,
            String task,
            Boolean planNeedsFrequency,
            Boolean planNeedsPower,
            Boolean planNeedsMeterList,
            Boolean planNeedsPhaseCurrent,
            Boolean planNeedsPhaseVoltage,
            Boolean planNeedsLineVoltage,
            Boolean planNeedsHarmonic,
            Integer planMeterId,
            Integer planMonth,
            String planMeterScope,
            String planPhase,
            String planLinePair,
            List<String> planPanelTokens,
            boolean wantsMeterSummary,
            boolean wantsAlarmSummary,
            boolean wantsMonthlyFrequencySummary,
            boolean wantsPerMeterPowerSummary,
            List<String> fallbackScopeHints) {
        AgentRuntimeModels.PlannerRunFlags flags = new AgentRuntimeModels.PlannerRunFlags();
        if (ctx == null) return flags;

        flags.runMeter = ctx.needsMeter;
        flags.runAlarm = ctx.needsAlarm;
        flags.runFrequency = ctx.needsFrequency;
        flags.runPower = ctx.needsPerMeterPower;
        flags.runMeterList = ctx.needsMeterList;
        flags.runPhaseCurrent = ctx.needsPhaseCurrent;
        flags.runPhaseVoltage = ctx.needsPhaseVoltage;
        flags.runLineVoltage = ctx.needsLineVoltage;
        flags.runHarmonic = ctx.needsHarmonic;

        if (!isBlank(task)) {
            String normalizedTask = task.trim().toLowerCase(java.util.Locale.ROOT);
            if ("meter".equals(normalizedTask)) {
                flags.runMeter = true;
                flags.runAlarm = false;
            } else if ("alarm".equals(normalizedTask)) {
                flags.runMeter = false;
                flags.runAlarm = true;
            } else if ("both".equals(normalizedTask)) {
                flags.runMeter = true;
                flags.runAlarm = true;
            } else if ("none".equals(normalizedTask)) {
                flags.runMeter = false;
                flags.runAlarm = false;
            }
        }

        if (ctx.needsFrequency && !wantsMeterSummary) flags.runMeter = false;
        if (ctx.needsFrequency && !wantsAlarmSummary) flags.runAlarm = false;
        if (ctx.needsPerMeterPower && !wantsMeterSummary) flags.runMeter = false;
        if (ctx.needsPerMeterPower && !wantsAlarmSummary) flags.runAlarm = false;
        if (ctx.needsHarmonic && !wantsMeterSummary) flags.runMeter = false;
        if (ctx.needsHarmonic && !wantsAlarmSummary) flags.runAlarm = false;
        if (ctx.needsHarmonic && !wantsMonthlyFrequencySummary) flags.runFrequency = false;

        if (planMeterId != null) ctx.requestedMeterId = planMeterId;
        if (planMonth != null && planMonth.intValue() >= 1 && planMonth.intValue() <= 12) {
            ctx.requestedMonth = planMonth;
        }
        if (planNeedsFrequency != null) flags.runFrequency = flags.runFrequency || planNeedsFrequency.booleanValue();
        if (planNeedsPower != null) flags.runPower = flags.runPower || planNeedsPower.booleanValue();
        if (planNeedsMeterList != null) flags.runMeterList = flags.runMeterList || planNeedsMeterList.booleanValue();
        if (planNeedsPhaseCurrent != null) flags.runPhaseCurrent = flags.runPhaseCurrent || planNeedsPhaseCurrent.booleanValue();
        if (planNeedsPhaseVoltage != null) flags.runPhaseVoltage = flags.runPhaseVoltage || planNeedsPhaseVoltage.booleanValue();
        if (planNeedsLineVoltage != null) flags.runLineVoltage = flags.runLineVoltage || planNeedsLineVoltage.booleanValue();
        if (planNeedsHarmonic != null) flags.runHarmonic = flags.runHarmonic || planNeedsHarmonic.booleanValue();
        if (flags.runMeterList && !wantsPerMeterPowerSummary) flags.runPower = false;
        if (ctx.needsHarmonic && !wantsMonthlyFrequencySummary) flags.runFrequency = false;

        if ((ctx.panelTokens == null || ctx.panelTokens.isEmpty()) && planPanelTokens != null && !planPanelTokens.isEmpty()) {
            ctx.panelTokens = new ArrayList<String>(planPanelTokens);
        }
        if (isBlank(ctx.requestedMeterScope) && !isBlank(planMeterScope)) ctx.requestedMeterScope = planMeterScope;
        if (isBlank(ctx.requestedPhase) && !isBlank(planPhase)) ctx.requestedPhase = planPhase;
        if (isBlank(ctx.requestedLinePair) && !isBlank(planLinePair)) ctx.requestedLinePair = planLinePair;
        if (isBlank(ctx.requestedMeterScope) && fallbackScopeHints != null && !fallbackScopeHints.isEmpty()) {
            ctx.requestedMeterScope = String.join(",", fallbackScopeHints);
        }
        return flags;
    }

    private static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }
}
