<%@ page contentType="application/json;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.util.concurrent.*" %>
<%@ page import="java.util.concurrent.atomic.*" %>
<%@ page import="java.net.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.lang.reflect.*" %>
<%@ page import="javax.servlet.ServletContext" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%!
    private static final int DI_POLLING_MS = 1000;
    private static final String POLL_RUNTIME_ATTR = "EPMS_MODBUS_POLL_RUNTIME";
    private static final ConcurrentHashMap<Integer, CacheEntry<PlcConfig>> PLC_CONFIG_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Integer, CacheEntry<List<Map<String, Object>>>> AI_MAP_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Integer, CacheEntry<List<Map<String, Object>>>> DI_MAP_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<Integer, CacheEntry<List<Map<String, Object>>>> DI_TAG_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, CacheEntry<Map<String, Map<String, Object>>>> AI_MEAS_MATCH_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Integer> LAST_DI_VALUE_MAP = new ConcurrentHashMap<>();
    private static final String ALARM_API_URL = "http://127.0.0.1:8080/epms/alarm_api.jsp";
    private static final long CACHE_TTL_MS = 30_000L;

    private static class CacheEntry<T> {
        final T data;
        final long loadedAtMs;
        CacheEntry(T data) {
            this.data = data;
            this.loadedAtMs = System.currentTimeMillis();
        }
    }

    private static boolean isCacheValid(CacheEntry<?> ce, long ttlMs) {
        return ce != null && (ttlMs <= 0L || (System.currentTimeMillis() - ce.loadedAtMs) < ttlMs);
    }

    private static class PollState {
        final AtomicLong attemptCount = new AtomicLong(0);
        final AtomicLong successCount = new AtomicLong(0);
        final AtomicLong readCount = new AtomicLong(0);
        final AtomicLong diReadCount = new AtomicLong(0);
        final AtomicLong aiReadCount = new AtomicLong(0);
        final AtomicLong readDurationSumMs = new AtomicLong(0);
        final AtomicBoolean aiInProgress = new AtomicBoolean(false);
        final AtomicBoolean diInProgress = new AtomicBoolean(false);
        volatile long lastReadDurationMs = 0L;
        volatile long lastDiReadMs = 0L;
        volatile long lastAiReadMs = 0L;
        volatile long lastProcMs = 0L;
        volatile List<Map<String, Object>> lastRows = Collections.emptyList();
        volatile List<Map<String, Object>> lastDiRows = Collections.emptyList();
        volatile boolean running = false;
        volatile int pollingMs = 1000;
        volatile String lastInfo = "";
        volatile String lastError = "";
        volatile long lastRunAt = 0L;
    }

    private static class PollRuntime {
        final ScheduledExecutorService exec;
        final ConcurrentHashMap<Integer, ScheduledFuture<?>> aiTasks = new ConcurrentHashMap<>();
        final ConcurrentHashMap<Integer, ScheduledFuture<?>> diTasks = new ConcurrentHashMap<>();
        final ConcurrentHashMap<Integer, PollState> states = new ConcurrentHashMap<>();

        PollRuntime() {
            ThreadFactory tf = new ThreadFactory() {
                private final AtomicInteger seq = new AtomicInteger(1);
                @Override
                public Thread newThread(Runnable r) {
                    Thread t = new Thread(r, "epms-modbus-poll-" + seq.getAndIncrement());
                    t.setDaemon(true);
                    return t;
                }
            };
            this.exec = Executors.newScheduledThreadPool(4, tf);
        }
    }

    private static PollRuntime getPollRuntime(ServletContext app) {
        synchronized (app) {
            Object cur = app.getAttribute(POLL_RUNTIME_ATTR);
            if (cur instanceof PollRuntime) return (PollRuntime)cur;
            if (cur != null) shutdownLegacyPollRuntime(cur);
            PollRuntime created = new PollRuntime();
            app.setAttribute(POLL_RUNTIME_ATTR, created);
            return created;
        }
    }

    private static void shutdownLegacyPollRuntime(Object legacy) {
        if (legacy == null) return;
        try {
            Field aiF = legacy.getClass().getDeclaredField("aiTasks");
            Field diF = legacy.getClass().getDeclaredField("diTasks");
            Field execF = legacy.getClass().getDeclaredField("exec");
            aiF.setAccessible(true);
            diF.setAccessible(true);
            execF.setAccessible(true);

            Object aiObj = aiF.get(legacy);
            Object diObj = diF.get(legacy);
            Object execObj = execF.get(legacy);

            cancelFutureMap(aiObj);
            cancelFutureMap(diObj);
            if (execObj instanceof ScheduledExecutorService) {
                ((ScheduledExecutorService)execObj).shutdownNow();
            }
        } catch (Exception ignore) {
            // Legacy runtime shape may differ; best-effort shutdown only.
        }
    }

    private static void cancelFutureMap(Object mapObj) {
        if (!(mapObj instanceof Map)) return;
        for (Object v : ((Map<?, ?>)mapObj).values()) {
            if (v instanceof Future) {
                try { ((Future<?>)v).cancel(false); } catch (Exception ignore) {}
            }
        }
    }

    private static class PlcConfig {
        boolean exists = false;
        boolean enabled = false;
        int pollingMs = 1000;
        String ip = null;
        int port = 502;
        int unitId = 1;
    }

    private static class PlcReadResult {
        boolean ok = false;
        String info = "";
        String error = "";
        long totalMs = 0L;
        long diMs = 0L;
        long aiMs = 0L;
        long procMs = 0L;
        int measurementsInserted = 0;
        int harmonicInserted = 0;
        int flickerInserted = 0;
        int deviceEventsOpened = 0;
        int deviceEventsClosed = 0;
        int aiAlarmOpened = 0;
        int aiAlarmClosed = 0;
        List<Map<String, Object>> rows = new ArrayList<>();
        List<Map<String, Object>> diRows = new ArrayList<>();
    }

    private static class AiRange {
        final int startReg;
        int endReg;
        byte[] regs;
        AiRange(int startReg, int endReg) {
            this.startReg = startReg;
            this.endReg = endReg;
        }
    }

    private static class DiReadData {
        final List<Map<String, Object>> rows;
        final long durationMs;
        DiReadData(List<Map<String, Object>> rows, long durationMs) {
            this.rows = rows;
            this.durationMs = durationMs;
        }
    }

    private static class AiReadData {
        final List<Map<String, Object>> rows;
        final int meterRead;
        final int totalFloat;
        final long durationMs;
        AiReadData(List<Map<String, Object>> rows, int meterRead, int totalFloat, long durationMs) {
            this.rows = rows;
            this.meterRead = meterRead;
            this.totalFloat = totalFloat;
            this.durationMs = durationMs;
        }
    }

    private static Connection createConn() throws Exception {
        return openDbConnection();
    }

    private static PollState getPollState(PollRuntime rt, int plcId) {
        return rt.states.computeIfAbsent(plcId, k -> new PollState());
    }

    private static byte[] readExactly(InputStream in, int len) throws IOException {
        byte[] buf = new byte[len];
        int off = 0;
        while (off < len) {
            int n = in.read(buf, off, len - off);
            if (n < 0) throw new EOFException("PLC response ended unexpectedly.");
            off += n;
        }
        return buf;
    }

    private static int toU16(byte hi, byte lo) {
        return ((hi & 0xFF) << 8) | (lo & 0xFF);
    }

    private static int toPlcBitIndex(int configuredBitNo) {
        // Prefer explicit 0-based configuration (0..15). Fallback to 1-based (1..16) when needed.
        if (configuredBitNo >= 0 && configuredBitNo <= 15) return configuredBitNo;
        if (configuredBitNo >= 1 && configuredBitNo <= 16) return configuredBitNo - 1;
        return configuredBitNo;
    }

    private static boolean isOcrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        // OCGR/51G는 OCR 집계에서 제외
        if (t.contains("OCGR") || t.contains("51G") || t.contains("지락")) return false;
        // OCR 명시 태그
        if (t.contains("OCR")) return true;
        // 과전류(50/51) 계전 태그
        if (t.contains("과전류")) return true;
        if (t.contains("\\50") || t.contains("₩50")) return true;
        if (t.contains("\\51") || t.contains("₩51")) return true;
        return false;
    }

    private static boolean isOcgrAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("OCGR")) return true;
        if (t.contains("51G")) return true;
        if (t.contains("지락")) return true;
        return false;
    }

    private static boolean isTripAlarmBit(String tagName) {
        if (tagName == null) return false;
        String t = tagName.toUpperCase(Locale.ROOT).replace(" ", "").replace("\n", "").replace("\r", "");
        if (t.contains("TR_ALARM")) return true;
        if (t.contains("TRALARM")) return true;
        if (t.contains("TRIP")) return true;
        return false;
    }

    private static String normalizeTagKey(String tagName) {
        if (tagName == null) return "";
        String t = tagName.trim().toUpperCase(Locale.ROOT);
        if (t.isEmpty()) return "";
        t = t.replaceAll("[^A-Z0-9]+", "_");
        t = t.replaceAll("_+", "_");
        t = t.replaceAll("^_+|_+$", "");
        if (t.length() > 64) t = t.substring(0, 64);
        return t;
    }

    private static String compactEventToken(String normalizedTagKey, String... dropTokens) {
        if (normalizedTagKey == null || normalizedTagKey.isEmpty()) return "";
        Set<String> drop = new HashSet<>();
        if (dropTokens != null) {
            for (String d : dropTokens) {
                if (d == null) continue;
                String x = d.trim().toUpperCase(Locale.ROOT);
                if (!x.isEmpty()) drop.add(x);
            }
        }
        LinkedHashSet<String> uniq = new LinkedHashSet<>();
        String[] parts = normalizedTagKey.split("_+");
        for (String p : parts) {
            if (p == null) continue;
            String x = p.trim().toUpperCase(Locale.ROOT);
            if (x.isEmpty()) continue;
            if (drop.contains(x)) continue;
            uniq.add(x);
        }
        if (uniq.isEmpty()) return "";
        return String.join("_", uniq);
    }

    private static String buildDiEventType(int diAddress, int bitNo, String tagName) {
        String tagKey = normalizeTagKey(tagName);
        if (isTripAlarmBit(tagName)) {
            String suffix = compactEventToken(tagKey, "DI", "TRIP", "TR", "ALARM");
            if ("TM".equals(suffix)) return "DI_TR_ALARM";
            return suffix.isEmpty() ? "DI_TRIP" : ("DI_TRIP_" + suffix);
        }
        if (isOcrAlarmBit(tagName)) {
            String suffix = compactEventToken(tagKey, "DI", "OCR");
            return suffix.isEmpty() ? "DI_OCR" : ("DI_OCR_" + suffix);
        }
        if (isOcgrAlarmBit(tagName)) {
            String suffix = compactEventToken(tagKey, "DI", "OCGR");
            return suffix.isEmpty() ? "DI_OCGR" : ("DI_OCGR_" + suffix);
        }
        if (tagKey.contains("ELD")) {
            String suffix = compactEventToken(tagKey, "DI", "ELD");
            if (suffix.matches("\\d+")) return "DI_ELD";
        }
        if (!tagKey.isEmpty()) {
            String suffix = compactEventToken(tagKey, "DI", "TAG");
            if ("ON1_OFF1_ST1".equals(suffix) || "ON2_OFF2_ST2".equals(suffix)) return "DI_ON_OFF";
            return suffix.isEmpty() ? "DI_TAG" : ("DI_TAG_" + suffix);
        }
        return "DI_BIT_" + bitNo;
    }

    private static class ModbusTcpClient implements AutoCloseable {
        private final Socket socket;
        private final InputStream in;
        private final OutputStream out;
        private int txId = 1;

        ModbusTcpClient(String ip, int port) throws IOException {
            socket = new Socket();
            socket.connect(new InetSocketAddress(ip, port), 3000);
            socket.setSoTimeout(4000);
            in = socket.getInputStream();
            out = socket.getOutputStream();
        }

        int nextTxId() {
            int cur = txId++;
            if (txId > 0x7FFF) txId = 1;
            return cur;
        }

        InputStream in() { return in; }
        OutputStream out() { return out; }

        @Override
        public void close() {
            try { socket.close(); } catch (Exception ignore) {}
        }
    }

    private static float decodeFloatFrom2Regs(byte a, byte b, byte c, byte d, String byteOrder) {
        byte[] x = new byte[4];
        String bo = (byteOrder == null) ? "ABCD" : byteOrder.trim().toUpperCase(Locale.ROOT);
        if ("BADC".equals(bo)) {
            x[0] = b; x[1] = a; x[2] = d; x[3] = c;
        } else if ("CDAB".equals(bo)) {
            x[0] = c; x[1] = d; x[2] = a; x[3] = b;
        } else if ("DCBA".equals(bo)) {
            x[0] = d; x[1] = c; x[2] = b; x[3] = a;
        } else {
            x[0] = a; x[1] = b; x[2] = c; x[3] = d;
        }
        int bits = ((x[0] & 0xFF) << 24) | ((x[1] & 0xFF) << 16) | ((x[2] & 0xFF) << 8) | (x[3] & 0xFF);
        return Float.intBitsToFloat(bits);
    }

    private static int toModbusOffset(int startAddress) {
        if (startAddress >= 40001 && startAddress <= 49999) return startAddress - 40001;
        if (startAddress >= 400001 && startAddress <= 499999) return startAddress - 400001;
        return startAddress;
    }

    private static int toModbusDiOffset(int startAddress) {
        if (startAddress >= 10001 && startAddress <= 19999) return startAddress - 10001;
        return startAddress;
    }

    private static byte[] readHoldingRegisters(ModbusTcpClient client, int unitId, int startAddressOffset, int registerCount) throws IOException {
        byte[] result = new byte[registerCount * 2];
        int readRegs = 0;
        while (readRegs < registerCount) {
            int chunk = Math.min(120, registerCount - readRegs);
            int addr = startAddressOffset + readRegs;
            int txId = client.nextTxId();

            byte[] req = new byte[12];
            req[0] = (byte)((txId >> 8) & 0xFF);
            req[1] = (byte)(txId & 0xFF);
            req[2] = 0; req[3] = 0;
            req[4] = 0; req[5] = 6;
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
            if (fn == 0x83) {
                int ex = pdu[1] & 0xFF;
                throw new IOException("Modbus exception code: " + ex);
            }
            if (fn != 0x03) throw new IOException("Unexpected function code: " + fn);
            int byteCount = pdu[1] & 0xFF;
            if (byteCount != chunk * 2) throw new IOException("Unexpected byte count: " + byteCount);
            System.arraycopy(pdu, 2, result, readRegs * 2, byteCount);
            readRegs += chunk;
        }
        return result;
    }

    private static boolean[] readDiscreteInputs(ModbusTcpClient client, int unitId, int startAddressOffset, int bitCount) throws IOException {
        boolean[] result = new boolean[bitCount];
        int readBits = 0;
        while (readBits < bitCount) {
            int chunk = Math.min(1800, bitCount - readBits);
            int addr = startAddressOffset + readBits;
            int txId = client.nextTxId();

            byte[] req = new byte[12];
            req[0] = (byte)((txId >> 8) & 0xFF);
            req[1] = (byte)(txId & 0xFF);
            req[2] = 0; req[3] = 0;
            req[4] = 0; req[5] = 6;
            req[6] = (byte)(unitId & 0xFF);
            req[7] = 0x02;
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
            if (fn == 0x82) {
                int ex = pdu[1] & 0xFF;
                throw new IOException("Modbus DI exception code: " + ex);
            }
            if (fn != 0x02) throw new IOException("Unexpected DI function code: " + fn);
            int byteCount = pdu[1] & 0xFF;

            for (int i = 0; i < chunk; i++) {
                int byteIndex = 2 + (i / 8);
                if (byteIndex >= 2 + byteCount) break;
                int bitMask = 1 << (i % 8);
                result[readBits + i] = (pdu[byteIndex] & bitMask) != 0;
            }
            readBits += chunk;
        }
        return result;
    }

    private static String escJson(String s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"' || c == '\\') b.append('\\').append(c);
            else if (c == '\n') b.append("\\n");
            else if (c == '\r') b.append("\\r");
            else if (c == '\t') b.append("\\t");
            else b.append(c);
        }
        return b.toString();
    }

    private static String clipForLog(String s, int maxLen) {
        if (s == null) return "-";
        String cleaned = s.replace('\r', ' ').replace('\n', ' ').replace('\t', ' ');
        if (cleaned.length() <= maxLen) return cleaned;
        return cleaned.substring(0, Math.max(0, maxLen)) + "...";
    }

    private static String b64url(String s) {
        if (s == null) s = "";
        return Base64.getUrlEncoder().withoutPadding().encodeToString(s.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private static int parseJsonIntField(String json, String key, int def) {
        if (json == null) return def;
        String pat = "\"" + key + "\"\\s*:\\s*(-?\\d+)";
        java.util.regex.Matcher m = java.util.regex.Pattern.compile(pat).matcher(json);
        if (m.find()) {
            try { return Integer.parseInt(m.group(1)); } catch (Exception ignore) {}
        }
        return def;
    }

    private static boolean parseJsonBoolField(String json, String key, boolean def) {
        if (json == null) return def;
        String pat = "\"" + key + "\"\\s*:\\s*(true|false)";
        java.util.regex.Matcher m = java.util.regex.Pattern.compile(pat).matcher(json);
        if (m.find()) return "true".equalsIgnoreCase(m.group(1));
        return def;
    }

    private static int[] persistDiRowsViaAlarmApi(int plcId, List<Map<String, Object>> diRows, Timestamp measuredAt) throws Exception {
        if (diRows == null || diRows.isEmpty()) return new int[]{0, 0};

        StringBuilder rows = new StringBuilder();
        for (Map<String, Object> r : diRows) {
            if (rows.length() > 0) rows.append(';');
            int pointId = ((Number)r.get("point_id")).intValue();
            int diAddress = ((Number)r.get("di_address")).intValue();
            int bitNo = ((Number)r.get("bit_no")).intValue();
            int value = ((Number)r.get("value")).intValue();
            String tagName = String.valueOf(r.get("tag_name") == null ? "" : r.get("tag_name"));
            String itemName = String.valueOf(r.get("item_name") == null ? "" : r.get("item_name"));
            String panelName = String.valueOf(r.get("panel_name") == null ? "" : r.get("panel_name"));
            rows.append(pointId).append('|')
                .append(diAddress).append('|')
                .append(bitNo).append('|')
                .append(value).append('|')
                .append(b64url(tagName)).append('|')
                .append(b64url(itemName)).append('|')
                .append(b64url(panelName));
        }

        String body = "action=process_di" +
                "&plc_id=" + plcId +
                "&measured_at_ms=" + measuredAt.getTime() +
                "&rows=" + URLEncoder.encode(rows.toString(), "UTF-8");

        HttpURLConnection con = null;
        try {
            URL u = new URL(ALARM_API_URL);
            con = (HttpURLConnection)u.openConnection();
            con.setRequestMethod("POST");
            con.setConnectTimeout(3000);
            con.setReadTimeout(6000);
            con.setDoOutput(true);
            con.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
            byte[] bytes = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            try (OutputStream os = con.getOutputStream()) {
                os.write(bytes);
            }

            int code = con.getResponseCode();
            InputStream is = (code >= 200 && code < 300) ? con.getInputStream() : con.getErrorStream();
            StringBuilder sb = new StringBuilder();
            if (is != null) {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(is, java.nio.charset.StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = br.readLine()) != null) sb.append(line);
                }
            }
            String json = sb.toString();
            boolean ok = parseJsonBoolField(json, "ok", false);
            if (!ok) throw new Exception("alarm_api process_di failed: " + json);
            int opened = parseJsonIntField(json, "opened", 0);
            int closed = parseJsonIntField(json, "closed", 0);
            return new int[]{opened, closed};
        } finally {
            if (con != null) con.disconnect();
        }
    }

    private static int[] persistAiRowsViaAlarmApi(int plcId, List<Map<String, Object>> aiRows, Timestamp measuredAt) throws Exception {
        if (aiRows == null || aiRows.isEmpty()) return new int[]{0, 0};

        StringBuilder rows = new StringBuilder();
        for (Map<String, Object> r : aiRows) {
            Object meterObj = r.get("meter_id");
            Object tokenObj = r.get("token");
            Object valueObj = r.get("value");
            if (!(meterObj instanceof Number) || tokenObj == null || !(valueObj instanceof Number)) continue;
            int meterId = ((Number)meterObj).intValue();
            String token = String.valueOf(tokenObj);
            double value = ((Number)valueObj).doubleValue();
            if (meterId <= 0 || token.trim().isEmpty()) continue;
            // Read IR from PLC for visibility, but do not persist IR-related records.
            if ("IR".equalsIgnoreCase(token.trim())) continue;
            if (rows.length() > 0) rows.append(';');
            rows.append(meterId).append('|')
                .append(b64url(token)).append('|')
                .append(String.format(Locale.US, "%.6f", value));
        }
        if (rows.length() == 0) return new int[]{0, 0};

        String body = "action=process_ai" +
                "&plc_id=" + plcId +
                "&measured_at_ms=" + measuredAt.getTime() +
                "&rows=" + URLEncoder.encode(rows.toString(), "UTF-8");

        HttpURLConnection con = null;
        try {
            URL u = new URL(ALARM_API_URL);
            con = (HttpURLConnection)u.openConnection();
            con.setRequestMethod("POST");
            con.setConnectTimeout(3000);
            con.setReadTimeout(6000);
            con.setDoOutput(true);
            con.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
            byte[] bytes = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            try (OutputStream os = con.getOutputStream()) {
                os.write(bytes);
            }

            int code = con.getResponseCode();
            InputStream is = (code >= 200 && code < 300) ? con.getInputStream() : con.getErrorStream();
            StringBuilder sb = new StringBuilder();
            if (is != null) {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(is, java.nio.charset.StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = br.readLine()) != null) sb.append(line);
                }
            }
            String json = sb.toString();
            boolean ok = parseJsonBoolField(json, "ok", false);
            if (!ok) throw new Exception("alarm_api process_ai failed: " + json);
            int opened = parseJsonIntField(json, "opened", 0);
            int closed = parseJsonIntField(json, "closed", 0);
            return new int[]{opened, closed};
        } finally {
            if (con != null) con.disconnect();
        }
    }

    private static PlcConfig loadPlcConfig(Connection conn, int plcId) throws Exception {
        PlcConfig cfg = new PlcConfig();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config WHERE plc_id = ?")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    cfg.exists = true;
                    cfg.ip = rs.getString("plc_ip");
                    cfg.port = rs.getInt("plc_port");
                    cfg.unitId = rs.getInt("unit_id");
                    cfg.pollingMs = rs.getInt("polling_ms");
                    cfg.enabled = rs.getBoolean("enabled");
                }
            }
        }
        return cfg;
    }

    private static PlcConfig getCachedPlcConfig(int plcId) throws Exception {
        CacheEntry<PlcConfig> ce = PLC_CONFIG_CACHE.get(plcId);
        if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;

        synchronized (PLC_CONFIG_CACHE) {
            ce = PLC_CONFIG_CACHE.get(plcId);
            if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
            try (Connection conn = createConn()) {
                PlcConfig loaded = loadPlcConfig(conn, plcId);
                PLC_CONFIG_CACHE.put(plcId, new CacheEntry<>(loaded));
                return loaded;
            }
        }
    }

    private static String normalizeMetricOrder(String metricOrder) {
        if (metricOrder == null || metricOrder.trim().isEmpty()) return metricOrder;
        String[] raw = metricOrder.split("\\s*,\\s*");
        if (raw.length < 5) return metricOrder;
        List<String> toks = new ArrayList<>();
        for (String t : raw) toks.add(t == null ? "" : t.trim());
        for (int i = 0; i <= toks.size() - 5; i++) {
            String t0 = toks.get(i).toUpperCase(Locale.ROOT);
            String t1 = toks.get(i + 1).toUpperCase(Locale.ROOT);
            String t2 = toks.get(i + 2).toUpperCase(Locale.ROOT);
            String t3 = toks.get(i + 3).toUpperCase(Locale.ROOT);
            String t4 = toks.get(i + 4).toUpperCase(Locale.ROOT);
            if ("KW".equals(t0) && "KHH".equals(t1) && "VA".equals(t2) && "VAH".equals(t3) && "PEAK".equals(t4)) {
                toks.set(i + 1, "KWH");
                toks.set(i + 2, "KVAR");
                toks.set(i + 3, "KVARH");
            }
        }
        return String.join(",", toks);
    }

    private static List<Map<String, Object>> loadAiMap(Connection conn, int plcId) throws Exception {
        List<Map<String, Object>> mapList = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, start_address, float_count, byte_order, metric_order " +
                "FROM dbo.plc_meter_map WHERE plc_id = ? AND enabled = 1 ORDER BY meter_id, start_address")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> m = new HashMap<>();
                    m.put("meter_id", rs.getInt("meter_id"));
                    m.put("start_address", rs.getInt("start_address"));
                    m.put("float_count", rs.getInt("float_count"));
                    m.put("byte_order", rs.getString("byte_order"));
                    String metricOrder = normalizeMetricOrder(rs.getString("metric_order"));
                    m.put("metric_order", metricOrder);
                    m.put("tokens", (metricOrder == null) ? new String[0] : metricOrder.split("\\s*,\\s*"));
                    mapList.add(m);
                }
            }
        }
        return mapList;
    }

    private static List<Map<String, Object>> getCachedAiMap(int plcId) throws Exception {
        CacheEntry<List<Map<String, Object>>> ce = AI_MAP_CACHE.get(plcId);
        if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
        synchronized (AI_MAP_CACHE) {
            ce = AI_MAP_CACHE.get(plcId);
            if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
            try (Connection conn = createConn()) {
                List<Map<String, Object>> loaded = loadAiMap(conn, plcId);
                AI_MAP_CACHE.put(plcId, new CacheEntry<>(loaded));
                return loaded;
            }
        }
    }

    private static List<Map<String, Object>> loadDiMap(Connection conn, int plcId) throws Exception {
        List<Map<String, Object>> diMapList = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT point_id, start_address, bit_count " +
                "FROM dbo.plc_di_map WHERE plc_id = ? AND enabled = 1 ORDER BY point_id, start_address")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> d = new HashMap<>();
                    d.put("point_id", rs.getInt("point_id"));
                    d.put("start_address", rs.getInt("start_address"));
                    d.put("bit_count", rs.getInt("bit_count"));
                    diMapList.add(d);
                }
            }
        }
        return diMapList;
    }

    private static List<Map<String, Object>> getCachedDiMap(int plcId) throws Exception {
        CacheEntry<List<Map<String, Object>>> ce = DI_MAP_CACHE.get(plcId);
        if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
        synchronized (DI_MAP_CACHE) {
            ce = DI_MAP_CACHE.get(plcId);
            if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
            try (Connection conn = createConn()) {
                List<Map<String, Object>> loaded = loadDiMap(conn, plcId);
                DI_MAP_CACHE.put(plcId, new CacheEntry<>(loaded));
                return loaded;
            }
        }
    }

    private static List<Map<String, Object>> loadDiTagMap(Connection conn, int plcId) throws Exception {
        List<Map<String, Object>> diTagList = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT point_id, di_address, bit_no, tag_name, item_name, panel_name " +
                "FROM dbo.plc_di_tag_map WHERE plc_id = ? AND enabled = 1 ORDER BY point_id, di_address, bit_no")) {
            ps.setInt(1, plcId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> t = new HashMap<>();
                    t.put("point_id", rs.getInt("point_id"));
                    t.put("di_address", rs.getInt("di_address"));
                    t.put("bit_no", rs.getInt("bit_no"));
                    t.put("tag_name", rs.getString("tag_name"));
                    t.put("item_name", rs.getString("item_name"));
                    t.put("panel_name", rs.getString("panel_name"));
                    diTagList.add(t);
                }
            }
        }
        return diTagList;
    }

    private static List<Map<String, Object>> getCachedDiTagMap(int plcId) throws Exception {
        CacheEntry<List<Map<String, Object>>> ce = DI_TAG_CACHE.get(plcId);
        if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
        synchronized (DI_TAG_CACHE) {
            ce = DI_TAG_CACHE.get(plcId);
            if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
            try (Connection conn = createConn()) {
                List<Map<String, Object>> loaded = loadDiTagMap(conn, plcId);
                DI_TAG_CACHE.put(plcId, new CacheEntry<>(loaded));
                return loaded;
            }
        }
    }

    private static Map<String, Map<String, Object>> loadAiMeasurementsMatch(Connection conn) throws Exception {
        Map<String, Map<String, Object>> out = new HashMap<>();
        String sql =
            "SELECT token, measurement_column, target_table, is_supported " +
            "FROM dbo.plc_ai_measurements_match";
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                boolean supported = rs.getBoolean("is_supported");
                String col = rs.getString("measurement_column");
                if (!supported || col == null || col.trim().isEmpty()) continue;
                String token = rs.getString("token");
                if (token == null || token.trim().isEmpty()) continue;
                String target = rs.getString("target_table");
                Map<String, Object> m = new HashMap<>();
                m.put("measurement_column", col.trim());
                m.put("target_table", target == null ? "" : target.trim().toLowerCase(Locale.ROOT));
                out.put(token.trim().toUpperCase(Locale.ROOT), m);
            }
        }
        return out;
    }

    private static Map<String, Map<String, Object>> getCachedAiMeasurementsMatch() throws Exception {
        final String key = "GLOBAL";
        CacheEntry<Map<String, Map<String, Object>>> ce = AI_MEAS_MATCH_CACHE.get(key);
        if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
        synchronized (AI_MEAS_MATCH_CACHE) {
            ce = AI_MEAS_MATCH_CACHE.get(key);
            if (isCacheValid(ce, CACHE_TTL_MS)) return ce.data;
            try (Connection conn = createConn()) {
                Map<String, Map<String, Object>> loaded = loadAiMeasurementsMatch(conn);
                AI_MEAS_MATCH_CACHE.put(key, new CacheEntry<>(loaded));
                return loaded;
            }
        }
    }

    private static int insertRowDynamic(Connection conn, String tableName, int meterId, Timestamp measuredAt, Map<String, Double> valueByColumn) throws Exception {
        if (valueByColumn == null || valueByColumn.isEmpty()) return 0;
        List<String> cols = new ArrayList<>();
        for (String col : valueByColumn.keySet()) {
            if (col == null) continue;
            String c = col.trim();
            if (c.matches("^[A-Za-z_][A-Za-z0-9_]*$")) cols.add(c);
        }
        if (cols.isEmpty()) return 0;
        Collections.sort(cols);

        StringBuilder sql = new StringBuilder();
        sql.append("INSERT INTO dbo.").append(tableName).append(" (meter_id, measured_at");
        for (String c : cols) sql.append(", ").append(c);
        sql.append(") VALUES (?, ?");
        for (int i = 0; i < cols.size(); i++) sql.append(", ?");
        sql.append(")");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            ps.setInt(idx++, meterId);
            ps.setTimestamp(idx++, measuredAt);
            for (String c : cols) {
                Double v = valueByColumn.get(c);
                if (v == null) ps.setNull(idx++, Types.DOUBLE);
                else ps.setDouble(idx++, v);
            }
            return ps.executeUpdate();
        }
    }

    private static void openAlarmLogIfNeeded(Connection conn, int meterId, String alarmType, String severity, Timestamp triggeredAt, String description) throws Exception {
        String selSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        try (PreparedStatement sel = conn.prepareStatement(selSql)) {
            sel.setInt(1, meterId);
            sel.setString(2, alarmType);
            try (ResultSet rs = sel.executeQuery()) {
                if (rs.next()) return;
            }
        }
        String insSql =
            "INSERT INTO dbo.alarm_log (meter_id, alarm_type, severity, triggered_at, description) " +
            "VALUES (?, ?, ?, ?, ?)";
        try (PreparedStatement ins = conn.prepareStatement(insSql)) {
            ins.setInt(1, meterId);
            ins.setString(2, alarmType);
            ins.setString(3, severity);
            ins.setTimestamp(4, triggeredAt);
            ins.setString(5, description);
            ins.executeUpdate();
        }
    }

    private static void closeAlarmLogIfOpen(Connection conn, int meterId, String alarmType, Timestamp clearedAt) throws Exception {
        String selSql =
            "SELECT TOP 1 alarm_id FROM dbo.alarm_log " +
            "WHERE meter_id = ? AND alarm_type = ? AND cleared_at IS NULL " +
            "ORDER BY alarm_id DESC";
        Long alarmId = null;
        try (PreparedStatement sel = conn.prepareStatement(selSql)) {
            sel.setInt(1, meterId);
            sel.setString(2, alarmType);
            try (ResultSet rs = sel.executeQuery()) {
                if (rs.next()) alarmId = rs.getLong(1);
            }
        }
        if (alarmId == null) return;
        try (PreparedStatement upd = conn.prepareStatement("UPDATE dbo.alarm_log SET cleared_at = ? WHERE alarm_id = ?")) {
            upd.setTimestamp(1, clearedAt);
            upd.setLong(2, alarmId.longValue());
            upd.executeUpdate();
        }
    }

    private static int[] persistAiRowsToTargetTables(List<Map<String, Object>> aiRows, Timestamp measuredAt) throws Exception {
        int measurementsInserted = 0;
        int harmonicInserted = 0;
        int flickerInserted = 0;
        if (aiRows == null || aiRows.isEmpty()) return new int[]{0, 0, 0};

        Map<String, Map<String, Object>> matchMap = getCachedAiMeasurementsMatch();
        Map<Integer, Map<String, Double>> measurementsByMeter = new HashMap<>();
        Map<Integer, Map<String, Double>> harmonicByMeter = new HashMap<>();
        Map<Integer, Map<String, Double>> flickerByMeter = new HashMap<>();

        for (Map<String, Object> row : aiRows) {
            Object meterObj = row.get("meter_id");
            Object tokenObj = row.get("token");
            Object valueObj = row.get("value");
            if (!(meterObj instanceof Number) || tokenObj == null || !(valueObj instanceof Number)) continue;

            int meterId = ((Number)meterObj).intValue();
            String token = String.valueOf(tokenObj).trim().toUpperCase(Locale.ROOT);
            int floatIndex = 0;
            Object floatIndexObj = row.get("float_index");
            if (floatIndexObj instanceof Number) {
                floatIndex = ((Number)floatIndexObj).intValue();
            }
            if ("KHH".equals(token)) token = "KWH";
            else if ("VAH".equals(token)) token = "KVARH";
            else if ("VA".equals(token) && floatIndex >= 18) token = "KVAR";
            if ("IR".equals(token)) continue;
            Map<String, Object> mm = matchMap.get(token);
            if (mm == null) continue;

            String col = (String)mm.get("measurement_column");
            String target = (String)mm.get("target_table");
            if (col == null || col.isEmpty()) continue;
            String colNorm = col.trim().toUpperCase(Locale.ROOT);
            if ("IR".equals(colNorm) || colNorm.endsWith("_IR") || colNorm.contains("INSULATION")) continue;
            double value = ((Number)valueObj).doubleValue();

            if ("measurements".equals(target)) {
                Map<String, Double> m = measurementsByMeter.computeIfAbsent(meterId, k -> new HashMap<>());
                m.put(col, value);
            } else if ("harmonic_measurements".equals(target)) {
                Map<String, Double> m = harmonicByMeter.computeIfAbsent(meterId, k -> new HashMap<>());
                m.put(col, value);
            } else if ("flicker_measurements".equals(target)) {
                Map<String, Double> m = flickerByMeter.computeIfAbsent(meterId, k -> new HashMap<>());
                m.put(col, value);
            }
        }

        try (Connection conn = createConn()) {
            for (Map.Entry<Integer, Map<String, Double>> e : measurementsByMeter.entrySet()) {
                measurementsInserted += insertRowDynamic(conn, "measurements", e.getKey(), measuredAt, e.getValue());
            }
            for (Map.Entry<Integer, Map<String, Double>> e : harmonicByMeter.entrySet()) {
                harmonicInserted += insertRowDynamic(conn, "harmonic_measurements", e.getKey(), measuredAt, e.getValue());
            }
            for (Map.Entry<Integer, Map<String, Double>> e : flickerByMeter.entrySet()) {
                flickerInserted += insertRowDynamic(conn, "flicker_measurements", e.getKey(), measuredAt, e.getValue());
            }
        }
        return new int[]{measurementsInserted, harmonicInserted, flickerInserted};
    }

    private static int[] persistDiRowsToDeviceEvents(int plcId, List<Map<String, Object>> diRows, Timestamp measuredAt) throws Exception {
        int opened = 0;
        int closed = 0;
        if (diRows == null || diRows.isEmpty()) return new int[]{0, 0};

        String selOpenSql =
            "SELECT TOP 1 event_id FROM dbo.device_events " +
            "WHERE device_id = ? AND event_type = ? AND restored_time IS NULL " +
            "ORDER BY event_id DESC";
        String insSql =
            "INSERT INTO dbo.device_events (device_id, event_type, event_time, severity, description) " +
            "VALUES (?, ?, ?, ?, ?)";
        String closeSql =
            "UPDATE dbo.device_events " +
            "SET restored_time = ?, duration_seconds = DATEDIFF(SECOND, event_time, ?), " +
            "    downtime_minutes = DATEDIFF(SECOND, event_time, ?) / 60.0 " +
            "WHERE event_id = ?";

        try (Connection conn = createConn();
             PreparedStatement selOpen = conn.prepareStatement(selOpenSql);
             PreparedStatement ins = conn.prepareStatement(insSql);
             PreparedStatement close = conn.prepareStatement(closeSql)) {
            Map<String, Map<String, Object>> ocrGroups = new LinkedHashMap<>();
            Map<String, Map<String, Object>> ocgrGroups = new LinkedHashMap<>();
            for (Map<String, Object> row : diRows) {
                int pointId = ((Number)row.get("point_id")).intValue();
                int diAddress = ((Number)row.get("di_address")).intValue();
                int bitNo = ((Number)row.get("bit_no")).intValue();
                int value = ((Number)row.get("value")).intValue();
                String tagName = String.valueOf(row.get("tag_name") == null ? "" : row.get("tag_name"));
                String itemName = String.valueOf(row.get("item_name") == null ? "" : row.get("item_name"));
                String panelName = String.valueOf(row.get("panel_name") == null ? "" : row.get("panel_name"));

                // OCR 관련 bit는 "개별 bit 이벤트" 대신 "OCR bit 전체 ON" 집계 이벤트로 처리
                if (isOcrAlarmBit(tagName)) {
                    String gk = pointId + ":" + diAddress;
                    Map<String, Object> g = ocrGroups.get(gk);
                    if (g == null) {
                        g = new HashMap<>();
                        g.put("point_id", pointId);
                        g.put("di_address", diAddress);
                        g.put("item_name", itemName);
                        g.put("panel_name", panelName);
                        g.put("tag_name", tagName);
                        g.put("bit_count", 0);
                        g.put("on_count", 0);
                        g.put("bit_values", new ArrayList<String>());
                        ocrGroups.put(gk, g);
                    }
                    g.put("bit_count", ((Integer)g.get("bit_count")) + 1);
                    if (value == 1) g.put("on_count", ((Integer)g.get("on_count")) + 1);
                    @SuppressWarnings("unchecked")
                    List<String> bitValues = (List<String>)g.get("bit_values");
                    bitValues.add(bitNo + ":" + value);
                    LAST_DI_VALUE_MAP.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, value);
                    continue;
                }
                if (isOcgrAlarmBit(tagName)) {
                    String gk = pointId + ":" + diAddress;
                    Map<String, Object> g = ocgrGroups.get(gk);
                    if (g == null) {
                        g = new HashMap<>();
                        g.put("point_id", pointId);
                        g.put("di_address", diAddress);
                        g.put("item_name", itemName);
                        g.put("panel_name", panelName);
                        g.put("tag_name", tagName);
                        g.put("bit_count", 0);
                        g.put("on_count", 0);
                        g.put("bit_values", new ArrayList<String>());
                        ocgrGroups.put(gk, g);
                    }
                    g.put("bit_count", ((Integer)g.get("bit_count")) + 1);
                    if (value == 1) g.put("on_count", ((Integer)g.get("on_count")) + 1);
                    @SuppressWarnings("unchecked")
                    List<String> bitValues = (List<String>)g.get("bit_values");
                    bitValues.add(bitNo + ":" + value);
                    LAST_DI_VALUE_MAP.put(plcId + ":" + pointId + ":" + diAddress + ":" + bitNo, value);
                    continue;
                }

                int deviceId = pointId;
                String eventType = buildDiEventType(diAddress, bitNo, tagName);
                String diKey = plcId + ":" + pointId + ":" + diAddress + ":" + bitNo;
                Integer prev = LAST_DI_VALUE_MAP.get(diKey);

                // 최초 관측에서 값이 1이면 즉시 open 이벤트를 생성한다.
                if (prev == null) {
                    if (value == 1) {
                        selOpen.setInt(1, deviceId);
                        selOpen.setString(2, eventType);
                        Long openEventId = null;
                        try (ResultSet rs = selOpen.executeQuery()) {
                            if (rs.next()) openEventId = rs.getLong(1);
                        }
                        if (openEventId == null) {
                            String desc = "PLC " + plcId + " DI ON: point=" + pointId +
                                          ", addr=" + diAddress + ", bit=" + bitNo +
                                          ", tag=" + tagName + ", item=" + itemName + ", panel=" + panelName;
                            String sev = isTripAlarmBit(tagName) ? "ALARM" : "WARN";
                            ins.setInt(1, deviceId);
                            ins.setString(2, eventType);
                            ins.setTimestamp(3, measuredAt);
                            ins.setString(4, sev);
                            ins.setString(5, desc);
                            opened += ins.executeUpdate();
                            if ("ALARM".equalsIgnoreCase(sev) || "CRITICAL".equalsIgnoreCase(sev)) {
                                openAlarmLogIfNeeded(conn, deviceId, eventType, sev, measuredAt, desc);
                            }
                        }
                    }
                    LAST_DI_VALUE_MAP.put(diKey, value);
                    continue;
                }

                // 0 -> 1 전이에서만 INSERT
                if (prev.intValue() == 0 && value == 1) {
                    selOpen.setInt(1, deviceId);
                    selOpen.setString(2, eventType);
                    Long openEventId = null;
                    try (ResultSet rs = selOpen.executeQuery()) {
                        if (rs.next()) openEventId = rs.getLong(1);
                    }
                    if (openEventId == null) {
                        String desc = "PLC " + plcId + " DI ON: point=" + pointId +
                                      ", addr=" + diAddress + ", bit=" + bitNo +
                                      ", tag=" + tagName + ", item=" + itemName + ", panel=" + panelName;
                        String sev = isTripAlarmBit(tagName) ? "ALARM" : "WARN";
                        ins.setInt(1, deviceId);
                        ins.setString(2, eventType);
                        ins.setTimestamp(3, measuredAt);
                        ins.setString(4, sev);
                        ins.setString(5, desc);
                        opened += ins.executeUpdate();
                        if ("ALARM".equalsIgnoreCase(sev) || "CRITICAL".equalsIgnoreCase(sev)) {
                            openAlarmLogIfNeeded(conn, deviceId, eventType, sev, measuredAt, desc);
                        }
                    }
                } else if (prev.intValue() == 1 && value == 0) {
                    // 1 -> 0 전이 시 열린 이벤트 종료
                    selOpen.setInt(1, deviceId);
                    selOpen.setString(2, eventType);
                    Long openEventId = null;
                    try (ResultSet rs = selOpen.executeQuery()) {
                        if (rs.next()) openEventId = rs.getLong(1);
                    }
                    if (openEventId != null) {
                        close.setTimestamp(1, measuredAt);
                        close.setTimestamp(2, measuredAt);
                        close.setTimestamp(3, measuredAt);
                        close.setLong(4, openEventId.longValue());
                        closed += close.executeUpdate();
                        closeAlarmLogIfOpen(conn, deviceId, eventType, measuredAt);
                    }
                }
                LAST_DI_VALUE_MAP.put(diKey, value);
            }

            // OCR 집계 이벤트: 해당 OCR bit가 모두 1이면 OPEN, 하나라도 0이면 CLOSE
            for (Map<String, Object> g : ocrGroups.values()) {
                int pointId = (Integer)g.get("point_id");
                int diAddress = (Integer)g.get("di_address");
                int bitCount = (Integer)g.get("bit_count");
                int onCount = (Integer)g.get("on_count");
                String itemName = String.valueOf(g.get("item_name") == null ? "" : g.get("item_name"));
                String panelName = String.valueOf(g.get("panel_name") == null ? "" : g.get("panel_name"));
                String tagName = String.valueOf(g.get("tag_name") == null ? "" : g.get("tag_name"));
                @SuppressWarnings("unchecked")
                List<String> bitValues = (List<String>)g.get("bit_values");

                if (bitCount <= 0) continue;
                boolean allOn = (onCount == bitCount);
                int deviceId = pointId;
                String tagKey = compactEventToken(normalizeTagKey(tagName), "DI", "OCR");
                String eventType = tagKey.isEmpty() ? "DI_OCR_ALL" : ("DI_OCR_ALL_" + tagKey);

                selOpen.setInt(1, deviceId);
                selOpen.setString(2, eventType);
                Long openEventId = null;
                try (ResultSet rs = selOpen.executeQuery()) {
                    if (rs.next()) openEventId = rs.getLong(1);
                }

                if (allOn) {
                    if (openEventId == null) {
                        String desc = "PLC " + plcId + " OCR ALL ON: point=" + pointId +
                                      ", addr=" + diAddress +
                                      ", bits=" + String.join(",", bitValues) +
                                      ", item=" + itemName + ", panel=" + panelName;
                        String sev = "ALARM";
                        ins.setInt(1, deviceId);
                        ins.setString(2, eventType);
                        ins.setTimestamp(3, measuredAt);
                        ins.setString(4, sev);
                        ins.setString(5, desc);
                        opened += ins.executeUpdate();
                        openAlarmLogIfNeeded(conn, deviceId, eventType, sev, measuredAt, desc);
                    }
                } else {
                    if (openEventId != null) {
                        close.setTimestamp(1, measuredAt);
                        close.setTimestamp(2, measuredAt);
                        close.setTimestamp(3, measuredAt);
                        close.setLong(4, openEventId.longValue());
                        closed += close.executeUpdate();
                        closeAlarmLogIfOpen(conn, deviceId, eventType, measuredAt);
                    }
                }
            }

            // OCGR 집계 이벤트: 해당 OCGR bit가 모두 1이면 OPEN, 하나라도 0이면 CLOSE
            for (Map<String, Object> g : ocgrGroups.values()) {
                int pointId = (Integer)g.get("point_id");
                int diAddress = (Integer)g.get("di_address");
                int bitCount = (Integer)g.get("bit_count");
                int onCount = (Integer)g.get("on_count");
                String itemName = String.valueOf(g.get("item_name") == null ? "" : g.get("item_name"));
                String panelName = String.valueOf(g.get("panel_name") == null ? "" : g.get("panel_name"));
                String tagName = String.valueOf(g.get("tag_name") == null ? "" : g.get("tag_name"));
                @SuppressWarnings("unchecked")
                List<String> bitValues = (List<String>)g.get("bit_values");

                if (bitCount <= 0) continue;
                boolean allOn = (onCount == bitCount);
                int deviceId = pointId;
                String tagKey = compactEventToken(normalizeTagKey(tagName), "DI", "OCGR");
                String eventType;
                if ("51G".equals(tagKey)) eventType = "DI_OCGR_51G";
                else eventType = tagKey.isEmpty() ? "DI_OCGR_ALL" : ("DI_OCGR_ALL_" + tagKey);

                selOpen.setInt(1, deviceId);
                selOpen.setString(2, eventType);
                Long openEventId = null;
                try (ResultSet rs = selOpen.executeQuery()) {
                    if (rs.next()) openEventId = rs.getLong(1);
                }

                if (allOn) {
                    if (openEventId == null) {
                        String desc = "PLC " + plcId + " OCGR ALL ON: point=" + pointId +
                                      ", addr=" + diAddress +
                                      ", bits=" + String.join(",", bitValues) +
                                      ", item=" + itemName + ", panel=" + panelName;
                        String sev = "ALARM";
                        ins.setInt(1, deviceId);
                        ins.setString(2, eventType);
                        ins.setTimestamp(3, measuredAt);
                        ins.setString(4, sev);
                        ins.setString(5, desc);
                        opened += ins.executeUpdate();
                        openAlarmLogIfNeeded(conn, deviceId, eventType, sev, measuredAt, desc);
                    }
                } else {
                    if (openEventId != null) {
                        close.setTimestamp(1, measuredAt);
                        close.setTimestamp(2, measuredAt);
                        close.setTimestamp(3, measuredAt);
                        close.setLong(4, openEventId.longValue());
                        closed += close.executeUpdate();
                        closeAlarmLogIfOpen(conn, deviceId, eventType, measuredAt);
                    }
                }
            }
        }
        return new int[]{opened, closed};
    }

    private static DiReadData readDiRows(ModbusTcpClient client, PlcConfig cfg, List<Map<String, Object>> diTagList) throws Exception {
        long t0 = System.currentTimeMillis();
        List<Map<String, Object>> out = new ArrayList<>();
        if (diTagList == null || diTagList.isEmpty()) {
            return new DiReadData(out, Math.max(0L, System.currentTimeMillis() - t0));
        }

        int minAddr = Integer.MAX_VALUE;
        int maxAddr = Integer.MIN_VALUE;
        for (Map<String, Object> t : diTagList) {
            int diAddress = (Integer)t.get("di_address");
            if (diAddress < minAddr) minAddr = diAddress;
            if (diAddress > maxAddr) maxAddr = diAddress;
        }

        int regCount = maxAddr - minAddr + 1;
        if (regCount <= 0) {
            return new DiReadData(out, Math.max(0L, System.currentTimeMillis() - t0));
        }

        // DI는 4xxxxx 레지스터(word) + bit_no 형태로 매핑되어 있으므로 Holding Register(0x03)로 읽는다.
        byte[] regs = readHoldingRegisters(client, cfg.unitId, toModbusOffset(minAddr), regCount);

        int diSeq = 1;
        for (Map<String, Object> t : diTagList) {
            int pointId = (Integer)t.get("point_id");
            int diAddress = (Integer)t.get("di_address");
            int bitNo = (Integer)t.get("bit_no");
            int plcBitNo = toPlcBitIndex(bitNo);
            String tagName = (String)t.get("tag_name");
            String itemName = (String)t.get("item_name");
            String panelName = (String)t.get("panel_name");
            int word = 0;
            int wordIdx = diAddress - minAddr;
            int byteIdx = wordIdx * 2;
            if (byteIdx >= 0 && (byteIdx + 1) < regs.length) {
                word = toU16(regs[byteIdx], regs[byteIdx + 1]);
            }
            boolean bitVal = (plcBitNo >= 0 && plcBitNo <= 15) && (((word >> plcBitNo) & 0x1) == 1);

            Map<String, Object> row = new HashMap<>();
            row.put("idx", diSeq++);
            row.put("point_id", pointId);
            row.put("di_address", diAddress);
            row.put("bit_no", bitNo);
            row.put("tag_name", tagName);
            row.put("item_name", itemName);
            row.put("panel_name", panelName);
            row.put("value", bitVal ? 1 : 0);
            out.add(row);
        }
        return new DiReadData(out, Math.max(0L, System.currentTimeMillis() - t0));
    }

    private static AiReadData readAiRows(ModbusTcpClient client, PlcConfig cfg, List<Map<String, Object>> mapList) throws Exception {
        long t0 = System.currentTimeMillis();
        if (mapList == null || mapList.isEmpty()) {
            throw new Exception("No enabled AI mapping found for this PLC.");
        }

        List<Map<String, Object>> out = new ArrayList<>();
        final int AI_MERGE_GAP_REGS = 8;
        final int AI_MERGE_MAX_REGS = 480;
        Map<Integer, List<AiRange>> aiRangesByMeter = new HashMap<>();
        for (Map<String, Object> m : mapList) {
            int meterId = (Integer)m.get("meter_id");
            int startAddress = (Integer)m.get("start_address");
            int floatCount = (Integer)m.get("float_count");
            if (floatCount <= 0) continue;
            int rowStart = startAddress;
            int rowEnd = startAddress + (floatCount * 2) - 1;

            List<AiRange> ranges = aiRangesByMeter.computeIfAbsent(meterId, k -> new ArrayList<>());
            if (ranges.isEmpty()) {
                ranges.add(new AiRange(rowStart, rowEnd));
                continue;
            }
            AiRange last = ranges.get(ranges.size() - 1);
            int mergedEnd = Math.max(last.endReg, rowEnd);
            int mergedLen = mergedEnd - last.startReg + 1;
            if (rowStart <= (last.endReg + 1 + AI_MERGE_GAP_REGS) && mergedLen <= AI_MERGE_MAX_REGS) last.endReg = mergedEnd;
            else ranges.add(new AiRange(rowStart, rowEnd));
        }

        for (List<AiRange> ranges : aiRangesByMeter.values()) {
            for (AiRange r : ranges) {
                int startOffset = toModbusOffset(r.startReg);
                int registerCount = r.endReg - r.startReg + 1;
                r.regs = readHoldingRegisters(client, cfg.unitId, startOffset, registerCount);
            }
        }

        int totalFloat = 0;
        int seq = 1;
        Set<Integer> metersRead = new HashSet<>();
        for (Map<String, Object> m : mapList) {
            int meterId = (Integer)m.get("meter_id");
            int startAddress = (Integer)m.get("start_address");
            int floatCount = (Integer)m.get("float_count");
            String byteOrder = (String)m.get("byte_order");
            if (floatCount <= 0) continue;

            metersRead.add(meterId);
            byte[] srcRegs = null;
            int baseByteOff = 0;
            List<AiRange> ranges = aiRangesByMeter.get(meterId);
            if (ranges != null) {
                for (AiRange r : ranges) {
                    int rowEnd = startAddress + (floatCount * 2) - 1;
                    if (startAddress >= r.startReg && rowEnd <= r.endReg) {
                        baseByteOff = (startAddress - r.startReg) * 2;
                        srcRegs = r.regs;
                        break;
                    }
                }
            }
            if (srcRegs == null) {
                int startOffset = toModbusOffset(startAddress);
                srcRegs = readHoldingRegisters(client, cfg.unitId, startOffset, floatCount * 2);
                baseByteOff = 0;
            }
            String[] tokens = (String[])m.get("tokens");
            if (tokens == null) tokens = new String[0];
            for (int i = 0; i < floatCount; i++) {
                int b = baseByteOff + (i * 4);
                float v = decodeFloatFrom2Regs(srcRegs[b], srcRegs[b + 1], srcRegs[b + 2], srcRegs[b + 3], byteOrder);
                Map<String, Object> row = new HashMap<>();
                row.put("idx", seq++);
                row.put("meter_id", meterId);
                row.put("float_index", i + 1);
                row.put("token", i < tokens.length ? tokens[i] : ("F" + (i + 1)));
                row.put("reg1", startAddress + (i * 2));
                row.put("reg2", startAddress + (i * 2) + 1);
                row.put("value", v);
                out.add(row);
            }
            totalFloat += floatCount;
        }
        return new AiReadData(out, metersRead.size(), totalFloat, Math.max(0L, System.currentTimeMillis() - t0));
    }

    private static DiReadData readDiData(int plcId, PlcConfig cfg) throws Exception {
        List<Map<String, Object>> diTagList = getCachedDiTagMap(plcId);
        try (ModbusTcpClient client = new ModbusTcpClient(cfg.ip, cfg.port)) {
            return readDiRows(client, cfg, diTagList);
        }
    }

    private static AiReadData readAiData(int plcId, PlcConfig cfg) throws Exception {
        List<Map<String, Object>> mapList = getCachedAiMap(plcId);
        try (ModbusTcpClient client = new ModbusTcpClient(cfg.ip, cfg.port)) {
            return readAiRows(client, cfg, mapList);
        }
    }

    private static PlcReadResult readPlcData(int plcId) {
        PlcReadResult result = new PlcReadResult();
        try {
            long tAllStart = System.currentTimeMillis();
            Timestamp measuredAt = new Timestamp(tAllStart);
            PlcConfig cfg = getCachedPlcConfig(plcId);
            if (!cfg.exists || cfg.ip == null) {
                result.error = "Selected PLC config not found.";
                return result;
            }
            if (!cfg.enabled) {
                result.error = "Selected PLC is inactive.";
                return result;
            }

            DiReadData diData = readDiData(plcId, cfg);
            AiReadData aiData = readAiData(plcId, cfg);
            int[] aiPersist = persistAiRowsToTargetTables(aiData.rows, measuredAt);
            int[] aiAlarmPersist = new int[]{0, 0};
            try {
                aiAlarmPersist = persistAiRowsViaAlarmApi(plcId, aiData.rows, measuredAt);
            } catch (Exception ignore) {
                // Keep AI data persistence alive even if alarm API is temporarily unavailable.
            }
            int[] diPersist;
            try {
                diPersist = persistDiRowsViaAlarmApi(plcId, diData.rows, measuredAt);
            } catch (Exception ex) {
                // Fallback for continuity when alarm_api is temporarily unavailable.
                diPersist = persistDiRowsToDeviceEvents(plcId, diData.rows, measuredAt);
            }

            result.diRows = diData.rows;
            result.rows = aiData.rows;
            result.measurementsInserted = aiPersist[0];
            result.harmonicInserted = aiPersist[1];
            result.flickerInserted = aiPersist[2];
            result.deviceEventsOpened = diPersist[0];
            result.deviceEventsClosed = diPersist[1];
            result.aiAlarmOpened = aiAlarmPersist[0];
            result.aiAlarmClosed = aiAlarmPersist[1];
            result.ok = true;
            result.info = "Read success. PLC " + plcId + " (" + cfg.ip + ":" + cfg.port + ", unit " + cfg.unitId +
                    "), meters=" + aiData.meterRead + ", total_floats=" + aiData.totalFloat + ", di_tags=" + result.diRows.size() +
                    ", measurements_ins=" + result.measurementsInserted + ", harmonic_ins=" + result.harmonicInserted +
                    ", flicker_ins=" + result.flickerInserted +
                    ", events_opened=" + result.deviceEventsOpened + ", events_closed=" + result.deviceEventsClosed +
                    ", ai_alarm_opened=" + result.aiAlarmOpened + ", ai_alarm_closed=" + result.aiAlarmClosed;
            long tEnd = System.currentTimeMillis();
            result.diMs = diData.durationMs;
            result.aiMs = aiData.durationMs;
            result.procMs = Math.max(0L, tEnd - tAllStart - result.diMs - result.aiMs);
            result.totalMs = Math.max(0L, tEnd - tAllStart);
            return result;
        } catch (Exception e) {
            result.error = e.getMessage();
            return result;
        }
    }

    private static void stopServerPolling(PollRuntime rt, int plcId) {
        ScheduledFuture<?> aiOld = rt.aiTasks.remove(plcId);
        if (aiOld != null) aiOld.cancel(false);
        ScheduledFuture<?> diOld = rt.diTasks.remove(plcId);
        if (diOld != null) diOld.cancel(false);
        PollState st = getPollState(rt, plcId);
        st.running = false;
    }

    private static void clearCaches(Integer plcId) {
        if (plcId == null) {
            PLC_CONFIG_CACHE.clear();
            AI_MAP_CACHE.clear();
            DI_MAP_CACHE.clear();
            DI_TAG_CACHE.clear();
            AI_MEAS_MATCH_CACHE.clear();
            LAST_DI_VALUE_MAP.clear();
            return;
        }

        PLC_CONFIG_CACHE.remove(plcId);
        AI_MAP_CACHE.remove(plcId);
        DI_MAP_CACHE.remove(plcId);
        DI_TAG_CACHE.remove(plcId);

        String prefix = plcId + ":";
        List<String> keys = new ArrayList<>(LAST_DI_VALUE_MAP.keySet());
        for (String k : keys) {
            if (k != null && k.startsWith(prefix)) LAST_DI_VALUE_MAP.remove(k);
        }
    }

    private static void startServerPolling(final PollRuntime rt, final int plcId, final int pollingMs) {
        stopServerPolling(rt, plcId);
        final PollState st = getPollState(rt, plcId);
        st.attemptCount.set(0L);
        st.successCount.set(0L);
        st.readCount.set(0L);
        st.diReadCount.set(0L);
        st.aiReadCount.set(0L);
        st.readDurationSumMs.set(0L);
        st.lastReadDurationMs = 0L;
        st.lastDiReadMs = 0L;
        st.lastAiReadMs = 0L;
        st.lastProcMs = 0L;
        st.lastRows = Collections.emptyList();
        st.lastDiRows = Collections.emptyList();
        st.lastRunAt = 0L;
        st.running = true;
        st.pollingMs = pollingMs;
        st.lastInfo = "";
        st.lastError = "";

        Runnable diTask = new Runnable() {
            @Override
            public void run() {
                if (!st.diInProgress.compareAndSet(false, true)) return;
                try {
                    st.attemptCount.incrementAndGet();
                    long t0 = System.currentTimeMillis();
                    Timestamp measuredAt = new Timestamp(t0);
                    PlcConfig cfg = getCachedPlcConfig(plcId);
                    if (!cfg.exists || cfg.ip == null) {
                        st.lastError = "Selected PLC config not found.";
                        st.lastRunAt = System.currentTimeMillis();
                        return;
                    }
                    if (!cfg.enabled) {
                        st.lastError = "Selected PLC is inactive.";
                        st.lastRunAt = System.currentTimeMillis();
                        return;
                    }

                    DiReadData diData = readDiData(plcId, cfg);
                    int[] diPersist;
                    try {
                        diPersist = persistDiRowsViaAlarmApi(plcId, diData.rows, measuredAt);
                    } catch (Exception ex) {
                        diPersist = persistDiRowsToDeviceEvents(plcId, diData.rows, measuredAt);
                    }
                    long usedElapsed = diData.durationMs > 0L ? diData.durationMs : Math.max(0L, System.currentTimeMillis() - t0);
                    st.successCount.incrementAndGet();
                    st.readCount.incrementAndGet();
                    st.diReadCount.incrementAndGet();
                    st.lastReadDurationMs = usedElapsed;
                    st.lastDiReadMs = diData.durationMs;
                    st.lastProcMs = 0L;
                    st.readDurationSumMs.addAndGet(usedElapsed);
                    st.lastDiRows = new ArrayList<>(diData.rows);
                    st.lastInfo = "DI read success. PLC " + plcId + ", di_tags=" + diData.rows.size() +
                                  ", events_opened=" + diPersist[0] + ", events_closed=" + diPersist[1];
                    st.lastError = "";
                    st.lastRunAt = System.currentTimeMillis();
                } catch (Exception e) {
                    e.printStackTrace(); // 서버 로그에 에러 출력
                    st.lastError = e.getMessage();
                    st.lastRunAt = System.currentTimeMillis();
                } finally {
                    st.diInProgress.set(false);
                }
            }
        };

        Runnable aiTask = new Runnable() {
            @Override
            public void run() {
                if (!st.aiInProgress.compareAndSet(false, true)) return;
                try {
                    st.attemptCount.incrementAndGet();
                    long t0 = System.currentTimeMillis();
                    Timestamp measuredAt = new Timestamp(t0);
                    PlcConfig cfg = getCachedPlcConfig(plcId);
                    if (!cfg.exists || cfg.ip == null) {
                        st.lastError = "Selected PLC config not found.";
                        st.lastRunAt = System.currentTimeMillis();
                        return;
                    }
                    if (!cfg.enabled) {
                        st.lastError = "Selected PLC is inactive.";
                        st.lastRunAt = System.currentTimeMillis();
                        return;
                    }

                    AiReadData aiData = readAiData(plcId, cfg);
                    int[] aiPersist = persistAiRowsToTargetTables(aiData.rows, measuredAt);
                    int[] aiAlarmPersist = new int[]{0, 0};
                    try {
                        aiAlarmPersist = persistAiRowsViaAlarmApi(plcId, aiData.rows, measuredAt);
                    } catch (Exception ignore) {
                        // Keep AI polling flow alive even when alarm_api is temporarily unavailable.
                    }
                    long usedElapsed = aiData.durationMs > 0L ? aiData.durationMs : Math.max(0L, System.currentTimeMillis() - t0);
                    st.successCount.incrementAndGet();
                    st.readCount.incrementAndGet();
                    st.aiReadCount.incrementAndGet();
                    st.lastReadDurationMs = usedElapsed;
                    st.lastAiReadMs = aiData.durationMs;
                    st.lastProcMs = 0L;
                    st.readDurationSumMs.addAndGet(usedElapsed);
                    st.lastRows = new ArrayList<>(aiData.rows);
                    st.lastInfo = "AI read success. PLC " + plcId + ", meters=" + aiData.meterRead + ", total_floats=" + aiData.totalFloat +
                                  ", measurements_ins=" + aiPersist[0] + ", harmonic_ins=" + aiPersist[1] +
                                  ", flicker_ins=" + aiPersist[2] +
                                  ", ai_alarm_opened=" + aiAlarmPersist[0] + ", ai_alarm_closed=" + aiAlarmPersist[1];
                    st.lastError = "";
                    st.lastRunAt = System.currentTimeMillis();
                } catch (Exception e) {
                    e.printStackTrace(); // 서버 로그에 에러 출력
                    st.lastError = e.getMessage();
                    st.lastRunAt = System.currentTimeMillis();
                } finally {
                    st.aiInProgress.set(false);
                }
            }
        };

        ScheduledFuture<?> diFuture = rt.exec.scheduleAtFixedRate(diTask, 0, DI_POLLING_MS, TimeUnit.MILLISECONDS);
        ScheduledFuture<?> aiFuture = rt.exec.scheduleAtFixedRate(aiTask, 0, pollingMs, TimeUnit.MILLISECONDS);
        rt.diTasks.put(plcId, diFuture);
        rt.aiTasks.put(plcId, aiFuture);
    }

    private static String toReadJson(PlcReadResult r) {
        StringBuilder outJson = new StringBuilder();
        outJson.append("{\"ok\":").append(r.ok ? "true" : "false");
        if (r.ok) {
            outJson.append(",\"info\":\"").append(escJson(r.info)).append("\"");
            outJson.append(",\"measurements_inserted\":").append(r.measurementsInserted);
            outJson.append(",\"harmonic_inserted\":").append(r.harmonicInserted);
            outJson.append(",\"flicker_inserted\":").append(r.flickerInserted);
            outJson.append(",\"device_events_opened\":").append(r.deviceEventsOpened);
            outJson.append(",\"device_events_closed\":").append(r.deviceEventsClosed);
            outJson.append(",\"ai_alarm_opened\":").append(r.aiAlarmOpened);
            outJson.append(",\"ai_alarm_closed\":").append(r.aiAlarmClosed);
            outJson.append(",\"rows\":");
            appendAiRowsJson(outJson, r.rows);
            outJson.append(",\"di_rows\":");
            appendDiRowsJson(outJson, r.diRows);
            outJson.append("}");
        } else {
            outJson.append(",\"error\":\"").append(escJson(r.error)).append("\"}");
        }
        return outJson.toString();
    }

    private static void appendAiRowsJson(StringBuilder outJson, List<Map<String, Object>> rows) {
        outJson.append("[");
        for (int i = 0; i < rows.size(); i++) {
            Map<String, Object> row = rows.get(i);
            Number v = (Number)row.get("value");
            double value = (v == null) ? 0.0d : v.doubleValue();
            outJson.append("{")
                   .append("\"idx\":").append(row.get("idx")).append(",")
                   .append("\"meter_id\":").append(row.get("meter_id")).append(",")
                   .append("\"token\":\"").append(escJson((String)row.get("token"))).append("\",")
                   .append("\"reg1\":").append(row.get("reg1")).append(",")
                   .append("\"reg2\":").append(row.get("reg2")).append(",")
                   .append("\"value\":").append(String.format(java.util.Locale.US, "%.6f", value))
                   .append("}");
            if (i < rows.size() - 1) outJson.append(",");
        }
        outJson.append("]");
    }

    private static void appendDiRowsJson(StringBuilder outJson, List<Map<String, Object>> rows) {
        outJson.append("[");
        for (int i = 0; i < rows.size(); i++) {
            Map<String, Object> row = rows.get(i);
            outJson.append("{")
                   .append("\"idx\":").append(row.get("idx")).append(",")
                   .append("\"point_id\":").append(row.get("point_id")).append(",")
                   .append("\"di_address\":").append(row.get("di_address")).append(",")
                   .append("\"bit_no\":").append(row.get("bit_no")).append(",")
                   .append("\"tag_name\":\"").append(escJson((String)row.get("tag_name"))).append("\",")
                   .append("\"item_name\":\"").append(escJson((String)row.get("item_name"))).append("\",")
                   .append("\"panel_name\":\"").append(escJson((String)row.get("panel_name"))).append("\",")
                   .append("\"value\":").append(row.get("value"))
                   .append("}");
            if (i < rows.size() - 1) outJson.append(",");
        }
        outJson.append("]");
    }
