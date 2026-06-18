package epms.ups;

import epms.util.UpsDataSourceProvider;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class UpsDeviceService {
    private UpsDeviceService() {
    }

    public static void saveDevice(
            String upsIdRaw,
            String upsName,
            String location,
            String ipAddress,
            String modbusPortRaw,
            String unitIdRaw,
            String profileIdRaw,
            String capacityRaw,
            String pollIntervalRaw,
            String enabledRaw) throws Exception {
        int modbusPort = blank(modbusPortRaw) ? 502 : Integer.parseInt(modbusPortRaw.trim());
        int unitId = blank(unitIdRaw) ? 1 : Integer.parseInt(unitIdRaw.trim());
        Integer profileId = blank(profileIdRaw) ? null : Integer.valueOf(profileIdRaw.trim());
        BigDecimal capacity = blank(capacityRaw) ? null : new BigDecimal(capacityRaw.trim());
        int pollIntervalSeconds = blank(pollIntervalRaw) ? 2 : Integer.parseInt(pollIntervalRaw.trim());
        boolean enabled = "1".equals(enabledRaw);
        Integer upsId = blank(upsIdRaw) ? null : Integer.valueOf(upsIdRaw.trim());

        if (blank(upsName)) throw new IllegalArgumentException("UPS 이름을 입력하세요.");
        if (blank(ipAddress)) throw new IllegalArgumentException("IP 주소를 입력하세요.");
        if (pollIntervalSeconds < 1) throw new IllegalArgumentException("수집주기는 1초 이상 입력하세요.");
        if (pollIntervalSeconds > 86400) throw new IllegalArgumentException("수집주기는 86400초 이하로 입력하세요.");

        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            ensurePollIntervalColumn(conn);
            if (upsId == null) {
                insertDevice(conn, upsName, location, ipAddress, modbusPort, unitId, profileId, capacity, pollIntervalSeconds, enabled);
            } else {
                updateDevice(conn, upsId.intValue(), upsName, location, ipAddress, modbusPort, unitId, profileId, capacity, pollIntervalSeconds, enabled);
            }
        }
    }

    public static List<Map<String, Object>> listProfiles() throws Exception {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement("SELECT profile_id, profile_name FROM dbo.ups_modbus_profile WHERE enabled = 1 ORDER BY profile_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> row = new HashMap<String, Object>();
                row.put("profile_id", Integer.valueOf(rs.getInt("profile_id")));
                row.put("profile_name", rs.getString("profile_name"));
                out.add(row);
            }
        }
        return out;
    }

    public static List<Map<String, Object>> listDevices() throws Exception {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            ensurePollIntervalColumn(conn);
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.profile_id, " +
                    "d.rated_capacity_kva, d.poll_interval_seconds, d.enabled, p.profile_name " +
                    "FROM dbo.ups_device d LEFT JOIN dbo.ups_modbus_profile p ON p.profile_id = d.profile_id ORDER BY d.ups_id DESC");
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<String, Object>();
                    row.put("ups_id", Integer.valueOf(rs.getInt("ups_id")));
                    row.put("ups_name", rs.getString("ups_name"));
                    row.put("location", rs.getString("location"));
                    row.put("ip_address", rs.getString("ip_address"));
                    row.put("modbus_port", Integer.valueOf(rs.getInt("modbus_port")));
                    row.put("unit_id", Integer.valueOf(rs.getInt("unit_id")));
                    int profileId = rs.getInt("profile_id");
                    row.put("profile_id", rs.wasNull() ? null : Integer.valueOf(profileId));
                    row.put("rated_capacity_kva", rs.getBigDecimal("rated_capacity_kva"));
                    row.put("poll_interval_seconds", Integer.valueOf(rs.getInt("poll_interval_seconds")));
                    row.put("enabled", Boolean.valueOf(rs.getBoolean("enabled")));
                    row.put("profile_name", rs.getString("profile_name"));
                    out.add(row);
                }
            }
        }
        return out;
    }

    public static List<Map<String, Object>> listDevicesBasic() throws Exception {
        return UpsDeviceLookupService.listDevicesBasic();
    }

    public static List<Map<String, Object>> listDevicesWithProfile() throws Exception {
        return UpsDeviceLookupService.listDevicesWithProfile();
    }

    public static void deleteDevice(String upsIdRaw) throws Exception {
        if (blank(upsIdRaw)) throw new IllegalArgumentException("삭제할 UPS를 선택하세요.");
        int upsId = Integer.parseInt(upsIdRaw.trim());
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            boolean oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);
            try {
                deleteByUpsId(conn, "dbo.ups_measurement", upsId);
                deleteByUpsId(conn, "dbo.ups_alarm_log", upsId);
                deleteByUpsId(conn, "dbo.ups_comm_status", upsId);
                int deleted;
                try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.ups_device WHERE ups_id=?")) {
                    ps.setInt(1, upsId);
                    deleted = ps.executeUpdate();
                }
                if (deleted == 0) throw new IllegalArgumentException("삭제할 UPS를 찾을 수 없습니다.");
                conn.commit();
            } catch (Exception e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(oldAutoCommit);
            }
        }
    }

    public static void ensurePollIntervalColumn(Connection conn) throws Exception {
        try (Statement st = conn.createStatement()) {
            st.execute(
                    "IF COL_LENGTH('dbo.ups_device', 'poll_interval_seconds') IS NULL " +
                    "ALTER TABLE dbo.ups_device ADD poll_interval_seconds int NOT NULL CONSTRAINT DF_ups_device_poll_interval_seconds DEFAULT (2)");
        }
    }

    private static void deleteByUpsId(Connection conn, String tableName, int upsId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM " + tableName + " WHERE ups_id=?")) {
            ps.setInt(1, upsId);
            ps.executeUpdate();
        }
    }

    private static void insertDevice(
            Connection conn,
            String upsName,
            String location,
            String ipAddress,
            int modbusPort,
            int unitId,
            Integer profileId,
            BigDecimal capacity,
            int pollIntervalSeconds,
            boolean enabled) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.ups_device (ups_name, location, ip_address, modbus_port, unit_id, profile_id, rated_capacity_kva, poll_interval_seconds, enabled, updated_at) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, sysdatetime())")) {
            bindDevice(ps, upsName, location, ipAddress, modbusPort, unitId, profileId, capacity, pollIntervalSeconds, enabled);
            ps.executeUpdate();
        }
    }

    private static void updateDevice(
            Connection conn,
            int upsId,
            String upsName,
            String location,
            String ipAddress,
            int modbusPort,
            int unitId,
            Integer profileId,
            BigDecimal capacity,
            int pollIntervalSeconds,
            boolean enabled) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.ups_device SET ups_name=?, location=?, ip_address=?, modbus_port=?, unit_id=?, profile_id=?, rated_capacity_kva=?, poll_interval_seconds=?, enabled=?, updated_at=sysdatetime() " +
                "WHERE ups_id=?")) {
            bindDevice(ps, upsName, location, ipAddress, modbusPort, unitId, profileId, capacity, pollIntervalSeconds, enabled);
            ps.setInt(10, upsId);
            if (ps.executeUpdate() == 0) throw new IllegalArgumentException("수정할 UPS를 찾을 수 없습니다.");
        }
    }

    private static void bindDevice(
            PreparedStatement ps,
            String upsName,
            String location,
            String ipAddress,
            int modbusPort,
            int unitId,
            Integer profileId,
            BigDecimal capacity,
            int pollIntervalSeconds,
            boolean enabled) throws Exception {
        ps.setString(1, upsName.trim());
        ps.setString(2, blank(location) ? null : location.trim());
        ps.setString(3, ipAddress.trim());
        ps.setInt(4, modbusPort);
        ps.setInt(5, unitId);
        if (profileId == null) ps.setNull(6, Types.INTEGER); else ps.setInt(6, profileId.intValue());
        if (capacity == null) ps.setNull(7, Types.DECIMAL); else ps.setBigDecimal(7, capacity);
        ps.setInt(8, pollIntervalSeconds);
        ps.setBoolean(9, enabled);
    }

    private static boolean blank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
