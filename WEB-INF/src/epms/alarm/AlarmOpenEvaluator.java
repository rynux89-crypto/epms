package epms.alarm;

import java.util.Locale;

public final class AlarmOpenEvaluator {
    private AlarmOpenEvaluator() {
    }

    public static boolean evalOpen(String operator, Double threshold1, Double threshold2, double value) {
        String op = operator == null ? ">=" : operator.trim().toUpperCase(Locale.ROOT);
        if ("BETWEEN".equals(op)) {
            if (threshold1 == null || threshold2 == null) {
                return false;
            }
            double lo = Math.min(threshold1.doubleValue(), threshold2.doubleValue());
            double hi = Math.max(threshold1.doubleValue(), threshold2.doubleValue());
            return value >= lo && value <= hi;
        }
        if ("OUTSIDE".equals(op)) {
            if (threshold1 == null || threshold2 == null) {
                return false;
            }
            double lo = Math.min(threshold1.doubleValue(), threshold2.doubleValue());
            double hi = Math.max(threshold1.doubleValue(), threshold2.doubleValue());
            return value < lo || value > hi;
        }
        if (threshold1 == null) {
            return false;
        }
        double x = threshold1.doubleValue();
        if (">=".equals(op)) return value >= x;
        if (">".equals(op)) return value > x;
        if ("<=".equals(op)) return value <= x;
        if ("<".equals(op)) return value < x;
        if ("=".equals(op)) return value == x;
        if ("!=".equals(op) || "<>".equals(op)) return value != x;
        return false;
    }

    public static String evalStage(AlarmRuleDef rule, double value) {
        if (rule == null || rule.getThreshold1() == null) {
            return null;
        }
        String op = rule.getOperator() == null ? ">=" : rule.getOperator().trim().toUpperCase(Locale.ROOT);
        if (rule.getThreshold2() == null) {
            boolean hit = evalOpen(op, rule.getThreshold1(), null, value);
            if (!hit) {
                return null;
            }
            String severity = rule.getSeverity();
            return (severity == null || severity.trim().isEmpty())
                    ? "WARN"
                    : severity.trim().toUpperCase(Locale.ROOT);
        }
        double t1 = rule.getThreshold1().doubleValue();
        double t2 = rule.getThreshold2().doubleValue();
        if (">=".equals(op) || ">".equals(op)) {
            if (value >= t2) return "CRITICAL";
            if (value >= t1) return "ALARM";
            return null;
        }
        if ("<=".equals(op) || "<".equals(op)) {
            if (value <= t2) return "CRITICAL";
            if (value <= t1) return "ALARM";
            return null;
        }
        boolean hit = evalOpen(op, rule.getThreshold1(), rule.getThreshold2(), value);
        if (!hit) {
            return null;
        }
        String severity = rule.getSeverity();
        return (severity == null || severity.trim().isEmpty())
                ? "WARN"
                : severity.trim().toUpperCase(Locale.ROOT);
    }
}
