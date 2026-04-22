package epms.peak;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import java.util.ArrayList;
import java.util.List;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class PeakPolicyManageServlet extends HttpServlet {
    private final PeakPolicyService service = new PeakPolicyService();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        req.setCharacterEncoding(StandardCharsets.UTF_8.name());
        String action = trimToNull(req.getParameter("action"));
        String redirectBase = req.getContextPath() + "/epms/peak_policy_manage.jsp";
        String returnFloor = trimToNull(req.getParameter("return_floor"));
        String returnCategory = trimToNull(req.getParameter("return_category"));
        String returnStatus = trimToNull(req.getParameter("return_status"));
        String returnSection = trimToNull(req.getParameter("return_section"));
        boolean redirectToDashboard = parseBoolSafe(req.getParameter("redirect_to_dashboard"));
        Long policyId = parsePositiveLong(req.getParameter("policy_id"));
        Long redirectEditId = null;
        try {
            if ("add".equals(action)) {
                redirectEditId = service.addPolicy(
                        trimToNull(req.getParameter("policy_name")),
                        parseNullableDouble(req.getParameter("peak_limit_kw")),
                        parseNullableDouble(req.getParameter("warning_threshold_pct")),
                        parseNullableDouble(req.getParameter("control_threshold_pct")),
                        parsePositiveInt(req.getParameter("priority_level")),
                        parseBoolSafe(req.getParameter("control_enabled")),
                        parseDateNullable(req.getParameter("effective_from")),
                        parseDateNullable(req.getParameter("effective_to")),
                        trimToNull(req.getParameter("notes")),
                        parseStoreIds(req.getParameterValues("store_ids")));
                resp.sendRedirect(redirectToDashboard
                        ? buildDashboardRedirectUrl(req, "Peak policy has been added.", returnFloor, returnCategory, returnStatus, returnSection)
                        : buildRedirectUrl(redirectBase, redirectEditId, "msg", "Peak policy has been added.", returnFloor, returnCategory, returnStatus, returnSection));
                return;
            }
            if ("update".equals(action)) {
                service.updatePolicy(
                        policyId,
                        trimToNull(req.getParameter("policy_name")),
                        parseNullableDouble(req.getParameter("peak_limit_kw")),
                        parseNullableDouble(req.getParameter("warning_threshold_pct")),
                        parseNullableDouble(req.getParameter("control_threshold_pct")),
                        parsePositiveInt(req.getParameter("priority_level")),
                        parseBoolSafe(req.getParameter("control_enabled")),
                        parseDateNullable(req.getParameter("effective_from")),
                        parseDateNullable(req.getParameter("effective_to")),
                        trimToNull(req.getParameter("notes")),
                        parseStoreIds(req.getParameterValues("store_ids")));
                resp.sendRedirect(redirectToDashboard
                        ? buildDashboardRedirectUrl(req, "Peak policy has been updated.", returnFloor, returnCategory, returnStatus, returnSection)
                        : buildRedirectUrl(redirectBase, policyId, "msg", "Peak policy has been updated.", returnFloor, returnCategory, returnStatus, returnSection));
                return;
            }
            if ("delete".equals(action)) {
                service.deletePolicy(policyId);
                resp.sendRedirect(buildRedirectUrl(redirectBase, null, "msg", "Peak policy has been deleted.", returnFloor, returnCategory, returnStatus, returnSection));
                return;
            }
            throw new IllegalArgumentException("Unsupported request.");
        } catch (Exception e) {
            resp.sendRedirect(buildRedirectUrl(redirectBase, policyId, "err", e.getMessage(), returnFloor, returnCategory, returnStatus, returnSection));
        }
    }

    private static List<Integer> parseStoreIds(String[] values) {
        List<Integer> rows = new ArrayList<Integer>();
        if (values == null) return rows;
        for (String value : values) {
            Integer storeId = parsePositiveInt(value);
            if (storeId != null) rows.add(storeId);
        }
        return rows;
    }

    private static String buildDashboardRedirectUrl(HttpServletRequest req, String message,
                                                    String returnFloor, String returnCategory,
                                                    String returnStatus, String returnSection) {
        StringBuilder sb = new StringBuilder(req.getContextPath()).append("/epms/peak_management.jsp");
        boolean hasQuery = false;
        hasQuery = appendOptionalParam(sb, hasQuery, "floor", returnFloor);
        hasQuery = appendOptionalParam(sb, hasQuery, "category", returnCategory);
        hasQuery = appendOptionalParam(sb, hasQuery, "status", returnStatus);
        hasQuery = appendOptionalParam(sb, hasQuery, "msg", message);
        if (returnSection != null && !returnSection.trim().isEmpty()) {
            sb.append('#').append(urlEncode(returnSection));
        }
        return sb.toString();
    }

    private static String buildRedirectUrl(String base, Long editId, String key, String value,
                                           String returnFloor, String returnCategory, String returnStatus,
                                           String returnSection) {
        StringBuilder sb = new StringBuilder(base);
        boolean hasQuery = false;
        if (editId != null) {
            sb.append(hasQuery ? '&' : '?').append("edit_id=").append(urlEncode(String.valueOf(editId)));
            hasQuery = true;
        }
        hasQuery = appendOptionalParam(sb, hasQuery, "return_floor", returnFloor);
        hasQuery = appendOptionalParam(sb, hasQuery, "return_category", returnCategory);
        hasQuery = appendOptionalParam(sb, hasQuery, "return_status", returnStatus);
        hasQuery = appendOptionalParam(sb, hasQuery, "return_section", returnSection);
        if (value != null && !value.trim().isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append(key).append('=').append(urlEncode(value));
        }
        return sb.toString();
    }

    private static boolean appendOptionalParam(StringBuilder sb, boolean hasQuery, String key, String value) {
        if (value == null || value.trim().isEmpty()) return hasQuery;
        sb.append(hasQuery ? '&' : '?').append(key).append('=').append(urlEncode(value));
        return true;
    }

    private static String urlEncode(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }

    private static String trimToNull(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
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

    private static Date parseDateNullable(String value) {
        if (value == null || value.trim().isEmpty()) return null;
        try {
            return Date.valueOf(value.trim());
        } catch (Exception ignore) {
            return null;
        }
    }

    private static boolean parseBoolSafe(String value) {
        return value != null
                && ("true".equalsIgnoreCase(value.trim())
                || "1".equals(value.trim())
                || "yes".equalsIgnoreCase(value.trim())
                || "on".equalsIgnoreCase(value.trim()));
    }
}
