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
%>
<%
request.setCharacterEncoding("UTF-8");

String building = trimToEmpty(request.getParameter("building"));
String action = trimToEmpty(request.getParameter("action"));
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

    if ("save_factor".equals(action)) {
        Double parsedFactor = parsePositiveDouble(factorInput);
        if (parsedFactor == null) {
            flashErr = "배출계수는 0보다 큰 숫자로 입력해 주세요.";
        } else {
            String actualSource = factorSourceInput.isEmpty() ? DEFAULT_FACTOR_SOURCE : factorSourceInput;
            String actualNote = factorNoteInput.isEmpty() ? DEFAULT_FACTOR_NOTE : factorNoteInput;
            try (PreparedStatement ps = conn.prepareStatement(
                    "MERGE dbo.epms_carbon_factor AS target " +
                    "USING (SELECT ? AS factor_code) AS source " +
                    "ON target.factor_code = source.factor_code " +
                    "WHEN MATCHED THEN " +
                    "  UPDATE SET factor_value = ?, factor_source = ?, factor_note = ?, updated_at = sysdatetime() " +
                    "WHEN NOT MATCHED THEN " +
                    "  INSERT (factor_code, factor_value, factor_unit, factor_source, factor_note, updated_at) " +
                    "  VALUES (?, ?, 'kgCO2_per_kWh', ?, ?, sysdatetime());")) {
                ps.setString(1, DEFAULT_FACTOR_CODE);
                ps.setBigDecimal(2, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", parsedFactor.doubleValue())));
                ps.setString(3, actualSource);
                ps.setString(4, actualNote);
                ps.setString(5, DEFAULT_FACTOR_CODE);
                ps.setBigDecimal(6, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", parsedFactor.doubleValue())));
                ps.setString(7, actualSource);
                ps.setString(8, actualNote);
                ps.executeUpdate();
                flashOk = "배출계수를 저장했습니다.";
            }
        }
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "IF NOT EXISTS (SELECT 1 FROM dbo.epms_carbon_factor WHERE factor_code = ?) " +
            "BEGIN " +
            "  INSERT INTO dbo.epms_carbon_factor (factor_code, factor_value, factor_unit, factor_source, factor_note) " +
            "  VALUES (?, ?, 'kgCO2_per_kWh', ?, ?) " +
            "END")) {
        ps.setString(1, DEFAULT_FACTOR_CODE);
        ps.setString(2, DEFAULT_FACTOR_CODE);
        ps.setBigDecimal(3, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", DEFAULT_FACTOR_VALUE)));
        ps.setString(4, DEFAULT_FACTOR_SOURCE);
        ps.setString(5, DEFAULT_FACTOR_NOTE);
        ps.executeUpdate();
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT factor_value, factor_source, factor_note, updated_at " +
            "FROM dbo.epms_carbon_factor WHERE factor_code = ?")) {
        ps.setString(1, DEFAULT_FACTOR_CODE);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                appliedFactor = rs.getBigDecimal("factor_value").doubleValue();
                appliedFactorSource = trimToEmpty(rs.getString("factor_source"));
                if (appliedFactorSource.isEmpty()) appliedFactorSource = DEFAULT_FACTOR_SOURCE;
                appliedFactorNote = trimToEmpty(rs.getString("factor_note"));
                if (appliedFactorNote.isEmpty()) appliedFactorNote = DEFAULT_FACTOR_NOTE;
                factorUpdatedAt = rs.getTimestamp("updated_at");
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

    try (Statement st = conn.createStatement()) {
        st.setQueryTimeout(QUERY_TIMEOUT_SEC);
        st.execute("IF OBJECT_ID('tempdb..#carbon_day_diff') IS NOT NULL DROP TABLE #carbon_day_diff");
        st.execute("CREATE TABLE #carbon_day_diff (meter_id INT NOT NULL, d DATE NOT NULL, day_kwh FLOAT NULL)");
    }

    LinkedHashMap<LocalDate, Double> computedDailyUsage = new LinkedHashMap<LocalDate, Double>();
    for (LocalDate d = LocalDate.of(yearlyStartYear, 1, 1); !d.isAfter(today); d = d.plusDays(1)) {
        computedDailyUsage.put(d, Double.valueOf(0.0d));
    }

    String populateSql =
        "WITH day_diff AS ( " +
        "  SELECT dm.meter_id, dm.measured_date AS d, CAST(dm.energy_consumed_kwh AS float) AS day_kwh " +
        "  FROM dbo.daily_measurements dm " +
        "  INNER JOIN dbo.meters m ON m.meter_id = dm.meter_id " +
        "  WHERE dm.measured_date BETWEEN ? AND ? " +
        "    AND (? = '' OR ISNULL(m.building_name, '') = ?) " +
        "    AND dm.energy_consumed_kwh IS NOT NULL " +
        ") " +
        "INSERT INTO #carbon_day_diff (meter_id, d, day_kwh) " +
        "SELECT meter_id, d, day_kwh FROM day_diff";

    try (PreparedStatement ps = conn.prepareStatement(populateSql)) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setDate(1, java.sql.Date.valueOf(LocalDate.of(yearlyStartYear, 1, 1)));
        ps.setDate(2, java.sql.Date.valueOf(today));
        ps.setString(3, building);
        ps.setString(4, building);
        ps.executeUpdate();
    }

    try (Statement st = conn.createStatement()) {
        st.setQueryTimeout(QUERY_TIMEOUT_SEC);
        st.execute("CREATE CLUSTERED INDEX IX_carbon_day_diff_d_meter ON #carbon_day_diff (d, meter_id)");
    }

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT d, SUM(CASE WHEN day_kwh >= 0 THEN day_kwh ELSE 0 END) AS sum_kwh " +
            "FROM #carbon_day_diff WHERE d BETWEEN ? AND ? GROUP BY d ORDER BY d")) {
        ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
        ps.setDate(1, java.sql.Date.valueOf(dailyStart));
        ps.setDate(2, java.sql.Date.valueOf(today));
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                java.sql.Date dObj = rs.getDate("d");
                if (dObj == null) continue;
                LocalDate keyDate = dObj.toLocalDate();
                if (computedDailyUsage.containsKey(keyDate)) computedDailyUsage.put(keyDate, Double.valueOf(rs.getDouble("sum_kwh")));
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
        deletePs.setDate(2, java.sql.Date.valueOf(LocalDate.of(yearlyStartYear, 1, 1)));
        deletePs.setDate(3, java.sql.Date.valueOf(today));
        deletePs.executeUpdate();

        for (Map.Entry<LocalDate, Double> entry : computedDailyUsage.entrySet()) {
            double usageKwh = nz(entry.getValue());
            insertPs.setString(1, scopeCode);
            if (building.isEmpty()) insertPs.setNull(2, Types.NVARCHAR); else insertPs.setString(2, building);
            insertPs.setDate(3, java.sql.Date.valueOf(entry.getKey()));
            insertPs.setBigDecimal(4, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", usageKwh)));
            insertPs.setBigDecimal(5, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", appliedFactor)));
            insertPs.setBigDecimal(6, new java.math.BigDecimal(String.format(java.util.Locale.US, "%.6f", usageKwh * appliedFactor)));
            insertPs.setString(7, appliedFactorSource);
            insertPs.setString(8, appliedFactorNote);
            insertPs.setTimestamp(9, calculatedAt);
            insertPs.addBatch();
        }
        insertPs.executeBatch();
    }
    lastCalculatedAt = calculatedAt;

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
        .toolbar{display:grid;grid-template-columns:1.2fr 1.1fr;gap:12px}
        .field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field input,.field select{width:100%;min-width:0}
        .actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
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
        .chart-box{height:250px}
        .hint{font-size:11px;color:#64748b;line-height:1.35}
        .page-footer{margin-top:10px;text-align:center;color:#6d8298;font-size:11px}
        @media (min-width:1280px){
            body{height:100vh;overflow:auto}
            .page-wrap{gap:8px}
            .toolbar{gap:10px}
            .kpi-grid,.meta-grid,.chart-grid{gap:8px}
            .chart-box{height:210px}
            .hint{font-size:10px;line-height:1.3}
            .panel-box{padding:8px}
            .field-grid{gap:6px}
            .actions{gap:6px}
        }
        @media (max-width:1180px){.toolbar,.chart-grid,.kpi-grid,.meta-grid,.field-grid{grid-template-columns:1fr}}
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
            <form method="get" class="field-grid" id="scopeFilterForm">
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
                    <input type="text" value="<%= fmtNumber(appliedFactor, 6) %> kgCO2/kWh" readonly>
                </div>
                <div class="actions" style="grid-column:1 / -1;">
                    <button type="submit" class="btn btn-primary">조회</button>
                </div>
            </form>
            <form method="post" action="<%= request.getContextPath() %>/carbon-emission-action" class="actions" style="margin-top:10px;">
                <input type="hidden" name="building" id="recalcBuildingInput" value="<%= h(building) %>">
                <button type="submit" name="action" value="recalc_scope" class="btn btn-secondary">현재 범위 재집계</button>
                <button type="submit" name="action" value="recalc_all" class="btn btn-secondary">전체 건물 재집계</button>
            </form>
            <div class="hint" style="margin-top:8px;font-weight:700;color:#1f3347;">
                현재 선택 건물: <span id="selectedBuildingLabel"><%= h(building.isEmpty() ? "전체 건물" : building) %></span>
            </div>
            <div class="hint" style="margin-top:8px;">매일 00:10에 건물별 상위 계측기 기준으로 자동 집계되며, 필요하면 여기서 즉시 다시 계산할 수 있습니다.</div>
        </div>

        <div class="panel-box">
            <h2>배출계수 설정</h2>
            <form method="post" class="field-grid">
                <input type="hidden" name="action" value="save_factor">
                <input type="hidden" name="building" value="<%= h(building) %>">
                <div class="field">
                    <label>배출계수 (kgCO2/kWh)</label>
                    <input type="text" name="factor_value" value="<%= fmtNumber(appliedFactor, 6) %>">
                </div>
                <div class="field">
                    <label>출처 / 기준</label>
                    <input type="text" name="factor_source" value="<%= h(appliedFactorSource) %>" placeholder="예: 내부 기준, 공시 기준, ESG 보고 기준">
                </div>
                <div class="actions" style="grid-column:1 / -1;">
                    <button type="submit" class="btn btn-primary">배출계수 저장</button>
                    <span class="hint">초기값은 시스템 기본값입니다. 공식 대외보고 시에는 반드시 보고 기준에 맞는 계수로 변경해 주세요.</span>
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
        out.print(String.format(java.util.Locale.US, "%.6f", nz(value) * appliedFactor / 1000.0d));
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
        out.print(String.format(java.util.Locale.US, "%.6f", nz(value) * appliedFactor / 1000.0d));
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
        out.print(String.format(java.util.Locale.US, "%.6f", nz(value) * appliedFactor / 1000.0d));
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
var recalcBuildingInput = document.getElementById('recalcBuildingInput');
var selectedBuildingLabel = document.getElementById('selectedBuildingLabel');
if (buildingSelect && recalcBuildingInput) {
  var syncRecalcBuilding = function () {
    recalcBuildingInput.value = buildingSelect.value || '';
    if (selectedBuildingLabel) {
      selectedBuildingLabel.textContent = buildingSelect.value || '전체 건물';
    }
  };
  syncRecalcBuilding();
  buildingSelect.addEventListener('change', syncRecalcBuilding);
}
</script>
<footer class="page-footer">EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
