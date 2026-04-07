package epms.plc;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class ModbusApiResponseSupport {
    private static final String STATUS_REASON_INACTIVE = "plc_config.enabled=0 상태입니다.";
    private static final String STATUS_REASON_PLC_RECONNECTING = "PLC 재연결을 시도 중입니다.";
    private static final String STATUS_REASON_CONFIG_MISSING = "PLC 설정을 찾을 수 없거나 IP가 비어 있습니다.";
    private static final String STATUS_REASON_MANUALLY_STOPPED = "수동 중지로 polling 자동 시작이 막혀 있습니다.";
    private static final String STATUS_REASON_RUNTIME_RESET = "서버 재시작 또는 런타임 초기화로 polling 상태가 초기화된 것으로 보입니다.";
    private static final String STATUS_REASON_NO_ACTIVE_TASK = "현재 실행 중인 polling 작업이 없습니다.";

    public static final class PlcConfigSnapshot {
        public boolean exists;
        public boolean enabled;
        public int pollingMs;
        public String ip;
    }

    private ModbusApiResponseSupport() {
    }

    public static String buildPollingStateJson(
            Map<Integer, PlcConfigSnapshot> cfgMap,
            Map<Integer, ModbusPollingSupport.PollState> states,
            boolean includeRows) {
        StringBuilder s = new StringBuilder();
        s.append("{\"ok\":true,\"states\":[");
        boolean first = true;
        if (cfgMap != null && !cfgMap.isEmpty()) {
            for (Map.Entry<Integer, PlcConfigSnapshot> entry : cfgMap.entrySet()) {
                Integer id = entry.getKey();
                PlcConfigSnapshot cfg = entry.getValue();
                ModbusPollingSupport.PollState st = states == null ? null : states.get(id);
                if (!first) s.append(",");
                first = false;
                appendPollStateJson(s, id, cfg, st, includeRows);
            }
        } else if (states != null && !states.isEmpty()) {
            List<Integer> ids = new ArrayList<>(states.keySet());
            Collections.sort(ids);
            for (Integer id : ids) {
                if (!first) s.append(",");
                first = false;
                appendPollStateJson(s, id, null, states.get(id), includeRows);
            }
        }
        s.append("]}");
        return s.toString();
    }

    public static String buildReadJson(
            boolean ok,
            String info,
            String error,
            int measurementsInserted,
            int harmonicInserted,
            int flickerInserted,
            int deviceEventsOpened,
            int deviceEventsClosed,
            int aiAlarmOpened,
            int aiAlarmClosed,
            List<PlcAiReadRow> rows,
            List<PlcDiReadRow> diRows) {
        StringBuilder outJson = new StringBuilder();
        outJson.append("{\"ok\":").append(ok ? "true" : "false");
        if (ok) {
            outJson.append(",\"info\":\"").append(escapeJson(info)).append("\"");
            outJson.append(",\"measurements_inserted\":").append(measurementsInserted);
            outJson.append(",\"harmonic_inserted\":").append(harmonicInserted);
            outJson.append(",\"flicker_inserted\":").append(flickerInserted);
            outJson.append(",\"device_events_opened\":").append(deviceEventsOpened);
            outJson.append(",\"device_events_closed\":").append(deviceEventsClosed);
            outJson.append(",\"ai_alarm_opened\":").append(aiAlarmOpened);
            outJson.append(",\"ai_alarm_closed\":").append(aiAlarmClosed);
            outJson.append(",\"rows\":");
            appendAiRowsJson(outJson, rows);
            outJson.append(",\"di_rows\":");
            appendDiRowsJson(outJson, diRows);
            outJson.append("}");
        } else {
            outJson.append(",\"error\":\"").append(escapeJson(error)).append("\"}");
        }
        return outJson.toString();
    }

    public static String buildOkInfoJson(String info) {
        return "{\"ok\":true,\"info\":\"" + escapeJson(info) + "\"}";
    }

    public static String buildStartPollingJson(String info, int pollingMs) {
        return "{\"ok\":true,\"info\":\"" + escapeJson(info) + "\",\"polling_ms\":" + pollingMs + "}";
    }

    public static String buildErrorJson(String error) {
        return "{\"ok\":false,\"error\":\"" + escapeJson(error) + "\"}";
    }

    private static void appendPollStateJson(
            StringBuilder s,
            Integer id,
            PlcConfigSnapshot cfg,
            ModbusPollingSupport.PollState st,
            boolean includeRows) {
        ModbusPollingSupport.PollState safeState = (st == null) ? new ModbusPollingSupport.PollState() : st;
        PlcConfigSnapshot safeCfg = (cfg == null) ? new PlcConfigSnapshot() : cfg;
        if (safeCfg.exists && safeCfg.pollingMs > 0) {
            safeState.pollingMs = safeCfg.pollingMs;
        }
        String status = resolvePollStatus(safeCfg, safeState);
        String statusReason = resolvePollStatusReason(safeCfg, safeState, status);
        long attempt = safeState.attemptCount.get();
        long success = safeState.successCount.get();
        double successRate = (attempt > 0L) ? (success * 100.0d / attempt) : 0.0d;
        double avgReadMs = (success > 0L) ? (safeState.readDurationSumMs.get() * 1.0d / success) : 0.0d;
        s.append("{")
         .append("\"plc_id\":").append(id).append(",")
         .append("\"enabled\":").append(safeCfg.enabled ? "true" : "false").append(",")
         .append("\"status\":\"").append(status).append("\",")
         .append("\"running\":").append(safeState.running ? "true" : "false").append(",")
         .append("\"polling_ms\":").append(safeState.pollingMs).append(",")
         .append("\"attempt_count\":").append(attempt).append(",")
         .append("\"success_count\":").append(success).append(",")
         .append("\"success_rate\":").append(String.format(Locale.US, "%.2f", successRate)).append(",")
         .append("\"read_count\":").append(safeState.readCount.get()).append(",")
         .append("\"di_read_count\":").append(safeState.diReadCount.get()).append(",")
         .append("\"ai_read_count\":").append(safeState.aiReadCount.get()).append(",")
         .append("\"last_read_ms\":").append(safeState.lastReadDurationMs).append(",")
         .append("\"di_read_ms\":").append(safeState.lastDiReadMs).append(",")
         .append("\"ai_read_ms\":").append(safeState.lastAiReadMs).append(",")
         .append("\"ai_sample_persist_ms\":").append(safeState.lastAiSamplePersistMs).append(",")
         .append("\"ai_target_persist_ms\":").append(safeState.lastAiTargetPersistMs).append(",")
         .append("\"ai_alarm_persist_ms\":").append(safeState.lastAiAlarmPersistMs).append(",")
         .append("\"proc_ms\":").append(safeState.lastProcMs).append(",")
         .append("\"avg_read_ms\":").append(String.format(Locale.US, "%.1f", avgReadMs)).append(",")
         .append("\"last_run_at\":").append(safeState.lastRunAt).append(",")
         .append("\"last_di_run_at\":").append(safeState.lastDiRunAt).append(",")
         .append("\"last_ai_run_at\":").append(safeState.lastAiRunAt).append(",")
         .append("\"auto_start_allowed\":").append(safeState.autoStartAllowed ? "true" : "false").append(",")
         .append("\"status_reason\":\"").append(escapeJson(statusReason)).append("\",")
         .append("\"last_info\":\"").append(escapeJson(safeState.lastInfo)).append("\",")
         .append("\"last_error\":\"").append(escapeJson(safeState.lastError)).append("\"");
        if (includeRows) {
            s.append(",\"rows\":");
            appendAiRowsJson(s, safeState.lastRows);
            s.append(",\"di_rows\":");
            appendDiRowsJson(s, safeState.lastDiRows);
        }
        s.append("}");
    }

    public static void appendAiRowsJson(StringBuilder outJson, List<PlcAiReadRow> rows) {
        outJson.append("[");
        if (rows != null) {
            for (int i = 0; i < rows.size(); i++) {
                PlcAiReadRow row = rows.get(i);
                double value = row == null ? 0.0d : row.value;
                outJson.append("{")
                       .append("\"idx\":").append(row.idx).append(",")
                       .append("\"meter_id\":").append(row.meterId).append(",")
                       .append("\"token\":\"").append(escapeJson(row.token)).append("\",")
                       .append("\"reg1\":").append(row.reg1).append(",")
                       .append("\"reg2\":").append(row.reg2).append(",")
                       .append("\"value\":").append(String.format(Locale.US, "%.6f", value))
                       .append("}");
                if (i < rows.size() - 1) outJson.append(",");
            }
        }
        outJson.append("]");
    }

    public static void appendDiRowsJson(StringBuilder outJson, List<PlcDiReadRow> rows) {
        outJson.append("[");
        if (rows != null) {
            for (int i = 0; i < rows.size(); i++) {
                PlcDiReadRow row = rows.get(i);
                outJson.append("{")
                       .append("\"idx\":").append(row.idx).append(",")
                       .append("\"point_id\":").append(row.pointId).append(",")
                       .append("\"di_address\":").append(row.diAddress).append(",")
                       .append("\"bit_no\":").append(row.bitNo).append(",")
                       .append("\"tag_name\":\"").append(escapeJson(row.tagName)).append("\",")
                       .append("\"item_name\":\"").append(escapeJson(row.itemName)).append("\",")
                       .append("\"panel_name\":\"").append(escapeJson(row.panelName)).append("\",")
                       .append("\"value\":").append(row.value)
                       .append("}");
                if (i < rows.size() - 1) outJson.append(",");
            }
        }
        outJson.append("]");
    }

    private static String resolvePollStatus(PlcConfigSnapshot cfg, ModbusPollingSupport.PollState st) {
        boolean enabled = cfg != null && cfg.enabled;
        if (!enabled) return "inactive";
        if (st != null && st.lastError != null && !st.lastError.trim().isEmpty()) return "error";
        if (st != null && st.running) return "running";
        return "stopped";
    }

    private static String resolvePollStatusReason(PlcConfigSnapshot cfg, ModbusPollingSupport.PollState st, String status) {
        ModbusPollingSupport.PollState safeState = (st == null) ? new ModbusPollingSupport.PollState() : st;
        PlcConfigSnapshot safeCfg = (cfg == null) ? new PlcConfigSnapshot() : cfg;
        String normalized = status == null ? "" : status.trim().toLowerCase(Locale.ROOT);
        if ("inactive".equals(normalized)) {
            return STATUS_REASON_INACTIVE;
        }
        if ("running".equals(normalized)) {
            return safeState.lastInfo == null ? "" : safeState.lastInfo;
        }
        if ("error".equals(normalized)) {
            String error = safeState.lastError == null ? "" : safeState.lastError.trim();
            String lastSuccess = formatPollTimestamp(safeState.lastSuccessAt);
            if (!error.isEmpty() && !lastSuccess.isEmpty()) {
                return error + " | " + STATUS_REASON_PLC_RECONNECTING + " 마지막 정상 주기: " + lastSuccess;
            }
            if (!error.isEmpty()) {
                return error + " | " + STATUS_REASON_PLC_RECONNECTING;
            }
            if (!lastSuccess.isEmpty()) {
                return STATUS_REASON_PLC_RECONNECTING + " 마지막 정상 주기: " + lastSuccess;
            }
            return STATUS_REASON_PLC_RECONNECTING;
        }
        if (!safeCfg.exists || safeCfg.ip == null || safeCfg.ip.trim().isEmpty()) {
            return STATUS_REASON_CONFIG_MISSING;
        }
        if (!safeState.autoStartAllowed) {
            return (safeState.lastInfo != null && !safeState.lastInfo.trim().isEmpty())
                    ? safeState.lastInfo
                    : STATUS_REASON_MANUALLY_STOPPED;
        }
        if (safeState.lastRunAt <= 0L) {
            return STATUS_REASON_RUNTIME_RESET;
        }
        if (safeState.lastInfo != null && !safeState.lastInfo.trim().isEmpty()) {
            return safeState.lastInfo;
        }
        return STATUS_REASON_NO_ACTIVE_TASK;
    }

    private static String formatPollTimestamp(long epochMs) {
        if (epochMs <= 0L) return "";
        return new Timestamp(epochMs).toString();
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        StringBuilder out = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            switch (ch) {
                case '\\':
                    out.append("\\\\");
                    break;
                case '"':
                    out.append("\\\"");
                    break;
                case '\n':
                    out.append("\\n");
                    break;
                case '\r':
                    out.append("\\r");
                    break;
                case '\t':
                    out.append("\\t");
                    break;
                case '\b':
                    out.append("\\b");
                    break;
                case '\f':
                    out.append("\\f");
                    break;
                default:
                    if (ch < 0x20) {
                        out.append(String.format(Locale.US, "\\u%04x", (int) ch));
                    } else {
                        out.append(ch);
                    }
                    break;
            }
        }
        return out.toString();
    }
}
