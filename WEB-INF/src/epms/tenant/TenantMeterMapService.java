package epms.tenant;

import epms.validation.ValidationService;
import java.sql.Connection;
import java.sql.Date;
import java.util.List;

public final class TenantMeterMapService {
    private final TenantMeterMapRepository repository;
    private final ValidationService validationService;

    public TenantMeterMapService() {
        this(new TenantMeterMapRepository(), new ValidationService());
    }

    public TenantMeterMapService(TenantMeterMapRepository repository, ValidationService validationService) {
        this.repository = repository;
        this.validationService = validationService;
    }

    public TenantMeterMapPageData loadPageData(String storeFilter, String buildingFilter, Long editId) throws Exception {
        TenantMeterMapPageData data = new TenantMeterMapPageData();
        try (Connection conn = repository.openConnection()) {
            data.getStoreOptions().addAll(repository.listStoreOptions(conn));
            data.getMeterOptions().addAll(repository.listMeterOptions(conn, buildingFilter));
            data.getBuildingOptions().addAll(repository.listBuildingOptions(conn));
            int[] counts = repository.countMapSummary(conn);
            data.setTotalMapCount(counts[0]);
            data.setPrimaryCount(counts[1]);
            List<TenantMeterMapRow> rows = repository.listRows(conn, storeFilter, buildingFilter);
            data.getRows().addAll(rows);
            if (editId != null) {
                for (TenantMeterMapRow row : rows) {
                    if (row.getMapId() == editId.longValue()) {
                        data.setSelectedRow(row);
                        break;
                    }
                }
            }
        }
        return data;
    }

    public Long addMap(Integer storeId, Integer meterId, String scope, Double ratio, boolean isPrimary,
            Date validFrom, Date validTo, String notes) throws Exception {
        validationService.validateMapRequired(storeId, meterId, validFrom);
        validationService.validateMapDateRange(validFrom, validTo);
        double actualRatio = validationService.normalizeAllocationRatio(ratio);
        String actualScope = validationService.normalizeBillingScope(scope);
        try (Connection conn = repository.openConnection()) {
            if (isPrimary) repository.clearPrimaryForStore(conn, storeId.intValue());
            return repository.addMap(conn, storeId.intValue(), meterId.intValue(), actualScope, actualRatio, isPrimary, validFrom, validTo, notes);
        }
    }

    public void updateMap(Long mapId, Integer storeId, Integer meterId, String scope, Double ratio, boolean isPrimary,
            Date validFrom, Date validTo, String notes) throws Exception {
        validationService.requireMapId(mapId);
        validationService.validateMapRequired(storeId, meterId, validFrom);
        validationService.validateMapDateRange(validFrom, validTo);
        double actualRatio = validationService.normalizeAllocationRatio(ratio);
        String actualScope = validationService.normalizeBillingScope(scope);
        try (Connection conn = repository.openConnection()) {
            if (isPrimary) repository.clearPrimaryForStoreExcept(conn, storeId.intValue(), mapId.longValue());
            repository.updateMap(conn, mapId.longValue(), storeId.intValue(), meterId.intValue(), actualScope, actualRatio, isPrimary, validFrom, validTo, notes);
        }
    }

    public void deleteMap(Long mapId) throws Exception {
        validationService.requireMapId(mapId);
        try (Connection conn = repository.openConnection()) {
            repository.deleteMap(conn, mapId.longValue());
        }
    }
}
