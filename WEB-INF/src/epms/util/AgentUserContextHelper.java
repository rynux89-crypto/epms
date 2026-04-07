package epms.util;

public final class AgentUserContextHelper {
    private AgentUserContextHelper() {
    }

    public static String buildUserContext(
        String dbContext,
        String delegatedContext,
        String powerFactorAnswer,
        String powerFactorNoSignalSnippet
    ) {
        String ctx = dbContext == null ? "" : dbContext.trim();
        if (ctx.isEmpty()) return "";
        if (ctx.contains("[Power factor outlier]")) {
            String answer = powerFactorAnswer == null ? "" : powerFactorAnswer;
            String snippet = powerFactorNoSignalSnippet == null ? "" : powerFactorNoSignalSnippet.trim();
            if ((ctx.contains("none") || ctx.contains("no data")) && !snippet.isEmpty()) {
                answer = answer + "\n\n" + snippet;
            }
            return answer;
        }
        if (delegatedContext != null) return delegatedContext;
        String routed = routeKnownContext(ctx);
        if (routed != null) return routed;
        return fallbackContextText(ctx, 600);
    }

    public static String routeKnownContext(String dbContext) {
        String ctx = dbContext == null ? "" : dbContext.trim();
        if (ctx.isEmpty()) return "";
        if (ctx.contains("[Harmonic exceed standard]")) return AgentCriticalDirectAnswerHelper.buildHarmonicExceedStandardDirectAnswer();
        if (ctx.contains("[EPMS knowledge]")) return AgentCriticalDirectAnswerHelper.buildEpmsKnowledgeDirectAnswer();
        if (ctx.contains("[Frequency outlier standard]")) return AgentCriticalDirectAnswerHelper.buildFrequencyOutlierStandardDirectAnswer();
        if (ctx.contains("[PF threshold]")) return AgentCriticalDirectAnswerHelper.buildPowerFactorThresholdDirectAnswer();
        if (ctx.contains("[Current unbalance count]")) return AgentDirectOutlierHelper.currentUnbalanceCount(ctx).answer;
        if (ctx.contains("[Scoped monthly energy]")) return AgentCriticalResultHelper.scopedMonthlyEnergy(ctx).answer;
        if (ctx.contains("[Panel monthly energy]")) return AgentCriticalResultHelper.panelMonthlyEnergy(ctx).answer;
        if (ctx.contains("[Usage monthly energy]")) return AgentCriticalResultHelper.usageMonthlyEnergy(ctx).answer;
        if (ctx.contains("[Usage power TOP]")) return AgentDirectPowerHelper.usagePowerTop(ctx).answer;
        if (ctx.contains("[Building power TOP]")) return AgentDirectPowerHelper.buildingPowerTop(ctx).answer;
        if (ctx.contains("[Alarm meter TOP]")) return AgentDirectAlarmHelper.alarmMeterTop(ctx).answer;
        if (ctx.contains("[Usage type list]")) return AgentAnswerFormatter.buildUsageTypeListDirectAnswer(ctx);
        if (ctx.contains("[Monthly peak power]")) return AgentAnswerFormatter.buildMonthlyPeakPowerDirectAnswer(ctx);
        return null;
    }

    public static String fallbackContextText(String dbContext, int maxLen) {
        String ctx = dbContext == null ? "" : dbContext.trim();
        if (ctx.isEmpty()) return "";
        String fallback = ctx
            .replace("STATE=NO_SIGNAL", "\uc2e0\ud638\uc5c6\uc74c")
            .replace("meter_id=", "\uacc4\uce21\uae30 ")
            .replace("no data", "\ub370\uc774\ud130 \uc5c6\uc74c")
            .replace("unavailable", "\uc870\ud68c \ubd88\uac00");
        return fallback.length() <= maxLen ? fallback : fallback.substring(0, maxLen);
    }
}
