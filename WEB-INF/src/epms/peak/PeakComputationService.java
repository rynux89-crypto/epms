package epms.peak;

import java.sql.Connection;

public final class PeakComputationService {
    private final PeakPolicyRepository repository = new PeakPolicyRepository();

    public PeakDashboardData loadDashboard() throws Exception {
        try (Connection conn = repository.openConnection()) {
            boolean peakSummaryTableReady = repository.peak15MinSummaryTableExists(conn);
            boolean peakSummaryProcedureReady = repository.peak15MinSummaryProcedureExists(conn);
            java.util.List<PeakMeterRow> rows = repository.listTopPeakMeters(conn, 30, 12);
            boolean policyTableReady = repository.peakPolicyTableExists(conn);
            int activePolicyCount = 0;
            java.util.List<PeakPolicyStatusRow> policyRows = java.util.Collections.emptyList();
            if (policyTableReady) {
                activePolicyCount = repository.countActivePolicies(conn);
                policyRows = repository.listPolicyStatusRows(conn, 30, 10);
            }
            double topInstantPeakKw = rows.isEmpty() ? 0.0d : rows.get(0).getInstantPeakKw();
            double topDemandPeakKw = rows.isEmpty() ? 0.0d : rows.get(0).getDemandPeakKw();
            return new PeakDashboardData(
                    repository.countActiveStores(conn),
                    repository.countActiveMappedMeters(conn),
                    repository.countUnmappedActiveStores(conn),
                    policyTableReady,
                    activePolicyCount,
                    topInstantPeakKw,
                    topDemandPeakKw,
                    peakSummaryTableReady,
                    peakSummaryProcedureReady,
                    repository.findPeak15MinSummaryUpdatedAt(conn),
                    repository.findLatestMeasurementAt(conn),
                    rows,
                    policyRows);
        }
    }

    public void refreshPeakSummary(int daysBack) throws Exception {
        try (Connection conn = repository.openConnection()) {
            repository.refreshPeak15MinSummary(conn, daysBack <= 0 ? 35 : daysBack);
        }
    }
}
