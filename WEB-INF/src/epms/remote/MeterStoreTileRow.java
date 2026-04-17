package epms.remote;

import java.sql.Date;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class MeterStoreTileRow {
    private final int meterId;
    private final String meterName;
    private final String buildingName;
    private final String panelName;
    private final String usageType;
    private final int storeCount;
    private final Integer displayStoreId;
    private final String displayStoreName;
    private final String displayStoreCode;
    private final String displayFloorName;
    private final String displayRoomName;
    private final String displayZoneName;
    private final Date effectiveStartDate;
    private final String storeList;
    private final Double lastMonthKwh;
    private final Double currentKw;
    private final Double currentValidKw;

    public MeterStoreTileRow(int meterId, String meterName, String buildingName, String panelName, String usageType,
            int storeCount, Integer displayStoreId, String displayStoreName, String displayStoreCode,
            String displayFloorName, String displayRoomName, String displayZoneName, Date effectiveStartDate,
            String storeList, Double lastMonthKwh, Double currentKw, Double currentValidKw) {
        this.meterId = meterId;
        this.meterName = meterName;
        this.buildingName = buildingName;
        this.panelName = panelName;
        this.usageType = usageType;
        this.storeCount = storeCount;
        this.displayStoreId = displayStoreId;
        this.displayStoreName = displayStoreName;
        this.displayStoreCode = displayStoreCode;
        this.displayFloorName = displayFloorName;
        this.displayRoomName = displayRoomName;
        this.displayZoneName = displayZoneName;
        this.effectiveStartDate = effectiveStartDate;
        this.storeList = storeList;
        this.lastMonthKwh = lastMonthKwh;
        this.currentKw = currentKw;
        this.currentValidKw = currentValidKw;
    }

    public int getMeterId() { return meterId; }
    public String getMeterName() { return meterName; }
    public String getBuildingName() { return buildingName; }
    public String getPanelName() { return panelName; }
    public String getUsageType() { return usageType; }
    public int getStoreCount() { return storeCount; }
    public Integer getDisplayStoreId() { return displayStoreId; }
    public String getDisplayStoreName() { return displayStoreName; }
    public String getDisplayStoreCode() { return displayStoreCode; }
    public String getDisplayFloorName() { return displayFloorName; }
    public String getDisplayRoomName() { return displayRoomName; }
    public String getDisplayZoneName() { return displayZoneName; }
    public Date getEffectiveStartDate() { return effectiveStartDate; }
    public String getStoreList() { return storeList; }
    public Double getLastMonthKwh() { return lastMonthKwh; }
    public Double getCurrentKw() { return currentKw; }
    public Double getCurrentValidKw() { return currentValidKw; }

    public Double getResolvedCurrentKw() {
        if (currentKw != null && Math.abs(currentKw.doubleValue()) > 0.0001d) return currentKw;
        return currentValidKw;
    }

    public String getLocationText() {
        List<String> parts = new ArrayList<String>();
        if (displayFloorName != null && !displayFloorName.trim().isEmpty()) parts.add(displayFloorName.trim());
        if (displayRoomName != null && !displayRoomName.trim().isEmpty()) parts.add(displayRoomName.trim());
        if (displayZoneName != null && !displayZoneName.trim().isEmpty()) parts.add(displayZoneName.trim());
        return parts.isEmpty() ? "" : " / " + String.join(" / ", parts);
    }

    public String getTileTitle() {
        return displayStoreName == null || displayStoreName.trim().isEmpty() ? meterName : displayStoreName;
    }

    public List<String> getStoreChipLabels() {
        if (storeList == null || storeList.trim().isEmpty()) return Collections.emptyList();
        String[] chips = storeList.split("\\|\\|");
        List<String> results = new ArrayList<String>();
        for (String chip : chips) {
            if (chip != null && !chip.trim().isEmpty()) results.add(chip.trim());
        }
        return results;
    }
}
