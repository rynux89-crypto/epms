package epms.util;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;

public final class UpsFormatSupport {
    private UpsFormatSupport() {
    }

    public static Timestamp parseDateTime(String raw, boolean endOfMinute) {
        if (raw == null || raw.trim().isEmpty()) return null;
        String s = raw.trim().replace('T', ' ');
        if (s.length() == 16) s += endOfMinute ? ":59" : ":00";
        try {
            return Timestamp.valueOf(s);
        } catch (Exception ignore) {
            return null;
        }
    }

    public static String htmlDateTime(Calendar cal) {
        if (cal == null) return "";
        return String.format(Locale.US, "%04d-%02d-%02dT%02d:%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE));
    }

    public static String displayDateTime(Object value) {
        if (value == null) return "";
        if (value instanceof Timestamp) {
            return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format((Timestamp)value);
        }
        String s = String.valueOf(value).replace('T', ' ');
        return s.length() > 19 ? s.substring(0, 19) : s;
    }

    public static String displaySlashDateTime(Object value) {
        return displayDateTime(value).replace('-', '/');
    }

    public static String fmt(Object value, int scale) {
        if (value == null) return "";
        try {
            double v = value instanceof Number ? ((Number)value).doubleValue() : Double.parseDouble(String.valueOf(value));
            return String.format(Locale.US, "%,." + scale + "f", v);
        } catch (Exception ignore) {
            return String.valueOf(value);
        }
    }

    public static String fmtDash(Object value, int scale) {
        String s = fmt(value, scale);
        return s.isEmpty() ? "---" : s;
    }

    public static String alarmNumber(BigDecimal value) {
        if (value == null) return "";
        return value.setScale(1, RoundingMode.HALF_UP).toPlainString();
    }

    public static int intValue(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            if (value instanceof Number) return ((Number)value).intValue();
            return Integer.parseInt(String.valueOf(value).trim());
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static String upsModeLabel(Object value) {
        int code = intValue(value, -1);
        if (code == 2) return "\uC778\uBC84\uD130";
        if (code == 4) return "\uBC30\uD130\uB9AC";
        if (code == 5) return "\uBC14\uC774\uD328\uC2A4";
        if (code == 6) return "\uC815\uC9C0";
        if (code == 7) return "\uD14C\uC2A4\uD2B8";
        return code < 0 ? "" : String.valueOf(code);
    }

    public static String systemModeLabel(Object value) {
        int code = intValue(value, -1);
        if (code == 2) return "\uC778\uBC84\uD130";
        if (code == 4) return "\uBC30\uD130\uB9AC";
        if (code == 5) return "\uBC14\uC774\uD328\uC2A4";
        if (code == 6) return "\uC815\uC9C0";
        if (code == 8) return "\uC720\uC9C0\uBCF4\uC218";
        return code < 0 ? "" : String.valueOf(code);
    }

    public static String scenarioLabel(String scenario) {
        if ("normal".equals(scenario)) return "\uC815\uC0C1";
        if ("battery".equals(scenario)) return "\uBC30\uD130\uB9AC \uC6B4\uC804";
        if ("bypass".equals(scenario)) return "\uBC14\uC774\uD328\uC2A4 \uC6B4\uC804";
        if ("low_battery".equals(scenario)) return "\uBC30\uD130\uB9AC \uBD80\uC871";
        if ("overload".equals(scenario)) return "\uACFC\uBD80\uD558";
        if ("input_fault".equals(scenario)) return "\uC785\uB825 \uC774\uC0C1";
        if ("output_fault".equals(scenario)) return "\uCD9C\uB825 \uC774\uC0C1";
        if ("bypass_fault".equals(scenario)) return "\uBC14\uC774\uD328\uC2A4 \uC774\uC0C1";
        if ("power_module_fault".equals(scenario)) return "\uD30C\uC6CC \uBAA8\uB4C8 \uC774\uC0C1";
        if ("critical".equals(scenario)) return "\uC911\uC694 \uC54C\uB78C";
        return scenario == null ? "" : scenario;
    }

}
