package epms.tenant;

import epms.validation.ValidationService;
import java.sql.Connection;
import java.sql.Date;
import java.util.List;

public final class TenantStoreService {
    private static final String STORE_CODE_PREFIX = "STORE";
    private final TenantStoreRepository repository;
    private final ValidationService validationService;

    public TenantStoreService() {
        this(new TenantStoreRepository(), new ValidationService());
    }

    public TenantStoreService(TenantStoreRepository repository, ValidationService validationService) {
        this.repository = repository;
        this.validationService = validationService;
    }

    public TenantStorePageData loadPageData(String searchQ, String statusQ, Integer editId) throws Exception {
        TenantStorePageData data = new TenantStorePageData();
        try (Connection conn = repository.openConnection()) {
            int[] counts = repository.countSummary(conn);
            data.setTotalCount(counts[0]);
            data.setActiveCount(counts[1]);
            data.setClosedCount(counts[2]);
            data.setGeneratedStoreCode(repository.nextStoreCode(conn, STORE_CODE_PREFIX));
            List<TenantStoreRow> rows = repository.listStores(conn, searchQ, statusQ);
            data.getRows().addAll(rows);
            if (editId != null) {
                for (TenantStoreRow row : rows) {
                    if (row.getStoreId() == editId.intValue()) {
                        data.setSelectedRow(row);
                        break;
                    }
                }
            }
        }
        return data;
    }

    public String addStore(String storeCode, String storeName, String businessNumber, String floorName,
            String roomName, String zoneName, String categoryName, String contactName, String contactPhone,
            String status, Date openedOn, Date closedOn, String notes) throws Exception {
        validationService.requireStoreName(storeName);
        validationService.validateStoreDateRange(openedOn, closedOn);
        try (Connection conn = repository.openConnection()) {
            String actualStoreCode = storeCode;
            if (actualStoreCode == null || actualStoreCode.trim().isEmpty()) {
                actualStoreCode = repository.nextStoreCode(conn, STORE_CODE_PREFIX);
            }
            String actualStatus = validationService.normalizeStoreStatus(status);
            repository.addStore(conn, new TenantStoreRow(
                    0, actualStoreCode, storeName, businessNumber, floorName, roomName, zoneName,
                    categoryName, contactName, contactPhone, actualStatus, openedOn, closedOn, notes));
        }
        return "매장을 등록했습니다.";
    }

    public String updateStore(Integer storeId, String storeCode, String storeName, String businessNumber,
            String floorName, String roomName, String zoneName, String categoryName, String contactName,
            String contactPhone, String status, Date openedOn, Date closedOn, String notes) throws Exception {
        validationService.requireStoreId(storeId);
        validationService.requireStoreName(storeName);
        validationService.validateStoreDateRange(openedOn, closedOn);
        String actualStatus = validationService.normalizeStoreStatus(status);
        try (Connection conn = repository.openConnection()) {
            repository.updateStore(conn, new TenantStoreRow(
                    storeId.intValue(), storeCode, storeName, businessNumber, floorName, roomName, zoneName,
                    categoryName, contactName, contactPhone, actualStatus, openedOn, closedOn, notes));
        }
        return "매장 정보를 수정했습니다.";
    }

    public String deleteStore(Integer storeId) throws Exception {
        validationService.requireStoreId(storeId);
        try (Connection conn = repository.openConnection()) {
            repository.validateDeleteAllowed(conn, storeId.intValue());
            repository.deleteStore(conn, storeId.intValue());
        }
        return "매장을 삭제했습니다.";
    }
}
