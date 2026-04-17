package epms.billing;

import java.math.BigDecimal;
import java.sql.Date;

public final class BillingRateRow {
    private final int rateId;
    private final String rateCode;
    private final String rateName;
    private final Date effectiveFrom;
    private final BigDecimal unitPricePerKwh;
    private final BigDecimal basicChargeAmount;
    private final BigDecimal demandUnitPrice;

    public BillingRateRow(int rateId, String rateCode, String rateName, Date effectiveFrom,
            BigDecimal unitPricePerKwh, BigDecimal basicChargeAmount, BigDecimal demandUnitPrice) {
        this.rateId = rateId;
        this.rateCode = rateCode;
        this.rateName = rateName;
        this.effectiveFrom = effectiveFrom;
        this.unitPricePerKwh = unitPricePerKwh;
        this.basicChargeAmount = basicChargeAmount;
        this.demandUnitPrice = demandUnitPrice;
    }

    public int getRateId() { return rateId; }
    public String getRateCode() { return rateCode; }
    public String getRateName() { return rateName; }
    public Date getEffectiveFrom() { return effectiveFrom; }
    public BigDecimal getUnitPricePerKwh() { return unitPricePerKwh; }
    public BigDecimal getBasicChargeAmount() { return basicChargeAmount; }
    public BigDecimal getDemandUnitPrice() { return demandUnitPrice; }
}
