package epms.util;

import epms.util.AgentRuntimeModels.PlannerExecutionResult;

public final class AgentPlannerContextSupport {
    private AgentPlannerContextSupport() {
    }

    public static String buildDbContext(
        boolean needsDb,
        boolean needsHarmonic,
        boolean wantsMonthlyFrequencySummary,
        PlannerExecutionResult plannerResult
    ) {
        if (!needsDb) {
            return "";
        }

        StringBuilder db = new StringBuilder();
        append(db, "Meter", plannerResult.meterCtx);
        append(db, "Alarm", plannerResult.alarmCtx);

        String frequencyCtx = plannerResult.frequencyCtx;
        if (needsHarmonic && !wantsMonthlyFrequencySummary) {
            frequencyCtx = "";
        }
        append(db, "Frequency", frequencyCtx);
        append(db, "PowerByMeter", plannerResult.powerCtx);
        append(db, "MeterList", plannerResult.meterListCtx);
        append(db, "PhaseCurrent", plannerResult.phaseCurrentCtx);
        append(db, "PhaseVoltage", plannerResult.phaseVoltageCtx);
        append(db, "LineVoltage", plannerResult.lineVoltageCtx);
        append(db, "Harmonic", plannerResult.harmonicCtx);
        append(db, "CoderDraft", plannerResult.coderDraft);
        return db.toString();
    }

    private static void append(StringBuilder out, String label, String value) {
        if (value == null || value.trim().isEmpty()) {
            return;
        }
        if (out.length() > 0) {
            out.append("\n");
        }
        out.append(label).append(": ").append(value);
    }
}
