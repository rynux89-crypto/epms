package epms.plc;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicReference;

public final class ModbusCacheSupport {
    public static final class CacheEntry<T> {
        public final T data;
        public final long loadedAtMs;

        public CacheEntry(T data) {
            this.data = data;
            this.loadedAtMs = System.currentTimeMillis();
        }
    }

    private static final ConcurrentHashMap<Integer, CacheEntry<Object>> PLC_CONFIG_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Integer, CacheEntry<Object>> AI_MAP_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Integer, CacheEntry<Object>> DI_MAP_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Integer, CacheEntry<Object>> DI_TAG_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, CacheEntry<Object>> AI_MEAS_MATCH_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, CacheEntry<Object>> DI_RULE_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Integer> LAST_DI_VALUE_MAP = new ConcurrentHashMap<>();
    private static final AtomicReference<Boolean> ALARM_LOG_RULE_COLUMNS_OK = new AtomicReference<Boolean>(null);

    private ModbusCacheSupport() {
    }

    @SuppressWarnings("unchecked")
    public static <T> ConcurrentHashMap<Integer, CacheEntry<T>> plcConfigCache() {
        return (ConcurrentHashMap<Integer, CacheEntry<T>>) (ConcurrentHashMap<?, ?>) PLC_CONFIG_CACHE;
    }

    @SuppressWarnings("unchecked")
    public static <T> ConcurrentHashMap<Integer, CacheEntry<T>> aiMapCache() {
        return (ConcurrentHashMap<Integer, CacheEntry<T>>) (ConcurrentHashMap<?, ?>) AI_MAP_CACHE;
    }

    @SuppressWarnings("unchecked")
    public static <T> ConcurrentHashMap<Integer, CacheEntry<T>> diMapCache() {
        return (ConcurrentHashMap<Integer, CacheEntry<T>>) (ConcurrentHashMap<?, ?>) DI_MAP_CACHE;
    }

    @SuppressWarnings("unchecked")
    public static <T> ConcurrentHashMap<Integer, CacheEntry<T>> diTagCache() {
        return (ConcurrentHashMap<Integer, CacheEntry<T>>) (ConcurrentHashMap<?, ?>) DI_TAG_CACHE;
    }

    @SuppressWarnings("unchecked")
    public static <T> ConcurrentHashMap<String, CacheEntry<T>> aiMeasurementsMatchCache() {
        return (ConcurrentHashMap<String, CacheEntry<T>>) (ConcurrentHashMap<?, ?>) AI_MEAS_MATCH_CACHE;
    }

    @SuppressWarnings("unchecked")
    public static <T> ConcurrentHashMap<String, CacheEntry<T>> diRuleCache() {
        return (ConcurrentHashMap<String, CacheEntry<T>>) (ConcurrentHashMap<?, ?>) DI_RULE_CACHE;
    }

    public static ConcurrentHashMap<String, Integer> lastDiValueMap() {
        return LAST_DI_VALUE_MAP;
    }

    public static AtomicReference<Boolean> alarmLogRuleColumnsOkRef() {
        return ALARM_LOG_RULE_COLUMNS_OK;
    }

    public static void clearCaches(Integer plcId) {
        if (plcId == null) {
            PLC_CONFIG_CACHE.clear();
            AI_MAP_CACHE.clear();
            DI_MAP_CACHE.clear();
            DI_TAG_CACHE.clear();
            AI_MEAS_MATCH_CACHE.clear();
            DI_RULE_CACHE.clear();
            LAST_DI_VALUE_MAP.clear();
            ALARM_LOG_RULE_COLUMNS_OK.set(null);
            return;
        }

        PLC_CONFIG_CACHE.remove(plcId);
        AI_MAP_CACHE.remove(plcId);
        DI_MAP_CACHE.remove(plcId);
        DI_TAG_CACHE.remove(plcId);

        String prefix = plcId + ":";
        for (String k : LAST_DI_VALUE_MAP.keySet()) {
            if (k != null && k.startsWith(prefix)) {
                LAST_DI_VALUE_MAP.remove(k);
            }
        }
    }
}
