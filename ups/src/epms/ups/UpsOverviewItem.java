package epms.ups;

public final class UpsOverviewItem {
    public String upsId;
    public String upsName;
    public String location;
    public String ipAddress;
    public String modbusPort;
    public String unitId;
    public String statusClass;
    public String statusText;
    public String measuredAtText;
    public String loadText;
    public String batteryText;
    public String outputVoltageText;
    public String outputKwText;
    public String outputKvaText;
    public String frequencyText;
    public String operationModeText;
    public String batteryTempText;
    public String remainingText;
    public int activeAlarmCount;

    public String detailUrl() {
        return "ups_status.jsp?ups_id=" + upsId;
    }

    public String filterText() {
        return (upsName == null ? "" : upsName) + " " + (location == null ? "" : location);
    }
}
