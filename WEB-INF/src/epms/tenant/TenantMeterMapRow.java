package epms.tenant;

import java.sql.Date;

public final class TenantMeterMapRow {
    private final long mapId;
    private final int storeId;
    private final int meterId;
    private final String billingScope;
    private final double allocationRatio;
    private final boolean primary;
    private final Date validFrom;
    private final Date validTo;
    private final String notes;
    private final String storeCode;
    private final String storeName;
    private final String meterName;
    private final String buildingName;
    private final String panelName;

    public TenantMeterMapRow(long mapId, int storeId, int meterId, String billingScope, double allocationRatio,
            boolean primary, Date validFrom, Date validTo, String notes, String storeCode, String storeName,
            String meterName, String buildingName, String panelName) {
        this.mapId = mapId;
        this.storeId = storeId;
        this.meterId = meterId;
        this.billingScope = billingScope;
        this.allocationRatio = allocationRatio;
        this.primary = primary;
        this.validFrom = validFrom;
        this.validTo = validTo;
        this.notes = notes;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.meterName = meterName;
        this.buildingName = buildingName;
        this.panelName = panelName;
    }

    public long getMapId() { return mapId; }
    public int getStoreId() { return storeId; }
    public int getMeterId() { return meterId; }
    public String getBillingScope() { return billingScope; }
    public double getAllocationRatio() { return allocationRatio; }
    public boolean isPrimary() { return primary; }
    public Date getValidFrom() { return validFrom; }
    public Date getValidTo() { return validTo; }
    public String getNotes() { return notes; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public String getMeterName() { return meterName; }
    public String getBuildingName() { return buildingName; }
    public String getPanelName() { return panelName; }
}
