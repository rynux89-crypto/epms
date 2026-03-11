<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.util.concurrent.*" %>
<%@ page import="java.util.concurrent.atomic.*" %>
<%@ page import="java.net.*" %>
<%@ page import="java.io.*" %>
<%@ page import="epms.util.PlcWriteSupport" %>
<%@ include file="../../includes/dbconfig.jspf" %>
<%@ include file="../../includes/epms_json.jspf" %>
<%!
private static final ScheduledExecutorService WRITE_EXEC = Executors.newScheduledThreadPool(4);
private static final ConcurrentHashMap<Integer, ScheduledFuture<?>> WRITE_TASKS = new ConcurrentHashMap<>();
private static final ConcurrentHashMap<Integer, WriteState> WRITE_STATES = new ConcurrentHashMap<>();
private static final ConcurrentHashMap<Integer, CacheEntry<PlcConfig>> PLC_CONFIG_CACHE = new ConcurrentHashMap<>();
private static final ConcurrentHashMap<Integer, CacheEntry<List<Map<String, Object>>>> AI_MAP_CACHE = new ConcurrentHashMap<>();
private static final ConcurrentHashMap<Integer, CacheEntry<List<Map<String, Object>>>> DI_TAG_CACHE = new ConcurrentHashMap<>();
private static final ConcurrentHashMap<String, TagRange> TAG_RANGE_OVERRIDES = new ConcurrentHashMap<>();
private static final Object TAG_RANGE_FILE_LOCK = new Object();
private static final ConcurrentHashMap<String, Double> ENERGY_ACCUM_MAP = new ConcurrentHashMap<>();
private static final ConcurrentHashMap<String, Integer> DI_LAST_VALUE_MAP = new ConcurrentHashMap<>();
private static final int WRITE_MAX_REGS_PER_REQ = 120;
private static final int WRITE_MAX_COILS_PER_REQ = 120;
private static final long PLC_CONFIG_CACHE_TTL_MS = 30_000L;
private static final long TAG_MAP_CACHE_TTL_MS = 60_000L;

private static class CacheEntry<T> {
    final T data;
    final long loadedAtMs;
    CacheEntry(T d){ this(d, System.currentTimeMillis()); }
    CacheEntry(T d, long t){ data=d; loadedAtMs=t; }
}
private static class TagRange { final double min,max; TagRange(double a,double b){min=a;max=b;} }
private static class WriteState {
    final AtomicLong attemptCount = new AtomicLong(0);
    final AtomicLong successCount = new AtomicLong(0);
    final AtomicLong writeCount = new AtomicLong(0);
    volatile boolean running = false;
    volatile int pollingMs = 1000;
    volatile long lastWriteMs = 0L, lastAiWriteMs = 0L, lastDiWriteMs = 0L, lastRunAt = 0L;
    volatile String lastInfo = "", lastError = "";
    volatile List<Map<String, Object>> lastAiRows = Collections.emptyList();
    volatile List<Map<String, Object>> lastDiRows = Collections.emptyList();
}
private static class PlcConfig { boolean exists=false, enabled=false; int pollingMs=1000, port=502, unitId=1; String ip=null; }
private static class WriteResult {
    boolean ok=false; String info="", error=""; long totalMs=0L, aiMs=0L, diMs=0L;
    List<Map<String, Object>> aiRows=new ArrayList<>(); List<Map<String, Object>> diRows=new ArrayList<>();
    String warning = "";
}
private static class AiWriteData {
    final List<Map<String, Object>> rows; final int meterWritten,totalFloat; final long durationMs;
    AiWriteData(List<Map<String, Object>> r,int m,int t,long d){rows=r;meterWritten=m;totalFloat=t;durationMs=d;}
}
private static class DiWriteData {
    final List<Map<String, Object>> rows; final int changedCount; final long durationMs;
    DiWriteData(List<Map<String, Object>> r,int c,long d){rows=r;changedCount=c;durationMs=d;}
}
private static class WriteRequestContext {
    String action;
    Integer plcId;
    boolean includeRows;
}
private static class ModbusTcpClient implements AutoCloseable {
    private final Socket socket; private final InputStream in; private final OutputStream out; private int txId=1;
    ModbusTcpClient(String ip,int port) throws IOException {
        socket = new Socket(); socket.connect(new InetSocketAddress(ip, port), 3000); socket.setSoTimeout(5000);
        in = socket.getInputStream(); out = socket.getOutputStream();
    }
    int nextTxId(){ int c=txId++; if(txId>0x7FFF) txId=1; return c; }
    InputStream in(){ return in; } OutputStream out(){ return out; }
    public void close(){ try{socket.close();}catch(Exception ignore){} }
}

private static Connection createConn() throws Exception { return openDbConnection(); }
private static WriteState getWriteState(int plcId){ return WRITE_STATES.computeIfAbsent(plcId, k -> new WriteState()); }
private static int toU16(byte hi, byte lo){ return PlcWriteSupport.toU16(hi, lo); }
private static boolean isCacheValid(CacheEntry<?> ce, long ttlMs){
    return ce != null && (ttlMs <= 0L || (System.currentTimeMillis() - ce.loadedAtMs) < ttlMs);
}
private static void invalidateConfigCache(Integer plcId){
    if (plcId == null) PLC_CONFIG_CACHE.clear();
    else PLC_CONFIG_CACHE.remove(plcId);
}
private static void invalidateTagMapCache(Integer plcId){
    if (plcId == null) {
        AI_MAP_CACHE.clear();
        DI_TAG_CACHE.clear();
        return;
    }
    AI_MAP_CACHE.remove(plcId);
    DI_TAG_CACHE.remove(plcId);
}
private static void invalidateRuntimeValueCache(Integer plcId){
    if (plcId == null) {
        ENERGY_ACCUM_MAP.clear();
        DI_LAST_VALUE_MAP.clear();
        return;
    }
    String plcPrefixA = String.valueOf(plcId) + ":";
    String plcPrefixE = String.valueOf(plcId) + "|E|";
    for (String k : new ArrayList<String>(ENERGY_ACCUM_MAP.keySet())) {
        if (k != null && k.startsWith(plcPrefixE)) ENERGY_ACCUM_MAP.remove(k);
    }
    for (String k : new ArrayList<String>(DI_LAST_VALUE_MAP.keySet())) {
        if (k != null && k.startsWith(plcPrefixA)) DI_LAST_VALUE_MAP.remove(k);
    }
}
private static int toHoldingOffset(int addr){ return PlcWriteSupport.toHoldingOffset(addr); }
private static int toCoilOffset(int addr){ return PlcWriteSupport.toCoilOffset(addr); }

private static byte[] readExactly(InputStream in, int len) throws IOException {
    return PlcWriteSupport.readExactly(in, len);
}

private static void writeRegs(ModbusTcpClient c, int unitId, int startOffset, int[] regs) throws IOException {
    if (regs == null || regs.length == 0) return;
    int i = 0;
    while (i < regs.length) {
        int chunk = Math.min(WRITE_MAX_REGS_PER_REQ, regs.length - i);
        int addr = startOffset + i;
        int byteCount = chunk * 2;
        int mbapLen = 7 + byteCount; // unit(1) + fn/start/qty/byteCount/data
        int tx = c.nextTxId();
        byte[] req = new byte[13 + byteCount];
        req[0]=(byte)((tx>>8)&0xFF); req[1]=(byte)(tx&0xFF);
        req[2]=0; req[3]=0; req[4]=(byte)((mbapLen>>8)&0xFF); req[5]=(byte)(mbapLen&0xFF);
        req[6]=(byte)(unitId&0xFF);
        req[7]=0x10;
        req[8]=(byte)((addr>>8)&0xFF); req[9]=(byte)(addr&0xFF);
        req[10]=(byte)((chunk>>8)&0xFF); req[11]=(byte)(chunk&0xFF);
        req[12]=(byte)(byteCount&0xFF);
        int off = 13;
        for (int j = 0; j < chunk; j++) {
            int regVal = regs[i + j] & 0xFFFF;
            req[off++] = (byte)((regVal>>8)&0xFF);
            req[off++] = (byte)(regVal&0xFF);
        }
        c.out().write(req); c.out().flush();

        byte[] mbap = readExactly(c.in(), 7);
        int len = toU16(mbap[4], mbap[5]);
        byte[] pdu = readExactly(c.in(), len - 1);
        int fn = pdu[0] & 0xFF;
        if (fn == 0x90) throw new IOException("Modbus write register exception: " + (pdu[1] & 0xFF));
        if (fn != 0x10) throw new IOException("Unexpected write function code: " + fn);
        if (pdu.length < 5) throw new IOException("Invalid FC16 response length: " + pdu.length);
        int echoedAddr = toU16(pdu[1], pdu[2]);
        int echoedQty = toU16(pdu[3], pdu[4]);
        if (echoedAddr != addr || echoedQty != chunk) {
            throw new IOException("FC16 echo mismatch: addr=" + echoedAddr + ", qty=" + echoedQty + ", expected_addr=" + addr + ", expected_qty=" + chunk);
        }
        i += chunk;
    }
}

