package epms.billing;

import java.util.ArrayList;
import java.util.List;

public final class BillingManagePageData {
    private String cycleFilter;
    private BillingCycleRow selectedCycle;
    private String nextRateCode = "RATE0001";
    private int statementCount;
    private int snapshotCount;
    private boolean allowClosingRun;
    private boolean allowStatementRun;
    private String runBlockMessage;
    private final List<BillingOption> storeOptions = new ArrayList<>();
    private final List<BillingOption> rateOptions = new ArrayList<>();
    private final List<BillingRateRow> rates = new ArrayList<>();
    private final List<BillingContractRow> contracts = new ArrayList<>();
    private final List<BillingCycleRow> cycles = new ArrayList<>();
    private final List<BillingStatementRow> statements = new ArrayList<>();

    public String getCycleFilter() { return cycleFilter; }
    public void setCycleFilter(String cycleFilter) { this.cycleFilter = cycleFilter; }
    public BillingCycleRow getSelectedCycle() { return selectedCycle; }
    public void setSelectedCycle(BillingCycleRow selectedCycle) { this.selectedCycle = selectedCycle; }
    public String getNextRateCode() { return nextRateCode; }
    public void setNextRateCode(String nextRateCode) { this.nextRateCode = nextRateCode; }
    public int getStatementCount() { return statementCount; }
    public void setStatementCount(int statementCount) { this.statementCount = statementCount; }
    public int getSnapshotCount() { return snapshotCount; }
    public void setSnapshotCount(int snapshotCount) { this.snapshotCount = snapshotCount; }
    public boolean isAllowClosingRun() { return allowClosingRun; }
    public void setAllowClosingRun(boolean allowClosingRun) { this.allowClosingRun = allowClosingRun; }
    public boolean isAllowStatementRun() { return allowStatementRun; }
    public void setAllowStatementRun(boolean allowStatementRun) { this.allowStatementRun = allowStatementRun; }
    public String getRunBlockMessage() { return runBlockMessage; }
    public void setRunBlockMessage(String runBlockMessage) { this.runBlockMessage = runBlockMessage; }
    public List<BillingOption> getStoreOptions() { return storeOptions; }
    public List<BillingOption> getRateOptions() { return rateOptions; }
    public List<BillingRateRow> getRates() { return rates; }
    public List<BillingContractRow> getContracts() { return contracts; }
    public List<BillingCycleRow> getCycles() { return cycles; }
    public List<BillingStatementRow> getStatements() { return statements; }
}
