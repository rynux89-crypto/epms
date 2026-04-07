package epms.util;

public final class AgentQueryIntentSupport {
    private AgentQueryIntentSupport() {}

    public static boolean wantsAlarmSummary(String userMessage) {
        return AgentQueryRouterCompat.wantsAlarmSummary(userMessage) || AgentScopedIntentSupport.wantsAlarmSummary(userMessage);
    }

    public static boolean wantsMonthlyPeakPower(String userMessage) {
        return AgentQueryRouter.wantsMonthlyPeakPower(userMessage) || AgentLocalIntentSupport.wantsMonthlyPeakPower(userMessage);
    }

    public static boolean wantsMeterListSummary(String userMessage) {
        if (AgentIntentSupport.hasMeasurementAnomalyIntent(userMessage)) return false;
        return AgentQueryRouterCompat.wantsMeterListSummary(userMessage);
    }

    public static boolean wantsMeterCountSummary(String userMessage) {
        if (AgentIntentSupport.hasMeasurementAnomalyIntent(userMessage)) return false;
        return AgentQueryRouterCompat.wantsMeterCountSummary(userMessage);
    }

    public static boolean wantsUsageTypeCountSummary(String userMessage) {
        return AgentQueryRouterCompat.wantsUsageTypeCountSummary(userMessage) && !AgentIntentSupport.hasAlarmIntent(userMessage);
    }

    public static boolean wantsUsageTypeListSummary(String userMessage) {
        return AgentQueryRouter.wantsUsageTypeListSummary(userMessage) && !AgentIntentSupport.hasAlarmIntent(userMessage);
    }

    public static boolean wantsAlarmCountSummary(String userMessage) {
        return AgentQueryRouterCompat.wantsAlarmCountSummary(userMessage) || AgentLocalIntentSupport.wantsAlarmCountSummary(userMessage);
    }

    public static boolean wantsOpenAlarms(String userMessage) {
        return AgentQueryRouterCompat.wantsOpenAlarms(userMessage) || AgentLocalIntentSupport.wantsOpenAlarms(userMessage);
    }

    public static boolean wantsOpenAlarmCountSummary(String userMessage) {
        return AgentQueryRouterCompat.wantsOpenAlarmCountSummary(userMessage) || AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage);
    }

    public static boolean wantsAlarmMeterTopN(String userMessage) {
        return AgentQueryRouter.wantsAlarmMeterTopN(userMessage) || AgentLocalIntentSupport.wantsAlarmMeterTopN(userMessage);
    }

    public static boolean wantsHarmonicExceed(String userMessage) {
        return AgentQueryRouterCompat.wantsHarmonicExceed(userMessage) || AgentLocalIntentSupport.wantsHarmonicExceed(userMessage);
    }

    public static boolean wantsFrequencyOutlier(String userMessage) {
        return AgentQueryRouterCompat.wantsFrequencyOutlier(userMessage) || AgentLocalIntentSupport.wantsFrequencyOutlier(userMessage);
    }

    public static boolean wantsVoltageUnbalanceTopN(String userMessage) {
        return AgentQueryRouterCompat.wantsVoltageUnbalanceTopN(userMessage) || AgentLocalIntentSupport.wantsVoltageUnbalanceTopN(userMessage);
    }

    public static boolean wantsPowerFactorOutlier(String userMessage) {
        return AgentQueryRouterCompat.wantsPowerFactorOutlier(userMessage) || AgentLocalIntentSupport.wantsPowerFactorOutlier(userMessage);
    }

    public static boolean wantsMonthlyPowerStats(String userMessage) {
        return AgentQueryRouterCompat.wantsMonthlyPowerStats(userMessage) || AgentLocalIntentSupport.wantsMonthlyPowerStats(userMessage);
    }
}
