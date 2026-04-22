package epms.peak;

import java.sql.Connection;
import java.sql.Date;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public final class PeakPolicyService {
    private final PeakPolicyRepository repository = new PeakPolicyRepository();

    public PeakPolicyPageData loadPageData(Long editId) throws Exception {
        try (Connection conn = repository.openConnection()) {
            List<PeakStoreOption> storeOptions = repository.listStoreOptions(conn);
            List<PeakPolicyRow> rows = repository.listPolicies(conn);
            PeakPolicyRow selectedRow = editId == null ? null : repository.findPolicyById(conn, editId);
            return new PeakPolicyPageData(storeOptions, rows, selectedRow);
        }
    }

    public Long addPolicy(String policyName, Double peakLimitKw, Double warningThresholdPct, Double controlThresholdPct,
            Integer priorityLevel, boolean controlEnabled, Date effectiveFrom, Date effectiveTo, String notes,
            List<Integer> storeIds) throws Exception {
        List<Integer> normalizedStoreIds = normalizeStoreIds(storeIds);
        validate(policyName, peakLimitKw, warningThresholdPct, controlThresholdPct, priorityLevel, effectiveFrom, effectiveTo, normalizedStoreIds);
        try (Connection conn = repository.openConnection()) {
            return repository.addPolicy(conn, new PeakPolicyRow(
                    null,
                    policyName,
                    peakLimitKw,
                    warningThresholdPct,
                    controlThresholdPct,
                    priorityLevel,
                    controlEnabled,
                    effectiveFrom,
                    effectiveTo,
                    notes,
                    null,
                    Integer.valueOf(normalizedStoreIds.size()),
                    normalizedStoreIds));
        }
    }

    public void updatePolicy(Long policyId, String policyName, Double peakLimitKw, Double warningThresholdPct,
            Double controlThresholdPct, Integer priorityLevel, boolean controlEnabled, Date effectiveFrom,
            Date effectiveTo, String notes, List<Integer> storeIds) throws Exception {
        if (policyId == null || policyId.longValue() <= 0L) {
            throw new IllegalArgumentException("Valid policy ID is required.");
        }
        List<Integer> normalizedStoreIds = normalizeStoreIds(storeIds);
        validate(policyName, peakLimitKw, warningThresholdPct, controlThresholdPct, priorityLevel, effectiveFrom, effectiveTo, normalizedStoreIds);
        try (Connection conn = repository.openConnection()) {
            repository.updatePolicy(conn, new PeakPolicyRow(
                    policyId,
                    policyName,
                    peakLimitKw,
                    warningThresholdPct,
                    controlThresholdPct,
                    priorityLevel,
                    controlEnabled,
                    effectiveFrom,
                    effectiveTo,
                    notes,
                    null,
                    Integer.valueOf(normalizedStoreIds.size()),
                    normalizedStoreIds));
        }
    }

    public void deletePolicy(Long policyId) throws Exception {
        if (policyId == null || policyId.longValue() <= 0L) {
            throw new IllegalArgumentException("Valid policy ID is required.");
        }
        try (Connection conn = repository.openConnection()) {
            repository.deletePolicy(conn, policyId);
        }
    }

    private static void validate(String policyName, Double peakLimitKw, Double warningThresholdPct, Double controlThresholdPct,
            Integer priorityLevel, Date effectiveFrom, Date effectiveTo, List<Integer> storeIds) {
        if (policyName == null || policyName.trim().isEmpty()) {
            throw new IllegalArgumentException("Policy name is required.");
        }
        if (peakLimitKw == null || peakLimitKw.doubleValue() <= 0.0d) {
            throw new IllegalArgumentException("Peak limit (kW) must be greater than 0.");
        }
        if (warningThresholdPct == null || warningThresholdPct.doubleValue() <= 0.0d || warningThresholdPct.doubleValue() > 100.0d) {
            throw new IllegalArgumentException("Warning threshold (%) must be between 0 and 100.");
        }
        if (controlThresholdPct == null || controlThresholdPct.doubleValue() <= 0.0d || controlThresholdPct.doubleValue() > 100.0d) {
            throw new IllegalArgumentException("Control threshold (%) must be between 0 and 100.");
        }
        if (warningThresholdPct.doubleValue() > controlThresholdPct.doubleValue()) {
            throw new IllegalArgumentException("Warning threshold cannot be greater than control threshold.");
        }
        if (priorityLevel == null || priorityLevel.intValue() < 1 || priorityLevel.intValue() > 9) {
            throw new IllegalArgumentException("Priority level must be between 1 and 9.");
        }
        if (effectiveFrom == null) {
            throw new IllegalArgumentException("Effective start date is required.");
        }
        if (effectiveTo != null && effectiveTo.before(effectiveFrom)) {
            throw new IllegalArgumentException("Effective end date cannot be before start date.");
        }
        if (storeIds == null || storeIds.isEmpty()) {
            throw new IllegalArgumentException("Select at least one store for this policy.");
        }
    }

    private static List<Integer> normalizeStoreIds(List<Integer> storeIds) {
        Set<Integer> unique = new LinkedHashSet<Integer>();
        if (storeIds != null) {
            for (Integer storeId : storeIds) {
                if (storeId != null && storeId.intValue() > 0) {
                    unique.add(storeId);
                }
            }
        }
        return new ArrayList<Integer>(unique);
    }
}
