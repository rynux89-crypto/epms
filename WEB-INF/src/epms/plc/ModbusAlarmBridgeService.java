package epms.plc;

import epms.util.ModbusSupport;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.util.List;
import java.util.Locale;

public final class ModbusAlarmBridgeService {
    private ModbusAlarmBridgeService() {
    }

    public static int[] persistDiRowsViaAlarmApi(String alarmApiUrl, int plcId, List<PlcDiReadRow> diRows, Timestamp measuredAt) throws Exception {
        if (diRows == null || diRows.isEmpty()) {
            return new int[]{0, 0};
        }

        StringBuilder rows = new StringBuilder();
        for (PlcDiReadRow r : diRows) {
            if (rows.length() > 0) rows.append(';');
            int pointId = r.pointId;
            int diAddress = r.diAddress;
            int bitNo = r.bitNo;
            int value = r.value;
            String tagName = r.tagName == null ? "" : r.tagName;
            String itemName = r.itemName == null ? "" : r.itemName;
            String panelName = r.panelName == null ? "" : r.panelName;
            rows.append(pointId).append('|')
                .append(diAddress).append('|')
                .append(bitNo).append('|')
                .append(value).append('|')
                .append(ModbusSupport.b64url(tagName)).append('|')
                .append(ModbusSupport.b64url(itemName)).append('|')
                .append(ModbusSupport.b64url(panelName));
        }

        String body = "action=process_di" +
                "&plc_id=" + plcId +
                "&measured_at_ms=" + measuredAt.getTime() +
                "&rows=" + URLEncoder.encode(rows.toString(), StandardCharsets.UTF_8.name());
        return ModbusSupport.invokeAlarmApiPersist(alarmApiUrl, "process_di", body);
    }

    public static int[] persistAiRowsViaAlarmApi(String alarmApiUrl, int plcId, List<PlcAiReadRow> aiRows, Timestamp measuredAt) throws Exception {
        if (aiRows == null || aiRows.isEmpty()) {
            return new int[]{0, 0};
        }

        StringBuilder rows = new StringBuilder();
        for (PlcAiReadRow r : aiRows) {
            if (r == null || r.token == null) continue;
            int meterId = r.meterId;
            String token = r.token;
            double value = r.value;
            if (meterId <= 0 || token.trim().isEmpty()) continue;
            if (isAiMatchPlcOnlyToken(token)) continue;
            if (rows.length() > 0) rows.append(';');
            rows.append(meterId).append('|')
                .append(ModbusSupport.b64url(token)).append('|')
                .append(String.format(Locale.US, "%.6f", value));
        }
        if (rows.length() == 0) {
            return new int[]{0, 0};
        }

        String body = "action=process_ai" +
                "&plc_id=" + plcId +
                "&measured_at_ms=" + measuredAt.getTime() +
                "&rows=" + URLEncoder.encode(rows.toString(), StandardCharsets.UTF_8.name());
        return ModbusSupport.invokeAlarmApiPersist(alarmApiUrl, "process_ai", body);
    }

    private static boolean isAiMatchPlcOnlyToken(String token) {
        if (token == null) return false;
        String t = token.trim().toUpperCase(Locale.ROOT);
        return "IR".equals(t)
                || t.endsWith("_IR")
                || t.contains("INSULATION")
                || t.contains("PLC_ONLY");
    }
}
