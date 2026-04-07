package epms.util;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentDirectResultHelper {
    private AgentDirectResultHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult simple(String dbContext, String userContext, String fallback) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.chooseUserContextAnswer(userContext, fallback);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult panelLatest(String dbContext, String userContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildPanelLatestStatusAnswer(dbContext, userContext);
        return result;
    }

    public static int countDistinctMeterIds(String context) {
        if (context == null || context.isEmpty()) {
            return 0;
        }
        HashSet<String> ids = new HashSet<String>();
        Matcher matcher = Pattern.compile("meter_id=([0-9]+)").matcher(context);
        while (matcher.find()) {
            ids.add(matcher.group(1));
        }
        return ids.size();
    }

    public static String finalizeDirectAnswer(String answer, String dbContext, int meterCount) {
        if (answer == null) {
            return null;
        }
        boolean skipMeterCountSuffix =
            dbContext != null
                && (dbContext.startsWith("[Alarm count]") || dbContext.startsWith("[Panel latest status]"));
        if (!skipMeterCountSuffix && meterCount > 0 && answer.indexOf('\n') < 0) {
            return answer + " (해당 계측기 " + meterCount + "개)";
        }
        return answer;
    }

    public static String buildPowerFactorNoSignalListSnippet(String ctx) {
        if (ctx == null || ctx.trim().isEmpty() || ctx.contains("none") || ctx.contains("unavailable")) {
            return null;
        }
        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        ArrayList<String> items = new ArrayList<String>();
        Matcher rowMatcher = Pattern.compile(
            "\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*t=([^;]+);"
        ).matcher(ctx);
        while (rowMatcher.find()) {
            String meterId = EpmsWebUtil.trimToNull(rowMatcher.group(1));
            String meterName = EpmsWebUtil.trimToNull(rowMatcher.group(2));
            String panel = EpmsWebUtil.trimToNull(rowMatcher.group(3));
            String ts = EpmsWebUtil.trimToNull(rowMatcher.group(4));
            if (meterId == null || meterName == null) {
                continue;
            }
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) {
                item += " / " + panel;
            }
            if (ts != null && !ts.isEmpty()) {
                item += " / " + clip(ts, 19);
            }
            items.add(item);
        }
        if (items.isEmpty()) {
            return null;
        }
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) {
            out.append("신호없음 계측기 예시:\n");
        } else {
            out.append(period).append(" 신호없음 계측기 예시:\n");
        }
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) {
                out.append("\n");
            }
        }
        return out.toString();
    }

    private static String clip(String text, int max) {
        if (text == null) {
            return null;
        }
        return text.length() <= max ? text : text.substring(0, max);
    }
}
