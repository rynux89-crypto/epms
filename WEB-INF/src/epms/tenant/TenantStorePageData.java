package epms.tenant;

import java.util.ArrayList;
import java.util.List;

public final class TenantStorePageData {
    private int totalCount;
    private int activeCount;
    private int closedCount;
    private String generatedStoreCode;
    private TenantStoreRow selectedRow;
    private final List<TenantStoreRow> rows = new ArrayList<>();

    public int getTotalCount() { return totalCount; }
    public void setTotalCount(int totalCount) { this.totalCount = totalCount; }
    public int getActiveCount() { return activeCount; }
    public void setActiveCount(int activeCount) { this.activeCount = activeCount; }
    public int getClosedCount() { return closedCount; }
    public void setClosedCount(int closedCount) { this.closedCount = closedCount; }
    public String getGeneratedStoreCode() { return generatedStoreCode; }
    public void setGeneratedStoreCode(String generatedStoreCode) { this.generatedStoreCode = generatedStoreCode; }
    public TenantStoreRow getSelectedRow() { return selectedRow; }
    public void setSelectedRow(TenantStoreRow selectedRow) { this.selectedRow = selectedRow; }
    public List<TenantStoreRow> getRows() { return rows; }
}
