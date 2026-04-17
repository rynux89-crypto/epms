package epms.tenant;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class TenantMeterMapManageServlet extends HttpServlet {
    private final TenantMeterMapService meterMapService = new TenantMeterMapService();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        req.setCharacterEncoding(StandardCharsets.UTF_8.name());

        String action = trimToNull(req.getParameter("action"));
        String storeFilter = trimToNull(req.getParameter("filter_store_id"));
        String buildingFilter = trimToNull(req.getParameter("filter_building"));
        String redirectBase = req.getContextPath() + "/epms/tenant_meter_map_manage.jsp";

        Long mapId = parsePositiveLong(req.getParameter("map_id"));
        Integer storeId = parsePositiveInt(req.getParameter("store_id"));
        Integer meterId = parsePositiveInt(req.getParameter("meter_id"));
        String scope = trimToNull(req.getParameter("billing_scope"));
        Double ratio = parseNullableDouble(req.getParameter("allocation_ratio"));
        boolean isPrimary = parseBoolSafe(req.getParameter("is_primary"));
        Date validFrom = parseDateNullable(req.getParameter("valid_from"));
        Date validTo = parseDateNullable(req.getParameter("valid_to"));
        String notes = trimToNull(req.getParameter("notes"));

        try {
            Long redirectEditId = null;
            String message;
            if ("add".equals(action)) {
                redirectEditId = meterMapService.addMap(storeId, meterId, scope, ratio, isPrimary, validFrom, validTo, notes);
                message = "매장-계측기 연결을 등록했습니다.";
            } else if ("update".equals(action)) {
                meterMapService.updateMap(mapId, storeId, meterId, scope, ratio, isPrimary, validFrom, validTo, notes);
                redirectEditId = mapId;
                message = "매장-계측기 연결을 수정했습니다.";
            } else if ("delete".equals(action)) {
                meterMapService.deleteMap(mapId);
                message = "매장-계측기 연결을 삭제했습니다.";
            } else {
                throw new IllegalArgumentException("지원하지 않는 요청입니다.");
            }
            resp.sendRedirect(buildRedirectUrl(redirectBase, storeFilter, buildingFilter, redirectEditId, "msg", message));
        } catch (Exception e) {
            resp.sendRedirect(buildRedirectUrl(redirectBase, storeFilter, buildingFilter, mapId, "err", e.getMessage()));
        }
    }

    private static String buildRedirectUrl(String base, String storeFilter, String buildingFilter, Long editId, String msgKey, String msg) {
        StringBuilder sb = new StringBuilder(base);
        boolean hasQuery = false;
        if (storeFilter != null && !storeFilter.isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append("filter_store_id=").append(urlEncode(storeFilter));
            hasQuery = true;
        }
        if (buildingFilter != null && !buildingFilter.isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append("filter_building=").append(urlEncode(buildingFilter));
            hasQuery = true;
        }
        if (editId != null) {
            sb.append(hasQuery ? '&' : '?').append("edit_id=").append(urlEncode(String.valueOf(editId)));
            hasQuery = true;
        }
        if (msg != null && !msg.trim().isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append(msgKey).append('=').append(urlEncode(msg));
        }
        return sb.toString();
    }

    private static String trimToNull(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String urlEncode(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }

    private static Date parseDateNullable(String value) {
        if (value == null || value.trim().isEmpty()) return null;
        try {
            return Date.valueOf(value.trim());
        } catch (Exception ignore) {
            return null;
        }
    }

    private static Integer parsePositiveInt(String value) {
        try {
            Integer parsed = Integer.valueOf(value);
            return parsed.intValue() > 0 ? parsed : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    private static Long parsePositiveLong(String value) {
        try {
            Long parsed = Long.valueOf(value);
            return parsed.longValue() > 0L ? parsed : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    private static Double parseNullableDouble(String value) {
        if (value == null || value.trim().isEmpty()) return null;
        try {
            return Double.valueOf(value.trim());
        } catch (Exception ignore) {
            return null;
        }
    }

    private static boolean parseBoolSafe(String value) {
        return value != null && ("true".equalsIgnoreCase(value.trim()) || "1".equals(value.trim()) || "yes".equalsIgnoreCase(value.trim()) || "on".equalsIgnoreCase(value.trim()));
    }
}
