package epms.remote;

import java.sql.Date;
import java.sql.Timestamp;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public final class EnergyDetailPageData {
    private final int storeId;
    private final int meterId;
    private final String storeCode;
    private final String storeName;
    private final String categoryName;
    private final String contactName;
    private final String contactPhone;
    private final String meterName;
    private final String buildingName;
    private final String panelName;
    private final String usageType;
    private final String locationText;
    private final Date openedOn;
    private final Date closedOn;
    private final Date validFrom;
    private final Date validTo;
    private final Date effectiveStart;
    private final Date effectiveEnd;
    private final Double allocationRatio;
    private final String billingScope;
    private final Boolean isPrimary;
    private final Timestamp currentMeasuredAt;
    private final Timestamp currentValidMeasuredAt;
    private final double shownCurrentKw;
    private final boolean usingFallbackCurrent;
    private final double todayKwh;
    private final double currentMonthKwh;
    private final double prevMonthKwh;
    private final String todayText;
    private final String currentMonthText;
    private final String prevMonthText;
    private final Map<String, Double> dailyUsage;
    private final Map<String, Double> monthlyUsage;
    private final String queryError;

    public EnergyDetailPageData(int storeId, int meterId, String storeCode, String storeName, String categoryName,
            String contactName, String contactPhone, String meterName, String buildingName, String panelName,
            String usageType, String locationText, Date openedOn, Date closedOn, Date validFrom, Date validTo,
            Date effectiveStart, Date effectiveEnd, Double allocationRatio, String billingScope, Boolean isPrimary,
            Timestamp currentMeasuredAt, Timestamp currentValidMeasuredAt, double shownCurrentKw,
            boolean usingFallbackCurrent, double todayKwh, double currentMonthKwh, double prevMonthKwh,
            String todayText, String currentMonthText, String prevMonthText, Map<String, Double> dailyUsage,
            Map<String, Double> monthlyUsage, String queryError) {
        this.storeId = storeId;
        this.meterId = meterId;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.categoryName = categoryName;
        this.contactName = contactName;
        this.contactPhone = contactPhone;
        this.meterName = meterName;
        this.buildingName = buildingName;
        this.panelName = panelName;
        this.usageType = usageType;
        this.locationText = locationText;
        this.openedOn = openedOn;
        this.closedOn = closedOn;
        this.validFrom = validFrom;
        this.validTo = validTo;
        this.effectiveStart = effectiveStart;
        this.effectiveEnd = effectiveEnd;
        this.allocationRatio = allocationRatio;
        this.billingScope = billingScope;
        this.isPrimary = isPrimary;
        this.currentMeasuredAt = currentMeasuredAt;
        this.currentValidMeasuredAt = currentValidMeasuredAt;
        this.shownCurrentKw = shownCurrentKw;
        this.usingFallbackCurrent = usingFallbackCurrent;
        this.todayKwh = todayKwh;
        this.currentMonthKwh = currentMonthKwh;
        this.prevMonthKwh = prevMonthKwh;
        this.todayText = todayText;
        this.currentMonthText = currentMonthText;
        this.prevMonthText = prevMonthText;
        this.dailyUsage = dailyUsage == null ? Collections.<String, Double>emptyMap() : new LinkedHashMap<String, Double>(dailyUsage);
        this.monthlyUsage = monthlyUsage == null ? Collections.<String, Double>emptyMap() : new LinkedHashMap<String, Double>(monthlyUsage);
        this.queryError = queryError;
    }

    public int getStoreId() { return storeId; }
    public int getMeterId() { return meterId; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public String getCategoryName() { return categoryName; }
    public String getContactName() { return contactName; }
    public String getContactPhone() { return contactPhone; }
    public String getMeterName() { return meterName; }
    public String getBuildingName() { return buildingName; }
    public String getPanelName() { return panelName; }
    public String getUsageType() { return usageType; }
    public String getLocationText() { return locationText; }
    public Date getOpenedOn() { return openedOn; }
    public Date getClosedOn() { return closedOn; }
    public Date getValidFrom() { return validFrom; }
    public Date getValidTo() { return validTo; }
    public Date getEffectiveStart() { return effectiveStart; }
    public Date getEffectiveEnd() { return effectiveEnd; }
    public Double getAllocationRatio() { return allocationRatio; }
    public String getBillingScope() { return billingScope; }
    public Boolean getIsPrimary() { return isPrimary; }
    public Timestamp getCurrentMeasuredAt() { return currentMeasuredAt; }
    public Timestamp getCurrentValidMeasuredAt() { return currentValidMeasuredAt; }
    public double getShownCurrentKw() { return shownCurrentKw; }
    public boolean isUsingFallbackCurrent() { return usingFallbackCurrent; }
    public double getTodayKwh() { return todayKwh; }
    public double getCurrentMonthKwh() { return currentMonthKwh; }
    public double getPrevMonthKwh() { return prevMonthKwh; }
    public String getTodayText() { return todayText; }
    public String getCurrentMonthText() { return currentMonthText; }
    public String getPrevMonthText() { return prevMonthText; }
    public Map<String, Double> getDailyUsage() { return dailyUsage; }
    public Map<String, Double> getMonthlyUsage() { return monthlyUsage; }
    public String getQueryError() { return queryError; }
}
