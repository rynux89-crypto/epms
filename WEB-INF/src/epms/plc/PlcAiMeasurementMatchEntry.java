package epms.plc;

public final class PlcAiMeasurementMatchEntry {
    public final String token;
    public final int floatIndex;
    public final String measurementColumn;
    public final String targetTable;

    public PlcAiMeasurementMatchEntry(String token, int floatIndex, String measurementColumn, String targetTable) {
        this.token = token;
        this.floatIndex = floatIndex;
        this.measurementColumn = measurementColumn;
        this.targetTable = targetTable;
    }
}
