package epms.util;

import java.sql.Timestamp;

public final class MeterStatusUtil {
    private MeterStatusUtil() {}

    public static double computeVoltageUnbalance(double an, double bn, double cn) {
        double avg = (an + bn + cn) / 3.0;
        if (Math.abs(avg) < 0.000001) return 0.0;
        double devA = Math.abs(an - avg);
        double devB = Math.abs(bn - avg);
        double devC = Math.abs(cn - avg);
        double maxDev = Math.max(devA, Math.max(devB, devC));
        return (maxDev / avg) * 100.0;
    }

    public static double computeCurrentUnbalance(double a, double b, double c) {
        double avg = (a + b + c) / 3.0;
        if (Math.abs(avg) < 0.000001) return 0.0;
        double devA = Math.abs(a - avg);
        double devB = Math.abs(b - avg);
        double devC = Math.abs(c - avg);
        double maxDev = Math.max(devA, Math.max(devB, devC));
        return (maxDev / avg) * 100.0;
    }

    public static double computeRepresentativeThd(double a, double b, double c) {
        return (a + b + c) / 3.0;
    }

    public static String formatFreshness(Timestamp measuredAt) {
        if (measuredAt == null) return "-";
        long diffMs = Math.max(0L, System.currentTimeMillis() - measuredAt.getTime());
        long seconds = diffMs / 1000L;
        if (seconds < 60L) return seconds + "\ucd08 \uc804";
        long minutes = seconds / 60L;
        if (minutes < 60L) return minutes + "\ubd84 \uc804";
        long hours = minutes / 60L;
        long remainMinutes = minutes % 60L;
        if (hours < 24L) {
            return remainMinutes > 0
                ? (hours + "\uc2dc\uac04 " + remainMinutes + "\ubd84 \uc804")
                : (hours + "\uc2dc\uac04 \uc804");
        }
        long days = hours / 24L;
        return days + "\uc77c \uc804";
    }

    public static String riskLevelForHigh(double value, double alarmThreshold, double criticalThreshold) {
        if (criticalThreshold > 0.0 && value >= criticalThreshold) return "CRITICAL";
        if (alarmThreshold > 0.0 && value >= alarmThreshold) return "ALARM";
        if (alarmThreshold > 0.0 && value >= alarmThreshold * 0.8) return "WATCH";
        return "NORMAL";
    }

    public static String riskLevelForOutside(double value, double low, double high) {
        if (high <= low) return "NORMAL";
        if (value < low || value > high) return "ALARM";
        double band = high - low;
        double margin = band * 0.1;
        if (value <= low + margin || value >= high - margin) return "WATCH";
        return "NORMAL";
    }

    public static int riskRank(String level) {
        if ("CRITICAL".equals(level)) return 3;
        if ("ALARM".equals(level)) return 2;
        if ("WATCH".equals(level)) return 1;
        return 0;
    }
}
