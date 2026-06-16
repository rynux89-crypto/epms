package epms.util;

import java.sql.Timestamp;
import java.util.Calendar;
import javax.servlet.http.HttpServletRequest;

public final class UpsDateRangeSupport {
    private UpsDateRangeSupport() {
    }

    public static DateRange lastDays(HttpServletRequest request, int days) {
        String fromRaw = request == null ? null : request.getParameter("from");
        String toRaw = request == null ? null : request.getParameter("to");
        boolean explicitTo = !blank(toRaw);

        Calendar nowCal = Calendar.getInstance();
        String defaultTo = UpsFormatSupport.htmlDateTime(nowCal);
        Calendar fromCal = (Calendar) nowCal.clone();
        fromCal.add(Calendar.DAY_OF_MONTH, -Math.max(1, days));
        String defaultFrom = UpsFormatSupport.htmlDateTime(fromCal);

        if (blank(fromRaw)) fromRaw = defaultFrom;
        if (blank(toRaw)) toRaw = defaultTo;

        return new DateRange(
                fromRaw,
                toRaw,
                explicitTo,
                UpsFormatSupport.parseDateTime(fromRaw, false),
                UpsFormatSupport.parseDateTime(toRaw, true));
    }

    private static boolean blank(String value) {
        return value == null || value.trim().isEmpty();
    }

    public static final class DateRange {
        public final String fromRaw;
        public final String toRaw;
        public final boolean explicitTo;
        public final Timestamp fromTs;
        public final Timestamp toTs;

        private DateRange(String fromRaw, String toRaw, boolean explicitTo, Timestamp fromTs, Timestamp toTs) {
            this.fromRaw = fromRaw;
            this.toRaw = toRaw;
            this.explicitTo = explicitTo;
            this.fromTs = fromTs;
            this.toTs = toTs;
        }
    }
}
