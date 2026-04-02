package epms.plc;

public final class PlcAiMeasurementMatchEntry {
    public final String token;
    public final String measurementColumn;
    public final String targetTable;

    public PlcAiMeasurementMatchEntry(String token, String measurementColumn, String targetTable) {
        this.token = token;
        this.measurementColumn = measurementColumn;
        this.targetTable = targetTable;
    }
}
