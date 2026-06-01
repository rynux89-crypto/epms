package epms.util;

import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;

public final class ModbusSupport {
    public static final class ModbusTcpClient implements AutoCloseable {
        private final Socket socket;
        private final InputStream in;
        private final OutputStream out;
        private int txId = 1;

        public ModbusTcpClient(String ip, int port) throws IOException {
            socket = new Socket();
            socket.connect(new InetSocketAddress(ip, port), 3000);
            socket.setSoTimeout(4000);
            in = socket.getInputStream();
            out = socket.getOutputStream();
        }

        public int nextTxId() {
            int cur = txId++;
            if (txId > 0x7FFF) txId = 1;
            return cur;
        }

        public InputStream in() {
            return in;
        }

        public OutputStream out() {
            return out;
        }

        @Override
        public void close() {
            try {
                socket.close();
            } catch (Exception ignore) {
            }
        }
    }

    private ModbusSupport() {
    }

    public static byte[] readExactly(InputStream in, int len) throws IOException {
        byte[] buf = new byte[len];
        int off = 0;
        while (off < len) {
            int n = in.read(buf, off, len - off);
            if (n < 0) throw new EOFException("Modbus response ended unexpectedly.");
            off += n;
        }
        return buf;
    }

    public static int toU16(byte hi, byte lo) {
        return ((hi & 0xFF) << 8) | (lo & 0xFF);
    }

    public static int toModbusOffset(int startAddress) {
        if (startAddress >= 40001 && startAddress <= 49999) return startAddress - 40001;
        if (startAddress >= 400001 && startAddress <= 499999) return startAddress - 400001;
        return startAddress;
    }

    public static byte[] readHoldingRegisters(ModbusTcpClient client, int unitId, int startAddressOffset, int registerCount) throws IOException {
        byte[] result = new byte[registerCount * 2];
        int readRegs = 0;
        while (readRegs < registerCount) {
            int chunk = Math.min(120, registerCount - readRegs);
            int addr = startAddressOffset + readRegs;
            int txId = client.nextTxId();

            byte[] req = new byte[12];
            req[0] = (byte)((txId >> 8) & 0xFF);
            req[1] = (byte)(txId & 0xFF);
            req[2] = 0;
            req[3] = 0;
            req[4] = 0;
            req[5] = 6;
            req[6] = (byte)(unitId & 0xFF);
            req[7] = 0x03;
            req[8] = (byte)((addr >> 8) & 0xFF);
            req[9] = (byte)(addr & 0xFF);
            req[10] = (byte)((chunk >> 8) & 0xFF);
            req[11] = (byte)(chunk & 0xFF);
            client.out().write(req);
            client.out().flush();

            byte[] mbap = readExactly(client.in(), 7);
            int len = toU16(mbap[4], mbap[5]);
            byte[] pdu = readExactly(client.in(), len - 1);
            int fn = pdu[0] & 0xFF;
            if (fn == 0x83) throw new IOException("Modbus exception code: " + (pdu[1] & 0xFF));
            if (fn != 0x03) throw new IOException("Unexpected function code: " + fn);
            int byteCount = pdu[1] & 0xFF;
            if (byteCount != chunk * 2) throw new IOException("Unexpected byte count: " + byteCount);
            System.arraycopy(pdu, 2, result, readRegs * 2, byteCount);
            readRegs += chunk;
        }
        return result;
    }
}
