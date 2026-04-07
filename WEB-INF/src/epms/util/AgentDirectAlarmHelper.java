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

    public static String directDbSummary(boolean meterRequested, boolean alarmRequested, String meterText, String alarmText) {
        if (!meterRequested && !alarmRequested) return null;
        String safeMeter = (meterText == null || meterText.trim().isEmpty()) ? "\ucd5c\uadfc \uacc4\uce21\uac12\uc744 \uc870\ud68c\ud588\uc2b5\ub2c8\ub2e4." : meterText;
        String safeAlarm = (alarmText == null || alarmText.trim().isEmpty()) ? "\ucd5c\uadfc \uc54c\ub78c\uc774 \uc5c6\uc2b5\ub2c8\ub2e4." : alarmText;
        if (meterRequested && alarmRequested) return safeMeter + "\n\n" + safeAlarm;
        return meterRequested ? safeMeter : safeAlarm;
    }

    private static AgentRuntimeModels.DirectAnswerResult result(String dbContext, String answer) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = answer;
        return result;
    }
}
