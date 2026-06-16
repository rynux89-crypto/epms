package epms.ups;

import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class UpsDeviceRow {
    public final Integer upsId;
    public final String upsName;
    public final String location;
    public final String ipAddress;
    public final Integer modbusPort;
    public final Integer unitId;
    public final Boolean enabled;
    public final String lastCommStatus;
    public final Object lastSuccessAt;
    public final Integer consecutiveFailCount;
    public final String profileName;

    private UpsDeviceRow(Integer upsId, String upsName, String location, String ipAddress,
            Integer modbusPort, Integer unitId, Boolean enabled, String lastCommStatus,
            Object lastSuccessAt, Integer consecutiveFailCount, String profileName) {
        this.upsId = upsId;
        this.upsName = upsName;
        this.location = location;
        this.ipAddress = ipAddress;
        this.modbusPort = modbusPort;
        this.unitId = unitId;
        this.enabled = enabled;
        this.lastCommStatus = lastCommStatus;
        this.lastSuccessAt = lastSuccessAt;
        this.consecutiveFailCount = consecutiveFailCount;
        this.profileName = profileName;
    }

    public static UpsDeviceRow basic(ResultSet rs) throws Exception {
        return new UpsDeviceRow(
            Integer.valueOf(rs.getInt("ups_id")),
            rs.getString("ups_name"),
            null,
            rs.getString("ip_address"),
            Integer.valueOf(rs.getInt("modbus_port")),
            null,
            null,
            null,
            null,
            null,
            null);
    }

    public static UpsDeviceRow withProfile(ResultSet rs) throws Exception {
        return new UpsDeviceRow(
            Integer.valueOf(rs.getInt("ups_id")),
            rs.getString("ups_name"),
            rs.getString("location"),
            rs.getString("ip_address"),
            Integer.valueOf(rs.getInt("modbus_port")),
            Integer.valueOf(rs.getInt("unit_id")),
            Boolean.valueOf(rs.getBoolean("enabled")),
            rs.getString("last_comm_status"),
            rs.getObject("last_success_at"),
            Integer.valueOf(rs.getInt("consecutive_fail_count")),
            rs.getString("profile_name"));
    }

    public Map<String, Object> toMap() {
        Map<String, Object> row = new HashMap<String, Object>();
        row.put("ups_id", upsId);
        row.put("ups_name", upsName);
        row.put("location", location);
        row.put("ip_address", ipAddress);
        row.put("modbus_port", modbusPort);
        row.put("unit_id", unitId);
        row.put("enabled", enabled);
        row.put("last_comm_status", lastCommStatus);
        row.put("last_success_at", lastSuccessAt);
        row.put("consecutive_fail_count", consecutiveFailCount);
        row.put("profile_name", profileName);
        return row;
    }

    public static List<Map<String, Object>> toMaps(List<UpsDeviceRow> rows) {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        for (UpsDeviceRow row : rows) {
            out.add(row.toMap());
        }
        return out;
    }
}
