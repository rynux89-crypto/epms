package epms.alarm;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * In-memory collector for future batched DB writes.
 *
 * <p>Current runtime still writes directly from JSP/JDBC, but this writer gives
 * us a concrete abstraction for the next migration step.</p>
 */
public final class AlarmBatchWriter {
    private final List<AlarmWriteOp> queue = new ArrayList<>();
    private int highWaterMark = 0;

    public synchronized void add(AlarmWriteOp op) {
        if (op != null) {
            queue.add(op);
            if (queue.size() > highWaterMark) {
                highWaterMark = queue.size();
            }
        }
    }

    public synchronized void addAll(List<AlarmWriteOp> ops) {
        if (ops == null || ops.isEmpty()) {
            return;
        }
        for (AlarmWriteOp op : ops) {
            if (op != null) {
                queue.add(op);
                if (queue.size() > highWaterMark) {
                    highWaterMark = queue.size();
                }
            }
        }
    }

    public synchronized List<AlarmWriteOp> drain() {
        List<AlarmWriteOp> out = new ArrayList<>(queue);
        queue.clear();
        return out;
    }

    public synchronized List<AlarmWriteOp> snapshot() {
        return Collections.unmodifiableList(new ArrayList<>(queue));
    }

    public synchronized int size() {
        return queue.size();
    }

    public synchronized void clear() {
        queue.clear();
    }

    public synchronized int getHighWaterMark() {
        return highWaterMark;
    }
}
