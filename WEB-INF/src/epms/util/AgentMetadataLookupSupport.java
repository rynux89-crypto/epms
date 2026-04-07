package epms.util;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

public final class AgentMetadataLookupSupport {
    private static final Object METER_SCOPE_CACHE_LOCK = new Object();
    private static final Object USAGE_TYPE_CACHE_LOCK = new Object();
    private static final Object USAGE_ALIAS_CACHE_LOCK = new Object();
    private static final Object BUILDING_NAME_CACHE_LOCK = new Object();
    private static final Object BUILDING_ALIAS_CACHE_LOCK = new Object();
    private static final long DEFAULT_CACHE_TTL_MS = 5L * 60L * 1000L;

    private static volatile List<String> meterScopeValueCache = new ArrayList<String>();
    private static volatile List<String> usageTypeValueCache = new ArrayList<String>();
    private static volatile Map<String, String> usageAliasMapCache = new LinkedHashMap<String, String>();
    private static volatile List<String> buildingNameValueCache = new ArrayList<String>();
    private static volatile Map<String, String> buildingAliasMapCache = new LinkedHashMap<String, String>();
    private static volatile long meterScopeCacheAt = 0L;
    private static volatile long usageTypeCacheAt = 0L;
    private static volatile long usageAliasCacheAt = 0L;
    private static volatile long buildingNameCacheAt = 0L;
    private static volatile long buildingAliasCacheAt = 0L;

    private AgentMetadataLookupSupport() {
    }

    public static List<String> findScopeTokensFromMeterMaster(String userMessage, int maxTokens) {
        ArrayList<String> out = new ArrayList<String>();
        String msg = normalizeScopeKey(userMessage);
        if (msg.isEmpty()) return out;
        List<String> master = getMeterScopeValuesCached();
        if (master == null || master.isEmpty()) return out;
        LinkedHashSet<String> uniq = new LinkedHashSet<String>();
        for (String value : master) {
            String normalized = normalizeScopeKey(value);
            if (normalized.length() < 2) continue;
            if (msg.contains(normalized)) {
                uniq.add(value);
                if (uniq.size() >= maxTokens) break;
            }
        }
        out.addAll(uniq);
        return out;
    }

    public static String findUsageTypeFromDb(String userMessage) {
        String msg = normalizeScopeKey(userMessage);
        if (msg.isEmpty()) return null;
        List<String> values = getUsageTypeValuesCached();
        if (values == null || values.isEmpty()) return null;
        for (String value : values) {
            String normalized = normalizeScopeKey(value);
            if (normalized.length() < 2) continue;
            if (msg.contains(normalized)) return value;
        }
        return null;
    }

    public static String findUsageAliasFromDb(String userMessage) {
        String msg = normalizeScopeKey(userMessage);
        if (msg.isEmpty()) return null;
        Map<String, String> aliasMap = getUsageAliasMapCached();
        if (aliasMap == null || aliasMap.isEmpty()) return null;
        String bestUsage = null;
        int bestLen = -1;
        for (Map.Entry<String, String> entry : aliasMap.entrySet()) {
            String alias = entry.getKey();
            if (alias == null || alias.length() < 2) continue;
            if (msg.contains(alias) && alias.length() > bestLen) {
                bestUsage = entry.getValue();
                bestLen = alias.length();
            }
        }
        return EpmsWebUtil.trimToNull(bestUsage);
    }

    public static String findBuildingNameFromDb(String userMessage) {
        String msg = normalizeScopeKey(userMessage);
        if (msg.isEmpty()) return null;
        List<String> values = getBuildingNameValuesCached();
        if (values == null || values.isEmpty()) return null;
        for (String value : values) {
            String normalized = normalizeScopeKey(value);
            if (normalized.length() < 2) continue;
            if (msg.contains(normalized)) return value;
        }
        return null;
    }

    public static String findBuildingAliasFromDb(String userMessage) {
        String msg = normalizeScopeKey(userMessage);
        if (msg.isEmpty()) return null;
        Map<String, String> aliasMap = getBuildingAliasMapCached();
        if (aliasMap == null || aliasMap.isEmpty()) return null;
        String bestBuilding = null;
        int bestLen = -1;
        for (Map.Entry<String, String> entry : aliasMap.entrySet()) {
            String alias = entry.getKey();
            if (alias == null || alias.length() < 2) continue;
            if (msg.contains(alias) && alias.length() > bestLen) {
                bestBuilding = entry.getValue();
                bestLen = alias.length();
            }
        }
        return EpmsWebUtil.trimToNull(bestBuilding);
    }

