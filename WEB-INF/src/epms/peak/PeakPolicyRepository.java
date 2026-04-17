package epms.peak;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

public final class PeakPolicyRepository {
    public Connection openConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public int countActiveStores(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) FROM dbo.tenant_store WHERE status = 'ACTIVE'");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    public int countActiveMappedMeters(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(DISTINCT meter_id) " +
                "FROM dbo.tenant_meter_map " +
                "WHERE valid_from <= CAST(GETDATE() AS date) " +
                "AND (valid_to IS NULL OR valid_to >= CAST(GETDATE() AS date))");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    public int countUnmappedActiveStores(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) " +
                "FROM dbo.tenant_store ts " +
                "WHERE ts.status = 'ACTIVE' " +
                "AND NOT EXISTS ( " +
                "    SELECT 1 FROM dbo.tenant_meter_map tm " +
                "    WHERE tm.store_id = ts.store_id " +
                "    AND tm.valid_from <= CAST(GETDATE() AS date) " +
                "    AND (tm.valid_to IS NULL OR tm.valid_to >= CAST(GETDATE() AS date)) " +
                ")");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    public boolean peakPolicyTableExists(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT CASE WHEN OBJECT_ID('dbo.peak_policy', 'U') IS NOT NULL THEN 1 ELSE 0 END");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() && rs.getInt(1) == 1;
        }
    }

    public boolean peak15MinSummaryTableExists(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT CASE WHEN OBJECT_ID('dbo.peak_15min_summary', 'U') IS NOT NULL THEN 1 ELSE 0 END");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() && rs.getInt(1) == 1;
        }
    }

    public Timestamp findPeak15MinSummaryUpdatedAt(Connection conn) throws Exception {
        if (!peak15MinSummaryTableExists(conn)) return null;
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT MAX(updated_at) AS latest_updated_at FROM dbo.peak_15min_summary");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getTimestamp("latest_updated_at") : null;
        }
    }

    public List<PeakMeterRow> listTopPeakMeters(Connection conn, int limitDays, int limitRows) throws Exception {
        List<PeakMeterRow> rows = new ArrayList<PeakMeterRow>();
        boolean useSummaryTable = peak15MinSummaryTableExists(conn);
        String sql =
            "WITH active_map AS ( " +
            "    SELECT tm.meter_id, ts.store_code, ts.store_name, " +
            "           ROW_NUMBER() OVER (PARTITION BY tm.meter_id ORDER BY tm.is_primary DESC, ts.store_code ASC, tm.map_id ASC) AS rn " +
            "    FROM dbo.tenant_meter_map tm " +
            "    INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id " +
            "    WHERE tm.valid_from <= CAST(GETDATE() AS date) " +
            "      AND (tm.valid_to IS NULL OR tm.valid_to >= CAST(GETDATE() AS date)) " +
            "), ranked_peak AS ( " +
            "    SELECT ms.meter_id, CAST(ms.active_power_total AS float) AS instant_peak_kw, ms.measured_at, " +
            "           ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY CAST(ms.active_power_total AS float) DESC, ms.measured_at DESC) AS rn " +
            "    FROM dbo.measurements ms " +
            "    WHERE ms.active_power_total IS NOT NULL " +
            "      AND ms.measured_at >= DATEADD(day, ?, GETDATE()) " +
            "), demand_bucket AS ( " +
            buildDemandBucketSql(useSummaryTable, "demand_peak_kw") +
            "), ranked_demand AS ( " +
            "    SELECT db.meter_id, db.bucket_at, db.demand_peak_kw, " +
            "           ROW_NUMBER() OVER (PARTITION BY db.meter_id ORDER BY db.demand_peak_kw DESC, db.bucket_at DESC) AS rn " +
            "    FROM demand_bucket db " +
            ") " +
            "SELECT TOP (?) rd.meter_id, m.name AS meter_name, m.building_name, m.panel_name, " +
            "       am.store_code, am.store_name, " +
            "       rp.instant_peak_kw, rp.measured_at AS instant_peak_measured_at, " +
            "       rd.demand_peak_kw, rd.bucket_at AS demand_peak_measured_at " +
            "FROM ranked_demand rd " +
            "INNER JOIN ranked_peak rp ON rp.meter_id = rd.meter_id AND rp.rn = 1 " +
            "INNER JOIN dbo.meters m ON m.meter_id = rd.meter_id " +
            "LEFT JOIN active_map am ON am.meter_id = rd.meter_id AND am.rn = 1 " +
            "WHERE rd.rn = 1 " +
            "ORDER BY rd.demand_peak_kw DESC, rd.bucket_at DESC";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, -Math.abs(limitDays));
            ps.setInt(2, -Math.abs(limitDays));
            ps.setInt(3, limitRows);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new PeakMeterRow(
                            rs.getInt("meter_id"),
                            rs.getString("meter_name"),
                            rs.getString("building_name"),
                            rs.getString("panel_name"),
                            rs.getString("store_code"),
                            rs.getString("store_name"),
                            rs.getDouble("instant_peak_kw"),
                            rs.getTimestamp("instant_peak_measured_at"),
                            rs.getDouble("demand_peak_kw"),
                            rs.getTimestamp("demand_peak_measured_at")));
                }
            }
        }
        return rows;
    }

    public List<PeakStoreOption> listStoreOptions(Connection conn) throws Exception {
        List<PeakStoreOption> rows = new ArrayList<PeakStoreOption>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT store_id, store_code, store_name FROM dbo.tenant_store WHERE status='ACTIVE' ORDER BY store_code");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                rows.add(new PeakStoreOption(String.valueOf(rs.getInt("store_id")),
                        rs.getString("store_code") + " - " + rs.getString("store_name")));
            }
        }
        return rows;
    }

    public int countActivePolicies(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) FROM dbo.peak_policy " +
                "WHERE effective_from <= CAST(GETDATE() AS date) " +
                "AND (effective_to IS NULL OR effective_to >= CAST(GETDATE() AS date))");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    public List<PeakPolicyStatusRow> listPolicyStatusRows(Connection conn, int limitDays, int limitRows) throws Exception {
        List<PeakPolicyStatusRow> rows = new ArrayList<PeakPolicyStatusRow>();
        boolean useSummaryTable = peak15MinSummaryTableExists(conn);
        String sql =
            "WITH active_policy AS ( " +
            "    SELECT p.policy_id, p.store_id, p.peak_limit_kw, p.warning_threshold_pct, p.control_threshold_pct, " +
            "           ROW_NUMBER() OVER (PARTITION BY p.store_id ORDER BY p.effective_from DESC, p.policy_id DESC) AS rn " +
            "    FROM dbo.peak_policy p " +
            "    WHERE p.effective_from <= CAST(GETDATE() AS date) " +
            "      AND (p.effective_to IS NULL OR p.effective_to >= CAST(GETDATE() AS date)) " +
            "), mapped_meter AS ( " +
            "    SELECT tm.store_id, tm.meter_id " +
            "    FROM dbo.tenant_meter_map tm " +
            "    WHERE tm.valid_from <= CAST(GETDATE() AS date) " +
            "      AND (tm.valid_to IS NULL OR tm.valid_to >= CAST(GETDATE() AS date)) " +
            "), demand_bucket AS ( " +
            buildDemandBucketSql(useSummaryTable, "demand_kw") +
            "), store_bucket AS ( " +
            "    SELECT mm.store_id, db.bucket_at, MAX(db.demand_kw) AS demand_kw " +
            "    FROM mapped_meter mm " +
            "    INNER JOIN demand_bucket db ON db.meter_id = mm.meter_id " +
            "    GROUP BY mm.store_id, db.bucket_at " +
            "), store_peak AS ( " +
            "    SELECT sb.store_id, MAX(sb.demand_kw) AS demand_peak_kw " +
            "    FROM store_bucket sb " +
            "    GROUP BY sb.store_id " +
            "), exceed_bucket AS ( " +
            "    SELECT ap.store_id, sb.bucket_at, sb.demand_kw, " +
            "           ROW_NUMBER() OVER (PARTITION BY ap.store_id ORDER BY sb.bucket_at DESC) AS rn " +
            "    FROM active_policy ap " +
            "    INNER JOIN store_bucket sb ON sb.store_id = ap.store_id " +
            "    WHERE ap.rn = 1 " +
            "      AND ap.peak_limit_kw > 0 " +
            "      AND ap.warning_threshold_pct IS NOT NULL " +
            "      AND sb.demand_kw >= (ap.peak_limit_kw * ap.warning_threshold_pct / 100.0) " +
            "), latest_exceed AS ( " +
            "    SELECT store_id, bucket_at AS latest_exceeded_at " +
            "    FROM exceed_bucket WHERE rn = 1 " +
            "), exceed_stats AS ( " +
            "    SELECT ap.store_id, " +
            "           SUM(CASE WHEN sb.bucket_at >= DATEADD(hour, -1, GETDATE()) " +
            "                     AND sb.demand_kw >= (ap.peak_limit_kw * ap.warning_threshold_pct / 100.0) THEN 1 ELSE 0 END) AS exceeded_count_last_hour, " +
            "           SUM(CASE WHEN CAST(sb.bucket_at AS date) = CAST(GETDATE() AS date) " +
            "                     AND sb.demand_kw >= (ap.peak_limit_kw * ap.warning_threshold_pct / 100.0) THEN 1 ELSE 0 END) AS exceeded_count_today " +
            "    FROM active_policy ap " +
            "    INNER JOIN store_bucket sb ON sb.store_id = ap.store_id " +
            "    WHERE ap.rn = 1 AND ap.peak_limit_kw > 0 AND ap.warning_threshold_pct IS NOT NULL " +
            "    GROUP BY ap.store_id " +
            "), ordered_bucket AS ( " +
            "    SELECT ap.store_id, sb.bucket_at, sb.demand_kw, " +
            "           CASE WHEN ap.peak_limit_kw > 0 AND ap.warning_threshold_pct IS NOT NULL " +
            "                     AND sb.demand_kw >= (ap.peak_limit_kw * ap.warning_threshold_pct / 100.0) THEN 1 ELSE 0 END AS is_exceed, " +
            "           SUM(CASE WHEN ap.peak_limit_kw > 0 AND ap.warning_threshold_pct IS NOT NULL " +
            "                         AND sb.demand_kw >= (ap.peak_limit_kw * ap.warning_threshold_pct / 100.0) THEN 0 ELSE 1 END) " +
            "               OVER (PARTITION BY ap.store_id ORDER BY sb.bucket_at DESC ROWS UNBOUNDED PRECEDING) AS break_group " +
            "    FROM active_policy ap " +
            "    INNER JOIN store_bucket sb ON sb.store_id = ap.store_id " +
            "    WHERE ap.rn = 1 " +
            "), consecutive_exceed AS ( " +
            "    SELECT store_id, COUNT(*) AS consecutive_exceeded_count " +
            "    FROM ordered_bucket " +
            "    WHERE is_exceed = 1 AND break_group = 0 " +
            "    GROUP BY store_id " +
            ") " +
            "SELECT TOP (?) ap.policy_id, ap.store_id, ts.store_code, ts.store_name, ts.floor_name, ts.category_name, ap.peak_limit_kw, " +
            "       ap.warning_threshold_pct, ap.control_threshold_pct, sp.demand_peak_kw, " +
            "       le.latest_exceeded_at, ISNULL(ce.consecutive_exceeded_count, 0) AS consecutive_exceeded_count, " +
            "       ISNULL(es.exceeded_count_last_hour, 0) AS exceeded_count_last_hour, " +
            "       ISNULL(es.exceeded_count_today, 0) AS exceeded_count_today " +
            "FROM active_policy ap " +
            "INNER JOIN dbo.tenant_store ts ON ts.store_id = ap.store_id " +
            "LEFT JOIN store_peak sp ON sp.store_id = ap.store_id " +
            "LEFT JOIN latest_exceed le ON le.store_id = ap.store_id " +
            "LEFT JOIN consecutive_exceed ce ON ce.store_id = ap.store_id " +
            "LEFT JOIN exceed_stats es ON es.store_id = ap.store_id " +
            "WHERE ap.rn = 1 " +
            "ORDER BY CASE WHEN ap.peak_limit_kw > 0 AND sp.demand_peak_kw IS NOT NULL THEN (sp.demand_peak_kw / ap.peak_limit_kw) ELSE 0 END DESC, ts.store_code ASC";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, -Math.abs(limitDays));
            ps.setInt(2, limitRows);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new PeakPolicyStatusRow(
                            Long.valueOf(rs.getLong("policy_id")),
                            Integer.valueOf(rs.getInt("store_id")),
                            rs.getString("store_code"),
                            rs.getString("store_name"),
                            rs.getString("floor_name"),
                            rs.getString("category_name"),
                            getNullableDouble(rs, "peak_limit_kw"),
                            getNullableDouble(rs, "warning_threshold_pct"),
                            getNullableDouble(rs, "control_threshold_pct"),
                            getNullableDouble(rs, "demand_peak_kw"),
                            rs.getTimestamp("latest_exceeded_at"),
                            rs.getInt("consecutive_exceeded_count"),
                            rs.getInt("exceeded_count_last_hour"),
                            rs.getInt("exceeded_count_today")));
                }
            }
        }
        return rows;
    }

    public List<PeakPolicyRow> listPolicies(Connection conn) throws Exception {
        List<PeakPolicyRow> rows = new ArrayList<PeakPolicyRow>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT p.policy_id, p.store_id, ts.store_code, ts.store_name, p.peak_limit_kw, " +
                "p.warning_threshold_pct, p.control_threshold_pct, p.priority_level, p.control_enabled, " +
                "p.effective_from, p.effective_to, p.notes " +
                "FROM dbo.peak_policy p " +
                "INNER JOIN dbo.tenant_store ts ON ts.store_id = p.store_id " +
                "ORDER BY ts.store_code ASC, p.effective_from DESC, p.policy_id DESC");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                rows.add(new PeakPolicyRow(
                        rs.getLong("policy_id"),
                        Integer.valueOf(rs.getInt("store_id")),
                        rs.getString("store_code"),
                        rs.getString("store_name"),
                        getNullableDouble(rs, "peak_limit_kw"),
                        getNullableDouble(rs, "warning_threshold_pct"),
                        getNullableDouble(rs, "control_threshold_pct"),
                        rs.getObject("priority_level") == null ? null : Integer.valueOf(rs.getInt("priority_level")),
                        rs.getBoolean("control_enabled"),
                        rs.getDate("effective_from"),
                        rs.getDate("effective_to"),
                        rs.getString("notes")));
            }
        }
        return rows;
    }

    public Long addPolicy(Connection conn, PeakPolicyRow row) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.peak_policy (store_id, peak_limit_kw, warning_threshold_pct, control_threshold_pct, priority_level, control_enabled, effective_from, effective_to, notes) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", Statement.RETURN_GENERATED_KEYS)) {
            bindPolicy(ps, row, false);
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return Long.valueOf(rs.getLong(1));
            }
        }
        return null;
    }

    public void updatePolicy(Connection conn, PeakPolicyRow row) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.peak_policy SET store_id=?, peak_limit_kw=?, warning_threshold_pct=?, control_threshold_pct=?, " +
                "priority_level=?, control_enabled=?, effective_from=?, effective_to=?, notes=?, updated_at=sysdatetime() " +
                "WHERE policy_id=?")) {
            bindPolicy(ps, row, true);
            ps.executeUpdate();
        }
    }

    public void deletePolicy(Connection conn, Long policyId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.peak_policy WHERE policy_id=?")) {
            ps.setLong(1, policyId.longValue());
            ps.executeUpdate();
        }
    }

    private static void bindPolicy(PreparedStatement ps, PeakPolicyRow row, boolean includePolicyId) throws Exception {
        ps.setInt(1, row.getStoreId().intValue());
        if (row.getPeakLimitKw() == null) ps.setNull(2, Types.DOUBLE); else ps.setDouble(2, row.getPeakLimitKw().doubleValue());
        if (row.getWarningThresholdPct() == null) ps.setNull(3, Types.DOUBLE); else ps.setDouble(3, row.getWarningThresholdPct().doubleValue());
        if (row.getControlThresholdPct() == null) ps.setNull(4, Types.DOUBLE); else ps.setDouble(4, row.getControlThresholdPct().doubleValue());
        if (row.getPriorityLevel() == null) ps.setNull(5, Types.INTEGER); else ps.setInt(5, row.getPriorityLevel().intValue());
        ps.setBoolean(6, row.isControlEnabled());
        if (row.getEffectiveFrom() == null) ps.setNull(7, Types.DATE); else ps.setDate(7, row.getEffectiveFrom());
        if (row.getEffectiveTo() == null) ps.setNull(8, Types.DATE); else ps.setDate(8, row.getEffectiveTo());
        ps.setString(9, row.getNotes());
        if (includePolicyId) ps.setLong(10, row.getPolicyId().longValue());
    }

    private static Double getNullableDouble(ResultSet rs, String columnName) throws Exception {
        Object value = rs.getObject(columnName);
        if (value == null) return null;
        return Double.valueOf(((Number) value).doubleValue());
    }

    private static String buildDemandBucketSql(boolean useSummaryTable, String valueAlias) {
        if (useSummaryTable) {
            return "    SELECT s.meter_id, s.bucket_at, CAST(s.demand_kw AS float) AS " + valueAlias + " " +
                   "    FROM dbo.peak_15min_summary s " +
                   "    WHERE s.bucket_at >= DATEADD(day, ?, GETDATE()) ";
        }
        return "    SELECT ms.meter_id, " +
               "           DATEADD(minute, (DATEDIFF(minute, 0, ms.measured_at) / 15) * 15, 0) AS bucket_at, " +
               "           AVG(CAST(ms.active_power_total AS float)) AS " + valueAlias + " " +
               "    FROM dbo.measurements ms " +
               "    WHERE ms.active_power_total IS NOT NULL " +
               "      AND ms.measured_at >= DATEADD(day, ?, GETDATE()) " +
               "    GROUP BY ms.meter_id, DATEADD(minute, (DATEDIFF(minute, 0, ms.measured_at) / 15) * 15, 0) ";
    }
}
