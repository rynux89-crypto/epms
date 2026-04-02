package epms.plc;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class ModbusRuntimeCacheSupport {
    private static final long CACHE_TTL_MS = 30_000L;

    private interface Loader<T> {
        T load() throws Exception;
    }

    private ModbusRuntimeCacheSupport() {
    }

    public static PlcConfig getCachedPlcConfig(int plcId) throws Exception {
        return getCachedByIntKey(ModbusCacheSupport.<PlcConfig>plcConfigCache(), plcId, new Loader<PlcConfig>() {
            @Override
            public PlcConfig load() throws Exception {
                return ModbusConfigRepository.loadPlcConfig(plcId);
            }
        });
    }

    public static List<PlcAiMapEntry> getCachedAiMap(int plcId) throws Exception {
        return getCachedByIntKey(ModbusCacheSupport.<List<PlcAiMapEntry>>aiMapCache(), plcId, new Loader<List<PlcAiMapEntry>>() {
            @Override
            public List<PlcAiMapEntry> load() throws Exception {
                return ModbusConfigRepository.loadAiMap(plcId);
            }
        });
    }

    public static List<PlcDiTagEntry> getCachedDiTagMap(int plcId) throws Exception {
        return getCachedByIntKey(ModbusCacheSupport.<List<PlcDiTagEntry>>diTagCache(), plcId, new Loader<List<PlcDiTagEntry>>() {
            @Override
            public List<PlcDiTagEntry> load() throws Exception {
                return ModbusConfigRepository.loadDiTagMap(plcId);
            }
        });
    }

    public static Map<String, PlcAiMeasurementMatchEntry> getCachedAiMeasurementsMatch() throws Exception {
        return getCachedByStringKey(ModbusCacheSupport.<Map<String, PlcAiMeasurementMatchEntry>>aiMeasurementsMatchCache(), "GLOBAL", new Loader<Map<String, PlcAiMeasurementMatchEntry>>() {
            @Override
            public Map<String, PlcAiMeasurementMatchEntry> load() throws Exception {
                return ModbusConfigRepository.loadAiMeasurementsMatch();
            }
        });
    }

    private static boolean isCacheValid(ModbusCacheSupport.CacheEntry<?> ce) {
        return ce != null && (System.currentTimeMillis() - ce.loadedAtMs) < CACHE_TTL_MS;
    }

    private static <T> T getCachedByIntKey(
            ConcurrentHashMap<Integer, ModbusCacheSupport.CacheEntry<T>> cache,
            int key,
            Loader<T> loader) throws Exception {
        Integer cacheKey = Integer.valueOf(key);
        ModbusCacheSupport.CacheEntry<T> ce = cache.get(cacheKey);
        if (isCacheValid(ce)) {
            return ce.data;
        }
        synchronized (cache) {
            ce = cache.get(cacheKey);
            if (isCacheValid(ce)) {
                return ce.data;
            }
            T loaded = loader.load();
            cache.put(cacheKey, new ModbusCacheSupport.CacheEntry<T>(loaded));
            return loaded;
        }
    }

    private static <T> T getCachedByStringKey(
            ConcurrentHashMap<String, ModbusCacheSupport.CacheEntry<T>> cache,
            String key,
            Loader<T> loader) throws Exception {
        ModbusCacheSupport.CacheEntry<T> ce = cache.get(key);
        if (isCacheValid(ce)) {
            return ce.data;
        }
        synchronized (cache) {
            ce = cache.get(key);
            if (isCacheValid(ce)) {
                return ce.data;
            }
            T loaded = loader.load();
            cache.put(key, new ModbusCacheSupport.CacheEntry<T>(loaded));
            return loaded;
        }
    }
}
