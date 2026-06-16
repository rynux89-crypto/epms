package epms.ups;

import epms.util.UpsDataSourceProvider;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.InputStreamReader;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.servlet.ServletContext;

public final class UpsSystemSetupService {
    private UpsSystemSetupService() {
    }

    public static String initSchema(ServletContext ctx) throws Exception {
        Connection adminConn = null;
        try {
            Map<String, String> cfg = loadConfigToml(ctx);
            String server = firstNonBlank(System.getenv("UPS_DB_SERVER"), cfg.get("ups_database.server"));
            String user = firstNonBlank(System.getenv("UPS_DB_USER"), cfg.get("ups_database.user"));
            String password = firstNonNull(System.getenv("UPS_DB_PASSWORD"), cfg.get("ups_database.password"));
            String encrypt = firstNonBlank(System.getenv("UPS_DB_ENCRYPT"), cfg.get("ups_database.encrypt"), "true");
            String trust = firstNonBlank(System.getenv("UPS_DB_TRUST_SERVER_CERTIFICATE"), cfg.get("ups_database.trust_server_certificate"), "true");

            Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
            String url = "jdbc:sqlserver://" + normalizeSqlServerHost(server) +
                ";databaseName=master;encrypt=" + encrypt + ";trustServerCertificate=" + trust + ";loginTimeout=5;";
            adminConn = DriverManager.getConnection(url, user, password);
            for (String batch : splitSqlBatches(readSchemaSql(ctx))) {
                try (Statement st = adminConn.createStatement()) {
                    st.execute(batch);
                }
            }
            return "UPS_MONITOR 데이터베이스와 기본 테이블을 초기화했습니다.";
        } finally {
            closeQuietly(adminConn);
        }
    }

    public static String clearHistory() throws Exception {
        Connection conn = null;
        try {
            conn = UpsDataSourceProvider.resolveDataSource().getConnection();
            conn.setAutoCommit(false);
            int alarmDeleted;
            int measurementDeleted;
            int commDeleted;
            try (Statement st = conn.createStatement()) {
                alarmDeleted = st.executeUpdate("DELETE FROM dbo.ups_alarm_log");
                commDeleted = st.executeUpdate("DELETE FROM dbo.ups_comm_status");
                measurementDeleted = st.executeUpdate("DELETE FROM dbo.ups_measurement");
                st.executeUpdate("UPDATE dbo.ups_device SET last_comm_status='UNKNOWN', last_success_at=NULL, last_error_at=NULL, last_error_message=NULL, updated_at=sysdatetime()");
            }
            conn.commit();
            return "UPS 이력 데이터를 삭제했습니다. 측정 " + measurementDeleted + "건, 알람 " + alarmDeleted + "건, 통신상태 " + commDeleted + "건";
        } catch (Exception e) {
            if (conn != null) {
                try {
                    conn.rollback();
                } catch (Exception ignore) {
                }
            }
            throw e;
        } finally {
            if (conn != null) {
                try {
                    conn.setAutoCommit(true);
                } catch (Exception ignore) {
                }
            }
            closeQuietly(conn);
        }
    }

