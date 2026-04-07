package epms.agent;

import epms.util.AgentModelRouter;
import epms.util.AgentQueryRouter;
import epms.util.AgentSupport;

import javax.servlet.ServletContext;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentApiRequestSupport {
    public static final String ATTR_USER_MESSAGE = "agent.userMessage";
    public static final String ATTR_FORCE_LLM_ONLY = "agent.forceLlmOnly";
    public static final String ATTR_FORCE_RULE_ONLY = "agent.forceRuleOnly";
    public static final String ATTR_PREFERS_NARRATIVE_HINT = "agent.prefersNarrativeHint";
    public static final String ATTR_IS_ADMIN = "agent.isAdmin";

    private static final Map<String, List<Long>> RATE_LIMIT_MAP = new ConcurrentHashMap<String, List<Long>>();
    private static final int RATE_LIMIT_WINDOW_MS = 60000;
    private static final int RATE_LIMIT_MAX_REQUESTS = 10;
    private static final Pattern MESSAGE_PATTERN = Pattern.compile("\"message\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"", Pattern.DOTALL);

    private AgentApiRequestSupport() {
    }

    public static boolean prepare(HttpServletRequest request, HttpServletResponse response, ServletContext application)
        throws IOException {
        request.setCharacterEncoding("UTF-8");
        response.setCharacterEncoding("UTF-8");
        response.setContentType("application/json;charset=UTF-8");
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type");

        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            response.setStatus(HttpServletResponse.SC_OK);
            return false;
        }

        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            writeErrorJson(response, HttpServletResponse.SC_METHOD_NOT_ALLOWED, "Method not allowed");
            return false;
        }

        String clientIp = resolveClientIp(request);
        if (!checkRateLimit(clientIp)) {
            writeErrorJson(
                response,
                429,
                "Rate limit exceeded. Maximum 10 requests per minute."
            );
            return false;
        }

        String body;
        try {
            body = readRequestBody(request);
        } catch (IOException e) {
            writeErrorJson(response, HttpServletResponse.SC_BAD_REQUEST, "Failed to read request");
            return false;
        }

        String userMessage = extractMessage(body);
        if (!isValidInput(userMessage)) {
            writeErrorJson(response, HttpServletResponse.SC_BAD_REQUEST, "Invalid message");
            return false;
        }

        AgentQueryRouter.ParsedQuery parsedQuery = AgentQueryRouter.parse(userMessage);
        request.setAttribute(ATTR_USER_MESSAGE, parsedQuery.userMessage);
        request.setAttribute(ATTR_FORCE_LLM_ONLY, Boolean.valueOf(parsedQuery.mode == AgentQueryRouter.Mode.LLM_ONLY));
        request.setAttribute(ATTR_FORCE_RULE_ONLY, Boolean.valueOf(parsedQuery.mode == AgentQueryRouter.Mode.RULE_ONLY));
        request.setAttribute(ATTR_PREFERS_NARRATIVE_HINT, Boolean.valueOf(parsedQuery.prefersNarrativeLlm));
        request.setAttribute(ATTR_IS_ADMIN, Boolean.valueOf(isAdminRequest(request, application)));
        return true;
    }

    private static String resolveClientIp(HttpServletRequest request) {
        String clientIp = AgentSupport.trimToNull(request.getHeader("X-Forwarded-For"));
        if (clientIp != null) {
            int comma = clientIp.indexOf(',');
            if (comma >= 0) {
                clientIp = AgentSupport.trimToNull(clientIp.substring(0, comma));
            }
        }
        if (clientIp == null) {
            clientIp = request.getRemoteAddr();
        }
        return clientIp == null ? "" : clientIp;
    }

    private static boolean checkRateLimit(String clientIp) {
        long now = System.currentTimeMillis();
        if (RATE_LIMIT_MAP.size() > 5000) {
            synchronized (RATE_LIMIT_MAP) {
                if (RATE_LIMIT_MAP.size() > 5000) {
                    RATE_LIMIT_MAP.clear();
                }
            }
        }

        List<Long> timestamps = RATE_LIMIT_MAP.compute(clientIp, (k, v) -> {
            List<Long> values = v == null ? new ArrayList<Long>() : v;
            values.removeIf(t -> now - t.longValue() > RATE_LIMIT_WINDOW_MS);
            values.add(Long.valueOf(now));
            return values;
        });
        return timestamps.size() <= RATE_LIMIT_MAX_REQUESTS;
    }

    private static String readRequestBody(HttpServletRequest request) throws IOException {
        StringBuilder sb = new StringBuilder();
        String line;
        java.io.BufferedReader reader = request.getReader();
        while ((line = reader.readLine()) != null) {
            sb.append(line).append('\n');
        }
        return sb.toString();
    }

    private static String extractMessage(String body) {
        if (body == null) {
            return "";
        }
        Matcher matcher = MESSAGE_PATTERN.matcher(body);
        if (!matcher.find()) {
            return "";
        }
        return AgentSupport.unescapeJsonText(matcher.group(1));
    }

    private static boolean isValidInput(String input) {
        return input != null && !input.isEmpty() && input.length() <= 2000;
    }

    private static boolean isAdminRequest(HttpServletRequest request, ServletContext application) {
        if (request == null) {
            return false;
        }
        try {
            HttpSession session = request.getSession(false);
            if (session != null) {
                Object role = session.getAttribute("role");
                if (role != null && "ADMIN".equalsIgnoreCase(String.valueOf(role).trim())) {
                    return true;
                }
                Object isAdmin = session.getAttribute("isAdmin");
                if (isAdmin instanceof Boolean && ((Boolean) isAdmin).booleanValue()) {
                    return true;
                }
            }
        } catch (Exception ignore) {
        }

        String headerToken = AgentSupport.trimToNull(request.getHeader("X-EPMS-ADMIN-TOKEN"));
        if (headerToken == null) {
            return false;
        }
        Properties props = AgentSupport.loadAgentModelConfig(application);
        String configuredToken = AgentSupport.trimToNull(props.getProperty("admin_token"));
        return configuredToken != null && configuredToken.equals(headerToken);
    }

    private static void writeErrorJson(HttpServletResponse response, int statusCode, String errorMessage) throws IOException {
        response.setStatus(statusCode);
        response.getWriter().write("{\"success\":false,\"error\":" + jsonEscape(errorMessage) + "}");
    }

    private static String jsonEscape(String text) {
        if (text == null) {
            return "\"\"";
        }
        StringBuilder sb = new StringBuilder();
        sb.append('"');
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '"':
                    sb.append("\\\"");
                    break;
                case '\\':
                    sb.append("\\\\");
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
        return sb.toString();
    }
}
