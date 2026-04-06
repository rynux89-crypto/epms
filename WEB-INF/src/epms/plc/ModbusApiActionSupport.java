package epms.plc;

import javax.servlet.ServletContext;

public final class ModbusApiActionSupport {
    private ModbusApiActionSupport() {
    }

    public static String handlePollingState(ServletContext servletContext, Integer plcId, String alarmApiUrl, boolean includeRows) {
        ModbusPollingSupport.PollRuntime pollRt = ModbusPollingSupport.getPollRuntime(servletContext);
        try {
            return ModbusApiResponseSupport.buildPollingStateJson(
                    ModbusConfigRepository.loadAllConfigSnapshots(),
                    pollRt.states,
                    includeRows
            );
        } catch (Exception e) {
            return ModbusApiResponseSupport.buildPollingStateJson(null, pollRt.states, includeRows);
        }
    }

    public static String handleClearCache(String method, Integer plcId) {
        if (!"POST".equalsIgnoreCase(method)) {
            return ModbusApiResponseSupport.buildErrorJson("POST method is required for clear_cache");
        }
        ModbusCacheSupport.clearCaches(plcId);
        return ModbusApiResponseSupport.buildOkInfoJson("cache cleared");
    }

    public static String handleStopPolling(ServletContext servletContext, String method, Integer plcId) {
        if (!"POST".equalsIgnoreCase(method)) {
            return ModbusApiResponseSupport.buildErrorJson("POST method is required for stop_polling");
        }
        if (plcId == null) {
            return ModbusApiResponseSupport.buildErrorJson("plc_id is required");
        }
        ModbusPollingSupport.stopServerPolling(
                ModbusPollingSupport.getPollRuntime(servletContext),
                plcId.intValue()
        );
        return ModbusApiResponseSupport.buildOkInfoJson("server polling stopped");
    }

    public static String handleRead(Integer plcId, String alarmApiUrl) {
        if (plcId == null) {
            return ModbusApiResponseSupport.buildErrorJson("plc_id is required");
        }
        PlcReadResult readResult = ModbusReadService.readPlcData(plcId.intValue(), alarmApiUrl);
        return ModbusApiResponseSupport.buildReadJson(
                readResult.ok,
                readResult.info,
                readResult.error,
                readResult.measurementsInserted,
                readResult.harmonicInserted,
                readResult.flickerInserted,
                readResult.deviceEventsOpened,
                readResult.deviceEventsClosed,
                readResult.aiAlarmOpened,
                readResult.aiAlarmClosed,
                readResult.rows,
                readResult.diRows
        );
    }

    public static String handleStartPolling(
            ServletContext servletContext,
            String method,
            Integer plcId,
            String pollingMsParam,
            String alarmApiUrl) {
        if (!"POST".equalsIgnoreCase(method)) {
            return ModbusApiResponseSupport.buildErrorJson("POST method is required for start_polling");
        }
        if (plcId == null) {
            return ModbusApiResponseSupport.buildErrorJson("plc_id is required");
        }
        try {
            ModbusApiResponseSupport.PlcConfigSnapshot cfg = ModbusConfigRepository.loadConfigSnapshot(plcId.intValue());
            if (cfg == null || !cfg.exists) {
                return ModbusApiResponseSupport.buildErrorJson("Selected PLC config not found.");
            }
            if (!cfg.enabled) {
                return ModbusApiResponseSupport.buildErrorJson("Selected PLC is inactive.");
            }
            int pollingMs = resolvePollingMs(pollingMsParam, cfg);
            ModbusPollingSupport.startServerPolling(
                    ModbusPollingSupport.getPollRuntime(servletContext),
                    plcId.intValue(),
                    pollingMs,
                    alarmApiUrl
            );
            return ModbusApiResponseSupport.buildStartPollingJson("server polling started", pollingMs);
        } catch (Exception e) {
            return ModbusApiResponseSupport.buildErrorJson(e.getMessage());
        }
    }

    private static int resolvePollingMs(String pollingMsParam, ModbusApiResponseSupport.PlcConfigSnapshot cfg) {
        int pollingMs = cfg.pollingMs > 0 ? cfg.pollingMs : 1000;
        if (pollingMsParam != null && !pollingMsParam.trim().isEmpty()) {
            try {
                int reqMs = Integer.parseInt(pollingMsParam.trim());
                if (reqMs > 0) {
                    pollingMs = reqMs;
                }
            } catch (Exception ignore) {
            }
        }
        return pollingMs;
    }
}
