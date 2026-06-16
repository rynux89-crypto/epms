package epms.ups;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class UpsDashboardModel {
    public String err;
    public List<UpsDeviceRow> deviceModels = new ArrayList<UpsDeviceRow>();
    public List<UpsDeviceRow> placementDeviceModels = new ArrayList<UpsDeviceRow>();
    public List<UpsAlarmRow> alarmModels = new ArrayList<UpsAlarmRow>();
    public List<UpsAlarmRow> eventModels = new ArrayList<UpsAlarmRow>();
    public Map<String, UpsMeasurementRow> latestModels = new LinkedHashMap<String, UpsMeasurementRow>();
    public UpsDeviceRow selectedDeviceModel;
    public UpsMeasurementRow selectedMeasurementModel = UpsMeasurementRow.empty();
    public List<UpsDeviceRow> sortedDeviceModels = new ArrayList<UpsDeviceRow>();

    public List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
    public List<Map<String, Object>> alarms = new ArrayList<Map<String, Object>>();
    public List<Map<String, Object>> events = new ArrayList<Map<String, Object>>();
    public Map<String, Map<String, Object>> latest = new LinkedHashMap<String, Map<String, Object>>();
    public Map<String, Object> selectedDevice = new HashMap<String, Object>();
    public Map<String, Object> selectedMeasurement = new HashMap<String, Object>();
    public List<Map<String, Object>> deviceRows = new ArrayList<Map<String, Object>>();
    public Map<String, Integer> locationCounts = new LinkedHashMap<String, Integer>();
    public Map<String, String> locationStates = new LinkedHashMap<String, String>();
    public Map<String, StringBuilder> locationNames = new LinkedHashMap<String, StringBuilder>();

    public int total;
    public int normal;
    public int warning;
    public int offline;
    public int activeAlarms;
    public int selectedActiveAlarms;
    public int healthScore;
    public int placementUpsTotal;

    public double avgLoad;
    public double avgBattery;
    public double avgVoltage = 220.0;
    public double avgFreq = 60.0;
    public double powerSum;
    public double selectedLoad;
    public double selectedBattery;
    public double selectedPower;
    public double selectedInputVoltage;
    public double selectedVoltage;
    public double selectedFreq;
    public double selectedBatteryCurrent;

    public String selectedId;
    public String selectedStatusCls = "offline";
    public boolean selectedOnline;
    public boolean uibClosed;
    public boolean ssibClosed;
    public boolean uobClosed;
    public boolean bf2Closed;
    public boolean mbbClosed;
    public boolean bbClosed;
    public boolean hasLoad;
    public boolean staticBypassFlowActive;
    public boolean maintenanceBypassFlowActive;
    public boolean bypassFlowActive;
    public boolean loadFlowActive;
    public boolean loadSuppliedActive;
    public boolean batteryDischarging;
    public boolean utilityFlowActive;
    public boolean batteryCharging;
    public boolean upsFlowActive;
    public boolean batteryFlowActive;

    public String flowSummary = "오프라인";
    public String flowUtilityDisplay = "--";
    public String flowLoadDisplay = "--";
    public String flowBatteryDisplay = "--";
    public String trendRangeText = "오프라인";
    public String loadTrendDisplay = "--";
    public String voltageTrendDisplay = "--";
    public String batteryTrendDisplay = "--";
    public String freqTrendDisplay = "--";
    public String loadSeriesPoints = "";
    public String voltageSeriesPoints = "";
    public String batterySeriesPoints = "";
    public String freqSeriesPoints = "";
    public String kpiLoadMiniPoints = "";
    public String kpiBatteryMiniBars = "";
    public String placementSummary = "등록된 UPS 없음";
    public String healthColor = "var(--dash-red)";
    public String healthText = "확인 필요";
    public String healthReasonText = "";
    public String selectedUpsHealth = "오프라인";
    public String selectedBatteryHealth = "확인 불가";
    public String selectedLoadHealth = "확인 불가";
    public String selectedCommHealth = "오프라인";
    public String selectedAlarmHealth = "확인 불가";
}
