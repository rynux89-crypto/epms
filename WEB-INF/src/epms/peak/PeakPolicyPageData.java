package epms.peak;

import java.util.Collections;
import java.util.List;

public final class PeakPolicyPageData {
    private final List<PeakStoreOption> storeOptions;
    private final List<PeakPolicyRow> rows;
    private final PeakPolicyRow selectedRow;

    public PeakPolicyPageData(List<PeakStoreOption> storeOptions, List<PeakPolicyRow> rows, PeakPolicyRow selectedRow) {
        this.storeOptions = storeOptions == null ? Collections.<PeakStoreOption>emptyList() : storeOptions;
        this.rows = rows == null ? Collections.<PeakPolicyRow>emptyList() : rows;
        this.selectedRow = selectedRow;
    }

    public List<PeakStoreOption> getStoreOptions() { return storeOptions; }
    public List<PeakPolicyRow> getRows() { return rows; }
    public PeakPolicyRow getSelectedRow() { return selectedRow; }
}
