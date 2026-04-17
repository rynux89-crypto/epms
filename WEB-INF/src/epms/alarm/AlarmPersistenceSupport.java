package epms.alarm;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

public final class AlarmPersistenceSupport {
    private AlarmPersistenceSupport() {
    }

    public static Connection createConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public static void ensureAlarmSchema(Connection conn) {
        if (conn == null) return;
        String sql =
            "IF COL_LENGTH('dbo.alarm_log','rule_id') IS NULL ALTER TABLE dbo.alarm_log ADD rule_id INT NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','rule_code') IS NULL ALTER TABLE dbo.alarm_log ADD rule_code VARCHAR(50) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','metric_key') IS NULL ALTER TABLE dbo.alarm_log ADD metric_key VARCHAR(100) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','source_token') IS NULL ALTER TABLE dbo.alarm_log ADD source_token VARCHAR(120) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','measured_value') IS NULL ALTER TABLE dbo.alarm_log ADD measured_value FLOAT NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','operator') IS NULL ALTER TABLE dbo.alarm_log ADD operator VARCHAR(10) NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','threshold1') IS NULL ALTER TABLE dbo.alarm_log ADD threshold1 FLOAT NULL; " +
            "IF COL_LENGTH('dbo.alarm_log','threshold2') IS NULL ALTER TABLE dbo.alarm_log ADD threshold2 FLOAT NULL;";
        try (Statement st = conn.createStatement()) {
            st.execute(sql);
        } catch (Exception ignore) {
        }
    }

    public static Long findOpenEventId(PreparedStatement ps, int eventEntityId, String eventType) throws Exception {
        ps.setInt(1, eventEntityId);
        ps.setString(2, eventType);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return rs.getLong(1);
        }
        return null;
    }

    public static Long findOpenAlarmId(PreparedStatement ps, int meterId, String alarmType) throws Exception {
        ps.setInt(1, meterId);
        ps.setString(2, alarmType);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) return rs.getLong(1);
        }
        return null;
    }

    public static List<Long> findOpenEventIds(PreparedStatement ps, int eventEntityId, String eventType) throws Exception {
        List<Long> out = new ArrayList<>();
        ps.setInt(1, eventEntityId);
        ps.setString(2, eventType);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) out.add(Long.valueOf(rs.getLong(1)));
        }
        return out;
    }

    public static List<Long> findOpenAlarmIds(PreparedStatement ps, int meterId, String alarmType) throws Exception {
        List<Long> out = new ArrayList<>();
        ps.setInt(1, meterId);
        ps.setString(2, alarmType);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) out.add(Long.valueOf(rs.getLong(1)));
        }
        return out;
    }

    public static int closeOpenEvent(PreparedStatement close, Timestamp measuredAt, Long eventId) throws Exception {
        if (eventId == null) return 0;
        close.setTimestamp(1, measuredAt);
        close.setTimestamp(2, measuredAt);
        close.setTimestamp(3, measuredAt);
        close.setLong(4, eventId.longValue());
        return close.executeUpdate();
    }

    public static void clearOpenAlarm(PreparedStatement clearAlarm, Timestamp measuredAt, Long alarmId) throws Exception {
        if (alarmId == null) return;
        clearAlarm.setTimestamp(1, measuredAt);
        clearAlarm.setLong(2, alarmId.longValue());
        clearAlarm.executeUpdate();
    }

    public static int insertDeviceEvent(
            PreparedStatement ins,
            Integer meterId,
            int eventEntityId,
            String eventType,
            Timestamp measuredAt,
            String severity,
            String description) throws Exception {
        if (meterId != null && meterId.intValue() > 0) ins.setInt(1, meterId.intValue());
        else ins.setNull(1, Types.INTEGER);
        ins.setInt(2, eventEntityId);
        ins.setString(3, eventType);
        ins.setTimestamp(4, measuredAt);
        ins.setString(5, severity);
        ins.setString(6, description);
        int updated = ins.executeUpdate();
        if (updated > 0) {
            AlarmFacade.queueOpenDiEvent(eventEntityId, eventType, severity, description);
        }
        return updated;
    }

    public static void insertDiAlarm(
            PreparedStatement insAlarm,
            int deviceId,
            String eventType,
            String severity,
            Timestamp measuredAt,
            String description) throws Exception {
        insAlarm.setInt(1, deviceId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        insAlarm.setNull(6, Types.INTEGER);
        insAlarm.setNull(7, Types.VARCHAR);
        insAlarm.setNull(8, Types.VARCHAR);
        insAlarm.setNull(9, Types.VARCHAR);
        insAlarm.setNull(10, Types.FLOAT);
        insAlarm.setNull(11, Types.VARCHAR);
        insAlarm.setNull(12, Types.FLOAT);
        insAlarm.setNull(13, Types.FLOAT);
        insAlarm.executeUpdate();
        AlarmFacade.queueOpenDiAlarm(deviceId, eventType, severity, description);
    }

    public static void insertAiAlarm(
            PreparedStatement insAlarm,
            int meterId,
            String eventType,
            String severity,
            Timestamp measuredAt,
            String description,
            AlarmRuleDef rule,
            double value,
            String resolvedSourceToken) throws Exception {
        insAlarm.setInt(1, meterId);
        insAlarm.setString(2, eventType);
        insAlarm.setString(3, severity);
        insAlarm.setTimestamp(4, measuredAt);
        insAlarm.setString(5, description);
        insAlarm.setInt(6, rule.getRuleId());
        insAlarm.setString(7, rule.getRuleCode());
        insAlarm.setString(8, rule.getMetricKey());
        insAlarm.setString(9, (resolvedSourceToken == null || resolvedSourceToken.trim().isEmpty()) ? rule.getMetricKey() : resolvedSourceToken);
        insAlarm.setDouble(10, value);
        insAlarm.setString(11, rule.getOperator());
        if (rule.getThreshold1() == null) insAlarm.setNull(12, Types.FLOAT); else insAlarm.setDouble(12, rule.getThreshold1().doubleValue());
        if (rule.getThreshold2() == null) insAlarm.setNull(13, Types.FLOAT); else insAlarm.setDouble(13, rule.getThreshold2().doubleValue());
        insAlarm.executeUpdate();
        AlarmFacade.queueOpenAiAlarm(meterId, eventType, severity, description);
    }
}
