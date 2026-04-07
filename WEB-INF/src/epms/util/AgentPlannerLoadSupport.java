package epms.util;

import epms.util.AgentRuntimeModels.AgentExecutionContext;
import epms.util.AgentRuntimeModels.PlannerExecutionResult;
import epms.util.AgentRuntimeModels.PlannerRunFlags;

public final class AgentPlannerLoadSupport {
    private AgentPlannerLoadSupport() {
    }

    public static PlannerExecutionResult loadContexts(PlannerRunFlags flags, AgentExecutionContext ctx) {
        PlannerExecutionResult result = new PlannerExecutionResult();
        if (flags == null || ctx == null) {
            return result;
        }
        String panelCsv = ctx.panelTokens == null || ctx.panelTokens.isEmpty() ? null : String.join(",", ctx.panelTokens);
        if (flags.runMeter) result.meterCtx = AgentDbTools.getRecentMeterContext(ctx.requestedMeterId, panelCsv);
        if (flags.runAlarm) result.alarmCtx = AgentDbTools.getRecentAlarmContext();
        if (flags.runFrequency) result.frequencyCtx = AgentDbTools.getMonthlyAvgFrequencyContext(ctx.requestedMeterId, ctx.requestedMonth);
        if (flags.runPower) result.powerCtx = AgentDbTools.getPerMeterPowerContext();
        if (flags.runMeterList) result.meterListCtx = AgentDbTools.getMeterListContext(ctx.requestedMeterScope, ctx.requestedTopN);
        if (flags.runPhaseCurrent) result.phaseCurrentCtx = AgentDbTools.getPhaseCurrentContext(ctx.requestedMeterId, ctx.requestedPhase);
        if (flags.runPhaseVoltage) result.phaseVoltageCtx = AgentDbTools.getPhaseVoltageContext(ctx.requestedMeterId, ctx.requestedPhase);
        if (flags.runLineVoltage) result.lineVoltageCtx = AgentDbTools.getLineVoltageContext(ctx.requestedMeterId, ctx.requestedLinePair);
        if (flags.runHarmonic) result.harmonicCtx = AgentDbTools.getHarmonicContext(ctx.requestedMeterId, panelCsv);
        return result;
    }
}
