package epms.util;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.math.BigDecimal;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class UpsSimulatorSupport {
    public static final String SIM_IP = "127.0.0.1";
    public static final int SIM_MODBUS_PORT = 1502;
    public static final String STATUS_URL = "http://127.0.0.1:1503/api/status";

    private UpsSimulatorSupport() {
    }

    public static boolean isSimulatorDevice(Map<String, Object> device) {
        if (device == null) return false;
        return SIM_IP.equals(String.valueOf(device.get("ip_address")))
            && String.valueOf(SIM_MODBUS_PORT).equals(String.valueOf(device.get("modbus_port")));
    }

    public static String readStatus(int timeoutMs) {
        return readUrl(STATUS_URL, timeoutMs);
    }

    public static String readUrl(String urlText, int timeoutMs) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlText);
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setRequestMethod("GET");
            try (BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream(), "UTF-8"))) {
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) sb.append(line);
                return sb.toString();
            }
        } catch (Exception ignore) {
            return null;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    public static BigDecimal jsonDecimal(String json, String key) {
        if (json == null) return null;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)");
            Matcher m = p.matcher(json);
            return m.find() ? new BigDecimal(m.group(1)) : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    public static boolean jsonBool(String json, String key, boolean fallback) {
        if (json == null) return fallback;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*(true|false)");
            Matcher m = p.matcher(json);
            return m.find() ? Boolean.parseBoolean(m.group(1)) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static int jsonInt(String json, String key, int fallback) {
        if (json == null) return fallback;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+)");
            Matcher m = p.matcher(json);
            return m.find() ? Integer.parseInt(m.group(1)) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static String jsonText(String json, String key, String fallback) {
        if (json == null) return fallback;
        try {
            Pattern p = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"");
            Matcher m = p.matcher(json);
            return m.find() ? m.group(1) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    public static void putJsonDecimal(Map<String, Object> target, String json, String jsonKey, String metricKey) {
        BigDecimal value = jsonDecimal(json, jsonKey);
        if (value != null) target.put(metricKey, value);
    }
}
