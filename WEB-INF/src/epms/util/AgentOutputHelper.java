package epms.util;

import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.Writer;

public final class AgentOutputHelper {
    private AgentOutputHelper() {
    }

    public static String buildSuccessJson(String finalAnswer, String rawDbContext, String userDbContext, boolean isAdmin) {
        String line = "{\"response\":\"" + escapeJsonString(finalAnswer) + "\",\"done\":true}\n";
        return "{\"provider_response\":"
            + quote(line)
            + ",\"db_context\":"
            + quote(rawDbContext)
            + ",\"db_context_user\":"
            + quote(userDbContext)
            + ",\"is_admin\":"
            + (isAdmin ? "true" : "false")
            + "}";
    }

    public static String buildErrorJson(String errorMessage) {
        return "{\"error\":" + quote(errorMessage) + "}";
    }

    public static String quoteJson(String value) {
        return quote(value);
    }

    public static void writeSuccessJson(
        Writer out,
        HttpServletResponse response,
        String finalAnswer,
        String rawDbContext,
        String userDbContext,
        boolean isAdmin
    ) throws IOException {
        response.setStatus(200);
        out.write(buildSuccessJson(finalAnswer, rawDbContext, userDbContext, isAdmin));
    }

    public static void writeErrorJson(
        Writer out,
        HttpServletResponse response,
        int statusCode,
        String errorMessage
    ) throws IOException {
        response.setStatus(statusCode);
        out.write(buildErrorJson(errorMessage));
    }

    private static String quote(String value) {
        return "\"" + EpmsWebUtil.escJson(value == null ? "" : value) + "\"";
    }

    private static String escapeJsonString(String value) {
        if (value == null) return "";
        return value.replace("\\", "\\\\")
                    .replace("\"", "\\\"")
                    .replace("\n", "\\n")
                    .replace("\r", "\\r");
    }
}
