package epms.tenant;

import java.sql.Date;

public final class TenantStoreRow {
    private final int storeId;
    private final String storeCode;
    private final String storeName;
    private final String businessNumber;
    private final String floorName;
    private final String roomName;
    private final String zoneName;
    private final String categoryName;
    private final String contactName;
    private final String contactPhone;
    private final String status;
    private final Date openedOn;
    private final Date closedOn;
    private final String notes;

    public TenantStoreRow(int storeId, String storeCode, String storeName, String businessNumber,
            String floorName, String roomName, String zoneName, String categoryName,
            String contactName, String contactPhone, String status, Date openedOn,
            Date closedOn, String notes) {
        this.storeId = storeId;
        this.storeCode = storeCode;
        this.storeName = storeName;
        this.businessNumber = businessNumber;
        this.floorName = floorName;
        this.roomName = roomName;
        this.zoneName = zoneName;
        this.categoryName = categoryName;
        this.contactName = contactName;
        this.contactPhone = contactPhone;
        this.status = status;
        this.openedOn = openedOn;
        this.closedOn = closedOn;
        this.notes = notes;
    }

    public int getStoreId() { return storeId; }
    public String getStoreCode() { return storeCode; }
    public String getStoreName() { return storeName; }
    public String getBusinessNumber() { return businessNumber; }
    public String getFloorName() { return floorName; }
    public String getRoomName() { return roomName; }
    public String getZoneName() { return zoneName; }
    public String getCategoryName() { return categoryName; }
    public String getContactName() { return contactName; }
    public String getContactPhone() { return contactPhone; }
    public String getStatus() { return status; }
    public Date getOpenedOn() { return openedOn; }
    public Date getClosedOn() { return closedOn; }
    public String getNotes() { return notes; }
}
