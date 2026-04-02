package epms.plc;

public final class PlcAiReadRow {
    public final int idx;
    public final int meterId;
    public final int floatIndex;
    public final String token;
    public final int reg1;
    public final int reg2;
    public final String byteOrder;
    public final double value;

    public PlcAiReadRow(int idx, int meterId, int floatIndex, String token, int reg1, int reg2, String byteOrder, double value) {
        this.idx = idx;
        this.meterId = meterId;
        this.floatIndex = floatIndex;
        this.token = token;
        this.reg1 = reg1;
        this.reg2 = reg2;
        this.byteOrder = byteOrder;
        this.value = value;
    }
}
