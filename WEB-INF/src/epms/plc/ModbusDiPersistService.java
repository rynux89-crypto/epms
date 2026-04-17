package epms.plc;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.List;
import java.util.Map;

public final class ModbusDiPersistService {
    private ModbusDiPersistService() {
    }

    public static int[] persistDiRowsToDeviceEvents(int plcId, List<PlcDiReadRow> diRows, Timestamp measuredAt) throws Exception {
        int opened = 0;
        int closed = 0;
        if (diRows == null || diRows.isEmpty()) {
            return new int[]{0, 0};
        }

        String selOpenSql =
            "SELECT TOP 1 event_id FROM dbo.device_events " +
            "WHERE COALESCE(meter_id, device_id) = ? AND event_type = ? AND restored_time IS NULL " +
            "ORDER BY event_id DESC";
        String insSql =
            "INSERT INTO dbo.device_events (meter_id, device_id, event_type, event_time, severity, description) " +
            "VALUES (?, ?, ?, ?, ?, ?)";
        String closeSql =
            "UPDATE dbo.device_events " +
            "SET restored_time = ?, duration_seconds = DATEDIFF(SECOND, event_time, ?), " +
            "    downtime_minutes = DATEDIFF(SECOND, event_time, ?) / 60.0 " +
            "WHERE event_id = ?";

        try (Connection conn = EpmsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement selOpen = conn.prepareStatement(selOpenSql);
             PreparedStatement ins = conn.prepareStatement(insSql);
             PreparedStatement close = conn.prepareStatement(closeSql)) {
            ModbusDiRuleSupport.ensureAlarmLogRuleColumns(conn);
            ModbusMeterResolutionSupport.MeterResolutionMaps meterMaps = ModbusMeterResolutionSupport.loadMeterResolutionMaps(conn);
            Map<String, ModbusDiRuleSupport.DiRuleMeta> diRuleMetaMap = ModbusDiRuleSupport.loadCachedDiRuleMeta(conn);

            for (PlcDiReadRow row : diRows) {
                int mappedMeterId = row.meterId;
                int pointId = row.pointId;
                int diAddress = row.diAddress;
                int bitNo = row.bitNo;
                int value = row.value;
                String tagName = asString(row.tagName);
                String itemName = asString(row.itemName);
                String panelName = asString(row.panelName);

                int resolvedMeterId = mappedMeterId > 0 ? mappedMeterId
                        : ModbusMeterResolutionSupport.resolveDiAlarmMeterId(meterMaps, itemName, panelName);
                Integer alarmMeterKey = resolvedMeterId > 0 ? Integer.valueOf(resolvedMeterId) : null;
                int eventEntityId = resolvedMeterId > 0 ? resolvedMeterId : pointId;
                String eventType = ModbusDiRuleSupport.buildDiEventType(bitNo, tagName);
                String diRuleCode = ModbusDiRuleSupport.resolveDiRuleCode(eventType, tagName);
                ModbusDiRuleSupport.DiRuleMeta diRuleMeta = diRuleMetaMap.get(ModbusDiRuleSupport.normKey(diRuleCode));
                boolean diRuleEnabled = diRuleMeta != null && diRuleMeta.ruleId > 0;
                String diKey = plcId + ":" + pointId + ":" + diAddress + ":" + bitNo;
                Integer prev = ModbusCacheSupport.lastDiValueMap().get(diKey);

                if (prev == null) {
                    if (value == 1) {
                        if (diRuleEnabled) {
                            opened += openDiEventIfNeeded(
                                    conn, selOpen, ins, alarmMeterKey, eventEntityId, plcId, diAddress, bitNo, tagName, itemName, panelName,
                                    measuredAt, alarmMeterKey, eventType, diRuleMeta);
                        }
                    } else {
                        closed += closeDiEventIfNeeded(conn, selOpen, close, eventEntityId, measuredAt, alarmMeterKey, eventType, itemName, panelName);
                    }
                    ModbusCacheSupport.lastDiValueMap().put(diKey, Integer.valueOf(value));
                    continue;
                }

                if (prev.intValue() == 0 && value == 1) {
                    if (diRuleEnabled) {
                        opened += openDiEventIfNeeded(
                                conn, selOpen, ins, alarmMeterKey, eventEntityId, plcId, diAddress, bitNo, tagName, itemName, panelName,
                                measuredAt, alarmMeterKey, eventType, diRuleMeta);
                    }
                } else if (prev.intValue() == 1 && value == 0) {
                    closed += closeDiEventIfNeeded(conn, selOpen, close, eventEntityId, measuredAt, alarmMeterKey, eventType, itemName, panelName);
                }
                ModbusCacheSupport.lastDiValueMap().put(diKey, Integer.valueOf(value));
            }
        }
        return new int[]{opened, closed};
    }

