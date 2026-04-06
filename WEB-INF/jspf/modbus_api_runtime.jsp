<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.lang.reflect.InvocationTargetException" %>
<%@ page import="java.lang.reflect.Method" %>
<%@ page import="epms.plc.ModbusApiActionSupport" %>
<%@ page import="epms.plc.ModbusApiResponseSupport" %>
<%@ page import="epms.plc.ModbusConfigRepository" %>
<%@ page import="epms.plc.ModbusRequestSupport" %>
<%@ page import="epms.util.ModbusSupport" %>
<%!
private static String modbusRuntimeEscJson(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
}

private static String modbusRuntimeErr(String msg) {
    return "{\"ok\":false,\"error\":\"" + modbusRuntimeEscJson(msg == null ? "" : msg) + "\"}";
}

private static String modbusRuntimeStartOk(String info, int pollingMs) {
    return "{\"ok\":true,\"info\":\"" + modbusRuntimeEscJson(info == null ? "" : info) + "\",\"polling_ms\":" + pollingMs + "}";
}
%>
<%
response.setCharacterEncoding(StandardCharsets.UTF_8.name());
response.setContentType("application/json;charset=UTF-8");

ModbusRequestSupport.ApiRequestContext reqCtx = ModbusRequestSupport.buildApiRequestContext(request);
ModbusRequestSupport.traceRequestIfNeeded(request, reqCtx);

String action = reqCtx.action;
if (action == null || action.trim().isEmpty()) {
    out.print(modbusRuntimeErr("action is required"));
    return;
}

String normalizedAction = reqCtx.actionNorm;
String alarmApiUrl = ModbusSupport.resolveAlarmApiUrl(request);

if ("polling_status".equalsIgnoreCase(normalizedAction) || "polling_snapshot".equalsIgnoreCase(normalizedAction)) {
    out.print(ModbusApiActionSupport.handlePollingState(
        application,
        reqCtx.plcId,
        alarmApiUrl,
        "polling_snapshot".equalsIgnoreCase(normalizedAction)
    ));
    return;
}

if ("clear_cache".equalsIgnoreCase(normalizedAction)) {
    out.print(ModbusApiActionSupport.handleClearCache(request.getMethod(), reqCtx.plcId));
    return;
}

if ("stop_polling".equalsIgnoreCase(normalizedAction)) {
    out.print(ModbusApiActionSupport.handleStopPolling(application, request.getMethod(), reqCtx.plcId));
    return;
}

if ("read".equalsIgnoreCase(normalizedAction)) {
    out.print(ModbusApiActionSupport.handleRead(reqCtx.plcId, alarmApiUrl));
    return;
}

if ("start_polling".equalsIgnoreCase(normalizedAction)) {
    if (!"POST".equalsIgnoreCase(request.getMethod())) {
        out.print(modbusRuntimeErr("POST method is required for start_polling"));
        return;
    }
    if (reqCtx.plcId == null) {
        out.print(modbusRuntimeErr("plc_id is required"));
        return;
    }

    try {
        int plcId = reqCtx.plcId.intValue();
        int pollingMs = 1000;
        Object cfg = ModbusConfigRepository.loadConfigSnapshot(plcId);
        if (cfg == null) {
            out.print(modbusRuntimeErr("Selected PLC config not found."));
            return;
        }

        boolean exists = true;
        boolean enabled = true;
        try {
            Field existsField = cfg.getClass().getDeclaredField("exists");
            existsField.setAccessible(true);
            exists = existsField.getBoolean(cfg);
        } catch (Exception ignore) {
        }
        try {
            Field enabledField = cfg.getClass().getDeclaredField("enabled");
            enabledField.setAccessible(true);
            enabled = enabledField.getBoolean(cfg);
        } catch (Exception ignore) {
        }
        try {
            Field pollingField = cfg.getClass().getDeclaredField("pollingMs");
            pollingField.setAccessible(true);
            int cfgPollingMs = pollingField.getInt(cfg);
            if (cfgPollingMs > 0) pollingMs = cfgPollingMs;
        } catch (Exception ignore) {
        }
        String pollingMsParam = request.getParameter("polling_ms");
        if (pollingMsParam != null && !pollingMsParam.trim().isEmpty()) {
            try {
                int reqPollingMs = Integer.parseInt(pollingMsParam.trim());
                if (reqPollingMs > 0) pollingMs = reqPollingMs;
            } catch (Exception ignore) {
            }
        }

        if (!exists) {
            out.print(modbusRuntimeErr("Selected PLC config not found."));
            return;
        }
        if (!enabled) {
            out.print(modbusRuntimeErr("Selected PLC is inactive."));
            return;
        }

        Class<?> pollingCls = Class.forName("epms.plc.ModbusPollingSupport");
        Object pollRuntime = pollingCls.getMethod("getPollRuntime", javax.servlet.ServletContext.class).invoke(null, application);
        Method startMethod = null;
        Method[] methods = pollingCls.getMethods();
        for (int i = 0; i < methods.length; i++) {
            Method m = methods[i];
            if (!"startServerPolling".equals(m.getName())) continue;
            startMethod = m;
            break;
        }
        if (startMethod == null) {
            out.print(modbusRuntimeErr("startServerPolling method not found."));
            return;
        }

        Class<?>[] paramTypes = startMethod.getParameterTypes();
        if (paramTypes.length == 4) {
            startMethod.invoke(null, pollRuntime, Integer.valueOf(plcId), Integer.valueOf(pollingMs), alarmApiUrl);
        } else if (paramTypes.length == 3) {
            startMethod.invoke(null, pollRuntime, Integer.valueOf(plcId), Integer.valueOf(pollingMs));
        } else {
            out.print(modbusRuntimeErr("Unsupported startServerPolling signature."));
            return;
        }

        out.print(modbusRuntimeStartOk("server polling started", pollingMs));
    } catch (InvocationTargetException ite) {
        Throwable cause = ite.getCause();
        out.print(modbusRuntimeErr(cause == null ? ite.toString() : String.valueOf(cause.getMessage())));
    } catch (Throwable t) {
        out.print(modbusRuntimeErr(String.valueOf(t.getMessage())));
    }
    return;
}

out.print(modbusRuntimeErr("unknown action"));
%>
