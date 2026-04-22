package epms.tenant;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public final class TenantStoreRepository {
    public Connection openConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public String nextStoreCode(Connection conn, String prefix) throws Exception {
        String sql =
            "SELECT TOP 1 store_code " +
            "FROM dbo.tenant_store " +
            "WHERE store_code LIKE ? " +
            "ORDER BY TRY_CONVERT(int, SUBSTRING(store_code, ?, 20)) DESC, store_id DESC";
        int next = 1;
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, prefix + "%");
            ps.setInt(2, prefix.length() + 1);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String code = rs.getString(1);
                    if (code != null && code.startsWith(prefix)) {
                        try {
                            next = Integer.parseInt(code.substring(prefix.length())) + 1;
                        } catch (Exception ignore) {
                            next = 1;
                        }
                    }
                }
            }
        }
        return prefix + String.format(java.util.Locale.ROOT, "%04d", next);
    }

    public void addStore(Connection conn, TenantStoreRow row) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.tenant_store (store_code, store_name, business_number, floor_name, room_name, zone_name, category_name, contact_name, contact_phone, status, opened_on, closed_on, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")) {
            bindStore(ps, row, false);
            ps.executeUpdate();
        }
    }

    public void updateStore(Connection conn, TenantStoreRow row) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.tenant_store SET store_code=?, store_name=?, business_number=?, floor_name=?, room_name=?, zone_name=?, category_name=?, contact_name=?, contact_phone=?, status=?, opened_on=?, closed_on=?, notes=?, updated_at=sysdatetime() WHERE store_id=?")) {
            bindStore(ps, row, true);
            ps.executeUpdate();
        }
    }

    public void validateDeleteAllowed(Connection conn, int storeId) throws Exception {
        try (PreparedStatement chk = conn.prepareStatement(
                "IF EXISTS (SELECT 1 FROM dbo.tenant_meter_map WHERE store_id = ?) " +
                "   OR EXISTS (SELECT 1 FROM dbo.tenant_billing_contract WHERE store_id = ?) " +
                "   OR EXISTS (SELECT 1 FROM dbo.billing_statement WHERE store_id = ?) " +
                "BEGIN THROW 53000, '연결된 매핑, 계약, 청구서가 있어 삭제할 수 없습니다.', 1; END")) {
            chk.setInt(1, storeId);
            chk.setInt(2, storeId);
            chk.setInt(3, storeId);
            chk.execute();
        }
    }

    public void deleteStore(Connection conn, int storeId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.tenant_store WHERE store_id = ?")) {
            ps.setInt(1, storeId);
            ps.executeUpdate();
        }
    }

    public void deleteStoreCascade(Connection conn, int storeId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "IF OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NOT NULL DELETE FROM dbo.peak_policy_store_map WHERE store_id = ?;" +
                "DELETE FROM dbo.billing_statement WHERE store_id = ?;" +
                "DELETE FROM dbo.billing_meter_snapshot WHERE store_id = ?;" +
                "DELETE FROM dbo.tenant_billing_contract WHERE store_id = ?;" +
                "DELETE FROM dbo.tenant_meter_map WHERE store_id = ?;" +
                "DELETE FROM dbo.tenant_store WHERE store_id = ?;")) {
            ps.setInt(1, storeId);
            ps.setInt(2, storeId);
            ps.setInt(3, storeId);
            ps.setInt(4, storeId);
            ps.setInt(5, storeId);
            ps.setInt(6, storeId);
            ps.executeUpdate();
        }
    }

    public void disableStore(Connection conn, int storeId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.tenant_store " +
                "SET status = 'CLOSED', " +
                "    closed_on = COALESCE(closed_on, ?), " +
                "    updated_at = sysdatetime() " +
                "WHERE store_id = ?")) {
            ps.setDate(1, Date.valueOf(LocalDate.now()));
            ps.setInt(2, storeId);
            ps.executeUpdate();
        }
    }

    public int[] countSummary(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) AS total_cnt, SUM(CASE WHEN status='ACTIVE' THEN 1 ELSE 0 END) AS active_cnt, SUM(CASE WHEN status='CLOSED' THEN 1 ELSE 0 END) AS closed_cnt FROM dbo.tenant_store");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                return new int[]{rs.getInt("total_cnt"), rs.getInt("active_cnt"), rs.getInt("closed_cnt")};
            }
        }
        return new int[]{0, 0, 0};
    }

    public List<TenantStoreRow> listStores(Connection conn, String searchQ, String statusQ) throws Exception {
        List<TenantStoreRow> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT store_id, store_code, store_name, business_number, floor_name, room_name, zone_name, category_name, contact_name, contact_phone, status, opened_on, closed_on, notes " +
                "FROM dbo.tenant_store " +
                "WHERE (?='' OR store_code LIKE ? OR store_name LIKE ? OR ISNULL(floor_name,'') LIKE ? OR ISNULL(room_name,'') LIKE ? OR ISNULL(zone_name,'') LIKE ?) " +
                "AND (?='' OR status=?) ORDER BY status ASC, store_code ASC, store_id ASC")) {
            ps.setString(1, searchQ);
            ps.setString(2, "%" + searchQ + "%");
            ps.setString(3, "%" + searchQ + "%");
            ps.setString(4, "%" + searchQ + "%");
            ps.setString(5, "%" + searchQ + "%");
            ps.setString(6, "%" + searchQ + "%");
            ps.setString(7, statusQ);
            ps.setString(8, statusQ);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new TenantStoreRow(
                            rs.getInt("store_id"),
                            rs.getString("store_code"),
                            rs.getString("store_name"),
                            rs.getString("business_number"),
                            rs.getString("floor_name"),
                            rs.getString("room_name"),
                            rs.getString("zone_name"),
                            rs.getString("category_name"),
                            rs.getString("contact_name"),
                            rs.getString("contact_phone"),
                            rs.getString("status"),
                            rs.getDate("opened_on"),
                            rs.getDate("closed_on"),
                            rs.getString("notes")));
                }
            }
        }
        return rows;
    }

    private static void bindStore(PreparedStatement ps, TenantStoreRow row, boolean includeStoreId) throws Exception {
        ps.setString(1, row.getStoreCode());
        ps.setString(2, row.getStoreName());
        ps.setString(3, row.getBusinessNumber());
        ps.setString(4, row.getFloorName());
        ps.setString(5, row.getRoomName());
        ps.setString(6, row.getZoneName());
        ps.setString(7, row.getCategoryName());
        ps.setString(8, row.getContactName());
        ps.setString(9, row.getContactPhone());
        ps.setString(10, row.getStatus());
        if (row.getOpenedOn() == null) ps.setNull(11, Types.DATE); else ps.setDate(11, row.getOpenedOn());
        if (row.getClosedOn() == null) ps.setNull(12, Types.DATE); else ps.setDate(12, row.getClosedOn());
        ps.setString(13, row.getNotes());
        if (includeStoreId) {
            ps.setInt(14, row.getStoreId());
        }
    }
}
