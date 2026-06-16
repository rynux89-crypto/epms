package epms.ups;

import epms.util.UpsDataSourceProvider;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class UpsDeviceLookupService {
    private UpsDeviceLookupService() {
    }

    public static List<Map<String, Object>> listDevicesBasic() throws Exception {
        return UpsDeviceRow.toMaps(listDeviceRowsBasic());
    }

    public static List<Map<String, Object>> listActiveDevicesBasic() throws Exception {
        return UpsDeviceRow.toMaps(listActiveDeviceRowsBasic());
    }

    public static List<UpsDeviceRow> listDeviceRowsBasic() throws Exception {
        List<UpsDeviceRow> out = new ArrayList<UpsDeviceRow>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT ups_id, ups_name, ip_address, modbus_port FROM dbo.ups_device ORDER BY ups_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                out.add(UpsDeviceRow.basic(rs));
            }
        }
        return out;
    }

    public static List<UpsDeviceRow> listActiveDeviceRowsBasic() throws Exception {
        List<UpsDeviceRow> out = new ArrayList<UpsDeviceRow>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT ups_id, ups_name, ip_address, modbus_port FROM dbo.ups_device WHERE enabled = 1 ORDER BY ups_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                out.add(UpsDeviceRow.basic(rs));
            }
        }
        return out;
    }

    public static List<Map<String, Object>> listDevicesWithProfile() throws Exception {
        return UpsDeviceRow.toMaps(listDeviceRowsWithProfile());
    }

    public static List<Map<String, Object>> listActiveDevicesWithProfile() throws Exception {
        return UpsDeviceRow.toMaps(listActiveDeviceRowsWithProfile());
    }

    public static List<UpsDeviceRow> listDeviceRowsWithProfile() throws Exception {
        List<UpsDeviceRow> out = new ArrayList<UpsDeviceRow>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.enabled, " +
                     "d.last_comm_status, d.last_success_at, COALESCE(cs.consecutive_fail_count, 0) AS consecutive_fail_count, p.profile_name " +
                     "FROM dbo.ups_device d " +
                     "LEFT JOIN dbo.ups_modbus_profile p ON p.profile_id = d.profile_id " +
                     "LEFT JOIN dbo.ups_comm_status cs ON cs.ups_id = d.ups_id " +
                     "ORDER BY d.ups_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                out.add(UpsDeviceRow.withProfile(rs));
            }
        }
        return out;
    }

    public static List<UpsDeviceRow> listActiveDeviceRowsWithProfile() throws Exception {
        List<UpsDeviceRow> out = new ArrayList<UpsDeviceRow>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.enabled, " +
                     "d.last_comm_status, d.last_success_at, COALESCE(cs.consecutive_fail_count, 0) AS consecutive_fail_count, p.profile_name " +
                     "FROM dbo.ups_device d " +
                     "LEFT JOIN dbo.ups_modbus_profile p ON p.profile_id = d.profile_id " +
                     "LEFT JOIN dbo.ups_comm_status cs ON cs.ups_id = d.ups_id " +
                     "WHERE d.enabled = 1 ORDER BY d.ups_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                out.add(UpsDeviceRow.withProfile(rs));
            }
        }
        return out;
    }
}
