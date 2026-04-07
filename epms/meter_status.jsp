<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*, java.util.*, java.text.*, epms.util.MeterStatusUtil" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%
    //request.setCharacterEncoding("UTF-8");
    // meter_id parameter
    String meterId = request.getParameter("meter_id");
    boolean hasMeterId = (meterId != null && !meterId.trim().isEmpty());
    boolean hasData    = false;   // 실제 측정 데이터 존재 여부
    
    int selectedIndex = -1;

    List<String[]> meterOptions = null;
    String meter_id = null;
    String meterName = null;
    String panelName = "-";
    String buildingName = "-";
    String usageType = "-";
    Timestamp measuredAt = null;
    double voltage_ab = 0, voltage_bc = 0, voltage_ca = 0;
    double voltage_an = 0, voltage_bn = 0, voltage_cn = 0;
    double current_a = 0, current_b = 0, current_c = 0, current_n = 0;
    double average_voltage = 0, phase_voltage_avg = 0, line_voltage_avg = 0, average_current = 0;
    double frequency = 0, power_factor = 0, power_factor_a = 0, power_factor_b = 0, power_factor_c = 0;
    double active_power_total = 0, reactive_power_total = 0, apparent_power_total = 0;
    double energy_consumed_total = 0, energy_generated_total = 0;
    double voltage_unbalance_rate = 0, harmonic_distortion_rate = 0;
    double current_unbalance_rate = 0, current_harmonic_distortion_rate = 0;
    String quality_status = "";
    boolean harmonicDistortionRateMissing = false;
    double thd_voltage_a = 0, thd_voltage_b = 0, thd_voltage_c = 0;
    double thd_current_a = 0, thd_current_b = 0, thd_current_c = 0;
    double voltage_h3_a = 0, voltage_h5_a = 0, voltage_h7_a = 0, voltage_h9_a = 0, voltage_h11_a = 0;
    double voltage_h3_b = 0, voltage_h5_b = 0, voltage_h7_b = 0, voltage_h9_b = 0, voltage_h11_b = 0;
    double voltage_h3_c = 0, voltage_h5_c = 0, voltage_h7_c = 0, voltage_h9_c = 0, voltage_h11_c = 0;
    double current_h3_a = 0, current_h5_a = 0, current_h7_a = 0, current_h9_a = 0, current_h11_a = 0;
    double current_h3_b = 0, current_h5_b = 0, current_h7_b = 0, current_h9_b = 0, current_h11_b = 0;
    double current_h3_c = 0, current_h5_c = 0, current_h7_c = 0, current_h9_c = 0, current_h11_c = 0;
    int sagCount = 0, swellCount = 0, otherVoltageEvents = 0;
    int totalAlarms = 0;
    String recentAlarmTypeLabelsJson = "[]";
    String recentAlarmTypeCountsJson = "[]";
    String recentAlarmTypeSummaryText = "";
    String freshnessText = "-";
    String riskSummaryText = "정상";
    List<String> qualityTrendLabels = null;
    List<Double> qualityTrendUnbalance = null;
    List<Double> qualityTrendThd = null;
    List<Double> currentQualityTrendUnbalance = null;
    List<Double> currentQualityTrendThd = null;
    SimpleDateFormat trendLabelFormat = null;
    long totalStartNs = System.nanoTime();
    long meterOptionQueryMs = 0L;
    long latestMeasurementQueryMs = 0L;
    long riskRuleQueryMs = 0L;
    long qualityTrendQueryMs = 0L;
    long harmonicTrendQueryMs = 0L;
    long latestHarmonicQueryMs = 0L;
    long voltageEventQueryMs = 0L;
    long alarmCountQueryMs = 0L;
    long calculationMs = 0L;
    long totalElapsedMs = 0L;
    String refreshParam = request.getParameter("refresh");
    if (refreshParam == null || refreshParam.trim().isEmpty() || !refreshParam.matches("\\d+")) {
        refreshParam = "off";
    }


    //if (!hasMeterId) { meterId = ""; }
    

    Connection conn = null;

    try {
        conn = openDbConnection();

    // meter option list
    meterOptions = new ArrayList<>(); // [id, name]
    long sectionStartNs = System.nanoTime();
    try (PreparedStatement psOpt = conn.prepareStatement(
            "SELECT meter_id, name " +
            "FROM meters " +
            "WHERE UPPER(COALESCE(name, '')) LIKE '%VCB%' " +
            "   OR UPPER(COALESCE(name, '')) LIKE '%ACB%' " +
            "   OR UPPER(COALESCE(panel_name, '')) LIKE '%VCB%' " +
            "   OR UPPER(COALESCE(panel_name, '')) LIKE '%ACB%' " +
            "ORDER BY meter_id")) {
        try (ResultSet rsOpt = psOpt.executeQuery()) {
            while(rsOpt.next()) {
                meterOptions.add(new String[]{ rsOpt.getString("meter_id"), rsOpt.getString("name") });
            }
        }
    } catch(Exception e) { out.println("옵션 조회 오류: " + e.getMessage()); }
    meterOptionQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;

    // resolved actual meter_id, with legacy index fallback
    meter_id = null;
    meterName = null;

    if (hasMeterId) {
        for (int i = 0; i < meterOptions.size(); i++) {
            if (meterId.equals(meterOptions.get(i)[0])) {
                selectedIndex = i;
                meter_id = meterOptions.get(i)[0];
                meterName = meterOptions.get(i)[1];
                break;
            }
        }
        if (meter_id == null) {
            try {
                selectedIndex = Integer.parseInt(meterId);
                if (selectedIndex >= 0 && selectedIndex < meterOptions.size()) {
                    meter_id = meterOptions.get(selectedIndex)[0];
                    meterName = meterOptions.get(selectedIndex)[1];
                }
            } catch (Exception ignore) {}
        }
    }


    //out.println(meter_id );
    //out.println(selectedIndex);
    //out.println(meterId);

    meterId = meter_id;


    // ====== 공통 메타 정보 ======
    // meterName    = "-";
    panelName = "-";
    buildingName = "-";
    usageType = "-";

    // ====== measurements / vw_meter_measurements 기준 계측값 ======
    measuredAt = null;
    voltage_ab = 0;
    voltage_bc = 0;
    voltage_ca = 0;
    voltage_an = 0;
    voltage_bn = 0;
    voltage_cn = 0;
    current_a = 0;
    current_b = 0;
    current_c = 0;
    current_n = 0;
    average_voltage = 0;
    phase_voltage_avg = 0;
    line_voltage_avg = 0;
    average_current = 0;
    frequency = 0;
    power_factor = 0;
    power_factor_a = 0;
    power_factor_b = 0;
    power_factor_c = 0;
    active_power_total = 0;
    reactive_power_total = 0;
    apparent_power_total = 0;
    energy_consumed_total = 0;
    energy_generated_total = 0;
    voltage_unbalance_rate = 0;
    harmonic_distortion_rate = 0;
    current_unbalance_rate = 0;
    current_harmonic_distortion_rate = 0;
    quality_status = "";
    harmonicDistortionRateMissing = false;

    // ====== harmonic_measurements / vw_harmonic_measurements 기준 ======
    thd_voltage_a = 0;
    thd_voltage_b = 0;
    thd_voltage_c = 0;
    thd_current_a = 0;
    thd_current_b = 0;
    thd_current_c = 0;
    voltage_h3_a = 0;
    voltage_h5_a = 0;
    voltage_h7_a = 0;
    voltage_h9_a = 0;
    voltage_h11_a = 0;
    voltage_h3_b = 0;
    voltage_h5_b = 0;
    voltage_h7_b = 0;
    voltage_h9_b = 0;
    voltage_h11_b = 0;
    voltage_h3_c = 0;
    voltage_h5_c = 0;
    voltage_h7_c = 0;
    voltage_h9_c = 0;
    voltage_h11_c = 0;
    current_h3_a = 0;
    current_h5_a = 0;
    current_h7_a = 0;
    current_h9_a = 0;
    current_h11_a = 0;
    current_h3_b = 0;
    current_h5_b = 0;
    current_h7_b = 0;
    current_h9_b = 0;
    current_h11_b = 0;
    current_h3_c = 0;
    current_h5_c = 0;
    current_h7_c = 0;
    current_h9_c = 0;
    current_h11_c = 0;

    // ====== voltage_events / vw_voltage_event_log 기준 이벤트 집계 ======
    sagCount = 0;
    swellCount = 0;
    otherVoltageEvents = 0;

    // ====== alarm_log / vw_alarm_log 기준 알람 집계 ======
    totalAlarms = 0;
    recentAlarmTypeLabelsJson = "[]";
    recentAlarmTypeCountsJson = "[]";
    recentAlarmTypeSummaryText = "최근 7일 알람 없음";
    freshnessText = "-";
    riskSummaryText = "정상";
    qualityTrendLabels = new ArrayList<>();
    qualityTrendUnbalance = new ArrayList<>();
    qualityTrendThd = new ArrayList<>();
    currentQualityTrendUnbalance = new ArrayList<>();
    currentQualityTrendThd = new ArrayList<>();
    trendLabelFormat = new SimpleDateFormat("HH:mm");

    try {
        if (hasMeterId) {
            // 1) 최신 계측값: vw_meter_measurements
            String sqlMeas =
                "SELECT TOP 1 " +
                "  meter_id, meter_name, panel_name, building_name, usage_type, " +
                "  measured_at, " +
                "  voltage_ab, voltage_bc, voltage_ca, " +
                "  voltage_an, voltage_bn, voltage_cn, " +
                "  current_a, current_b, current_c, current_n, " +
                "  average_voltage, average_current, " +
                "  frequency, " +
                "  power_factor, power_factor_a, power_factor_b, power_factor_c, " +
                "  active_power_total, reactive_power_total, apparent_power_total, " +
                "  energy_consumed_total, energy_generated_total, " +
                "  voltage_unbalance_rate, harmonic_distortion_rate, quality_status, " +
                "  hm.thd_voltage_a, hm.thd_voltage_b, hm.thd_voltage_c, " +
                "  hm.thd_current_a, hm.thd_current_b, hm.thd_current_c, " +
                "  hm.voltage_h3_a, hm.voltage_h5_a, hm.voltage_h7_a, hm.voltage_h9_a, hm.voltage_h11_a, " +
                "  hm.voltage_h3_b, hm.voltage_h5_b, hm.voltage_h7_b, hm.voltage_h9_b, hm.voltage_h11_b, " +
                "  hm.voltage_h3_c, hm.voltage_h5_c, hm.voltage_h7_c, hm.voltage_h9_c, hm.voltage_h11_c, " +
                "  hm.current_h3_a, hm.current_h5_a, hm.current_h7_a, hm.current_h9_a, hm.current_h11_a, " +
                "  hm.current_h3_b, hm.current_h5_b, hm.current_h7_b, hm.current_h9_b, hm.current_h11_b, " +
                "  hm.current_h3_c, hm.current_h5_c, hm.current_h7_c, hm.current_h9_c, hm.current_h11_c, " +
                "  al.alarm_cnt, " +
                "  alt.alarm_type_labels_js, alt.alarm_type_counts_js, alt.alarm_type_summary " +
                "FROM vw_meter_measurements " +
                "OUTER APPLY ( " +
                "    SELECT TOP 1 " +
                "      thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
                "      thd_current_a, thd_current_b, thd_current_c, " +
                "      voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
                "      voltage_h3_b, voltage_h5_b, voltage_h7_b, voltage_h9_b, voltage_h11_b, " +
                "      voltage_h3_c, voltage_h5_c, voltage_h7_c, voltage_h9_c, voltage_h11_c, " +
                "      current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a, " +
                "      current_h3_b, current_h5_b, current_h7_b, current_h9_b, current_h11_b, " +
                "      current_h3_c, current_h5_c, current_h7_c, current_h9_c, current_h11_c " +
                "    FROM vw_harmonic_measurements hm " +
                "    WHERE hm.meter_id = vw_meter_measurements.meter_id " +
                "    ORDER BY hm.measured_at DESC " +
                ") hm " +
                "OUTER APPLY ( " +
                "    SELECT COUNT(*) AS alarm_cnt " +
                "    FROM alarm_log al " +
                "    WHERE al.meter_id = vw_meter_measurements.meter_id " +
                "      AND al.triggered_at >= DATEADD(DAY, -7, GETDATE()) " +
                ") al " +
                "OUTER APPLY ( " +
                "    SELECT " +
                "      STRING_AGG(q.alarm_name_js, ', ') AS alarm_type_labels_js, " +
                "      STRING_AGG(CAST(q.cnt AS varchar(20)), ', ') AS alarm_type_counts_js, " +
                "      STRING_AGG(CONCAT(q.alarm_name, ': ', q.cnt), ', ') AS alarm_type_summary " +
                "    FROM ( " +
                "      SELECT TOP 7 " +
                "        COALESCE(ar2.rule_name, ar2c.rule_name, al2.alarm_type, 'UNKNOWN') AS alarm_name, " +
                "        '''' + REPLACE(COALESCE(ar2.rule_name, ar2c.rule_name, al2.alarm_type, 'UNKNOWN'), '''', '''''') + '''' AS alarm_name_js, " +
                "        COUNT(*) AS cnt " +
                "      FROM alarm_log al2 " +
                "      LEFT JOIN alarm_rule ar2 ON ar2.rule_id = al2.rule_id " +
                "      LEFT JOIN alarm_rule ar2c ON ar2c.rule_code = CASE WHEN al2.rule_code LIKE 'DI_%' THEN SUBSTRING(al2.rule_code, 4, 100) ELSE al2.rule_code END " +
                "      WHERE al2.meter_id = vw_meter_measurements.meter_id " +
                "        AND al2.triggered_at >= DATEADD(DAY, -7, GETDATE()) " +
                "      GROUP BY COALESCE(ar2.rule_name, ar2c.rule_name, al2.alarm_type, 'UNKNOWN') " +
                "      ORDER BY COUNT(*) DESC, COALESCE(ar2.rule_name, ar2c.rule_name, al2.alarm_type, 'UNKNOWN') " +
                "    ) q " +
                ") alt " +
                "WHERE meter_id = ? " +
                "ORDER BY measured_at DESC";

            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlMeas)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        hasData = true;

                        meterName    = rs.getString("meter_name");
                        panelName    = rs.getString("panel_name");
                        buildingName = rs.getString("building_name");
                        usageType    = rs.getString("usage_type");

                        measuredAt   = rs.getTimestamp("measured_at");

                        voltage_ab   = rs.getDouble("voltage_ab");
                        voltage_bc   = rs.getDouble("voltage_bc");
                        voltage_ca   = rs.getDouble("voltage_ca");
                        voltage_an   = rs.getDouble("voltage_an");
                        voltage_bn   = rs.getDouble("voltage_bn");
                        voltage_cn   = rs.getDouble("voltage_cn");

                        current_a    = rs.getDouble("current_a");
                        current_b    = rs.getDouble("current_b");
                        current_c    = rs.getDouble("current_c");
                        current_n    = rs.getDouble("current_n");

                        average_voltage = rs.getDouble("average_voltage");
                        average_current = rs.getDouble("average_current");
                        phase_voltage_avg = (voltage_an + voltage_bn + voltage_cn) / 3.0;
                        line_voltage_avg  = (voltage_ab + voltage_bc + voltage_ca) / 3.0;
                        current_unbalance_rate = MeterStatusUtil.computeCurrentUnbalance(current_a, current_b, current_c);

                        frequency    = rs.getDouble("frequency");
                        power_factor = rs.getDouble("power_factor");
                        power_factor_a = rs.getDouble("power_factor_a");
                        power_factor_b = rs.getDouble("power_factor_b");
                        power_factor_c = rs.getDouble("power_factor_c");

                        active_power_total   = rs.getDouble("active_power_total");
                        reactive_power_total = rs.getDouble("reactive_power_total");
                        apparent_power_total = rs.getDouble("apparent_power_total");

                        energy_consumed_total = rs.getDouble("energy_consumed_total");
                        energy_generated_total = rs.getDouble("energy_generated_total");

                        voltage_unbalance_rate   = rs.getDouble("voltage_unbalance_rate");
                        if (rs.wasNull()) {
                            voltage_unbalance_rate = MeterStatusUtil.computeVoltageUnbalance(voltage_an, voltage_bn, voltage_cn);
                        }
                        harmonic_distortion_rate = rs.getDouble("harmonic_distortion_rate");
                        harmonicDistortionRateMissing = rs.wasNull();
                        thd_voltage_a = rs.getDouble("thd_voltage_a");
                        thd_voltage_b = rs.getDouble("thd_voltage_b");
                        thd_voltage_c = rs.getDouble("thd_voltage_c");
                        thd_current_a = rs.getDouble("thd_current_a");
                        thd_current_b = rs.getDouble("thd_current_b");
                        thd_current_c = rs.getDouble("thd_current_c");
                        voltage_h3_a = rs.getDouble("voltage_h3_a");
                        voltage_h5_a = rs.getDouble("voltage_h5_a");
                        voltage_h7_a = rs.getDouble("voltage_h7_a");
                        voltage_h9_a = rs.getDouble("voltage_h9_a");
                        voltage_h11_a = rs.getDouble("voltage_h11_a");
                        voltage_h3_b = rs.getDouble("voltage_h3_b");
                        voltage_h5_b = rs.getDouble("voltage_h5_b");
                        voltage_h7_b = rs.getDouble("voltage_h7_b");
                        voltage_h9_b = rs.getDouble("voltage_h9_b");
                        voltage_h11_b = rs.getDouble("voltage_h11_b");
                        voltage_h3_c = rs.getDouble("voltage_h3_c");
                        voltage_h5_c = rs.getDouble("voltage_h5_c");
                        voltage_h7_c = rs.getDouble("voltage_h7_c");
                        voltage_h9_c = rs.getDouble("voltage_h9_c");
                        voltage_h11_c = rs.getDouble("voltage_h11_c");
                        current_h3_a = rs.getDouble("current_h3_a");
                        current_h5_a = rs.getDouble("current_h5_a");
                        current_h7_a = rs.getDouble("current_h7_a");
                        current_h9_a = rs.getDouble("current_h9_a");
                        current_h11_a = rs.getDouble("current_h11_a");
                        current_h3_b = rs.getDouble("current_h3_b");
                        current_h5_b = rs.getDouble("current_h5_b");
                        current_h7_b = rs.getDouble("current_h7_b");
                        current_h9_b = rs.getDouble("current_h9_b");
                        current_h11_b = rs.getDouble("current_h11_b");
                        current_h3_c = rs.getDouble("current_h3_c");
                        current_h5_c = rs.getDouble("current_h5_c");
                        current_h7_c = rs.getDouble("current_h7_c");
                        current_h9_c = rs.getDouble("current_h9_c");
                        current_h11_c = rs.getDouble("current_h11_c");
                        if (harmonicDistortionRateMissing) {
                            harmonic_distortion_rate = MeterStatusUtil.computeRepresentativeThd(thd_voltage_a, thd_voltage_b, thd_voltage_c);
                        }
                        current_harmonic_distortion_rate = MeterStatusUtil.computeRepresentativeThd(thd_current_a, thd_current_b, thd_current_c);
                        totalAlarms = rs.getInt("alarm_cnt");
                        String alarmTypeLabelsRaw = rs.getString("alarm_type_labels_js");
                        String alarmTypeCountsRaw = rs.getString("alarm_type_counts_js");
                        String alarmTypeSummaryRaw = rs.getString("alarm_type_summary");
                        if (alarmTypeLabelsRaw != null && !alarmTypeLabelsRaw.trim().isEmpty()) {
                            recentAlarmTypeLabelsJson = "[" + alarmTypeLabelsRaw + "]";
                        }
                        if (alarmTypeCountsRaw != null && !alarmTypeCountsRaw.trim().isEmpty()) {
                            recentAlarmTypeCountsJson = "[" + alarmTypeCountsRaw + "]";
                        }
                        if (alarmTypeSummaryRaw != null && !alarmTypeSummaryRaw.trim().isEmpty()) {
                            recentAlarmTypeSummaryText = alarmTypeSummaryRaw;
                        }
                        quality_status           = rs.getString("quality_status");
                    }
                }
            }
            latestMeasurementQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;

            double vUnbalAlarm = 0.0, vUnbalCritical = 0.0;
            double thdAlarm = 0.0, thdCritical = 0.0;
            double iUnbalAlarm = 0.0, iUnbalCritical = 0.0;
            double freqLow = 0.0, freqHigh = 0.0;

            String sqlRiskRule = 
                "SELECT rule_code, operator, threshold1, threshold2 " +
                "FROM alarm_rule " +
                "WHERE enabled = 1 AND rule_code IN ('V_UNBAL','THD_V','I_UNBAL','FREQUENCY')";
            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlRiskRule);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String ruleCode = rs.getString("rule_code");
                    double t1 = rs.getDouble("threshold1");
                    if (rs.wasNull()) t1 = 0.0;
                    double t2 = rs.getDouble("threshold2");
                    if (rs.wasNull()) t2 = 0.0;
                    if ("V_UNBAL".equals(ruleCode)) {
                        vUnbalAlarm = t1;
                        vUnbalCritical = t2;
                    } else if ("THD_V".equals(ruleCode)) {
                        thdAlarm = t1;
                        thdCritical = t2;
                    } else if ("I_UNBAL".equals(ruleCode)) {
                        iUnbalAlarm = t1;
                        iUnbalCritical = t2;
                    } else if ("FREQUENCY".equals(ruleCode)) {
                        freqLow = t1;
                        freqHigh = t2;
                    }
                }
            }
            riskRuleQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;

            long calcStartNs = System.nanoTime();
            freshnessText = MeterStatusUtil.formatFreshness(measuredAt);
            String riskMetric = "정상";
            String riskLevel = "NORMAL";

            String vUnbalLevel = MeterStatusUtil.riskLevelForHigh(voltage_unbalance_rate, vUnbalAlarm, vUnbalCritical);
            if (MeterStatusUtil.riskRank(vUnbalLevel) > MeterStatusUtil.riskRank(riskLevel)) {
                riskLevel = vUnbalLevel;
                riskMetric = "전압 불평형율 " + String.format("%.2f", voltage_unbalance_rate) + "%";
            }

            String thdLevel = MeterStatusUtil.riskLevelForHigh(harmonic_distortion_rate, thdAlarm, thdCritical);
            if (MeterStatusUtil.riskRank(thdLevel) > MeterStatusUtil.riskRank(riskLevel)) {
                riskLevel = thdLevel;
                riskMetric = "전압 왜형율 " + String.format("%.2f", harmonic_distortion_rate) + "%";
            }

            String iUnbalLevel = MeterStatusUtil.riskLevelForHigh(current_unbalance_rate, iUnbalAlarm, iUnbalCritical);
            if (MeterStatusUtil.riskRank(iUnbalLevel) > MeterStatusUtil.riskRank(riskLevel)) {
                riskLevel = iUnbalLevel;
                riskMetric = "전류 불평형율 " + String.format("%.2f", current_unbalance_rate) + "%";
            }

            String freqLevel = MeterStatusUtil.riskLevelForOutside(frequency, freqLow, freqHigh);
            if (MeterStatusUtil.riskRank(freqLevel) > MeterStatusUtil.riskRank(riskLevel)) {
                riskLevel = freqLevel;
                riskMetric = "주파수 " + String.format("%.3f", frequency) + "Hz";
            }

            if (!"NORMAL".equals(riskLevel)) {
                riskSummaryText = riskLevel + " - " + riskMetric;
            }
            calculationMs += (System.nanoTime() - calcStartNs) / 1000000L;

            String sqlQualityTrend =
                "SELECT TOP 12 vm.measured_at, vm.voltage_unbalance_rate, vm.harmonic_distortion_rate, vm.voltage_an, vm.voltage_bn, vm.voltage_cn, " +
                "       vm.current_a, vm.current_b, vm.current_c " +
                "FROM vw_meter_measurements vm " +
                "WHERE vm.meter_id = ? " +
                "ORDER BY vm.measured_at DESC";

            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlQualityTrend)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Timestamp ts = rs.getTimestamp("measured_at");
                        double trendUnbalance = rs.getDouble("voltage_unbalance_rate");
                        if (rs.wasNull()) {
                            trendUnbalance = MeterStatusUtil.computeVoltageUnbalance(
                                rs.getDouble("voltage_an"),
                                rs.getDouble("voltage_bn"),
                                rs.getDouble("voltage_cn")
                            );
                        }
                        double trendThd = rs.getDouble("harmonic_distortion_rate");
                        if (rs.wasNull()) trendThd = 0.0;
                        double currentTrendUnbalance = MeterStatusUtil.computeCurrentUnbalance(
                            rs.getDouble("current_a"),
                            rs.getDouble("current_b"),
                            rs.getDouble("current_c")
                        );
                        qualityTrendLabels.add(0, ts == null ? "-" : trendLabelFormat.format(ts));
                        qualityTrendUnbalance.add(0, trendUnbalance);
                        qualityTrendThd.add(0, trendThd);
                        currentQualityTrendUnbalance.add(0, currentTrendUnbalance);
                        currentQualityTrendThd.add(0, 0.0);
                    }
                }
            }
            qualityTrendQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;

            String sqlHarmonicTrend =
                "SELECT TOP 12 measured_at, thd_voltage_a, thd_voltage_b, thd_voltage_c, thd_current_a, thd_current_b, thd_current_c " +
                "FROM vw_harmonic_measurements " +
                "WHERE meter_id = ? " +
                "ORDER BY measured_at DESC";
            List<Double> harmonicTrendVoltage = new ArrayList<>();
            List<Double> harmonicTrendCurrent = new ArrayList<>();
            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlHarmonicTrend)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        harmonicTrendVoltage.add(0, MeterStatusUtil.computeRepresentativeThd(
                            rs.getDouble("thd_voltage_a"),
                            rs.getDouble("thd_voltage_b"),
                            rs.getDouble("thd_voltage_c")
                        ));
                        harmonicTrendCurrent.add(0, MeterStatusUtil.computeRepresentativeThd(
                            rs.getDouble("thd_current_a"),
                            rs.getDouble("thd_current_b"),
                            rs.getDouble("thd_current_c")
                        ));
                    }
                }
            }
            harmonicTrendQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;
            int trendFillCount = Math.min(qualityTrendLabels.size(), Math.min(harmonicTrendVoltage.size(), harmonicTrendCurrent.size()));
            for (int i = 0; i < trendFillCount; i++) {
                if (i < qualityTrendThd.size() && qualityTrendThd.get(i) <= 0.0) {
                    qualityTrendThd.set(i, harmonicTrendVoltage.get(i));
                }
                if (i < currentQualityTrendThd.size()) {
                    currentQualityTrendThd.set(i, harmonicTrendCurrent.get(i));
                }
            }

            // 기본 데이터가 없더라도 meter_id 기준의 고조파, 알람, 이벤트 조회는 값이 있을 수 있으므로 계속 진행
            // 필요하면 if (hasData) { ... } 형태로 더 감쌀 수 있음

            // 2) 최신 고조파: vw_harmonic_measurements
            String sqlHarm =
                "SELECT TOP 1 " +
                "  thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
                "  thd_current_a, thd_current_b, thd_current_c, " +
                "  voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
                "  voltage_h3_b, voltage_h5_b, voltage_h7_b, voltage_h9_b, voltage_h11_b, " +
                "  voltage_h3_c, voltage_h5_c, voltage_h7_c, voltage_h9_c, voltage_h11_c, " +
                "  current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a, " +
                "  current_h3_b, current_h5_b, current_h7_b, current_h9_b, current_h11_b, " +
                "  current_h3_c, current_h5_c, current_h7_c, current_h9_c, current_h11_c " +
                "FROM vw_harmonic_measurements " +
                "WHERE meter_id = ? " +
                "ORDER BY measured_at DESC";

            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlHarm)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        thd_voltage_a = rs.getDouble("thd_voltage_a");
                        thd_voltage_b = rs.getDouble("thd_voltage_b");
                        thd_voltage_c = rs.getDouble("thd_voltage_c");
                        thd_current_a = rs.getDouble("thd_current_a");
                        thd_current_b = rs.getDouble("thd_current_b");
                        thd_current_c = rs.getDouble("thd_current_c");

                        voltage_h3_a = rs.getDouble("voltage_h3_a");
                        voltage_h5_a = rs.getDouble("voltage_h5_a");
                        voltage_h7_a = rs.getDouble("voltage_h7_a");
                        voltage_h9_a = rs.getDouble("voltage_h9_a");
                        voltage_h11_a = rs.getDouble("voltage_h11_a");

                        voltage_h3_b = rs.getDouble("voltage_h3_b");
                        voltage_h5_b = rs.getDouble("voltage_h5_b");
                        voltage_h7_b = rs.getDouble("voltage_h7_b");
                        voltage_h9_b = rs.getDouble("voltage_h9_b");
                        voltage_h11_b = rs.getDouble("voltage_h11_b");

                        voltage_h3_c = rs.getDouble("voltage_h3_c");
                        voltage_h5_c = rs.getDouble("voltage_h5_c");
                        voltage_h7_c = rs.getDouble("voltage_h7_c");
                        voltage_h9_c = rs.getDouble("voltage_h9_c");
                        voltage_h11_c = rs.getDouble("voltage_h11_c");
                        current_h3_a = rs.getDouble("current_h3_a");
                        current_h5_a = rs.getDouble("current_h5_a");
                        current_h7_a = rs.getDouble("current_h7_a");
                        current_h9_a = rs.getDouble("current_h9_a");
                        current_h11_a = rs.getDouble("current_h11_a");
                        current_h3_b = rs.getDouble("current_h3_b");
                        current_h5_b = rs.getDouble("current_h5_b");
                        current_h7_b = rs.getDouble("current_h7_b");
                        current_h9_b = rs.getDouble("current_h9_b");
                        current_h11_b = rs.getDouble("current_h11_b");
                        current_h3_c = rs.getDouble("current_h3_c");
                        current_h5_c = rs.getDouble("current_h5_c");
                        current_h7_c = rs.getDouble("current_h7_c");
                        current_h9_c = rs.getDouble("current_h9_c");
                        current_h11_c = rs.getDouble("current_h11_c");

                        if (harmonicDistortionRateMissing) {
                            harmonic_distortion_rate = MeterStatusUtil.computeRepresentativeThd(thd_voltage_a, thd_voltage_b, thd_voltage_c);
                        }
                        current_harmonic_distortion_rate = MeterStatusUtil.computeRepresentativeThd(thd_current_a, thd_current_b, thd_current_c);
                    }
                }
            }
            latestHarmonicQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;

            // 4) 최근 7일 전압 이벤트 집계: vw_voltage_event_log
            String sqlVoltEvent =
                "SELECT event_type, COUNT(*) AS cnt " +
                "FROM vw_voltage_event_log " +
                "WHERE meter_id = ? " +
                "  AND triggered_at >= DATEADD(DAY, -7, GETDATE()) " +
                "GROUP BY event_type";

            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlVoltEvent)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        String etype = rs.getString("event_type");
                        int cnt = rs.getInt("cnt");
                        if ("sag".equalsIgnoreCase(etype)) {
                            sagCount += cnt;
                        } else if ("swell".equalsIgnoreCase(etype)) {
                            swellCount += cnt;
                        } else {
                            otherVoltageEvents += cnt;
                        }
                    }
                }
            }
            voltageEventQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;

            // 5) 최근 7일 알람 건수: vw_alarm_log
            String sqlAlarm =
                "SELECT COUNT(*) AS cnt " +
                "FROM vw_alarm_log " +
                "WHERE meter_id = ? " +
                "  AND triggered_at >= DATEADD(DAY, -7, GETDATE())";

            sectionStartNs = System.nanoTime();
            try (PreparedStatement ps = conn.prepareStatement(sqlAlarm)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        totalAlarms = rs.getInt("cnt");
                    }
                }
            }
            alarmCountQueryMs = (System.nanoTime() - sectionStartNs) / 1000000L;
        }
    } catch (Exception e) {
        e.printStackTrace();
    }

    } finally {
        totalElapsedMs = (System.nanoTime() - totalStartNs) / 1000000L;
        application.log(
            "meter_status timing meterId=" + (meterId == null ? "-" : meterId) +
            ", hasData=" + hasData +
            ", meterOptionsMs=" + meterOptionQueryMs +
            ", latestMeasurementMs=" + latestMeasurementQueryMs +
            ", riskRuleMs=" + riskRuleQueryMs +
            ", qualityTrendMs=" + qualityTrendQueryMs +
            ", harmonicTrendMs=" + harmonicTrendQueryMs +
            ", latestHarmonicMs=" + latestHarmonicQueryMs +
            ", voltageEventMs=" + voltageEventQueryMs +
            ", alarmCountMs=" + alarmCountQueryMs +
            ", calcMs=" + calculationMs +
            ", totalMs=" + totalElapsedMs
        );
        closeQuietly(conn);
    }

    String measuredAtStr = (measuredAt != null ? measuredAt.toString() : "-");
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>계측기 상세 모니터링</title>
    <script src="../js/chart.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
