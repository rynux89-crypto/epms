package epms.validation;

import java.sql.Date;
import java.util.Set;

public final class ValidationService {
    private static final Set<String> STORE_STATUSES = Set.of("ACTIVE", "CLOSED");
    private static final Set<String> BILLING_SCOPES = Set.of("DIRECT", "SHARED", "SUB");
    private static final Set<String> SNAPSHOT_TYPES = Set.of("OPENING", "CLOSING");
    private static final Set<String> STATEMENT_STATUSES = Set.of("DRAFT", "ISSUED", "CONFIRMED");

    public void requireStoreName(String storeName) {
        if (storeName == null || storeName.trim().isEmpty()) {
            throw new IllegalArgumentException("매장명은 필수입니다.");
        }
    }

    public String normalizeStoreStatus(String status) {
        String actual = status == null || status.trim().isEmpty() ? "ACTIVE" : status.trim().toUpperCase();
        if (!STORE_STATUSES.contains(actual)) {
            throw new IllegalArgumentException("유효하지 않은 매장 상태입니다.");
        }
        return actual;
    }

    public void validateStoreDateRange(Date openedOn, Date closedOn) {
        if (openedOn != null && closedOn != null && closedOn.before(openedOn)) {
            throw new IllegalArgumentException("종료일은 오픈일보다 빠를 수 없습니다.");
        }
    }

    public void requireStoreId(Integer storeId) {
        if (storeId == null) {
            throw new IllegalArgumentException("유효한 매장 ID가 필요합니다.");
        }
    }

    public void requireMapId(Long mapId) {
        if (mapId == null) {
            throw new IllegalArgumentException("유효한 연결 ID가 필요합니다.");
        }
    }

    public void validateMapRequired(Integer storeId, Integer meterId, Date validFrom) {
        if (storeId == null || meterId == null || validFrom == null) {
            throw new IllegalArgumentException("매장, 계측기, 적용 시작일은 필수입니다.");
        }
    }

    public String normalizeBillingScope(String scope) {
        String actual = scope == null || scope.trim().isEmpty() ? "DIRECT" : scope.trim().toUpperCase();
        if (!BILLING_SCOPES.contains(actual)) {
            throw new IllegalArgumentException("유효하지 않은 정산 범위입니다.");
        }
        return actual;
    }

    public double normalizeAllocationRatio(Double ratio) {
        double actual = ratio == null ? 1.0d : ratio.doubleValue();
        if (actual <= 0.0d || actual > 1.0d) {
            throw new IllegalArgumentException("배분 비율은 0보다 크고 1 이하여야 합니다.");
        }
        return actual;
    }

    public void validateMapDateRange(Date validFrom, Date validTo) {
        if (validFrom != null && validTo != null && validTo.before(validFrom)) {
            throw new IllegalArgumentException("적용 종료일은 시작일보다 빠를 수 없습니다.");
        }
    }

    public void requireRateFields(String rateCode, String rateName, Date effectiveFrom) {
        if (rateCode == null || rateCode.trim().isEmpty() || rateName == null || rateName.trim().isEmpty() || effectiveFrom == null) {
            throw new IllegalArgumentException("요금제 코드, 요금제명, 적용 시작일은 필수입니다.");
        }
    }

    public void requireContractFields(Integer storeId, Integer rateId, Date startDate) {
        if (storeId == null || rateId == null || startDate == null) {
            throw new IllegalArgumentException("매장, 요금제, 계약 시작일은 필수입니다.");
        }
    }

    public void validateSnapshotType(String snapshotType) {
        if (snapshotType == null || !SNAPSHOT_TYPES.contains(snapshotType.trim().toUpperCase())) {
            throw new IllegalArgumentException("유효하지 않은 스냅샷 유형입니다.");
        }
    }

    public void validateStatementStatus(String statementStatus) {
        if (statementStatus == null || !STATEMENT_STATUSES.contains(statementStatus.trim().toUpperCase())) {
            throw new IllegalArgumentException("유효하지 않은 청구서 상태입니다.");
        }
    }

    public void requireCycleId(Integer cycleId) {
        if (cycleId == null) {
            throw new IllegalArgumentException("유효한 정산 주기가 필요합니다.");
        }
    }

    public void requireBillingMonth(String billingMonth) {
        if (billingMonth == null || !billingMonth.matches("\\d{4}-\\d{2}")) {
            throw new IllegalArgumentException("정산월 형식이 올바르지 않습니다.");
        }
    }
}
