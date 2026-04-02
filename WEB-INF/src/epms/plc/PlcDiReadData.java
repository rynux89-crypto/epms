package epms.plc;

import java.util.List;

public final class PlcDiReadData {
    public final List<PlcDiReadRow> rows;
    public final long durationMs;

    public PlcDiReadData(List<PlcDiReadRow> rows, long durationMs) {
        this.rows = rows;
        this.durationMs = durationMs;
    }
}