%>
<%
    response.setContentType("application/json; charset=UTF-8");
    PollRuntime pollRt = getPollRuntime(application);

    String action = request.getParameter("action");
    String plcParam = request.getParameter("plc_id");
    Integer plcId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}

    String actionNorm = (action == null) ? "" : action.trim().toLowerCase(java.util.Locale.ROOT);
    boolean shouldTrace = "read".equals(actionNorm) ||
                          "start_polling".equals(actionNorm) ||
                          "stop_polling".equals(actionNorm);
    if (shouldTrace) {
        String remoteAddr = clipForLog(request.getRemoteAddr(), 64);
        String xff = clipForLog(request.getHeader("X-Forwarded-For"), 120);
        String ua = clipForLog(request.getHeader("User-Agent"), 220);
        String referer = clipForLog(request.getHeader("Referer"), 220);
        String query = clipForLog(request.getQueryString(), 220);
        String method = clipForLog(request.getMethod(), 10);
        System.out.println(
            "[modbus_api] ts=" + new java.sql.Timestamp(System.currentTimeMillis()) +
            " action=" + actionNorm +
            " plc_id=" + (plcId == null ? "-" : String.valueOf(plcId)) +
            " method=" + method +
            " remote=" + remoteAddr +
            " xff=" + xff +
            " referer=" + referer +
            " ua=" + ua +
            " query=" + query
        );
    }

    if (action == null || action.trim().isEmpty()) {
        out.print("{\"ok\":false,\"error\":\"action is required\"}");
        return;
    }

    if ("polling_status".equalsIgnoreCase(action)) {
        StringBuilder s = new StringBuilder();
        s.append("{\"ok\":true,\"states\":[");
        boolean first = true;
        List<Integer> ids = new ArrayList<>(pollRt.states.keySet());
        Collections.sort(ids);
        for (Integer id : ids) {
            PollState st = pollRt.states.get(id);
            if (st == null) continue;
            long attempt = st.attemptCount.get();
            long success = st.successCount.get();
            double successRate = (attempt > 0L) ? (success * 100.0d / attempt) : 0.0d;
            double avgReadMs = (success > 0L) ? (st.readDurationSumMs.get() * 1.0d / success) : 0.0d;
            if (!first) s.append(",");
            first = false;
            s.append("{")
             .append("\"plc_id\":").append(id).append(",")
             .append("\"running\":").append(st.running ? "true" : "false").append(",")
             .append("\"polling_ms\":").append(st.pollingMs).append(",")
             .append("\"attempt_count\":").append(attempt).append(",")
             .append("\"success_count\":").append(success).append(",")
             .append("\"success_rate\":").append(String.format(java.util.Locale.US, "%.2f", successRate)).append(",")
             .append("\"read_count\":").append(st.readCount.get()).append(",")
             .append("\"di_read_count\":").append(st.diReadCount.get()).append(",")
             .append("\"ai_read_count\":").append(st.aiReadCount.get()).append(",")
             .append("\"last_read_ms\":").append(st.lastReadDurationMs).append(",")
             .append("\"di_read_ms\":").append(st.lastDiReadMs).append(",")
             .append("\"ai_read_ms\":").append(st.lastAiReadMs).append(",")
             .append("\"proc_ms\":").append(st.lastProcMs).append(",")
             .append("\"avg_read_ms\":").append(String.format(java.util.Locale.US, "%.1f", avgReadMs)).append(",")
             .append("\"last_run_at\":").append(st.lastRunAt).append(",")
             .append("\"last_info\":\"").append(escJson(st.lastInfo)).append("\",")
             .append("\"last_error\":\"").append(escJson(st.lastError)).append("\"")
             .append("}");
        }
        s.append("]}");
        out.print(s.toString());
        return;
    }

    if ("polling_snapshot".equalsIgnoreCase(action)) {
        StringBuilder s = new StringBuilder();
        s.append("{\"ok\":true,\"states\":[");
        boolean first = true;
        List<Integer> ids = new ArrayList<>(pollRt.states.keySet());
        Collections.sort(ids);
        for (Integer id : ids) {
            PollState st = pollRt.states.get(id);
            if (st == null) continue;
            long attempt = st.attemptCount.get();
            long success = st.successCount.get();
            double successRate = (attempt > 0L) ? (success * 100.0d / attempt) : 0.0d;
            double avgReadMs = (success > 0L) ? (st.readDurationSumMs.get() * 1.0d / success) : 0.0d;
            if (!first) s.append(",");
            first = false;
            s.append("{")
             .append("\"plc_id\":").append(id).append(",")
             .append("\"running\":").append(st.running ? "true" : "false").append(",")
             .append("\"polling_ms\":").append(st.pollingMs).append(",")
             .append("\"attempt_count\":").append(attempt).append(",")
             .append("\"success_count\":").append(success).append(",")
             .append("\"success_rate\":").append(String.format(java.util.Locale.US, "%.2f", successRate)).append(",")
             .append("\"read_count\":").append(st.readCount.get()).append(",")
             .append("\"di_read_count\":").append(st.diReadCount.get()).append(",")
             .append("\"ai_read_count\":").append(st.aiReadCount.get()).append(",")
             .append("\"last_read_ms\":").append(st.lastReadDurationMs).append(",")
             .append("\"di_read_ms\":").append(st.lastDiReadMs).append(",")
             .append("\"ai_read_ms\":").append(st.lastAiReadMs).append(",")
             .append("\"proc_ms\":").append(st.lastProcMs).append(",")
             .append("\"avg_read_ms\":").append(String.format(java.util.Locale.US, "%.1f", avgReadMs)).append(",")
             .append("\"last_run_at\":").append(st.lastRunAt).append(",")
             .append("\"last_info\":\"").append(escJson(st.lastInfo)).append("\",")
             .append("\"last_error\":\"").append(escJson(st.lastError)).append("\",")
             .append("\"rows\":");
            appendAiRowsJson(s, st.lastRows);
            s.append(",\"di_rows\":");
            appendDiRowsJson(s, st.lastDiRows);
            s.append("}");
        }
        s.append("]}");
        out.print(s.toString());
        return;
    }

    if ("clear_cache".equalsIgnoreCase(action)) {
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            out.print("{\"ok\":false,\"error\":\"POST method is required for clear_cache\"}");
            return;
        }
        clearCaches(plcId);
        out.print("{\"ok\":true,\"info\":\"cache cleared\"}");
        return;
    }

    if (plcId == null) {
        out.print("{\"ok\":false,\"error\":\"plc_id is required\"}");
        return;
    }

    if ("read".equalsIgnoreCase(action)) {
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            out.print("{\"ok\":false,\"error\":\"POST method is required for read\"}");
            return;
        }
        PollState st = getPollState(pollRt, plcId);
        st.attemptCount.incrementAndGet();
        long t0 = System.currentTimeMillis();
        PlcReadResult rr = readPlcData(plcId);
        long elapsed = Math.max(0L, System.currentTimeMillis() - t0);
        if (rr.ok) {
            st.successCount.incrementAndGet();
            st.readCount.incrementAndGet();
            st.diReadCount.incrementAndGet();
            st.aiReadCount.incrementAndGet();
            long usedElapsed = rr.totalMs > 0L ? rr.totalMs : elapsed;
            st.lastReadDurationMs = usedElapsed;
            st.lastDiReadMs = rr.diMs;
            st.lastAiReadMs = rr.aiMs;
            st.lastProcMs = rr.procMs;
            st.readDurationSumMs.addAndGet(usedElapsed);
            st.lastRows = new ArrayList<>(rr.rows);
            st.lastDiRows = new ArrayList<>(rr.diRows);
            st.lastInfo = rr.info;
            st.lastError = "";
        } else {
            st.lastError = rr.error;
        }
        st.lastRunAt = System.currentTimeMillis();
        out.print(toReadJson(rr));
        return;
    }

    if ("start_polling".equalsIgnoreCase(action)) {
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            out.print("{\"ok\":false,\"error\":\"POST method is required for start_polling\"}");
            return;
        }
        int pollingMs = 1000;
        try {
            PLC_CONFIG_CACHE.remove(plcId);
            PlcConfig cfg = getCachedPlcConfig(plcId);
            if (!cfg.exists) {
                out.print("{\"ok\":false,\"error\":\"Selected PLC config not found.\"}");
                return;
            }
            if (!cfg.enabled) {
                out.print("{\"ok\":false,\"error\":\"Selected PLC is inactive.\"}");
                return;
            }
            pollingMs = cfg.pollingMs;
        } catch (Exception e) {
            out.print("{\"ok\":false,\"error\":\"" + escJson(e.getMessage()) + "\"}");
            return;
        }

        String msParam = request.getParameter("polling_ms");
        if (msParam != null && !msParam.trim().isEmpty()) {
            try { pollingMs = Integer.parseInt(msParam.trim()); } catch (Exception ignore) {}
        }
        if (pollingMs <= 0) pollingMs = 1000;

        startServerPolling(pollRt, plcId, pollingMs);
        out.print("{\"ok\":true,\"info\":\"server polling started (" + pollingMs + "ms)\"}");
        return;
    }

    if ("stop_polling".equalsIgnoreCase(action)) {
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            out.print("{\"ok\":false,\"error\":\"POST method is required for stop_polling\"}");
            return;
        }
        stopServerPolling(pollRt, plcId);
        out.print("{\"ok\":true,\"info\":\"server polling stopped\"}");
        return;
    }

    out.print("{\"ok\":false,\"error\":\"unknown action\"}");
%>


