<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../../includes/dbconfig.jspf" %>
<%@ include file="../../includes/epms_html.jspf" %>
<%@ include file="../../includes/epms_json.jspf" %>
<%!
    private static final int QUERY_TIMEOUT_SEC = 30;
    private static final String DEFAULT_FACTOR_CODE = "DEFAULT_ELECTRICITY";
    private static final String DEFAULT_SCOPE_ALL = "__ALL__";
    private static final double DEFAULT_FACTOR_VALUE = 0.45d;
    private static final String DEFAULT_FACTOR_SOURCE = "SYSTEM_DEFAULT";
    private static final String DEFAULT_FACTOR_NOTE = "Initial default factor. Update this value to match your reporting standard.";

    private static double nz(Double value) {
        return value == null ? 0.0d : value.doubleValue();
    }

    private static Double parsePositiveDouble(String value) {
        try {
            if (value == null) return null;
            double parsed = Double.parseDouble(value.trim());
            return parsed > 0.0d ? Double.valueOf(parsed) : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    private static String trimToEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    private static String fmtNumber(double value, int decimals) {
        return String.format(java.util.Locale.US, "%,." + decimals + "f", value);
    }

    private static String fmtDateTime(Timestamp ts) {
        return ts == null ? "-" : ts.toString();
    }

    private static String normalizeFactorCode(String value) {
        String code = trimToEmpty(value).toUpperCase(java.util.Locale.US).replaceAll("[^A-Z0-9_\\-]", "_");
        return code.isEmpty() ? DEFAULT_FACTOR_CODE : code;
    }

    private static String generateFactorCode() {
        return "FACTOR_" + LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss_SSS"));
    }

    private static final class FactorOption {
        final String code;
        final String name;
        final double value;
        final String source;
        final String note;
        final Timestamp updatedAt;

        FactorOption(String code, String name, double value, String source, String note, Timestamp updatedAt) {
            this.code = code;
            this.name = name;
            this.value = value;
            this.source = source;
            this.note = note;
            this.updatedAt = updatedAt;
        }
    }
%>
<%
request.setCharacterEncoding("UTF-8");

String building = trimToEmpty(request.getParameter("building"));
String selectedFactorCode = normalizeFactorCode(request.getParameter("factor_code"));
String action = trimToEmpty(request.getParameter("action"));
String factorCodeInput = trimToEmpty(request.getParameter("factor_code_input"));
String factorNameInput = trimToEmpty(request.getParameter("factor_name"));
String factorInput = trimToEmpty(request.getParameter("factor_value"));
String factorSourceInput = trimToEmpty(request.getParameter("factor_source"));
String factorNoteInput = trimToEmpty(request.getParameter("factor_note"));

String flashOk = null;
String flashErr = null;
String flashOkParam = trimToEmpty(request.getParameter("msg"));
String flashErrParam = trimToEmpty(request.getParameter("err"));
if (!flashOkParam.isEmpty()) flashOk = flashOkParam;
if (!flashErrParam.isEmpty()) flashErr = flashErrParam;

LocalDate today = LocalDate.now();
LocalDate dailyStart = today.minusDays(29);
YearMonth currentYm = YearMonth.from(today);
LocalDate currentMonthStart = currentYm.atDay(1);
YearMonth monthlyStartYm = currentYm.minusMonths(11);
LocalDate monthlyStart = monthlyStartYm.atDay(1);
int currentYear = today.getYear();
int yearlyStartYear = currentYear - 4;
LocalDate yearStart = LocalDate.of(today.getYear(), 1, 1);

List<String> buildingOptions = new ArrayList<String>();
List<FactorOption> factorOptions = new ArrayList<FactorOption>();
LinkedHashMap<String, Double> dailyTotals = new LinkedHashMap<String, Double>();
LinkedHashMap<String, Double> monthlyTotals = new LinkedHashMap<String, Double>();
LinkedHashMap<Integer, Double> yearlyTotals = new LinkedHashMap<Integer, Double>();
LinkedHashMap<String, Double> dailyUsageTotals = new LinkedHashMap<String, Double>();
for (LocalDate d = dailyStart; !d.isAfter(today); d = d.plusDays(1)) dailyTotals.put(d.toString(), Double.valueOf(0.0d));
for (YearMonth ym = monthlyStartYm; !ym.isAfter(currentYm); ym = ym.plusMonths(1)) monthlyTotals.put(ym.toString(), Double.valueOf(0.0d));
for (int y = yearlyStartYear; y <= currentYear; y++) yearlyTotals.put(Integer.valueOf(y), Double.valueOf(0.0d));
for (LocalDate d = dailyStart; !d.isAfter(today); d = d.plusDays(1)) dailyUsageTotals.put(d.toString(), Double.valueOf(0.0d));

double appliedFactor = DEFAULT_FACTOR_VALUE;
String appliedFactorSource = DEFAULT_FACTOR_SOURCE;
String appliedFactorNote = DEFAULT_FACTOR_NOTE;
Timestamp factorUpdatedAt = null;
Timestamp lastCalculatedAt = null;

double todayKwh = 0.0d;
double currentMonthKwh = 0.0d;
double rolling12MonthKwh = 0.0d;
double currentYearKwh = 0.0d;
double todayCo2Kg = 0.0d;
double currentMonthCo2Kg = 0.0d;
double rolling12MonthCo2Kg = 0.0d;
double currentYearCo2Kg = 0.0d;
String queryError = null;
String scopeCode = building.isEmpty() ? DEFAULT_SCOPE_ALL : building;
String scopeLabel = building.isEmpty() ? "전체 건물" : building;

try (Connection conn = openDbConnection()) {
    if ("save_factor".equals(action)) {
    try (Statement st = conn.createStatement()) {
        st.setQueryTimeout(QUERY_TIMEOUT_SEC);
        st.execute(
            "IF OBJECT_ID('dbo.epms_carbon_factor', 'U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.epms_carbon_factor ( " +
            "    factor_code varchar(50) NOT NULL PRIMARY KEY, " +
            "    factor_name nvarchar(120) NULL, " +
            "    factor_value decimal(12,6) NOT NULL, " +
            "    factor_unit varchar(32) NOT NULL CONSTRAINT DF_epms_carbon_factor_unit DEFAULT ('kgCO2_per_kWh'), " +
            "    factor_source nvarchar(200) NULL, " +
            "    factor_note nvarchar(500) NULL, " +
            "    is_active bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_active DEFAULT (1), " +
            "    is_default bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_default DEFAULT (0), " +
            "    created_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_created_at DEFAULT (sysdatetime()), " +
            "    updated_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_updated_at DEFAULT (sysdatetime()) " +
            "  ) " +
            "END");
        st.execute("IF COL_LENGTH('dbo.epms_carbon_factor', 'factor_name') IS NULL ALTER TABLE dbo.epms_carbon_factor ADD factor_name nvarchar(120) NULL");
        st.execute("IF COL_LENGTH('dbo.epms_carbon_factor', 'is_active') IS NULL ALTER TABLE dbo.epms_carbon_factor ADD is_active bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_active DEFAULT (1)");
        st.execute("IF COL_LENGTH('dbo.epms_carbon_factor', 'is_default') IS NULL ALTER TABLE dbo.epms_carbon_factor ADD is_default bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_default DEFAULT (0)");
        st.execute("IF COL_LENGTH('dbo.epms_carbon_factor', 'created_at') IS NULL ALTER TABLE dbo.epms_carbon_factor ADD created_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_created_at DEFAULT (sysdatetime())");
        st.execute(
            "IF OBJECT_ID('dbo.epms_building_carbon_daily', 'U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.epms_building_carbon_daily ( " +
            "    scope_code varchar(120) NOT NULL, " +
            "    building_name nvarchar(200) NULL, " +
            "    emission_date date NOT NULL, " +
            "    factor_code varchar(50) NULL, " +
            "    usage_kwh decimal(18,6) NOT NULL, " +
            "    emission_factor decimal(12,6) NOT NULL, " +
            "    co2_kg decimal(18,6) NOT NULL, " +
            "    factor_source nvarchar(200) NULL, " +
            "    factor_note nvarchar(500) NULL, " +
            "    calculated_at datetime2 NOT NULL CONSTRAINT DF_epms_building_carbon_daily_calculated_at DEFAULT (sysdatetime()), " +
            "    CONSTRAINT PK_epms_building_carbon_daily PRIMARY KEY (scope_code, emission_date) " +
            "  ) " +
            "END");
        st.execute("IF COL_LENGTH('dbo.epms_building_carbon_daily', 'factor_code') IS NULL ALTER TABLE dbo.epms_building_carbon_daily ADD factor_code varchar(50) NULL");
        st.execute(
            "IF OBJECT_ID('dbo.epms_carbon_factor_history', 'U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.epms_carbon_factor_history ( " +
            "    history_id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY, " +
            "    factor_code varchar(50) NOT NULL, " +
            "    factor_name nvarchar(120) NULL, " +
            "    factor_value decimal(12,6) NOT NULL, " +
            "    factor_unit varchar(32) NOT NULL, " +
            "    factor_source nvarchar(200) NULL, " +
            "    factor_note nvarchar(500) NULL, " +
            "    change_action varchar(20) NOT NULL, " +
            "    changed_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_history_changed_at DEFAULT (sysdatetime()) " +
            "  ) " +
            "END");
    }
    }

    if ("save_factor".equals(action)) {
        Double parsedFactor = parsePositiveDouble(factorInput);
        String actualFactorCode = factorCodeInput.isEmpty() ? generateFactorCode() : normalizeFactorCode(factorCodeInput);
        String actualFactorName = factorNameInput.isEmpty() ? actualFactorCode : factorNameInput;
        if (parsedFactor == null) {
            flashErr = "배출계수는 0보다 큰 숫자로 입력해 주세요.";
        } else {
            String actualSource = factorSourceInput.isEmpty() ? DEFAULT_FACTOR_SOURCE : factorSourceInput;
            String actualNote = factorNoteInput.isEmpty() ? DEFAULT_FACTOR_NOTE : factorNoteInput;
            boolean existed = false;
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT 1 FROM dbo.epms_carbon_factor WHERE factor_code = ?")) {
                ps.setString(1, actualFactorCode);
                try (ResultSet rs = ps.executeQuery()) {
                    existed = rs.next();
                }
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "MERGE dbo.epms_carbon_factor AS target " +
                    "USING (SELECT ? AS factor_code) AS source " +
                    "ON target.factor_code = source.factor_code " +
                    "WHEN MATCHED THEN " +
                    "  UPDATE SET factor_name = ?, factor_value = ?, factor_source = ?, factor_note = ?, is_active = 1, updated_at = sysdatetime() " +
                    "WHEN NOT MATCHED THEN " +
                    "  INSERT (factor_code, factor_name, factor_value, factor_unit, factor_source, factor_note, is_active, is_default, created_at, updated_at) " +
                    "  VALUES (?, ?, ?, 'kgCO2_per_kWh', ?, ?, 1, 0, sysdatetime(), sysdatetime());")) {
                ps.setString(1, actualFactorCode);
                ps.setString(2, actualFactorName);
                ps.setBigDecimal(3, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", parsedFactor.doubleValue())));
                ps.setString(4, actualSource);
                ps.setString(5, actualNote);
                ps.setString(6, actualFactorCode);
                ps.setString(7, actualFactorName);
                ps.setBigDecimal(8, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", parsedFactor.doubleValue())));
                ps.setString(9, actualSource);
                ps.setString(10, actualNote);
                ps.executeUpdate();
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO dbo.epms_carbon_factor_history " +
                    "(factor_code, factor_name, factor_value, factor_unit, factor_source, factor_note, change_action) " +
                    "VALUES (?, ?, ?, 'kgCO2_per_kWh', ?, ?, ?)")) {
                ps.setString(1, actualFactorCode);
                ps.setString(2, actualFactorName);
                ps.setBigDecimal(3, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", parsedFactor.doubleValue())));
                ps.setString(4, actualSource);
                ps.setString(5, actualNote);
                ps.setString(6, existed ? "UPDATE" : "CREATE");
                ps.executeUpdate();
            }
            selectedFactorCode = actualFactorCode;
            flashOk = existed ? "배출계수를 수정하고 이력을 저장했습니다." : "배출계수를 추가하고 이력을 저장했습니다.";
        }
    }

    boolean factorTableExists = false;
    boolean carbonDailyTableExists = false;
    try (Statement st = conn.createStatement()) {
        st.setQueryTimeout(QUERY_TIMEOUT_SEC);
        try (ResultSet rs = st.executeQuery("SELECT CASE WHEN OBJECT_ID('dbo.epms_carbon_factor', 'U') IS NULL THEN 0 ELSE 1 END")) {
            if (rs.next()) factorTableExists = rs.getInt(1) == 1;
        }
        try (ResultSet rs = st.executeQuery("SELECT CASE WHEN OBJECT_ID('dbo.epms_building_carbon_daily', 'U') IS NULL THEN 0 ELSE 1 END")) {
            if (rs.next()) carbonDailyTableExists = rs.getInt(1) == 1;
        }
    }

    if (factorTableExists) {
    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT factor_code, ISNULL(factor_name, factor_code) AS factor_name, factor_value, factor_source, factor_note, updated_at " +
            "FROM dbo.epms_carbon_factor WHERE ISNULL(is_active, 1) = 1 ORDER BY is_default DESC, factor_code")) {
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                factorOptions.add(new FactorOption(
                    rs.getString("factor_code"),
                    rs.getString("factor_name"),
                    rs.getBigDecimal("factor_value").doubleValue(),
                    trimToEmpty(rs.getString("factor_source")),
                    trimToEmpty(rs.getString("factor_note")),
                    rs.getTimestamp("updated_at")));
            }
        }
    }
    }

    if (factorOptions.isEmpty()) {
        factorOptions.add(new FactorOption(DEFAULT_FACTOR_CODE, "Default electricity factor", DEFAULT_FACTOR_VALUE, DEFAULT_FACTOR_SOURCE, DEFAULT_FACTOR_NOTE, null));
    }
    boolean selectedFactorExists = false;
    for (FactorOption opt : factorOptions) {
        if (opt.code.equals(selectedFactorCode)) {
            selectedFactorExists = true;
            break;
        }
    }
    if (!selectedFactorExists) selectedFactorCode = DEFAULT_FACTOR_CODE;

    if (factorTableExists) {
    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT factor_code, factor_value, factor_source, factor_note, updated_at " +
            "FROM dbo.epms_carbon_factor WHERE factor_code = ? AND ISNULL(is_active, 1) = 1")) {
        ps.setString(1, selectedFactorCode);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                selectedFactorCode = rs.getString("factor_code");
                appliedFactor = rs.getBigDecimal("factor_value").doubleValue();
                appliedFactorSource = trimToEmpty(rs.getString("factor_source"));
                if (appliedFactorSource.isEmpty()) appliedFactorSource = DEFAULT_FACTOR_SOURCE;
                appliedFactorNote = trimToEmpty(rs.getString("factor_note"));
                if (appliedFactorNote.isEmpty()) appliedFactorNote = DEFAULT_FACTOR_NOTE;
                factorUpdatedAt = rs.getTimestamp("updated_at");
            }
        }
    }
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT DISTINCT building_name " +
            "FROM dbo.meters " +
            "WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name)) <> '' " +
            "ORDER BY building_name");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) buildingOptions.add(rs.getString(1));
    }

    if (carbonDailyTableExists) {
    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT emission_date, usage_kwh, co2_kg " +
            "FROM dbo.epms_building_carbon_daily " +
            "WHERE scope_code = ? AND emission_date BETWEEN ? AND ? ORDER BY emission_date")) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setString(1, scopeCode);
        ps.setDate(2, java.sql.Date.valueOf(dailyStart));
        ps.setDate(3, java.sql.Date.valueOf(today));
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                java.sql.Date dObj = rs.getDate("emission_date");
                if (dObj == null) continue;
                String key = dObj.toLocalDate().toString();
                if (dailyTotals.containsKey(key)) dailyTotals.put(key, Double.valueOf(rs.getDouble("co2_kg") / 1000.0d));
                if (dailyUsageTotals.containsKey(key)) dailyUsageTotals.put(key, Double.valueOf(rs.getDouble("usage_kwh")));
            }
        }
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT MAX(calculated_at) AS last_calculated_at " +
            "FROM dbo.epms_building_carbon_daily WHERE scope_code = ?")) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setString(1, scopeCode);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) lastCalculatedAt = rs.getTimestamp("last_calculated_at");
        }
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT CONVERT(char(7), emission_date, 126) AS ym, SUM(co2_kg) AS sum_co2_kg " +
            "FROM dbo.epms_building_carbon_daily " +
            "WHERE scope_code = ? AND emission_date BETWEEN ? AND ? " +
            "GROUP BY CONVERT(char(7), emission_date, 126) ORDER BY ym")) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setString(1, scopeCode);
        ps.setDate(2, java.sql.Date.valueOf(monthlyStart));
        ps.setDate(3, java.sql.Date.valueOf(today));
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String key = rs.getString("ym");
                if (key != null && monthlyTotals.containsKey(key)) monthlyTotals.put(key, Double.valueOf(rs.getDouble("sum_co2_kg") / 1000.0d));
            }
        }
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT YEAR(emission_date) AS yy, SUM(co2_kg) AS sum_co2_kg " +
            "FROM dbo.epms_building_carbon_daily " +
            "WHERE scope_code = ? AND emission_date BETWEEN ? AND ? " +
            "GROUP BY YEAR(emission_date) ORDER BY yy")) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setString(1, scopeCode);
        ps.setDate(2, java.sql.Date.valueOf(LocalDate.of(yearlyStartYear, 1, 1)));
        ps.setDate(3, java.sql.Date.valueOf(today));
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Integer key = Integer.valueOf(rs.getInt("yy"));
                if (yearlyTotals.containsKey(key)) yearlyTotals.put(key, Double.valueOf(rs.getDouble("sum_co2_kg") / 1000.0d));
            }
        }
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT " +
            "  SUM(CASE WHEN emission_date = ? THEN usage_kwh ELSE 0 END) AS today_kwh, " +
            "  SUM(CASE WHEN emission_date BETWEEN ? AND ? THEN usage_kwh ELSE 0 END) AS current_month_kwh, " +
            "  SUM(CASE WHEN emission_date BETWEEN ? AND ? THEN usage_kwh ELSE 0 END) AS rolling_12m_kwh, " +
            "  SUM(CASE WHEN emission_date BETWEEN ? AND ? THEN usage_kwh ELSE 0 END) AS current_year_kwh, " +
            "  SUM(CASE WHEN emission_date = ? THEN co2_kg ELSE 0 END) AS today_co2_kg, " +
            "  SUM(CASE WHEN emission_date BETWEEN ? AND ? THEN co2_kg ELSE 0 END) AS current_month_co2_kg, " +
            "  SUM(CASE WHEN emission_date BETWEEN ? AND ? THEN co2_kg ELSE 0 END) AS rolling_12m_co2_kg, " +
            "  SUM(CASE WHEN emission_date BETWEEN ? AND ? THEN co2_kg ELSE 0 END) AS current_year_co2_kg " +
            "FROM dbo.epms_building_carbon_daily WHERE scope_code = ?")) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setDate(1, java.sql.Date.valueOf(today));
        ps.setDate(2, java.sql.Date.valueOf(currentMonthStart));
        ps.setDate(3, java.sql.Date.valueOf(today));
        ps.setDate(4, java.sql.Date.valueOf(monthlyStart));
        ps.setDate(5, java.sql.Date.valueOf(today));
        ps.setDate(6, java.sql.Date.valueOf(yearStart));
        ps.setDate(7, java.sql.Date.valueOf(today));
        ps.setDate(8, java.sql.Date.valueOf(today));
        ps.setDate(9, java.sql.Date.valueOf(currentMonthStart));
        ps.setDate(10, java.sql.Date.valueOf(today));
        ps.setDate(11, java.sql.Date.valueOf(monthlyStart));
        ps.setDate(12, java.sql.Date.valueOf(today));
        ps.setDate(13, java.sql.Date.valueOf(yearStart));
        ps.setDate(14, java.sql.Date.valueOf(today));
        ps.setString(15, scopeCode);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                todayKwh = rs.getDouble("today_kwh");
                currentMonthKwh = rs.getDouble("current_month_kwh");
                rolling12MonthKwh = rs.getDouble("rolling_12m_kwh");
                currentYearKwh = rs.getDouble("current_year_kwh");
                todayCo2Kg = rs.getDouble("today_co2_kg");
                currentMonthCo2Kg = rs.getDouble("current_month_co2_kg");
                rolling12MonthCo2Kg = rs.getDouble("rolling_12m_co2_kg");
                currentYearCo2Kg = rs.getDouble("current_year_co2_kg");
            }
        }
    }
    }
} catch (Exception e) {
    queryError = e.getMessage();
}
%>
<!doctype html>
<html>
<head>
    <meta charset="UTF-8">
    <title>건물 탄소배출량 조회</title>
    <script src="../../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1560px;margin:10px auto;padding:0 10px}
        .page-wrap{display:grid;gap:10px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px}
        .page-head h1{margin:0 0 4px;font-size:28px;line-height:1.1}
        .page-head p{margin:0;font-size:13px;line-height:1.45;color:#5b7188}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;padding:8px 14px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff}
        .panel-box{padding:10px;border:1px solid #d9dfe8;border-radius:8px;background:#fff;box-shadow:none}
        .panel-box h2{margin:0 0 8px;font-size:17px;line-height:1.2}
        .notice{padding:10px 12px;border-radius:10px;font-weight:700}
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .toolbar{display:grid;grid-template-columns:1fr 1fr;gap:12px;align-items:start}
        .field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
        .filter-form{display:grid;grid-template-columns:minmax(160px,1fr) minmax(220px,1.4fr) auto;gap:8px;align-items:end}
        .factor-form{display:grid;grid-template-columns:minmax(180px,1.2fr) minmax(130px,.7fr) minmax(180px,1.1fr) auto;gap:8px;align-items:end}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field input,.field select{width:100%;min-width:0}
        .toolbar .field input,.toolbar .field select,.toolbar .btn{height:36px;box-sizing:border-box}
        .toolbar .field input,.toolbar .field select{padding:0 10px;line-height:34px}
        .toolbar .btn{display:inline-flex;align-items:center;justify-content:center;padding:0 14px;line-height:1}
        .actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
        .inline-action{align-self:end;white-space:nowrap}
        .selected-summary{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px;font-size:11px;color:#1f3347;font-weight:700}
        .selected-summary span{display:inline-flex;align-items:center;min-height:24px;padding:4px 8px;border:1px solid #dbe5ef;border-radius:999px;background:#f8fbfd}
        .form-note{grid-column:1 / -1;margin-top:-2px}
        .kpi-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}
        .kpi-card{padding:10px;border:1px solid #d9e2ec;border-radius:10px;background:linear-gradient(180deg,#fff 0%,#f8fbfd 100%)}
        .kpi-label{font-size:11px;color:#5b7188;font-weight:700}
        .kpi-value{margin-top:4px;font-size:21px;font-weight:900;color:#19324d;line-height:1.08}
        .kpi-sub{margin-top:4px;font-size:11px;color:#64748b}
        .meta-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}
        .meta-item{padding:8px;border:1px solid #e2e8f0;border-radius:8px;background:#fafcff}
        .meta-label{font-size:11px;color:#64748b;font-weight:700}
        .meta-value{margin-top:3px;font-size:12px;font-weight:800;color:#223447}
        .chart-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
        .chart-panel{padding:8px;border:1px solid #d9dfe8;border-radius:8px;background:#fff}
        .chart-panel h3{margin:0 0 6px;color:#1f3347;font-size:14px}
        .chart-box{height:310px}
        .hint{font-size:11px;color:#64748b;line-height:1.35}
        .page-footer{margin-top:10px;text-align:center;color:#6d8298;font-size:11px}
        @media (min-width:1280px){
            body{height:100vh;overflow:auto}
            .page-wrap{gap:8px}
            .toolbar{gap:10px}
            .kpi-grid,.meta-grid,.chart-grid{gap:8px}
            .chart-box{height:260px}
            .hint{font-size:10px;line-height:1.3}
            .panel-box{padding:8px}
            .field-grid{gap:6px}
            .actions{gap:6px}
        }
        @media (max-width:1180px){.toolbar,.chart-grid,.kpi-grid,.meta-grid,.field-grid,.filter-form,.factor-form{grid-template-columns:1fr}.inline-action{width:100%}.inline-action .btn{width:100%}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>건물 탄소배출량 조회</h1>
            <p>건물 단위 전력사용량(kWh)을 기준으로 CO2 배출량을 계산합니다. 기본 배출계수는 DB에 저장되며, 대외보고 기준에 맞게 이 화면에서 수정할 수 있습니다.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="energy_overview.jsp">에너지 현황</a>
            <a class="btn" href="energy_manage.jsp">에너지 분석</a>
            <a class="btn" href="../epms_main.jsp">EPMS 홈</a>
        </div>
    </div>

    <% if (flashOk != null) { %><div class="notice ok"><%= h(flashOk) %></div><% } %>
    <% if (flashErr != null) { %><div class="notice err"><%= h(flashErr) %></div><% } %>
    <% if (queryError != null && !queryError.trim().isEmpty()) { %><div class="notice err">조회 오류: <%= h(queryError) %></div><% } %>

    <div class="toolbar">
        <div class="panel-box">
            <h2>조회 조건</h2>
            <form method="post" action="<%= request.getContextPath() %>/carbon-emission-action" class="filter-form" id="scopeFilterForm">
                <input type="hidden" name="action" id="scopeActionInput" value="<%= building.isEmpty() ? "recalc_all" : "recalc_scope" %>">
                <div class="field">
                    <label>건물</label>
                    <select name="building" id="buildingSelect">
                        <option value="">전체 건물</option>
                        <% for (String opt : buildingOptions) { %>
                        <option value="<%= h(opt) %>" <%= opt.equals(building) ? "selected" : "" %>><%= h(opt) %></option>
                        <% } %>
                    </select>
                </div>
                <div class="field">
                    <label>적용 배출계수</label>
                    <select name="factor_code" id="factorSelect">
                        <% for (FactorOption opt : factorOptions) { %>
                        <option value="<%= h(opt.code) %>" <%= opt.code.equals(selectedFactorCode) ? "selected" : "" %>><%= h(opt.name) %> - <%= fmtNumber(opt.value, 6) %></option>
                        <% } %>
                    </select>
                </div>
                <div class="actions inline-action">
                    <button type="submit" class="btn btn-primary">계산 후 조회</button>
                </div>
            </form>
        </div>

        <div class="panel-box">
            <h2>배출계수 설정</h2>
            <form method="post" class="factor-form">
                <input type="hidden" name="action" value="save_factor">
                <input type="hidden" name="factor_code" value="<%= h(selectedFactorCode) %>">
                <input type="hidden" name="building" value="<%= h(building) %>">
                <div class="field">
                    <label>계수명</label>
                    <input type="text" name="factor_name" value="" placeholder="예: 2026 전력 배출계수">
                </div>
                <div class="field">
                    <label>배출계수 (kgCO2/kWh)</label>
                    <input type="text" name="factor_value" value="<%= fmtNumber(appliedFactor, 6) %>">
                </div>
                <div class="field">
                    <label>출처 / 기준</label>
                    <input type="text" name="factor_source" value="<%= h(appliedFactorSource) %>" placeholder="예: 내부 기준, 공시 기준, ESG 보고 기준">
                </div>
                <div class="actions inline-action">
                    <button type="submit" class="btn btn-primary">배출계수 저장</button>
                </div>
            </form>
        </div>
    </div>

    <div class="kpi-grid">
        <div class="kpi-card">
            <div class="kpi-label">금일 탄소배출량</div>
            <div class="kpi-value"><%= fmtNumber(todayCo2Kg / 1000.0d, 3) %> tCO2</div>
            <div class="kpi-sub"><%= fmtNumber(todayKwh, 1) %> kWh 기준</div>
        </div>
        <div class="kpi-card">
            <div class="kpi-label">당월 탄소배출량</div>
            <div class="kpi-value"><%= fmtNumber(currentMonthCo2Kg / 1000.0d, 3) %> tCO2</div>
            <div class="kpi-sub"><%= fmtNumber(currentMonthKwh, 1) %> kWh 기준</div>
        </div>
        <div class="kpi-card">
            <div class="kpi-label">최근 12개월 탄소배출량</div>
            <div class="kpi-value"><%= fmtNumber(rolling12MonthCo2Kg / 1000.0d, 3) %> tCO2</div>
            <div class="kpi-sub"><%= fmtNumber(rolling12MonthKwh, 1) %> kWh 기준</div>
        </div>
        <div class="kpi-card">
            <div class="kpi-label">금년 누적 탄소배출량</div>
            <div class="kpi-value"><%= fmtNumber(currentYearCo2Kg / 1000.0d, 3) %> tCO2</div>
            <div class="kpi-sub"><%= fmtNumber(currentYearKwh, 1) %> kWh 기준</div>
        </div>
    </div>

    <div class="meta-grid">
        <div class="meta-item">
            <div class="meta-label">조회 범위</div>
            <div class="meta-value"><%= h(scopeLabel) %></div>
        </div>
        <div class="meta-item">
            <div class="meta-label">배출계수</div>
            <div class="meta-value"><%= fmtNumber(appliedFactor, 6) %> kgCO2/kWh</div>
        </div>
        <div class="meta-item">
            <div class="meta-label">출처 / 기준</div>
            <div class="meta-value"><%= h(appliedFactorSource) %></div>
        </div>
        <div class="meta-item">
            <div class="meta-label">최근 수정 시각</div>
            <div class="meta-value"><%= h(fmtDateTime(factorUpdatedAt)) %></div>
        </div>
        <div class="meta-item">
            <div class="meta-label">집계 저장 시각</div>
            <div class="meta-value"><%= h(fmtDateTime(lastCalculatedAt)) %></div>
        </div>
    </div>

    <div class="chart-grid">
        <div class="chart-panel">
            <h3>최근 30일 일별 탄소배출량</h3>
            <div id="dailyCarbonChart" class="chart-box"></div>
        </div>
        <div class="chart-panel">
            <h3>최근 12개월 월별 탄소배출량</h3>
            <div id="monthlyCarbonChart" class="chart-box"></div>
        </div>
        <div class="chart-panel">
            <h3>최근 5개년 연도별 탄소배출량</h3>
            <div id="yearlyCarbonChart" class="chart-box"></div>
        </div>
    </div>
</div>

<script>
const dailyLabels = [<%
    boolean first = true;
    for (String label : dailyTotals.keySet()) {
        if (!first) out.print(",");
        out.print("\"" + escJson(label) + "\"");
        first = false;
    }
%>];
const dailyCarbonValues = [<%
    first = true;
    for (Double value : dailyTotals.values()) {
        if (!first) out.print(",");
        out.print(String.format(java.util.Locale.US, "%.6f", nz(value)));
        first = false;
    }
%>];
const monthlyLabels = [<%
    first = true;
    for (String label : monthlyTotals.keySet()) {
        if (!first) out.print(",");
        out.print("\"" + escJson(label) + "\"");
        first = false;
    }
%>];
const monthlyCarbonValues = [<%
    first = true;
    for (Double value : monthlyTotals.values()) {
        if (!first) out.print(",");
        out.print(String.format(java.util.Locale.US, "%.6f", nz(value)));
        first = false;
    }
%>];
const yearlyLabels = [<%
    first = true;
    for (Integer label : yearlyTotals.keySet()) {
        if (!first) out.print(",");
        out.print("\"" + label + "\"");
        first = false;
    }
%>];
const yearlyCarbonValues = [<%
    first = true;
    for (Double value : yearlyTotals.values()) {
        if (!first) out.print(",");
        out.print(String.format(java.util.Locale.US, "%.6f", nz(value)));
        first = false;
    }
%>];

const dailyCarbonChart = echarts.init(document.getElementById('dailyCarbonChart'));
dailyCarbonChart.setOption({
  tooltip: { trigger: 'axis', valueFormatter: function (value) { return Number(value).toFixed(3) + ' tCO2'; } },
  grid: { left: 52, right: 18, top: 28, bottom: 42 },
  xAxis: { type: 'category', data: dailyLabels, axisLabel: { rotate: 45 } },
  yAxis: { type: 'value', name: 'tCO2' },
  series: [{ type: 'bar', data: dailyCarbonValues, itemStyle: { color: '#2f7d32' } }]
});

const monthlyCarbonChart = echarts.init(document.getElementById('monthlyCarbonChart'));
monthlyCarbonChart.setOption({
  tooltip: { trigger: 'axis', valueFormatter: function (value) { return Number(value).toFixed(3) + ' tCO2'; } },
  grid: { left: 52, right: 18, top: 28, bottom: 42 },
  xAxis: { type: 'category', data: monthlyLabels, axisLabel: { rotate: 45 } },
  yAxis: { type: 'value', name: 'tCO2' },
  series: [{ type: 'line', smooth: true, data: monthlyCarbonValues, itemStyle: { color: '#0f766e' }, areaStyle: { color: 'rgba(15,118,110,0.12)' } }]
});

const yearlyCarbonChart = echarts.init(document.getElementById('yearlyCarbonChart'));
yearlyCarbonChart.setOption({
  tooltip: { trigger: 'axis', valueFormatter: function (value) { return Number(value).toFixed(3) + ' tCO2'; } },
  grid: { left: 52, right: 18, top: 28, bottom: 42 },
  xAxis: { type: 'category', data: yearlyLabels },
  yAxis: { type: 'value', name: 'tCO2' },
  series: [{ type: 'bar', data: yearlyCarbonValues, itemStyle: { color: '#1d4ed8' } }]
});

window.addEventListener('resize', function () {
  dailyCarbonChart.resize();
  monthlyCarbonChart.resize();
  yearlyCarbonChart.resize();
});

var buildingSelect = document.getElementById('buildingSelect');
var factorSelect = document.getElementById('factorSelect');
var scopeActionInput = document.getElementById('scopeActionInput');
if (buildingSelect) {
  var syncScopeSelection = function () {
    if (scopeActionInput) {
      scopeActionInput.value = buildingSelect.value ? 'recalc_scope' : 'recalc_all';
    }
  };
  syncScopeSelection();
  buildingSelect.addEventListener('change', syncScopeSelection);
}
</script>
<footer class="page-footer">EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
