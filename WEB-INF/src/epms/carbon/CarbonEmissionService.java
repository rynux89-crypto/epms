package epms.carbon;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class CarbonEmissionService {
    public static final String DEFAULT_FACTOR_CODE = "DEFAULT_ELECTRICITY";
    public static final String DEFAULT_SCOPE_ALL = "__ALL__";
    public static final double DEFAULT_FACTOR_VALUE = 0.45d;
    public static final String DEFAULT_FACTOR_SOURCE = "SYSTEM_DEFAULT";
    public static final String DEFAULT_FACTOR_NOTE = "Initial default factor. Update this value to match your reporting standard.";
    private static final int QUERY_TIMEOUT_SEC = 30;

    public Connection openConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public void refreshAllScopes() throws Exception {
        try (Connection conn = openConnection()) {
            ensureSchema(conn);
            refreshScope(conn, "");
            for (String building : listBuildings(conn)) {
                refreshScope(conn, building);
            }
        }
    }

    public void refreshScope(String building) throws Exception {
        try (Connection conn = openConnection()) {
            ensureSchema(conn);
            refreshScope(conn, building);
        }
    }

    private void refreshScope(Connection conn, String building) throws Exception {
        String safeBuilding = building == null ? "" : building.trim();
        String scopeCode = safeBuilding.isEmpty() ? DEFAULT_SCOPE_ALL : safeBuilding;

        FactorData factor = loadFactor(conn);

        LocalDate today = LocalDate.now();
        int yearlyStartYear = today.getYear() - 4;
        LocalDate startDate = LocalDate.of(yearlyStartYear, 1, 1);

        try (Statement st = conn.createStatement()) {
            st.setQueryTimeout(QUERY_TIMEOUT_SEC);
            st.execute("IF OBJECT_ID('tempdb..#carbon_day_diff_job') IS NOT NULL DROP TABLE #carbon_day_diff_job");
            st.execute("CREATE TABLE #carbon_day_diff_job (meter_id INT NOT NULL, d DATE NOT NULL, day_kwh FLOAT NULL)");
        }

        LinkedHashMap<LocalDate, Double> computedDailyUsage = new LinkedHashMap<LocalDate, Double>();
        for (LocalDate d = startDate; !d.isAfter(today); d = d.plusDays(1)) {
            computedDailyUsage.put(d, Double.valueOf(0.0d));
        }

        String populateSql =
                "WITH candidate_meters AS ( " +
                "  SELECT m.meter_id " +
                "  FROM dbo.meters m " +
                "  WHERE (? = '' OR ISNULL(m.building_name, '') = ?) " +
                "), root_meters AS ( " +
                "  SELECT cm.meter_id " +
                "  FROM candidate_meters cm " +
                "  WHERE EXISTS ( " +
                "    SELECT 1 FROM dbo.meter_tree t " +
                "    WHERE t.parent_meter_id = cm.meter_id AND ISNULL(t.is_active, 1) = 1 " +
                "  ) " +
                "  AND NOT EXISTS ( " +
                "    SELECT 1 FROM dbo.meter_tree t " +
                "    WHERE t.child_meter_id = cm.meter_id AND ISNULL(t.is_active, 1) = 1 " +
                "  ) " +
                "), selected_meters AS ( " +
                "  SELECT meter_id FROM root_meters " +
                "  UNION ALL " +
                "  SELECT meter_id FROM candidate_meters WHERE NOT EXISTS (SELECT 1 FROM root_meters) " +
                "), day_diff AS ( " +
                "  SELECT dm.meter_id, dm.measured_date AS d, CAST(dm.energy_consumed_kwh AS float) AS day_kwh " +
                "  FROM dbo.daily_measurements dm " +
                "  INNER JOIN selected_meters sm ON sm.meter_id = dm.meter_id " +
                "  WHERE dm.measured_date BETWEEN ? AND ? " +
                "    AND dm.energy_consumed_kwh IS NOT NULL " +
                ") " +
                "INSERT INTO #carbon_day_diff_job (meter_id, d, day_kwh) " +
                "SELECT meter_id, d, day_kwh FROM day_diff";

        try (PreparedStatement ps = conn.prepareStatement(populateSql)) {
            ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
            ps.setString(1, safeBuilding);
            ps.setString(2, safeBuilding);
            ps.setDate(3, Date.valueOf(startDate));
            ps.setDate(4, Date.valueOf(today));
            ps.executeUpdate();
        }

        try (Statement st = conn.createStatement()) {
            st.setQueryTimeout(QUERY_TIMEOUT_SEC);
            st.execute("CREATE CLUSTERED INDEX IX_carbon_day_diff_job_d_meter ON #carbon_day_diff_job (d, meter_id)");
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT d, SUM(CASE WHEN day_kwh >= 0 THEN day_kwh ELSE 0 END) AS sum_kwh " +
                "FROM #carbon_day_diff_job WHERE d BETWEEN ? AND ? GROUP BY d ORDER BY d")) {
            ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
            ps.setDate(1, Date.valueOf(startDate));
            ps.setDate(2, Date.valueOf(today));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Date dObj = rs.getDate("d");
                    if (dObj == null) continue;
                    LocalDate day = dObj.toLocalDate();
                    if (computedDailyUsage.containsKey(day)) {
                        computedDailyUsage.put(day, Double.valueOf(rs.getDouble("sum_kwh")));
                    }
                }
            }
        }

        Timestamp calculatedAt = new Timestamp(System.currentTimeMillis());
        try (PreparedStatement deletePs = conn.prepareStatement(
                "DELETE FROM dbo.epms_building_carbon_daily WHERE scope_code = ? AND emission_date BETWEEN ? AND ?");
             PreparedStatement insertPs = conn.prepareStatement(
                "INSERT INTO dbo.epms_building_carbon_daily " +
                "(scope_code, building_name, emission_date, usage_kwh, emission_factor, co2_kg, factor_source, factor_note, calculated_at) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")) {
            deletePs.setString(1, scopeCode);
            deletePs.setDate(2, Date.valueOf(startDate));
            deletePs.setDate(3, Date.valueOf(today));
            deletePs.executeUpdate();

            for (Map.Entry<LocalDate, Double> entry : computedDailyUsage.entrySet()) {
                double usageKwh = nz(entry.getValue());
                insertPs.setString(1, scopeCode);
                if (safeBuilding.isEmpty()) insertPs.setNull(2, java.sql.Types.NVARCHAR);
                else insertPs.setString(2, safeBuilding);
                insertPs.setDate(3, Date.valueOf(entry.getKey()));
                insertPs.setBigDecimal(4, decimal(usageKwh));
                insertPs.setBigDecimal(5, decimal(factor.value));
                insertPs.setBigDecimal(6, decimal(usageKwh * factor.value));
                insertPs.setString(7, factor.source);
                insertPs.setString(8, factor.note);
                insertPs.setTimestamp(9, calculatedAt);
                insertPs.addBatch();
            }
            insertPs.executeBatch();
        }
    }

    private FactorData loadFactor(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "IF NOT EXISTS (SELECT 1 FROM dbo.epms_carbon_factor WHERE factor_code = ?) " +
                "BEGIN " +
                "  INSERT INTO dbo.epms_carbon_factor (factor_code, factor_value, factor_unit, factor_source, factor_note) " +
                "  VALUES (?, ?, 'kgCO2_per_kWh', ?, ?) " +
                "END")) {
            ps.setString(1, DEFAULT_FACTOR_CODE);
            ps.setString(2, DEFAULT_FACTOR_CODE);
            ps.setBigDecimal(3, decimal(DEFAULT_FACTOR_VALUE));
            ps.setString(4, DEFAULT_FACTOR_SOURCE);
            ps.setString(5, DEFAULT_FACTOR_NOTE);
            ps.executeUpdate();
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT factor_value, factor_source, factor_note FROM dbo.epms_carbon_factor WHERE factor_code = ?")) {
            ps.setString(1, DEFAULT_FACTOR_CODE);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String source = rs.getString("factor_source");
                    String note = rs.getString("factor_note");
                    return new FactorData(
                            rs.getBigDecimal("factor_value").doubleValue(),
                            source == null || source.trim().isEmpty() ? DEFAULT_FACTOR_SOURCE : source.trim(),
                            note == null || note.trim().isEmpty() ? DEFAULT_FACTOR_NOTE : note.trim());
                }
            }
        }
        return new FactorData(DEFAULT_FACTOR_VALUE, DEFAULT_FACTOR_SOURCE, DEFAULT_FACTOR_NOTE);
    }

    private List<String> listBuildings(Connection conn) throws Exception {
        List<String> rows = new ArrayList<String>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT DISTINCT building_name " +
                "FROM dbo.meters WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name)) <> '' " +
                "ORDER BY building_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) rows.add(rs.getString(1));
        }
        return rows;
    }

    public void ensureSchema(Connection conn) throws Exception {
        try (Statement st = conn.createStatement()) {
            st.setQueryTimeout(QUERY_TIMEOUT_SEC);
            st.execute(
                    "IF OBJECT_ID('dbo.epms_carbon_factor', 'U') IS NULL " +
                    "BEGIN " +
                    "  CREATE TABLE dbo.epms_carbon_factor ( " +
                    "    factor_code varchar(50) NOT NULL PRIMARY KEY, " +
                    "    factor_value decimal(12,6) NOT NULL, " +
                    "    factor_unit varchar(32) NOT NULL CONSTRAINT DF_epms_carbon_factor_unit DEFAULT ('kgCO2_per_kWh'), " +
                    "    factor_source nvarchar(200) NULL, " +
                    "    factor_note nvarchar(500) NULL, " +
                    "    updated_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_updated_at DEFAULT (sysdatetime()) " +
                    "  ) " +
                    "END");
            st.execute(
                    "IF OBJECT_ID('dbo.epms_building_carbon_daily', 'U') IS NULL " +
                    "BEGIN " +
                    "  CREATE TABLE dbo.epms_building_carbon_daily ( " +
                    "    scope_code varchar(120) NOT NULL, " +
                    "    building_name nvarchar(200) NULL, " +
                    "    emission_date date NOT NULL, " +
                    "    usage_kwh decimal(18,6) NOT NULL, " +
                    "    emission_factor decimal(12,6) NOT NULL, " +
                    "    co2_kg decimal(18,6) NOT NULL, " +
                    "    factor_source nvarchar(200) NULL, " +
                    "    factor_note nvarchar(500) NULL, " +
                    "    calculated_at datetime2 NOT NULL CONSTRAINT DF_epms_building_carbon_daily_calculated_at DEFAULT (sysdatetime()), " +
                    "    CONSTRAINT PK_epms_building_carbon_daily PRIMARY KEY (scope_code, emission_date) " +
                    "  ) " +
                    "END");
        }
    }

    private static java.math.BigDecimal decimal(double value) {
        return new java.math.BigDecimal(String.format(Locale.US, "%.6f", value));
    }

    private static double nz(Double value) {
        return value == null ? 0.0d : value.doubleValue();
    }

    private static final class FactorData {
        private final double value;
        private final String source;
        private final String note;

        private FactorData(double value, String source, String note) {
            this.value = value;
            this.source = source;
            this.note = note;
        }
    }
}
