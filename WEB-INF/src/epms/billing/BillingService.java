package epms.billing;

import epms.validation.ValidationService;
import java.sql.Connection;
import java.sql.Date;
import java.time.LocalDate;
import java.util.List;

public final class BillingService {
    private final BillingRepository repository;
    private final ValidationService validationService;

    public BillingService() {
        this(new BillingRepository(), new ValidationService());
    }

    public BillingService(BillingRepository repository, ValidationService validationService) {
        this.repository = repository;
        this.validationService = validationService;
    }

    public BillingManagePageData loadPageData(String billingMonth, String cycleFilter, LocalDate todayLocal) throws Exception {
        validationService.requireBillingMonth(billingMonth);
        BillingManagePageData data = new BillingManagePageData();
        try (Connection conn = repository.openConnection()) {
            String effectiveCycleFilter = cycleFilter == null ? "" : cycleFilter.trim();
            if (effectiveCycleFilter.isEmpty()) {
                Integer autoCycleId = repository.ensureMonthlyCycle(conn, billingMonth);
                if (autoCycleId != null) effectiveCycleFilter = String.valueOf(autoCycleId);
            }

            List<BillingRateRow> rates = repository.listRates(conn);
            List<BillingCycleRow> cycles = repository.listCycles(conn);
            BillingCycleRow selectedCycle = null;
            for (BillingCycleRow row : cycles) {
                if (String.valueOf(row.getCycleId()).equals(effectiveCycleFilter)) selectedCycle = row;
                if (billingMonth.equals(row.getCycleCode())) {
                    effectiveCycleFilter = String.valueOf(row.getCycleId());
                    selectedCycle = row;
                }
            }

            data.setCycleFilter(effectiveCycleFilter);
            data.setSelectedCycle(selectedCycle);
            data.setNextRateCode(repository.nextRateCode(conn));
            data.setStatementCount(repository.countStatements(conn));
            data.setSnapshotCount(repository.countSnapshots(conn));
            data.getStoreOptions().addAll(repository.listStoreOptions(conn));
            data.getRates().addAll(rates);
            data.getRateOptions().addAll(repository.toRateOptions(rates));
            data.getContracts().addAll(repository.listContracts(conn));
            data.getCycles().addAll(cycles);
            data.getStatements().addAll(repository.listStatements(conn, effectiveCycleFilter));

            if (selectedCycle != null && selectedCycle.getCycleEndDate() != null) {
                LocalDate cycleEndLocal = selectedCycle.getCycleEndDate().toLocalDate();
                boolean allowClosingRun = todayLocal.isAfter(cycleEndLocal);
                data.setAllowClosingRun(allowClosingRun);
                data.setAllowStatementRun(allowClosingRun);
                if (!allowClosingRun) {
                    data.setRunBlockMessage("현재 진행 중인 월은 마감 검침과 매장 청구를 생성할 수 없습니다. 월 종료 후 실행하세요.");
                }
            }
        }
        return data;
    }

    public String addRate(String rateCode, String rateName, Date effectiveFrom, Double unitPrice, Double basicCharge, Double demandPrice) throws Exception {
        try (Connection conn = repository.openConnection()) {
            String actualRateCode = rateCode;
            if (actualRateCode == null || actualRateCode.trim().isEmpty()) actualRateCode = repository.nextRateCode(conn);
            validationService.requireRateFields(actualRateCode, rateName, effectiveFrom);
            repository.addRate(conn, actualRateCode, rateName, effectiveFrom, safeZero(unitPrice), safeZero(basicCharge), safeZero(demandPrice));
        }
        return "요금제를 등록했습니다.";
    }

    public String deleteRate(Integer rateId) throws Exception {
        try (Connection conn = repository.openConnection()) {
            repository.deleteRate(conn, rateId);
        }
        return "요금제를 삭제했습니다.";
    }

    public String addContract(Integer storeId, Integer rateId, Date startDate, Double demandKw) throws Exception {
        validationService.requireContractFields(storeId, rateId, startDate);
        try (Connection conn = repository.openConnection()) {
            repository.addContract(conn, storeId, rateId, startDate, demandKw);
        }
        return "계약을 등록했습니다.";
    }

