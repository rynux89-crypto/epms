package epms.plc;

import epms.util.ModbusSupport;
import java.sql.Timestamp;
import java.util.Locale;
import javax.servlet.http.HttpServletRequest;

public final class ModbusRequestSupport {
    public static final class ApiRequestContext {
        public String action;
        public String actionNorm;
        public Integer plcId;
    }

    private ModbusRequestSupport() {
    }

    public static ApiRequestContext buildApiRequestContext(HttpServletRequest req) {
        ApiRequestContext ctx = new ApiRequestContext();
        ctx.action = req.getParameter("action");
        String plcParam = req.getParameter("plc_id");
        try {
            if (plcParam != null && !plcParam.trim().isEmpty()) {
                ctx.plcId = Integer.valueOf(Integer.parseInt(plcParam.trim()));
            }
        } catch (Exception ignore) {
        }
        ctx.actionNorm = (ctx.action == null) ? "" : ctx.action.trim().toLowerCase(Locale.ROOT);
        return ctx;
    }

    public static void traceRequestIfNeeded(HttpServletRequest req, ApiRequestContext ctx) {
        boolean shouldTrace = "read".equals(ctx.actionNorm)
                || "start_polling".equals(ctx.actionNorm)
                || "stop_polling".equals(ctx.actionNorm);
        if (!shouldTrace) {
            return;
        }
        String remoteAddr = ModbusSupport.clipForLog(req.getRemoteAddr(), 64);
        String xff = ModbusSupport.clipForLog(req.getHeader("X-Forwarded-For"), 120);
        String ua = ModbusSupport.clipForLog(req.getHeader("User-Agent"), 220);
        String referer = ModbusSupport.clipForLog(req.getHeader("Referer"), 220);
        String query = ModbusSupport.clipForLog(req.getQueryString(), 220);
        String method = ModbusSupport.clipForLog(req.getMethod(), 10);
        System.out.println(
                "[modbus_api] ts=" + new Timestamp(System.currentTimeMillis()) +
                " action=" + ctx.actionNorm +
                " plc_id=" + (ctx.plcId == null ? "-" : String.valueOf(ctx.plcId)) +
                " method=" + method +
                " remote=" + remoteAddr +
                " xff=" + xff +
                " referer=" + referer +
                " ua=" + ua +
                " query=" + query
        );
    }
}
