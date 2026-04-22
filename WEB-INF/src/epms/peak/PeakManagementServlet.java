package epms.peak;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class PeakManagementServlet extends HttpServlet {
    private final PeakComputationService service = new PeakComputationService();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        req.setCharacterEncoding(StandardCharsets.UTF_8.name());
        String action = trimToNull(req.getParameter("action"));
        String redirectBase = req.getContextPath() + "/epms/peak_management.jsp";
        String floor = trimToNull(req.getParameter("floor"));
        String category = trimToNull(req.getParameter("category"));
        String status = trimToNull(req.getParameter("status"));
        try {
            if ("refresh_summary".equals(action)) {
                service.refreshPeakSummary(parsePositiveInt(req.getParameter("days_back"), 35));
                resp.sendRedirect(buildRedirectUrl(redirectBase, "msg", "15분 집계 데이터를 새로고침했습니다.", floor, category, status));
                return;
            }
            throw new IllegalArgumentException("Unsupported request.");
        } catch (Exception e) {
            resp.sendRedirect(buildRedirectUrl(redirectBase, "err", e.getMessage(), floor, category, status));
        }
    }

    private static int parsePositiveInt(String value, int defaultValue) {
        try {
            int parsed = Integer.parseInt(value);
            return parsed > 0 ? parsed : defaultValue;
        } catch (Exception ignore) {
            return defaultValue;
        }
    }

    private static String trimToNull(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String buildRedirectUrl(String base, String key, String value,
                                           String floor, String category, String status) {
        StringBuilder sb = new StringBuilder(base);
        boolean hasQuery = false;
        hasQuery = appendOptionalParam(sb, hasQuery, "floor", floor);
        hasQuery = appendOptionalParam(sb, hasQuery, "category", category);
        hasQuery = appendOptionalParam(sb, hasQuery, "status", status);
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
}
