package epms.ups;

import epms.util.ModbusSupport;
import epms.util.UpsDataSourceProvider;
import java.io.IOException;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class UpsCollectorService {
    private static final int MAX_READ_REGISTERS = 120;

    private static final class Device {
        int upsId;
        String ip;
        int port;
        int unitId;
        Integer profileId;
    }

    private static final class Point {
        String metricKey;
        int functionCode;
        int registerAddress;
        int registerCount;
        String dataType;
        BigDecimal scaleFactor;
    }

    private static final class Range {
        int functionCode;
        int startAddress;
        int registerCount;
        final List<Point> points = new ArrayList<Point>();
    }

    public void pollEnabledDevices() throws Exception {
        List<Device> devices;
        Map<Integer, List<Point>> pointsByProfile = new HashMap<Integer, List<Point>>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            devices = loadDevices(conn);
            for (Device d : devices) {
                if (d.profileId != null && !pointsByProfile.containsKey(d.profileId)) {
                    pointsByProfile.put(d.profileId, loadPoints(conn, d.profileId.intValue()));
                }
            }
        }

        for (Device device : devices) {
            List<Point> points = device.profileId == null ? null : pointsByProfile.get(device.profileId);
            if (points == null || points.isEmpty()) {
                updateFailure(device.upsId, "No enabled Modbus points for profile.");
                continue;
            }
            try {
                Map<String, BigDecimal> values = readDevice(device, points);
                persistMeasurement(device.upsId, values);
                syncValueAlarms(device.upsId, values);
                updateSuccess(device.upsId);
            } catch (Exception e) {
                updateFailure(device.upsId, e.getMessage());
            }
        }
    }

    private static List<Device> loadDevices(Connection conn) throws Exception {
        List<Device> out = new ArrayList<Device>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT ups_id, ip_address, modbus_port, unit_id, profile_id " +
                "FROM dbo.ups_device WHERE enabled = 1 ORDER BY ups_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Device d = new Device();
                d.upsId = rs.getInt("ups_id");
                d.ip = rs.getString("ip_address");
                d.port = rs.getInt("modbus_port");
                d.unitId = rs.getInt("unit_id");
                int profileId = rs.getInt("profile_id");
                d.profileId = rs.wasNull() ? null : Integer.valueOf(profileId);
                out.add(d);
            }
        }
        return out;
    }

    private static List<Point> loadPoints(Connection conn, int profileId) throws Exception {
        List<Point> out = new ArrayList<Point>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT metric_key, function_code, register_address, register_count, data_type, scale_factor " +
                "FROM dbo.ups_modbus_point WHERE profile_id = ? AND enabled = 1 ORDER BY function_code, register_address, sort_order")) {
            ps.setInt(1, profileId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Point p = new Point();
                    p.metricKey = rs.getString("metric_key");
                    p.functionCode = rs.getInt("function_code");
                    p.registerAddress = rs.getInt("register_address");
                    p.registerCount = Math.max(1, rs.getInt("register_count"));
                    p.dataType = normalize(rs.getString("data_type"));
                    p.scaleFactor = rs.getBigDecimal("scale_factor");
                    if (p.scaleFactor == null) {
                        p.scaleFactor = BigDecimal.ONE;
                    }
                    out.add(p);
                }
            }
        }
        return out;
    }

    private static Map<String, BigDecimal> readDevice(Device device, List<Point> points) throws Exception {
        Map<String, BigDecimal> out = new LinkedHashMap<String, BigDecimal>();
        List<Range> ranges = buildRanges(points);
        try (ModbusSupport.ModbusTcpClient client = new ModbusSupport.ModbusTcpClient(device.ip, device.port)) {
            for (Range range : ranges) {
                byte[] bytes = readRegisters(client, device.unitId, range.functionCode, range.startAddress, range.registerCount);
                for (Point p : range.points) {
                    int offset = p.registerAddress - range.startAddress;
                    BigDecimal value = decode(bytes, offset, p);
                    if (value != null) {
                        out.put(p.metricKey, value);
                    }
                }
            }
        }
        return out;
    }

    private static List<Range> buildRanges(List<Point> points) {
        List<Range> out = new ArrayList<Range>();
        Range cur = null;
        for (Point p : points) {
            int count = Math.max(p.registerCount, inferredRegisterCount(p));
            p.registerCount = count;
            int end = p.registerAddress + count;
            if (cur == null || cur.functionCode != p.functionCode || end - cur.startAddress > MAX_READ_REGISTERS) {
                cur = new Range();
                cur.functionCode = p.functionCode;
                cur.startAddress = p.registerAddress;
                cur.registerCount = count;
                out.add(cur);
            } else {
                int curEnd = cur.startAddress + cur.registerCount;
                if (end > curEnd) {
                    cur.registerCount = end - cur.startAddress;
                }
            }
            cur.points.add(p);
        }
        return out;
    }

    private static byte[] readRegisters(ModbusSupport.ModbusTcpClient client, int unitId, int functionCode, int startAddress, int registerCount) throws IOException {
        if (functionCode == 3) {
            return ModbusSupport.readHoldingRegisters(client, unitId, ModbusSupport.toModbusOffset(startAddress), registerCount);
        }
        if (functionCode != 4) {
            throw new IOException("Unsupported Modbus function code: " + functionCode);
        }

        byte[] result = new byte[registerCount * 2];
        int readRegs = 0;
        while (readRegs < registerCount) {
            int chunk = Math.min(MAX_READ_REGISTERS, registerCount - readRegs);
            int addr = ModbusSupport.toModbusOffset(startAddress) + readRegs;
            int txId = client.nextTxId();

            byte[] req = new byte[12];
            req[0] = (byte) ((txId >> 8) & 0xFF);
            req[1] = (byte) (txId & 0xFF);
            req[2] = 0;
            req[3] = 0;
            req[4] = 0;
            req[5] = 6;
            req[6] = (byte) (unitId & 0xFF);
            req[7] = 0x04;
            req[8] = (byte) ((addr >> 8) & 0xFF);
            req[9] = (byte) (addr & 0xFF);
            req[10] = (byte) ((chunk >> 8) & 0xFF);
            req[11] = (byte) (chunk & 0xFF);
            client.out().write(req);
            client.out().flush();

            byte[] mbap = ModbusSupport.readExactly(client.in(), 7);
            int len = ModbusSupport.toU16(mbap[4], mbap[5]);
            byte[] pdu = ModbusSupport.readExactly(client.in(), len - 1);
            int fn = pdu[0] & 0xFF;
            if (fn == 0x84) {
                throw new IOException("Modbus input register exception code: " + (pdu[1] & 0xFF));
            }
            if (fn != 0x04) {
                throw new IOException("Unexpected input register function code: " + fn);
            }
            int byteCount = pdu[1] & 0xFF;
            if (byteCount != chunk * 2) {
                throw new IOException("Unexpected input register byte count: " + byteCount);
            }
            System.arraycopy(pdu, 2, result, readRegs * 2, byteCount);
            readRegs += chunk;
        }
        return result;
    }

    private static BigDecimal decode(byte[] bytes, int registerOffset, Point p) {
        int byteOffset = registerOffset * 2;
        if (byteOffset < 0 || byteOffset + 1 >= bytes.length) {
            return null;
        }
        long raw;
        String type = p.dataType;
        if ("INT16".equals(type)) {
            raw = (short) ModbusSupport.toU16(bytes[byteOffset], bytes[byteOffset + 1]);
        } else if ("UINT32".equals(type) || ("ENUM".equals(type) && p.registerCount >= 2)) {
            if (byteOffset + 3 >= bytes.length) return null;
            raw = ((long) ModbusSupport.toU16(bytes[byteOffset], bytes[byteOffset + 1]) << 16)
                    | (long) ModbusSupport.toU16(bytes[byteOffset + 2], bytes[byteOffset + 3]);
        } else if ("INT32".equals(type)) {
            if (byteOffset + 3 >= bytes.length) return null;
            raw = (int) (((long) ModbusSupport.toU16(bytes[byteOffset], bytes[byteOffset + 1]) << 16)
                    | (long) ModbusSupport.toU16(bytes[byteOffset + 2], bytes[byteOffset + 3]));
        } else {
            raw = ModbusSupport.toU16(bytes[byteOffset], bytes[byteOffset + 1]);
        }
        return BigDecimal.valueOf(raw).multiply(p.scaleFactor);
    }

    private static int inferredRegisterCount(Point p) {
        String type = p.dataType;
        if ("UINT32".equals(type) || "INT32".equals(type)) return 2;
        if ("ups_operation_mode".equalsIgnoreCase(p.metricKey)) return 2;
        return 1;
    }

    private static String normalize(String s) {
        if (s == null) return "UINT16";
        return s.trim().toUpperCase(Locale.ROOT);
    }

    private static BigDecimal avg(BigDecimal a, BigDecimal b, BigDecimal c) {
        int n = 0;
        BigDecimal sum = BigDecimal.ZERO;
        if (a != null) { sum = sum.add(a); n++; }
        if (b != null) { sum = sum.add(b); n++; }
        if (c != null) { sum = sum.add(c); n++; }
        if (n == 0) return null;
        return sum.divide(BigDecimal.valueOf(n), 3, java.math.RoundingMode.HALF_UP);
    }

    private static BigDecimal minutesFromSeconds(BigDecimal seconds) {
        if (seconds == null) return null;
        return seconds.divide(BigDecimal.valueOf(60L), 3, java.math.RoundingMode.HALF_UP);
    }

    private static void persistMeasurement(int upsId, Map<String, BigDecimal> v) throws Exception {
        BigDecimal outV12 = v.get("output_voltage_l12");
        BigDecimal outV23 = v.get("output_voltage_l23");
        BigDecimal outV31 = v.get("output_voltage_l31");
        BigDecimal outI1 = v.get("output_current_l1");
        BigDecimal outI2 = v.get("output_current_l2");
        BigDecimal outI3 = v.get("output_current_l3");

        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.ups_measurement (" +
                "ups_id, measured_at, input_voltage, output_voltage, output_voltage_l12, output_voltage_l23, output_voltage_l31, " +
                "output_current, output_current_l1, output_current_l2, output_current_l3, " +
                "output_power_kw, output_power_l1_kw, output_power_l2_kw, output_power_l3_kw, " +
                "output_apparent_l1_kva, output_apparent_l2_kva, output_apparent_l3_kva, output_apparent_total_kva, " +
                "output_pf_l1, output_pf_l2, output_pf_l3, " +
                "load_percent, frequency, battery_voltage, battery_current, battery_charge_percent, battery_temperature, remaining_minutes, " +
                "ups_operation_mode_code, system_operation_mode_code, bypass_status_code, energy_storage_status_code, input_status_code, output_status_code, " +
                "switchgear_status_code, battery_breaker_status_code, raw_status) " +
                "VALUES (?, sysdatetime(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")) {
            int i = 1;
            ps.setInt(i++, upsId);
            setDecimal(ps, i++, avg(v.get("input_voltage_l1n"), v.get("input_voltage_l2n"), v.get("input_voltage_l3n")));
            setDecimal(ps, i++, avg(outV12, outV23, outV31));
            setDecimal(ps, i++, outV12);
            setDecimal(ps, i++, outV23);
            setDecimal(ps, i++, outV31);
            setDecimal(ps, i++, avg(outI1, outI2, outI3));
            setDecimal(ps, i++, outI1);
            setDecimal(ps, i++, outI2);
            setDecimal(ps, i++, outI3);
            setDecimal(ps, i++, v.get("output_power_total_kw"));
            setDecimal(ps, i++, v.get("output_power_l1_kw"));
            setDecimal(ps, i++, v.get("output_power_l2_kw"));
            setDecimal(ps, i++, v.get("output_power_l3_kw"));
            setDecimal(ps, i++, v.get("output_apparent_l1_kva"));
            setDecimal(ps, i++, v.get("output_apparent_l2_kva"));
            setDecimal(ps, i++, v.get("output_apparent_l3_kva"));
            setDecimal(ps, i++, v.get("output_apparent_total_kva"));
            setDecimal(ps, i++, v.get("output_pf_l1"));
            setDecimal(ps, i++, v.get("output_pf_l2"));
            setDecimal(ps, i++, v.get("output_pf_l3"));
            setDecimal(ps, i++, v.get("output_load_total_percent"));
            setDecimal(ps, i++, v.get("output_frequency"));
            setDecimal(ps, i++, v.get("battery_voltage"));
            setDecimal(ps, i++, v.get("battery_current"));
            setDecimal(ps, i++, v.get("battery_charge_percent"));
            setDecimal(ps, i++, v.get("battery_temperature"));
            setDecimal(ps, i++, minutesFromSeconds(v.get("battery_remaining_seconds")));
            setInt(ps, i++, v.get("ups_operation_mode"));
            setInt(ps, i++, v.get("system_operation_mode"));
            setInt(ps, i++, v.get("bypass_status"));
            setInt(ps, i++, v.get("energy_storage_status"));
            setInt(ps, i++, v.get("input_status"));
            setInt(ps, i++, v.get("output_status"));
            setInt(ps, i++, v.get("switchgear_status"));
            setInt(ps, i++, v.get("battery_breaker_status"));
            setInt(ps, i++, v.get("ups_status_word"));
            ps.executeUpdate();
        }
    }

    private static void syncValueAlarms(int upsId, Map<String, BigDecimal> values) throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(
                    "SELECT rule_code, metric_key, operator, threshold_value, severity, message_template " +
                    "FROM dbo.ups_alarm_rule WHERE enabled = 1 ORDER BY rule_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String ruleCode = rs.getString("rule_code");
                String metricKey = rs.getString("metric_key");
                String operator = rs.getString("operator");
                BigDecimal threshold = rs.getBigDecimal("threshold_value");
                String severity = rs.getString("severity");
                String template = rs.getString("message_template");
                BigDecimal value = values.get(metricKey);
                boolean active = value != null && compare(value, operator, threshold);
                if (active) {
                    openAlarm(conn, upsId, ruleCode, metricKey, severity, renderMessage(template, metricKey, value, threshold));
                } else {
                    clearAlarm(conn, upsId, ruleCode);
                }
            }
        }
    }

    private static boolean compare(BigDecimal value, String operator, BigDecimal threshold) {
        if (value == null || threshold == null || operator == null) return false;
        String op = operator.trim().toUpperCase(Locale.ROOT);
        if ("BIT_SET".equals(op)) {
            int bit = threshold.intValue();
            if (bit < 0 || bit > 30) return false;
            return (value.intValue() & (1 << bit)) != 0;
        }
        int c = value.compareTo(threshold);
        if (">".equals(op)) return c > 0;
        if (">=".equals(op)) return c >= 0;
        if ("<".equals(op)) return c < 0;
        if ("<=".equals(op)) return c <= 0;
        if ("=".equals(op) || "==".equals(op)) return c == 0;
        if ("!=".equals(op) || "<>".equals(op)) return c != 0;
        return false;
    }

    private static String renderMessage(String template, String metricKey, BigDecimal value, BigDecimal threshold) {
        String msg = template == null || template.trim().isEmpty() ? metricKey + " alarm" : template;
        msg = msg.replace("{metric}", metricKey == null ? "" : metricKey);
        msg = msg.replace("{value}", value == null ? "" : value.stripTrailingZeros().toPlainString());
        msg = msg.replace("{threshold}", threshold == null ? "" : threshold.stripTrailingZeros().toPlainString());
        return msg.length() > 500 ? msg.substring(0, 500) : msg;
    }

    private static void openAlarm(Connection conn, int upsId, String ruleCode, String metricKey, String severity, String message) throws Exception {
        try (PreparedStatement check = conn.prepareStatement(
                "SELECT 1 FROM dbo.ups_alarm_log WHERE ups_id=? AND rule_code=? AND status='ACTIVE'")) {
            check.setInt(1, upsId);
            check.setString(2, ruleCode);
            try (ResultSet rs = check.executeQuery()) {
                if (rs.next()) return;
            }
        }
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.ups_alarm_log (ups_id, rule_code, metric_key, severity, alarm_message, occurred_at, status) " +
                "VALUES (?, ?, ?, ?, ?, sysdatetime(), 'ACTIVE')")) {
            ps.setInt(1, upsId);
            ps.setString(2, ruleCode);
            ps.setString(3, metricKey);
            ps.setString(4, severity == null ? "WARNING" : severity);
            ps.setString(5, message);
            ps.executeUpdate();
        }
    }

    private static void clearAlarm(Connection conn, int upsId, String ruleCode) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.ups_alarm_log SET status='CLEARED', cleared_at=sysdatetime() " +
                "WHERE ups_id=? AND rule_code=? AND status='ACTIVE'")) {
            ps.setInt(1, upsId);
            ps.setString(2, ruleCode);
            ps.executeUpdate();
        }
    }

    private static void setDecimal(PreparedStatement ps, int idx, BigDecimal value) throws Exception {
        if (value == null) ps.setNull(idx, Types.DECIMAL);
        else ps.setBigDecimal(idx, value);
    }

    private static void setInt(PreparedStatement ps, int idx, BigDecimal value) throws Exception {
        if (value == null) ps.setNull(idx, Types.INTEGER);
        else ps.setInt(idx, value.intValue());
    }

    private static void updateSuccess(int upsId) throws Exception {
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            try (PreparedStatement ps = conn.prepareStatement(
                    "UPDATE dbo.ups_device SET last_comm_status='OK', last_success_at=sysdatetime(), last_error_message=NULL, updated_at=sysdatetime() WHERE ups_id=?")) {
                ps.setInt(1, upsId);
                ps.executeUpdate();
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "MERGE dbo.ups_comm_status AS t USING (SELECT ? AS ups_id) AS s ON t.ups_id=s.ups_id " +
                    "WHEN MATCHED THEN UPDATE SET status='OK', consecutive_fail_count=0, last_poll_at=sysdatetime(), last_success_at=sysdatetime(), last_error_message=NULL, updated_at=sysdatetime() " +
                    "WHEN NOT MATCHED THEN INSERT (ups_id, status, consecutive_fail_count, last_poll_at, last_success_at, updated_at) VALUES (?, 'OK', 0, sysdatetime(), sysdatetime(), sysdatetime());")) {
                ps.setInt(1, upsId);
                ps.setInt(2, upsId);
                ps.executeUpdate();
            }
            clearAlarm(conn, upsId, "UPS_COMM_FAIL");
        }
    }

    private static void updateFailure(int upsId, String error) {
        String msg = error == null ? "Unknown UPS polling error" : error;
        if (msg.length() > 500) msg = msg.substring(0, 500);
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            try (PreparedStatement ps = conn.prepareStatement(
                    "UPDATE dbo.ups_device SET last_comm_status='ERROR', last_error_at=sysdatetime(), last_error_message=?, updated_at=sysdatetime() WHERE ups_id=?")) {
                ps.setString(1, msg);
                ps.setInt(2, upsId);
                ps.executeUpdate();
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "MERGE dbo.ups_comm_status AS t USING (SELECT ? AS ups_id) AS s ON t.ups_id=s.ups_id " +
                    "WHEN MATCHED THEN UPDATE SET status='ERROR', consecutive_fail_count=consecutive_fail_count+1, last_poll_at=sysdatetime(), last_error_at=sysdatetime(), last_error_message=?, updated_at=sysdatetime() " +
                    "WHEN NOT MATCHED THEN INSERT (ups_id, status, consecutive_fail_count, last_poll_at, last_error_at, last_error_message, updated_at) VALUES (?, 'ERROR', 1, sysdatetime(), sysdatetime(), ?, sysdatetime());")) {
                ps.setInt(1, upsId);
                ps.setString(2, msg);
                ps.setInt(3, upsId);
                ps.setString(4, msg);
                ps.executeUpdate();
            }
            openAlarm(conn, upsId, "UPS_COMM_FAIL", "communication", "CRITICAL", "UPS 통신 실패: " + msg);
        } catch (Exception ignore) {
        }
    }
}
