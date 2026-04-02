package epms.plc;

import epms.util.ModbusSupport;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

/**
 * Servlet entrypoint for the Modbus API.
 *
 * <p>The legacy JSP endpoint remains only as a compatibility wrapper that forwards
 * requests here.</p>
 */
public final class ModbusApiServlet extends HttpServlet {
    private static final String JSON_TYPE = "application/json;charset=UTF-8";

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        serviceModbus(req, resp);
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        serviceModbus(req, resp);
    }

    private void serviceModbus(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setCharacterEncoding(StandardCharsets.UTF_8.name());
        resp.setContentType(JSON_TYPE);

        ModbusRequestSupport.ApiRequestContext reqCtx = ModbusRequestSupport.buildApiRequestContext(req);
        ModbusRequestSupport.traceRequestIfNeeded(req, reqCtx);

        String action = reqCtx.action;
        if (action == null || action.trim().isEmpty()) {
            writeJson(resp, ModbusApiResponseSupport.buildErrorJson("action is required"));
            return;
        }
        String normalizedAction = reqCtx.actionNorm;
        String alarmApiUrl = ModbusSupport.resolveAlarmApiUrl(req);

        if ("polling_status".equalsIgnoreCase(normalizedAction) || "polling_snapshot".equalsIgnoreCase(normalizedAction)) {
            writeJson(resp, ModbusApiActionSupport.handlePollingState(
                    getServletContext(),
                    reqCtx.plcId,
                    alarmApiUrl,
                    "polling_snapshot".equalsIgnoreCase(normalizedAction)
            ));
            return;
        }

        if ("clear_cache".equalsIgnoreCase(normalizedAction)) {
            writeJson(resp, ModbusApiActionSupport.handleClearCache(req.getMethod(), reqCtx.plcId));
            return;
        }

        if ("stop_polling".equalsIgnoreCase(normalizedAction)) {
            writeJson(resp, ModbusApiActionSupport.handleStopPolling(getServletContext(), req.getMethod(), reqCtx.plcId));
            return;
        }

        if ("read".equalsIgnoreCase(normalizedAction)) {
            writeJson(resp, ModbusApiActionSupport.handleRead(reqCtx.plcId, alarmApiUrl));
            return;
        }

        if ("start_polling".equalsIgnoreCase(normalizedAction)) {
            writeJson(resp, ModbusApiActionSupport.handleStartPolling(
                    getServletContext(),
                    req.getMethod(),
                    reqCtx.plcId,
                    req.getParameter("polling_ms"),
                    alarmApiUrl
            ));
            return;
        }

        writeJson(resp, ModbusApiResponseSupport.buildErrorJson("unknown action"));
    }

    private static void writeJson(HttpServletResponse resp, String body) throws IOException {
        resp.getWriter().write(body == null ? "" : body);
    }
}
