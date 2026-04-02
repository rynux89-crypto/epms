package epms.plc;

import epms.plc.ModbusApiResponseSupport.PlcConfigSnapshot;
import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class ModbusConfigRepository {
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
        List<PlcAiMapEntry> mapList = new ArrayList<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT meter_id, start_address, float_count, byte_order, metric_order " +
                     "FROM dbo.plc_meter_map WHERE plc_id = ? AND enabled = 1 ORDER BY meter_id, start_address")) {
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
        List<PlcDiTagEntry> diTagList = new ArrayList<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT point_id, di_address, bit_no, tag_name, item_name, panel_name " +
                     "FROM dbo.plc_di_tag_map WHERE plc_id = ? AND enabled = 1 ORDER BY point_id, di_address, bit_no")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    diTagList.add(new PlcDiTagEntry(
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
        Map<String, PlcAiMeasurementMatchEntry> out = new HashMap<>();
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT token, measurement_column, target_table, is_supported FROM dbo.plc_ai_measurements_match");
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
                String target = normalizeAiMatchTargetTable(rs.getString("target_table"));
                String normalizedToken = token.trim().toUpperCase(Locale.ROOT);
                out.put(normalizedToken, new PlcAiMeasurementMatchEntry(normalizedToken, col.trim(), target));
            }
        }
        return out;
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
