package epms.alarm;

import java.util.Objects;

/**
 * Key for open-alarm state tracking.
 */
public final class AlarmStateKey {
    private final int meterId;
    private final String alarmType;

    public AlarmStateKey(int meterId, String alarmType) {
        this.meterId = meterId;
        this.alarmType = alarmType == null ? "" : alarmType.trim();
    }

    public int getMeterId() {
        return meterId;
    }

    public String getAlarmType() {
        return alarmType;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof AlarmStateKey)) return false;
        AlarmStateKey that = (AlarmStateKey) o;
        return meterId == that.meterId && Objects.equals(alarmType, that.alarmType);
    }

    @Override
    public int hashCode() {
        return Objects.hash(meterId, alarmType);
    }

    @Override
    public String toString() {
        return meterId + ":" + alarmType;
    }
}
