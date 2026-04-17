package epms.peak;

import java.sql.Timestamp;

public final class PeakMeterRow {
    private final int meterId;
    private final String meterName;
    private final String buildingName;
    private final String panelName;
    private final String storeCode;
    private final String storeName;
    private final double instantPeakKw;
    private final Timestamp instantPeakMeasuredAt;
    private final double demandPeakKw;
    private final Timestamp demandPeakMeasuredAt;

    public PeakMeterRow(int meterId, String meterName, String buildingName, String panelName,
            String storeCode, String storeName, double instantPeakKw, Timestamp instantPeakMeasuredAt,
            double demandPeakKw, Timestamp demandPeakMeasuredAt) {
        this.meterId = meterId;
        this.meterName = meterName;
        this.buildingName = buildingName;
        this.panelName = panelName;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.instantPeakKw = instantPeakKw;
        this.instantPeakMeasuredAt = instantPeakMeasuredAt;
        this.demandPeakKw = demandPeakKw;
        this.demandPeakMeasuredAt = demandPeakMeasuredAt;
    }

    public int getMeterId() { return meterId; }
    public String getMeterName() { return meterName; }
    public String getBuildingName() { return buildingName; }
    public String getPanelName() { return panelName; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public double getInstantPeakKw() { return instantPeakKw; }
    public Timestamp getInstantPeakMeasuredAt() { return instantPeakMeasuredAt; }
    public double getDemandPeakKw() { return demandPeakKw; }
    public Timestamp getDemandPeakMeasuredAt() { return demandPeakMeasuredAt; }
}
