package epms.util;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import javax.naming.InitialContext;
import javax.sql.DataSource;

public final class AgentDbTools {
    private AgentDbTools() {
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

    public static String getUsageTypeListContext(Integer topN) {
        int n = topN != null ? topN.intValue() : 50;
        if (n < 1) n = 50;
        if (n > 100) n = 100;
        String sql =
            "SELECT TOP " + n + " LTRIM(RTRIM(ISNULL(usage_type,''))) AS usage_type " +
            "FROM dbo.meters " +
            "WHERE LTRIM(RTRIM(ISNULL(usage_type,''))) <> '' " +
            "GROUP BY LTRIM(RTRIM(ISNULL(usage_type,''))) " +
            "ORDER BY LTRIM(RTRIM(ISNULL(usage_type,''))) ASC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Usage type list];");
                int i = 0;
                while (rs.next()) {
                    String usageType = clip(rs.getString("usage_type"), 40);
                    if (usageType == null || usageType.trim().isEmpty()) continue;
                    i++;
                    sb.append(" ").append(i).append(")").append(usageType.trim()).append(";");
                }
                if (i == 0) return "[Usage type list] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Usage type list] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getRecentMeterContext(Integer meterId, String panelTokenCsv) {
        List<String> panelTokens = splitPanelTokens(panelTokenCsv);
        String baseSelect =
            "SELECT TOP %d m.meter_id, m.name AS meter_name, ms.measured_at, " +
            "m.panel_name, ms.average_voltage, ms.line_voltage_avg, ms.phase_voltage_avg, ms.voltage_ab, ms.average_current, " +
            "COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c) / 3.0) AS power_factor, " +
            "ms.active_power_total, ms.reactive_power_total, ms.frequency, ms.quality_status " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id ";

        boolean filtered = meterId != null;
        boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
        StringBuilder where = new StringBuilder();
        if (filtered) {
            where.append("WHERE m.meter_id = ? ");
        } else if (panelFiltered) {
            where.append("WHERE 1=1 ");
            for (int i = 0; i < panelTokens.size(); i++) {
                where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
            }
        }

        int topN = filtered ? 1 : (panelFiltered ? 1 : 3);
        String sql = String.format(baseSelect, topN) + where.toString() + "ORDER BY ms.measurement_id DESC";
        StringBuilder sb = new StringBuilder(filtered
            ? "[Latest meter readings: meter_id=" + meterId + "]"
            : (panelFiltered ? "[Latest meter readings: panel=" + panelTokens + "]" : "[Latest meter readings]"));
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            if (filtered) {
                ps.setInt(1, meterId.intValue());
            } else if (panelFiltered) {
                int pi = 1;
                for (String token : panelTokens) {
                    String normalized = token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT);
                    ps.setString(pi++, "%" + normalized + "%");
                }
            }
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                int i = 0;
                while (rs.next()) {
                    i++;
                    double v = chooseVoltage(
                        rs.getDouble("average_voltage"),
                        rs.getDouble("line_voltage_avg"),
                        rs.getDouble("phase_voltage_avg"),
                        rs.getDouble("voltage_ab")
                    );
                    double c = rs.getDouble("average_current");
                    double pf = rs.getDouble("power_factor");
                    double kw = rs.getDouble("active_power_total");
                    double kvar = rs.getDouble("reactive_power_total");
                    double hz = rs.getDouble("frequency");
                    boolean noSignal =
                        Math.abs(v) < 0.0001d &&
                        Math.abs(c) < 0.0001d &&
                        Math.abs(pf) < 0.0001d &&
                        Math.abs(kw) < 0.0001d &&
                        Math.abs(kvar) < 0.0001d;

                    sb.append(" ")
                        .append(i).append(")")
                        .append("meter_id=").append(rs.getInt("meter_id")).append(", ")
                        .append(clip(rs.getString("meter_name"), 40))
                        .append(", panel=").append(clip(rs.getString("panel_name"), 60))
                        .append(" @ ").append(fmtTs(rs.getTimestamp("measured_at")))
                        .append(" V=").append(fmtNum(v))
                        .append(", I=").append(fmtNum(c))
                        .append(", PF=").append(fmtNum(pf))
                        .append(", kW=").append(fmtNum(kw))
                        .append(", kVAr=").append(fmtNum(kvar))
                        .append(", Hz=").append(fmtNum(hz))
                        .append(", QS=").append(clip(rs.getString("quality_status"), 20));
                    if (noSignal) sb.append(", STATE=NO_SIGNAL");
                    sb.append(";");
                }
                if (i == 0) {
                    return filtered
                        ? "[Latest meter readings: meter_id=" + meterId + "] no data"
                        : (panelFiltered
                            ? "[Latest meter readings: panel=" + panelTokens + "] no data"
                            : "[Latest meter readings] no data");
                }
            }
        } catch (Exception e) {
            return (filtered
                ? "[Latest meter readings: meter_id=" + meterId + "]"
                : (panelFiltered ? "[Latest meter readings: panel=" + panelTokens + "]" : "[Latest meter readings]"))
                + " unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
        return sb.toString();
    }

    public static String getMonthlyAvgFrequencyContext(Integer meterId, Integer month) {
        Integer targetMonth = month;
        int year = java.time.LocalDate.now().getYear();

        try (Connection conn = openDbConnection()) {
            if (targetMonth == null) {
                String ymSql =
                    "SELECT TOP 1 YEAR(measured_at) AS yy, MONTH(measured_at) AS mm " +
                    "FROM dbo.measurements " +
                    (meterId != null ? "WHERE meter_id = ? " : "") +
                    "ORDER BY measurement_id DESC";
                try (PreparedStatement ps = conn.prepareStatement(ymSql)) {
                    if (meterId != null) ps.setInt(1, meterId.intValue());
                    ps.setQueryTimeout(5);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            year = rs.getInt("yy");
                            targetMonth = Integer.valueOf(rs.getInt("mm"));
                        }
                    }
                }
            } else {
                String ySql =
                    "SELECT TOP 1 YEAR(measured_at) AS yy " +
                    "FROM dbo.measurements " +
                    "WHERE MONTH(measured_at)=? " +
                    (meterId != null ? "AND meter_id=? " : "") +
                    "ORDER BY yy DESC";
                try (PreparedStatement ps = conn.prepareStatement(ySql)) {
                    int pi = 1;
                    ps.setInt(pi++, targetMonth.intValue());
                    if (meterId != null) ps.setInt(pi++, meterId.intValue());
                    ps.setQueryTimeout(5);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) year = rs.getInt("yy");
                    }
                }
            }

            if (targetMonth == null) return "[Monthly frequency avg] no data";

            String sql =
                "SELECT AVG(CAST(frequency AS float)) AS avg_hz, " +
                "MIN(CAST(frequency AS float)) AS min_hz, " +
                "MAX(CAST(frequency AS float)) AS max_hz, " +
                "COUNT(1) AS sample_count " +
                "FROM dbo.measurements " +
                "WHERE YEAR(measured_at)=? AND MONTH(measured_at)=? " +
                (meterId != null ? "AND meter_id=? " : "");
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                int pi = 1;
                ps.setInt(pi++, year);
                ps.setInt(pi++, targetMonth.intValue());
                if (meterId != null) ps.setInt(pi++, meterId.intValue());
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        long n = rs.getLong("sample_count");
                        String period = year + "-" + String.format(Locale.US, "%02d", targetMonth.intValue());
                        if (n <= 0) {
                            return "[Monthly frequency avg] meter_id=" + (meterId == null ? "-" : meterId)
                                + ", period=" + period + ", no data";
                        }
                        return "[Monthly frequency avg] meter_id=" + (meterId == null ? "-" : meterId)
                            + ", period=" + period
                            + ", avg_hz=" + fmtNum(rs.getDouble("avg_hz"))
                            + ", min_hz=" + fmtNum(rs.getDouble("min_hz"))
                            + ", max_hz=" + fmtNum(rs.getDouble("max_hz"))
                            + ", samples=" + n;
                    }
                }
            }
            return "[Monthly frequency avg] no data";
        } catch (Exception e) {
            return "[Monthly frequency avg] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getRecentAlarmContext() {
        String unresolvedSql =
            "SELECT COUNT(1) AS cnt FROM dbo.vw_alarm_log WHERE cleared_at IS NULL";
        String latestSql =
            "SELECT TOP 5 severity, alarm_type, meter_name, triggered_at, cleared_at, description " +
            "FROM dbo.vw_alarm_log ORDER BY triggered_at DESC";
        try (Connection conn = openDbConnection()) {
            int unresolved = 0;
            try (PreparedStatement ps = conn.prepareStatement(unresolvedSql)) {
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) unresolved = rs.getInt("cnt");
                }
            }

            StringBuilder sb = new StringBuilder("[Latest alarms]");
            sb.append(" unresolved=").append(unresolved).append(";");
            try (PreparedStatement ps = conn.prepareStatement(latestSql)) {
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    int i = 0;
                    while (rs.next()) {
                        i++;
                        String sev = clip(rs.getString("severity"), 20);
                        String type = clip(rs.getString("alarm_type"), 40);
                        String meter = clip(rs.getString("meter_name"), 40);
                        Timestamp trig = rs.getTimestamp("triggered_at");
                        Timestamp clr = rs.getTimestamp("cleared_at");
                        String desc = clip(rs.getString("description"), 80);

                        sb.append(" ")
                            .append(i).append(")")
                            .append("-".equals(sev) ? "-" : sev)
                            .append("/")
                            .append("-".equals(type) ? "-" : type)
                            .append(" @ ").append("-".equals(meter) ? "-" : meter)
                            .append(" t=").append(fmtTs(trig))
                            .append(", cleared=").append(clr == null ? "N" : "Y");
                        if (!"-".equals(desc)) sb.append(", desc=").append(desc);
                        sb.append(";");
                    }
                    if (i == 0) sb.append(" no recent alarm;");
                }
            }
            return sb.toString();
        } catch (Exception e) {
            return "[Latest alarms] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getPerMeterPowerContext() {
        String sql =
            "SELECT m.meter_id, m.name AS meter_name, m.panel_name, " +
            "x.measured_at, x.active_power_total, x.energy_consumed_total " +
            "FROM dbo.meters m " +
            "OUTER APPLY ( " +
            "  SELECT TOP 1 measured_at, active_power_total, energy_consumed_total " +
            "  FROM dbo.measurements ms WHERE ms.meter_id = m.meter_id ORDER BY ms.measured_at DESC " +
            ") x " +
            "ORDER BY m.meter_id";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(20);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Per-meter latest power]");
                int i = 0;
                int maxLines = 30;
                while (rs.next()) {
                    i++;
                    if (i <= maxLines) {
                        int meterId = rs.getInt("meter_id");
                        String meterName = clip(rs.getString("meter_name"), 40);
                        String panel = clip(rs.getString("panel_name"), 40);
                        Timestamp ts = rs.getTimestamp("measured_at");
                        double kw = rs.getDouble("active_power_total");
                        double kwh = rs.getDouble("energy_consumed_total");
                        sb.append(" ")
                            .append(i).append(")")
                            .append("meter_id=").append(meterId)
                            .append(", ").append("-".equals(meterName) ? "-" : meterName)
                            .append(", panel=").append("-".equals(panel) ? "-" : panel)
                            .append(", t=").append(fmtTs(ts))
                            .append(", kW=").append(fmtNum(kw))
                            .append(", kWh=").append(fmtNum(kwh))
                            .append(";");
                    }
                }
                if (i == 0) return "[Per-meter latest power] no data";
                if (i > maxLines) sb.append(" ... total=").append(i).append(" meters");
                return sb.toString();
            }
        } catch (Exception e) {
            String msg = e.getMessage() == null ? "" : (" (" + clip(e.getMessage(), 80) + ")");
            return "[Per-meter latest power] unavailable: " + clip(e.getClass().getSimpleName(), 24) + msg;
        }
    }

    public static String getHarmonicContext(Integer meterId, String panelTokenCsv) {
        List<String> panelTokens = splitPanelTokens(panelTokenCsv);
        String base =
            "SELECT TOP 1 meter_id, meter_name, panel_name, measured_at, " +
            "thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
            "thd_current_a, thd_current_b, thd_current_c, " +
            "voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
            "current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a " +
            "FROM dbo.vw_harmonic_measurements ";

        boolean filtered = meterId != null;
        boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
        StringBuilder where = new StringBuilder();
        if (filtered) {
            where.append("WHERE meter_id = ? ");
        } else if (panelFiltered) {
            where.append("WHERE 1=1 ");
            for (int i = 0; i < panelTokens.size(); i++) {
                where.append("AND UPPER(REPLACE(REPLACE(panel_name,'_',''),' ','')) LIKE ? ");
            }
        }
        String sql = base + where.toString() + "ORDER BY measured_at DESC";

        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            if (filtered) {
                ps.setInt(1, meterId.intValue());
            } else if (panelFiltered) {
                int pi = 1;
                for (String token : panelTokens) {
                    String t = token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT);
                    ps.setString(pi++, "%" + t + "%");
                }
            }
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return "[Harmonic summary] " + (meterId != null ? ("meter_id=" + meterId + ", ") : "") + "no data";
                }
                int rowMeterId = rs.getInt("meter_id");
                String meterName = clip(rs.getString("meter_name"), 40);
                String panel = clip(rs.getString("panel_name"), 40);
                Timestamp ts = rs.getTimestamp("measured_at");
                return "[Harmonic summary] meter_id=" + rowMeterId
                    + ", meter=" + ("-".equals(meterName) ? "-" : meterName)
                    + ", panel=" + ("-".equals(panel) ? "-" : panel)
                    + ", t=" + fmtTs(ts)
                    + ", THD_V(A/B/C)=" + fmtNum(rs.getDouble("thd_voltage_a")) + "/" + fmtNum(rs.getDouble("thd_voltage_b")) + "/" + fmtNum(rs.getDouble("thd_voltage_c"))
                    + ", THD_I(A/B/C)=" + fmtNum(rs.getDouble("thd_current_a")) + "/" + fmtNum(rs.getDouble("thd_current_b")) + "/" + fmtNum(rs.getDouble("thd_current_c"))
                    + ", Vh(3/5/7/9/11)_A=" + fmtNum(rs.getDouble("voltage_h3_a")) + "/" + fmtNum(rs.getDouble("voltage_h5_a")) + "/" + fmtNum(rs.getDouble("voltage_h7_a")) + "/" + fmtNum(rs.getDouble("voltage_h9_a")) + "/" + fmtNum(rs.getDouble("voltage_h11_a"))
                    + ", Ih(3/5/7/9/11)_A=" + fmtNum(rs.getDouble("current_h3_a")) + "/" + fmtNum(rs.getDouble("current_h5_a")) + "/" + fmtNum(rs.getDouble("current_h7_a")) + "/" + fmtNum(rs.getDouble("current_h9_a")) + "/" + fmtNum(rs.getDouble("current_h11_a"));
            }
        } catch (Exception e) {
            return "[Harmonic summary] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getLatestEnergyContext(Integer meterId, String panelTokenCsv) {
        List<String> panelTokens = splitPanelTokens(panelTokenCsv);
        String baseSelect =
            "SELECT TOP %d m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
            "ms.active_power_total, ms.energy_consumed_total, ms.reactive_energy_total " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id ";

        boolean filtered = meterId != null;
        boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
        StringBuilder where = new StringBuilder();
        if (filtered) {
            where.append("WHERE m.meter_id = ? ");
        } else if (panelFiltered) {
            for (int i = 0; i < panelTokens.size(); i++) {
                where.append(i == 0 ? "WHERE 1=1 " : "");
                where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
            }
        }

        int topN = filtered ? 1 : (panelFiltered ? 1 : 3);
        String sql = String.format(baseSelect, topN) + where.toString() + "ORDER BY ms.measurement_id DESC";
        StringBuilder sb = new StringBuilder(filtered
            ? "[Latest energy: meter_id=" + meterId + "]"
            : (panelFiltered ? "[Latest energy: panel=" + panelTokens + "]" : "[Latest energy]"));
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            if (filtered) {
                ps.setInt(1, meterId.intValue());
            } else if (panelFiltered) {
                int pi = 1;
                for (String token : panelTokens) {
                    String normalized = token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT);
                    ps.setString(pi++, "%" + normalized + "%");
                }
            }
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                        .append("meter_id=").append(rs.getInt("meter_id"))
                        .append(", ").append(clip(rs.getString("meter_name"), 40))
                        .append(", panel=").append(clip(rs.getString("panel_name"), 60))
                        .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                        .append(", kW=").append(fmtNum(rs.getDouble("active_power_total")))
                        .append(", kWh=").append(fmtNum(rs.getDouble("energy_consumed_total")))
                        .append(", kVArh=").append(fmtNum(rs.getDouble("reactive_energy_total")))
                        .append(";");
                }
                if (i == 0) {
                    return filtered
                        ? "[Latest energy: meter_id=" + meterId + "] no data"
                        : (panelFiltered ? "[Latest energy: panel=" + panelTokens + "] no data" : "[Latest energy] no data");
                }
            }
        } catch (Exception e) {
            return (filtered
                ? "[Latest energy: meter_id=" + meterId + "]"
                : (panelFiltered ? "[Latest energy: panel=" + panelTokens + "]" : "[Latest energy]"))
                + " unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
        return sb.toString();
    }

    public static String getEnergyDeltaContext(Integer meterId, Timestamp fromTs, Timestamp toTs, String periodLabel, boolean reactive) {
        if (meterId == null) {
            return reactive ? "[Reactive energy delta] meter_id required" : "[Energy delta] meter_id required";
        }
        if (fromTs == null || toTs == null) {
            return reactive ? "[Reactive energy delta] period required" : "[Energy delta] period required";
        }
        String column = reactive ? "reactive_energy_total" : "energy_consumed_total";
        String prefix = reactive ? "[Reactive energy delta]" : "[Energy delta]";
        String sql =
            "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, CAST(ms." + column + " AS float) AS energy_val " +
            "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            "WHERE m.meter_id=? AND ms.measured_at >= ? AND ms.measured_at < ? AND ms." + column + " IS NOT NULL " +
            "ORDER BY ms.measured_at %s, ms.measurement_id %s";
        try (Connection conn = openDbConnection()) {
            String meterName = null;
            String panelName = null;
            Timestamp firstTs = null;
            Timestamp lastTs = null;
            Double firstVal = null;
            Double lastVal = null;
            try (PreparedStatement ps = conn.prepareStatement(String.format(sql, "ASC", "ASC"))) {
                ps.setInt(1, meterId.intValue());
                ps.setTimestamp(2, fromTs);
                ps.setTimestamp(3, toTs);
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        meterName = clip(rs.getString("meter_name"), 40);
                        panelName = clip(rs.getString("panel_name"), 60);
                        firstTs = rs.getTimestamp("measured_at");
                        firstVal = Double.valueOf(rs.getDouble("energy_val"));
                    }
                }
            }
            try (PreparedStatement ps = conn.prepareStatement(String.format(sql, "DESC", "DESC"))) {
                ps.setInt(1, meterId.intValue());
                ps.setTimestamp(2, fromTs);
                ps.setTimestamp(3, toTs);
                ps.setQueryTimeout(5);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        if (meterName == null) meterName = clip(rs.getString("meter_name"), 40);
                        if (panelName == null) panelName = clip(rs.getString("panel_name"), 60);
                        lastTs = rs.getTimestamp("measured_at");
                        lastVal = Double.valueOf(rs.getDouble("energy_val"));
                    }
                }
            }
            if (firstVal == null || lastVal == null) {
                return prefix + " meter_id=" + meterId + ", period=" + (periodLabel == null ? "-" : periodLabel) + ", no data";
            }
            double delta = Math.max(0.0d, lastVal.doubleValue() - firstVal.doubleValue());
            return prefix + " meter_id=" + meterId
                + ", meter=" + (meterName == null || meterName.isEmpty() ? "-" : meterName)
                + ", panel=" + (panelName == null || panelName.isEmpty() ? "-" : panelName)
                + ", period=" + (periodLabel == null ? "-" : periodLabel)
                + ", delta=" + fmtNum(delta)
                + ", start_t=" + fmtTs(firstTs)
                + ", end_t=" + fmtTs(lastTs)
                + ", start_v=" + fmtNum(firstVal.doubleValue())
                + ", end_v=" + fmtNum(lastVal.doubleValue());
        } catch (Exception e) {
            return prefix + " unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getVoltageAverageContext(Integer meterId, String panelTokenCsv, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer recentDays) {
        List<String> panelTokens = splitPanelTokens(panelTokenCsv);
        String expr = "COALESCE(ms.average_voltage, ms.line_voltage_avg, ms.phase_voltage_avg, ms.voltage_ab, ms.voltage_phase_a)";
        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        boolean filtered = meterId != null;
        boolean panelFiltered = !filtered && panelTokens != null && !panelTokens.isEmpty();
        if (filtered) {
            where.append("AND m.meter_id = ? ");
        } else if (panelFiltered) {
            for (int i = 0; i < panelTokens.size(); i++) {
                where.append("AND UPPER(REPLACE(REPLACE(m.panel_name,'_',''),' ','')) LIKE ? ");
            }
        }
        if (fromTs != null) where.append("AND ms.measured_at >= ? ");
        if (toTs != null) where.append("AND ms.measured_at < ? ");
        if (fromTs == null && toTs == null && recentDays != null && recentDays.intValue() > 0) {
            where.append("AND ms.measured_at >= DATEADD(DAY, -?, GETDATE()) ");
        }

        int topN = filtered ? 1 : (panelFiltered ? 3 : 5);
        String sql =
            "SELECT TOP " + topN + " m.meter_id, m.name AS meter_name, m.panel_name, " +
            "AVG(CAST(CASE WHEN " + expr + " > 0 THEN " + expr + " ELSE NULL END AS float)) AS avg_v, " +
            "MIN(CAST(CASE WHEN " + expr + " > 0 THEN " + expr + " ELSE NULL END AS float)) AS min_v, " +
            "MAX(CAST(CASE WHEN " + expr + " > 0 THEN " + expr + " ELSE NULL END AS float)) AS max_v, " +
            "COUNT(CASE WHEN " + expr + " > 0 THEN 1 END) AS sample_count " +
            "FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            where.toString() +
            "GROUP BY m.meter_id, m.name, m.panel_name " +
            "ORDER BY m.meter_id ASC";

        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (filtered) {
                ps.setInt(pi++, meterId.intValue());
            } else if (panelFiltered) {
                for (String token : panelTokens) {
                    String t = token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT);
                    ps.setString(pi++, "%" + t + "%");
                }
            }
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            if (fromTs == null && toTs == null && recentDays != null && recentDays.intValue() > 0) {
                ps.setInt(pi++, recentDays.intValue());
            }
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Voltage avg]");
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
                else if (recentDays != null && recentDays.intValue() > 0) sb.append(" days=").append(recentDays.intValue());
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    long n = rs.getLong("sample_count");
                    sb.append(" ").append(i).append(")")
                        .append("meter_id=").append(rs.getInt("meter_id"))
                        .append(", ").append(clip(rs.getString("meter_name"), 24))
                        .append(", panel=").append(clip(rs.getString("panel_name"), 24))
                        .append(", avg_v=").append(n > 0 ? fmtNum(rs.getDouble("avg_v")) : "-")
                        .append(", min_v=").append(n > 0 ? fmtNum(rs.getDouble("min_v")) : "-")
                        .append(", max_v=").append(n > 0 ? fmtNum(rs.getDouble("max_v")) : "-")
                        .append(", samples=").append(n)
                        .append(";");
                }
                if (i == 0) return "[Voltage avg] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Voltage avg] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getVoltagePhaseAngleContext(Integer meterId) {
        if (meterId == null) return "[Voltage phase angle] meter_id required";
        String sql =
            "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
            "ms.voltage_phase_a, ms.voltage_phase_b, ms.voltage_phase_c " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            "WHERE m.meter_id = ? " +
            "ORDER BY ms.measurement_id DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) return "[Voltage phase angle] meter_id=" + meterId + ", no data";
                double va = rs.getDouble("voltage_phase_a");
                if (rs.wasNull()) va = Double.NaN;
                double vb = rs.getDouble("voltage_phase_b");
                if (rs.wasNull()) vb = Double.NaN;
                double vc = rs.getDouble("voltage_phase_c");
                if (rs.wasNull()) vc = Double.NaN;
                return "[Voltage phase angle] meter_id=" + meterId
                    + ", meter=" + clip(rs.getString("meter_name"), 40)
                    + ", panel=" + clip(rs.getString("panel_name"), 40)
                    + ", t=" + fmtTs(rs.getTimestamp("measured_at"))
                    + ", Va=" + fmtNum(va)
                    + ", Vb=" + fmtNum(vb)
                    + ", Vc=" + fmtNum(vc);
            }
        } catch (Exception e) {
            return "[Voltage phase angle] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getCurrentPhaseAngleContext(Integer meterId) {
        if (meterId == null) return "[Current phase angle] meter_id required";
        String sql =
            "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
            "ms.current_phase_a, ms.current_phase_b, ms.current_phase_c " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            "WHERE m.meter_id = ? " +
            "ORDER BY ms.measurement_id DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) return "[Current phase angle] meter_id=" + meterId + ", no data";
                double ia = rs.getDouble("current_phase_a");
                if (rs.wasNull()) ia = Double.NaN;
                double ib = rs.getDouble("current_phase_b");
                if (rs.wasNull()) ib = Double.NaN;
                double ic = rs.getDouble("current_phase_c");
                if (rs.wasNull()) ic = Double.NaN;
                return "[Current phase angle] meter_id=" + meterId
                    + ", meter=" + clip(rs.getString("meter_name"), 40)
                    + ", panel=" + clip(rs.getString("panel_name"), 40)
                    + ", t=" + fmtTs(rs.getTimestamp("measured_at"))
                    + ", Ia=" + fmtNum(ia)
                    + ", Ib=" + fmtNum(ib)
                    + ", Ic=" + fmtNum(ic);
            }
        } catch (Exception e) {
            return "[Current phase angle] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getPhaseCurrentContext(Integer meterId, String phase) {
        String p = EpmsWebUtil.trimToNull(phase);
        if (meterId == null) return "[Phase current] meter_id required";
        if (p == null) return "[Phase current] phase required";
        p = p.toUpperCase(Locale.ROOT);
        String col = "A".equals(p) ? "current_a" : ("B".equals(p) ? "current_b" : ("C".equals(p) ? "current_c" : null));
        if (col == null) return "[Phase current] invalid phase";
        String sql =
            "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " + col + " AS phase_current " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            "WHERE m.meter_id = ? " +
            "ORDER BY ms.measurement_id DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) return "[Phase current] meter_id=" + meterId + ", phase=" + p + ", no data";
                double i = rs.getDouble("phase_current");
                if (rs.wasNull()) i = Double.NaN;
                return "[Phase current] meter_id=" + meterId
                    + ", meter=" + clip(rs.getString("meter_name"), 40)
                    + ", panel=" + clip(rs.getString("panel_name"), 40)
                    + ", t=" + fmtTs(rs.getTimestamp("measured_at"))
                    + ", phase=" + p
                    + ", I=" + fmtNum(i);
            }
        } catch (Exception e) {
            return "[Phase current] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getPhaseVoltageContext(Integer meterId, String phase) {
        String p = EpmsWebUtil.trimToNull(phase);
        if (meterId == null) return "[Phase voltage] meter_id required";
        if (p == null) return "[Phase voltage] phase required";
        p = p.toUpperCase(Locale.ROOT);
        String col = "A".equals(p) ? "voltage_phase_a" : ("B".equals(p) ? "voltage_phase_b" : ("C".equals(p) ? "voltage_phase_c" : null));
        if (col == null) return "[Phase voltage] invalid phase";
        String sql =
            "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " + col + " AS phase_voltage " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            "WHERE m.meter_id = ? " +
            "ORDER BY ms.measurement_id DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) return "[Phase voltage] meter_id=" + meterId + ", phase=" + p + ", no data";
                double v = rs.getDouble("phase_voltage");
                if (rs.wasNull()) v = Double.NaN;
                return "[Phase voltage] meter_id=" + meterId
                    + ", meter=" + clip(rs.getString("meter_name"), 40)
                    + ", panel=" + clip(rs.getString("panel_name"), 40)
                    + ", t=" + fmtTs(rs.getTimestamp("measured_at"))
                    + ", phase=" + p
                    + ", V=" + fmtNum(v);
            }
        } catch (Exception e) {
            return "[Phase voltage] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getLineVoltageContext(Integer meterId, String pair) {
        if (meterId == null) return "[Line voltage] meter_id required";
        String p = EpmsWebUtil.trimToNull(pair);
        if (p != null) p = p.toUpperCase(Locale.ROOT);
        if (p != null && !("AB".equals(p) || "BC".equals(p) || "CA".equals(p))) p = null;
        String sql =
            "SELECT TOP 1 m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at, " +
            "ms.voltage_ab, ms.voltage_bc, ms.voltage_ca " +
            "FROM dbo.measurements ms " +
            "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            "WHERE m.meter_id = ? " +
            "ORDER BY ms.measurement_id DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) return "[Line voltage] meter_id=" + meterId + ", pair=" + (p == null ? "ALL" : p) + ", no data";
                double vab = rs.getDouble("voltage_ab");
                if (rs.wasNull()) vab = Double.NaN;
                double vbc = rs.getDouble("voltage_bc");
                if (rs.wasNull()) vbc = Double.NaN;
                double vca = rs.getDouble("voltage_ca");
                if (rs.wasNull()) vca = Double.NaN;
                return "[Line voltage] meter_id=" + meterId
                    + ", meter=" + clip(rs.getString("meter_name"), 40)
                    + ", panel=" + clip(rs.getString("panel_name"), 40)
                    + ", t=" + fmtTs(rs.getTimestamp("measured_at"))
                    + ", pair=" + (p == null ? "ALL" : p)
                    + ", Vab=" + fmtNum(vab)
                    + ", Vbc=" + fmtNum(vbc)
                    + ", Vca=" + fmtNum(vca);
            }
        } catch (Exception e) {
            return "[Line voltage] unavailable: " + clip(e.getClass().getSimpleName(), 24);
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
            "SELECT TOP " + n + " ISNULL(NULLIF(LTRIM(RTRIM(alarm_type)),''), '(\uBBF8\uBD84\uB958)') AS alarm_type, COUNT(1) AS cnt " +
            "FROM dbo.vw_alarm_log " + where +
            "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(alarm_type)),''), '(\uBBF8\uBD84\uB958)') " +
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

    public static String getAlarmMeterTopNContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer topN) {
        int d = days != null ? days.intValue() : 7;
        int n = topN != null ? topN.intValue() : 10;
        if (n < 1) n = 10;
        if (n > 50) n = 50;
        boolean byRange = fromTs != null || toTs != null;

        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        if (byRange) {
            if (fromTs != null) where.append("AND triggered_at >= ? ");
            if (toTs != null) where.append("AND triggered_at < ? ");
        } else {
            where.append("AND triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
        }

        String sql =
            "SELECT TOP " + n + " ISNULL(NULLIF(LTRIM(RTRIM(meter_name)), ''), '(\uBBF8\uBD84\uB958 \uACC4\uCE21\uAE30)') AS meter_name, COUNT(1) AS cnt " +
            "FROM dbo.vw_alarm_log " + where +
            "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(meter_name)), ''), '(\uBBF8\uBD84\uB958 \uACC4\uCE21\uAE30)') " +
            "ORDER BY cnt DESC, meter_name ASC";

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
                StringBuilder sb = new StringBuilder("[Alarm meter TOP] ");
                if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
                else sb.append("days=").append(d).append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                        .append(clip(rs.getString("meter_name"), 80))
                        .append("=")
                        .append(rs.getLong("cnt"))
                        .append(";");
                }
                if (i == 0) return "[Alarm meter TOP] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Alarm meter TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
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

    public static String getMonthlyPeakPowerContext(Integer meterId, Integer month) {
        int mm = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int yy = java.time.LocalDate.now().getYear();
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT TOP 1 ms.meter_id, ISNULL(NULLIF(LTRIM(RTRIM(m.name)), ''), '-') AS meter_name, ");
        sql.append("ISNULL(NULLIF(LTRIM(RTRIM(m.panel_name)), ''), '-') AS panel_name, ");
        sql.append("ms.measured_at, CAST(ms.active_power_total AS float) AS peak_kw ");
        sql.append("FROM dbo.measurements ms ");
        sql.append("LEFT JOIN dbo.meters m ON m.meter_id = ms.meter_id ");
        sql.append("WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? ");
        if (meterId != null) {
            sql.append("AND ms.meter_id=? ");
        }
        sql.append("ORDER BY CAST(ms.active_power_total AS float) DESC, ms.measured_at ASC");

        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            ps.setInt(pi++, yy);
            ps.setInt(pi++, mm);
            if (meterId != null) ps.setInt(pi++, meterId.intValue());
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return "[Monthly peak power] period=" + String.format(Locale.US, "%04d-%02d", yy, mm)
                        + (meterId != null ? "; meter_id=" + meterId.intValue() : "")
                        + "; no data";
                }
                return "[Monthly peak power] period=" + String.format(Locale.US, "%04d-%02d", yy, mm)
                    + "; meter_id=" + rs.getInt("meter_id")
                    + "; meter_name=" + clip(rs.getString("meter_name"), 60)
                    + "; panel=" + clip(rs.getString("panel_name"), 60)
                    + "; peak_kw=" + fmtNum(rs.getDouble("peak_kw"))
                    + "; t=" + fmtTs(rs.getTimestamp("measured_at"));
            }
        } catch (Exception e) {
            return "[Monthly peak power] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getMonthlyPowerStatsContext(Integer meterId, Integer month) {
        if (meterId == null) return "[Monthly power stats] meter_id required";
        int mm = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int yy = java.time.LocalDate.now().getYear();
        String sql =
            "SELECT AVG(CAST(active_power_total AS float)) AS avg_kw, MAX(CAST(active_power_total AS float)) AS max_kw, COUNT(1) AS sample_count " +
            "FROM dbo.measurements WHERE meter_id=? AND YEAR(measured_at)=? AND MONTH(measured_at)=?";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, meterId.intValue());
            ps.setInt(2, yy);
            ps.setInt(3, mm);
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    long n = rs.getLong("sample_count");
                    if (n <= 0) {
                        return "[Monthly power stats] meter_id=" + meterId + ", period=" + yy + "-" + String.format(Locale.US, "%02d", mm) + ", no data";
                    }
                    return "[Monthly power stats] meter_id=" + meterId + ", period=" + yy + "-" + String.format(Locale.US, "%02d", mm) +
                        ", avg_kw=" + fmtNum(rs.getDouble("avg_kw")) + ", max_kw=" + fmtNum(rs.getDouble("max_kw")) + ", samples=" + n;
                }
            }
        } catch (Exception e) {
            return "[Monthly power stats] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
        return "[Monthly power stats] no data";
    }

    public static String getUsageMeterTopNContext(Integer topN) {
        int n = topN != null ? topN.intValue() : 5;
        if (n < 1) n = 5;
        if (n > 20) n = 20;
        String sql =
            "SELECT TOP " + n + " " +
            "  ISNULL(NULLIF(LTRIM(RTRIM(usage_type)), ''), '미분류') AS usage_type, " +
            "  COUNT(*) AS meter_count " +
            "FROM dbo.meters " +
            "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(usage_type)), ''), '미분류') " +
            "ORDER BY COUNT(*) DESC, ISNULL(NULLIF(LTRIM(RTRIM(usage_type)), ''), '미분류') ASC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Usage meter top];");
                int i = 0;
                while (rs.next()) {
                    i++;
                    String usageType = EpmsWebUtil.trimToNull(rs.getString("usage_type"));
                    if (usageType == null) usageType = "미분류";
                    sb.append(" ").append(i).append(")")
                      .append(clip(usageType, 40))
                      .append(": count=")
                      .append(rs.getInt("meter_count"))
                      .append(";");
                }
                if (i == 0) return "[Usage meter top] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Usage meter top] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getScopedMonthlyEnergyContext(String scopeToken, Integer month) {
        List<String> tokens = splitScopeTokens(scopeToken);
        if (tokens.isEmpty()) return "[Scoped monthly energy] scope required";
        int mm = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int yy = java.time.LocalDate.now().getYear();
        StringBuilder scopeWhere = new StringBuilder("(");
        for (int i = 0; i < tokens.size(); i++) {
            if (i > 0) scopeWhere.append(" OR ");
            scopeWhere.append("UPPER(ISNULL(m.building_name,'')) LIKE ? OR UPPER(ISNULL(m.usage_type,'')) LIKE ?");
        }
        scopeWhere.append(")");
        String sql =
            "WITH selected_leaf_meters AS ( " +
            "  SELECT DISTINCT m.meter_id " +
            "  FROM dbo.meters m " +
            "  WHERE " + scopeWhere + " " +
            "    AND NOT EXISTS ( " +
            "      SELECT 1 FROM dbo.meter_tree t " +
            "      WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
            "    ) " +
            "), month_samples AS ( " +
            "  SELECT ms.meter_id, ms.measurement_id, ms.measured_at, " +
            "         CAST(ms.active_power_total AS float) AS active_kw, " +
            "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
            "  FROM dbo.measurements ms " +
            "  INNER JOIN selected_leaf_meters slm ON slm.meter_id = ms.meter_id " +
            "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
            "), month_energy AS ( " +
            "  SELECT meter_id, " +
            "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
            "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
            "  FROM month_samples GROUP BY meter_id " +
            ") " +
            "SELECT " +
            "  (SELECT COUNT(*) FROM selected_leaf_meters) AS leaf_meter_count, " +
            "  (SELECT COUNT(*) FROM month_energy) AS measured_meter_count, " +
            "  (SELECT COUNT(*) FROM month_energy WHERE start_kwh IS NOT NULL AND end_kwh IS NOT NULL AND end_kwh < start_kwh) AS negative_delta_count, " +
            "  (SELECT AVG(active_kw) FROM month_samples) AS avg_kw, " +
            "  (SELECT SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 WHEN end_kwh < start_kwh THEN 0 ELSE end_kwh - start_kwh END) FROM month_energy) AS sum_kwh";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            for (String token : tokens) {
                String upper = token.toUpperCase(Locale.ROOT);
                ps.setString(pi++, "%" + upper + "%");
                ps.setString(pi++, "%" + upper + "%");
            }
            ps.setInt(pi++, yy);
            ps.setInt(pi++, mm);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int leafMeterCount = rs.getInt("leaf_meter_count");
                    int measuredMeterCount = rs.getInt("measured_meter_count");
                    if (leafMeterCount <= 0) {
                        return "[Scoped monthly energy] scope=" + String.join(",", tokens) + "; period=" + yy + "-" + String.format(Locale.US, "%02d", mm) + "; no data";
                    }
                    return "[Scoped monthly energy] scope=" + String.join(",", tokens)
                        + "; period=" + yy + "-" + String.format(Locale.US, "%02d", mm)
                        + "; leaf_meter_count=" + leafMeterCount
                        + "; measured_meter_count=" + measuredMeterCount
                        + "; negative_delta_count=" + rs.getInt("negative_delta_count")
                        + "; avg_kw=" + fmtNum(rs.getDouble("avg_kw"))
                        + "; sum_kwh=" + fmtNum(rs.getDouble("sum_kwh"));
                }
            }
        } catch (Exception e) {
            return "[Scoped monthly energy] scope=" + String.join(",", tokens) + "; unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
        return "[Scoped monthly energy] no data";
    }

    public static String getPanelMonthlyEnergyContext(String panelTokenCsv, Integer month) {
        List<String> panelTokens = splitPanelTokens(panelTokenCsv);
        if (panelTokens.isEmpty()) return "[Panel monthly energy] panel token required";
        int mm = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int yy = java.time.LocalDate.now().getYear();
        StringBuilder panelWhere = new StringBuilder("(");
        for (int i = 0; i < panelTokens.size(); i++) {
            if (i > 0) panelWhere.append(" OR ");
            panelWhere.append("UPPER(REPLACE(REPLACE(ISNULL(m.panel_name,''),'_',''),' ','')) LIKE ?");
        }
        panelWhere.append(")");
        String sql =
            "WITH selected_leaf_meters AS ( " +
            "  SELECT DISTINCT m.meter_id " +
            "  FROM dbo.meters m " +
            "  WHERE " + panelWhere + " " +
            "    AND NOT EXISTS ( " +
            "      SELECT 1 FROM dbo.meter_tree t " +
            "      WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
            "    ) " +
            "), month_samples AS ( " +
            "  SELECT ms.meter_id, ms.measurement_id, ms.measured_at, " +
            "         CAST(ms.active_power_total AS float) AS active_kw, " +
            "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
            "  FROM dbo.measurements ms " +
            "  INNER JOIN selected_leaf_meters slm ON slm.meter_id = ms.meter_id " +
            "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
            "), month_energy AS ( " +
            "  SELECT meter_id, " +
            "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
            "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
            "  FROM month_samples GROUP BY meter_id " +
            ") " +
            "SELECT " +
            "  (SELECT COUNT(*) FROM selected_leaf_meters) AS leaf_meter_count, " +
            "  (SELECT COUNT(*) FROM month_energy) AS measured_meter_count, " +
            "  (SELECT COUNT(*) FROM month_energy WHERE start_kwh IS NOT NULL AND end_kwh IS NOT NULL AND end_kwh < start_kwh) AS negative_delta_count, " +
            "  (SELECT AVG(active_kw) FROM month_samples) AS avg_kw, " +
            "  (SELECT SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 WHEN end_kwh < start_kwh THEN 0 ELSE end_kwh - start_kwh END) FROM month_energy) AS sum_kwh";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            for (String token : panelTokens) {
                String normalized = token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT);
                ps.setString(pi++, "%" + normalized + "%");
            }
            ps.setInt(pi++, yy);
            ps.setInt(pi++, mm);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int leafMeterCount = rs.getInt("leaf_meter_count");
                    int measuredMeterCount = rs.getInt("measured_meter_count");
                    if (leafMeterCount <= 0) {
                        return "[Panel monthly energy] panel=" + panelTokens + "; period=" + yy + "-" + String.format(Locale.US, "%02d", mm) + "; no data";
                    }
                    return "[Panel monthly energy] panel=" + panelTokens
                        + "; period=" + yy + "-" + String.format(Locale.US, "%02d", mm)
                        + "; leaf_meter_count=" + leafMeterCount
                        + "; measured_meter_count=" + measuredMeterCount
                        + "; negative_delta_count=" + rs.getInt("negative_delta_count")
                        + "; avg_kw=" + fmtNum(rs.getDouble("avg_kw"))
                        + "; sum_kwh=" + fmtNum(rs.getDouble("sum_kwh"));
                }
            }
        } catch (Exception e) {
            return "[Panel monthly energy] panel=" + panelTokens + "; unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
        return "[Panel monthly energy] no data";
    }

    public static String getUsageMonthlyEnergyContext(String usageToken, Integer month) {
        String token = EpmsWebUtil.trimToNull(usageToken);
        if (token == null) return "[Usage monthly energy] usage token required";
        int mm = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int yy = java.time.LocalDate.now().getYear();
        String sql =
            "WITH selected_leaf_meters AS ( " +
            "  SELECT DISTINCT m.meter_id " +
            "  FROM dbo.meters m " +
            "  WHERE UPPER(ISNULL(m.usage_type,'')) LIKE ? " +
            "    AND NOT EXISTS ( " +
            "      SELECT 1 FROM dbo.meter_tree t " +
            "      WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
            "    ) " +
            "), month_samples AS ( " +
            "  SELECT ms.meter_id, ms.measurement_id, ms.measured_at, " +
            "         CAST(ms.active_power_total AS float) AS active_kw, " +
            "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
            "  FROM dbo.measurements ms " +
            "  INNER JOIN selected_leaf_meters slm ON slm.meter_id = ms.meter_id " +
            "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
            "), month_energy AS ( " +
            "  SELECT meter_id, " +
            "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
            "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
            "  FROM month_samples GROUP BY meter_id " +
            ") " +
            "SELECT " +
            "  (SELECT COUNT(*) FROM selected_leaf_meters) AS leaf_meter_count, " +
            "  (SELECT COUNT(*) FROM month_energy) AS measured_meter_count, " +
            "  (SELECT COUNT(*) FROM month_energy WHERE start_kwh IS NOT NULL AND end_kwh IS NOT NULL AND end_kwh < start_kwh) AS negative_delta_count, " +
            "  (SELECT AVG(active_kw) FROM month_samples) AS avg_kw, " +
            "  (SELECT SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 WHEN end_kwh < start_kwh THEN 0 ELSE end_kwh - start_kwh END) FROM month_energy) AS sum_kwh";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, "%" + token.toUpperCase(Locale.ROOT) + "%");
            ps.setInt(2, yy);
            ps.setInt(3, mm);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int leafMeterCount = rs.getInt("leaf_meter_count");
                    int measuredMeterCount = rs.getInt("measured_meter_count");
                    if (leafMeterCount <= 0) {
                        return "[Usage monthly energy] usage=" + token + "; period=" + yy + "-" + String.format(Locale.US, "%02d", mm) + "; no data";
                    }
                    return "[Usage monthly energy] usage=" + token
                        + "; period=" + yy + "-" + String.format(Locale.US, "%02d", mm)
                        + "; leaf_meter_count=" + leafMeterCount
                        + "; measured_meter_count=" + measuredMeterCount
                        + "; negative_delta_count=" + rs.getInt("negative_delta_count")
                        + "; avg_kw=" + fmtNum(rs.getDouble("avg_kw"))
                        + "; sum_kwh=" + fmtNum(rs.getDouble("sum_kwh"));
                }
            }
        } catch (Exception e) {
            return "[Usage monthly energy] usage=" + token + "; unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
        return "[Usage monthly energy] no data";
    }

    public static String getUsagePowerTopNContext(Integer month, Integer topN) {
        int mm = month != null ? month.intValue() : java.time.LocalDate.now().getMonthValue();
        int yy = java.time.LocalDate.now().getYear();
        int n = topN != null ? topN.intValue() : 5;
        String sql =
            "WITH leaf_meters AS ( " +
            "  SELECT m.meter_id, ISNULL(NULLIF(LTRIM(RTRIM(m.usage_type)), ''), '미분류') AS usage_type " +
            "  FROM dbo.meters m " +
            "  WHERE NOT EXISTS ( " +
            "    SELECT 1 FROM dbo.meter_tree t " +
            "    WHERE t.parent_meter_id = m.meter_id AND ISNULL(t.is_active, 1) = 1 " +
            "  ) " +
            "), month_samples AS ( " +
            "  SELECT lm.usage_type, ms.meter_id, ms.measurement_id, ms.measured_at, " +
            "         CAST(ms.active_power_total AS float) AS active_kw, " +
            "         CAST(ms.energy_consumed_total AS float) AS energy_kwh, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at ASC, ms.measurement_id ASC) AS rn_first, " +
            "         ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn_last " +
            "  FROM dbo.measurements ms " +
            "  INNER JOIN leaf_meters lm ON lm.meter_id = ms.meter_id " +
            "  WHERE YEAR(ms.measured_at)=? AND MONTH(ms.measured_at)=? " +
            "), month_energy AS ( " +
            "  SELECT usage_type, meter_id, " +
            "         MAX(CASE WHEN rn_first = 1 THEN energy_kwh END) AS start_kwh, " +
            "         MAX(CASE WHEN rn_last = 1 THEN energy_kwh END) AS end_kwh " +
            "  FROM month_samples GROUP BY usage_type, meter_id " +
            "), usage_avg AS ( " +
            "  SELECT usage_type, AVG(active_kw) AS avg_kw " +
            "  FROM month_samples GROUP BY usage_type " +
            "), usage_sum AS ( " +
            "  SELECT usage_type, SUM(CASE WHEN start_kwh IS NULL OR end_kwh IS NULL THEN 0 ELSE end_kwh - start_kwh END) AS sum_kwh " +
            "  FROM month_energy GROUP BY usage_type " +
            "), usage_agg AS ( " +
            "  SELECT a.usage_type, a.avg_kw, ISNULL(s.sum_kwh, 0) AS sum_kwh " +
            "  FROM usage_avg a LEFT JOIN usage_sum s ON s.usage_type = a.usage_type " +
            ") " +
            "SELECT TOP " + n + " usage_type, avg_kw, sum_kwh FROM usage_agg ORDER BY sum_kwh DESC, avg_kw DESC, usage_type ASC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, yy);
            ps.setInt(2, mm);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Usage power TOP] period=" + yy + "-" + String.format(Locale.US, "%02d", mm) + ";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append(clip(rs.getString("usage_type"), 30))
                      .append(": avg_kw=").append(fmtNum(rs.getDouble("avg_kw")))
                      .append(", sum_kwh=").append(fmtNum(rs.getDouble("sum_kwh"))).append(";");
                }
                if (i == 0) return "[Usage power TOP] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Usage power TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getUsageAlarmTopNContext(Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel, Integer topN) {
        int d = days != null ? days.intValue() : 7;
        int n = topN != null ? topN.intValue() : 10;
        if (n < 1) n = 10;
        if (n > 50) n = 50;
        boolean byRange = (fromTs != null || toTs != null);
        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        if (byRange) {
            if (fromTs != null) where.append("AND al.triggered_at >= ? ");
            if (toTs != null) where.append("AND al.triggered_at < ? ");
        } else {
            where.append("AND al.triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
        }
        String sql =
            "SELECT TOP " + n + " " +
            "  ISNULL(NULLIF(LTRIM(RTRIM(m.usage_type)), ''), '미분류') AS usage_type, " +
            "  COUNT(1) AS cnt " +
            "FROM dbo.vw_alarm_log al " +
            "LEFT JOIN dbo.meters m ON m.name = al.meter_name " +
            where.toString() +
            "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(m.usage_type)), ''), '미분류') " +
            "ORDER BY cnt DESC, usage_type ASC";
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
                StringBuilder sb = new StringBuilder("[Usage alarm TOP] ");
                if (byRange) sb.append("period=").append(periodLabel == null ? "-" : periodLabel).append(";");
                else sb.append("days=").append(d).append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append(clip(rs.getString("usage_type"), 40))
                      .append("=")
                      .append(rs.getLong("cnt"))
                      .append(";");
                }
                if (i == 0) return "[Usage alarm TOP] no data";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Usage alarm TOP] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getUsageAlarmCountContext(String usageToken, Integer days, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        String token = EpmsWebUtil.trimToNull(usageToken);
        if (token == null) return "[Usage alarm count] usage token required";
        int d = days != null ? days.intValue() : 7;
        boolean byRange = (fromTs != null || toTs != null);
        StringBuilder sql = new StringBuilder(
            "SELECT COUNT(1) AS cnt " +
            "FROM dbo.vw_alarm_log al " +
            "LEFT JOIN dbo.meters m ON m.name = al.meter_name " +
            "WHERE UPPER(ISNULL(m.usage_type,'')) LIKE ? "
        );
        if (byRange) {
            if (fromTs != null) sql.append("AND al.triggered_at >= ? ");
            if (toTs != null) sql.append("AND al.triggered_at < ? ");
        } else {
            sql.append("AND al.triggered_at >= DATEADD(DAY, -?, GETDATE()) ");
        }
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int pi = 1;
            ps.setString(pi++, "%" + token.toUpperCase(Locale.ROOT) + "%");
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
                    if (byRange) return "[Usage alarm count] usage=" + token + "; period=" + (periodLabel == null ? "-" : periodLabel) + "; count=" + cnt;
                    return "[Usage alarm count] usage=" + token + "; days=" + d + "; count=" + cnt;
                }
            }
            return "[Usage alarm count] no data";
        } catch (Exception e) {
            return "[Usage alarm count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static String getCurrentUnbalanceCountContext(Double thresholdPct, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        double th = thresholdPct != null ? thresholdPct.doubleValue() : 10.0d;
        StringBuilder where = new StringBuilder("WHERE 1=1 ");
        if (fromTs != null) where.append("AND ms.measured_at >= ? ");
        if (toTs != null) where.append("AND ms.measured_at < ? ");
        String sql =
            "WITH latest AS ( " +
            "  SELECT m.meter_id, m.name AS meter_name, ms.measured_at, " +
            "         CAST(ms.current_phase_a AS float) AS ia, " +
            "         CAST(ms.current_phase_b AS float) AS ib, " +
            "         CAST(ms.current_phase_c AS float) AS ic, " +
            "         ROW_NUMBER() OVER (PARTITION BY m.meter_id ORDER BY ms.measured_at DESC, ms.measurement_id DESC) AS rn " +
            "  FROM dbo.measurements ms INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
            where.toString() +
            "), calc AS ( " +
            "  SELECT meter_id, meter_name, measured_at, ia, ib, ic, " +
            "         ((ISNULL(ia,0) + ISNULL(ib,0) + ISNULL(ic,0)) / 3.0) AS avg_i " +
            "  FROM latest WHERE rn = 1 " +
            "), filtered AS ( " +
            "  SELECT meter_id, meter_name, measured_at, " +
            "         CASE WHEN avg_i <= 0 THEN NULL ELSE " +
            "           (100.0 * (" +
            "             CASE " +
            "               WHEN ABS(ISNULL(ia,0) - avg_i) >= ABS(ISNULL(ib,0) - avg_i) AND ABS(ISNULL(ia,0) - avg_i) >= ABS(ISNULL(ic,0) - avg_i) THEN ABS(ISNULL(ia,0) - avg_i) " +
            "               WHEN ABS(ISNULL(ib,0) - avg_i) >= ABS(ISNULL(ic,0) - avg_i) THEN ABS(ISNULL(ib,0) - avg_i) " +
            "               ELSE ABS(ISNULL(ic,0) - avg_i) " +
            "             END" +
            "           ) / avg_i) END AS current_unbalance_pct " +
            "  FROM calc " +
            ") " +
            "SELECT COUNT(*) AS meter_count " +
            "FROM filtered WHERE current_unbalance_pct > ?";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setDouble(pi++, th);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                int count = rs.next() ? rs.getInt("meter_count") : 0;
                StringBuilder sb = new StringBuilder("[Current unbalance count] threshold=").append(fmtNum(th));
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append("; period=").append(periodLabel);
                sb.append("; count=").append(count);
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Current unbalance count] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }
    }

    public static int getPowerFactorNoSignalCount(Timestamp fromTs, Timestamp toTs) {
        StringBuilder srcWhere = new StringBuilder("WHERE 1=1 ");
        if (fromTs != null) srcWhere.append("AND ms.measured_at >= ? ");
        if (toTs != null) srcWhere.append("AND ms.measured_at < ? ");
        String sql =
            "WITH latest AS (" +
            " SELECT ms.*, ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
            " FROM dbo.measurements ms " + srcWhere +
            ") " +
            "SELECT COUNT(*) AS cnt " +
            "FROM latest ms " +
            "WHERE ms.rn=1 " +
            "AND (" +
            " COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) IS NULL " +
            " OR COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) = 0" +
            ")";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return rs.getInt("cnt");
                return 0;
            }
        } catch (Exception e) {
            return -1;
        }
    }

    public static String getPowerFactorNoSignalListContext(int topN, Timestamp fromTs, Timestamp toTs, String periodLabel) {
        int n = topN > 0 ? topN : 10;
        StringBuilder srcWhere = new StringBuilder("WHERE 1=1 ");
        if (fromTs != null) srcWhere.append("AND ms.measured_at >= ? ");
        if (toTs != null) srcWhere.append("AND ms.measured_at < ? ");
        String sql =
            "WITH latest AS (" +
            " SELECT ms.*, ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
            " FROM dbo.measurements ms " + srcWhere +
            ") " +
            "SELECT TOP " + n + " m.meter_id, m.name AS meter_name, m.panel_name, ms.measured_at " +
            "FROM latest ms INNER JOIN dbo.meters m ON m.meter_id=ms.meter_id " +
            "WHERE ms.rn=1 " +
            "AND (" +
            " COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) IS NULL " +
            " OR COALESCE(ms.power_factor, ms.power_factor_avg, (ms.power_factor_a + ms.power_factor_b + ms.power_factor_c)/3.0) = 0" +
            ") " +
            "ORDER BY ms.measured_at DESC";
        try (Connection conn = openDbConnection(); PreparedStatement ps = conn.prepareStatement(sql)) {
            int pi = 1;
            if (fromTs != null) ps.setTimestamp(pi++, fromTs);
            if (toTs != null) ps.setTimestamp(pi++, toTs);
            ps.setQueryTimeout(10);
            try (ResultSet rs = ps.executeQuery()) {
                StringBuilder sb = new StringBuilder("[Power factor no signal]");
                if (periodLabel != null && !periodLabel.isEmpty()) sb.append(" period=").append(periodLabel);
                sb.append(";");
                int i = 0;
                while (rs.next()) {
                    i++;
                    sb.append(" ").append(i).append(")")
                      .append("meter_id=").append(rs.getInt("meter_id"))
                      .append(", ").append(clip(rs.getString("meter_name"), 24))
                      .append(", panel=").append(clip(rs.getString("panel_name"), 24))
                      .append(", t=").append(fmtTs(rs.getTimestamp("measured_at")))
                      .append(";");
                }
                if (i == 0) return "[Power factor no signal] none";
                return sb.toString();
            }
        } catch (Exception e) {
            return "[Power factor no signal] unavailable: " + clip(e.getClass().getSimpleName(), 24);
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

    public static Integer resolveMeterIdByName(String meterNameToken) {
        String token = EpmsWebUtil.trimToNull(meterNameToken);
        if (token == null) return null;
        String normalized = token.replaceAll("[\\s_\\-]+", "").toUpperCase(Locale.ROOT);
        if (normalized.length() < 3) return null;
        String sql =
            "SELECT TOP 1 meter_id " +
            "FROM dbo.meters " +
            "WHERE UPPER(REPLACE(REPLACE(REPLACE(name,'_',''),'-',''),' ','')) = ? " +
            "   OR UPPER(REPLACE(REPLACE(REPLACE(name,'_',''),'-',''),' ','')) LIKE ? " +
            "ORDER BY CASE WHEN UPPER(REPLACE(REPLACE(REPLACE(name,'_',''),'-',''),' ','')) = ? THEN 0 ELSE 1 END, meter_id ASC";
        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, normalized);
            ps.setString(2, "%" + normalized + "%");
            ps.setString(3, normalized);
            ps.setQueryTimeout(5);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return Integer.valueOf(rs.getInt("meter_id"));
            }
        } catch (Exception ignore) {
        }
        return null;
    }

    public static String buildSchemaContextFromDb(int maxTables, int maxColumnsPerTable, int maxChars) {
        String tableSql =
            "SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE " +
            "FROM INFORMATION_SCHEMA.TABLES " +
            "WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','sys') " +
            "ORDER BY TABLE_SCHEMA, TABLE_NAME";
        String columnSql =
            "SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE " +
            "FROM INFORMATION_SCHEMA.COLUMNS " +
            "WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','sys') " +
            "ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION";

        LinkedHashMap<String, String> tableTypeMap = new LinkedHashMap<String, String>();
        LinkedHashMap<String, ArrayList<String>> columnMap = new LinkedHashMap<String, ArrayList<String>>();

        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(tableSql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String schema = rs.getString("TABLE_SCHEMA");
                    String table = rs.getString("TABLE_NAME");
                    if (schema == null || table == null) continue;
                    String key = schema + "." + table;
                    tableTypeMap.put(key, rs.getString("TABLE_TYPE"));
                    columnMap.put(key, new ArrayList<String>());
                }
            }
        } catch (Exception e) {
            return "[Schema] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }

        try (Connection conn = openDbConnection();
             PreparedStatement ps = conn.prepareStatement(columnSql)) {
            ps.setQueryTimeout(8);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String schema = rs.getString("TABLE_SCHEMA");
                    String table = rs.getString("TABLE_NAME");
                    String col = rs.getString("COLUMN_NAME");
                    String dt = rs.getString("DATA_TYPE");
                    if (schema == null || table == null || col == null) continue;
                    String key = schema + "." + table;
                    ArrayList<String> cols = columnMap.get(key);
                    if (cols == null || cols.size() >= maxColumnsPerTable) continue;
                    cols.add(col + "(" + (dt == null ? "?" : dt) + ")");
                }
            }
        } catch (Exception e) {
            return "[Schema] unavailable: " + clip(e.getClass().getSimpleName(), 24);
        }

        if (tableTypeMap.isEmpty()) return "[Schema] no table metadata";

        StringBuilder sb = new StringBuilder();
        sb.append("[Schema snapshot]\n");
        int tableCount = 0;
        for (Map.Entry<String, String> e : tableTypeMap.entrySet()) {
            if (tableCount >= maxTables) break;
            String key = e.getKey();
            ArrayList<String> cols = columnMap.get(key);
            sb.append(key)
              .append(" [")
              .append(e.getValue() == null ? "TABLE" : e.getValue())
              .append("]: ");
            if (cols == null || cols.isEmpty()) {
                sb.append("(no columns)");
            } else {
                for (int i = 0; i < cols.size(); i++) {
                    if (i > 0) sb.append(", ");
                    sb.append(cols.get(i));
                }
            }
            sb.append('\n');
            tableCount++;
            if (sb.length() >= maxChars) break;
        }
        if (tableTypeMap.size() > tableCount) {
            sb.append("... truncated tables: ").append(tableTypeMap.size() - tableCount).append('\n');
        }
        if (sb.length() > maxChars) {
            return sb.substring(0, maxChars) + "\n... truncated by size";
        }
        return sb.toString();
    }

    private static void appendAreaConditions(StringBuilder sql, List<String> areaTokens, String alias) {
        if (areaTokens == null || areaTokens.isEmpty()) return;
        for (int i = 0; i < areaTokens.size(); i++) {
            sql.append("AND (UPPER(ISNULL(").append(alias).append(".meter_name,'')) LIKE ? ");
            sql.append("OR EXISTS (SELECT 1 FROM dbo.meters m WHERE m.name = ").append(alias).append(".meter_name AND UPPER(ISNULL(m.panel_name,'')) LIKE ?)) ");
            sql.append("OR EXISTS (SELECT 1 FROM dbo.meters m WHERE m.name = ").append(alias).append(".meter_name AND UPPER(ISNULL(m.usage_type,'')) LIKE ?)) ");
        }
    }

    private static int bindAreaTokens(PreparedStatement ps, int startIndex, List<String> areaTokens) throws Exception {
        int pi = startIndex;
        if (areaTokens == null || areaTokens.isEmpty()) return pi;
        for (int i = 0; i < areaTokens.size(); i++) {
            String a = "%" + areaTokens.get(i).toUpperCase(Locale.ROOT) + "%";
            ps.setString(pi++, a);
            ps.setString(pi++, a);
            ps.setString(pi++, a);
        }
        return pi;
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

    private static String normalizeIntent(String s) {
        if (s == null) return "";
        return s.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
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

    private static final DecimalFormat DF = new DecimalFormat("0.00");
}
