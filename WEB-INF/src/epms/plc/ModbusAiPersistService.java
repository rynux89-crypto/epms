package epms.plc;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class ModbusAiPersistService {
    private ModbusAiPersistService() {
    }

    public static int[] persistAiRowsToTargetTables(
            Map<String, PlcAiMeasurementMatchEntry> matchMap,
            List<PlcAiReadRow> aiRows,
            Timestamp measuredAt) throws Exception {
        int measurementsInserted = 0;
        int harmonicInserted = 0;
        int flickerInserted = 0;
        if (aiRows == null || aiRows.isEmpty()) {
            return new int[]{0, 0, 0};
        }

        Map<Integer, Map<String, Double>> measurementsByMeter = new HashMap<>();
        Map<Integer, Map<String, Double>> harmonicByMeter = new HashMap<>();
        Map<Integer, Map<String, Double>> flickerByMeter = new HashMap<>();

        for (PlcAiReadRow row : aiRows) {
            if (row == null || row.token == null) {
                continue;
            }

            int meterId = row.meterId;
            String token = row.token.trim().toUpperCase(Locale.ROOT);
            if (isAiMatchPlcOnlyToken(token)) {
                continue;
            }
            PlcAiMeasurementMatchEntry mm = matchMap == null ? null : matchMap.get(token);
            if (mm == null) {
                continue;
            }

            String col = asString(mm.measurementColumn);
            String target = asString(mm.targetTable);
            if (col.isEmpty()) {
                continue;
            }
            String colNorm = col.toUpperCase(Locale.ROOT);
            if ("IR".equals(colNorm) || colNorm.endsWith("_IR") || colNorm.contains("INSULATION")) {
                continue;
            }
            double value = row.value;

            if ("measurements".equals(target)) {
                measurementsByMeter.computeIfAbsent(Integer.valueOf(meterId), k -> new HashMap<>()).put(col, Double.valueOf(value));
            } else if ("harmonic_measurements".equals(target)) {
                harmonicByMeter.computeIfAbsent(Integer.valueOf(meterId), k -> new HashMap<>()).put(col, Double.valueOf(value));
            } else if ("flicker_measurements".equals(target)) {
                flickerByMeter.computeIfAbsent(Integer.valueOf(meterId), k -> new HashMap<>()).put(col, Double.valueOf(value));
            }
        }

        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection()) {
            for (Map.Entry<Integer, Map<String, Double>> e : measurementsByMeter.entrySet()) {
                measurementsInserted += insertRowDynamic(conn, "measurements", e.getKey().intValue(), measuredAt, e.getValue());
            }
            for (Map.Entry<Integer, Map<String, Double>> e : harmonicByMeter.entrySet()) {
                harmonicInserted += insertRowDynamic(conn, "harmonic_measurements", e.getKey().intValue(), measuredAt, e.getValue());
            }
            for (Map.Entry<Integer, Map<String, Double>> e : flickerByMeter.entrySet()) {
                flickerInserted += insertRowDynamic(conn, "flicker_measurements", e.getKey().intValue(), measuredAt, e.getValue());
            }
        }
        return new int[]{measurementsInserted, harmonicInserted, flickerInserted};
    }

    public static int persistAiRowsToSamples(int plcId, PlcConfig cfg, List<PlcAiReadRow> aiRows, Timestamp measuredAt) throws Exception {
        if (cfg == null || aiRows == null || aiRows.isEmpty()) {
            return 0;
        }

        String sql =
            "INSERT INTO dbo.plc_ai_samples " +
            "(measured_at, plc_id, plc_ip, unit_id, meter_id, reg_address, value_float, byte_order, quality) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
        int inserted = 0;
        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            for (PlcAiReadRow row : aiRows) {
                if (row == null) {
                    continue;
                }

                ps.setTimestamp(1, measuredAt);
                ps.setInt(2, plcId);
                ps.setString(3, cfg.ip);
                ps.setInt(4, cfg.unitId);
                ps.setInt(5, row.meterId);
                ps.setInt(6, row.reg1);
                ps.setDouble(7, row.value);
                String byteOrder = asString(row.byteOrder);
                if (byteOrder.isEmpty()) {
                    byteOrder = "ABCD";
                }
                ps.setString(8, byteOrder);
                ps.setString(9, "GOOD");
                ps.addBatch();
                inserted++;
            }
            if (inserted > 0) {
                ps.executeBatch();
            }
        }
        return inserted;
    }

    private static int insertRowDynamic(Connection conn, String tableName, int meterId, Timestamp measuredAt, Map<String, Double> valueByColumn) throws Exception {
        if (valueByColumn == null || valueByColumn.isEmpty()) {
            return 0;
        }
        List<String> cols = new ArrayList<>();
        for (String col : valueByColumn.keySet()) {
            if (col == null) {
                continue;
            }
            String c = col.trim();
            if (c.matches("^[A-Za-z_][A-Za-z0-9_]*$")) {
                cols.add(c);
            }
        }
        if (cols.isEmpty()) {
            return 0;
        }
        Collections.sort(cols);

        StringBuilder sql = new StringBuilder();
        sql.append("INSERT INTO dbo.").append(tableName).append(" (meter_id, measured_at");
        for (String c : cols) {
            sql.append(", ").append(c);
        }
        sql.append(") VALUES (?, ?");
        for (int i = 0; i < cols.size(); i++) {
            sql.append(", ?");
        }
        sql.append(")");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            ps.setInt(idx++, meterId);
            ps.setTimestamp(idx++, measuredAt);
            for (String c : cols) {
                Double v = valueByColumn.get(c);
                if (v == null) {
                    ps.setNull(idx++, Types.DOUBLE);
                } else {
                    ps.setDouble(idx++, v.doubleValue());
                }
            }
            return ps.executeUpdate();
        }
    }

    private static boolean isAiMatchPlcOnlyToken(String token) {
        if (token == null) {
            return false;
        }
        String t = token.trim().toUpperCase(Locale.ROOT);
        return "IR".equals(t)
                || t.endsWith("_IR")
                || t.contains("INSULATION")
                || t.contains("PLC_ONLY");
    }

    private static String asString(Object value) {
        return value == null ? "" : String.valueOf(value).trim();
    }
}
