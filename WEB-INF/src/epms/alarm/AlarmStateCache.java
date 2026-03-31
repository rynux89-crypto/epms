package epms.alarm;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Lightweight in-memory cache for current open alarm state.
 *
 * <p>This cache is intended to reduce repetitive DB open-state lookups during
 * high-volume processing. DB remains the system of record.</p>
 */
public final class AlarmStateCache {
    private final ConcurrentHashMap<AlarmStateKey, AlarmOpenState> openStates = new ConcurrentHashMap<>();

    public AlarmOpenState get(AlarmStateKey key) {
        return key == null ? null : openStates.get(key);
    }

    public boolean isOpen(AlarmStateKey key) {
        return get(key) != null;
    }

    public boolean isOpenFresh(AlarmStateKey key, long nowMs, long maxAgeMs) {
        AlarmOpenState state = get(key);
        if (state == null) {
            return false;
        }
        if (maxAgeMs <= 0L) {
            return true;
        }
        if ((nowMs - state.getOpenedAtMs()) > maxAgeMs) {
            clear(key);
            return false;
        }
        return true;
    }

    public void putOpen(AlarmStateKey key, AlarmOpenState state) {
        if (key == null || state == null) {
            return;
        }
        openStates.put(key, state);
    }

    public void clear(AlarmStateKey key) {
        if (key == null) {
            return;
        }
        openStates.remove(key);
    }

    public int size() {
        return openStates.size();
    }

    public void clearAll() {
        openStates.clear();
    }

    public Map<AlarmStateKey, AlarmOpenState> snapshot() {
        return new ConcurrentHashMap<>(openStates);
    }
}
