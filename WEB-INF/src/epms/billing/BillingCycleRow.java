package epms.billing;

import java.sql.Date;

public final class BillingCycleRow {
    private final int cycleId;
    private final String cycleCode;
    private final Date cycleStartDate;
    private final Date cycleEndDate;
    private final String status;

    public BillingCycleRow(int cycleId, String cycleCode, Date cycleStartDate, Date cycleEndDate, String status) {
        this.cycleId = cycleId;
        this.cycleCode = cycleCode;
        this.cycleStartDate = cycleStartDate;
        this.cycleEndDate = cycleEndDate;
        this.status = status;
    }

    public int getCycleId() { return cycleId; }
    public String getCycleCode() { return cycleCode; }
    public Date getCycleStartDate() { return cycleStartDate; }
    public Date getCycleEndDate() { return cycleEndDate; }
    public String getStatus() { return status; }
}
