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

    public static AgentRuntimeModels.DirectAnswerResult usagePowerTop(String dbContext) {
        return result(dbContext, buildUsagePowerTopAnswer(dbContext));
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

    private static String buildUsagePowerTopAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return "\uc6a9\ub3c4\ubcc4 \uc804\ub825 TOP \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("unavailable")) {
            return "\uc6a9\ub3c4\ubcc4 \uc804\ub825 TOP\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("no data")) {
            return "\uc6a9\ub3c4\ubcc4 \uc804\ub825 TOP \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }

        java.util.regex.Matcher periodMatcher = java.util.regex.Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        String period = periodMatcher.find() ? periodMatcher.group(1) : "-";
        java.util.regex.Matcher row = java.util.regex.Pattern.compile("\\s[0-9]+\\)([^:;]+):\\s*avg_kw=([0-9.\\-]+),\\s*sum_kwh=([0-9.\\-]+);").matcher(ctx);
        java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
        while (row.find()) {
            String usage = EpmsWebUtil.trimToNull(row.group(1));
            String avgKw = EpmsWebUtil.trimToNull(row.group(2));
            String sumKwh = EpmsWebUtil.trimToNull(row.group(3));
            if (usage == null || avgKw == null || sumKwh == null) continue;
            parts.add(usage + " \ud3c9\uade0\uc804\ub825 " + avgKw + "kW, \ub204\uc801 " + sumKwh + "kWh");
        }
        if (parts.isEmpty()) {
            return "\uc6a9\ub3c4\ubcc4 \uc804\ub825 TOP \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        return period + " \uc6a9\ub3c4\ubcc4 \uc804\ub825 TOP\uc740 " + String.join(" / ", parts) + "\uc785\ub2c8\ub2e4.";
    }
}
