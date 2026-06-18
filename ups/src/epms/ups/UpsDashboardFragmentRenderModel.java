package epms.ups;

import epms.util.UpsFormatSupport;
import epms.util.UpsEventFormatSupport;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class UpsDashboardFragmentRenderModel {
    public final boolean hasDevices;
    public final String selectedUpsId;
    public final String selectedUpsName;
    public final String selectedStatusText;
    public final String selectedProfileName;
    public final String selectedCapacityText;
    public final String selectedOperationModeText;
    public final String selectedInputVoltageText;
    public final String selectedOutputVoltageText;
    public final String selectedFrequencyText;
    public final String selectedLocationText;
    public final String selectedLinkQuery;
    public final String avgLoadText;
    public final String avgBatteryText;
    public final String powerSumText;
    public final String apparentPowerSumText;
    public final String kpiLoadMiniPoints;
    public final String kpiBatteryMiniBars;
    public final List<DeviceOption> deviceOptions = new ArrayList<DeviceOption>();
    public final List<AlarmItem> alarmItems = new ArrayList<AlarmItem>();
    public final List<EventItem> eventItems = new ArrayList<EventItem>();
    public final List<DeviceItem> deviceItems = new ArrayList<DeviceItem>();
    public final List<PlacementItem> placementItems = new ArrayList<PlacementItem>();

    public UpsDashboardFragmentRenderModel(UpsDashboardModel dashboard) {
        UpsDashboardModel d = dashboard == null ? new UpsDashboardModel() : dashboard;
        this.hasDevices = !d.devices.isEmpty();
        this.selectedUpsId = stringValue(d.selectedDevice.get("ups_id"));
        this.selectedUpsName = hasDevices ? stringValue(d.selectedDevice.get("ups_name")) : "등록된 UPS 없음";
        this.selectedStatusText = hasDevices
            ? UpsDashboardRenderSupport.statusText(UpsDashboardViewService.statusClass(
                d.selectedDevice,
                d.selectedMeasurement,
                UpsDashboardViewService.activeAlarmCountFor(d.alarms, d.selectedDevice.get("ups_name")),
                UpsDashboardViewService.activeCriticalAlarmCountFor(d.alarms, d.selectedDevice.get("ups_name"))))
            : "미등록";
        this.selectedProfileName = valueOrDefault(d.selectedDevice.get("profile_name"), "Galaxy VS");
        this.selectedCapacityText = fmt(d.selectedMeasurement.get("output_apparent_total_kva"), 0) + " kVA";
        this.selectedOperationModeText = UpsDashboardRenderSupport.operationModeText(d.selectedMeasurement.get("ups_operation_mode_code"), d.selectedOnline);
        this.selectedInputVoltageText = d.selectedOnline ? fmt(Double.valueOf(d.selectedInputVoltage), 0) + " V" : "--";
        this.selectedOutputVoltageText = d.selectedOnline ? fmt(Double.valueOf(d.selectedVoltage), 0) + " V" : "--";
        this.selectedFrequencyText = d.selectedOnline && d.selectedOutputAvailable ? fmt(d.selectedMeasurement.get("frequency"), 1) + " Hz" : "--";
        this.selectedLocationText = valueOrDefault(d.selectedDevice.get("location"), "전산실 A");
        this.selectedLinkQuery = hasDevices ? "?ups_id=" + selectedUpsId : "";
        this.avgLoadText = fmt(Double.valueOf(d.avgLoad), 0);
        this.avgBatteryText = fmt(Double.valueOf(d.avgBattery), 0);
        this.powerSumText = fmt(Double.valueOf(d.powerSum), 0);
        this.apparentPowerSumText = fmt(Double.valueOf(d.apparentPowerSum), 0);
        this.kpiLoadMiniPoints = UpsDashboardRenderSupport.kpiLoadMiniPoints(d.avgLoad);
        this.kpiBatteryMiniBars = UpsDashboardRenderSupport.kpiBatteryMiniBars(d.avgBattery);

        for (Map<String, Object> row : d.devices) {
            String id = stringValue(row.get("ups_id"));
            deviceOptions.add(new DeviceOption(id, stringValue(row.get("ups_name")), id.equals(d.selectedId)));
        }
        int alarmsAdded = 0;
        for (Map<String, Object> row : d.alarms) {
            if (!"ACTIVE".equalsIgnoreCase(stringValue(row.get("status")))) continue;
            if (!alarmDeviceEnabled(row)) continue;
            if (alarmsAdded >= 4) break;
            alarmItems.add(new AlarmItem(
                "CRITICAL".equalsIgnoreCase(stringValue(row.get("severity"))),
                stringValue(row.get("ups_name")),
                stringValue(row.get("alarm_message")),
                displayDateTime(row.get("occurred_at"))));
            alarmsAdded++;
        }
        int eventsAdded = 0;
        for (Map<String, Object> row : d.events) {
            if (!"EVENT".equalsIgnoreCase(stringValue(row.get("status")))) continue;
            if (eventsAdded >= 4) break;
            eventItems.add(new EventItem(
                stringValue(row.get("ups_name")),
                UpsEventFormatSupport.displayEventMessage(row.get("alarm_message")),
                displayDateTime(row.get("occurred_at"))));
            eventsAdded++;
        }
        for (Map<String, Object> row : d.deviceRows) {
            Map<String, Object> measurement = d.latest.get(stringValue(row.get("ups_id")));
            int active = UpsDashboardViewService.activeAlarmCountFor(d.alarms, row.get("ups_name"));
            int critical = UpsDashboardViewService.activeCriticalAlarmCountFor(d.alarms, row.get("ups_name"));
            String statusClass = UpsDashboardViewService.statusClass(row, measurement, active, critical);
            Object load = measurement == null ? null : measurement.get("load_percent");
            Object battery = measurement == null ? null : measurement.get("battery_charge_percent");
            deviceItems.add(new DeviceItem(
                stringValue(row.get("ups_id")),
                stringValue(row.get("ups_name")),
                stringValue(row.get("profile_name")),
                fmt(load, 0),
                UpsDashboardRenderSupport.pctStyle(load),
                fmt(battery, 0),
                UpsDashboardRenderSupport.pctStyle(battery),
                statusClass,
                UpsDashboardRenderSupport.statusText(statusClass),
                stringValue(row.get("location"))));
        }
        for (Map.Entry<String, Integer> entry : d.locationCounts.entrySet()) {
            String loc = entry.getKey();
            String state = d.locationStates.get(loc);
            if (state == null || state.length() == 0) state = "ok";
            String names = d.locationNames.get(loc) == null ? "" : String.valueOf(d.locationNames.get(loc));
            String targetUpsId = d.locationTargetIds.get(loc) == null ? "" : String.valueOf(d.locationTargetIds.get(loc));
            placementItems.add(new PlacementItem(loc, entry.getValue().intValue(), state, names, targetUpsId));
        }
    }

    private static String fmt(Object value, int scale) {
        return UpsFormatSupport.fmtDash(value, scale);
    }

    private static String displayDateTime(Object value) {
        if (value == null) return "--";
        if (value instanceof Timestamp) {
            return new SimpleDateFormat("MM/dd HH:mm:ss").format((Timestamp)value);
        }
        String text = UpsFormatSupport.displaySlashDateTime(value);
        return text.length() >= 14 ? text.substring(text.length() - 14) : text;
    }

    private static String valueOrDefault(Object value, String fallback) {
        String s = stringValue(value);
        return s.length() == 0 || "null".equalsIgnoreCase(s) ? fallback : s;
    }

    private static String stringValue(Object value) {
        return value == null ? "" : String.valueOf(value);
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

    public static final class DeviceOption {
        public final String id;
        public final String name;
        public final boolean active;

        DeviceOption(String id, String name, boolean active) {
            this.id = id;
            this.name = name;
            this.active = active;
        }
    }

    public static final class AlarmItem {
        public final boolean critical;
        public final String upsName;
        public final String message;
        public final String occurredAtText;

        AlarmItem(boolean critical, String upsName, String message, String occurredAtText) {
            this.critical = critical;
            this.upsName = upsName;
            this.message = message;
            this.occurredAtText = occurredAtText;
        }
    }

    public static final class EventItem {
        public final String upsName;
        public final String message;
        public final String occurredAtText;

        EventItem(String upsName, String message, String occurredAtText) {
            this.upsName = upsName;
            this.message = message;
            this.occurredAtText = occurredAtText;
        }
    }

    public static final class DeviceItem {
        public final String id;
        public final String name;
        public final String profileName;
        public final String loadText;
        public final String loadStyle;
        public final String batteryText;
        public final String batteryStyle;
        public final String statusClass;
        public final String statusText;
        public final String location;

        DeviceItem(String id, String name, String profileName, String loadText, String loadStyle,
                String batteryText, String batteryStyle, String statusClass,
                String statusText, String location) {
            this.id = id;
            this.name = name;
            this.profileName = profileName;
            this.loadText = loadText;
            this.loadStyle = loadStyle;
            this.batteryText = batteryText;
            this.batteryStyle = batteryStyle;
            this.statusClass = statusClass;
            this.statusText = statusText;
            this.location = location;
        }
    }

    public static final class PlacementItem {
        public final String location;
        public final int count;
        public final String stateClass;
        public final String names;
        public final String targetUpsId;

        PlacementItem(String location, int count, String stateClass, String names, String targetUpsId) {
            this.location = location;
            this.count = count;
            this.stateClass = stateClass;
            this.names = names;
            this.targetUpsId = targetUpsId;
        }
    }
}
