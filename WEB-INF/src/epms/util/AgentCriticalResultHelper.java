package epms.util;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentCriticalResultHelper {
    private AgentCriticalResultHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult scopedMonthlyEnergy(String dbContext) {
        return result(
            dbContext,
            buildMonthlyEnergyAnswer(
                dbContext,
                "scope",
                "scope required",
                "\uad6c\uc5ed",
                "\ud574\ub2f9 \uad6c\uc5ed",
                "\uac74\ubb3c\uc774\ub098 \uad6c\uc5ed\uc744 \uc9c0\uc815\ud574 \uc8fc\uc138\uc694. \uc608: \ub3d9\uad00\uc758 \uc804\uccb4 \uc0ac\uc6a9\ub7c9\uc740?"
            )
        );
    }

    public static AgentRuntimeModels.DirectAnswerResult panelMonthlyEnergy(String dbContext) {
        return result(
            dbContext,
            buildMonthlyEnergyAnswer(
                dbContext,
                "panel",
                "panel token required",
                "\ud328\ub110",
                "\ud574\ub2f9 \ud328\ub110",
                "\ud328\ub110\uba85\uc744 \uc9c0\uc815\ud574 \uc8fc\uc138\uc694. \uc608: MDB_3C \ud328\ub110 \uc804\uccb4 \uc0ac\uc6a9\ub7c9\uc740?"
            )
        );
    }

    public static AgentRuntimeModels.DirectAnswerResult usageMonthlyEnergy(String dbContext) {
        return result(
            dbContext,
            buildMonthlyEnergyAnswer(
                dbContext,
                "usage",
                "usage token required",
                "\uc6a9\ub3c4",
                "\ud574\ub2f9 \uc6a9\ub3c4",
                "\uc6a9\ub3c4\ub97c \uc9c0\uc815\ud574 \uc8fc\uc138\uc694. \uc608: \ub3d9\ub825 \uc6a9\ub3c4 \uc804\uccb4 \uc0ac\uc6a9\ub7c9\uc740?"
            )
        );
    }

    public static AgentRuntimeModels.DirectAnswerResult openAlarmCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext == null ? "" : dbContext;
        if (result.dbContext.contains("unavailable")) {
            result.answer = "\ud604\uc7ac \uc5f4\ub9b0 \uc54c\ub78c \uc218\ub97c \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
            return result;
        }

        Matcher countMatcher = Pattern.compile("count=([0-9]+)").matcher(result.dbContext);
        int count = countMatcher.find() ? Integer.parseInt(countMatcher.group(1)) : 0;
        Matcher typeMatcher = Pattern.compile("type=([^;]+)").matcher(result.dbContext);
        Matcher scopeMatcher = Pattern.compile("scope=([^;]+)").matcher(result.dbContext);
        String typeLabel = typeMatcher.find() ? EpmsWebUtil.trimToNull(typeMatcher.group(1)) : null;
        String scopeLabel = scopeMatcher.find() ? EpmsWebUtil.trimToNull(scopeMatcher.group(1)) : null;
        String subject = (typeLabel == null || typeLabel.isEmpty()) ? "\uc5f4\ub9b0 \uc54c\ub78c" : ("\uc5f4\ub9b0 " + typeLabel + " \uc54c\ub78c");
        result.answer = (scopeLabel == null || scopeLabel.isEmpty())
            ? ("\ud604\uc7ac " + subject + "\uc740 \ucd1d " + count + "\uac74\uc785\ub2c8\ub2e4.")
            : (scopeLabel + " " + subject + "\uc740 \ucd1d " + count + "\uac74\uc785\ub2c8\ub2e4.");
        return result;
    }

    private static AgentRuntimeModels.DirectAnswerResult result(String dbContext, String answer) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext == null ? "" : dbContext;
        result.answer = answer;
        return result;
    }

    private static String buildMonthlyEnergyAnswer(
        String ctx,
        String key,
        String requiredToken,
        String subjectLabel,
        String defaultLabel,
        String requiredMessage
    ) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return subjectLabel + "\ubcc4 \uc804\ub825 \uc0ac\uc6a9\ub7c9 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains(requiredToken)) {
            return requiredMessage;
        }
        if (ctx.contains("unavailable")) {
            return subjectLabel + "\ubcc4 \uc804\ub825 \uc0ac\uc6a9\ub7c9\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("no data")) {
            return "\uc694\uccad\ud55c " + subjectLabel + "\uc758 \uc804\ub825 \uc0ac\uc6a9\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }

        Matcher labelMatcher = Pattern.compile(key + "=([^;]+)").matcher(ctx);
        Matcher periodMatcher = Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        Matcher leafMatcher = Pattern.compile("leaf_meter_count=([0-9]+)").matcher(ctx);
        Matcher measuredMatcher = Pattern.compile("measured_meter_count=([0-9]+)").matcher(ctx);
        Matcher negativeMatcher = Pattern.compile("negative_delta_count=([0-9]+)").matcher(ctx);
        Matcher avgMatcher = Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
        Matcher sumMatcher = Pattern.compile("sum_kwh=([0-9.\\-]+)").matcher(ctx);

        String label = labelMatcher.find() ? EpmsWebUtil.trimToNull(labelMatcher.group(1)) : null;
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        String leafMeterCount = leafMatcher.find() ? EpmsWebUtil.trimToNull(leafMatcher.group(1)) : "0";
        String measuredMeterCount = measuredMatcher.find() ? EpmsWebUtil.trimToNull(measuredMatcher.group(1)) : "0";
        String negativeDeltaCount = negativeMatcher.find() ? EpmsWebUtil.trimToNull(negativeMatcher.group(1)) : "0";
        String avgKw = avgMatcher.find() ? EpmsWebUtil.trimToNull(avgMatcher.group(1)) : "-";
        String sumKwh = sumMatcher.find() ? EpmsWebUtil.trimToNull(sumMatcher.group(1)) : "-";

        String resolvedLabel = (label == null || label.isEmpty())
            ? defaultLabel
            : ("usage".equals(key) ? (label + " \uc6a9\ub3c4") : label);
        String prefix = (period == null || period.isEmpty())
            ? (resolvedLabel + " \uc804\ub825 \uc0ac\uc6a9\ub7c9 \uc870\ud68c \uacb0\uacfc\uc785\ub2c8\ub2e4.")
            : (resolvedLabel + " " + period + " \uc804\ub825 \uc0ac\uc6a9\ub7c9\uc785\ub2c8\ub2e4.");
        StringBuilder out = new StringBuilder();
        out.append(prefix)
            .append("\n\n\ud575\uc2ec \uac12:\n")
            .append("- \ub204\uc801 \uc804\ub825\ub7c9: ").append(sumKwh).append("kWh\n")
            .append("- \ud3c9\uade0\uc804\ub825: ").append(avgKw).append("kW\n\n")
            .append("\uba54\ud0c0 \uc815\ubcf4:\n")
            .append("- \ucd5c\uc885 \ub9ac\ud504 \uacc4\uce21\uae30 \uc218: ").append(leafMeterCount).append("\uac1c\n")
            .append("- \ub370\uc774\ud130 \uc9d1\uacc4 \ub9ac\ud504 \uc218: ").append(measuredMeterCount).append("\uac1c");
        if (!"0".equals(negativeDeltaCount)) {
            out.append("\n- \ub9ac\uc14b \uc758\uc2ec \ub9ac\ud504 \uc218: ").append(negativeDeltaCount).append("\uac1c");
        }
        return out.toString();
    }
}
