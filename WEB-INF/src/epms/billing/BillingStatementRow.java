package epms.billing;

import java.math.BigDecimal;
import java.sql.Timestamp;

public final class BillingStatementRow {
    private final long statementId;
    private final String storeCode;
    private final String storeName;
    private final BigDecimal usageKwh;
    private final Object peakDemandKw;
    private final BigDecimal totalAmount;
    private final String statementStatus;
    private final Timestamp issuedAt;

    public BillingStatementRow(long statementId, String storeCode, String storeName, BigDecimal usageKwh,
            Object peakDemandKw, BigDecimal totalAmount, String statementStatus, Timestamp issuedAt) {
        this.statementId = statementId;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.usageKwh = usageKwh;
        this.peakDemandKw = peakDemandKw;
        this.totalAmount = totalAmount;
        this.statementStatus = statementStatus;
        this.issuedAt = issuedAt;
    }

    public long getStatementId() { return statementId; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public BigDecimal getUsageKwh() { return usageKwh; }
    public Object getPeakDemandKw() { return peakDemandKw; }
    public BigDecimal getTotalAmount() { return totalAmount; }
    public String getStatementStatus() { return statementStatus; }
    public Timestamp getIssuedAt() { return issuedAt; }
}
