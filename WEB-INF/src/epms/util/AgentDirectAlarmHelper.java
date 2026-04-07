package epms.util;

public final class AgentDirectAlarmHelper {
    private AgentDirectAlarmHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult alarmMeterTop(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildAlarmMeterTopDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult alarmType(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildAlarmTypeDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult alarmSeverity(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildAlarmSeverityDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult usageAlarmTop(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildUsageAlarmTopDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult usageAlarmCount(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildUsageAlarmCountDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult openAlarms(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildOpenAlarmsDirectAnswer(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult latestAlarms(String dbContext) {
        return result(dbContext, AgentAnswerFormatter.buildLatestAlarmsDirectAnswer(dbContext));
    }

    private static AgentRuntimeModels.DirectAnswerResult result(String dbContext, String answer) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = answer;
        return result;
    }
}
