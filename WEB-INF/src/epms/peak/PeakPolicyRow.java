package epms.peak;

import java.sql.Date;

public final class PeakPolicyRow {
    private final Long policyId;
    private final Integer storeId;
    private final String storeCode;
    private final String storeName;
    private final Double peakLimitKw;
    private final Double warningThresholdPct;
    private final Double controlThresholdPct;
    private final Integer priorityLevel;
    private final boolean controlEnabled;
    private final Date effectiveFrom;
    private final Date effectiveTo;
    private final String notes;

    public PeakPolicyRow(Long policyId, Integer storeId, String storeCode, String storeName, Double peakLimitKw,
            Double warningThresholdPct, Double controlThresholdPct, Integer priorityLevel, boolean controlEnabled,
            Date effectiveFrom, Date effectiveTo, String notes) {
        this.policyId = policyId;
        this.storeId = storeId;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.peakLimitKw = peakLimitKw;
        this.warningThresholdPct = warningThresholdPct;
        this.controlThresholdPct = controlThresholdPct;
        this.priorityLevel = priorityLevel;
        this.controlEnabled = controlEnabled;
        this.effectiveFrom = effectiveFrom;
        this.effectiveTo = effectiveTo;
        this.notes = notes;
    }

    public Long getPolicyId() { return policyId; }
    public Integer getStoreId() { return storeId; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public Double getPeakLimitKw() { return peakLimitKw; }
    public Double getWarningThresholdPct() { return warningThresholdPct; }
    public Double getControlThresholdPct() { return controlThresholdPct; }
    public Integer getPriorityLevel() { return priorityLevel; }
    public boolean isControlEnabled() { return controlEnabled; }
    public Date getEffectiveFrom() { return effectiveFrom; }
    public Date getEffectiveTo() { return effectiveTo; }
    public String getNotes() { return notes; }
}
