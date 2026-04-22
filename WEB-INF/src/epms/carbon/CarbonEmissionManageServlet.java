package epms.carbon;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class CarbonEmissionManageServlet extends HttpServlet {
    private final CarbonEmissionService service = new CarbonEmissionService();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        req.setCharacterEncoding(StandardCharsets.UTF_8.name());
        String action = trimToEmpty(req.getParameter("action"));
        String building = trimToEmpty(req.getParameter("building"));
        String redirectBase = req.getContextPath() + "/epms/carbon_emissions.jsp";
        try {
            if ("recalc_scope".equals(action)) {
                service.refreshScope(building);
                resp.sendRedirect(buildRedirectUrl(redirectBase, building, "msg", "선택한 범위의 탄소배출량을 재집계했습니다."));
                return;
            }
            if ("recalc_all".equals(action)) {
                service.refreshAllScopes();
                resp.sendRedirect(buildRedirectUrl(redirectBase, building, "msg", "전체 건물 탄소배출량을 재집계했습니다."));
                return;
            }
            throw new IllegalArgumentException("Unsupported request.");
        } catch (Exception e) {
            resp.sendRedirect(buildRedirectUrl(redirectBase, building, "err", e.getMessage()));
        }
    }

    private static String buildRedirectUrl(String base, String building, String key, String value) {
        StringBuilder sb = new StringBuilder(base);
        boolean hasQuery = false;
        if (building != null && !building.trim().isEmpty()) {
            sb.append('?').append("building=").append(urlEncode(building));
            hasQuery = true;
        }
        if (value != null && !value.trim().isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append(key).append('=').append(urlEncode(value));
        }
        return sb.toString();
    }

    private static String trimToEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    private static String urlEncode(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }
}
