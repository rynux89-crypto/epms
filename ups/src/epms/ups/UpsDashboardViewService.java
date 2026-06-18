package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsFormatSupport;
import epms.util.UpsSimulatorSupport;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class UpsDashboardViewService {
    private static final int COMM_FAIL_OFFLINE_THRESHOLD = 3;

    private UpsDashboardViewService() {
    }



    public static UpsDashboardModel build(String selectedIdParam) {
        UpsDashboardModel model = new UpsDashboardModel();
        try {
            loadBaseData(model);
            selectDevice(model, selectedIdParam);
            summarizeDevices(model);
            deriveSelectedStatus(model);
            derivePowerFlow(model);
            deriveTrends(model);
            deriveAlarmCount(model);
            derivePlacement(model);
            deriveHealth(model);
            sortDeviceRows(model);
        } catch (Exception e) {
            model.err = e.getMessage();
        }
        return model;
    }

    private static void loadBaseData(UpsDashboardModel model) throws Exception {
        model.deviceModels = UpsDeviceLookupService.listActiveDeviceRowsWithProfile();
        model.placementDeviceModels = UpsDeviceLookupService.listDeviceRowsWithProfile();
        model.alarmModels = UpsAlarmEventService.alarmRowList(null, null, null);
        model.eventModels = UpsAlarmEventService.eventRowList(null, null, null);
        model.devices = UpsDeviceRow.toMaps(model.deviceModels);
        model.alarms = UpsAlarmRow.toMaps(model.alarmModels);
        model.events = UpsAlarmRow.toMaps(model.eventModels);
        for (UpsDeviceRow device : model.placementDeviceModels) {
            UpsMeasurementRow latest = latestRowFor(device.upsId);
            String key = String.valueOf(device.upsId);
            model.latestModels.put(key, latest);
            model.latest.put(key, latest.toMap());
        }
    }

    private static void selectDevice(UpsDashboardModel model, String selectedIdParam) {
        model.total = model.deviceModels.size();
        model.selectedId = selectedIdParam;
        if (model.deviceModels.isEmpty()) return;

        if (selectedIdParam != null && selectedIdParam.trim().length() > 0) {
            model.selectedDeviceModel = model.deviceModels.get(0);
            for (UpsDeviceRow device : model.deviceModels) {
                if (selectedIdParam.equals(String.valueOf(device.upsId))) {
                    model.selectedDeviceModel = device;
                    break;
                }
            }
        } else {
            model.selectedDeviceModel = model.deviceModels.get(0);
            for (UpsDeviceRow device : model.deviceModels) {
                UpsMeasurementRow measurement = model.latestModels.get(String.valueOf(device.upsId));
                int active = activeAlarmCountForRows(model.alarmModels, device.upsName);
                int critical = activeCriticalAlarmCountForRows(model.alarmModels, device.upsName);
                if ("normal".equals(statusClass(device, measurement, active, critical))) {
                    model.selectedDeviceModel = device;
                    break;
                }
            }
        }

        model.selectedId = String.valueOf(model.selectedDeviceModel.upsId);
        UpsMeasurementRow selected = model.latestModels.get(model.selectedId);
        model.selectedMeasurementModel = selected == null ? UpsMeasurementRow.empty() : selected;
        model.selectedDevice = model.selectedDeviceModel.toMap();
        model.selectedMeasurement = model.selectedMeasurementModel.toMap();
    }

    private static void summarizeDevices(UpsDashboardModel model) {
        double loadSum = 0;
        double batterySum = 0;
        double voltageSum = 0;
        double freqSum = 0;
        int loadCount = 0;
        int batteryCount = 0;
        int voltageCount = 0;
        int freqCount = 0;

        for (UpsDeviceRow device : model.deviceModels) {
            UpsMeasurementRow measurement = model.latestModels.get(String.valueOf(device.upsId));
            int active = activeAlarmCountForRows(model.alarmModels, device.upsName);
            int critical = activeCriticalAlarmCountForRows(model.alarmModels, device.upsName);
            String cls = statusClass(device, measurement, active, critical);
            if ("normal".equals(cls)) model.normal++;
            else if ("warning".equals(cls) || "critical".equals(cls)) model.warning++;
            else model.offline++;

            if (!isOnline(device, measurement)) continue;

            if (measurement != null && measurement.get("load_percent") != null) {
                loadSum += num(measurement.get("load_percent"), 0);
                loadCount++;
            }
            if (measurement != null && measurement.get("battery_charge_percent") != null) {
                batterySum += num(measurement.get("battery_charge_percent"), 0);
                batteryCount++;
            }
            if (measurement != null && measurement.get("output_power_kw") != null) {
                model.powerSum += num(measurement.get("output_power_kw"), 0);
            }
            if (measurement != null && measurement.get("output_apparent_total_kva") != null) {
                model.apparentPowerSum += num(measurement.get("output_apparent_total_kva"), 0);
            }
            if (measurement != null && measurement.get("output_voltage") != null) {
                voltageSum += num(measurement.get("output_voltage"), 0);
                voltageCount++;
            }
            if (measurement != null && measurement.get("frequency") != null) {
                freqSum += num(measurement.get("frequency"), 0);
                freqCount++;
            }
        }

        model.avgLoad = loadCount == 0 ? 0 : loadSum / loadCount;
        model.avgBattery = batteryCount == 0 ? 0 : batterySum / batteryCount;
        model.avgVoltage = voltageCount == 0 ? 220 : voltageSum / voltageCount;
        model.avgFreq = freqCount == 0 ? 60 : freqSum / freqCount;
    }

    private static void deriveSelectedStatus(UpsDashboardModel model) {
        model.selectedLoad = num(model.selectedMeasurementModel.get("load_percent"), model.avgLoad);
        model.selectedBattery = num(model.selectedMeasurementModel.get("battery_charge_percent"), model.avgBattery);
        model.selectedPower = num(model.selectedMeasurementModel.get("output_power_kw"), model.powerSum);
        model.selectedApparentPower = num(model.selectedMeasurementModel.get("output_apparent_total_kva"), model.apparentPowerSum);
        model.selectedInputVoltage = num(model.selectedMeasurementModel.get("input_voltage"), model.avgVoltage);
        model.selectedVoltage = num(model.selectedMeasurementModel.get("output_voltage"), model.avgVoltage);
        model.selectedFreq = num(model.selectedMeasurementModel.get("frequency"), model.avgFreq);
        model.selectedBatteryCurrent = num(model.selectedMeasurementModel.get("battery_current"), 0);
        model.selectedActiveAlarms = activeAlarmCountForRows(model.alarmModels, model.selectedDeviceModel == null ? null : model.selectedDeviceModel.upsName);
        int selectedCriticalAlarms = activeCriticalAlarmCountForRows(model.alarmModels, model.selectedDeviceModel == null ? null : model.selectedDeviceModel.upsName);
        model.selectedStatusCls = model.deviceModels.isEmpty()
            ? "offline"
            : statusClass(model.selectedDeviceModel, model.selectedMeasurementModel, model.selectedActiveAlarms, selectedCriticalAlarms);
        model.selectedOnline = isOnline(model.selectedDeviceModel, model.selectedMeasurementModel);
        model.selectedOutputAvailable = outputAvailable(model.selectedMeasurementModel);
    }

    private static void derivePowerFlow(UpsDashboardModel model) {
        int selectedModeCode = intNum(model.selectedMeasurementModel.get("ups_operation_mode_code"), 2);
        model.uibClosed = bitOn(model.selectedMeasurementModel.get("switchgear_status_code"), 0, true);
        model.ssibClosed = bitOn(model.selectedMeasurementModel.get("switchgear_status_code"), 1, false);
        model.uobClosed = bitOn(model.selectedMeasurementModel.get("switchgear_status_code"), 3, true);
        model.bf2Closed = bitOn(model.selectedMeasurementModel.get("switchgear_status_code"), 4, false);
        model.mbbClosed = bitOn(model.selectedMeasurementModel.get("switchgear_status_code"), 10, false);
        model.bbClosed = intTruthy(model.selectedMeasurementModel.get("battery_breaker_status_code"), true);

        if (UpsSimulatorSupport.isSimulatorDevice(model.selectedDevice)) {
            String simStatus = UpsSimulatorSupport.readStatus(250);
            if (simStatus != null && simStatus.trim().length() > 0) {
                model.uibClosed = UpsSimulatorSupport.jsonBool(simStatus, "uib", model.uibClosed);
                model.ssibClosed = UpsSimulatorSupport.jsonBool(simStatus, "ssib", model.ssibClosed);
                model.uobClosed = UpsSimulatorSupport.jsonBool(simStatus, "uob", model.uobClosed);
                model.bf2Closed = UpsSimulatorSupport.jsonBool(simStatus, "bf2", model.bf2Closed);
                model.mbbClosed = UpsSimulatorSupport.jsonBool(simStatus, "mbb", model.mbbClosed);
                model.bbClosed = UpsSimulatorSupport.jsonBool(simStatus, "bb", model.bbClosed);
            }
        }

        boolean outputAvailable = model.selectedOutputAvailable;
        model.hasLoad = outputAvailable && (model.selectedPower > 0.1 || model.selectedLoad > 0.1);
        model.staticBypassFlowActive = model.selectedOnline && model.ssibClosed && model.bf2Closed && model.hasLoad;
        model.maintenanceBypassFlowActive = model.selectedOnline && model.mbbClosed && model.hasLoad;
        model.bypassFlowActive = model.staticBypassFlowActive || model.maintenanceBypassFlowActive;
        boolean inputAvailable = model.uibClosed && model.selectedInputVoltage > 0.1;
        model.loadFlowActive = model.selectedOnline && outputAvailable && model.uobClosed && model.hasLoad && !model.bypassFlowActive;
        model.loadSuppliedActive = model.selectedOnline && model.hasLoad && (model.loadFlowActive || model.bypassFlowActive);
        model.batteryDischarging = model.selectedOnline && model.bbClosed && !model.bypassFlowActive
            && (selectedModeCode == 4 || model.selectedBatteryCurrent < -0.1 || (!inputAvailable && model.loadFlowActive));
        model.utilityFlowActive = model.selectedOnline && inputAvailable && !model.batteryDischarging
            && !model.bypassFlowActive;
        model.batteryCharging = model.selectedOnline && model.bbClosed && model.utilityFlowActive && model.selectedBatteryCurrent > 0.1;
        model.upsFlowActive = model.selectedOnline && (model.utilityFlowActive || model.batteryDischarging || model.loadFlowActive);
        model.batteryFlowActive = model.selectedOnline && (model.batteryDischarging || model.batteryCharging);

        model.flowSummary = !model.selectedOnline ? "오프라인"
            : (model.maintenanceBypassFlowActive ? "MBB Close / 유지보수 바이패스"
            : (model.staticBypassFlowActive ? "SSIB+BF2 Close / 정적 바이패스"
            : (!model.uibClosed ? (model.batteryDischarging ? "UIB Open / 배터리 공급" : "UIB Open / 입력 차단")
            : (model.batteryDischarging ? "배터리 방전 공급"
            : (model.batteryCharging ? "상용전원 공급 / 배터리 충전" : "상용전원 공급")))));

        model.flowUtilityDisplay = model.selectedOnline ? fmt(model.selectedInputVoltage, 0) + " V / " + (model.selectedOutputAvailable ? fmt(model.selectedFreq, 1) + " Hz" : "--") : "--";
        model.flowLoadDisplay = model.selectedOnline ? fmt(model.selectedPower, 0) + " kW / " + fmt(model.selectedApparentPower, 0) + " kVA / " + fmt(model.selectedLoad, 0) + "%" : "--";
        model.flowBatteryDisplay = model.selectedOnline ? fmt(model.selectedBattery, 0) + "% / " + fmt(model.selectedBatteryCurrent, 0) + " A" : "--";
    }

    private static void deriveTrends(UpsDashboardModel model) {
        model.trendRangeText = model.selectedOnline ? "최근 1시간" : "오프라인";
        model.trendAxisLabels = trendAxisLabels();
        model.loadTrendDisplay = model.selectedOnline ? fmt(model.selectedLoad, 0) + "%" : "--";
        model.voltageTrendDisplay = model.selectedOnline ? fmt(model.selectedVoltage, 0) + " V" : "--";
        model.batteryTrendDisplay = model.selectedOnline ? fmt(model.selectedBattery, 0) + "%" : "--";
        model.freqTrendDisplay = model.selectedOnline && model.selectedOutputAvailable ? fmt(model.selectedFreq, 1) + " Hz" : "--";
        List<Double> allLoadSeries = recentAggregateSeries("load_percent", model.avgLoad);
        model.kpiLoadMiniPoints = sparkPoints(allLoadSeries, 80.0, 44.0, 4.0);
        model.kpiBatteryMiniBars = batteryGauge(model.avgBattery, 120.0, 44.0);
        model.loadSeriesPoints = model.selectedOnline ? percentSparkPoints(recentLastValueSeries(model.selectedId, "load_percent", model.selectedLoad)) : "";
        model.voltageSeriesPoints = model.selectedOnline ? voltageSparkPoints(recentLastValueSeries(model.selectedId, "output_voltage", model.selectedVoltage)) : "";
        model.batterySeriesPoints = model.selectedOnline ? percentSparkPoints(recentLastValueSeries(model.selectedId, "battery_charge_percent", model.selectedBattery)) : "";
        model.freqSeriesPoints = model.selectedOnline ? frequencySparkPoints(recentLastValueSeries(model.selectedId, "frequency", model.selectedFreq)) : "";
    }

    private static void deriveAlarmCount(UpsDashboardModel model) {
        for (UpsAlarmRow alarm : model.alarmModels) {
            if (!alarmDeviceEnabled(alarm.toMap())) continue;
            if ("ACTIVE".equalsIgnoreCase(String.valueOf(alarm.status))) model.activeAlarms++;
        }
    }

    private static void derivePlacement(UpsDashboardModel model) {
        for (UpsDeviceRow device : model.placementDeviceModels) {
            Object rawLocation = device.location;
            String location = rawLocation == null ? "" : String.valueOf(rawLocation).trim();
            if (location.length() == 0 || "null".equalsIgnoreCase(location)) location = "위치 미지정";

            UpsMeasurementRow measurement = model.latestModels.get(String.valueOf(device.upsId));
            int active = activeAlarmCountForRows(model.alarmModels, device.upsName);
            int critical = activeCriticalAlarmCountForRows(model.alarmModels, device.upsName);
            String status = statusClass(device, measurement, active, critical);
            String rackState = "critical".equals(status) ? "critical" : ("warning".equals(status) ? "warn" : ("offline".equals(status) ? "offline" : "ok"));

            Integer count = model.locationCounts.get(location);
            model.locationCounts.put(location, Integer.valueOf(count == null ? 1 : count.intValue() + 1));
            model.placementUpsTotal++;

            String currentState = model.locationStates.get(location);
            if (currentState == null || placementPriority(rackState) > placementPriority(currentState)) {
                model.locationStates.put(location, rackState);
            }

            StringBuilder names = model.locationNames.get(location);
            if (names == null) {
                names = new StringBuilder();
                model.locationNames.put(location, names);
            }
            if (names.length() > 0) names.append(", ");
            names.append(String.valueOf(device.upsName));
        }

        int locationTotal = model.locationCounts.size();
        if (locationTotal == 0) {
            model.placementSummary = "등록된 UPS 없음";
        } else if (locationTotal == 1) {
            Map.Entry<String, Integer> only = model.locationCounts.entrySet().iterator().next();
            model.placementSummary = only.getKey() + " / UPS " + only.getValue() + "대";
        } else {
            model.placementSummary = "위치 " + locationTotal + "곳 / UPS " + model.placementUpsTotal + "대";
        }
    }

    private static void deriveHealth(UpsDashboardModel model) {
        model.healthScore = model.deviceModels.isEmpty() ? 0 : 100;
        List<String> reasons = new ArrayList<String>();
        if (!model.deviceModels.isEmpty()) {
            if (!model.selectedOnline) {
                model.healthScore -= 45;
                reasons.add("통신 오프라인");
            }
            if (model.selectedActiveAlarms > 0) {
                int penalty = Math.min(30, 10 + (model.selectedActiveAlarms * 5));
                model.healthScore -= penalty;
                reasons.add("활성 알람 " + model.selectedActiveAlarms + "건");
            }
            if (model.selectedBattery < 20) {
                model.healthScore -= 25;
                reasons.add("배터리 위험 " + fmt(model.selectedBattery, 0) + "%");
            } else if (model.selectedBattery < 60) {
                model.healthScore -= 10;
                reasons.add("배터리 낮음 " + fmt(model.selectedBattery, 0) + "%");
            }
            if (model.selectedLoad >= 95) {
                model.healthScore -= 20;
                reasons.add("부하 위험 " + fmt(model.selectedLoad, 0) + "%");
            } else if (model.selectedLoad >= 85) {
                model.healthScore -= 10;
                reasons.add("부하 높음 " + fmt(model.selectedLoad, 0) + "%");
            }
            if (model.healthScore < 0) model.healthScore = 0;
        } else {
            reasons.add("등록된 UPS 없음");
        }

        model.healthColor = model.healthScore >= 90 ? "var(--dash-green)"
            : (model.healthScore >= 70 ? "var(--dash-yellow)" : "var(--dash-red)");
        model.healthText = model.healthScore >= 90 ? "매우 양호"
            : (model.healthScore >= 70 ? "주의" : "확인 필요");
        model.selectedUpsHealth = "normal".equals(model.selectedStatusCls) ? "정상"
            : ("critical".equals(model.selectedStatusCls) ? "장애" : ("warning".equals(model.selectedStatusCls) ? "경고" : "오프라인"));
        model.selectedBatteryHealth = model.selectedOnline
            ? (model.selectedBattery >= 60 ? "정상" : (model.selectedBattery >= 20 ? "주의" : "위험"))
            : "확인 불가";
        model.selectedLoadHealth = model.selectedOnline
            ? (model.selectedLoad < 85 ? "정상" : (model.selectedLoad < 95 ? "주의" : "위험"))
            : "확인 불가";
        model.selectedCommHealth = model.selectedOnline ? "정상" : "오프라인";
        model.selectedAlarmHealth = model.selectedOnline
            ? (model.selectedActiveAlarms == 0 ? "정상" : model.selectedActiveAlarms + "건")
            : "확인 불가";
        model.healthReasonText = reasons.isEmpty() ? "감점 없음" : joinReasons(reasons);
    }

    private static String joinReasons(List<String> reasons) {
        StringBuilder out = new StringBuilder();
        for (String reason : reasons) {
            if (reason == null || reason.length() == 0) continue;
            if (out.length() > 0) out.append(" · ");
            out.append(reason);
        }
        return out.length() == 0 ? "감점 없음" : out.toString();
    }

    private static void sortDeviceRows(final UpsDashboardModel model) {
        model.sortedDeviceModels = new ArrayList<UpsDeviceRow>(model.deviceModels);
        Collections.sort(model.sortedDeviceModels, new Comparator<UpsDeviceRow>() {
            public int compare(UpsDeviceRow a, UpsDeviceRow b) {
                UpsMeasurementRow ma = model.latestModels.get(String.valueOf(a.upsId));
                UpsMeasurementRow mb = model.latestModels.get(String.valueOf(b.upsId));
                int aa = activeAlarmCountForRows(model.alarmModels, a.upsName);
                int ab = activeAlarmCountForRows(model.alarmModels, b.upsName);
                int ac = activeCriticalAlarmCountForRows(model.alarmModels, a.upsName);
                int bc = activeCriticalAlarmCountForRows(model.alarmModels, b.upsName);
                String ca = statusClass(a, ma, aa, ac);
                String cb = statusClass(b, mb, ab, bc);
                int na = "normal".equals(ca) ? 0 : 1;
                int nb = "normal".equals(cb) ? 0 : 1;
                if (na != nb) return na - nb;
                double kvaA = num(ma == null ? null : ma.get("output_apparent_total_kva"), 0);
                double kvaB = num(mb == null ? null : mb.get("output_apparent_total_kva"), 0);
                int byCapacity = Double.compare(kvaB, kvaA);
                if (byCapacity != 0) return byCapacity;
                return String.valueOf(a.upsName).compareToIgnoreCase(String.valueOf(b.upsName));
            }
        });
        model.deviceRows = UpsDeviceRow.toMaps(model.sortedDeviceModels);
    }

    public static String fmt(Object value, int scale) {
        return UpsFormatSupport.fmtDash(value, scale);
    }

    public static String statusText(String cls) {
        if ("normal".equals(cls)) return "정상";
        if ("critical".equals(cls)) return "장애";
        if ("warning".equals(cls)) return "경고";
        return "오프라인";
    }

    public static String operationModeText(Object value, boolean online) {
        if (!online) return "오프라인";
        return UpsFormatSupport.upsModeLabel(value);
    }

    public static String pctStyle(Object value) {
        int v = Math.max(0, Math.min(100, intNum(value, 0)));
        return "width:" + v + "%";
    }

    public static double num(Object value, double fallback) {
        if (value == null) return fallback;
        if (value instanceof Number) return ((Number)value).doubleValue();
        try {
            return Double.parseDouble(String.valueOf(value));
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static int intNum(Object value, int fallback) {
        return (int)Math.round(num(value, fallback));
    }

    public static boolean bitOn(Object value, int bit, boolean fallback) {
        if (value == null) return fallback;
        try {
            int raw = value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value).trim());
            return (raw & (1 << bit)) != 0;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static boolean intTruthy(Object value, boolean fallback) {
        if (value == null) return fallback;
        try {
            int raw = value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value).trim());
            return raw != 0;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static boolean commBad(Map<String, Object> row) {
        if (row == null || row.get("last_comm_status") == null) return false;
        String status = String.valueOf(row.get("last_comm_status")).trim();
        int failCount = intNum(row.get("consecutive_fail_count"), 0);
        if (failCount > 0 && failCount < COMM_FAIL_OFFLINE_THRESHOLD) return false;
        return !(status.length() == 0
            || "OK".equalsIgnoreCase(status)
            || "NORMAL".equalsIgnoreCase(status)
            || "ONLINE".equalsIgnoreCase(status));
    }

    public static boolean commBad(UpsDeviceRow row) {
        if (row == null || row.lastCommStatus == null) return false;
        String status = String.valueOf(row.lastCommStatus).trim();
        int failCount = row.consecutiveFailCount == null ? 0 : row.consecutiveFailCount.intValue();
        if (failCount > 0 && failCount < COMM_FAIL_OFFLINE_THRESHOLD) return false;
        return !(status.length() == 0
            || "OK".equalsIgnoreCase(status)
            || "NORMAL".equalsIgnoreCase(status)
            || "ONLINE".equalsIgnoreCase(status));
    }

    public static String statusClass(Map<String, Object> device, Map<String, Object> measurement, int activeAlarms) {
        return statusClass(device, measurement, activeAlarms, 0);
    }

    public static String statusClass(Map<String, Object> device, Map<String, Object> measurement, int activeAlarms, int criticalAlarms) {
        if (criticalAlarms > 0) return "critical";
        if (commBad(device)) return "offline";
        if (measurement == null || measurement.get("measured_at") == null) return "offline";
        if (activeAlarms > 0) return "warning";
        return "normal";
    }

    public static String statusClass(UpsDeviceRow device, UpsMeasurementRow measurement, int activeAlarms) {
        return statusClass(device, measurement, activeAlarms, 0);
    }

    public static String statusClass(UpsDeviceRow device, UpsMeasurementRow measurement, int activeAlarms, int criticalAlarms) {
        if (criticalAlarms > 0) return "critical";
        if (commBad(device)) return "offline";
        if (measurement == null || !measurement.hasMeasuredAt()) return "offline";
        if (activeAlarms > 0) return "warning";
        return "normal";
    }

    public static boolean isOnline(UpsDeviceRow device, UpsMeasurementRow measurement) {
        return !commBad(device) && measurement != null && measurement.hasMeasuredAt();
    }

    public static boolean outputAvailable(UpsMeasurementRow measurement) {
        if (measurement == null || !measurement.hasMeasuredAt()) return false;
        int outputStatusCode = intNum(measurement.get("output_status_code"), 0);
        return (outputStatusCode & ((1 << 0) | (1 << 1))) == 0
            && num(measurement.get("output_voltage"), 0) > 0.1;
    }

    public static boolean outputAvailable(Map<String, Object> measurement) {
        if (measurement == null || measurement.get("measured_at") == null) return false;
        int outputStatusCode = intNum(measurement.get("output_status_code"), 0);
        return (outputStatusCode & ((1 << 0) | (1 << 1))) == 0
            && num(measurement.get("output_voltage"), 0) > 0.1;
    }

    public static int activeAlarmCountFor(List<Map<String, Object>> alarms, Object upsName) {
        if (upsName == null || alarms == null) return 0;
        int count = 0;
        String name = String.valueOf(upsName);
        for (Map<String, Object> alarm : alarms) {
            if (!alarmDeviceEnabled(alarm)) continue;
            if (name.equals(String.valueOf(alarm.get("ups_name")))
                && "ACTIVE".equalsIgnoreCase(String.valueOf(alarm.get("status")))) {
                count++;
            }
        }
        return count;
    }

    public static int activeCriticalAlarmCountFor(List<Map<String, Object>> alarms, Object upsName) {
        if (upsName == null || alarms == null) return 0;
        int count = 0;
        String name = String.valueOf(upsName);
        for (Map<String, Object> alarm : alarms) {
            if (!alarmDeviceEnabled(alarm)) continue;
            if (name.equals(String.valueOf(alarm.get("ups_name")))
                && "ACTIVE".equalsIgnoreCase(String.valueOf(alarm.get("status")))
                && "CRITICAL".equalsIgnoreCase(String.valueOf(alarm.get("severity")))) {
                count++;
            }
        }
        return count;
    }

    public static int activeAlarmCountForRows(List<UpsAlarmRow> alarms, Object upsName) {
        if (upsName == null || alarms == null) return 0;
        int count = 0;
        String name = String.valueOf(upsName);
        for (UpsAlarmRow alarm : alarms) {
            if (!alarmDeviceEnabled(alarm.toMap())) continue;
            if (name.equals(String.valueOf(alarm.upsName))
                && "ACTIVE".equalsIgnoreCase(String.valueOf(alarm.status))) {
                count++;
            }
        }
        return count;
    }

    public static int activeCriticalAlarmCountForRows(List<UpsAlarmRow> alarms, Object upsName) {
        if (upsName == null || alarms == null) return 0;
        int count = 0;
        String name = String.valueOf(upsName);
        for (UpsAlarmRow alarm : alarms) {
            if (!alarmDeviceEnabled(alarm.toMap())) continue;
            if (name.equals(String.valueOf(alarm.upsName))
                && "ACTIVE".equalsIgnoreCase(String.valueOf(alarm.status))
                && "CRITICAL".equalsIgnoreCase(String.valueOf(alarm.severity))) {
                count++;
            }
        }
        return count;
    }

    private static int placementPriority(String state) {
        if ("critical".equals(state)) return 3;
        if ("warn".equals(state)) return 2;
        if ("offline".equals(state)) return 1;
        return 0;
    }

    private static boolean alarmDeviceEnabled(Map<String, Object> alarm) {
        if (alarm == null || !alarm.containsKey("device_enabled")) return true;
        Object enabled = alarm.get("device_enabled");
        if (enabled == null) return false;
        if (enabled instanceof Boolean) return Boolean.TRUE.equals(enabled);
        if (enabled instanceof Number) return ((Number)enabled).intValue() != 0;
        String value = String.valueOf(enabled).trim();
        return "1".equals(value) || "true".equalsIgnoreCase(value) || "Y".equalsIgnoreCase(value);
    }

    private static UpsMeasurementRow latestRowFor(Object upsId) {
        try {
            if (upsId == null) return UpsMeasurementRow.empty();
            return UpsRealtimeService.latestStatusMeasurementRow(String.valueOf(upsId));
        } catch (Exception ignore) {
            return UpsMeasurementRow.empty();
        }
    }

    private static String metricColumn(String key) {
        if ("load_percent".equals(key)) return "load_percent";
        if ("output_voltage".equals(key)) return "output_voltage";
        if ("battery_charge_percent".equals(key)) return "battery_charge_percent";
        if ("frequency".equals(key)) return "frequency";
        return null;
    }

    private static List<Double> recentSeries(String upsId, String key, double fallback) {
        List<Double> values = new ArrayList<Double>();
        String column = metricColumn(key);
        if (upsId == null || upsId.trim().isEmpty() || column == null) {
            values.add(Double.valueOf(fallback));
            return values;
        }

        Double[] buckets = new Double[60];
        String sql =
            "SELECT DATEDIFF(minute, m.measured_at, SYSDATETIME()) AS minute_ago, AVG(CAST(m." + column + " AS float)) AS measured_value " +
            "FROM dbo.ups_measurement m " +
            "WHERE m.ups_id = ? " +
            "AND m.measured_at >= DATEADD(hour, -1, SYSDATETIME()) " +
            "AND m.measured_at <= SYSDATETIME() " +
            "AND " + column + " IS NOT NULL " +
            "GROUP BY DATEDIFF(minute, m.measured_at, SYSDATETIME())";
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, Integer.parseInt(upsId.trim()));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int minuteAgo = rs.getInt("minute_ago");
                    if (minuteAgo >= 0 && minuteAgo < 60) {
                        buckets[59 - minuteAgo] = Double.valueOf(rs.getDouble("measured_value"));
                    }
                }
            }
        } catch (Exception ignore) {
            return Arrays.asList(Double.valueOf(fallback), Double.valueOf(fallback));
        }

        Double carry = null;
        for (int i = 0; i < buckets.length; i++) {
            if (buckets[i] != null) {
                carry = buckets[i];
                break;
            }
        }
        if (carry == null) carry = Double.valueOf(fallback);
        for (int i = 0; i < buckets.length; i++) {
            if (buckets[i] == null) {
                buckets[i] = carry;
            } else {
                carry = buckets[i];
            }
            values.add(buckets[i]);
        }
        return values;
    }

    private static List<Double> recentLastValueSeries(String upsId, String key, double fallback) {
        List<Double> values = new ArrayList<Double>();
        String column = metricColumn(key);
        if (upsId == null || upsId.trim().isEmpty() || column == null) {
            values.add(Double.valueOf(fallback));
            return values;
        }

        Double[] buckets = new Double[60];
        String sql =
            "WITH ranked AS ( " +
            "SELECT DATEDIFF(minute, m.measured_at, SYSDATETIME()) AS minute_ago, " +
            "CAST(m." + column + " AS float) AS measured_value, " +
            "ROW_NUMBER() OVER (PARTITION BY DATEDIFF(minute, m.measured_at, SYSDATETIME()) ORDER BY m.measured_at DESC) AS rn " +
            "FROM dbo.ups_measurement m " +
            "WHERE m.ups_id = ? " +
            "AND m.measured_at >= DATEADD(hour, -1, SYSDATETIME()) " +
            "AND m.measured_at <= SYSDATETIME() " +
            "AND " + column + " IS NOT NULL " +
            ") SELECT minute_ago, measured_value FROM ranked WHERE rn = 1";
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, Integer.parseInt(upsId.trim()));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int minuteAgo = rs.getInt("minute_ago");
                    if (minuteAgo >= 0 && minuteAgo < 60) {
                        buckets[59 - minuteAgo] = Double.valueOf(rs.getDouble("measured_value"));
                    }
                }
            }
        } catch (Exception ignore) {
            return Arrays.asList(Double.valueOf(fallback), Double.valueOf(fallback));
        }

        Double carry = firstNonNull(buckets, Double.valueOf(fallback));
        for (int i = 0; i < buckets.length; i++) {
            if (buckets[i] == null) {
                buckets[i] = carry;
            } else {
                carry = buckets[i];
            }
            values.add(buckets[i]);
        }
        return values;
    }

    private static List<Double> recentAggregateSeries(String key, double fallback) {
        List<Double> values = new ArrayList<Double>();
        String column = metricColumn(key);
        if (column == null) {
            values.add(Double.valueOf(fallback));
            return values;
        }

        Double[] buckets = new Double[60];
        String sql =
            "SELECT DATEDIFF(minute, measured_at, SYSDATETIME()) AS minute_ago, AVG(CAST(" + column + " AS float)) AS measured_value " +
            "FROM dbo.ups_measurement m " +
            "JOIN dbo.ups_device d ON d.ups_id = m.ups_id " +
            "LEFT JOIN dbo.ups_comm_status cs ON cs.ups_id = d.ups_id " +
            "WHERE d.enabled = 1 " +
            "AND (cs.status IS NULL OR cs.status IN ('OK', 'NORMAL', 'ONLINE') OR ISNULL(cs.consecutive_fail_count, 0) < " + COMM_FAIL_OFFLINE_THRESHOLD + ") " +
            "AND m.measured_at >= DATEADD(hour, -1, SYSDATETIME()) " +
            "AND m.measured_at <= SYSDATETIME() " +
            "AND m." + column + " IS NOT NULL " +
            "GROUP BY DATEDIFF(minute, measured_at, SYSDATETIME())";
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                int minuteAgo = rs.getInt("minute_ago");
                if (minuteAgo >= 0 && minuteAgo < 60) {
                    buckets[59 - minuteAgo] = Double.valueOf(rs.getDouble("measured_value"));
                }
            }
        } catch (Exception ignore) {
            return Arrays.asList(Double.valueOf(fallback), Double.valueOf(fallback));
        }

        Double carry = firstNonNull(buckets, Double.valueOf(fallback));
        for (int i = 0; i < buckets.length; i++) {
            if (buckets[i] == null) {
                buckets[i] = carry;
            } else {
                carry = buckets[i];
            }
            values.add(buckets[i]);
        }
        return values;
    }

    private static Double firstNonNull(Double[] values, Double fallback) {
        if (values != null) {
            for (Double value : values) {
                if (value != null) return value;
            }
        }
        return fallback;
    }

    private static String sparkPoints(List<Double> values) {
        return sparkPoints(values, 260.0, 70.0, 8.0);
    }

    private static String percentSparkPoints(List<Double> values) {
        return fixedScaleSparkPoints(values, 260.0, 70.0, 8.0, 0.0, 100.0);
    }

    private static String frequencySparkPoints(List<Double> values) {
        return fixedScaleSparkPoints(values, 260.0, 70.0, 8.0, 55.0, 65.0);
    }

    private static String voltageSparkPoints(List<Double> values) {
        return fixedScaleSparkPoints(values, 260.0, 70.0, 8.0, 360.0, 400.0);
    }

    private static String trendAxisLabels() {
        int[] minutesAgo = new int[] { 60, 45, 30, 15, 0 };
        double[] xs = new double[] { 0.0, 65.0, 130.0, 195.0, 260.0 };
        String[] anchors = new String[] { "start", "middle", "middle", "middle", "end" };
        SimpleDateFormat format = new SimpleDateFormat("HH:mm", Locale.KOREA);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < minutesAgo.length; i++) {
            Calendar cal = Calendar.getInstance();
            cal.add(Calendar.MINUTE, -minutesAgo[i]);
            Date time = cal.getTime();
            out.append(String.format(Locale.US,
                "<text class=\"spark-axis-label\" x=\"%.1f\" y=\"77\" text-anchor=\"%s\">%s</text>",
                xs[i], anchors[i], format.format(time)));
        }
        return out.toString();
    }

    private static String sparkPoints(List<Double> values, double width, double height, double pad) {
        if (values == null || values.isEmpty()) values = Arrays.asList(Double.valueOf(0));
        if (values.size() == 1) values = Arrays.asList(values.get(0), values.get(0));
        double min = Double.MAX_VALUE;
        double max = -Double.MAX_VALUE;
        for (Double raw : values) {
            double v = raw == null ? 0 : raw.doubleValue();
            if (v < min) min = v;
            if (v > max) max = v;
        }
        if (max - min < 0.0001) {
            max = max + 1;
            min = min - 1;
        }
        StringBuilder points = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            double v = values.get(i) == null ? min : values.get(i).doubleValue();
            double x = values.size() == 1 ? width / 2 : (width * i) / (values.size() - 1);
            double y = pad + (height - (pad * 2)) * (1 - ((v - min) / (max - min)));
            if (i > 0) points.append(' ');
            points.append(String.format(Locale.US, "%.1f,%.1f", x, y));
        }
        return points.toString();
    }

    private static String fixedScaleSparkPoints(List<Double> values, double width, double height, double pad, double min, double max) {
        if (values == null || values.isEmpty()) values = Arrays.asList(Double.valueOf(min));
        if (values.size() == 1) values = Arrays.asList(values.get(0), values.get(0));
        double range = max - min;
        if (range <= 0.0001) range = 1.0;
        StringBuilder points = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            double raw = values.get(i) == null ? min : values.get(i).doubleValue();
            double v = Math.max(min, Math.min(max, raw));
            double x = values.size() == 1 ? width / 2 : (width * i) / (values.size() - 1);
            double y = pad + (height - (pad * 2)) * (1 - ((v - min) / range));
            if (i > 0) points.append(' ');
            points.append(String.format(Locale.US, "%.1f,%.1f", x, y));
        }
        return points.toString();
    }

    private static String miniBars(List<Double> values, double width, double height, int barCount) {
        if (values == null || values.isEmpty()) values = Arrays.asList(Double.valueOf(0));
        int count = Math.max(1, barCount);
        double gap = 5.0;
        double barWidth = Math.max(2.0, (width - (gap * (count + 1))) / count);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < count; i++) {
            int idx = count == 1 ? values.size() - 1 : (int)Math.round((values.size() - 1) * (i / (double)(count - 1)));
            double raw = values.get(Math.max(0, Math.min(values.size() - 1, idx))).doubleValue();
            double pct = Math.max(0.0, Math.min(100.0, raw));
            double barHeight = Math.max(3.0, (height - 8.0) * (pct / 100.0));
            double x = gap + i * (barWidth + gap);
            double y = height - barHeight - 2.0;
            out.append(String.format(Locale.US,
                "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" fill=\"#29e675\"/>",
                x, y, barWidth, barHeight));
        }
        return out.toString();
    }

    private static String batteryGauge(double value, double width, double height) {
        double pct = Math.max(0.0, Math.min(100.0, value));
        String color = pct <= 20.0 ? "#ff5c52" : (pct <= 50.0 ? "#ffbf31" : "#29e675");
        double x = 5.0;
        double y = 4.0;
        double bodyWidth = width - 14.0;
        double bodyHeight = 36.0;
        double fillWidth = Math.max(0.0, (bodyWidth - 4.0) * (pct / 100.0));
        StringBuilder out = new StringBuilder();
        out.append(String.format(Locale.US,
            "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"5\" fill=\"none\" stroke=\"#2f4960\" stroke-width=\"2\"/>",
            x, y, bodyWidth, bodyHeight));
        out.append(String.format(Locale.US,
            "<rect x=\"%.1f\" y=\"%.1f\" width=\"5.0\" height=\"18.0\" rx=\"2\" fill=\"#2f4960\"/>",
            x + bodyWidth + 1.0, y + 9.0));
        out.append(String.format(Locale.US,
            "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"4\" fill=\"%s\"/>",
            x + 2.0, y + 2.0, fillWidth, bodyHeight - 4.0, color));
        return out.toString();
    }
}
