package epms.peak;

import java.sql.Timestamp;

public final class PeakPolicyStatusRow {
    private final Long policyId;
    private final Integer storeId;
    private final String storeCode;
    private final String storeName;
    private final String floorName;
    private final String categoryName;
    private final Double peakLimitKw;
    private final Double warningThresholdPct;
    private final Double controlThresholdPct;
    private final Double demandPeakKw;
    private final Timestamp latestExceededAt;
    private final int consecutiveExceededCount;
    private final int exceededCountLastHour;
    private final int exceededCountToday;

    public PeakPolicyStatusRow(Long policyId, Integer storeId, String storeCode, String storeName, String floorName,
            String categoryName, Double peakLimitKw, Double warningThresholdPct, Double controlThresholdPct,
            Double demandPeakKw, Timestamp latestExceededAt, int consecutiveExceededCount,
            int exceededCountLastHour, int exceededCountToday) {
        this.policyId = policyId;
        this.storeId = storeId;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.floorName = floorName;
        this.categoryName = categoryName;
        this.peakLimitKw = peakLimitKw;
        this.warningThresholdPct = warningThresholdPct;
        this.controlThresholdPct = controlThresholdPct;
        this.demandPeakKw = demandPeakKw;
        this.latestExceededAt = latestExceededAt;
        this.consecutiveExceededCount = consecutiveExceededCount;
        this.exceededCountLastHour = exceededCountLastHour;
        this.exceededCountToday = exceededCountToday;
    }

    public Long getPolicyId() { return policyId; }
    public Integer getStoreId() { return storeId; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public String getFloorName() { return floorName; }
    public String getCategoryName() { return categoryName; }
    public Double getPeakLimitKw() { return peakLimitKw; }
    public Double getWarningThresholdPct() { return warningThresholdPct; }
    public Double getControlThresholdPct() { return controlThresholdPct; }
    public Double getDemandPeakKw() { return demandPeakKw; }
    public Timestamp getLatestExceededAt() { return latestExceededAt; }
    public int getConsecutiveExceededCount() { return consecutiveExceededCount; }
    public int getExceededCountLastHour() { return exceededCountLastHour; }
    public int getExceededCountToday() { return exceededCountToday; }

    public double getUsagePct() {
        if (peakLimitKw == null || peakLimitKw.doubleValue() <= 0.0d || demandPeakKw == null) return 0.0d;
        return (demandPeakKw.doubleValue() / peakLimitKw.doubleValue()) * 100.0d;
    }

    public boolean isWarningTarget() {
        double usagePct = getUsagePct();
        return warningThresholdPct != null && usagePct >= warningThresholdPct.doubleValue();
    }

    public boolean isControlTarget() {
        double usagePct = getUsagePct();
        return controlThresholdPct != null && usagePct >= controlThresholdPct.doubleValue();
    }

    public String getStatusLabel() {
        if (isControlTarget()) return "제어";
        if (isWarningTarget()) return "경고";
        return "정상";
    }
}