    public String deleteContract(Long contractId) throws Exception {
        try (Connection conn = repository.openConnection()) {
            repository.deleteContract(conn, contractId);
        }
        return "계약을 삭제했습니다.";
    }

    public String deleteCycle(Integer cycleId) throws Exception {
        try (Connection conn = repository.openConnection()) {
            repository.deleteCycle(conn, cycleId);
        }
        return "정산 주기를 삭제했습니다.";
    }

    public Integer ensureCycle(String runMonth, Integer cycleId) throws Exception {
        if (cycleId != null) return cycleId;
        validationService.requireBillingMonth(runMonth);
        try (Connection conn = repository.openConnection()) {
            return repository.ensureMonthlyCycle(conn, runMonth);
        }
    }

    public String generateSnapshot(Integer cycleId, String snapshotType) throws Exception {
        validationService.requireCycleId(cycleId);
        validationService.validateSnapshotType(snapshotType);
        try (Connection conn = repository.openConnection()) {
            String actualType = snapshotType.trim().toUpperCase();
            BillingPrecheckResult precheck = validateSnapshotRun(conn, cycleId.intValue(), actualType);
            if (precheck.hasErrors()) {
                throw new IllegalStateException(precheck.summarizeErrors());
            }
            repository.runSnapshot(conn, cycleId, actualType);
        }
        return snapshotType + " 검침 스냅샷을 생성했습니다.";
    }

    public String generateStatement(Integer cycleId) throws Exception {
        validationService.requireCycleId(cycleId);
        try (Connection conn = repository.openConnection()) {
            BillingPrecheckResult precheck = validateStatementRun(conn, cycleId.intValue());
            if (precheck.hasErrors()) {
                throw new IllegalStateException(precheck.summarizeErrors());
            }
            repository.runStatement(conn, cycleId);
        }
        return "청구서를 생성했습니다.";
    }

    public String updateStatementStatus(Long statementId, String statementStatus) throws Exception {
        if (statementId == null) {
            throw new IllegalArgumentException("유효한 청구서 ID가 필요합니다.");
        }
        validationService.validateStatementStatus(statementStatus);
        try (Connection conn = repository.openConnection()) {
            repository.updateStatementStatus(conn, statementId, statementStatus.trim().toUpperCase());
        }
        return "청구서 상태를 변경했습니다.";
    }

    private static Double safeZero(Double value) {
        return value == null ? Double.valueOf(0.0d) : value;
    }

    private BillingPrecheckResult validateSnapshotRun(Connection conn, int cycleId, String snapshotType) throws Exception {
        BillingPrecheckResult result = new BillingPrecheckResult();
        if (!repository.cycleExists(conn, cycleId)) {
            result.addError("선택한 정산 주기가 존재하지 않습니다.");
            return result;
        }

        int mapCount = repository.countActiveStoreMeterMapsForCycle(conn, cycleId);
        if (mapCount <= 0) {
            result.addError("선택 월에 유효한 매장-계측기 연결이 없습니다.");
            return result;
        }

        int measurementCandidateCount = repository.countSnapshotMeasurementCandidates(conn, cycleId, snapshotType);
        if (measurementCandidateCount <= 0) {
            result.addError("스냅샷 생성에 사용할 계측 데이터가 없습니다.");
        } else if (measurementCandidateCount < mapCount) {
            result.addWarning("일부 매장은 스냅샷 후보 계측 데이터가 부족할 수 있습니다.");
        }
        return result;
    }

    private BillingPrecheckResult validateStatementRun(Connection conn, int cycleId) throws Exception {
        BillingPrecheckResult result = new BillingPrecheckResult();
        if (!repository.cycleExists(conn, cycleId)) {
            result.addError("선택한 정산 주기가 존재하지 않습니다.");
            return result;
        }

        int contractCount = repository.countActiveContractsForCycle(conn, cycleId);
        if (contractCount <= 0) {
            result.addError("선택 월에 유효한 계약 정보가 없습니다.");
        }

        int openingCount = repository.countOpeningSnapshots(conn, cycleId);
        int closingCount = repository.countClosingSnapshots(conn, cycleId);
        if (openingCount <= 0) {
            result.addError("시작 검침 스냅샷이 없습니다.");
        }
        if (closingCount <= 0) {
            result.addError("마감 검침 스냅샷이 없습니다.");
        }
        return result;
    }
}
