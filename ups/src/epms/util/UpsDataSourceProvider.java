package epms.util;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;
import java.util.logging.Logger;
import javax.naming.InitialContext;
import javax.naming.NamingException;
import javax.sql.DataSource;

public final class UpsDataSourceProvider {
    private static final String DB_JNDI_NAME = "java:comp/env/jdbc/ups";
    private static final Object LOCK = new Object();
    private static volatile DataSource cachedDataSource = null;

    private UpsDataSourceProvider() {
    }

    public static DataSource resolveDataSource() throws Exception {
        DataSource ds = cachedDataSource;
        if (ds != null) {
            return ds;
        }

        synchronized (LOCK) {
            if (cachedDataSource != null) {
                return cachedDataSource;
            }

            InitialContext ic = null;
            NamingException lastError = null;
            try {
                ic = new InitialContext();
                String[] names = new String[]{DB_JNDI_NAME, "jdbc/ups"};
                for (String name : names) {
                    try {
                        Object obj = ic.lookup(name);
                        if (obj instanceof DataSource) {
                            cachedDataSource = (DataSource) obj;
                            return cachedDataSource;
                        }
                    } catch (NamingException ne) {
                        lastError = ne;
                    }
                }
            } finally {
                try {
                    if (ic != null) {
                        ic.close();
                    }
                } catch (Exception ignore) {
                }
            }

            cachedDataSource = new DirectConfigDataSource(loadDirectConfig(lastError));
            return cachedDataSource;
        }
    }

    private static Map<String, String> loadDirectConfig(Exception primaryError) throws Exception {
        Map<String, String> fileConfig = loadConfigToml();
        Map<String, String> cfg = new HashMap<String, String>();
        cfg.put("server", firstNonBlank(System.getenv("UPS_DB_SERVER"), fileConfig.get("ups_database.server")));
        cfg.put("name", firstNonBlank(System.getenv("UPS_DB_NAME"), fileConfig.get("ups_database.name")));
        cfg.put("user", firstNonBlank(System.getenv("UPS_DB_USER"), fileConfig.get("ups_database.user")));
        cfg.put("password", firstNonNull(System.getenv("UPS_DB_PASSWORD"), fileConfig.get("ups_database.password")));
        cfg.put("encrypt", firstNonBlank(System.getenv("UPS_DB_ENCRYPT"), fileConfig.get("ups_database.encrypt"), "true"));
        cfg.put("trust", firstNonBlank(System.getenv("UPS_DB_TRUST_SERVER_CERTIFICATE"), fileConfig.get("ups_database.trust_server_certificate"), "true"));
        if (isBlank(cfg.get("server")) || isBlank(cfg.get("name")) || isBlank(cfg.get("user")) || cfg.get("password") == null) {
            NamingException e = new NamingException("UPS database settings are incomplete. Configure JNDI jdbc/ups or WEB-INF/config.toml [ups_database].");
            if (primaryError != null) e.addSuppressed(primaryError);
            throw e;
        }
        return cfg;
    }

    private static Map<String, String> loadConfigToml() {
        Map<String, String> out = new HashMap<String, String>();
        File file = findConfigFile();
        if (file == null || !file.isFile()) return out;
        String section = null;
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            String rawLine;
            while ((rawLine = reader.readLine()) != null) {
                String line = rawLine.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                if (line.startsWith("[") && line.endsWith("]") && line.length() > 2) {
                    section = line.substring(1, line.length() - 1).trim();
                    continue;
                }
                int eq = line.indexOf('=');
                if (eq <= 0) continue;
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();
                int commentIdx = value.indexOf(" #");
                if (commentIdx >= 0) value = value.substring(0, commentIdx).trim();
                if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
                    value = value.substring(1, value.length() - 1);
                }
                out.put((section == null || section.isEmpty()) ? key : section + "." + key, value);
            }
        } catch (Exception ignore) {
        } finally {
            try {
                if (reader != null) reader.close();
            } catch (Exception ignore) {
            }
        }
        return out;
    }

    private static File findConfigFile() {
        String catalinaBase = System.getProperty("catalina.base");
        String userDir = System.getProperty("user.dir");
        String[] paths = new String[] {
            catalinaBase == null ? null : catalinaBase + File.separator + "webapps" + File.separator + "ups" + File.separator + "WEB-INF" + File.separator + "config.toml",
            catalinaBase == null ? null : catalinaBase + File.separator + "webapps" + File.separator + "ROOT" + File.separator + "ups" + File.separator + "WEB-INF" + File.separator + "config.toml",
            userDir == null ? null : userDir + File.separator + "ups" + File.separator + "WEB-INF" + File.separator + "config.toml"
        };
        for (String path : paths) {
            if (path == null) continue;
            File f = new File(path);
            if (f.isFile()) return f;
        }
        return null;
    }

    private static String firstNonBlank(String... values) {
        if (values == null) return null;
        for (String value : values) {
            if (!isBlank(value)) return value;
        }
        return null;
    }

    private static String firstNonNull(String... values) {
        if (values == null) return null;
        for (String value : values) {
            if (value != null) return value;
        }
        return null;
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private static String normalizeSqlServerHost(String server) {
        String s = server == null ? "" : server.trim();
        if (s.matches("^[^\\\\,]+,\\d+$")) return s.replace(',', ':');
        return s;
    }

    private static final class DirectConfigDataSource implements DataSource {
        private final Map<String, String> cfg;

        DirectConfigDataSource(Map<String, String> cfg) {
            this.cfg = cfg;
        }

        @Override
        public Connection getConnection() throws SQLException {
            try {
                Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
            } catch (ClassNotFoundException e) {
                throw new SQLException("SQL Server JDBC driver not found.", e);
            }
            String url = "jdbc:sqlserver://" + normalizeSqlServerHost(cfg.get("server")) +
                ";databaseName=" + cfg.get("name").trim() +
                ";encrypt=" + cfg.get("encrypt").trim() +
                ";trustServerCertificate=" + cfg.get("trust").trim() +
                ";loginTimeout=5;";
            return DriverManager.getConnection(url, cfg.get("user").trim(), cfg.get("password"));
        }

        @Override
        public Connection getConnection(String username, String password) throws SQLException {
            return getConnection();
        }

        @Override
        public PrintWriter getLogWriter() throws SQLException {
            return null;
        }

        @Override
        public void setLogWriter(PrintWriter out) throws SQLException {
        }

        @Override
        public void setLoginTimeout(int seconds) throws SQLException {
        }

        @Override
        public int getLoginTimeout() throws SQLException {
            return 5;
        }

        @Override
        public Logger getParentLogger() {
            return Logger.getGlobal();
        }

        @Override
        public <T> T unwrap(Class<T> iface) throws SQLException {
            throw new SQLException("Not a wrapper.");
        }

        @Override
        public boolean isWrapperFor(Class<?> iface) throws SQLException {
            return false;
        }
    }
}
