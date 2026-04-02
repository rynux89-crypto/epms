package epms.plc;

import java.util.List;

public final class PlcAiReadData {
    public final List<PlcAiReadRow> rows;
    public final int meterRead;
    public final int totalFloat;
    public final long durationMs;

    public PlcAiReadData(List<PlcAiReadRow> rows, int meterRead, int totalFloat, long durationMs) {
        this.rows = rows;
        this.meterRead = meterRead;
        this.totalFloat = totalFloat;
        this.durationMs = durationMs;
    }
}