private static void writeCoils(ModbusTcpClient c, int unitId, int startOffset, boolean[] coils) throws IOException {
    if (coils == null || coils.length == 0) return;
    if (startOffset < 0 || startOffset > 0xFFFF) throw new IOException("Coil start offset out of range: " + startOffset);
    int i = 0;
    while (i < coils.length) {
        int chunk = Math.min(WRITE_MAX_COILS_PER_REQ, coils.length - i);
        int addr = startOffset + i;
        if (addr < 0 || addr > 0xFFFF || (addr + chunk - 1) > 0xFFFF) {
            throw new IOException("Coil range out of 16-bit address space: start=" + addr + ", qty=" + chunk);
        }
        int byteCount = (chunk + 7) / 8;
        int mbapLen = 7 + byteCount; // unit + fn/start/qty/byteCount/data
        int tx = c.nextTxId();
        byte[] req = new byte[13 + byteCount];
        req[0]=(byte)((tx>>8)&0xFF); req[1]=(byte)(tx&0xFF);
        req[2]=0; req[3]=0; req[4]=(byte)((mbapLen>>8)&0xFF); req[5]=(byte)(mbapLen&0xFF);
        req[6]=(byte)(unitId&0xFF);
        req[7]=0x0F;
        req[8]=(byte)((addr>>8)&0xFF); req[9]=(byte)(addr&0xFF);
        req[10]=(byte)((chunk>>8)&0xFF); req[11]=(byte)(chunk&0xFF);
        req[12]=(byte)(byteCount&0xFF);
        for (int j = 0; j < chunk; j++) {
            if (coils[i + j]) req[13 + (j / 8)] |= (byte)(1 << (j % 8));
        }
        c.out().write(req); c.out().flush();

        byte[] mbap=readExactly(c.in(),7); int len=toU16(mbap[4],mbap[5]); byte[] pdu=readExactly(c.in(),len-1); int fn=pdu[0]&0xFF;
        if(fn==0x8F) throw new IOException("Modbus write coils exception: " + (pdu[1]&0xFF));
        if(fn!=0x0F) throw new IOException("Unexpected coils function code: " + fn);
        if (pdu.length < 5) throw new IOException("Invalid FC15 response length: " + pdu.length);
        int echoedAddr = toU16(pdu[1], pdu[2]);
        int echoedQty = toU16(pdu[3], pdu[4]);
        if (echoedAddr != addr || echoedQty != chunk) {
            throw new IOException("FC15 echo mismatch: addr=" + echoedAddr + ", qty=" + echoedQty + ", expected_addr=" + addr + ", expected_qty=" + chunk);
        }
        i += chunk;
    }
}

private static PlcConfig loadPlcConfig(Connection conn, int plcId) throws Exception {
    PlcConfig cfg = new PlcConfig();
    try (PreparedStatement ps = conn.prepareStatement("SELECT plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config WHERE plc_id = ?")) {
        ps.setInt(1, plcId);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                cfg.exists = true; cfg.ip = rs.getString("plc_ip"); cfg.port = rs.getInt("plc_port"); cfg.unitId = rs.getInt("unit_id"); cfg.pollingMs = rs.getInt("polling_ms"); cfg.enabled = rs.getBoolean("enabled");
            }
        }
    }
    return cfg;
}

private static PlcConfig getCachedPlcConfig(int plcId) throws Exception {
    CacheEntry<PlcConfig> ce = PLC_CONFIG_CACHE.get(plcId); if (isCacheValid(ce, PLC_CONFIG_CACHE_TTL_MS)) return ce.data;
    synchronized (PLC_CONFIG_CACHE) {
        ce = PLC_CONFIG_CACHE.get(plcId); if (isCacheValid(ce, PLC_CONFIG_CACHE_TTL_MS)) return ce.data;
        try (Connection conn = createConn()) {
            PlcConfig loaded = loadPlcConfig(conn, plcId); PLC_CONFIG_CACHE.put(plcId, new CacheEntry<>(loaded)); return loaded;
        }
    }
}

private static List<Map<String,Object>> loadAiMap(Connection conn, int plcId) throws Exception {
    List<Map<String,Object>> out = new ArrayList<>();
    try (PreparedStatement ps = conn.prepareStatement("SELECT meter_id, start_address, float_count, byte_order, metric_order FROM dbo.plc_meter_map WHERE plc_id = ? AND enabled = 1 ORDER BY meter_id, start_address")) {
        ps.setInt(1, plcId);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String,Object> m = new HashMap<>();
                m.put("meter_id", rs.getInt("meter_id")); m.put("start_address", rs.getInt("start_address")); m.put("float_count", rs.getInt("float_count")); m.put("byte_order", rs.getString("byte_order"));
                String metricOrder = rs.getString("metric_order"); m.put("tokens", metricOrder == null ? new String[0] : metricOrder.split("\\s*,\\s*"));
                out.add(m);
            }
        }
    }
    return out;
}

private static List<Map<String,Object>> getCachedAiMap(int plcId) throws Exception {
    CacheEntry<List<Map<String,Object>>> ce = AI_MAP_CACHE.get(plcId); if (isCacheValid(ce, TAG_MAP_CACHE_TTL_MS)) return ce.data;
    synchronized (AI_MAP_CACHE) {
        ce = AI_MAP_CACHE.get(plcId); if (isCacheValid(ce, TAG_MAP_CACHE_TTL_MS)) return ce.data;
        try (Connection conn = createConn()) {
            List<Map<String,Object>> loaded = loadAiMap(conn, plcId); AI_MAP_CACHE.put(plcId, new CacheEntry<>(loaded)); return loaded;
        }
    }
}

private static List<Map<String,Object>> loadDiTagMap(Connection conn, int plcId) throws Exception {
    List<Map<String,Object>> out = new ArrayList<>();
    try (PreparedStatement ps = conn.prepareStatement("SELECT point_id, di_address, bit_no, tag_name, item_name, panel_name FROM dbo.plc_di_tag_map WHERE plc_id = ? AND enabled = 1 ORDER BY di_address, bit_no")) {
        ps.setInt(1, plcId);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String,Object> r = new HashMap<>();
                r.put("point_id", rs.getInt("point_id")); r.put("di_address", rs.getInt("di_address")); r.put("bit_no", rs.getInt("bit_no"));
                r.put("tag_name", rs.getString("tag_name")); r.put("item_name", rs.getString("item_name")); r.put("panel_name", rs.getString("panel_name"));
                out.add(r);
            }
        }
    }
    return out;
}

private static List<Map<String,Object>> getCachedDiTagMap(int plcId) throws Exception {
    CacheEntry<List<Map<String,Object>>> ce = DI_TAG_CACHE.get(plcId); if (isCacheValid(ce, TAG_MAP_CACHE_TTL_MS)) return ce.data;
    synchronized (DI_TAG_CACHE) {
        ce = DI_TAG_CACHE.get(plcId); if (isCacheValid(ce, TAG_MAP_CACHE_TTL_MS)) return ce.data;
        try (Connection conn = createConn()) {
            List<Map<String,Object>> loaded = loadDiTagMap(conn, plcId); DI_TAG_CACHE.put(plcId, new CacheEntry<>(loaded)); return loaded;
        }
    }
}

private static boolean isEnergyToken(String token){
    String t = token == null ? "" : token.toLowerCase(Locale.ROOT);
    return t.contains("kwh") || t.contains("kvarh") || t.contains("energy");
}

private static File getTagRangeFile(){
    String cb = System.getProperty("catalina.base");
    if (cb != null && !cb.trim().isEmpty()) return new File(cb, "webapps/ROOT/WEB-INF/data/plc_tag_ranges.properties");
    String ch = System.getProperty("catalina.home");
    if (ch != null && !ch.trim().isEmpty()) return new File(ch, "webapps/ROOT/WEB-INF/data/plc_tag_ranges.properties");
    return new File("WEB-INF/data/plc_tag_ranges.properties");
}

private static void loadTagRangesFromFile() throws Exception {
    synchronized (TAG_RANGE_FILE_LOCK) {
        File f = getTagRangeFile();
        Map<String, TagRange> loaded = new HashMap<>();
        if (f.exists()) {
            Properties p = new Properties();
            FileInputStream fis = null;
            try {
                fis = new FileInputStream(f);
                p.load(fis);
            } finally {
                if (fis != null) try { fis.close(); } catch (Exception ignore) {}
            }
            for (String key : p.stringPropertyNames()) {
                if (key == null) continue;
                String token = key.trim().toUpperCase(Locale.ROOT);
                if (token.isEmpty()) continue;
                String raw = p.getProperty(key, "");
                String[] parts = raw.split("\\s*,\\s*");
                if (parts.length < 2) continue;
                try {
                    double min = Double.parseDouble(parts[0]);
                    double max = Double.parseDouble(parts[1]);
                    loaded.put(token, new TagRange(round2(Math.min(min, max)), round2(Math.max(min, max))));
                } catch (Exception ignore) {}
            }
        }
        TAG_RANGE_OVERRIDES.clear();
        TAG_RANGE_OVERRIDES.putAll(loaded);
    }
}

private static void flushTagRangesToFile() throws Exception {
    synchronized (TAG_RANGE_FILE_LOCK) {
        File f = getTagRangeFile();
        File parent = f.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();

        Properties p = new Properties();
        List<String> keys = new ArrayList<>(TAG_RANGE_OVERRIDES.keySet());
        Collections.sort(keys);
        for (String k : keys) {
            TagRange r = TAG_RANGE_OVERRIDES.get(k);
            if (r == null) continue;
            p.setProperty(k, String.format(Locale.US, "%.2f,%.2f", r.min, r.max));
        }
        FileOutputStream fos = null;
        try {
            fos = new FileOutputStream(f, false);
            p.store(fos, "plc_write tag range overrides");
        } finally {
            if (fos != null) try { fos.close(); } catch (Exception ignore) {}
        }
    }
}

private static void saveTagRangeToFile(String token, double min, double max) throws Exception {
    TAG_RANGE_OVERRIDES.put(token.trim().toUpperCase(Locale.ROOT), new TagRange(round2(Math.min(min,max)), round2(Math.max(min,max))));
    flushTagRangesToFile();
}

private static void clearTagRangesInFile() throws Exception {
    TAG_RANGE_OVERRIDES.clear();
    flushTagRangesToFile();
}

