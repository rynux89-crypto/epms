package epms.peak;

import java.sql.Connection;
import java.sql.Date;
import java.util.List;

public final class PeakPolicyService {
    private final PeakPolicyRepository repository = new PeakPolicyRepository();

    public PeakPolicyPageData loadPageData(Long editId) throws Exception {
        try (Connection conn = repository.openConnection()) {
            List<PeakStoreOption> storeOptions = repository.listStoreOptions(conn);
            List<PeakPolicyRow> rows = repository.listPolicies(conn);
            PeakPolicyRow selectedRow = null;
            if (editId != null) {
                for (PeakPolicyRow row : rows) {
                    if (editId.equals(row.getPolicyId())) {
                        selectedRow = row;
                        break;
                    }
                }
            }
            return new PeakPolicyPageData(storeOptions, rows, selectedRow);
        }
    }

    public Long addPolicy(Integer storeId, Double peakLimitKw, Double warningThresholdPct, Double controlThresholdPct,
            Integer priorityLevel, boolean controlEnabled, Date effectiveFrom, Date effectiveTo, String notes) throws Exception {
        validate(storeId, peakLimitKw, warningThresholdPct, controlThresholdPct, priorityLevel, effectiveFrom, effectiveTo);
        try (Connection conn = repository.openConnection()) {
            return repository.addPolicy(conn, new PeakPolicyRow(null, storeId, null, null, peakLimitKw,
                    warningThresholdPct, controlThresholdPct, priorityLevel, controlEnabled, effectiveFrom, effectiveTo, notes));
        }
    }

    public void updatePolicy(Long policyId, Integer storeId, Double peakLimitKw, Double warningThresholdPct,
            Double controlThresholdPct, Integer priorityLevel, boolean controlEnabled, Date effectiveFrom,
            Date effectiveTo, String notes) throws Exception {
        if (policyId == null || policyId.longValue() <= 0L) throw new IllegalArgumentException("유효한 정책 ID가 필요합니다.");
        validate(storeId, peakLimitKw, warningThresholdPct, controlThresholdPct, priorityLevel, effectiveFrom, effectiveTo);
        try (Connection conn = repository.openConnection()) {
            repository.updatePolicy(conn, new PeakPolicyRow(policyId, storeId, null, null, peakLimitKw,
                    warningThresholdPct, controlThresholdPct, priorityLevel, controlEnabled, effectiveFrom, effectiveTo, notes));
        }
    }

    public void deletePolicy(Long policyId) throws Exception {
        if (policyId == null || policyId.longValue() <= 0L) throw new IllegalArgumentException("유효한 정책 ID가 필요합니다.");
        try (Connection conn = repository.openConnection()) {
            repository.deletePolicy(conn, policyId);
        }
    }

    private static void validate(Integer storeId, Double peakLimitKw, Double warningThresholdPct, Double controlThresholdPct,
            Integer priorityLevel, Date effectiveFrom, Date effectiveTo) {
        if (storeId == null || storeId.intValue() <= 0) throw new IllegalArgumentException("매장을 선택해 주세요.");
        if (peakLimitKw == null || peakLimitKw.doubleValue() <= 0.0d) throw new IllegalArgumentException("피크 한도(kW)는 0보다 커야 합니다.");
        if (warningThresholdPct == null || warningThresholdPct.doubleValue() <= 0.0d || warningThresholdPct.doubleValue() > 100.0d) {
            throw new IllegalArgumentException("주의 기준(%)은 0~100 범위여야 합니다.");
        }
        if (controlThresholdPct == null || controlThresholdPct.doubleValue() <= 0.0d || controlThresholdPct.doubleValue() > 100.0d) {
            throw new IllegalArgumentException("제어 기준(%)은 0~100 범위여야 합니다.");
        }
        if (warningThresholdPct.doubleValue() > controlThresholdPct.doubleValue()) {
            throw new IllegalArgumentException("주의 기준은 제어 기준보다 클 수 없습니다.");
        }
        if (priorityLevel == null || priorityLevel.intValue() < 1 || priorityLevel.intValue() > 9) {
            throw new IllegalArgumentException("우선순위는 1~9 범위여야 합니다.");
        }
        if (effectiveFrom == null) throw new IllegalArgumentException("적용 시작일이 필요합니다.");
        if (effectiveTo != null && effectiveTo.before(effectiveFrom)) throw new IllegalArgumentException("적용 종료일은 시작일보다 빠를 수 없습니다.");
    }
}