    private static List<String> buildMeterScopeValuesFromDb() {
        LinkedHashSet<String> set = new LinkedHashSet<String>();
        String sql =
            "SELECT DISTINCT LTRIM(RTRIM(v)) AS v " +
            "FROM (" +
            "  SELECT building_name AS v FROM dbo.meters WHERE building_name IS NOT NULL " +
            "  UNION ALL " +
            "  SELECT usage_type AS v FROM dbo.meters WHERE usage_type IS NOT NULL " +
            ") t " +
            "WHERE LTRIM(RTRIM(v)) <> ''";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String value = EpmsWebUtil.trimToNull(rs.getString("v"));
                    if (value == null) continue;
                    if (normalizeScopeKey(value).length() < 2) continue;
                    set.add(value);
                }
            }
        } catch (Exception ignore) {
        }
        return sortByNormalizedLength(set);
    }

    private static List<String> getMeterScopeValuesCached() {
        long now = System.currentTimeMillis();
        List<String> cached = meterScopeValueCache;
        if (cached != null && !cached.isEmpty() && (now - meterScopeCacheAt) < DEFAULT_CACHE_TTL_MS) {
            return cached;
        }
        synchronized (METER_SCOPE_CACHE_LOCK) {
            long now2 = System.currentTimeMillis();
            if (meterScopeValueCache != null && !meterScopeValueCache.isEmpty() && (now2 - meterScopeCacheAt) < DEFAULT_CACHE_TTL_MS) {
                return meterScopeValueCache;
            }
            List<String> fresh = buildMeterScopeValuesFromDb();
            meterScopeValueCache = fresh == null ? new ArrayList<String>() : fresh;
            meterScopeCacheAt = now2;
            return meterScopeValueCache;
        }
    }

    private static List<String> buildUsageTypeValuesFromDb() {
        LinkedHashSet<String> set = new LinkedHashSet<String>();
        String sql =
            "SELECT DISTINCT LTRIM(RTRIM(ISNULL(usage_type,''))) AS usage_type " +
            "FROM dbo.meters " +
            "WHERE LTRIM(RTRIM(ISNULL(usage_type,''))) <> ''";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String value = EpmsWebUtil.trimToNull(rs.getString("usage_type"));
                    if (value == null) continue;
                    if (normalizeScopeKey(value).length() < 2) continue;
                    set.add(value);
                }
            }
        } catch (Exception ignore) {
        }
        return sortByNormalizedLength(set);
    }

    private static List<String> getUsageTypeValuesCached() {
        long now = System.currentTimeMillis();
        List<String> cached = usageTypeValueCache;
        if (cached != null && !cached.isEmpty() && (now - usageTypeCacheAt) < DEFAULT_CACHE_TTL_MS) {
            return cached;
        }
        synchronized (USAGE_TYPE_CACHE_LOCK) {
            long now2 = System.currentTimeMillis();
            if (usageTypeValueCache != null && !usageTypeValueCache.isEmpty() && (now2 - usageTypeCacheAt) < DEFAULT_CACHE_TTL_MS) {
                return usageTypeValueCache;
            }
            List<String> fresh = buildUsageTypeValuesFromDb();
            usageTypeValueCache = fresh == null ? new ArrayList<String>() : fresh;
            usageTypeCacheAt = now2;
            return usageTypeValueCache;
        }
    }

    private static Map<String, String> buildUsageAliasMapFromDb() {
        LinkedHashMap<String, String> out = new LinkedHashMap<String, String>();
        String sql =
            "SELECT LTRIM(RTRIM(ISNULL(alias_keyword,''))) AS alias_keyword, " +
            "       LTRIM(RTRIM(ISNULL(usage_type,''))) AS usage_type " +
            "FROM dbo.usage_type_alias " +
            "WHERE LTRIM(RTRIM(ISNULL(alias_keyword,''))) <> '' " +
            "  AND LTRIM(RTRIM(ISNULL(usage_type,''))) <> '' " +
            "  AND ISNULL(is_active, 1) = 1";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String alias = EpmsWebUtil.trimToNull(rs.getString("alias_keyword"));
                    String usageType = EpmsWebUtil.trimToNull(rs.getString("usage_type"));
                    if (alias == null || usageType == null) continue;
                    String key = normalizeScopeKey(alias);
                    if (key.length() < 2) continue;
                    out.put(key, usageType);
                }
            }
        } catch (Exception ignore) {
        }
        return out;
    }

    private static Map<String, String> getUsageAliasMapCached() {
        long now = System.currentTimeMillis();
        Map<String, String> cached = usageAliasMapCache;
        if (cached != null && !cached.isEmpty() && (now - usageAliasCacheAt) < DEFAULT_CACHE_TTL_MS) {
            return cached;
        }
        synchronized (USAGE_ALIAS_CACHE_LOCK) {
            long now2 = System.currentTimeMillis();
            if (usageAliasMapCache != null && !usageAliasMapCache.isEmpty() && (now2 - usageAliasCacheAt) < DEFAULT_CACHE_TTL_MS) {
                return usageAliasMapCache;
            }
            Map<String, String> fresh = buildUsageAliasMapFromDb();
            usageAliasMapCache = fresh == null ? new LinkedHashMap<String, String>() : fresh;
            usageAliasCacheAt = now2;
            return usageAliasMapCache;
        }
    }

    private static List<String> buildBuildingNameValuesFromDb() {
        LinkedHashSet<String> set = new LinkedHashSet<String>();
        String sql =
            "SELECT DISTINCT LTRIM(RTRIM(ISNULL(building_name,''))) AS building_name " +
            "FROM dbo.meters " +
            "WHERE LTRIM(RTRIM(ISNULL(building_name,''))) <> ''";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String value = EpmsWebUtil.trimToNull(rs.getString("building_name"));
                    if (value == null) continue;
                    if (normalizeScopeKey(value).length() < 2) continue;
                    set.add(value);
                }
            }
        } catch (Exception ignore) {
        }
        return sortByNormalizedLength(set);
    }

    private static List<String> getBuildingNameValuesCached() {
        long now = System.currentTimeMillis();
        List<String> cached = buildingNameValueCache;
        if (cached != null && !cached.isEmpty() && (now - buildingNameCacheAt) < DEFAULT_CACHE_TTL_MS) {
            return cached;
        }
        synchronized (BUILDING_NAME_CACHE_LOCK) {
            long now2 = System.currentTimeMillis();
            if (buildingNameValueCache != null && !buildingNameValueCache.isEmpty() && (now2 - buildingNameCacheAt) < DEFAULT_CACHE_TTL_MS) {
                return buildingNameValueCache;
            }
            List<String> fresh = buildBuildingNameValuesFromDb();
            buildingNameValueCache = fresh == null ? new ArrayList<String>() : fresh;
            buildingNameCacheAt = now2;
            return buildingNameValueCache;
        }
    }

    private static Map<String, String> buildBuildingAliasMapFromDb() {
        LinkedHashMap<String, String> out = new LinkedHashMap<String, String>();
        String sql =
            "SELECT LTRIM(RTRIM(ISNULL(alias_keyword,''))) AS alias_keyword, " +
            "       LTRIM(RTRIM(ISNULL(building_name,''))) AS building_name " +
            "FROM dbo.building_alias " +
            "WHERE LTRIM(RTRIM(ISNULL(alias_keyword,''))) <> '' " +
            "  AND LTRIM(RTRIM(ISNULL(building_name,''))) <> '' " +
            "  AND ISNULL(is_active, 1) = 1";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String alias = EpmsWebUtil.trimToNull(rs.getString("alias_keyword"));
                    String building = EpmsWebUtil.trimToNull(rs.getString("building_name"));
                    if (alias == null || building == null) continue;
                    String key = normalizeScopeKey(alias);
                    if (key.length() < 2) continue;
                    out.put(key, building);
                }
            }
        } catch (Exception ignore) {
        }
        return out;
    }

    private static Map<String, String> getBuildingAliasMapCached() {
        long now = System.currentTimeMillis();
        Map<String, String> cached = buildingAliasMapCache;
        if (cached != null && !cached.isEmpty() && (now - buildingAliasCacheAt) < DEFAULT_CACHE_TTL_MS) {
            return cached;
        }
        synchronized (BUILDING_ALIAS_CACHE_LOCK) {
            long now2 = System.currentTimeMillis();
            if (buildingAliasMapCache != null && !buildingAliasMapCache.isEmpty() && (now2 - buildingAliasCacheAt) < DEFAULT_CACHE_TTL_MS) {
                return buildingAliasMapCache;
            }
            Map<String, String> fresh = buildBuildingAliasMapFromDb();
            buildingAliasMapCache = fresh == null ? new LinkedHashMap<String, String>() : fresh;
            buildingAliasCacheAt = now2;
            return buildingAliasMapCache;
        }
    }

    private static List<String> sortByNormalizedLength(LinkedHashSet<String> values) {
        ArrayList<String> out = new ArrayList<String>(values);
        Collections.sort(out, new Comparator<String>() {
            @Override
            public int compare(String a, String b) {
                int la = normalizeScopeKey(a).length();
                int lb = normalizeScopeKey(b).length();
                if (la != lb) return lb - la;
                return a.compareToIgnoreCase(b);
            }
        });
        return out;
    }

    private static String normalizeScopeKey(String value) {
        if (value == null) return "";
        return value.toLowerCase(java.util.Locale.ROOT).replaceAll("[\\s_\\-]+", "");
    }

    private static Connection openDbConnection() throws Exception {
        DataSource dataSource = EpmsDataSourceProvider.resolveDataSource();
        return dataSource.getConnection();
    }
}