private static void ensureTagRangesLoaded() {
    if (!TAG_RANGE_OVERRIDES.isEmpty()) return;
    synchronized (TAG_RANGE_OVERRIDES) {
        if (!TAG_RANGE_OVERRIDES.isEmpty()) return;
        try { loadTagRangesFromFile(); } catch (Exception ignore) {}
    }
}
private static boolean isCurrentLikeToken(String token){
    String t = token == null ? "" : token.toLowerCase(Locale.ROOT);
    return t.contains("curr") || t.contains(" ia") || t.contains(" ib") || t.contains(" ic")
        || t.contains("_ia") || t.contains("_ib") || t.contains("_ic")
        || t.startsWith("i") || t.contains("thd-i");
}
private static boolean isVoltageLikeToken(String token){
    String t = token == null ? "" : token.toLowerCase(Locale.ROOT);
    return t.contains("volt") || t.contains(" va") || t.contains(" vb") || t.contains(" vc")
        || t.contains("_va") || t.contains("_vb") || t.contains("_vc")
        || t.startsWith("v") || t.contains("thd-v");
}
private static boolean isLineVoltageToken(String token){
    String t = token == null ? "" : token.toLowerCase(Locale.ROOT).trim();
    return t.contains("ll") || t.contains("line")
        || t.contains("v12") || t.contains("v23") || t.contains("v31")
        || t.contains("vab") || t.contains("vbc") || t.contains("vca")
        || "va".equals(t);
}
private static Character detectPhaseLetter(String token){
    if (token == null) return null;
    String s = token.toLowerCase(Locale.ROOT).trim();
    if (s.startsWith("h_")) return null; // harmonic tags are not phase-angle tags
    if (s.contains("pf") || s.contains("powerfactor")) return null;
    if (s.matches(".*\\bpi1\\b.*") || s.matches(".*\\bpv1\\b.*") || s.matches(".*\\bp1\\b.*")) return 'a';
    if (s.matches(".*\\bpi2\\b.*") || s.matches(".*\\bpv2\\b.*") || s.matches(".*\\bp2\\b.*")) return 'b';
    if (s.matches(".*\\bpi3\\b.*") || s.matches(".*\\bpv3\\b.*") || s.matches(".*\\bp3\\b.*")) return 'c';
    if (!(s.contains("angle") || s.contains("phase"))) return null;
    String[] parts = s.split("[^a-z0-9]+");
    for (String p : parts) {
        if ("a".equals(p) || "b".equals(p) || "c".equals(p)) return p.charAt(0);
        if (p.length() == 2 && (p.charAt(0) == 'v' || p.charAt(0) == 'i')) {
            char c = p.charAt(1);
            if (c == 'a' || c == 'b' || c == 'c') return c;
        }
        if (p.startsWith("phase") && p.length() >= 6) {
            char c = p.charAt(5);
            if (c == 'a' || c == 'b' || c == 'c') return c;
        }
        if (p.startsWith("angle") && p.length() >= 6) {
            char c = p.charAt(5);
            if (c == 'a' || c == 'b' || c == 'c') return c;
        }
    }
    return null;
}
private static double round2(double v){ return Math.round(v * 100.0d) / 100.0d; }
private static TagRange inferRange(String token){
    String raw = token == null ? "" : token.toLowerCase(Locale.ROOT).trim();
    String t = raw.replace(" ", "").replace("_", "");
    Character phByTag = detectPhaseLetter(token);
    if (phByTag != null && phByTag.charValue() == 'a') return new TagRange(-5.0, 5.0);
    if (phByTag != null && phByTag.charValue() == 'b') return new TagRange(-175.0, -165.0);
    if (phByTag != null && phByTag.charValue() == 'c') return new TagRange(165.0, 175.0);
    if (t.contains("thd") || t.contains("distortion") || raw.startsWith("h_")) {
        if (isCurrentLikeToken(token)) return new TagRange(2.0, 35.0);
        if (isVoltageLikeToken(token) || raw.startsWith("h_")) return new TagRange(0.5, 8.0);
        return new TagRange(0.5, 8.0);
    }
    if (t.contains("freq") || t.contains("hz")) return new TagRange(59.8, 60.2);
    if (t.contains("pf") || t.contains("powerfactor")) return new TagRange(0.85, 1.00);
    if (t.contains("angle") || t.contains("phase")) {
        Character ph = detectPhaseLetter(token);
        if (ph != null && ph.charValue() == 'a') return new TagRange(-5.0, 5.0);
        if (ph != null && ph.charValue() == 'b') return new TagRange(-175.0, -165.0);
        if (ph != null && ph.charValue() == 'c') return new TagRange(165.0, 175.0);
        return new TagRange(-180.0, 180.0);
    }
    if (t.contains("volt") || t.startsWith("v")) return isLineVoltageToken(token) ? new TagRange(342.0, 418.0) : new TagRange(215.0, 225.0);
    if (t.contains("curr") || t.startsWith("i")) return new TagRange(5.0, 450.0);
    if (isEnergyToken(token)) return new TagRange(1000.0, 9999999.0);
    if (t.contains("kw") || t.contains("kvar") || t.contains("kva") || t.contains("power")) return new TagRange(10.0, 12000.0);
    return new TagRange(0.0, 100.0);
}
private static TagRange getRange(String token){ ensureTagRangesLoaded(); TagRange ov = TAG_RANGE_OVERRIDES.get(token==null?"":token.trim().toUpperCase(Locale.ROOT)); return ov != null ? ov : inferRange(token); }
private static void setRange(String token, double min, double max){
    if(token==null||token.trim().isEmpty()) return;
    TAG_RANGE_OVERRIDES.put(token.trim().toUpperCase(Locale.ROOT), new TagRange(round2(Math.min(min,max)), round2(Math.max(min,max))));
}

private static int[] floatToRegs(float f, String byteOrder){ return PlcWriteSupport.floatToRegs(f, byteOrder); }
private static float regsToFloat(int reg1, int reg2, String byteOrder){ return PlcWriteSupport.regsToFloat(reg1, reg2, byteOrder); }

private static double nextValue(String plcKey, String token, TagRange r){
    double min=r.min,max=r.max; if (max<=min) return min; double span=max-min; ThreadLocalRandom rnd=ThreadLocalRandom.current(); String tn = token == null ? "" : token.toLowerCase(Locale.ROOT);
    if (isEnergyToken(tn)) {
        String key = plcKey + "|E|" + tn; Double prev = ENERGY_ACCUM_MAP.get(key); if (prev == null) prev = min + rnd.nextDouble() * Math.min(span * 0.1, span);
        double inc = Math.max(0.001, span * rnd.nextDouble(0.00001, 0.0002)); double cur = prev + inc; if (cur > max) cur = min + rnd.nextDouble() * Math.min(span * 0.1, span); cur = round2(cur); ENERGY_ACCUM_MAP.put(key, cur); return cur;
    }
    double center = min + (span * 0.5), v = center + rnd.nextGaussian() * span * 0.12; if (v < min) v = min; if (v > max) v = max; return round2(v);
}

private static int extractModbusExceptionCode(String msg){ return PlcWriteSupport.extractModbusExceptionCode(msg); }

private static AiWriteData writeAiRandom(int plcId, PlcConfig cfg) throws Exception {
    long t0=System.currentTimeMillis();
    List<Map<String,Object>> mapList=getCachedAiMap(plcId), out=new ArrayList<>();
    if(mapList==null||mapList.isEmpty()) return new AiWriteData(out,0,0,System.currentTimeMillis()-t0);

    Map<Integer, List<Map<String,Object>>> byMeter = new LinkedHashMap<>();
    for (Map<String,Object> m : mapList) {
        Integer meterId = (Integer)m.get("meter_id");
        if (meterId == null) continue;
        byMeter.computeIfAbsent(meterId, k -> new ArrayList<>()).add(m);
    }
    if (byMeter.isEmpty()) return new AiWriteData(out,0,0,System.currentTimeMillis()-t0);

    List<Integer> meterIds = new ArrayList<>(byMeter.keySet());
    Collections.sort(meterIds);

    int seq=1,totalFloat=0,meterWritten=0;
    try (ModbusTcpClient client = new ModbusTcpClient(cfg.ip, cfg.port)) {
        for (Integer meterIdObj : meterIds) {
            if (meterIdObj == null) continue;
            int meterId = meterIdObj.intValue();
            List<Map<String,Object>> selectedRows = byMeter.get(meterIdObj);
            if (selectedRows == null || selectedRows.isEmpty()) continue;
            boolean wroteCurrentMeter = false;
            for (Map<String,Object> m : selectedRows) {
                int start=(Integer)m.get("start_address"), cnt=(Integer)m.get("float_count"); String bo=(String)m.get("byte_order"); if(cnt<=0) continue;
                String[] toks=(String[])m.get("tokens"); if(toks==null) toks=new String[0]; int[] regs=new int[cnt*2];
                for(int i=0;i<cnt;i++){
                    String token=(i<toks.length&&toks[i]!=null&&!toks[i].trim().isEmpty())?toks[i].trim():("F"+(i+1)); TagRange tr=getRange(token); double val=nextValue(plcId+":"+meterId, token, tr); int[] pair=floatToRegs((float)val, bo);
                    regs[i*2]=pair[0]; regs[i*2+1]=pair[1];
                    double sentVal = (double)regsToFloat(pair[0], pair[1], bo);
                    Map<String,Object> row=new HashMap<>(); row.put("idx",seq++); row.put("meter_id",meterId); row.put("token",token); row.put("reg1",start+(i*2)); row.put("reg2",start+(i*2)+1); row.put("value",sentVal); row.put("range_min",tr.min); row.put("range_max",tr.max); out.add(row);
                }
                int offset = toHoldingOffset(start);
                try {
                    writeRegs(client, cfg.unitId, offset, regs);
                } catch (IOException e) {
                    int ex = extractModbusExceptionCode(e.getMessage());
                    String extra = (ex > 0) ? (", modbus_ex=" + ex) : "";
                    throw new IOException(
                        "AI write failed: plc_id=" + plcId +
                        ", meter_id=" + meterId +
                        ", unit_id=" + cfg.unitId +
                        ", ip=" + cfg.ip +
                        ", port=" + cfg.port +
                        ", start_address=" + start +
                        ", offset=" + offset +
                        ", reg_count=" + regs.length +
                        ", function=16" +
                        extra +
                        ", cause=" + e.getMessage(), e);
                }
                wroteCurrentMeter = true;
                totalFloat += cnt;
            }
            if (wroteCurrentMeter) meterWritten++;
        }
    }
    return new AiWriteData(out, meterWritten, totalFloat, Math.max(0L, System.currentTimeMillis()-t0));
}

