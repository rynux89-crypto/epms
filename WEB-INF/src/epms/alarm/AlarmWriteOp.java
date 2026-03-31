package epms.alarm;

/**
 * Planned DB mutation for alarm/event persistence.
 *
 * <p>This is intentionally storage-agnostic so a future batch writer can
 * transform queued operations into JDBC batch executions.</p>
 */
public final class AlarmWriteOp {
    public enum Kind {
        OPEN_AI_ALARM,
        CLEAR_AI_ALARM,
        OPEN_DI_EVENT,
        CLOSE_DI_EVENT,
        OPEN_DI_ALARM,
        CLEAR_DI_ALARM
    }

    private final Kind kind;
    private final AlarmStateKey stateKey;
    private final String severity;
    private final String description;

    public AlarmWriteOp(Kind kind, AlarmStateKey stateKey, String severity, String description) {
        this.kind = kind;
        this.stateKey = stateKey;
        this.severity = severity;
        this.description = description;
    }

    public Kind getKind() {
        return kind;
    }

    public AlarmStateKey getStateKey() {
        return stateKey;
    }

    public String getSeverity() {
        return severity;
    }

    public String getDescription() {
        return description;
    }
}
