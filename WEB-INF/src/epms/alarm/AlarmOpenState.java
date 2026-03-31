package epms.alarm;

/**
 * In-memory snapshot of an open alarm.
 */
public final class AlarmOpenState {
    private final long openedAtMs;
    private final String severity;
    private final Double measuredValue;

    public AlarmOpenState(long openedAtMs, String severity, Double measuredValue) {
        this.openedAtMs = openedAtMs;
        this.severity = severity;
        this.measuredValue = measuredValue;
    }

    public long getOpenedAtMs() {
        return openedAtMs;
    }

    public String getSeverity() {
        return severity;
    }

    public Double getMeasuredValue() {
        return measuredValue;
    }
}