private static DiWriteData writeDi10Pct(int plcId, PlcConfig cfg) throws Exception {
    long t0=System.currentTimeMillis(); List<Map<String,Object>> tags=getCachedDiTagMap(plcId), out=new ArrayList<>(); if(tags==null||tags.isEmpty()) return new DiWriteData(out,0,System.currentTimeMillis()-t0);
    LinkedHashMap<Integer,List<Map<String,Object>>> byAddr=new LinkedHashMap<>();
    for(Map<String,Object> t:tags){
        int addr=((Number)t.get("di_address")).intValue();
        byAddr.computeIfAbsent(addr, k -> new ArrayList<>()).add(t);
    }
    List<Integer> addrs=new ArrayList<>(byAddr.keySet()); if(addrs.isEmpty()) return new DiWriteData(out,0,System.currentTimeMillis()-t0);
    int total=addrs.size(), changeCount=(int)Math.ceil(total*0.20d); if(changeCount<1) changeCount=1; if(changeCount>total) changeCount=total;
    Collections.shuffle(addrs, ThreadLocalRandom.current()); Set<Integer> changedSet=new HashSet<>(); for(int i=0;i<changeCount;i++) changedSet.add(addrs.get(i));
    int seq=1;
    try (ModbusTcpClient client = new ModbusTcpClient(cfg.ip, cfg.port)) {
        TreeMap<Integer, Integer> changedRegs = new TreeMap<>();
        for (Integer addr : addrs) {
            List<Map<String,Object>> pts = byAddr.get(addr);
            if (pts == null || pts.isEmpty()) continue;
            String key = plcId + ":" + addr;
            Integer prevWord = DI_LAST_VALUE_MAP.get(key);
            int word = (prevWord == null) ? 0 : (prevWord.intValue() & 0xFFFF);

            // First-seen init: seed only configured bits so table starts with meaningful values.
            if (prevWord == null) {
                for (Map<String,Object> p : pts) {
                    int b = ((Number)p.get("bit_no")).intValue();
                    if (b < 0 || b > 15) continue;
                    int bitVal = ThreadLocalRandom.current().nextInt(2);
                    if (bitVal == 1) word |= (1 << b); else word &= ~(1 << b);
                }
            }

            boolean changed = changedSet.contains(addr);
            if (changed) {
                // Toggle one configured bit for this register.
                List<Integer> validBits = new ArrayList<>();
                for (Map<String,Object> p : pts) {
                    int b = ((Number)p.get("bit_no")).intValue();
                    if (b >= 0 && b <= 15 && !validBits.contains(Integer.valueOf(b))) validBits.add(Integer.valueOf(b));
                }
                if (!validBits.isEmpty()) {
                    int pick = validBits.get(ThreadLocalRandom.current().nextInt(validBits.size())).intValue();
                    word ^= (1 << pick);
                }
                changedRegs.put(Integer.valueOf(toHoldingOffset(addr.intValue())), Integer.valueOf(word & 0xFFFF));
            }

            DI_LAST_VALUE_MAP.put(key, Integer.valueOf(word & 0xFFFF));

            for (Map<String,Object> s : pts) {
                int pointId=((Number)s.get("point_id")).intValue(), bitNo=((Number)s.get("bit_no")).intValue();
                String tagName=String.valueOf(s.get("tag_name")==null?"":s.get("tag_name")), itemName=String.valueOf(s.get("item_name")==null?"":s.get("item_name")), panelName=String.valueOf(s.get("panel_name")==null?"":s.get("panel_name"));
                int bitVal = (bitNo >= 0 && bitNo <= 15) ? (((word >> bitNo) & 0x1) == 1 ? 1 : 0) : 0;
                Map<String,Object> row=new HashMap<>(); row.put("idx",seq++); row.put("point_id",pointId); row.put("di_address",addr); row.put("bit_no",bitNo); row.put("tag_name",tagName); row.put("item_name",itemName); row.put("panel_name",panelName); row.put("value",bitVal); row.put("changed",changed?1:0); out.add(row);
            }
        }
        if (!changedRegs.isEmpty()) {
            try {
                Integer batchStart = null, prevOffset = null;
                List<Integer> batchVals = new ArrayList<>();
                for (Map.Entry<Integer, Integer> e : changedRegs.entrySet()) {
                    int off = e.getKey().intValue();
                    int v = e.getValue().intValue() & 0xFFFF;
                    boolean canAppend = (batchStart != null && prevOffset != null && off == (prevOffset.intValue() + 1) && batchVals.size() < WRITE_MAX_REGS_PER_REQ);
                    if (!canAppend) {
                        if (batchStart != null && !batchVals.isEmpty()) {
                            int[] arr = new int[batchVals.size()];
                            for (int k=0;k<batchVals.size();k++) arr[k]=batchVals.get(k).intValue() & 0xFFFF;
                            writeRegs(client, cfg.unitId, batchStart.intValue(), arr);
                        }
                        batchStart = Integer.valueOf(off);
                        batchVals.clear();
                    }
                    batchVals.add(Integer.valueOf(v));
                    prevOffset = Integer.valueOf(off);
                }
                if (batchStart != null && !batchVals.isEmpty()) {
                    int[] arr = new int[batchVals.size()];
                    for (int k=0;k<batchVals.size();k++) arr[k]=batchVals.get(k).intValue() & 0xFFFF;
                    writeRegs(client, cfg.unitId, batchStart.intValue(), arr);
                }
            } catch (IOException e) {
                int ex = extractModbusExceptionCode(e.getMessage());
                String extra = (ex > 0) ? (", modbus_ex=" + ex) : "";
                throw new IOException(
                    "DI write failed: plc_id=" + plcId +
                    ", unit_id=" + cfg.unitId +
                    ", ip=" + cfg.ip +
                    ", port=" + cfg.port +
                    ", changed_count=" + changedRegs.size() +
                    ", function=16" +
                    extra +
                    ", cause=" + e.getMessage(), e);
            }
        }
    }
    return new DiWriteData(out, changeCount, Math.max(0L, System.currentTimeMillis()-t0));
}

private static WriteResult writePlcSample(int plcId){
    WriteResult r = new WriteResult(); long t0 = System.currentTimeMillis();
    try {
        PlcConfig cfg = getCachedPlcConfig(plcId);
        if(!cfg.exists || cfg.ip==null){ r.error="Selected PLC config not found."; return r; }
        if(!cfg.enabled){ r.error="Selected PLC is inactive."; return r; }
        AiWriteData ai = writeAiRandom(plcId, cfg);
        DiWriteData di = new DiWriteData(new ArrayList<Map<String,Object>>(), 0, 0L);
        try {
            di = writeDi10Pct(plcId, cfg);
        } catch (Exception diEx) {
            r.warning = "DI write skipped: " + diEx.getMessage();
        }

        r.aiRows=ai.rows; r.diRows=di.rows; r.aiMs=ai.durationMs; r.diMs=di.durationMs; r.totalMs=Math.max(0L, System.currentTimeMillis()-t0); r.ok=true;
        r.info="Write success. PLC "+plcId+" ("+cfg.ip+":"+cfg.port+", unit "+cfg.unitId+"), meters="+ai.meterWritten+", total_floats="+ai.totalFloat+", di_total="+di.rows.size()+", di_changed="+di.changedCount;
        if (r.warning != null && !r.warning.isEmpty()) r.info = r.info + " [WARN] " + r.warning;
        return r;
    } catch(Exception e){ r.error=e.getMessage(); return r; }
}

private static void applyWriteResultToState(WriteState st, WriteResult rr){
    if (st == null || rr == null) return;
    if (rr.ok) {
        st.successCount.incrementAndGet();
        st.writeCount.incrementAndGet();
        st.lastWriteMs = rr.totalMs;
        st.lastAiWriteMs = rr.aiMs;
        st.lastDiWriteMs = rr.diMs;
        st.lastAiRows = new ArrayList<>(rr.aiRows);
        st.lastDiRows = new ArrayList<>(rr.diRows);
        st.lastInfo = rr.info;
        st.lastError = "";
    } else {
        st.lastError = rr.error;
    }
    st.lastRunAt = System.currentTimeMillis();
}

private static void resetWriteStateForPolling(WriteState st, int pollingMs) {
    if (st == null) return;
    st.running = true;
    st.pollingMs = pollingMs;
    st.lastError = "";
}

private static WriteResult runWriteCycle(WriteState st, int plcId) {
    if (st != null) st.attemptCount.incrementAndGet();
    WriteResult rr = writePlcSample(plcId);
    applyWriteResultToState(st, rr);
    return rr;
}

private static void stopWriting(int plcId){ ScheduledFuture<?> old=WRITE_TASKS.remove(plcId); if(old!=null) old.cancel(false); getWriteState(plcId).running=false; }
private static void startWriting(final int plcId, final int pollingMs){
    stopWriting(plcId); final WriteState st=getWriteState(plcId); resetWriteStateForPolling(st, pollingMs);
    Runnable task=new Runnable(){ public void run(){ runWriteCycle(st, plcId); }};
    WRITE_TASKS.put(plcId, WRITE_EXEC.scheduleAtFixedRate(task, 0, pollingMs, TimeUnit.MILLISECONDS));
}