</head>
<body class="page-meter-status">
  <div class="dash">
    <div class="dash-top">
      <div class="title-bar">
          <h2>계측기 상세 모니터링</h2>
          <div class="inline-actions">
              <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'" >EPMS 홈</button>
          </div>
      </div>

      <!-- 조회 조건 -->
      <form method="GET" class="search-form">
        <div class="form-row">
          <div class="card meter-box">
            <label>Meter:</label>
            <select name="meter_id">
              <% for(int i=0; i<meterOptions.size(); i++) { %>
                <option value="<%= meterOptions.get(i)[0] %>" <%= (i == selectedIndex ? "selected" : "") %>>
                  <%= meterOptions.get(i)[1] %>
                </option>
              <% } %>
            </select>
            <button type="submit">조회</button>
          </div>

          <!-- 자동 새로고침 -->
          <div class="card refresh-box">
            <span>자동 새로고침:</span>
            <label><input type="radio" name="refresh" value="5000" <%= "5000".equals(refreshParam) ? "checked" : "" %>> 5초</label>
            <label><input type="radio" name="refresh" value="10000" <%= "10000".equals(refreshParam) ? "checked" : "" %>> 10초</label>
            <label><input type="radio" name="refresh" value="30000" <%= "30000".equals(refreshParam) ? "checked" : "" %>> 30초</label>
            <label><input type="radio" name="refresh" value="60000" <%= "60000".equals(refreshParam) ? "checked" : "" %>> 1분</label>
            <label><input type="radio" name="refresh" value="off" <%= "off".equals(refreshParam) ? "checked" : "" %>> 해제</label>
          </div>
        </div>
      </form>

      <% if (!hasData) { %>
        <div style="margin:12px 0;padding:10px 12px;border:1px solid #ffd6d6;background:#fff3f3;color:#b42318;border-radius:10px;font-weight:700;">데이터가 없습니다</div>
      <% } %>

      <script>
        (function () {
          let refreshTimer = null;

          function startRefresh(ms) {
            if (refreshTimer) clearInterval(refreshTimer);
            refreshTimer = null;

            if (ms && Number.isFinite(ms) && ms > 0) {
              refreshTimer = setInterval(() => location.reload(), ms);
            }
          }

          function selectedFromQuery() {
            const params = new URLSearchParams(location.search);
            const v = params.get("refresh"); // "10000" | "30000" | "60000" | null
            return (v && /^\d+$/.test(v)) ? v : "off";
          }

          function syncUIAndTimer() {
            const selected = selectedFromQuery();

            // 선택값을 즉시 체크 상태에 반영
            document.querySelectorAll('input[name="refresh"]').forEach(r => {
              r.checked = (r.value === selected);
            });

            // 선택값에 맞는 타이머 반영
            startRefresh(selected === "off" ? null : Number(selected));
          }

          function setQueryAndReload(value) {
            const params = new URLSearchParams(location.search);

            if (value === "off") params.delete("refresh");
            else params.set("refresh", value);

            location.search = params.toString();
          }

          window.addEventListener("DOMContentLoaded", () => {
            // 로드 시 체크 복원 + 타이머 시작
            syncUIAndTimer();

            // 이벤트 바인딩 (DOM 로드 후라 100% 동작)
            document.querySelectorAll('input[name="refresh"]').forEach(radio => {
              radio.addEventListener("change", function () {
                setQueryAndReload(this.value);
              });
            });
          });
        })();
      </script>

      <% if (!hasMeterId) { %>
          <div class="alert-box">
              meter_id 파라미터가 없습니다. 계측기를 선택한 뒤 다시 시도해 주세요.
          </div>
      <% } else if (!hasData) { %>
          <div class="alert-box">
              지정한 계측기(<strong><%= meterId %></strong>)에 대한 최근 계측 데이터가 없습니다.
          </div>
      <% } else { %>
      <div class="meta-info" style="margin-top:5px;">
          <span>Meter : <strong><%= meterName %></strong></span>
          <span>Panel : <strong><%= panelName %></strong></span>
          <span>Building : <strong><%= buildingName %></strong></span>
          <span>Usage : <strong><%= usageType %></strong></span>
          <span>마지막 계측시각: <strong><%= measuredAtStr.substring(0,19) %></strong></span>
          <span>신선도: <strong><%= freshnessText %></strong></span>
          <span>기준 대비 위험도: <strong><%= riskSummaryText %></strong></span>
      </div>
      <br>
      <% } %>  

    <%
        // render dashboard cards only when meter_id and data are both available
        if (hasMeterId && hasData) {
    %>
  </div>
  <div class="dash-main">
    <main class="dash-grid">
        <!-- 1. 전압 품질 상태 -->
        <section class="panel_s">
            <h3>전압 품질 상태</h3>
            <div class="chartBox_s" style="height:220px;">
                <canvas id="qualityChart"></canvas>
            </div>
            <div class="status-text">
                전압 불평형율: <strong><%= String.format("%.2f", voltage_unbalance_rate) %> %</strong><br/>
                전압 왜형율(THD): <strong><%= String.format("%.2f", harmonic_distortion_rate) %> %</strong>
            </div>
        </section>

        <!-- 2. 전류 품질 상태 -->
        <section class="panel_s">
            <h3>전류 품질 상태</h3>
            <div class="chartBox_s" style="height:220px;">
                <canvas id="currentQualityChart"></canvas>
            </div>
            <div class="status-text">
                전류 불평형율: <strong><%= String.format("%.2f", current_unbalance_rate) %> %</strong><br/>
                전류 왜형율(THD-I): <strong><%= String.format("%.2f", current_harmonic_distortion_rate) %> %</strong>
            </div>
        </section>

        <!-- 3. 부하 / 전력 상태 -->
        <section class="panel_s">
            <h3>부하 / 전력 상태</h3>
            <div class="chartBox_s">
                <canvas id="powerChart"></canvas>
            </div>
            <div class="status-text">
                유효전력 P: <strong><%= String.format("%.1f", active_power_total) %> kW</strong>, 
                무효전력 Q: <strong><%= String.format("%.1f", reactive_power_total) %> kVar</strong>, 
                피상전력 S: <strong><%= String.format("%.1f", apparent_power_total) %> kVA</strong><br/>
                역률: <strong><%= String.format("%.3f", power_factor) %></strong>,
                주파수 <strong><%= String.format("%.3f", frequency) %> Hz</strong>
            </div>
        </section>

        <!-- 4. 고조파(전압) -->
        <section class="panel_s">
            <h3>고조파 (전압 3·5·7·9·11차)</h3>
            <div class="chartBox_s">
                <canvas id="harmonicChart"></canvas>
            </div>
            <div class="status-text">
                THD-V(A/B/C): 
                <strong><%= String.format("%.1f", thd_voltage_a) %> / 
                        <%= String.format("%.1f", thd_voltage_b) %> / 
                        <%= String.format("%.1f", thd_voltage_c) %> %</strong>
            </div>
        </section>

        <!-- 5. 고조파(전류) -->
        <section class="panel_s">
            <h3>고조파 (전류 3·5·7·9·11차)</h3>
            <div class="chartBox_s">
                <canvas id="currentHarmonicChart"></canvas>
            </div>
            <div class="status-text">
                THD-I(A/B/C):
                <strong><%= String.format("%.1f", thd_current_a) %> /
                        <%= String.format("%.1f", thd_current_b) %> /
                        <%= String.format("%.1f", thd_current_c) %> %</strong>
            </div>
        </section>

        <!-- 6. 최근 7일 알람 유형별 발생 횟수 -->
        <section class="panel_s">
            <h3>최근 7일 알람 유형별 발생 횟수</h3>
            <div class="chartBox_s">
                <canvas id="eventChart"></canvas>
            </div>
            <div class="status-text">
                알람 발생 총 건수: <strong><%= totalAlarms %></strong><br/>
                유형 요약: <strong><%= recentAlarmTypeSummaryText %></strong>
            </div>
        </section>

        <!-- 7. 전압 / 전류 기본 정보 -->
        <section class="panel_s panel-text-only panel-primary-info">
            <h3>전압 / 전류 기본 정보</h3>
            <div class="status-text auto-fit-text">
                <div class="basic-info-grid">
                    <div class="basic-info-item">
                        <span class="basic-info-label">선간 전압 (V)</span>
                        <div class="basic-info-value">AB <%= String.format("%.1f", voltage_ab) %> / BC <%= String.format("%.1f", voltage_bc) %> / CA <%= String.format("%.1f", voltage_ca) %></div>
                    </div>
                    <div class="basic-info-item">
                        <span class="basic-info-label">상간 전압 (V)</span>
                        <div class="basic-info-value">AN <%= String.format("%.1f", voltage_an) %> / BN <%= String.format("%.1f", voltage_bn) %> / CN <%= String.format("%.1f", voltage_cn) %></div>
                    </div>
                    <div class="basic-info-item">
                        <span class="basic-info-label">상 전류 (A)</span>
                        <div class="basic-info-value">A <%= String.format("%.1f", current_a) %> / B <%= String.format("%.1f", current_b) %> / C <%= String.format("%.1f", current_c) %> / N <%= String.format("%.1f", current_n) %></div>
                    </div>
                    <div class="basic-info-item">
                        <span class="basic-info-label">평균 값</span>
                        <div class="basic-info-value">상전압 <%= String.format("%.1f", phase_voltage_avg) %> V / 선간전압 <%= String.format("%.1f", line_voltage_avg) %> V / 전류 <%= String.format("%.1f", average_current) %> A</div>
                    </div>
                </div>
                <div class="basic-info-energy">
                    <span class="basic-info-label">누적 에너지</span>
                    <div class="basic-info-value">사용 <%= String.format("%.1f", energy_consumed_total) %> kWh</div>
                    <div class="basic-info-value">발전 <%= String.format("%.1f", energy_generated_total) %> kWh</div>
                </div>
            </div>
        </section>
    </main>
  </div>
  <%
      } // if (hasMeterId && hasData)
  %>

  <footer class="dash-footer">© EPMS Dashboard · SNUT CNT</footer>


  <%
      // meter_id가 없거나 데이터가 없으면 차트 캔버스 자체가 없으므로 JS도 안전하지만, 불필요한 로드를 줄이기 위해 hasMeterId && hasData일 때만 스크립트 출력
      if (hasMeterId && hasData) {
  %>
  <script>
    // ===== JSP 값 -> JS 상수 =====
    const vUnbalance = <%= voltage_unbalance_rate %>;
    const vThd       = <%= harmonic_distortion_rate %>;
    const qualityTrendLabels = [<%
      for (int i = 0; i < qualityTrendLabels.size(); i++) {
        if (i > 0) out.print(", ");
        out.print("'" + qualityTrendLabels.get(i).replace("\\", "\\\\").replace("'", "\\'") + "'");
      }
    %>];
    const qualityTrendUnbalance = [<%
      for (int i = 0; i < qualityTrendUnbalance.size(); i++) {
        if (i > 0) out.print(", ");
        out.print(String.format(Locale.US, "%.4f", qualityTrendUnbalance.get(i)));
      }
    %>];
    const qualityTrendThd = [<%
      for (int i = 0; i < qualityTrendThd.size(); i++) {
        if (i > 0) out.print(", ");
        out.print(String.format(Locale.US, "%.4f", qualityTrendThd.get(i)));
      }
    %>];
    const currentQualityTrendUnbalance = [<%
      for (int i = 0; i < currentQualityTrendUnbalance.size(); i++) {
        if (i > 0) out.print(", ");
        out.print(String.format(Locale.US, "%.4f", currentQualityTrendUnbalance.get(i)));
      }
    %>];
    const currentQualityTrendThd = [<%
      for (int i = 0; i < currentQualityTrendThd.size(); i++) {
        if (i > 0) out.print(", ");
        out.print(String.format(Locale.US, "%.4f", currentQualityTrendThd.get(i)));
      }
    %>];
    const phaseVoltageAvg = <%= phase_voltage_avg %>;
    const lineVoltageAvg  = <%= line_voltage_avg %>;
    const currentUnbalance = <%= current_unbalance_rate %>;
    const currentThd = <%= current_harmonic_distortion_rate %>;

    const pTotal = <%= active_power_total %>;
    const qTotal = <%= reactive_power_total %>;
    const sTotal = <%= apparent_power_total %>;

    const pf = <%= power_factor %>;
    const freq = <%= frequency %>;

    const thdVa = <%= thd_voltage_a %>;
    const thdVb = <%= thd_voltage_b %>;
    const thdVc = <%= thd_voltage_c %>;

    const h3a = <%= voltage_h3_a %>, h5a = <%= voltage_h5_a %>, h7a = <%= voltage_h7_a %>, h9a = <%= voltage_h9_a %>, h11a = <%= voltage_h11_a %>;
    const h3b = <%= voltage_h3_b %>, h5b = <%= voltage_h5_b %>, h7b = <%= voltage_h7_b %>, h9b = <%= voltage_h9_b %>, h11b = <%= voltage_h11_b %>;
    const h3c = <%= voltage_h3_c %>, h5c = <%= voltage_h5_c %>, h7c = <%= voltage_h7_c %>, h9c = <%= voltage_h9_c %>, h11c = <%= voltage_h11_c %>;
    const thdIa = <%= thd_current_a %>, thdIb = <%= thd_current_b %>, thdIc = <%= thd_current_c %>;
    const i3a = <%= current_h3_a %>, i5a = <%= current_h5_a %>, i7a = <%= current_h7_a %>, i9a = <%= current_h9_a %>, i11a = <%= current_h11_a %>;
    const i3b = <%= current_h3_b %>, i5b = <%= current_h5_b %>, i7b = <%= current_h7_b %>, i9b = <%= current_h9_b %>, i11b = <%= current_h11_b %>;
    const i3c = <%= current_h3_c %>, i5c = <%= current_h5_c %>, i7c = <%= current_h7_c %>, i9c = <%= current_h9_c %>, i11c = <%= current_h11_c %>;

    const sagCnt   = <%= sagCount %>;
    const swellCnt = <%= swellCount %>;
    const otherEvt = <%= otherVoltageEvents %>;
    const alarmCnt = <%= totalAlarms %>;
    const recentAlarmTypeLabels = <%= recentAlarmTypeLabelsJson %>;
    const recentAlarmTypeCounts = <%= recentAlarmTypeCountsJson %>;
    const recentAlarmTypeDisplayLabels = (recentAlarmTypeLabels.length ? recentAlarmTypeLabels : ['알람 없음']).map(label =>
      label.length > 18 ? (label.substring(0, 18) + '...') : label
    );

    // 1. 전압 품질 상태 차트
    const ctxQuality = document.getElementById('qualityChart');
    if (ctxQuality) {
      new Chart(ctxQuality, {
        type: 'bar',
        data: {
          labels: ['전압 불평형율', '전압 왜형율(THD)'],
          datasets: [{
            data: [vUnbalance, vThd]
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '값 (%)' }
            }
          }
        }
      });
    }

    const qualityLabels = qualityTrendLabels.length ? qualityTrendLabels : ['현재'];
    const qualityUnbalanceData = qualityTrendUnbalance.length ? qualityTrendUnbalance : [vUnbalance];
    const qualityThdData = qualityTrendThd.length ? qualityTrendThd : [vThd];
    if (ctxQuality) {
      const existingQualityChart = Chart.getChart(ctxQuality);
      if (existingQualityChart) existingQualityChart.destroy();
      if (qualityTrendLabels.length > 1) {
        new Chart(ctxQuality, {
          type: 'line',
          data: {
            labels: qualityLabels,
            datasets: [{
              label: '전압 불평형율',
              data: qualityUnbalanceData,
              borderColor: '#2c66d6',
              backgroundColor: 'rgba(44,102,214,0.15)',
              tension: 0.25,
              pointRadius: 2,
              pointHoverRadius: 4,
              fill: false
            }, {
              label: '전압 왜형율(THD)',
              data: qualityThdData,
              borderColor: '#4aa3df',
              backgroundColor: 'rgba(74,163,223,0.15)',
              tension: 0.25,
              pointRadius: 2,
              pointHoverRadius: 4,
              fill: false
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: true, position: 'top' } },
            scales: {
              x: {
                grid: { display: false },
                title: { display: true, text: '최근 측정 시각' }
              },
              y: {
                beginAtZero: true,
                grace: '10%',
                title: { display: true, text: '값 (%)' }
              }
            }
          }
        });
      } else {
        new Chart(ctxQuality, {
          type: 'bar',
          data: {
            labels: ['전압 불평형율', '전압 왜형율(THD)'],
            datasets: [{
              data: [vUnbalance, vThd],
              backgroundColor: ['rgba(44,102,214,0.8)', 'rgba(74,163,223,0.8)']
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: {
              x: { grid: { display: false } },
              y: {
                beginAtZero: true,
                grace: '10%',
                title: { display: true, text: '값 (%)' }
              }
            }
          }
        });
      }
    }

    const currentQualityLabels = qualityTrendLabels.length ? qualityTrendLabels : ['현재'];
    const currentQualityUnbalanceData = currentQualityTrendUnbalance.length ? currentQualityTrendUnbalance : [currentUnbalance];
    const currentQualityThdData = currentQualityTrendThd.length ? currentQualityTrendThd : [currentThd];
    const ctxCurrentQuality = document.getElementById('currentQualityChart');
    if (ctxCurrentQuality) {
      if (currentQualityTrendUnbalance.length > 1 || currentQualityTrendThd.length > 1) {
        new Chart(ctxCurrentQuality, {
          type: 'line',
          data: {
            labels: currentQualityLabels,
            datasets: [{
              label: '전류 불평형율',
              data: currentQualityUnbalanceData,
              borderColor: '#d96c1f',
              backgroundColor: 'rgba(217,108,31,0.15)',
              tension: 0.25,
              pointRadius: 2,
              pointHoverRadius: 4,
              fill: false
            }, {
              label: '전류 왜형율(THD-I)',
              data: currentQualityThdData,
              borderColor: '#e3a21a',
              backgroundColor: 'rgba(227,162,26,0.15)',
              tension: 0.25,
              pointRadius: 2,
              pointHoverRadius: 4,
              fill: false
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: true, position: 'top' } },
            scales: {
              x: {
                grid: { display: false },
                title: { display: true, text: '최근 측정 시각' }
              },
              y: {
                beginAtZero: true,
                grace: '10%',
                title: { display: true, text: '값 (%)' }
              }
            }
          }
        });
      } else {
        new Chart(ctxCurrentQuality, {
          type: 'bar',
          data: {
            labels: ['전류 불평형율', '전류 왜형율(THD-I)'],
            datasets: [{
              data: [currentUnbalance, currentThd],
              backgroundColor: ['rgba(217,108,31,0.8)', 'rgba(227,162,26,0.8)']
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: {
              x: { grid: { display: false } },
              y: {
                beginAtZero: true,
                grace: '10%',
                title: { display: true, text: '값 (%)' }
              }
            }
          }
        });
      }
    }

    // 2. 부하 / 전력 상태 차트 (P, Q, S)
    const ctxPower = document.getElementById('powerChart');
    if (ctxPower) {
      new Chart(ctxPower, {
        type: 'bar',
        data: {
          labels: ['P(kW)', 'Q(kVar)', 'S(kVA)'],
          datasets: [{
            data: [pTotal, qTotal, sTotal]
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                afterBody: function() {
                  return '역률: ' + pf.toFixed(3) + '\\n' +
                    '주파수: ' + freq.toFixed(3) + ' Hz';
                }
              }
            }
          },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '전력' }
            }
          }
        }
      });
    }

    // 3. 고조파 차트 (3, 5, 7, 9, 11차 상별)
    const ctxHarm = document.getElementById('harmonicChart');
    if (ctxHarm) {
      new Chart(ctxHarm, {
        type: 'bar',
        data: {
          labels: ['3차', '5차', '7차', '9차', '11차'],
          datasets: [
            { label: 'A상', data: [h3a, h5a, h7a, h9a, h11a] },
            { label: 'B상', data: [h3b, h5b, h7b, h9b, h11b] },
            { label: 'C상', data: [h3c, h5c, h7c, h9c, h11c] }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { position: 'bottom' } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '전압 고조파 (단위: %)' }
            }
          }
        }
      });
    }

    // 4. 전류 고조파 차트
    const ctxCurrentHarm = document.getElementById('currentHarmonicChart');
    if (ctxCurrentHarm) {
      new Chart(ctxCurrentHarm, {
        type: 'bar',
        data: {
          labels: ['3차', '5차', '7차', '9차', '11차'],
          datasets: [
            { label: 'A상', data: [i3a, i5a, i7a, i9a, i11a] },
            { label: 'B상', data: [i3b, i5b, i7b, i9b, i11b] },
            { label: 'C상', data: [i3c, i5c, i7c, i9c, i11c] }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { position: 'bottom' } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '전류 고조파 (단위: %)' }
            }
          }
        }
      });
    }

    // 5. 알람 차트
    const ctxEvent = document.getElementById('eventChart');
    if (ctxEvent) {
      new Chart(ctxEvent, {
        type: 'bar',
        data: {
          labels: recentAlarmTypeDisplayLabels,
          datasets: [{
            data: recentAlarmTypeCounts.length ? recentAlarmTypeCounts : [0]
          }]
        },
        options: {
          indexAxis: 'y',
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                title: function(items) {
                  if (!items || !items.length) return '';
                  const idx = items[0].dataIndex;
                  return (recentAlarmTypeLabels.length ? recentAlarmTypeLabels : ['알람 없음'])[idx];
                }
              }
            }
          },
          scales: {
            x: {
              beginAtZero: true,
              grid: { display: false },
                title: { display: true, text: '발생 건수' }
            },
            y: {
              grid: { display: false },
              ticks: {
                autoSkip: false
              },
              afterFit: function(scale) {
                scale.width = 140;
              }
            }
          }
        }
      });
    }
  </script>
  <%
      } // end if (hasMeterId && hasData)
  %>
  </div>
</body>
</html>





