package epms.alarm;

import epms.alarm.AlarmApiModels.AiRequestPayload;
import epms.alarm.AlarmApiModels.AiRow;
import epms.alarm.AlarmApiModels.DiRequestPayload;
import epms.util.EpmsWebUtil;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.servlet.http.HttpServletRequest;

public final class AlarmApiRequestSupport {
    private AlarmApiRequestSupport() {
    }

    public static DiRequestPayload parseDiRequest(HttpServletRequest req) {
        DiRequestPayload payload = new DiRequestPayload();
        payload.plcId = EpmsWebUtil.parseIntSafe(req.getParameter("plc_id"), 0);
        long measuredAtMs = EpmsWebUtil.parseLongSafe(req.getParameter("measured_at_ms"), System.currentTimeMillis());
        payload.measuredAt = new Timestamp(measuredAtMs);
        payload.rows = parseRows(req.getParameter("rows"));
        return payload;
    }

    public static AiRequestPayload parseAiRequest(HttpServletRequest req) {
        AiRequestPayload payload = new AiRequestPayload();
        payload.plcId = EpmsWebUtil.parseIntSafe(req.getParameter("plc_id"), 0);
        long measuredAtMs = EpmsWebUtil.parseLongSafe(req.getParameter("measured_at_ms"), System.currentTimeMillis());
        payload.measuredAt = new Timestamp(measuredAtMs);
        payload.rows = parseAiRows(req.getParameter("rows"));
        return payload;
    }

    private static List<Map<String, Object>> parseRows(String raw) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (raw == null || raw.trim().isEmpty()) return out;
        String[] rows = raw.split(";");
        for (String line : rows) {
            if (line == null || line.trim().isEmpty()) continue;
            String[] p = line.split("\\|", -1);
            if (p.length < 7) continue;
            Map<String, Object> r = new HashMap<>();
            r.put("point_id", Integer.valueOf(EpmsWebUtil.parseIntSafe(p[0], 0)));
            r.put("di_address", Integer.valueOf(EpmsWebUtil.parseIntSafe(p[1], 0)));
            r.put("bit_no", Integer.valueOf(EpmsWebUtil.parseIntSafe(p[2], 0)));
            r.put("value", Integer.valueOf(EpmsWebUtil.parseIntSafe(p[3], 0)));
            r.put("tag_name", b64urlDecode(p[4]));
            r.put("item_name", b64urlDecode(p[5]));
            r.put("panel_name", b64urlDecode(p[6]));
            out.add(r);
        }
        return out;
    }

    private static List<AiRow> parseAiRows(String raw) {
        List<AiRow> out = new ArrayList<>();
        if (raw == null || raw.trim().isEmpty()) return out;
        String[] rows = raw.split(";");
        for (String line : rows) {
            if (line == null || line.trim().isEmpty()) continue;
            String[] p = line.split("\\|", -1);
            if (p.length < 3) continue;
            AiRow r = new AiRow();
            r.meterId = EpmsWebUtil.parseIntSafe(p[0], 0);
            r.token = b64urlDecode(p[1]);
            Double v = EpmsWebUtil.parseDoubleSafe(p[2]);
            if (r.meterId <= 0 || r.token == null || r.token.trim().isEmpty() || v == null) continue;
            r.value = v.doubleValue();
            out.add(r);
        }
        return out;
    }

    private static String b64urlDecode(String s) {
        if (s == null || s.isEmpty()) return "";
        try {
            int mod = s.length() % 4;
            if (mod == 2) s = s + "==";
            else if (mod == 3) s = s + "=";
            else if (mod == 1) return "";
            byte[] bytes = Base64.getUrlDecoder().decode(s);
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }
}
