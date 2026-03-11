package epms.util;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import javax.naming.InitialContext;
import javax.sql.DataSource;

public final class AgentDbToolsCompat {
    private AgentDbToolsCompat() {
    }

    public static String getMeterListContext(String scopeToken, Integer topN) {
        List<String> tokens = splitScopeTokens(scopeToken);
        int n = topN != null ? topN.intValue() : 20;
        if (n < 1) n = 20;
        if (n > 100) n = 100;
        StringBuilder sql = new StringBuilder(
            "SELECT TOP " + n + " meter_id, name, panel_name, building_name, usage_type FROM dbo.meters WHERE 1=1 "
        );
        for (int i = 0; i < tokens.size(); i++) {
            sql.append("AND (UPPER(ISNULL(name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(panel_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(building_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(usage_type,'')) LIKE ?) ");
        }
        sql.append("ORDER BY meter_id ASC");
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            for (int i = 0; i < tokens.size(); i++) {
                String t = "%" + tokens.get(i).toUpperCase(Locale.ROOT) + "%";
                ps.setString(pi++, t);
                ps.setString(pi++, t);
                ps.setString(pi++, t);
                ps.setString(pi++, t);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Meter list]");
                if (!tokens.isEmpty()) sb.append(" scope=").append(String.join(",", tokens));
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append("meter_id=").append(rs.getInt("meter_id"))
                      .append(", ").append(clip(rs.getString("name"), 40))
                      .append(", panel=").append(clip(rs.getString("panel_name"), 40))
                      .append(", building=").append(clip(rs.getString("building_name"), 30))
                      .append(", usage=").append(clip(rs.getString("usage_type"), 30))
                      .append(";");
                }
                if (i == 0) return "[Meter list] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Meter list] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getMeterCountContext(String scopeToken) {
        List<String> tokens = splitScopeTokens(scopeToken);
        StringBuilder sql = new StringBuilder("SELECT COUNT(*) FROM dbo.meters WHERE 1=1 ");
        for (int i = 0; i < tokens.size(); i++) {
            sql.append("AND (UPPER(ISNULL(name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(panel_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(building_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(usage_type,'')) LIKE ?) ");
        }
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            for (int i = 0; i < tokens.size(); i++) {
                String t = "%" + tokens.get(i).toUpperCase(Locale.ROOT) + "%";
                ps.setString(pi++, t);
                ps.setString(pi++, t);
                ps.setString(pi++, t);
                ps.setString(pi++, t);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                int count = rs.next() ? rs.getInt(1) : 0;
                StringBuilder sb = new StringBuilder("[Meter count]");
                if (!tokens.isEmpty()) sb.append(" scope=").append(String.join(",", tokens));
                sb.append("; count=").append(count);
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Meter count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getPanelCountContext(String scopeToken) {
        List<String> tokens = splitScopeTokens(scopeToken);
        StringBuilder sql = new StringBuilder(
            "SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ISNULL(panel_name,''))), '')) FROM dbo.meters WHERE LTRIM(RTRIM(ISNULL(panel_name,''))) <> '' "
        );
        for (int i = 0; i < tokens.size(); i++) {
            sql.append("AND (UPPER(ISNULL(name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(panel_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(building_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(usage_type,'')) LIKE ?) ");
        }
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            for (int i = 0; i < tokens.size(); i++) {
                String t = "%" + tokens.get(i).toUpperCase(Locale.ROOT) + "%";
                ps.setString(pi++, t);
                ps.setString(pi++, t);
                ps.setString(pi++, t);
                ps.setString(pi++, t);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                int count = rs.next() ? rs.getInt(1) : 0;
                StringBuilder sb = new StringBuilder("[Panel count]");
                if (!tokens.isEmpty()) sb.append(" scope=").append(String.join(",", tokens));
                sb.append("; count=").append(count);
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Panel count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getBuildingCountContext() {
        String sql = "SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ISNULL(building_name,''))), '')) FROM dbo.meters WHERE LTRIM(RTRIM(ISNULL(building_name,''))) <> ''";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                int count = rs.next() ? rs.getInt(1) : 0;
                return "[Building count]; count=" + count;
            }
        } catch (Exception e) {
            return "[Building count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getUsageTypeCountContext() {
        String sql = "SELECT COUNT(DISTINCT NULLIF(LTRIM(RTRIM(ISNULL(usage_type,''))), '')) FROM dbo.meters WHERE LTRIM(RTRIM(ISNULL(usage_type,''))) <> ''";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                int count = rs.next() ? rs.getInt(1) : 0;
                return "[Usage count]; count=" + count;
            }
        } catch (Exception e) {
            return "[Usage count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getAlarmSeveritySummaryContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        int d = days != null ? days.intValue() : 7;
        boolean byRange = (fromTs != null || toTs != null);
        String sql;
        if (byRange) {
            StringBuilder sb = new StringBuilder("SELECT severity, COUNT(1) AS cnt FROM dbo.vw_alarm_log WHERE 1=1 ");
            if (fromTs != null) sb.append("AND triggered_at >= ? ");
            if (toTs != null) sb.append("AND triggered_at < ? ");
            sb.append("GROUP BY severity ORDER BY cnt DESC");
            sql = sb.toString();
        } else {
            sql = "SELECT severity, COUNT(1) AS cnt FROM dbo.vw_alarm_log WHERE triggered_at >= DATEADD(DAY, -?, GETDATE()) GROUP BY severity ORDER BY cnt DESC";
        }
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (byRange) {
                if (fromTs != null) ps.setTimestamp(pi++, fromTs);
                if (toTs != null) ps.setTimestamp(pi++, toTs);
            } else {
                ps.setInt(pi++, d);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Alarm severity summary] ");
                if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
                else sb.append("days=").append(d).append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(clip(rs.getString("severity"), 20)).append("=").append(rs.getLong("cnt")).append(";");
                }
                if (i == 0) return "[Alarm severity summary] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Alarm severity summary] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getAlarmTypeSummaryContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer meterId, boolean tripOnly, Integer topN) {
        int d = days != null ? days.intValue() : 7;
        int n = topN != null ? topN.intValue() : 20;
        if (n < 1) n = 20;
        if (n > 50) n = 50;
        boolean byRange = (fromTs != null || toTs != null);
        String meterName = getMeterNameById(meterId);
        boolean byMeter = meterId != null && meterName != null && !meterName.isEmpty();
        String scope = tripOnly ? "trip" : "all";

        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        if (byMeter) where.append("AND meter_name = ? ");
        if (tripOnly) where.append("AND UPPER(ISNULL(alarm_type,'')) LIKE '%TRIP%' ");
        if (byRange) {
            if (fromTs != null) where.append("AND triggered_at >= ? ");
            if (toTs != null) where.append("AND triggered_at < ? ");
        } else {
            where.append("AND triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
        }

        String sql =
            "SELECT TOP " + n + " ISNULL(NULLIF(LTRIM(RTRIM(alarm_type)),''), '(미분류)') AS alarm_type, COUNT(1) AS cnt " +
            "FROM dbo.vw_alarm_log " + where +
            "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(alarm_type)),''), '(미분류)') " +
            "ORDER BY cnt DESC, alarm_type ASC";

        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (byMeter) ps.setString(pi++, meterName);
            if (byRange) {
                if (fromTs != null) ps.setTimestamp(pi++, fromTs);
                if (toTs != null) ps.setTimestamp(pi++, toTs);
            } else {
                ps.setInt(pi++, d);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Alarm types] ");
                if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
                else sb.append("days=").append(d).append(";");
                sb.append(" scope=").append(scope).append(";");
                if (byMeter) sb.append(" meter_id=").append(meterId.intValue()).append("; meter_name=").append(meterName).append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append(clip(rs.getString("alarm_type"), 40))
                      .append("=")
                      .append(rs.getLong("cnt"))
                      .append(";");
                }
                if (i == 0) return "[Alarm types] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Alarm types] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getAlarmCountContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer meterId, String alarmTypeToken, String areaToken) {
        int d = days != null ? days.intValue() : 7;
        boolean byRange = (fromTs != null || toTs != null);
        String meterName = getMeterNameById(meterId);
        boolean byMeter = meterId != null && meterName != null && !meterName.isEmpty();
        String token = EpmsWebUtil.trimToNull(alarmTypeToken);
        String area = EpmsWebUtil.trimToNull(areaToken);
        List<String> areaTokens = splitScopeTokens(area);
        if (token != null) token = token.toUpperCase(Locale.ROOT);
        String scope = token == null ? "all" : ("type:" + token);

        StringBuilder sql = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al WHERE 1=1 ");
        if (byMeter) sql.append("AND al.meter_name = ? ");
        if (token != null) sql.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
        appendAreaConditions(sql, areaTokens, "al");
        if (byRange) {
            if (fromTs != null) sql.append("AND al.triggered_at >= ? ");
            if (toTs != null) sql.append("AND al.triggered_at < ? ");
        } else {
            sql.append("AND al.triggered_at >= DATEADD(DAY, -?, GETDATE())");
        }

        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            if (byMeter) ps.setString(pi++, meterName);
            if (token != null) ps.setString(pi++, "%" + token + "%");
            pi = bindAreaTokens(ps, pi, areaTokens);
            if (byRange) {
                if (fromTs != null) ps.setTimestamp(pi++, fromTs);
                if (toTs != null) ps.setTimestamp(pi++, toTs);
            } else {
                ps.setInt(pi++, d);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    long cnt = rs.getLong("cnt");
                    String meterTag = byMeter ? ("; meter_id=" + meterId.intValue() + "; meter_name=" + meterName) : "";
                    String areaTag = areaTokens.isEmpty() ? "" : ("; area=" + String.join(",", areaTokens));
                    if (byRange) return "[Alarm count] period=" + (periodLabel == null ? "-" : periodLabel) + "; scope=" + scope + areaTag + meterTag + "; count=" + cnt;
                    return "[Alarm count] days=" + d + "; scope=" + scope + areaTag + meterTag + "; count=" + cnt;
                }
            }
            return "[Alarm count] no data";
        } catch (Exception e) {
            return "[Alarm count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getOpenAlarmsContext(Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        int n = topN != null ? topN.intValue() : 10;
        StringBuilder where = new StringBuilder("WHERE cleared_at IS NULL ");
        if (fromTs != null) where.append("AND triggered_at >= ? ");
        if (toTs != null) where.append("AND triggered_at < ? ");
        String sql =
            "SELECT TOP " + n + " severity, alarm_type, meter_name, triggered_at, description " +
            "FROM dbo.vw_alarm_log " + where + "ORDER BY triggered_at DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Open alarms]");
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append(clip(rs.getString("severity"), 12)).append("/")
                      .append(clip(rs.getString("alarm_type"), 24))
                      .append(" @ ").append(clip(rs.getString("meter_name"), 24))
                      .append(", t=").append(fmtTs(rs.getTimestamp("triggered_at")))
                      .append(", desc=").append(clip(rs.getString("description"), 40))
                      .append(";");
                }
                if (i == 0) return "[Open alarms] none";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Open alarms] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getOpenAlarmCountContext(Timestamp fromTs, Timestamp toTs, String periodLabel, Integer meterId, String alarmTypeToken, String areaToken) {
        String meterName = getMeterNameById(meterId);
        boolean byMeter = meterId != null && meterName != null && !meterName.isEmpty();
        String token = EpmsWebUtil.trimToNull(alarmTypeToken);
        String area = EpmsWebUtil.trimToNull(areaToken);
        List<String> areaTokens = splitScopeTokens(area);
        if (token != null) token = token.toUpperCase(Locale.ROOT);
        boolean byRange = (fromTs != null || toTs != null);
        StringBuilder sql = new StringBuilder("SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log al WHERE al.cleared_at IS NULL ");
        if (byMeter) sql.append("AND al.meter_name = ? ");
        if (token != null) sql.append("AND UPPER(ISNULL(alarm_type,'')) LIKE ? ");
        appendAreaConditions(sql, areaTokens, "al");
        if (byRange) {
            if (fromTs != null) sql.append("AND al.triggered_at >= ? ");
            if (toTs != null) sql.append("AND al.triggered_at < ? ");
        }
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            if (byMeter) ps.setString(pi++, meterName);
            if (token != null) ps.setString(pi++, "%" + token + "%");
            pi = bindAreaTokens(ps, pi, areaTokens);
            if (byRange) {
                if (fromTs != null) ps.setTimestamp(pi++, fromTs);
                if (toTs != null) ps.setTimestamp(pi++, toTs);
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                int count = rs.next() ? rs.getInt(1) : 0;
                StringBuilder sb = new StringBuilder("[Open alarm count]");
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
                if (token != null) sb.append("; type=").append(token);
                if (area != null && !area.isEmpty()) sb.append("; scope=").append(area);
                sb.append("; count=").append(count);
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Open alarm count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getBuildingPowerTopNContext(Integer month, Integer topN) {
        int targetMonth = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int n = topN != null ? topN.intValue() : 10;
        if (n < 1) n = 10;
        if (n > 20) n = 20;
        String sql =
            "SELECT TOP " + n + " building_name, AVG(CAST(active_power_total AS float)) AS avg_kw, " +
            "SUM(CAST(ISNULL(energy_consumed_total, 0) AS float)) AS sum_kwh " +
            "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            "WHERE MONTH(ms.measured_at) = ? AND NULLIF(LTRIM(RTRIM(ISNULL(m.building_name,''))), '') IS NOT NULL " +
            "GROUP BY building_name ORDER BY avg_kw DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, targetMonth);
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Building power TOP] period=")
                    .append(java.time.LocalDate.now().getYear()).append("-")
                    .append(String.format(Locale.ROOT, "%02d", targetMonth)).append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append(clip(rs.getString("building_name"), 30))
                      .append(": avg_kw=").append(fmtNum(rs.getDouble("avg_kw")))
                      .append(", sum_kwh=").append(fmtNum(rs.getDouble("sum_kwh"))).append(";");
                }
                if (i == 0) return "[Building power TOP] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Building power TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getPanelLatestStatusContext(String panelTokenCsv, Integer topN) {
        List<String> panelTokens = splitPanelTokens(panelTokenCsv);
        if (panelTokens.isEmpty()) return "[Panel latest status] panel token required";
        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        for (int i = 0; i < panelTokens.size(); i++) {
            where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
        }
        String sql =
            "WITH latest AS ( " +
            " SELECT m.meter_id, m.name, m.panel_name, ms.measured_at, " +
            " ms.average_voltage, ms.line_voltage_avg, ms.phase_voltage_avg, ms.voltage_ab, " +
            " ms.average_current, " +
            " COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) AS power_factor, " +
            " ms.frequency, ms.active_power_total, ms.reactive_power_total, " +
            " ROW_NUMBER() OVER (PARTITION BY m.meter_id ORDER BY ms.measured_at DESC) AS rn " +
            " FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            where.toString() +
            "), tree_edges AS ( " +
            " SELECT t.parent_meter_id, t.child_meter_id " +
            " FROM dbo.meter_tree t WHERE t.is_active = 1 " +
            " AND EXISTS (SELECT 1 FROM latest l1 WHERE l1.rn=1 AND l1.meter_id = t.parent_meter_id) " +
            " AND EXISTS (SELECT 1 FROM latest l2 WHERE l2.rn=1 AND l2.meter_id = t.child_meter_id) " +
            "), ranked AS ( " +
            " SELECT *, " +
            " CASE WHEN EXISTS (SELECT 1 FROM tree_edges te WHERE te.parent_meter_id = latest.meter_id) " +
            "      AND NOT EXISTS (SELECT 1 FROM tree_edges te WHERE te.child_meter_id = latest.meter_id) THEN 1 ELSE 0 END AS is_tree_main, " +
            " CASE WHEN EXISTS (SELECT 1 FROM tree_edges te WHERE te.parent_meter_id = latest.meter_id) " +
            "      AND NOT EXISTS (SELECT 1 FROM tree_edges te WHERE te.child_meter_id = latest.meter_id) THEN 0 " +
            "      WHEN NOT EXISTS (SELECT 1 FROM tree_edges te WHERE te.child_meter_id = latest.meter_id) THEN 1 " +
            "      WHEN EXISTS (SELECT 1 FROM tree_edges te WHERE te.parent_meter_id = latest.meter_id) THEN 2 ELSE 3 END AS main_rank, " +
            " COUNT(*) OVER() AS panel_meter_count FROM latest WHERE rn=1 ) " +
            "SELECT TOP 1 meter_id, name, panel_name, measured_at, average_voltage, line_voltage_avg, phase_voltage_avg, voltage_ab, is_tree_main, average_current, power_factor, frequency, active_power_total, reactive_power_total, panel_meter_count " +
            "FROM ranked ORDER BY main_rank ASC, measured_at DESC, meter_id ASC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            for (String token : panelTokens) {
                ps.setString(pi++, "%" + token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT) + "%");
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) return "[Panel latest status] no data";
                int meterId = rs.getInt("meter_id");
                String meterName = clip(rs.getString("name"), 30);
                String panelName = clip(rs.getString("panel_name"), 30);
                Timestamp ts = rs.getTimestamp("measured_at");
                double v = chooseVoltage(rs.getDouble("average_voltage"), rs.getDouble("line_voltage_avg"), rs.getDouble("phase_voltage_avg"), rs.getDouble("voltage_ab"));
                double c = rs.getDouble("average_current");
                double pf = rs.getDouble("power_factor");
                double hz = rs.getDouble("frequency");
                double kw = rs.getDouble("active_power_total");
                double kvar = rs.getDouble("reactive_power_total");
                int isTreeMain = rs.getInt("is_tree_main");
                int meterCount = rs.getInt("panel_meter_count");
                return "[Panel latest status] panel=" + panelTokens
                    + "; meter_count=" + meterCount
                    + "; is_tree_main=" + isTreeMain
                    + "; main_meter_id=" + meterId
                    + ", " + (meterName.isEmpty() ? "-" : meterName)
                    + ", panel=" + (panelName.isEmpty() ? "-" : panelName)
                    + ", t=" + fmtTs(ts)
                    + ", V=" + fmtNum(v)
                    + ", I=" + fmtNum(c)
                    + ", PF=" + fmtNum(pf)
                    + ", Hz=" + fmtNum(hz)
                    + ", kW=" + fmtNum(kw)
                    + ", kVAr=" + fmtNum(kvar)
                    + ";";
            }
        } catch (Exception e) {
            return "[Panel latest status] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getHarmonicExceedListContext(Double thdV, Double thdI, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        double v = thdV != null ? thdV.doubleValue() : 3.0d;
        double i = thdI != null ? thdI.doubleValue() : 20.0d;
        int n = topN != null ? topN.intValue() : 10;
        StringBuilder where = new StringBuilder(
            "WHERE (thd_voltage_a > ? OR thd_voltage_b > ? OR thd_voltage_c > ? OR thd_current_a > ? OR thd_current_b > ? OR thd_current_c > ?) "
        );
        if (fromTs != null) where.append("AND measured_at >= ? ");
        if (toTs != null) where.append("AND measured_at < ? ");
        String sql =
            "WITH filtered AS ( " +
            "SELECT meter_id, meter_name, panel_name, measured_at, " +
            "thd_voltage_a, thd_voltage_b, thd_voltage_c, thd_current_a, thd_current_b, thd_current_c, " +
            "ROW_NUMBER() OVER (PARTITION BY meter_id ORDER BY measured_at DESC) AS rn " +
            "FROM dbo.vw_harmonic_measurements " + where +
            ") " +
            "SELECT TOP " + n + " meter_id, meter_name, panel_name, measured_at, " +
            "thd_voltage_a, thd_voltage_b, thd_voltage_c, thd_current_a, thd_current_b, thd_current_c " +
            "FROM filtered WHERE rn=1 ORDER BY measured_at DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            ps.setDouble(pi++, v); ps.setDouble(pi++, v); ps.setDouble(pi++, v);
            ps.setDouble(pi++, i); ps.setDouble(pi++, i); ps.setDouble(pi++, i);
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Harmonic exceed] thdV>").append(fmtNum(v)).append(", thdI>").append(fmtNum(i));
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(", period=").append(periodLabel);
                sb.append(";");
                int idx = 0;
                while (rs.next()) {
                    idx++;
                    sb.append(" ").append(idx).append(")")
                      .append("meter_id=").append(rs.getInt("meter_id"))
                      .append(", ").append(clip(rs.getString("meter_name"), 24))
                      .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                      .append(", TV=").append(fmtNum(rs.getDouble("thd_voltage_a"))).append("/").append(fmtNum(rs.getDouble("thd_voltage_b"))).append("/").append(fmtNum(rs.getDouble("thd_voltage_c")))
                      .append(", TI=").append(fmtNum(rs.getDouble("thd_current_a"))).append("/").append(fmtNum(rs.getDouble("thd_current_b"))).append("/").append(fmtNum(rs.getDouble("thd_current_c")))
                      .append(";");
                }
                if (idx == 0) return "[Harmonic exceed] none";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Harmonic exceed] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getFrequencyOutlierListContext(Double thresholdHz, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        double hz = thresholdHz != null ? thresholdHz.doubleValue() : 59.5d;
        int n = topN != null ? topN.intValue() : 10;
        StringBuilder where = new StringBuilder("WHERE (ms.frequency < ? OR ms.frequency > ?) ");
        if (fromTs != null) where.append("AND ms.measured_at >= ? ");
        if (toTs != null) where.append("AND ms.measured_at < ? ");
        String sql =
            "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, ms.frequency " +
            "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            where + "ORDER BY ms.measured_at DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            ps.setDouble(pi++, hz);
            ps.setDouble(pi++, 60.5d);
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Frequency outlier] threshold<").append(fmtNum(hz)).append(" or >60.50");
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(", period=").append(periodLabel);
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append("meter_id=").append(rs.getInt("meter_id"))
                      .append(", ").append(clip(rs.getString("meter_name"), 24))
                      .append(", Hz=").append(fmtNum(rs.getDouble("frequency")))
                      .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                      .append(";");
                }
                if (i == 0) return "[Frequency outlier] none";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Frequency outlier] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getVoltageUnbalanceTopNContext(Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        int n = topN != null ? topN.intValue() : 10;
        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        if (fromTs != null) where.append("AND ms.measured_at >= ? ");
        if (toTs != null) where.append("AND ms.measured_at < ? ");
        String sql =
            "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, ms.measured_at, ms.voltage_unbalance_rate " +
            "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            where + "ORDER BY ms.voltage_unbalance_rate DESC, ms.measured_at DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Voltage unbalance TOP ").append(n).append("]");
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append("meter_id=").append(rs.getInt("meter_id"))
                      .append(", ").append(clip(rs.getString("meter_name"), 24))
                      .append(", unb=").append(fmtNum(rs.getDouble("voltage_unbalance_rate")))
                      .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                      .append(";");
                }
                if (i == 0) return "[Voltage unbalance TOP] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Voltage unbalance TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getPowerFactorOutlierListContext(Double pfThreshold, Integer topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        double th = pfThreshold != null ? pfThreshold.doubleValue() : 0.9d;
        int n = topN != null ? topN.intValue() : 10;
        StringBuilder srcWhere = new StringBuilder("WHERE 1=1 ");
        if (fromTs != null) srcWhere.append("AND ms.measured_at >= ? ");
        if (toTs != null) srcWhere.append("AND ms.measured_at < ? ");
        String sql =
            "WITH latest AS (" +
            " SELECT ms.*, ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
            " FROM dbo.measurements ms " + srcWhere +
            ") " +
            "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
            "COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) AS pf " +
            "FROM latest ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            "WHERE ms.rn=1 " +
            "AND COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) > 0 " +
            "AND COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) < ? " +
            "ORDER BY pf ASC, ms.measured_at DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setDouble(pi++, th);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Power factor outlier] pf<").append(fmtNum(th));
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(", period=").append(periodLabel);
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append("meter_id=").append(rs.getInt("meter_id"))
                      .append(", ").append(clip(rs.getString("meter_name"), 24))
                      .append(", panel=").append(clip(rs.getString("panel_name"), 24))
                      .append(", pf=").append(fmtNum(rs.getDouble("pf")))
                      .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                      .append(";");
                }
                if (i == 0) return "[Power factor outlier] none";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Power factor outlier] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    private static Connection openDbConnection() throws Exception {
        InitialContext ic = new InitialContext();
        DataSource ds = (DataSource) ic.lookup("java:comp/env/jdbc/epms");
        return ds.getConnection();
    }

    private static List<String> splitScopeTokens(String areaToken) {
        ArrayList<String> out = new ArrayList<String>();
        String raw = EpmsWebUtil.trimToNull(areaToken);
        if (raw == null) return out;
        String norm = raw.replaceAll("[\"'`]", " ").trim();
        if (norm.isEmpty()) return out;
        String[] parts = norm.split("\\s*(?:\\uC758|\\uACFC|\\uC640|\\uBC0F|\\uADF8\\uB9AC\\uACE0|,|/|\\\\|\\s+)\\s*");
        LinkedHashSet<String> uniq = new LinkedHashSet<String>();
        for (int i = 0; i < parts.length; i++) {
            String p = EpmsWebUtil.trimToNull(parts[i]);
            if (p == null) continue;
            String n = normalizeIntent(p);
            if (n.length() < 2) continue;
            if ("\uC54C\uB78C".equals(n) || "\uACC4\uCE21\uAE30".equals(n) || "\uAD00\uB828\uB41C".equals(n)) continue;
            uniq.add(p);
        }
        out.addAll(uniq);
        if (out.isEmpty()) out.add(norm);
        return out;
    }

    private static String normalizeIntent(String s) {
        if (s == null) return "";
        return s.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }

    private static List<String> splitPanelTokens(String panelTokenCsv) {
        ArrayList<String> out = new ArrayList<String>();
        String raw = EpmsWebUtil.trimToNull(panelTokenCsv);
        if (raw == null) return out;
        for (String p : raw.split("\\s*,\\s*")) {
            String t = EpmsWebUtil.trimToNull(p);
            if (t != null) out.add(t);
        }
        return out;
    }

    private static String getMeterNameById(Integer meterId) {
        if (meterId == null) return null;
        String sql = "SELECT TOP 1 name FROM dbo.meters WHERE meter_id = ?";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return EpmsWebUtil.trimToNull(rs.getString("name"));
            }
        } catch (Exception ignore) {
        }
        return null;
    }

    private static void appendAreaConditions(StringBuilder sql, List<String> areaTokens, String alias) {
        if (areaTokens == null || areaTokens.isEmpty()) return;
        for (int i = 0; i < areaTokens.size(); i++) {
            sql.append("AND (");
            sql.append("UPPER(ISNULL(").append(alias).append(".meter_name,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(").append(alias).append(".description,'')) LIKE ? ");
            sql.append("OR UPPER(ISNULL(").append(alias).append(".alarm_type,'')) LIKE ? ");
            sql.append(") ");
        }
    }

    private static int bindAreaTokens(PreparedStatement ps, int startIndex, List<String> areaTokens) throws Exception {
        int pi = startIndex;
        if (areaTokens == null) return pi;
        for (String token : areaTokens) {
            String t = "%" + token.toUpperCase(Locale.ROOT) + "%";
            ps.setString(pi++, t);
            ps.setString(pi++, t);
            ps.setString(pi++, t);
        }
        return pi;
    }

    private static String clip(String s, int maxLen) {
        if (s == null) return "-";
        String t = s.replaceAll("\\s+", " ").trim();
        if (t.isEmpty()) return "-";
        return t.length() > maxLen ? t.substring(0, maxLen) + "..." : t;
    }

    private static String fmtTs(Timestamp ts) {
        if (ts == null) return "-";
        java.time.LocalDateTime ldt = ts.toLocalDateTime();
        return java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").format(ldt);
    }

    private static double chooseVoltage(double averageVoltage, double lineVoltageAvg, double phaseVoltageAvg, double voltageAb) {
        if (!Double.isNaN(averageVoltage) && averageVoltage > 0.0d) return averageVoltage;
        if (!Double.isNaN(lineVoltageAvg) && lineVoltageAvg > 0.0d) return lineVoltageAvg;
        if (!Double.isNaN(phaseVoltageAvg) && phaseVoltageAvg > 0.0d) return phaseVoltageAvg;
        return voltageAb;
    }

    private static String fmtNum(double v) {
        if (Double.isNaN(v) || Double.isInfinite(v)) return "-";
        synchronized (DF) {
            return DF.format(v);
        }
    }

    private static final java.text.DecimalFormat DF = new java.text.DecimalFormat("0.00");
}
