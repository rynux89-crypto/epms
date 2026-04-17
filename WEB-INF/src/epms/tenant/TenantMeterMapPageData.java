package epms.tenant;

import java.util.ArrayList;
import java.util.List;

public final class TenantMeterMapPageData {
    private final List<TenantOption> storeOptions = new ArrayList<>();
    private final List<TenantOption> meterOptions = new ArrayList<>();
    private final List<String> buildingOptions = new ArrayList<>();
    private final List<TenantMeterMapRow> rows = new ArrayList<>();
    private TenantMeterMapRow selectedRow;
    private int totalMapCount;
    private int primaryCount;

    public List<TenantOption> getStoreOptions() { return storeOptions; }
    public List<TenantOption> getMeterOptions() { return meterOptions; }
    public List<String> getBuildingOptions() { return buildingOptions; }
    public List<TenantMeterMapRow> getRows() { return rows; }
    public TenantMeterMapRow getSelectedRow() { return selectedRow; }
    public void setSelectedRow(TenantMeterMapRow selectedRow) { this.selectedRow = selectedRow; }
    public int getTotalMapCount() { return totalMapCount; }
    public void setTotalMapCount(int totalMapCount) { this.totalMapCount = totalMapCount; }
    public int getPrimaryCount() { return primaryCount; }
    public void setPrimaryCount(int primaryCount) { this.primaryCount = primaryCount; }
}
