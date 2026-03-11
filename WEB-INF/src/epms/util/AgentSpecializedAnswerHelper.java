package epms.util;

public final class AgentSpecializedAnswerHelper {
    private AgentSpecializedAnswerHelper() {
    }

    public static final class Selection {
        public final String type;
        public final String context;
        public final String fallbackText;

        public Selection(String type, String context, String fallbackText) {
            this.type = type;
            this.context = context;
            this.fallbackText = fallbackText;
        }
    }

    public static Selection select(
        boolean forceCoderFlow,
        boolean needsHarmonic,
        boolean needsFrequency,
        boolean needsPerMeterPower,
        boolean needsMeterList,
        boolean needsPhaseCurrent,
        boolean needsPhaseVoltage,
        boolean needsLineVoltage,
        String harmonicCtx,
        String frequencyCtx,
        String powerCtx,
        String meterListCtx,
        String phaseCurrentCtx,
        String phaseVoltageCtx,
        String lineVoltageCtx
    ) {
        if (forceCoderFlow) return null;
        if (hasText(harmonicCtx) && needsHarmonic) {
            return new Selection("harmonic", harmonicCtx, null);
        }
        if (hasText(frequencyCtx) && needsFrequency) {
            return new Selection("frequency", frequencyCtx, null);
        }
        if (hasText(powerCtx) && needsPerMeterPower) {
            return new Selection("power", powerCtx, null);
        }
        if (hasText(meterListCtx) && needsMeterList) {
            return new Selection("meter_list", meterListCtx, "계측기 목록을 조회했습니다.");
        }
        if (hasText(phaseCurrentCtx) && needsPhaseCurrent) {
            return new Selection("phase_current", phaseCurrentCtx, "상전류를 조회했습니다.");
        }
        if (hasText(phaseVoltageCtx) && needsPhaseVoltage) {
            return new Selection("phase_voltage", phaseVoltageCtx, "상전압을 조회했습니다.");
        }
        if (hasText(lineVoltageCtx) && needsLineVoltage) {
            return new Selection("line_voltage", lineVoltageCtx, "선간전압을 조회했습니다.");
        }
        return null;
    }

    private static boolean hasText(String value) {
        return value != null && !value.trim().isEmpty();
    }
}
