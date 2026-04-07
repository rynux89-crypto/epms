package epms.util;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentDirectAnswerHelper {
    private AgentDirectAnswerHelper() {
    }

    public static String buildUsageMeterCountAnswer(String dbContext, String usageLabel) {
        if (hasUnavailable(dbContext)) {
            return "\uD604\uC7AC \uC6A9\uB3C4\uBCC4 \uACC4\uCE21\uAE30 \uC218\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        int count = extractCount(dbContext);
        String label = trimToNull(usageLabel);
        if (label == null) {
            label = "\uD574\uB2F9";
        }
        return label + " \uC6A9\uB3C4 \uACC4\uCE21\uAE30\uB294 \uCD1D " + count + "\uAC1C\uC785\uB2C8\uB2E4.";
    }

    public static String buildMeterCountAnswer(String dbContext) {
        if (hasUnavailable(dbContext)) {
            return "\uD604\uC7AC \uACC4\uCE21\uAE30 \uC218\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        int count = extractCount(dbContext);
        String scopeLabel = extractToken(dbContext, "scope");
        return (scopeLabel == null || scopeLabel.isEmpty())
            ? ("\uD604\uC7AC \uB4F1\uB85D\uB41C \uACC4\uCE21\uAE30\uB294 \uCD1D " + count + "\uAC1C\uC785\uB2C8\uB2E4.")
            : (scopeLabel + " \uAD00\uB828 \uACC4\uCE21\uAE30\uB294 \uCD1D " + count + "\uAC1C\uC785\uB2C8\uB2E4.");
    }

    public static String buildBuildingCountAnswer(String dbContext) {
        if (hasUnavailable(dbContext)) {
            return "\uD604\uC7AC \uAC74\uBB3C \uC218\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        return "\uD604\uC7AC \uB4F1\uB85D\uB41C \uAC74\uBB3C\uC740 \uCD1D " + extractCount(dbContext) + "\uAC1C\uC785\uB2C8\uB2E4.";
    }

    public static String buildUsageTypeCountAnswer(String dbContext) {
        if (hasUnavailable(dbContext)) {
            return "\uD604\uC7AC \uC6A9\uB3C4 \uC218\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        return "\uD604\uC7AC \uB4F1\uB85D\uB41C \uC6A9\uB3C4\uB294 \uCD1D " + extractCount(dbContext) + "\uAC1C\uC785\uB2C8\uB2E4.";
    }

    public static String buildPanelCountAnswer(String dbContext) {
        if (hasUnavailable(dbContext)) {
            return "\uD604\uC7AC \uD328\uB110 \uC218\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        int count = extractCount(dbContext);
        String scopeLabel = extractToken(dbContext, "scope");
        return (scopeLabel == null || scopeLabel.isEmpty())
            ? ("\uD604\uC7AC \uB4F1\uB85D\uB41C \uD328\uB110\uC740 \uCD1D " + count + "\uAC1C\uC785\uB2C8\uB2E4.")
            : (scopeLabel + " \uAD00\uB828 \uD328\uB110\uC740 \uCD1D " + count + "\uAC1C\uC785\uB2C8\uB2E4.");
    }

    public static String buildOpenAlarmCountAnswer(String dbContext) {
        if (hasUnavailable(dbContext)) {
            return "\uD604\uC7AC \uC5F4\uB9B0 \uC54C\uB78C \uC218\uB97C \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        int count = extractCount(dbContext);
        String typeLabel = extractToken(dbContext, "type");
        String scopeLabel = extractToken(dbContext, "scope");
        String subject = (typeLabel == null || typeLabel.isEmpty()) ? "\uC5F4\uB9B0 \uC54C\uB78C" : ("\uC5F4\uB9B0 " + typeLabel + " \uC54C\uB78C");
        return (scopeLabel == null || scopeLabel.isEmpty())
            ? ("\uD604\uC7AC " + subject + "\uC740 \uCD1D " + count + "\uAC74\uC785\uB2C8\uB2E4.")
            : (scopeLabel + " " + subject + "\uC740 \uCD1D " + count + "\uAC74\uC785\uB2C8\uB2E4.");
    }

    public static String chooseUserContextAnswer(String userContext, String fallback) {
        String text = trimToNull(userContext);
        return text == null ? fallback : text;
    }

    public static String buildPanelLatestStatusAnswer(String dbContext, String userContext) {
        if (dbContext != null && dbContext.contains("no data")) {
            return "\uD328\uB110 \uCD5C\uC2E0 \uC0C1\uD0DC \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        return chooseUserContextAnswer(userContext, "\uD328\uB110 \uCD5C\uC2E0 \uC0C1\uD0DC\uB97C \uC870\uD68C\uD588\uC2B5\uB2C8\uB2E4.");
    }

    public static AgentRuntimeModels.DirectAnswerResult buildUserContextResult(String dbContext, String userContext, String fallback) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = chooseUserContextAnswer(userContext, fallback);
        return result;
    }

    private static boolean hasUnavailable(String dbContext) {
        return dbContext != null && dbContext.contains("unavailable");
    }

    private static int extractCount(String dbContext) {
        Matcher cm = Pattern.compile("count=([0-9]+)").matcher(dbContext == null ? "" : dbContext);
        return cm.find() ? Integer.parseInt(cm.group(1)) : 0;
    }

    private static String extractToken(String dbContext, String name) {
        Matcher m = Pattern.compile(name + "=([^;]+)").matcher(dbContext == null ? "" : dbContext);
        return m.find() ? trimToNull(m.group(1)) : null;
    }

    private static String trimToNull(String s) {
        if (s == null) {
            return null;
        }
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }
}
