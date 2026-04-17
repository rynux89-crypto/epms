package epms.billing;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class BillingManageServlet extends HttpServlet {
    private final BillingService billingService = new BillingService();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        req.setCharacterEncoding(StandardCharsets.UTF_8.name());

        String action = trimToNull(req.getParameter("action"));
        String billingMonth = trimToNull(req.getParameter("billing_month"));
        String cycleFilter = trimToNull(req.getParameter("cycle_id"));
        String redirectBase = req.getContextPath() + "/epms/tenant_billing_manage.jsp";

        try {
            String message = null;
            Integer redirectCycleId = parsePositiveInt(req.getParameter("cycle_id"));

            if ("rate_add".equals(action)) {
                String rateCode = trimToNull(req.getParameter("rate_code"));
                String rateName = trimToNull(req.getParameter("rate_name"));
                Date effectiveFrom = parseDateNullable(req.getParameter("effective_from"));
                Double unitPrice = parseNullableDouble(req.getParameter("unit_price_per_kwh"));
                Double basicCharge = parseNullableDouble(req.getParameter("basic_charge_amount"));
                Double demandPrice = parseNullableDouble(req.getParameter("demand_unit_price"));
                message = billingService.addRate(rateCode, rateName, effectiveFrom, unitPrice, basicCharge, demandPrice);
            } else if ("rate_delete".equals(action)) {
                message = billingService.deleteRate(parsePositiveInt(req.getParameter("rate_id")));
            } else if ("contract_add".equals(action)) {
                Integer storeId = parsePositiveInt(req.getParameter("store_id"));
                Integer rateId = parsePositiveInt(req.getParameter("rate_id"));
                Date startDate = parseDateNullable(req.getParameter("contract_start_date"));
                Double demandKw = parseNullableDouble(req.getParameter("contracted_demand_kw"));
                message = billingService.addContract(storeId, rateId, startDate, demandKw);
            } else if ("contract_delete".equals(action)) {
                message = billingService.deleteContract(parsePositiveLong(req.getParameter("contract_id")));
            } else if ("cycle_delete".equals(action)) {
                message = billingService.deleteCycle(parsePositiveInt(req.getParameter("cycle_id")));
                redirectCycleId = null;
            } else if ("generate_snapshot".equals(action)) {
                String snapshotType = trimToNull(req.getParameter("snapshot_type"));
                redirectCycleId = billingService.ensureCycle(billingMonth, redirectCycleId);
                message = billingService.generateSnapshot(redirectCycleId, snapshotType);
            } else if ("generate_statement".equals(action)) {
                redirectCycleId = billingService.ensureCycle(billingMonth, redirectCycleId);
                message = billingService.generateStatement(redirectCycleId);
            } else if ("statement_status".equals(action)) {
                Long statementId = parsePositiveLong(req.getParameter("statement_id"));
                String statementStatus = trimToNull(req.getParameter("statement_status"));
                message = billingService.updateStatementStatus(statementId, statementStatus);
            } else {
                throw new IllegalArgumentException("지원하지 않는 요청입니다.");
            }

            resp.sendRedirect(buildRedirectUrl(redirectBase, billingMonth, redirectCycleId, "msg", message));
        } catch (Exception e) {
            resp.sendRedirect(buildRedirectUrl(redirectBase, billingMonth, redirectCycleIdOr(cycleFilter), "err", e.getMessage()));
        }
    }

    private static Integer redirectCycleIdOr(String raw) {
        return parsePositiveInt(raw);
    }

    private static String buildRedirectUrl(String base, String billingMonth, Integer cycleId, String messageKey, String message) {
        StringBuilder sb = new StringBuilder(base);
        boolean hasQuery = false;
        if (billingMonth != null && !billingMonth.trim().isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append("billing_month=").append(urlEncode(billingMonth));
            hasQuery = true;
        }
        if (cycleId != null) {
            sb.append(hasQuery ? '&' : '?').append("cycle_id=").append(urlEncode(String.valueOf(cycleId)));
            hasQuery = true;
        }
        if (message != null && !message.trim().isEmpty()) {
            sb.append(hasQuery ? '&' : '?').append(messageKey).append('=').append(urlEncode(message));
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
}
