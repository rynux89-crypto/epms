package epms.alarm;

/**
 * Aggregated processing counters for batch-oriented alarm execution.
 */
public final class AlarmProcessingResult {
    private final int opened;
    private final int closed;
    private final int inspected;

    public AlarmProcessingResult(int opened, int closed, int inspected) {
        this.opened = opened;
        this.closed = closed;
        this.inspected = inspected;
    }

    public int getOpened() {
        return opened;
    }

    public int getClosed() {
        return closed;
    }

    public int getInspected() {
        return inspected;
    }

    public AlarmProcessingResult plus(AlarmProcessingResult other) {
        if (other == null) {
            return this;
        }
        return new AlarmProcessingResult(
                opened + other.opened,
                closed + other.closed,
                inspected + other.inspected
        );
    }
}
