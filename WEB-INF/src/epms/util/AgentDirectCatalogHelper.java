package epms.util;

import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentDirectCatalogHelper {
    private AgentDirectCatalogHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult usageMeterCount(String dbContext, String usageLabel) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildUsageMeterCountAnswer(dbContext, usageLabel);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult meterCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildMeterCountAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult usageTypeList(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentAnswerFormatter.buildUsageTypeListDirectAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult meterList(String dbContext) {
        return AgentDirectResultHelper.simple(
            dbContext,
            AgentAnswerFormatter.buildUserDbContext(dbContext),
            "\uacc4\uce21\uae30 \ubaa9\ub85d\uc744 \uc870\ud68c\ud588\uc2b5\ub2c8\ub2e4."
        );
    }

    public static AgentRuntimeModels.DirectAnswerResult buildingCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildBuildingCountAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult usageTypeCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildUsageTypeCountAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult panelCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = AgentDirectAnswerHelper.buildPanelCountAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult panelLatest(String dbContext) {
        return AgentDirectResultHelper.panelLatest(dbContext, AgentAnswerFormatter.buildUserDbContext(dbContext));
    }

    public static AgentRuntimeModels.DirectAnswerResult usageMeterTop(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = buildUsageMeterTopAnswer(dbContext);
        return result;
    }

    private static String buildUsageMeterTopAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return "\uc6a9\ub3c4\ubcc4 \uacc4\uce21\uae30 \uc218 TOP \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("unavailable")) {
            return "\uc6a9\ub3c4\ubcc4 \uacc4\uce21\uae30 \uc218 TOP\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("no data")) {
            return "\uc6a9\ub3c4\ubcc4 \uacc4\uce21\uae30 \uc218 TOP \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }

        Matcher row = Pattern.compile("\\s[0-9]+\\)([^:;]+):\\s*count=([0-9]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String usage = EpmsWebUtil.trimToNull(row.group(1));
            String count = EpmsWebUtil.trimToNull(row.group(2));
            if (usage == null || count == null) continue;
            parts.add(usage + " " + count + "\uac1c");
        }
        if (parts.isEmpty()) {
            return "\uc6a9\ub3c4\ubcc4 \uacc4\uce21\uae30 \uc218 TOP \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        return "\uacc4\uce21\uae30\ub97c \uac00\uc7a5 \ub9ce\uc774 \uac00\uc9c4 \uc6a9\ub3c4\ub294 " + String.join(" / ", parts) + "\uc785\ub2c8\ub2e4.";
    }
}
