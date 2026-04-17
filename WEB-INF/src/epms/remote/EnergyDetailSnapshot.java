package epms.remote;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;

public final class EnergyDetailSnapshot {
    private int storeId;
    private int meterId;
    private String storeCode;
    private String storeName;
    private String floorName;
    private String roomName;
    private String zoneName;
    private String categoryName;
    private String contactName;
    private String contactPhone;
    private Date openedOn;
    private Date closedOn;
    private String meterName;
    private String buildingName;
    private String panelName;
    private String usageType;
    private Date validFrom;
    private Date validTo;
    private Double allocationRatio;
    private String billingScope;
    private Boolean isPrimary;
    private Timestamp currentMeasuredAt;
    private Double currentKw;
    private Timestamp currentValidMeasuredAt;
    private Double currentValidKw;
    private final LinkedHashMap<LocalDate, Double> dailyUsage = new LinkedHashMap<LocalDate, Double>();

    public int getStoreId() { return storeId; }
    public void setStoreId(int storeId) { this.storeId = storeId; }
    public int getMeterId() { return meterId; }
    public void setMeterId(int meterId) { this.meterId = meterId; }
    public String getStoreCode() { return storeCode; }
    public void setStoreCode(String storeCode) { this.storeCode = storeCode; }
    public String getStoreName() { return storeName; }
    public void setStoreName(String storeName) { this.storeName = storeName; }
    public String getFloorName() { return floorName; }
    public void setFloorName(String floorName) { this.floorName = floorName; }
    public String getRoomName() { return roomName; }
    public void setRoomName(String roomName) { this.roomName = roomName; }
    public String getZoneName() { return zoneName; }
    public void setZoneName(String zoneName) { this.zoneName = zoneName; }
    public String getCategoryName() { return categoryName; }
    public void setCategoryName(String categoryName) { this.categoryName = categoryName; }
    public String getContactName() { return contactName; }
    public void setContactName(String contactName) { this.contactName = contactName; }
    public String getContactPhone() { return contactPhone; }
    public void setContactPhone(String contactPhone) { this.contactPhone = contactPhone; }
    public Date getOpenedOn() { return openedOn; }
    public void setOpenedOn(Date openedOn) { this.openedOn = openedOn; }
    public Date getClosedOn() { return closedOn; }
    public void setClosedOn(Date closedOn) { this.closedOn = closedOn; }
    public String getMeterName() { return meterName; }
    public void setMeterName(String meterName) { this.meterName = meterName; }
    public String getBuildingName() { return buildingName; }
    public void setBuildingName(String buildingName) { this.buildingName = buildingName; }
    public String getPanelName() { return panelName; }
    public void setPanelName(String panelName) { this.panelName = panelName; }
    public String getUsageType() { return usageType; }
    public void setUsageType(String usageType) { this.usageType = usageType; }
    public Date getValidFrom() { return validFrom; }
    public void setValidFrom(Date validFrom) { this.validFrom = validFrom; }
    public Date getValidTo() { return validTo; }
    public void setValidTo(Date validTo) { this.validTo = validTo; }
    public Double getAllocationRatio() { return allocationRatio; }
    public void setAllocationRatio(Double allocationRatio) { this.allocationRatio = allocationRatio; }
    public String getBillingScope() { return billingScope; }
    public void setBillingScope(String billingScope) { this.billingScope = billingScope; }
    public Boolean getIsPrimary() { return isPrimary; }
    public void setIsPrimary(Boolean isPrimary) { this.isPrimary = isPrimary; }
    public Timestamp getCurrentMeasuredAt() { return currentMeasuredAt; }
    public void setCurrentMeasuredAt(Timestamp currentMeasuredAt) { this.currentMeasuredAt = currentMeasuredAt; }
    public Double getCurrentKw() { return currentKw; }
    public void setCurrentKw(Double currentKw) { this.currentKw = currentKw; }
    public Timestamp getCurrentValidMeasuredAt() { return currentValidMeasuredAt; }
    public void setCurrentValidMeasuredAt(Timestamp currentValidMeasuredAt) { this.currentValidMeasuredAt = currentValidMeasuredAt; }
    public Double getCurrentValidKw() { return currentValidKw; }
    public void setCurrentValidKw(Double currentValidKw) { this.currentValidKw = currentValidKw; }
    public LinkedHashMap<LocalDate, Double> getDailyUsage() { return dailyUsage; }

    public void putDailyUsage(LocalDate day, Double kwh) {
        dailyUsage.put(day, kwh);
    }

    public void putAllDailyUsage(Map<LocalDate, Double> source) {
        if (source == null) return;
        dailyUsage.putAll(source);
    }
}
