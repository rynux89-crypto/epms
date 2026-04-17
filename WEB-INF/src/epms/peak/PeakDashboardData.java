package epms.peak;

import java.sql.Timestamp;
import java.util.Collections;
import java.util.List;

public final class PeakDashboardData {
    private final int activeStoreCount;
    private final int activeMappedMeterCount;
    private final int unmappedActiveStoreCount;
    private final boolean policyTableReady;
    private final int activePolicyCount;
    private final double topInstantPeakKw;
    private final double topDemandPeakKw;
    private final boolean peakSummaryTableReady;
    private final Timestamp peakSummaryUpdatedAt;
    private final List<PeakMeterRow> topPeakMeters;
    private final List<PeakPolicyStatusRow> policyStatusRows;

    public PeakDashboardData(int activeStoreCount, int activeMappedMeterCount, int unmappedActiveStoreCount,
             boolean policyTableReady, int activePolicyCount, double topInstantPeakKw, double topDemandPeakKw,
             boolean peakSummaryTableReady, Timestamp peakSummaryUpdatedAt,
             List<PeakMeterRow> topPeakMeters, List<PeakPolicyStatusRow> policyStatusRows) {
        this.activeStoreCount = activeStoreCount;
        this.activeMappedMeterCount = activeMappedMeterCount;
        this.unmappedActiveStoreCount = unmappedActiveStoreCount;
        this.policyTableReady = policyTableReady;
        this.activePolicyCount = activePolicyCount;
        this.topInstantPeakKw = topInstantPeakKw;
        this.topDemandPeakKw = topDemandPeakKw;
        this.peakSummaryTableReady = peakSummaryTableReady;
        this.peakSummaryUpdatedAt = peakSummaryUpdatedAt;
        this.topPeakMeters = topPeakMeters == null ? Collections.<PeakMeterRow>emptyList() : topPeakMeters;
        this.policyStatusRows = policyStatusRows == null ? Collections.<PeakPolicyStatusRow>emptyList() : policyStatusRows;
    }

    public int getActiveStoreCount() { return activeStoreCount; }
    public int getActiveMappedMeterCount() { return activeMappedMeterCount; }
    public int getUnmappedActiveStoreCount() { return unmappedActiveStoreCount; }
    public boolean isPolicyTableReady() { return policyTableReady; }
    public int getActivePolicyCount() { return activePolicyCount; }
    public double getTopInstantPeakKw() { return topInstantPeakKw; }
    public double getTopDemandPeakKw() { return topDemandPeakKw; }
    public boolean isPeakSummaryTableReady() { return peakSummaryTableReady; }
    public Timestamp getPeakSummaryUpdatedAt() { return peakSummaryUpdatedAt; }
    public List<PeakMeterRow> getTopPeakMeters() { return topPeakMeters; }
    public List<PeakPolicyStatusRow> getPolicyStatusRows() { return policyStatusRows; }

    public long getPeakSummaryLagMinutes() {
        if (peakSummaryUpdatedAt == null) return Long.MAX_VALUE;
        long diffMillis = System.currentTimeMillis() - peakSummaryUpdatedAt.getTime();
        return diffMillis <= 0L ? 0L : diffMillis / 60000L;
    }

    public boolean isPeakSummaryStale() {
        return peakSummaryTableReady && getPeakSummaryLagMinutes() > 30L;
    }

    public int getWarningTargetCount() {
        int count = 0;
        for (PeakPolicyStatusRow row : policyStatusRows) {
            if (row.isWarningTarget() && !row.isControlTarget()) count++;
        }
        return count;
    }

    public int getControlTargetCount() {
        int count = 0;
        for (PeakPolicyStatusRow row : policyStatusRows) {
            if (row.isControlTarget()) count++;
        }
        return count;
    }
}
