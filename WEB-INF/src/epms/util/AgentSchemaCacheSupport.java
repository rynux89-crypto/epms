package epms.util;

public final class AgentSchemaCacheSupport {
    private static final Object SCHEMA_CACHE_LOCK = new Object();
    private static volatile String schemaContextCache = "";
    private static volatile long schemaContextCacheAt = 0L;
    private static volatile long schemaCacheTtlMs = 5L * 60L * 1000L;

    private AgentSchemaCacheSupport() {
    }

    public static void applySchemaCacheTtl(long nextTtlMs, long defaultTtlMs) {
        long effective = nextTtlMs > 0L ? nextTtlMs : defaultTtlMs;
        long prevTtlMs = schemaCacheTtlMs;
        schemaCacheTtlMs = effective;
        if (prevTtlMs != effective) {
            schemaContextCacheAt = 0L;
        }
    }

    public static String getSchemaContextCached(
            long defaultTtlMs,
            int maxTables,
            int maxColumnsPerTable,
            int maxChars) {
        long now = System.currentTimeMillis();
        long ttlMs = schemaCacheTtlMs > 0 ? schemaCacheTtlMs : defaultTtlMs;
        String cached = schemaContextCache;
        if (cached != null && !cached.isEmpty() && (now - schemaContextCacheAt) < ttlMs) {
            return cached;
        }
        synchronized (SCHEMA_CACHE_LOCK) {
            long now2 = System.currentTimeMillis();
            long ttlMs2 = schemaCacheTtlMs > 0 ? schemaCacheTtlMs : defaultTtlMs;
            if (schemaContextCache != null && !schemaContextCache.isEmpty() && (now2 - schemaContextCacheAt) < ttlMs2) {
                return schemaContextCache;
            }
            String fresh = AgentDbTools.buildSchemaContextFromDb(maxTables, maxColumnsPerTable, maxChars);
            schemaContextCache = fresh == null ? "" : fresh;
            schemaContextCacheAt = now2;
            return schemaContextCache;
        }
    }
}
