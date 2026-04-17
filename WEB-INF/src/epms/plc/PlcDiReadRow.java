package epms.plc;

public final class PlcDiReadRow {
    public final int idx;
    public final int meterId;
    public final int pointId;
    public final int diAddress;
    public final int bitNo;
    public final String tagName;
    public final String itemName;
    public final String panelName;
    public final int value;

    public PlcDiReadRow(int idx, int meterId, int pointId, int diAddress, int bitNo, String tagName, String itemName, String panelName, int value) {
        this.idx = idx;
        this.meterId = meterId;
        this.pointId = pointId;
        this.diAddress = diAddress;
        this.bitNo = bitNo;
        this.tagName = tagName;
        this.itemName = itemName;
        this.panelName = panelName;
        this.value = value;
    }
}
