package epms.tenant;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

public final class TenantMeterMapRepository {
    public Connection openConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public void clearPrimaryForStore(Connection conn, int storeId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.tenant_meter_map SET is_primary = 0, updated_at = sysdatetime() WHERE store_id = ?")) {
            ps.setInt(1, storeId);
            ps.executeUpdate();
        }
    }

    public void clearPrimaryForStoreExcept(Connection conn, int storeId, long mapId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.tenant_meter_map SET is_primary = 0, updated_at = sysdatetime() WHERE store_id = ? AND map_id <> ?")) {
            ps.setInt(1, storeId);
            ps.setLong(2, mapId);
            ps.executeUpdate();
        }
    }

    public Long addMap(Connection conn, int storeId, int meterId, String scope, double ratio, boolean isPrimary,
            Date validFrom, Date validTo, String notes) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.tenant_meter_map (store_id, meter_id, billing_scope, allocation_ratio, is_primary, valid_from, valid_to, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, storeId);
            ps.setInt(2, meterId);
            ps.setString(3, scope);
            ps.setDouble(4, ratio);
            ps.setBoolean(5, isPrimary);
            ps.setDate(6, validFrom);
            if (validTo == null) ps.setNull(7, Types.DATE); else ps.setDate(7, validTo);
            ps.setString(8, notes);
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return Long.valueOf(rs.getLong(1));
            }
        }
        return null;
    }

    public void updateMap(Connection conn, long mapId, int storeId, int meterId, String scope, double ratio,
            boolean isPrimary, Date validFrom, Date validTo, String notes) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.tenant_meter_map SET store_id=?, meter_id=?, billing_scope=?, allocation_ratio=?, is_primary=?, valid_from=?, valid_to=?, notes=?, updated_at=sysdatetime() WHERE map_id=?")) {
            ps.setInt(1, storeId);
            ps.setInt(2, meterId);
            ps.setString(3, scope);
            ps.setDouble(4, ratio);
            ps.setBoolean(5, isPrimary);
            ps.setDate(6, validFrom);
            if (validTo == null) ps.setNull(7, Types.DATE); else ps.setDate(7, validTo);
            ps.setString(8, notes);
            ps.setLong(9, mapId);
            ps.executeUpdate();
        }
    }

    public void deleteMap(Connection conn, long mapId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.tenant_meter_map WHERE map_id = ?")) {
            ps.setLong(1, mapId);
            ps.executeUpdate();
        }
    }

    public List<TenantOption> listStoreOptions(Connection conn) throws Exception {
        List<TenantOption> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT store_id, store_code, store_name FROM dbo.tenant_store WHERE status = 'ACTIVE' ORDER BY store_code");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                rows.add(new TenantOption(rs.getString("store_id"),
                        rs.getString("store_code") + " - " + rs.getString("store_name")));
            }
        }
        return rows;
    }

    public List<TenantOption> listMeterOptions(Connection conn, String buildingFilter) throws Exception {
        List<TenantOption> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, name, building_name, panel_name FROM dbo.meters WHERE (?='' OR ISNULL(building_name,'')=?) ORDER BY meter_id")) {
            ps.setString(1, buildingFilter);
            ps.setString(2, buildingFilter);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new TenantOption(
                            rs.getString("meter_id"),
                            "#" + rs.getString("meter_id") + " / " + rs.getString("name") + " / " +
                            rs.getString("building_name") + " / " + rs.getString("panel_name")));
                }
            }
        }
        return rows;
    }

    public List<String> listBuildingOptions(Connection conn) throws Exception {
        List<String> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT building_name FROM dbo.meters WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name)) <> '' ORDER BY building_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) rows.add(rs.getString(1));
        }
        return rows;
    }

    public int[] countMapSummary(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) AS total_cnt, SUM(CASE WHEN is_primary = 1 THEN 1 ELSE 0 END) AS primary_cnt FROM dbo.tenant_meter_map");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                return new int[]{rs.getInt("total_cnt"), rs.getInt("primary_cnt")};
            }
        }
        return new int[]{0, 0};
    }

    public List<TenantMeterMapRow> listRows(Connection conn, String storeFilter, String buildingFilter) throws Exception {
        List<TenantMeterMapRow> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT tm.map_id, tm.store_id, tm.meter_id, tm.billing_scope, tm.allocation_ratio, tm.is_primary, tm.valid_from, tm.valid_to, tm.notes, " +
                "ts.store_code, ts.store_name, m.name AS meter_name, m.building_name, m.panel_name " +
                "FROM dbo.tenant_meter_map tm " +
                "INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id " +
                "INNER JOIN dbo.meters m ON m.meter_id = tm.meter_id " +
                "WHERE (?='' OR CAST(tm.store_id AS varchar(20))=?) AND (?='' OR ISNULL(m.building_name,'')=?) " +
                "ORDER BY ts.store_code, tm.is_primary DESC, tm.map_id DESC")) {
            ps.setString(1, storeFilter);
            ps.setString(2, storeFilter);
            ps.setString(3, buildingFilter);
            ps.setString(4, buildingFilter);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new TenantMeterMapRow(
                            rs.getLong("map_id"),
                            rs.getInt("store_id"),
                            rs.getInt("meter_id"),
                            rs.getString("billing_scope"),
                            rs.getDouble("allocation_ratio"),
                            rs.getBoolean("is_primary"),
                            rs.getDate("valid_from"),
                            rs.getDate("valid_to"),
                            rs.getString("notes"),
                            rs.getString("store_code"),
                            rs.getString("store_name"),
                            rs.getString("meter_name"),
                            rs.getString("building_name"),
                            rs.getString("panel_name")));
                }
            }
        }
        return rows;
    }
}
