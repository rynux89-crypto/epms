package epms.plc;

public final class PlcDiTagEntry {
    public final int pointId;
    public final int diAddress;
    public final int bitNo;
    public final String tagName;
    public final String itemName;
    public final String panelName;

    public PlcDiTagEntry(int pointId, int diAddress, int bitNo, String tagName, String itemName, String panelName) {
        this.pointId = pointId;
        this.diAddress = diAddress;
        this.bitNo = bitNo;
        this.tagName = tagName;
        this.itemName = itemName;
        this.panelName = panelName;
    }
}
