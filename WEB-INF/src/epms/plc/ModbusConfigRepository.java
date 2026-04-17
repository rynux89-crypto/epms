package epms.plc;

import epms.plc.ModbusApiResponseSupport.PlcConfigSnapshot;
import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class ModbusConfigRepository {
    private static final String AI_MASTER_TABLE = "plc_ai_mapping_master";
    private static final String DI_MASTER_TABLE = "plc_di_mapping_master";
    private static final String AI_LEGACY_MAP_TABLE = "plc_meter_map";
    private static final String DI_LEGACY_TAG_TABLE = "plc_di_tag_map";
    private static final String AI_LEGACY_MATCH_TABLE = "plc_ai_measurements_match";
    private static final String LEGACY_FALLBACK_PROPERTY = "epms.plc.legacyFallbackEnabled";
    private static final String LEGACY_FALLBACK_ENV = "EPMS_PLC_LEGACY_FALLBACK_ENABLED";

    private ModbusConfigRepository() {
    }

    public static Map<Integer, PlcConfigSnapshot> loadAllConfigSnapshots() throws Exception {
        Map<Integer, PlcConfigSnapshot> out = new LinkedHashMap<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled " +
                     "FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                PlcConfigSnapshot cfg = new PlcConfigSnapshot();
                cfg.exists = true;
                cfg.ip = rs.getString("plc_ip");
                cfg.pollingMs = rs.getInt("polling_ms");
                cfg.enabled = rs.getBoolean("enabled");
                out.put(Integer.valueOf(rs.getInt("plc_id")), cfg);
            }
        }
        return out;
    }

    public static Map<Integer, PlcConfig> loadAllPlcConfigs() throws Exception {
        Map<Integer, PlcConfig> out = new LinkedHashMap<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled " +
                     "FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                PlcConfig cfg = new PlcConfig();
                cfg.exists = true;
                cfg.ip = rs.getString("plc_ip");
                cfg.port = rs.getInt("plc_port");
                cfg.unitId = rs.getInt("unit_id");
                cfg.pollingMs = rs.getInt("polling_ms");
                cfg.enabled = rs.getBoolean("enabled");
                out.put(Integer.valueOf(rs.getInt("plc_id")), cfg);
            }
        }
        return out;
    }

    public static PlcConfigSnapshot loadConfigSnapshot(int plcId) throws Exception {
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled " +
                     "FROM dbo.plc_config WHERE plc_id = ?")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return null;
                }
                PlcConfigSnapshot cfg = new PlcConfigSnapshot();
                cfg.exists = true;
                cfg.ip = rs.getString("plc_ip");
                cfg.pollingMs = rs.getInt("polling_ms");
                cfg.enabled = rs.getBoolean("enabled");
                return cfg;
            }
        }
    }

    public static PlcConfig loadPlcConfig(int plcId) throws Exception {
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config WHERE plc_id = ?")) {
            PlcConfig cfg = new PlcConfig();
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    cfg.exists = true;
                    cfg.ip = rs.getString("plc_ip");
                    cfg.port = rs.getInt("plc_port");
                    cfg.unitId = rs.getInt("unit_id");
                    cfg.pollingMs = rs.getInt("polling_ms");
                    cfg.enabled = rs.getBoolean("enabled");
                }
            }
            return cfg;
        }
    }

    public static List<PlcAiMapEntry> loadAiMap(int plcId) throws Exception {
        // Runtime reads master-first. Legacy fallback is intentionally kept for
        // compatibility until every PLC/import path is confirmed on the master tables.
        if (hasRowsForPlc(AI_MASTER_TABLE, plcId)) {
            List<PlcAiMapEntry> masterMapList = loadAiMapFromMaster(plcId);
            if (!masterMapList.isEmpty()) {
                return masterMapList;
            }
        }
        if (!isLegacyFallbackEnabled()) {
            return new ArrayList<>();
        }
        
        List<PlcAiMapEntry> mapList = new ArrayList<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT meter_id, start_address, float_count, byte_order, metric_order " +
                     "FROM dbo." + AI_LEGACY_MAP_TABLE + " WHERE plc_id = ? AND enabled = 1 ORDER BY meter_id, start_address")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String metricOrder = normalizeMetricOrder(rs.getString("metric_order"));
                    mapList.add(new PlcAiMapEntry(
                            rs.getInt("meter_id"),
                            rs.getInt("start_address"),
                            rs.getInt("float_count"),
                            rs.getString("byte_order"),
                            metricOrder,
                            metricOrder == null ? new String[0] : metricOrder.split("\\s*,\\s*")
                    ));
                }
            }
        }
        return mapList;
    }

    public static List<PlcDiTagEntry> loadDiTagMap(int plcId) throws Exception {
        if (hasRowsForPlc(DI_MASTER_TABLE, plcId)) {
            List<PlcDiTagEntry> masterDiTagList = loadDiTagMapFromMaster(plcId);
            if (!masterDiTagList.isEmpty()) {
                return masterDiTagList;
            }
        }
        if (!isLegacyFallbackEnabled()) {
            return new ArrayList<>();
        }

        List<PlcDiTagEntry> diTagList = new ArrayList<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT point_id, di_address, bit_no, tag_name, item_name, panel_name " +
                     "FROM dbo." + DI_LEGACY_TAG_TABLE + " WHERE plc_id = ? AND enabled = 1 ORDER BY point_id, di_address, bit_no")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    diTagList.add(new PlcDiTagEntry(
                            0,
                            rs.getInt("point_id"),
                            rs.getInt("di_address"),
                            rs.getInt("bit_no"),
                            rs.getString("tag_name"),
                            rs.getString("item_name"),
                            rs.getString("panel_name")
                    ));
                }
            }
        }
        return diTagList;
    }

    public static Map<String, PlcAiMeasurementMatchEntry> loadAiMeasurementsMatch() throws Exception {
        if (tableExists(AI_MASTER_TABLE)) {
            Map<String, PlcAiMeasurementMatchEntry> masterMatch = loadAiMeasurementsMatchFromMaster();
            if (!masterMatch.isEmpty()) {
                return masterMatch;
            }
        }
        if (!isLegacyFallbackEnabled()) {
            return new HashMap<>();
        }

        Map<String, PlcAiMeasurementMatchEntry> out = new HashMap<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT token, float_index, measurement_column, target_table, is_supported FROM dbo." + AI_LEGACY_MATCH_TABLE);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                boolean supported = rs.getBoolean("is_supported");
                String col = rs.getString("measurement_column");
                if (!supported || col == null || col.trim().isEmpty()) {
                    continue;
                }
                String token = rs.getString("token");
                if (token == null || token.trim().isEmpty()) {
                    continue;
                }
                int floatIndex = rs.getInt("float_index");
                if (floatIndex <= 0) {
                    continue;
                }
                String target = normalizeAiMatchTargetTable(rs.getString("target_table"));
                String normalizedToken = token.trim().toUpperCase(Locale.ROOT);
                out.put(buildAiMatchKey(normalizedToken, floatIndex), new PlcAiMeasurementMatchEntry(normalizedToken, floatIndex, col.trim(), target));
            }
        }
        return out;
    }

    public static String buildAiMatchKey(String token, int floatIndex) {
        String normalizedToken = token == null ? "" : token.trim().toUpperCase(Locale.ROOT);
        return normalizedToken + "|" + floatIndex;
    }

    private static List<PlcAiMapEntry> loadAiMapFromMaster(int plcId) throws Exception {
        Map<Integer, List<AiMasterRow>> rowsByMeter = new LinkedHashMap<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT meter_id, float_index, token, reg_address, byte_order " +
                     "FROM dbo." + AI_MASTER_TABLE + " " +
                     "WHERE plc_id = ? AND enabled = 1 " +
                     "ORDER BY meter_id, float_index")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int meterId = rs.getInt("meter_id");
                    rowsByMeter.computeIfAbsent(Integer.valueOf(meterId), k -> new ArrayList<AiMasterRow>())
                            .add(new AiMasterRow(
                                    meterId,
                                    rs.getInt("float_index"),
                                    normalizeAiToken(rs.getString("token")),
                                    rs.getInt("reg_address"),
                                    rs.getString("byte_order")
                            ));
                }
            }
        }

        List<PlcAiMapEntry> out = new ArrayList<>();
        for (Map.Entry<Integer, List<AiMasterRow>> e : rowsByMeter.entrySet()) {
            List<AiMasterRow> rows = e.getValue();
            if (rows == null || rows.isEmpty()) {
                continue;
            }
            int startAddress = rows.get(0).regAddress;
            String byteOrder = rows.get(0).byteOrder;
            String[] tokens = new String[rows.size()];
            for (int i = 0; i < rows.size(); i++) {
                AiMasterRow row = rows.get(i);
                if (row.regAddress < startAddress) {
                    startAddress = row.regAddress;
                }
                if ((byteOrder == null || byteOrder.trim().isEmpty()) && row.byteOrder != null && !row.byteOrder.trim().isEmpty()) {
                    byteOrder = row.byteOrder;
                }
                tokens[i] = row.token;
            }
            String metricOrder = String.join(",", tokens);
            out.add(new PlcAiMapEntry(
                    e.getKey().intValue(),
                    startAddress,
                    rows.size(),
                    byteOrder == null || byteOrder.trim().isEmpty() ? "ABCD" : byteOrder,
                    metricOrder,
                    tokens
            ));
        }
        return out;
    }

    private static List<PlcDiTagEntry> loadDiTagMapFromMaster(int plcId) throws Exception {
        List<PlcDiTagEntry> diTagList = new ArrayList<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT meter_id, point_id, di_address, bit_no, tag_name, item_name, panel_name " +
                     "FROM dbo." + DI_MASTER_TABLE + " " +
                     "WHERE plc_id = ? AND enabled = 1 " +
                     "ORDER BY point_id, di_address, bit_no")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    diTagList.add(new PlcDiTagEntry(
                            rs.getInt("meter_id"),
                            rs.getInt("point_id"),
                            rs.getInt("di_address"),
                            rs.getInt("bit_no"),
                            rs.getString("tag_name"),
                            rs.getString("item_name"),
                            rs.getString("panel_name")
                    ));
                }
            }
        }
        return diTagList;
    }

    private static Map<String, PlcAiMeasurementMatchEntry> loadAiMeasurementsMatchFromMaster() throws Exception {
        Map<String, PlcAiMeasurementMatchEntry> out = new HashMap<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT token, float_index, measurement_column, target_table " +
                     "FROM dbo." + AI_MASTER_TABLE + " " +
                     "WHERE enabled = 1 AND db_insert_yn = 1 " +
                     "  AND measurement_column IS NOT NULL AND LTRIM(RTRIM(measurement_column)) <> '' " +
                     "ORDER BY token, float_index");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String token = normalizeAiToken(rs.getString("token"));
                if (token.isEmpty()) {
                    continue;
                }
                int floatIndex = rs.getInt("float_index");
                if (floatIndex <= 0) {
                    continue;
                }
                String col = rs.getString("measurement_column");
                if (col == null || col.trim().isEmpty()) {
                    continue;
                }
                String target = normalizeAiMatchTargetTable(rs.getString("target_table"));
                String key = buildAiMatchKey(token, floatIndex);
                if (!out.containsKey(key)) {
                    out.put(key, new PlcAiMeasurementMatchEntry(token, floatIndex, col.trim(), target));
                }
            }
        }
        return out;
    }

    private static boolean hasRowsForPlc(String tableName, int plcId) throws Exception {
        if (!tableExists(tableName)) {
            return false;
        }
        String sql = "SELECT TOP 1 1 FROM dbo." + tableName + " WHERE plc_id = ?";
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    private static boolean tableExists(String tableName) throws Exception {
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection()) {
            DatabaseMetaData meta = conn.getMetaData();
            try (ResultSet rs = meta.getTables(conn.getCatalog(), null, tableName, new String[]{"TABLE"})) {
                if (rs.next()) {
                    return true;
                }
            }
            try (ResultSet rs = meta.getTables(conn.getCatalog(), "dbo", tableName, new String[]{"TABLE"})) {
                return rs.next();
            }
        }
    }

    private static boolean isLegacyFallbackEnabled() {
        String prop = System.getProperty(LEGACY_FALLBACK_PROPERTY);
        if (prop != null && !prop.trim().isEmpty()) {
            return parseBooleanFlag(prop, true);
        }
        String env = System.getenv(LEGACY_FALLBACK_ENV);
        if (env != null && !env.trim().isEmpty()) {
            return parseBooleanFlag(env, true);
        }
        return true;
    }

    private static boolean parseBooleanFlag(String value, boolean defaultValue) {
        if (value == null) {
            return defaultValue;
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        if (normalized.isEmpty()) {
            return defaultValue;
        }
        if ("1".equals(normalized) || "true".equals(normalized) || "y".equals(normalized) || "yes".equals(normalized) || "on".equals(normalized)) {
            return true;
        }
        if ("0".equals(normalized) || "false".equals(normalized) || "n".equals(normalized) || "no".equals(normalized) || "off".equals(normalized)) {
            return false;
        }
        return defaultValue;
    }

    private static String normalizeAiToken(String token) {
        if (token == null) {
            return "";
        }
        String normalized = token.trim().toUpperCase(Locale.ROOT);
        if ("KHH".equals(normalized)) {
            return "KWH";
        }
        return normalized;
    }

    private static final class AiMasterRow {
        private final int meterId;
        private final int floatIndex;
        private final String token;
        private final int regAddress;
        private final String byteOrder;

        private AiMasterRow(int meterId, int floatIndex, String token, int regAddress, String byteOrder) {
            this.meterId = meterId;
            this.floatIndex = floatIndex;
            this.token = token;
            this.regAddress = regAddress;
            this.byteOrder = byteOrder;
        }
    }

    private static String normalizeMetricOrder(String metricOrder) {
        if (metricOrder == null || metricOrder.trim().isEmpty()) return metricOrder;
        String[] raw = metricOrder.split("\\s*,\\s*");
        if (raw.length < 5) return metricOrder;
        List<String> toks = new ArrayList<>();
        for (String t : raw) toks.add(t == null ? "" : t.trim());
        return String.join(",", toks);
    }

    private static String normalizeAiMatchTargetTable(String value) {
        if (value == null) return "measurements";
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        if (normalized.isEmpty()) return "measurements";
        if ("measurements".equals(normalized) || "harmonic_measurements".equals(normalized) || "flicker_measurements".equals(normalized)) {
            return normalized;
        }
        return "measurements";
    }
}