private static void appendAiRowsJson(StringBuilder s, List<Map<String,Object>> rows){
    s.append("["); for(int i=0;i<rows.size();i++){ Map<String,Object> r=rows.get(i); Number v=(Number)r.get("value"), mn=(Number)r.get("range_min"), mx=(Number)r.get("range_max");
        s.append("{\"idx\":").append(r.get("idx")).append(",\"meter_id\":").append(r.get("meter_id")).append(",\"token\":\"").append(escJson(String.valueOf(r.get("token")))).append("\",\"reg1\":").append(r.get("reg1")).append(",\"reg2\":").append(r.get("reg2")).append(",\"value\":").append(String.format(java.util.Locale.US,"%.2f", v==null?0.0:v.doubleValue())).append(",\"range_min\":").append(String.format(java.util.Locale.US,"%.2f", mn==null?0.0:mn.doubleValue())).append(",\"range_max\":").append(String.format(java.util.Locale.US,"%.2f", mx==null?0.0:mx.doubleValue())).append("}");
        if(i<rows.size()-1) s.append(",");
    } s.append("]");
}
private static void appendDiRowsJson(StringBuilder s, List<Map<String,Object>> rows){
    s.append("["); for(int i=0;i<rows.size();i++){ Map<String,Object> r=rows.get(i);
        s.append("{\"idx\":").append(r.get("idx")).append(",\"point_id\":").append(r.get("point_id")).append(",\"di_address\":").append(r.get("di_address")).append(",\"bit_no\":").append(r.get("bit_no")).append(",\"tag_name\":\"").append(escJson(String.valueOf(r.get("tag_name")))).append("\",\"item_name\":\"").append(escJson(String.valueOf(r.get("item_name")))).append("\",\"panel_name\":\"").append(escJson(String.valueOf(r.get("panel_name")))).append("\",\"value\":").append(r.get("value")).append(",\"changed\":").append(r.get("changed")).append("}");
        if(i<rows.size()-1) s.append(",");
    } s.append("]");
}
private static void appendRangesJson(StringBuilder s){
    ensureTagRangesLoaded();
    s.append("{"); List<String> keys=new ArrayList<>(TAG_RANGE_OVERRIDES.keySet()); Collections.sort(keys); boolean first=true;
    for(String k:keys){ TagRange r=TAG_RANGE_OVERRIDES.get(k); if(r==null) continue; if(!first) s.append(","); first=false; s.append("\"").append(escJson(k)).append("\":{\"min\":").append(String.format(java.util.Locale.US,"%.2f",r.min)).append(",\"max\":").append(String.format(java.util.Locale.US,"%.2f",r.max)).append("}"); }
    s.append("}");
}
private static void appendWriteStateJson(StringBuilder s, Integer id, WriteState st){
    long attempt = st.attemptCount.get(), success = st.successCount.get();
    s.append("{\"plc_id\":").append(id).append(",\"running\":").append(st.running ? "true" : "false")
     .append(",\"polling_ms\":").append(st.pollingMs)
     .append(",\"attempt_count\":").append(attempt)
     .append(",\"success_count\":").append(success)
     .append(",\"write_count\":").append(st.writeCount.get())
     .append(",\"last_write_ms\":").append(st.lastWriteMs)
     .append(",\"di_write_ms\":").append(st.lastDiWriteMs)
     .append(",\"ai_write_ms\":").append(st.lastAiWriteMs)
     .append(",\"last_run_at\":").append(st.lastRunAt)
     .append(",\"last_info\":\"").append(escJson(st.lastInfo)).append("\"")
     .append(",\"last_error\":\"").append(escJson(st.lastError)).append("\"");
}

private static WriteRequestContext buildWriteRequestContext(javax.servlet.http.HttpServletRequest req) {
    WriteRequestContext ctx = new WriteRequestContext();
    ctx.action = req.getParameter("action");
    String plcParam = req.getParameter("plc_id");
    try {
        if (plcParam != null && !plcParam.trim().isEmpty()) ctx.plcId = Integer.parseInt(plcParam.trim());
    } catch (Exception ignore) {
    }
    ctx.includeRows = "1".equals(req.getParameter("include_rows"));
    return ctx;
}

private static String buildWriteStatesJson(boolean includeRows) {
    StringBuilder s = new StringBuilder();
    s.append("{\"ok\":true,\"states\":[");
    List<Integer> ids = new ArrayList<>(WRITE_STATES.keySet());
    Collections.sort(ids);
    boolean first = true;
    for (Integer id : ids) {
        WriteState st = WRITE_STATES.get(id);
        if (st == null) continue;
        if (!first) s.append(",");
        first = false;
        appendWriteStateJson(s, id, st);
        if (includeRows) {
            s.append(",\"rows\":");
            appendAiRowsJson(s, st.lastAiRows);
            s.append(",\"di_rows\":");
            appendDiRowsJson(s, st.lastDiRows);
        }
        s.append("}");
    }
    s.append("]}");
    return s.toString();
}

