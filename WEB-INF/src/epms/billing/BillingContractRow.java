package epms.billing;

import java.sql.Date;

public final class BillingContractRow {
    private final long contractId;
    private final String storeCode;
    private final String storeName;
    private final String rateCode;
    private final String rateName;
    private final Date contractStartDate;
    private final Object contractedDemandKw;

    public BillingContractRow(long contractId, String storeCode, String storeName, String rateCode,
            String rateName, Date contractStartDate, Object contractedDemandKw) {
        this.contractId = contractId;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.rateCode = rateCode;
        this.rateName = rateName;
        this.contractStartDate = contractStartDate;
        this.contractedDemandKw = contractedDemandKw;
    }

    public long getContractId() { return contractId; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public String getRateCode() { return rateCode; }
    public String getRateName() { return rateName; }
    public Date getContractStartDate() { return contractStartDate; }
    public Object getContractedDemandKw() { return contractedDemandKw; }
}
