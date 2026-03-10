package epms.util;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.servlet.http.HttpServletRequest;

public final class ModbusSupport {
    private ModbusSupport() {
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
