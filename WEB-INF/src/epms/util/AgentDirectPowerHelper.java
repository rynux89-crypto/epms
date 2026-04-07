package epms.util;

public final class AgentDirectPowerHelper {
    private AgentDirectPowerHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult voltageAverage(String dbContext, Integer meterId) {
        return result(dbContext, AgentAnswerFormatter.buildVoltageAverageDirectAnswer(dbContext, meterId));
    }

    public static AgentRuntimeModels.DirectAnswerResult frequency(String dbContext, Integer meterId, Integer month) {
        return result(dbContext, AgentAnswerFormatter.buildFrequencyDirectAnswer(dbContext, meterId, month));
    }

    public static AgentRuntimeModels.DirectAnswerResult monthlyPeak(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildMonthlyPeakPowerDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult monthlyPowerStats(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildMonthlyPowerStatsDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult buildingPowerTop(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildBuildingPowerTopDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult energyValue(String dbContext, boolean reactive) {
        return result(dbContext, AgentAnswerFormatter.buildEnergyValueDirectAnswer(dbContext, reactive));
    }

    public static AgentRuntimeModels.DirectAnswerResult energyDelta(String dbContext, boolean reactive) {
        return result(dbContext, AgentAnswerFormatter.buildEnergyDeltaDirectAnswer(dbContext, reactive));
    }

    public static AgentRuntimeModels.DirectAnswerResult powerValue(String dbContext, boolean reactive) {
        return result(dbContext, AgentAnswerFormatter.buildPowerValueDirectAnswer(dbContext, reactive));
    }

    public static AgentRuntimeModels.DirectAnswerResult harmonic(String dbContext, Integer meterId) {
        return result(dbContext, AgentAnswerFormatter.buildHarmonicDirectAnswer(dbContext, meterId));
    }

    private static AgentRuntimeModels.DirectAnswerResult result(String dbContext, String answer) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = answer;
        return result;
    }
}
