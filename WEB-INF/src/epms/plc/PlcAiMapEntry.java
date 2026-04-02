package epms.plc;

public final class PlcAiMapEntry {
    public final int meterId;
    public final int startAddress;
    public final int floatCount;
    public final String byteOrder;
    public final String metricOrder;
    public final String[] tokens;

    public PlcAiMapEntry(int meterId, int startAddress, int floatCount, String byteOrder, String metricOrder, String[] tokens) {
        this.meterId = meterId;
        this.startAddress = startAddress;
        this.floatCount = floatCount;
        this.byteOrder = byteOrder;
        this.metricOrder = metricOrder;
        this.tokens = tokens == null ? new String[0] : tokens;
    }
}