private static String buildWriteResultJson(WriteResult rr) {
    StringBuilder s = new StringBuilder();
    s.append("{\"ok\":").append(rr.ok ? "true" : "false");
    if (rr.ok) {
        s.append(",\"info\":\"").append(escJson(rr.info)).append("\",\"rows\":");
        appendAiRowsJson(s, rr.aiRows);
        s.append(",\"di_rows\":");
        appendDiRowsJson(s, rr.diRows);
        s.append("}");
    } else {
        s.append(",\"error\":\"").append(escJson(rr.error)).append("\"}");
    }
    return s.toString();
}
%>
<%
WriteRequestContext reqCtx = buildWriteRequestContext(request);
if (reqCtx.action != null && !reqCtx.action.trim().isEmpty()) {
    response.setContentType("application/json; charset=UTF-8");

    if ("polling_status".equalsIgnoreCase(reqCtx.action)) {
        out.print(buildWriteStatesJson(false));
        return;
    }

    if ("polling_snapshot".equalsIgnoreCase(reqCtx.action)) {
        out.print(buildWriteStatesJson(reqCtx.includeRows));
        return;
    }

    if ("get_tag_ranges".equalsIgnoreCase(reqCtx.action)) {
        try { loadTagRangesFromFile(); } catch (Exception ignore) {}
        StringBuilder s = new StringBuilder();
        s.append("{\"ok\":true,\"ranges\":");
        appendRangesJson(s);
        s.append("}");
        out.print(s.toString());
        return;
    }

    if ("clear_tag_ranges".equalsIgnoreCase(reqCtx.action)) {
        try {
            clearTagRangesInFile();
            out.print("{\"ok\":true,\"info\":\"tag ranges cleared\"}");
        } catch (Exception e) {
            out.print("{\"ok\":false,\"error\":\"" + escJson(e.getMessage()) + "\"}");
        }
        return;
    }

    if ("set_tag_range".equalsIgnoreCase(reqCtx.action)) {
        String token = request.getParameter("token");
        String minParam = request.getParameter("min");
        String maxParam = request.getParameter("max");
        if (token == null || token.trim().isEmpty()) {
            out.print("{\"ok\":false,\"error\":\"token is required\"}");
            return;
        }
        try {
            double min = Double.parseDouble(minParam);
            double max = Double.parseDouble(maxParam);
            saveTagRangeToFile(token.trim().toUpperCase(Locale.ROOT), round2(Math.min(min,max)), round2(Math.max(min,max)));
            out.print("{\"ok\":true,\"info\":\"tag range saved\"}");
        } catch (Exception e) {
            out.print("{\"ok\":false,\"error\":\"" + escJson(e.getMessage()) + "\"}");
        }
        return;
    }

    if ("refresh_cache".equalsIgnoreCase(reqCtx.action)) {
        String scopeParam = request.getParameter("scope");
        String scope = (scopeParam == null || scopeParam.trim().isEmpty()) ? "all" : scopeParam.trim().toLowerCase(Locale.ROOT);

        boolean doConfig = "all".equals(scope) || "config".equals(scope);
        boolean doMap = "all".equals(scope) || "map".equals(scope);
        boolean doRuntime = "all".equals(scope) || "runtime".equals(scope);
        boolean doRange = "all".equals(scope) || "range".equals(scope);
        if (!doConfig && !doMap && !doRuntime && !doRange) {
            out.print("{\"ok\":false,\"error\":\"invalid scope\"}");
            return;
        }

        Integer targetPlcId = reqCtx.plcId;
        if (doConfig) invalidateConfigCache(targetPlcId);
        if (doMap) invalidateTagMapCache(targetPlcId);
        if (doRuntime) invalidateRuntimeValueCache(targetPlcId);
        if (doRange) TAG_RANGE_OVERRIDES.clear();

        String target = (targetPlcId == null) ? "all" : String.valueOf(targetPlcId);
        out.print("{\"ok\":true,\"info\":\"cache refreshed\",\"scope\":\"" + escJson(scope) + "\",\"target\":\"" + escJson(target) + "\"}");
        return;
    }

    if (reqCtx.plcId == null) {
        out.print("{\"ok\":false,\"error\":\"plc_id is required\"}");
        return;
    }

    if ("write".equalsIgnoreCase(reqCtx.action)) {
        WriteState st = getWriteState(reqCtx.plcId);
        WriteResult rr = runWriteCycle(st, reqCtx.plcId);
        out.print(buildWriteResultJson(rr));
        return;
    }

    if ("start_polling".equalsIgnoreCase(reqCtx.action)) {
        int pollingMs = 1000;
        try {
            PlcConfig cfg = getCachedPlcConfig(reqCtx.plcId);
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
        int writeSec = Math.max(1, (int)Math.round(pollingMs / 1000.0d));
        String secParam = request.getParameter("write_sec");
        if (secParam != null && !secParam.trim().isEmpty()) {
            try { writeSec = Integer.parseInt(secParam.trim()); } catch (Exception ignore) {}
        }
        if (writeSec <= 0) writeSec = 1;
        pollingMs = writeSec * 1000;
        startWriting(reqCtx.plcId, pollingMs);
        out.print("{\"ok\":true,\"info\":\"server write polling started (" + writeSec + "s)\"}");
        return;
    }

    if ("stop_polling".equalsIgnoreCase(reqCtx.action)) {
        stopWriting(reqCtx.plcId);
        out.print("{\"ok\":true,\"info\":\"server write polling stopped\"}");
        return;
    }

    out.print("{\"ok\":false,\"error\":\"unknown action\"}");
    return;
}
%>
<%
List<Map<String, Object>> plcList = new ArrayList<>();
Map<Integer, String> meterNameMap = new HashMap<>();
Map<Integer, String> meterPanelMap = new HashMap<>();
Set<String> knownTags = new TreeSet<>();
try (Connection conn = createConn()) {
    try (PreparedStatement ps = conn.prepareStatement("SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config ORDER BY plc_id");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            Map<String, Object> r = new HashMap<>();
            r.put("plc_id", rs.getInt("plc_id"));
            r.put("plc_ip", rs.getString("plc_ip"));
            r.put("plc_port", rs.getInt("plc_port"));
            r.put("unit_id", rs.getInt("unit_id"));
            r.put("polling_ms", rs.getInt("polling_ms"));
            r.put("enabled", rs.getBoolean("enabled"));
            plcList.add(r);
        }
    }
    try (PreparedStatement ps = conn.prepareStatement("SELECT meter_id, name, panel_name FROM dbo.meters ORDER BY meter_id");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            int meterId = rs.getInt("meter_id");
            meterNameMap.put(meterId, rs.getString("name"));
            meterPanelMap.put(meterId, rs.getString("panel_name"));
        }
    }
    try (PreparedStatement ps = conn.prepareStatement("SELECT metric_order FROM dbo.plc_meter_map WHERE enabled = 1");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            String metricOrder = rs.getString("metric_order");
            if (metricOrder == null || metricOrder.trim().isEmpty()) continue;
            String[] toks = metricOrder.split("\\s*,\\s*");
            for (String t : toks) if (t != null && !t.trim().isEmpty()) knownTags.add(t.trim());
        }
    }
} catch (Exception ignore) {}
%>
<html>
<head>
    <title>PLC Write Sample</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1300px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; } th { font-size: 11px; }
        .ctrl-col { width: 245px; min-width: 245px; }
        .ctrl { display: inline-flex; gap: 4px; flex-wrap: nowrap; white-space: nowrap; align-items: center; }
        .ctrl button { min-width: 0; padding: 1px 4px; font-size: 10px; line-height: 1.2; }
        .ctrl .btn-write-once { width: 52px; }
        .ctrl .btn-start, .ctrl .btn-stop { width: 40px; }
        .write-sec { width: 44px; height: 22px; padding: 1px 3px; font-size: 10px; }
        .plc-table th, .plc-table td { padding: 6px 8px; }
        .plc-table th:nth-child(1), .plc-table td:nth-child(1) { width: 48px; }
        .plc-table th:nth-child(2), .plc-table td:nth-child(2) { width: 170px; }
        .plc-table th:nth-child(3), .plc-table td:nth-child(3) { width: 58px; }
        .plc-table th:nth-child(4), .plc-table td:nth-child(4) { width: 58px; }
        .plc-table th:nth-child(5), .plc-table td:nth-child(5) { width: 66px; }
        .plc-table th:nth-child(6), .plc-table td:nth-child(6) { width: 58px; }
        .plc-table th:nth-child(8), .plc-table td:nth-child(8) { width: 58px; }
        .plc-table th:nth-child(9), .plc-table td:nth-child(9) { width: 84px; white-space: nowrap; }
        .plc-table th:nth-child(10), .plc-table td:nth-child(10) { width: 70px; white-space: nowrap; }
        .plc-table th:nth-child(11), .plc-table td:nth-child(11) { width: 70px; white-space: nowrap; }
        .data-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; align-items: start; }
        .range-help { margin: 6px 0 8px 0; font-size: 12px; color: #475569; }
        .range-edit { width: 100px; height: 28px; padding: 2px 6px; font-size: 12px; }
        .range-save { height: 28px; padding: 2px 8px; font-size: 11px; }
        .range-selected { background: #f5f9ff; }
        @media (max-width: 1100px) { .data-grid { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🤖 PLC 상태 / 샘플 쓰기</h2>
        <div class="inline-actions"><button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button></div>
    </div>
    <div class="info-box">
        PLC별로 랜덤 샘플값을 PLC로 write합니다.<br/>
        AI: 태그 특성 기반 랜덤 + 태그별 범위 오버라이드, DI: 전체 주소 중 10%만 값 변경 후 write
    </div>
    <div id="okBox" class="ok-box" style="display:none;"></div>
    <div id="errBox" class="err-box" style="display:none;"></div>

    <h3 style="margin-top:12px;">PLC 등록 상태</h3>
    <table class="plc-table">
        <thead><tr><th>plc_id</th><th>ip</th><th>port</th><th>unit_id</th><th>polling_ms</th><th>enabled</th><th class="ctrl-col">control</th><th>state</th><th>write_count</th><th>di_write_ms</th><th>ai_write_ms</th></tr></thead>
        <tbody>
        <% if (plcList.isEmpty()) { %>
        <tr><td colspan="11">등록된 PLC가 없습니다.</td></tr>
        <% } else { for (Map<String, Object> p : plcList) { boolean enabled = (Boolean)p.get("enabled"); int plcId = ((Number)p.get("plc_id")).intValue(); WriteState initSt = WRITE_STATES.get(plcId); boolean running = (initSt != null && initSt.running); %>
        <tr>
            <td><%= p.get("plc_id") %></td><td class="mono"><%= p.get("plc_ip") %></td><td><%= p.get("plc_port") %></td><td><%= p.get("unit_id") %></td><td><%= p.get("polling_ms") %></td>
            <td><% if (enabled) { %><span class="badge b-on">ACTIVE</span><% } else { %><span class="badge b-off">INACTIVE</span><% } %></td>
            <td class="ctrl-col"><div class="ctrl">
                <button type="button" class="btn-write-once" data-plc-id="<%= p.get("plc_id") %>" <%= enabled ? "" : "disabled" %>>쓰기 1회</button>
                <input type="number" min="1" step="1" class="write-sec" data-plc-id="<%= p.get("plc_id") %>" value="<%= Math.max(3, (int)Math.round(((Number)p.get("polling_ms")).doubleValue() / 1000.0d)) %>" title="write interval (sec)" <%= enabled ? "" : "disabled" %> />
                <button type="button" class="btn-start" data-plc-id="<%= p.get("plc_id") %>" <%= (enabled && !running) ? "" : "disabled" %>>시작</button>
                <button type="button" class="btn-stop" data-plc-id="<%= p.get("plc_id") %>" <%= running ? "" : "disabled" %>>중지</button>
            </div></td>
            <td id="state-<%= p.get("plc_id") %>"><%= enabled ? (running ? "running" : "idle") : "inactive" %></td>
            <td id="count-<%= p.get("plc_id") %>"><%= (initSt == null) ? "0" : String.valueOf(initSt.writeCount.get()) %></td><td id="dims-<%= p.get("plc_id") %>"><%= (initSt == null || initSt.lastDiWriteMs <= 0) ? "-" : (initSt.lastDiWriteMs + "ms") %></td><td id="aims-<%= p.get("plc_id") %>"><%= (initSt == null || initSt.lastAiWriteMs <= 0) ? "-" : (initSt.lastAiWriteMs + "ms") %></td>
        </tr>
        <% }} %>
        </tbody>
    </table>

    <h3 style="margin-top:12px;">AI 태그 랜덤 범위 설정</h3>
    <div class="range-help">
        리스트에서 태그를 선택하고 `min/max`를 바로 수정한 뒤 `저장`을 누르세요.
        <button type="button" id="btnPhasePreset" class="range-save" style="margin-left:8px;">위상각 A/B/C 기본값 일괄 적용</button>
        <button type="button" id="btnClearRanges" class="range-save" style="margin-left:6px;">범위 초기화</button>
        <button type="button" id="btnRefreshCache" class="range-save" style="margin-left:6px;">캐시 새로고침</button>
    </div>
    <table>
        <thead>
        <tr><th>tag</th><th>min</th><th>max</th><th>action</th></tr>
        </thead>
        <tbody id="rangeRows"><tr><td colspan="4">아직 범위 데이터가 없습니다.</td></tr></tbody>
    </table>

    <div style="display:flex; align-items:center; gap:8px; margin:10px 0;">
        <label for="meterFilter">meter:</label><select id="meterFilter"><option value="">전체</option></select>
    </div>

    <div class="data-grid">
        <div>
            <h3>AI Write 데이터 (float)</h3>
            <table><thead><tr><th>#</th><th>plc_id</th><th>meter_id</th><th>panel_name</th><th>tag</th><th>reg1</th><th>reg2</th><th>value_float</th></tr></thead><tbody id="writeRows"><tr><td colspan="8">아직 AI 데이터가 없습니다.</td></tr></tbody></table>
        </div>
        <div>
            <h3>DI Write 데이터 (bit)</h3>
            <table><thead><tr><th>#</th><th>plc_id</th><th>point_id</th><th>di_address</th><th>bit_no</th><th>tag_name</th><th>item_name</th><th>panel_name</th><th>value</th><th>changed</th></tr></thead><tbody id="diRows"><tr><td colspan="10">아직 DI 데이터가 없습니다.</td></tr></tbody></table>
        </div>
    </div>
</div>
<footer>짤 EPMS Dashboard | SNUT CNT</footer>
<script>
(function(){
  const API = 'plc_write.jsp';
  const meterNameMap = {
    <% boolean firstMeter = true; for (Map.Entry<Integer, String> e : meterNameMap.entrySet()) { %>
    <% if (!firstMeter) { %>,<% } %>"<%= e.getKey() %>":"<%= (e.getValue() == null ? "" : e.getValue().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")) %>"<% firstMeter = false; %>
    <% } %>
  };
  const meterPanelMap = {
    <% boolean firstPanel = true; for (Map.Entry<Integer, String> e : meterPanelMap.entrySet()) { %>
    <% if (!firstPanel) { %>,<% } %>"<%= e.getKey() %>":"<%= (e.getValue() == null ? "" : e.getValue().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")) %>"<% firstPanel = false; %>
    <% } %>
  };
  const knownTags = [
    <% boolean firstTag = true; for (String t : knownTags) { %>
    <% if (!firstTag) { %>,<% } %>"<%= t.replace("\\", "\\\\").replace("\"", "\\\"") %>"<% firstTag = false; %>
    <% } %>
  ];

  const okBox = document.getElementById('okBox');
  const errBox = document.getElementById('errBox');
  const rowsBody = document.getElementById('writeRows');
  const diRowsBody = document.getElementById('diRows');
  const meterFilter = document.getElementById('meterFilter');
  const rangeRows = document.getElementById('rangeRows');
  const btnPhasePreset = document.getElementById('btnPhasePreset');
  const btnClearRanges = document.getElementById('btnClearRanges');
  const btnRefreshCache = document.getElementById('btnRefreshCache');

  const lastRowsByPlc = {};
  const lastDiRowsByPlc = {};
  const lastWriteCountByPlc = {};
  let rangeOverrideMap = {};
  let snapshotLoading = false;
  let lastSnapshotRefreshAt = 0;
  let lastPollErrorAt = 0;

  function esc(s){ return String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;'); }
  function toNum(v){ const n = Number(v); return Number.isFinite(n) ? n : 0; }
  function showOk(msg){ if(!msg) return; okBox.style.display=''; okBox.textContent=msg; errBox.style.display='none'; }
  function showErr(msg){ if(!msg) return; errBox.style.display=''; errBox.textContent=msg; okBox.style.display='none'; }
  function ratioText(a,s){ const A=toNum(a), S=toNum(s); return A + '/' + S + '(' + (A>0?(S*100/A):0).toFixed(1) + '%)'; }
  function setState(plcId, txt, isErr){ const el=document.getElementById('state-'+plcId); if(!el) return; el.textContent=txt; el.style.color=isErr?'#b42318':'#334155'; }
  function setButtons(plcId, running){ const a=document.querySelector('.btn-start[data-plc-id="'+plcId+'"]'); const b=document.querySelector('.btn-stop[data-plc-id="'+plcId+'"]'); if(a) a.disabled=running; if(b) b.disabled=!running; }
  function getWriteSec(plcId){
    const el = document.querySelector('.write-sec[data-plc-id="'+plcId+'"]');
    if(!el) return 3;
    const n = parseInt(el.value || '3', 10);
    return Number.isFinite(n) && n > 0 ? n : 3;
  }
  function setCount(plcId, writeCount, attemptCount, successCount){
    const el=document.getElementById('count-'+plcId);
    if(!el) return;
    const w = toNum(writeCount);
    const a = toNum(attemptCount);
    const s = toNum(successCount);
    el.textContent = w + ' (A:' + a + ', S:' + s + ')';
  }
  function setMs(plcId, diMs, aiMs){ const d=document.getElementById('dims-'+plcId), a=document.getElementById('aims-'+plcId); if(!d||!a) return; d.textContent=toNum(diMs)>0?(toNum(diMs)+'ms'):'-'; a.textContent=toNum(aiMs)>0?(toNum(aiMs)+'ms'):'-'; }
  function netErrMsg(e){
    const msg = String((e && e.message) ? e.message : '');
    const name = String((e && e.name) ? e.name : '');
    if (name === 'AbortError' || msg.toLowerCase().includes('aborted')) return '요청 시간 초과';
    return msg || '요청 실패';
  }

  async function fetchJson(params, timeoutMs){
    const q = new URLSearchParams(params||{});
    q.set('_ts', Date.now());
    const ctrl = new AbortController();
    const ms = (Number.isFinite(Number(timeoutMs)) && Number(timeoutMs) > 0) ? Number(timeoutMs) : 12000;
    const tm = setTimeout(() => ctrl.abort('timeout'), ms);
    try {
      const res = await fetch(API + '?' + q.toString(), { cache: 'no-store', signal: ctrl.signal });
      return await res.json();
    } finally {
      clearTimeout(tm);
    }
  }

  function mergedRows(){
    const ids = Object.keys(lastRowsByPlc).sort((a,b)=>parseInt(a,10)-parseInt(b,10)); let idx=1; const out=[];
    ids.forEach(plcId => (lastRowsByPlc[plcId]||[]).forEach(r => out.push({ idx: idx++, plc_id: plcId, meter_id: r.meter_id, panel_name: meterPanelMap[String(r.meter_id)]||'', token: r.token, reg1: r.reg1, reg2: r.reg2, value: r.value, range_min:r.range_min, range_max:r.range_max })));
    return out;
  }
  function mergedDiRows(){
    const ids = Object.keys(lastDiRowsByPlc).sort((a,b)=>parseInt(a,10)-parseInt(b,10)); let idx=1; const out=[];
    ids.forEach(plcId => (lastDiRowsByPlc[plcId]||[]).forEach(r => out.push({ idx: idx++, plc_id: plcId, point_id:r.point_id, di_address:r.di_address, bit_no:r.bit_no, tag_name:r.tag_name, item_name:r.item_name, panel_name:r.panel_name, value:r.value, changed:r.changed })));
    return out;
  }

  function refreshMeterFilter(rows){
    const prev = meterFilter.value;
    const set = new Set(); (rows||[]).forEach(r => set.add(String(r.meter_id)));
    const meters = Array.from(set).sort((a,b)=>parseInt(a,10)-parseInt(b,10));
    let html = '<option value="">전체</option>';
    meters.forEach(m => {
      const nm = meterNameMap[m], pn = meterPanelMap[m], sx = pn ? (' / ' + pn) : '';
      const label = nm ? (nm + ' (#' + m + ')' + sx) : ('meter ' + m + sx);
      html += '<option value="' + m + '">' + esc(label) + '</option>';
    });
    meterFilter.innerHTML = html;
    meterFilter.value = meters.includes(prev) ? prev : '';
  }

  function renderRows(rows){
    const filterMeter = meterFilter.value, selectedPanel = filterMeter ? (meterPanelMap[filterMeter]||'') : '';
    const viewRows = (rows||[]).filter(r => !filterMeter ? true : (selectedPanel ? ((r.panel_name||'')===selectedPanel) : (String(r.meter_id)===filterMeter)));
    if(!viewRows.length){ rowsBody.innerHTML = '<tr><td colspan="8">아직 AI 데이터가 없습니다.</td></tr>'; return; }
    rowsBody.innerHTML = viewRows.map(r => '<tr><td>'+esc(r.idx)+'</td><td>'+esc(r.plc_id)+'</td><td>'+esc(r.meter_id)+'</td><td>'+esc(r.panel_name||'-')+'</td><td class="mono">'+esc(r.token)+'</td><td class="mono">'+esc(r.reg1)+'</td><td class="mono">'+esc(r.reg2)+'</td><td class="mono">'+esc(Number(r.value).toFixed(2))+'</td></tr>').join('');
  }
  function renderDiRows(rows){
    const filterMeter = meterFilter.value, selectedPanel = filterMeter ? (meterPanelMap[filterMeter]||'') : '';
    const viewRows = (rows||[]).filter(r => !filterMeter ? true : (selectedPanel ? ((r.panel_name||'')===selectedPanel) : false));
    if(!viewRows.length){ diRowsBody.innerHTML = '<tr><td colspan="10">아직 DI 데이터가 없습니다.</td></tr>'; return; }
    diRowsBody.innerHTML = viewRows.map(r => '<tr><td>'+esc(r.idx)+'</td><td>'+esc(r.plc_id)+'</td><td>'+esc(r.point_id)+'</td><td class="mono">'+esc(r.di_address)+'</td><td class="mono">'+esc(r.bit_no)+'</td><td>'+esc(r.tag_name||'-')+'</td><td>'+esc(r.item_name||'-')+'</td><td>'+esc(r.panel_name||'-')+'</td><td class="mono">'+esc(r.value)+'</td><td class="mono">'+(Number(r.changed)===1?'Y':'-')+'</td></tr>').join('');
  }

  function inferDefaultRange(tag){
    const raw = String(tag||'').toLowerCase();
    const t = raw.replaceAll(' ','').replaceAll('_','');
    const isCurrentLike = raw.includes('curr') || raw.includes(' ia') || raw.includes(' ib') || raw.includes(' ic')
      || raw.includes('_ia') || raw.includes('_ib') || raw.includes('_ic') || raw.startsWith('i') || raw.includes('thd-i');
    const isVoltageLike = raw.includes('volt') || raw.includes(' va') || raw.includes(' vb') || raw.includes(' vc')
      || raw.includes('_va') || raw.includes('_vb') || raw.includes('_vc') || raw.startsWith('v') || raw.includes('thd-v');
    const isLineVoltage = raw.includes('ll') || raw.includes('line')
      || raw.includes('v12') || raw.includes('v23') || raw.includes('v31')
      || raw.includes('vab') || raw.includes('vbc') || raw.includes('vca')
      || raw === 'va';
    const phByTag = detectPhaseForTag(tag);
    if (phByTag === 'a') return {min:-5,max:5};
    if (phByTag === 'b') return {min:-175,max:-165};
    if (phByTag === 'c') return {min:165,max:175};
    if (t.includes('thd') || t.includes('distortion') || raw.startsWith('h_')) {
      if (isCurrentLike) return {min:2,max:35};
      if (isVoltageLike || raw.startsWith('h_')) return {min:0.5,max:8};
      return {min:0.5,max:8};
    }
    if (t.includes('freq') || t.includes('hz')) return {min:59.8,max:60.2};
    if (t.includes('pf') || t.includes('powerfactor')) return {min:0.85,max:1.0};
    if (t.includes('angle') || t.includes('phase')) return {min:-180,max:180};
    if (t.includes('volt') || t.startsWith('v')) return isLineVoltage ? {min:342,max:418} : {min:215,max:225};
    if (t.includes('curr') || t.startsWith('i')) return {min:5,max:450};
    if (t.includes('kwh') || t.includes('kvarh') || t.includes('energy')) return {min:1000,max:9999999};
    if (t.includes('kw') || t.includes('kvar') || t.includes('kva') || t.includes('power')) return {min:10,max:12000};
    return {min:0,max:100};
  }
  function detectPhaseForTag(tag){
    const raw = String(tag||'').toLowerCase().trim();
    if(raw.startsWith('h_')) return null;
    if(raw.includes('pf') || raw.includes('powerfactor')) return null;
    if(/\bpi1\b/.test(raw) || /\bpv1\b/.test(raw) || /\bp1\b/.test(raw)) return 'a';
    if(/\bpi2\b/.test(raw) || /\bpv2\b/.test(raw) || /\bp2\b/.test(raw)) return 'b';
    if(/\bpi3\b/.test(raw) || /\bpv3\b/.test(raw) || /\bp3\b/.test(raw)) return 'c';
    if(!(raw.includes('angle') || raw.includes('phase'))) return null;
    const parts = raw.split(/[^a-z0-9]+/).filter(Boolean);
    for(const p of parts){
      if(p === 'a' || p === 'b' || p === 'c') return p;
      if(p.length === 2 && (p[0] === 'v' || p[0] === 'i') && (p[1] === 'a' || p[1] === 'b' || p[1] === 'c')) return p[1];
      if((p.startsWith('phase') || p.startsWith('angle')) && p.length >= 6){
        const c = p[5];
        if(c === 'a' || c === 'b' || c === 'c') return c;
      }
    }
    if(raw.includes('va')) return 'a';
    if(raw.includes('vb')) return 'b';
    if(raw.includes('vc')) return 'c';
    return null;
  }
  function getPhasePresetRange(tag){
    const ph = detectPhaseForTag(tag);
    if(ph === 'a') return {min:-5, max:5};
    if(ph === 'b') return {min:-175, max:-165};
    if(ph === 'c') return {min:165, max:175};
    return null;
  }
  function renderRanges(selectedTag){
    if(!knownTags.length){ rangeRows.innerHTML='<tr><td colspan="4">등록된 tag가 없습니다.</td></tr>'; return; }
    rangeRows.innerHTML = knownTags.map(tag => {
      const key = String(tag).toUpperCase();
      const r = rangeOverrideMap[key] || inferDefaultRange(tag);
      const selectedClass = (selectedTag && selectedTag.toUpperCase() === key) ? ' class="range-selected"' : '';
      const tagEncoded = encodeURIComponent(tag);
      return '<tr data-tag="' + tagEncoded + '"' + selectedClass + '>' +
        '<td class="mono">' + esc(tag) + '</td>' +
        '<td><input class="range-edit range-min" type="number" step="0.01" value="' + esc(Number(r.min).toFixed(2)) + '"/></td>' +
        '<td><input class="range-edit range-max" type="number" step="0.01" value="' + esc(Number(r.max).toFixed(2)) + '"/></td>' +
        '<td><button type="button" class="range-save">저장</button></td>' +
      '</tr>';
    }).join('');
  }
  async function loadRanges(){
    try {
      const data = await fetchJson({ action:'get_tag_ranges' });
      if(!data.ok) return;
      rangeOverrideMap = data.ranges || {};
      renderRanges();
    } catch(e){}
  }

  async function saveRangeFromRow(row){
    if(!row) return;
    const tag = decodeURIComponent(row.getAttribute('data-tag') || '');
    const minInput = row.querySelector('.range-min');
    const maxInput = row.querySelector('.range-max');
    const saveBtn = row.querySelector('.range-save');
    if(!tag || !minInput || !maxInput || !saveBtn){ showErr('입력 데이터가 올바르지 않습니다.'); return; }
    const min = Number(minInput.value);
    const max = Number(maxInput.value);
    if(!Number.isFinite(min) || !Number.isFinite(max)){ showErr('범위 값은 숫자여야 합니다.'); return; }
    if(saveBtn.disabled) return;
    saveBtn.disabled = true;
    try {
      const data = await fetchJson({ action:'set_tag_range', token:tag, min:min, max:max });
      if(!data.ok){ showErr(data.error || '범위 저장 실패'); return; }
      const key = String(tag).toUpperCase();
      rangeOverrideMap[key] = { min: Math.min(min, max), max: Math.max(min, max) };
      showOk('범위 저장 완료: ' + tag);
    } catch(e){
      showErr('통신 오류: ' + netErrMsg(e));
    } finally {
      saveBtn.disabled = false;
    }
  }
  async function applyPhasePresetAll(){
    const rows = Array.from(rangeRows.querySelectorAll('tr[data-tag]'));
    const targets = rows.filter(row => {
      const tag = decodeURIComponent(row.getAttribute('data-tag') || '');
      return !!getPhasePresetRange(tag);
    });
    if(!targets.length){ showErr('위상각 태그를 찾지 못했습니다.'); return; }
    let ok = 0;
    for(const row of targets){
      const tag = decodeURIComponent(row.getAttribute('data-tag') || '');
      const preset = getPhasePresetRange(tag);
      if(!preset) continue;
      const minInput = row.querySelector('.range-min');
      const maxInput = row.querySelector('.range-max');
      if(!minInput || !maxInput) continue;
      minInput.value = Number(preset.min).toFixed(2);
      maxInput.value = Number(preset.max).toFixed(2);
      await saveRangeFromRow(row);
      ok++;
    }
    showOk('위상각 기본값 적용/저장 완료: ' + ok + '건');
  }

  function applyStateUi(st){
    const plcId = String(st.plc_id);
    setButtons(plcId, !!st.running);
    setCount(plcId, st.write_count, st.attempt_count, st.success_count);
    setMs(plcId, st.di_write_ms, st.ai_write_ms);
    if (st.last_error) setState(plcId, st.running ? 'running(error)' : 'error', true);
    else if (st.running) setState(plcId, 'running', false);
    else setState(plcId, 'stopped', false);
  }

  async function refreshStatus(){
    try {
      const data = await fetchJson({ action:'polling_status' });
      if(!data.ok) return;
      let changed = false;
      (data.states || []).forEach(st => {
        const plcId = String(st.plc_id);
        const wc = Number(st.write_count || 0);
        if(lastWriteCountByPlc[plcId] !== wc){
          lastWriteCountByPlc[plcId] = wc;
          changed = true;
        }
        applyStateUi(st);
      });
      const now = Date.now();
      const periodicRefresh = (now - lastSnapshotRefreshAt) >= 2000;
      if(changed || periodicRefresh) {
        lastSnapshotRefreshAt = now;
        loadSnapshotRowsIfNeeded();
      }
    } catch(e){
      const now = Date.now();
      if ((now - lastPollErrorAt) > 4000) {
        showErr('상태 조회 실패: ' + netErrMsg(e));
        lastPollErrorAt = now;
      }
    }
  }
  async function loadSnapshot(includeRows){
    try {
      const data = await fetchJson({ action:'polling_snapshot', include_rows: includeRows ? 1 : 0 });
      if(!data.ok) return;
      const states = data.states || [];
      if(!states.length) return;
      Object.keys(lastRowsByPlc).forEach(k => delete lastRowsByPlc[k]);
      Object.keys(lastDiRowsByPlc).forEach(k => delete lastDiRowsByPlc[k]);
      states.forEach(st => {
        const plcId = String(st.plc_id);
        lastWriteCountByPlc[plcId] = Number(st.write_count || 0);
        lastRowsByPlc[plcId] = st.rows || [];
        lastDiRowsByPlc[plcId] = st.di_rows || [];
        applyStateUi(st);
      });
      const rows = mergedRows(); refreshMeterFilter(rows); renderRows(rows); renderDiRows(mergedDiRows());
    } catch(e){}
  }
  async function loadSnapshotRowsIfNeeded(){
    if(snapshotLoading) return;
    snapshotLoading = true;
    try { await loadSnapshot(true); }
    finally { snapshotLoading = false; }
  }

  async function writeOnce(plcId){
    try {
      const data = await fetchJson({ action:'write', plc_id:plcId });
      if(!data.ok){ showErr(data.error || '쓰기 실패'); await refreshStatus(); return; }
      showOk(data.info || '쓰기 성공');
      lastRowsByPlc[String(plcId)] = data.rows || [];
      lastDiRowsByPlc[String(plcId)] = data.di_rows || [];
      const rows = mergedRows(); refreshMeterFilter(rows); renderRows(rows); renderDiRows(mergedDiRows());
      await refreshStatus();
    } catch(e){ showErr('통신 오류: ' + netErrMsg(e)); }
  }
  async function startPolling(plcId){
    try {
      const sec = getWriteSec(plcId);
      const data = await fetchJson({ action:'start_polling', plc_id:plcId, write_sec:sec });
      if(!data.ok){ showErr(data.error || '서버 쓰기 시작 실패'); await refreshStatus(); return; }
      showOk(data.info || '서버 쓰기 시작'); setButtons(plcId, true); await writeOnce(plcId);
    } catch(e){ showErr('통신 오류: ' + netErrMsg(e)); }
  }
  async function stopPolling(plcId){
    try {
      setState(plcId, 'stopping...', false);
      setButtons(plcId, false);
      const data = await fetchJson({ action:'stop_polling', plc_id:plcId }, 5000);
      if(!data.ok){ showErr(data.error || '서버 쓰기 중지 실패'); return; }
      showOk(data.info || '서버 쓰기 중지');
      setState(plcId, 'stopped', false);
      setTimeout(() => { refreshStatus(); }, 150);
    } catch(e){ showErr('통신 오류: ' + netErrMsg(e)); }
  }

  document.querySelectorAll('.btn-write-once').forEach(btn => btn.addEventListener('click', () => writeOnce(btn.getAttribute('data-plc-id'))));
  document.querySelectorAll('.btn-start').forEach(btn => btn.addEventListener('click', () => startPolling(btn.getAttribute('data-plc-id'))));
  document.querySelectorAll('.btn-stop').forEach(btn => btn.addEventListener('click', () => stopPolling(btn.getAttribute('data-plc-id'))));
  meterFilter.addEventListener('change', function(){ renderRows(mergedRows()); renderDiRows(mergedDiRows()); });
  if(rangeRows) {
    rangeRows.addEventListener('click', async function(e){
      const tr = e.target.closest('tr[data-tag]');
      if(!tr) return;
      Array.from(rangeRows.querySelectorAll('tr[data-tag]')).forEach(r => r.classList.remove('range-selected'));
      tr.classList.add('range-selected');
      if(e.target.classList.contains('range-save')){
        await saveRangeFromRow(tr);
      }
    });
    rangeRows.addEventListener('keydown', async function(e){
      if(e.key !== 'Enter') return;
      const input = e.target.closest('.range-edit');
      if(!input) return;
      const tr = input.closest('tr[data-tag]');
      if(!tr) return;
      e.preventDefault();
      await saveRangeFromRow(tr);
    });
  }
  if(btnPhasePreset){
    btnPhasePreset.addEventListener('click', async function(){
      btnPhasePreset.disabled = true;
      try { await applyPhasePresetAll(); }
      finally { btnPhasePreset.disabled = false; }
    });
  }
  if(btnClearRanges){
    btnClearRanges.addEventListener('click', async function(){
      btnClearRanges.disabled = true;
      try {
        const data = await fetchJson({ action:'clear_tag_ranges' });
        if(!data.ok){ showErr(data.error || '범위 초기화 실패'); return; }
        rangeOverrideMap = {};
        renderRanges();
        showOk('범위 초기화 완료');
      } catch(e){
        showErr('통신 오류: ' + netErrMsg(e));
      } finally {
        btnClearRanges.disabled = false;
      }
    });
  }
  if(btnRefreshCache){
    btnRefreshCache.addEventListener('click', async function(){
      btnRefreshCache.disabled = true;
      try {
        const data = await fetchJson({ action:'refresh_cache', scope:'all' });
        if(!data.ok){ showErr(data.error || '캐시 새로고침 실패'); return; }
        showOk('캐시 새로고침 완료');
      } catch(e){
        showErr('통신 오류: ' + netErrMsg(e));
      } finally {
        btnRefreshCache.disabled = false;
      }
    });
  }

  async function init(){
    await Promise.all([loadSnapshot(false), refreshStatus(), loadRanges()]);
    setTimeout(() => { loadSnapshotRowsIfNeeded(); }, 300);
    setInterval(refreshStatus, 2000);
  }
  init();
})();
</script>
</body>
</html>
