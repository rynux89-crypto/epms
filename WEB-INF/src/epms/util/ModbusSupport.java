package epms.util;

import java.io.BufferedReader;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.servlet.http.HttpServletRequest;

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
            if (txId > 0x7FFF) {
                txId = 1;
            }
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
            if (n < 0) {
                throw new EOFException("PLC response ended unexpectedly.");
            }
            off += n;
        }
        return buf;
    }

    public static int toU16(byte hi, byte lo) {
        return ((hi & 0xFF) << 8) | (lo & 0xFF);
    }

    public static int toModbusOffset(int startAddress) {
        if (startAddress >= 40001 && startAddress <= 49999) {
            return startAddress - 40001;
        }
        if (startAddress >= 400001 && startAddress <= 499999) {
            return startAddress - 400001;
        }
        return startAddress;
    }

    public static int toModbusDiOffset(int startAddress) {
        if (startAddress >= 10001 && startAddress <= 19999) {
            return startAddress - 10001;
        }
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
            req[0] = (byte) ((txId >> 8) & 0xFF);
            req[1] = (byte) (txId & 0xFF);
            req[2] = 0;
            req[3] = 0;
            req[4] = 0;
            req[5] = 6;
            req[6] = (byte) (unitId & 0xFF);
            req[7] = 0x03;
            req[8] = (byte) ((addr >> 8) & 0xFF);
            req[9] = (byte) (addr & 0xFF);
            req[10] = (byte) ((chunk >> 8) & 0xFF);
            req[11] = (byte) (chunk & 0xFF);
            client.out().write(req);
            client.out().flush();

            byte[] mbap = readExactly(client.in(), 7);
            int len = toU16(mbap[4], mbap[5]);
            byte[] pdu = readExactly(client.in(), len - 1);
            int fn = pdu[0] & 0xFF;
            if (fn == 0x83) {
                int ex = pdu[1] & 0xFF;
                throw new IOException("Modbus exception code: " + ex);
            }
            if (fn != 0x03) {
                throw new IOException("Unexpected function code: " + fn);
            }
            int byteCount = pdu[1] & 0xFF;
            if (byteCount != chunk * 2) {
                throw new IOException("Unexpected byte count: " + byteCount);
            }
            System.arraycopy(pdu, 2, result, readRegs * 2, byteCount);
            readRegs += chunk;
        }
        return result;
    }

    public static boolean[] readDiscreteInputs(ModbusTcpClient client, int unitId, int startAddressOffset, int bitCount) throws IOException {
        boolean[] result = new boolean[bitCount];
        int readBits = 0;
        while (readBits < bitCount) {
            int chunk = Math.min(1800, bitCount - readBits);
            int addr = startAddressOffset + readBits;
            int txId = client.nextTxId();

            byte[] req = new byte[12];
            req[0] = (byte) ((txId >> 8) & 0xFF);
            req[1] = (byte) (txId & 0xFF);
            req[2] = 0;
            req[3] = 0;
            req[4] = 0;
            req[5] = 6;
            req[6] = (byte) (unitId & 0xFF);
            req[7] = 0x02;
            req[8] = (byte) ((addr >> 8) & 0xFF);
            req[9] = (byte) (addr & 0xFF);
            req[10] = (byte) ((chunk >> 8) & 0xFF);
            req[11] = (byte) (chunk & 0xFF);
            client.out().write(req);
            client.out().flush();

            byte[] mbap = readExactly(client.in(), 7);
            int len = toU16(mbap[4], mbap[5]);
            byte[] pdu = readExactly(client.in(), len - 1);
            int fn = pdu[0] & 0xFF;
            if (fn == 0x82) {
                int ex = pdu[1] & 0xFF;
                throw new IOException("Modbus DI exception code: " + ex);
            }
            if (fn != 0x02) {
                throw new IOException("Unexpected DI function code: " + fn);
            }
            int byteCount = pdu[1] & 0xFF;

            for (int i = 0; i < chunk; i++) {
                int byteIndex = 2 + (i / 8);
                if (byteIndex >= 2 + byteCount) {
                    break;
                }
                int bitMask = 1 << (i % 8);
                result[readBits + i] = (pdu[byteIndex] & bitMask) != 0;
            }
            readBits += chunk;
        }
        return result;
    }

    public static String clipForLog(String s, int maxLen) {
        if (s == null) {
            return "-";
        }
        String cleaned = s.replace('\r', ' ').replace('\n', ' ').replace('\t', ' ');
        if (cleaned.length() <= maxLen) {
            return cleaned;
        }
        return cleaned.substring(0, Math.max(0, maxLen)) + "...";
    }

    public static String b64url(String s) {
        if (s == null) {
            s = "";
        }
        return Base64.getUrlEncoder().withoutPadding().encodeToString(s.getBytes(StandardCharsets.UTF_8));
    }

    public static int parseJsonIntField(String json, String key, int def) {
        if (json == null) {
            return def;
        }
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*(-?\\d+)").matcher(json);
        if (m.find()) {
            try {
                return Integer.parseInt(m.group(1));
            } catch (Exception ignore) {
            }
        }
        return def;
    }

    public static boolean parseJsonBoolField(String json, String key, boolean def) {
        if (json == null) {
            return def;
        }
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*(true|false)").matcher(json);
        if (m.find()) {
            return "true".equalsIgnoreCase(m.group(1));
        }
        return def;
    }

    public static String resolveAlarmApiUrl(HttpServletRequest req) {
        String env = EpmsWebUtil.trimToNull(System.getenv("EPMS_ALARM_API_URL"));
        if (env != null) {
            return env;
        }
        if (req == null) {
            return "http://127.0.0.1:8080/epms/alarm_api.jsp";
        }
        String scheme = EpmsWebUtil.trimToNull(req.getScheme());
        String host = EpmsWebUtil.trimToNull(req.getServerName());
        String ctx = EpmsWebUtil.trimToNull(req.getContextPath());
        int port = req.getServerPort();
        if (scheme == null) {
            scheme = "http";
        }
        if (host == null) {
            host = "127.0.0.1";
        }
        if (ctx == null) {
            ctx = "";
        }
        boolean defaultPort = ("http".equalsIgnoreCase(scheme) && port == 80)
                || ("https".equalsIgnoreCase(scheme) && port == 443);
        String portPart = defaultPort ? "" : (":" + port);
        return scheme + "://" + host + portPart + ctx + "/epms/alarm_api.jsp";
    }

    public static int[] invokeAlarmApiPersist(String alarmApiUrl, String actionName, String body) throws Exception {
        HttpURLConnection con = null;
        try {
            URL u = new URL(alarmApiUrl);
            con = (HttpURLConnection) u.openConnection();
            con.setRequestMethod("POST");
            con.setConnectTimeout(3000);
            con.setReadTimeout(6000);
            con.setDoOutput(true);
            con.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            try (OutputStream os = con.getOutputStream()) {
                os.write(bytes);
            }

            int code = con.getResponseCode();
            InputStream is = (code >= 200 && code < 300) ? con.getInputStream() : con.getErrorStream();
            StringBuilder sb = new StringBuilder();
            if (is != null) {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        sb.append(line);
                    }
                }
            }
            String json = sb.toString();
            boolean ok = parseJsonBoolField(json, "ok", false);
            if (!ok) {
                throw new Exception("alarm_api " + actionName + " failed: " + json);
            }
            int opened = parseJsonIntField(json, "opened", 0);
            int closed = parseJsonIntField(json, "closed", 0);
            return new int[]{opened, closed};
        } finally {
            if (con != null) {
                con.disconnect();
            }
        }
    }
}