    public static Map<String, Object> loadStatus(ServletContext application) {
        Map<String, Object> out = new HashMap<String, Object>();
        out.put("canConnect", Boolean.FALSE);
        out.put("connectError", null);
        out.put("deviceCount", Integer.valueOf(0));
        out.put("profileCount", Integer.valueOf(0));
        out.put("pointCount", Integer.valueOf(0));
        out.put("alarmCount", Integer.valueOf(0));
        out.put("measurementCount", Integer.valueOf(0));
        out.put("commCount", Integer.valueOf(0));
        out.put("collectorStatus", appString(application, "ups.collector.status", "UNKNOWN"));
        out.put("collectorLastStart", appObject(application, "ups.collector.lastStartAt"));
        out.put("collectorLastSuccess", appObject(application, "ups.collector.lastSuccessAt"));
        out.put("collectorLastErrorAt", appObject(application, "ups.collector.lastErrorAt"));
        out.put("collectorLastDuration", appObject(application, "ups.collector.lastDurationMs"));
        out.put("collectorLastError", appObject(application, "ups.collector.lastError"));
        out.put("collectorInterval", appObject(application, "ups.collector.intervalSeconds"));

        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            out.put("canConnect", Boolean.TRUE);
            out.put("deviceCount", Integer.valueOf(countTable(conn, "dbo.ups_device")));
            out.put("profileCount", Integer.valueOf(countTable(conn, "dbo.ups_modbus_profile")));
            out.put("pointCount", Integer.valueOf(countTable(conn, "dbo.ups_modbus_point")));
            out.put("alarmCount", Integer.valueOf(countTable(conn, "dbo.ups_alarm_log")));
            out.put("measurementCount", Integer.valueOf(countTable(conn, "dbo.ups_measurement")));
            out.put("commCount", Integer.valueOf(countTable(conn, "dbo.ups_comm_status")));
        } catch (Exception e) {
            out.put("connectError", e.getMessage());
        }
        return out;
    }

    private static Object appObject(ServletContext application, String key) {
        return application == null ? null : application.getAttribute(key);
    }

    private static String appString(ServletContext application, String key, String fallback) {
        Object value = appObject(application, key);
        if (value == null || "null".equals(String.valueOf(value))) {
            return fallback;
        }
        return String.valueOf(value);
    }

    private static int countTable(Connection conn, String tableName) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM " + tableName);
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    private static String readSchemaSql(ServletContext ctx) throws Exception {
        return readSqlFile(ctx, "/scripts/create_ups_monitor.sql") +
            "\n--GO--\n" +
            readSqlFile(ctx, "/scripts/create_schneider_easy_ups_profile.sql");
    }

    private static String readSqlFile(ServletContext ctx, String webPath) throws Exception {
        String path = ctx == null ? null : ctx.getRealPath(webPath);
        if (path == null) {
            throw new FileNotFoundException(webPath);
        }
        BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(path), "UTF-8"));
        StringBuilder sb = new StringBuilder();
        try {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.trim().equalsIgnoreCase("GO")) {
                    sb.append("\n--GO--\n");
                } else {
                    sb.append(line).append('\n');
                }
            }
        } finally {
            closeQuietly(reader);
        }
        return sb.toString();
    }

    private static List<String> splitSqlBatches(String sql) {
        List<String> out = new ArrayList<String>();
        if (sql == null) {
            return out;
        }
        String[] chunks = sql.split("(?m)^--GO--$");
        for (String chunk : chunks) {
            String x = chunk == null ? "" : chunk.trim();
            if (x.length() > 0) {
                out.add(x);
            }
        }
        return out;
    }

    private static Map<String, String> loadConfigToml(ServletContext ctx) {
        Map<String, String> out = new HashMap<String, String>();
        File file = configFile(ctx);
        if (file == null || !file.isFile()) {
            return out;
        }
        String section = null;
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            String rawLine;
            while ((rawLine = reader.readLine()) != null) {
                String line = rawLine.trim();
                if (line.length() == 0 || line.startsWith("#")) {
                    continue;
                }
                if (line.startsWith("[") && line.endsWith("]") && line.length() > 2) {
                    section = line.substring(1, line.length() - 1).trim();
                    continue;
                }
                int eq = line.indexOf('=');
                if (eq <= 0) {
                    continue;
                }
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();
                int commentIdx = value.indexOf(" #");
                if (commentIdx >= 0) {
                    value = value.substring(0, commentIdx).trim();
                }
                if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
                    value = value.substring(1, value.length() - 1);
                }
                out.put((section == null || section.length() == 0) ? key : section + "." + key, value);
            }
        } catch (Exception ignore) {
        } finally {
            closeQuietly(reader);
        }
        return out;
    }

    private static File configFile(ServletContext ctx) {
        try {
            String path = ctx == null ? null : ctx.getRealPath("/WEB-INF/config.toml");
            return path == null || path.length() == 0 ? null : new File(path);
        } catch (Exception ignore) {
            return null;
        }
    }

    private static String firstNonBlank(String... values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (value != null && value.trim().length() > 0) {
                return value;
            }
        }
        return null;
    }

    private static String firstNonNull(String... values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (value != null) {
                return value;
            }
        }
        return null;
    }

    private static String normalizeSqlServerHost(String server) {
        String s = server == null ? "" : server.trim();
        if (s.matches("^[^\\\\,]+,\\d+$")) {
            return s.replace(',', ':');
        }
        return s;
    }

    private static void closeQuietly(AutoCloseable closeable) {
        if (closeable == null) {
            return;
        }
        try {
            closeable.close();
        } catch (Exception ignore) {
        }
    }
}
