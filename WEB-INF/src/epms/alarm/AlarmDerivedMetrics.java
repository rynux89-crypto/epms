package epms.alarm;

public final class AlarmDerivedMetrics {
    private AlarmDerivedMetrics() {
    }

    public static Double computeUnbalancePercent(Double a, Double b, Double c) {
        if (a == null || b == null || c == null) {
            return null;
        }
        double avg = (a.doubleValue() + b.doubleValue() + c.doubleValue()) / 3.0;
        if (Math.abs(avg) < 0.000001d) {
            return null;
        }
        double d1 = Math.abs(a.doubleValue() - avg);
        double d2 = Math.abs(b.doubleValue() - avg);
        double d3 = Math.abs(c.doubleValue() - avg);
        double max = Math.max(d1, Math.max(d2, d3));
        return Double.valueOf((max / Math.abs(avg)) * 100.0d);
    }

    public static Double computeVariationPercent(Double previous, Double current) {
        if (previous == null || current == null) {
            return null;
        }
        double prev = previous.doubleValue();
        if (Math.abs(prev) < 0.000001d) {
            return null;
        }
        return Double.valueOf((Math.abs(current.doubleValue() - prev) / Math.abs(prev)) * 100.0d);
    }
}
