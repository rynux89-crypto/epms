package epms.plc;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

public final class ModbusMeterResolutionSupport {
    public static final class MeterResolutionMaps {
        public final Map<String, Integer> meterIdByName;
        public final Map<String, Integer> meterIdByNamePanel;
        public final Map<String, Integer> uniqueMeterIdByPanel;
        public final Map<String, Integer> uniqueMeterIdByCompactPanel;

        MeterResolutionMaps(
                Map<String, Integer> meterIdByName,
                Map<String, Integer> meterIdByNamePanel,
                Map<String, Integer> uniqueMeterIdByPanel,
                Map<String, Integer> uniqueMeterIdByCompactPanel) {
            this.meterIdByName = meterIdByName;
            this.meterIdByNamePanel = meterIdByNamePanel;
            this.uniqueMeterIdByPanel = uniqueMeterIdByPanel;
            this.uniqueMeterIdByCompactPanel = uniqueMeterIdByCompactPanel;
        }
    }

    private ModbusMeterResolutionSupport() {
    }

    public static MeterResolutionMaps loadMeterResolutionMaps(Connection conn) throws Exception {
        return new MeterResolutionMaps(
                loadMeterIdByExactName(conn),
                loadMeterIdByExactNamePanel(conn),
                loadUniqueMeterIdByPanel(conn, false),
                loadUniqueMeterIdByPanel(conn, true)
        );
    }

    public static int resolveDiAlarmMeterId(MeterResolutionMaps maps, String itemName, String panelName) {
        if (maps == null) {
            return 0;
        }
        String itemKey = normKey(itemName);
        String panelKey = normKey(panelName);
        if (!itemKey.isEmpty() && !panelKey.isEmpty()) {
            Integer exactNamePanel = maps.meterIdByNamePanel.get(itemKey + "|" + panelKey);
            if (exactNamePanel != null && exactNamePanel.intValue() > 0) return exactNamePanel.intValue();
        }
        if (!itemKey.isEmpty()) {
            Integer exact = maps.meterIdByName.get(itemKey);
            if (exact != null && exact.intValue() > 0) return exact.intValue();
        }
        if (!panelKey.isEmpty()) {
            Integer byPanel = maps.uniqueMeterIdByPanel.get(panelKey);
            if (byPanel != null && byPanel.intValue() > 0) return byPanel.intValue();
        }
        String compactPanel = compactKey(panelName);
        if (!compactPanel.isEmpty()) {
            Integer byCompactPanel = maps.uniqueMeterIdByCompactPanel.get(compactPanel);
            if (byCompactPanel != null && byCompactPanel.intValue() > 0) return byCompactPanel.intValue();
        }
        return 0;
    }

    static String normKey(String s) {
        return s == null ? "" : s.trim().toUpperCase(Locale.ROOT);
    }

    static String compactKey(String s) {
        String x = normKey(s);
        return x.isEmpty() ? "" : x.replaceAll("[^A-Z0-9]+", "");
    }

    private static Map<String, Integer> loadMeterIdByExactName(Connection conn) throws Exception {
        Map<String, Integer> out = new HashMap<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, name FROM dbo.meters WHERE name IS NOT NULL AND LTRIM(RTRIM(name)) <> ''");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String key = normKey(rs.getString("name"));
                if (!key.isEmpty() && !out.containsKey(key)) {
                    out.put(key, Integer.valueOf(rs.getInt("meter_id")));
                }
            }
        }
        return out;
    }

    private static Map<String, Integer> loadMeterIdByExactNamePanel(Connection conn) throws Exception {
        Map<String, Integer> out = new HashMap<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, name, panel_name FROM dbo.meters " +
                "WHERE name IS NOT NULL AND LTRIM(RTRIM(name)) <> '' " +
                "  AND panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> ''");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String nameKey = normKey(rs.getString("name"));
                String panelKey = normKey(rs.getString("panel_name"));
                if (nameKey.isEmpty() || panelKey.isEmpty()) continue;
                String key = nameKey + "|" + panelKey;
                if (!out.containsKey(key)) out.put(key, Integer.valueOf(rs.getInt("meter_id")));
            }
        }
        return out;
    }

    private static Map<String, Integer> loadUniqueMeterIdByPanel(Connection conn, boolean compact) throws Exception {
        Map<String, Integer> firstSeen = new HashMap<>();
        Set<String> duplicates = new HashSet<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, panel_name FROM dbo.meters WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> ''");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String raw = rs.getString("panel_name");
                String key = compact ? compactKey(raw) : normKey(raw);
                if (key.isEmpty()) continue;
                Integer meterId = Integer.valueOf(rs.getInt("meter_id"));
                if (firstSeen.containsKey(key) && !Objects.equals(firstSeen.get(key), meterId)) {
                    duplicates.add(key);
                } else if (!firstSeen.containsKey(key)) {
                    firstSeen.put(key, meterId);
                }
            }
        }
        for (String dup : duplicates) firstSeen.remove(dup);
        return firstSeen;
    }
}
