package epms.plc;

import java.util.ArrayList;
import java.util.List;

public final class PlcReadResult {
    public boolean ok = false;
    public String info = "";
    public String error = "";
    public long totalMs = 0L;
    public long diMs = 0L;
    public long aiMs = 0L;
    public long procMs = 0L;
    public int measurementsInserted = 0;
    public int harmonicInserted = 0;
    public int flickerInserted = 0;
    public int deviceEventsOpened = 0;
    public int deviceEventsClosed = 0;
    public int aiAlarmOpened = 0;
    public int aiAlarmClosed = 0;
    public List<PlcAiReadRow> rows = new ArrayList<>();
    public List<PlcDiReadRow> diRows = new ArrayList<>();
}
