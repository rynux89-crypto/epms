package epms.peak;

import java.sql.Date;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class PeakPolicyRow {
    private final Long policyId;
    private final String policyName;
    private final Double peakLimitKw;
    private final Double warningThresholdPct;
    private final Double controlThresholdPct;
    private final Integer priorityLevel;
    private final boolean controlEnabled;
    private final Date effectiveFrom;
    private final Date effectiveTo;
    private final String notes;
    private final String assignedStoreSummary;
    private final Integer assignedStoreCount;
    private final List<Integer> assignedStoreIds;

    public PeakPolicyRow(Long policyId, String policyName, Double peakLimitKw,
            Double warningThresholdPct, Double controlThresholdPct, Integer priorityLevel, boolean controlEnabled,
            Date effectiveFrom, Date effectiveTo, String notes, String assignedStoreSummary,
            Integer assignedStoreCount, List<Integer> assignedStoreIds) {
        this.policyId = policyId;
        this.policyName = policyName;
        this.peakLimitKw = peakLimitKw;
        this.warningThresholdPct = warningThresholdPct;
        this.controlThresholdPct = controlThresholdPct;
        this.priorityLevel = priorityLevel;
        this.controlEnabled = controlEnabled;
        this.effectiveFrom = effectiveFrom;
        this.effectiveTo = effectiveTo;
        this.notes = notes;
        this.assignedStoreSummary = assignedStoreSummary;
        this.assignedStoreCount = assignedStoreCount;
        this.assignedStoreIds = assignedStoreIds == null
                ? Collections.<Integer>emptyList()
                : Collections.unmodifiableList(new ArrayList<Integer>(assignedStoreIds));
    }

    public Long getPolicyId() { return policyId; }
    public String getPolicyName() { return policyName; }
    public Double getPeakLimitKw() { return peakLimitKw; }
    public Double getWarningThresholdPct() { return warningThresholdPct; }
    public Double getControlThresholdPct() { return controlThresholdPct; }
    public Integer getPriorityLevel() { return priorityLevel; }
    public boolean isControlEnabled() { return controlEnabled; }
    public Date getEffectiveFrom() { return effectiveFrom; }
    public Date getEffectiveTo() { return effectiveTo; }
    public String getNotes() { return notes; }
    public String getAssignedStoreSummary() { return assignedStoreSummary; }
    public Integer getAssignedStoreCount() { return assignedStoreCount; }
    public List<Integer> getAssignedStoreIds() { return assignedStoreIds; }
}
