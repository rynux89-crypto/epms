package epms.alarm;

import java.sql.Connection;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * TTL cache for enabled AI alarm rules.
 */
public final class AlarmRuleCache {
    private volatile List<AlarmRuleDef> cachedAiRules = Collections.emptyList();
    private volatile long loadedAtMs = 0L;
    private final long ttlMs;

    public AlarmRuleCache(long ttlMs) {
        this.ttlMs = Math.max(0L, ttlMs);
    }

    public List<AlarmRuleDef> getAiRules(Connection conn) throws Exception {
        long now = System.currentTimeMillis();
        if (!cachedAiRules.isEmpty() && (ttlMs <= 0L || (now - loadedAtMs) < ttlMs)) {
            return cachedAiRules;
        }
        synchronized (this) {
            now = System.currentTimeMillis();
            if (!cachedAiRules.isEmpty() && (ttlMs <= 0L || (now - loadedAtMs) < ttlMs)) {
                return cachedAiRules;
            }
            List<AlarmRuleDef> loaded = AlarmRuleRepository.loadEnabledAiRuleDefs(conn);
            cachedAiRules = Collections.unmodifiableList(new ArrayList<>(loaded));
            loadedAtMs = now;
            return cachedAiRules;
        }
    }

    public void invalidate() {
        cachedAiRules = Collections.emptyList();
        loadedAtMs = 0L;
    }

    public int size() {
        return cachedAiRules.size();
    }
}