    private static int openDiEventIfNeeded(
            Connection conn,
            PreparedStatement selOpen,
            PreparedStatement ins,
            Integer meterId,
            int eventEntityId,
            int plcId,
            int diAddress,
            int bitNo,
            String tagName,
            String itemName,
            String panelName,
            Timestamp measuredAt,
            Integer alarmMeterKey,
            String eventType,
            ModbusDiRuleSupport.DiRuleMeta diRuleMeta) throws Exception {
        String desc = ModbusDiRuleSupport.renderDiDescription(diRuleMeta, plcId, eventEntityId, diAddress, bitNo, tagName, itemName, panelName, eventType);
        String sev = ModbusDiRuleSupport.getDiSeverity(tagName);
        Long openEventId = findOpenDeviceEventId(selOpen, eventEntityId, eventType);
        int opened = 0;
        if (openEventId == null) {
            if (meterId != null && meterId.intValue() > 0) ins.setInt(1, meterId.intValue());
            else ins.setNull(1, Types.INTEGER);
            ins.setInt(2, eventEntityId);
            ins.setString(3, eventType);
            ins.setTimestamp(4, measuredAt);
            ins.setString(5, sev);
            ins.setString(6, desc);
            opened += ins.executeUpdate();
        }
        if ("ALARM".equalsIgnoreCase(sev) || "CRITICAL".equalsIgnoreCase(sev)) {
            openAlarmLogIfNeeded(conn, alarmMeterKey, eventType, sev, measuredAt, desc, itemName, panelName, diRuleMeta, eventType);
        }
        return opened;
    }

    private static int closeDiEventIfNeeded(
            Connection conn,
            PreparedStatement selOpen,
            PreparedStatement close,
            int eventEntityId,
            Timestamp measuredAt,
            Integer alarmMeterKey,
            String eventType,
            String itemName,
            String panelName) throws Exception {
        Long openEventId = findOpenDeviceEventId(selOpen, eventEntityId, eventType);
        int closed = 0;
        if (openEventId != null) {
            close.setTimestamp(1, measuredAt);
            close.setTimestamp(2, measuredAt);
            close.setTimestamp(3, measuredAt);
            close.setLong(4, openEventId.longValue());
            closed += close.executeUpdate();
        }
        closeAlarmLogIfOpen(conn, alarmMeterKey, eventType, measuredAt, itemName, panelName);
        return closed;
    }

    private static Long findOpenDeviceEventId(PreparedStatement selOpen, int eventEntityId, String eventType) throws Exception {
        selOpen.setInt(1, eventEntityId);
        selOpen.setString(2, eventType);
        try (ResultSet rs = selOpen.executeQuery()) {
            if (rs.next()) {
                return Long.valueOf(rs.getLong(1));
            }
        }
        return null;
    }

    private static void openAlarmLogIfNeeded(Connection conn, Integer meterId, String alarmType, String severity, Timestamp triggeredAt, String description, String itemName, String panelName, ModbusDiRuleSupport.DiRuleMeta ruleMeta, String sourceToken) throws Exception {
        if (meterId != null && meterId.intValue() > 0) {
            String selSql =
                "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
                "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
                "ORDER BY alarm_id DESC";
            try (PreparedStatement sel = conn.prepareStatement(selSql)) {
                sel.setInt(1, meterId.intValue());
                sel.setString(2, alarmType);
                try (ResultSet rs = sel.executeQuery()) {
                    if (rs.next()) return;
                }
            }
        } else {
            String descLike = ModbusDiRuleSupport.buildDiAlarmDescLike(itemName, panelName);
            String selSql =
                "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
                "WHERE meter_id IS NULL AND alarm_type = ? AND cleared_at IS NULL " +
                (descLike != null ? "AND description LIKE ? " : "") +
                "ORDER BY alarm_id DESC";
            try (PreparedStatement sel = conn.prepareStatement(selSql)) {
                sel.setString(1, alarmType);
                if (descLike != null) sel.setString(2, descLike);
                try (ResultSet rs = sel.executeQuery()) {
                    if (rs.next()) return;
                }
            }
        }
        String insSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description, rule_id, rule_code, metric_key, source_token) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
        try (PreparedStatement ins = conn.prepareStatement(insSql)) {
            if (meterId != null && meterId.intValue() > 0) ins.setInt(1, meterId.intValue());
            else ins.setNull(1, Types.INTEGER);
            ins.setString(2, alarmType);
            ins.setString(3, severity);
            ins.setTimestamp(4, triggeredAt);
            ins.setString(5, description);
            if (ruleMeta != null && ruleMeta.ruleId > 0) ins.setInt(6, ruleMeta.ruleId); else ins.setNull(6, Types.INTEGER);
            ins.setString(7, ruleMeta == null ? null : ruleMeta.ruleCode);
            ins.setString(8, ruleMeta == null ? null : ruleMeta.metricKey);
            ins.setString(9, sourceToken);
            ins.executeUpdate();
        }
    }

    private static void closeAlarmLogIfOpen(Connection conn, Integer meterId, String alarmType, Timestamp clearedAt, String itemName, String panelName) throws Exception {
        if (meterId != null && meterId.intValue() > 0) {
            String updSql =
                "UPDATE dbo.alarm_log SET cleared_at = ? " +
                "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL";
            try (PreparedStatement upd = conn.prepareStatement(updSql)) {
                upd.setTimestamp(1, clearedAt);
                upd.setInt(2, meterId.intValue());
                upd.setString(3, alarmType);
                upd.executeUpdate();
            }
        } else {
            String descLike = ModbusDiRuleSupport.buildDiAlarmDescLike(itemName, panelName);
            String updSql =
                "UPDATE dbo.alarm_log SET cleared_at = ? " +
                "WHERE meter_id IS NULL AND alarm_type = ? AND cleared_at IS NULL " +
                (descLike != null ? "AND description LIKE ? " : "");
            try (PreparedStatement upd = conn.prepareStatement(updSql)) {
                upd.setTimestamp(1, clearedAt);
                upd.setString(2, alarmType);
                if (descLike != null) upd.setString(3, descLike);
                upd.executeUpdate();
            }
        }
    }

    private static String asString(Object value) {
        return value == null ? "" : String.valueOf(value);
    }
}
