package epms.util;

import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class PlcWriteSupport {
    private PlcWriteSupport() {
    }

    public static int toU16(byte hi, byte lo) {
        return ((hi & 0xFF) << 8) | (lo & 0xFF);
    }

    public static int toHoldingOffset(int addr) {
        if (addr >= 40001 && addr <= 49999) return addr - 40001;
        if (addr >= 400001 && addr <= 499999) return addr - 400001;
        return addr;
    }

    public static int toCoilOffset(int addr) {
        if (addr >= 1 && addr <= 9999) return addr - 1;
        if (addr >= 10001 && addr <= 19999) return addr - 10001;
        if (addr >= 100001 && addr <= 199999) return addr - 100001;
        if (addr >= 400001 && addr <= 499999) return addr - 400001;
        return addr;
    }

    public static byte[] readExactly(InputStream in, int len) throws IOException {
        byte[] b = new byte[len];
        int off = 0;
        while (off < len) {
            int n = in.read(b, off, len - off);
            if (n < 0) throw new EOFException("PLC response ended unexpectedly.");
            off += n;
        }
        return b;
    }

    public static int[] floatToRegs(float f, String byteOrder) {
        ByteBuffer bb = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putFloat(f);
        byte[] src = bb.array();
        byte[] out = new byte[4];
        String bo = byteOrder == null ? "ABCD" : byteOrder.trim().toUpperCase(java.util.Locale.ROOT);
        if ("BADC".equals(bo)) {
            out[0] = src[1]; out[1] = src[0]; out[2] = src[3]; out[3] = src[2];
        } else if ("CDAB".equals(bo)) {
            out[0] = src[2]; out[1] = src[3]; out[2] = src[0]; out[3] = src[1];
        } else if ("DCBA".equals(bo)) {
            out[0] = src[3]; out[1] = src[2]; out[2] = src[1]; out[3] = src[0];
        } else {
            out = src;
        }
        return new int[]{((out[0] & 0xFF) << 8) | (out[1] & 0xFF), ((out[2] & 0xFF) << 8) | (out[3] & 0xFF)};
    }

    public static float regsToFloat(int reg1, int reg2, String byteOrder) {
        byte x0 = (byte) ((reg1 >> 8) & 0xFF);
        byte x1 = (byte) (reg1 & 0xFF);
        byte x2 = (byte) ((reg2 >> 8) & 0xFF);
        byte x3 = (byte) (reg2 & 0xFF);
        byte[] out = new byte[4];
        String bo = byteOrder == null ? "ABCD" : byteOrder.trim().toUpperCase(java.util.Locale.ROOT);
        if ("BADC".equals(bo)) {
            out[0] = x1; out[1] = x0; out[2] = x3; out[3] = x2;
        } else if ("CDAB".equals(bo)) {
            out[0] = x2; out[1] = x3; out[2] = x0; out[3] = x1;
        } else if ("DCBA".equals(bo)) {
            out[0] = x3; out[1] = x2; out[2] = x1; out[3] = x0;
        } else {
            out[0] = x0; out[1] = x1; out[2] = x2; out[3] = x3;
        }
        return ByteBuffer.wrap(out).order(ByteOrder.BIG_ENDIAN).getFloat();
    }

    public static int extractModbusExceptionCode(String msg) {
        if (msg == null) return -1;
        int idx = msg.lastIndexOf(':');
        if (idx < 0 || idx + 1 >= msg.length()) return -1;
        try {
            return Integer.parseInt(msg.substring(idx + 1).trim());
        } catch (Exception ignore) {
            return -1;
        }
    }
}
