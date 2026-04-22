package epms.tenant;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class TenantStoreManageServlet extends HttpServlet {
    private final TenantStoreService storeService = new TenantStoreService();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        req.setCharacterEncoding(StandardCharsets.UTF_8.name());

        String action = trimToNull(req.getParameter("action"));
        String deleteMode = trimToNull(req.getParameter("delete_mode"));
        String searchQ = trimToNull(req.getParameter("q"));
        String statusQ = trimToNull(req.getParameter("status"));
        Integer requestedEditId = parsePositiveInt(req.getParameter("edit_id"));
        String redirectBase = req.getContextPath() + "/epms/tenant_store_manage.jsp";

        Integer storeId = parsePositiveInt(req.getParameter("store_id"));
        String storeCode = trimToNull(req.getParameter("store_code"));
        String storeName = trimToNull(req.getParameter("store_name"));
        String businessNumber = trimToNull(req.getParameter("business_number"));
        String floorName = trimToNull(req.getParameter("floor_name"));
        String roomName = trimToNull(req.getParameter("room_name"));
        String zoneName = trimToNull(req.getParameter("zone_name"));
        String categoryName = trimToNull(req.getParameter("category_name"));
        String contactName = trimToNull(req.getParameter("contact_name"));
        String contactPhone = trimToNull(req.getParameter("contact_phone"));
        String status = trimToNull(req.getParameter("store_status"));
        Date openedOn = parseDateNullable(req.getParameter("opened_on"));
        Date closedOn = parseDateNullable(req.getParameter("closed_on"));
        String notes = trimToNull(req.getParameter("notes"));

        try {
            String message;
            Integer redirectEditId = null;
            if ("add".equals(action)) {
                message = storeService.addStore(storeCode, storeName, businessNumber, floorName, roomName, zoneName,
                        categoryName, contactName, contactPhone, status, openedOn, closedOn, notes);
            } else if ("update".equals(action)) {
                message = storeService.updateStore(storeId, storeCode, storeName, businessNumber, floorName, roomName, zoneName,
                        categoryName, contactName, contactPhone, status, openedOn, closedOn, notes);
                redirectEditId = storeId;
            } else if ("delete".equals(action)) {
                if ("cascade".equalsIgnoreCase(deleteMode)) {
                    message = storeService.deleteStoreCascade(storeId);
                } else if ("disable".equalsIgnoreCase(deleteMode)) {
                    message = storeService.disableStore(storeId);
                    redirectEditId = requestedEditId;
                } else {
                    message = storeService.deleteStore(storeId);
                }
            } else {
                throw new IllegalArgumentException("지원하지 않는 요청입니다.");
            }
            resp.sendRedirect(buildRedirectUrl(redirectBase, searchQ, statusQ, redirectEditId, "msg", message));
        } catch (Exception e) {
            resp.sendRedirect(buildRedirectUrl(redirectBase, searchQ, statusQ, storeId, "err", e.getMessage()));
        }
    }

    private static String buildRedirectUrl(String base, String searchQ, String statusQ, Integer editId, String msgKey, String msg) {
        StringBuilder sb = new StringBuilder(base);
        boolean hasQuery = false;
        if (searchQ != null && !searchQ.isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append("q=").append(urlEncode(searchQ));
            hasQuery = true;
        }
        if (statusQ != null && !statusQ.isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append("status=").append(urlEncode(statusQ));
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
}
