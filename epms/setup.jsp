<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.io.*" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
private String nv(String value, String fallback) {
    if (value == null) return fallback;
    String trimmed = value.trim();
    return trimmed.isEmpty() ? fallback : trimmed;
}

private String q(String value) {
    String v = value == null ? "" : value;
    return "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
}

private File getConfigFile() {
    String path = getServletContext().getRealPath("/WEB-INF/config.toml");
    if (path == null || path.isEmpty()) return null;
    return new File(path);
}

private Map<String, String> loadToml(File file) {
    Map<String, String> out = new LinkedHashMap<String, String>();
    if (file == null || !file.exists() || !file.isFile()) return out;

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
            String fullKey = (section == null || section.isEmpty()) ? key : (section + "." + key);
            out.put(fullKey, value);
        }
    } catch (Exception ignore) {
    } finally {
        try { if (reader != null) reader.close(); } catch (Exception ignore) {}
    }
    return out;
}

private void saveToml(File file, Map<String, String> cfg) throws Exception {
    if (file == null) throw new IOException("Config path unavailable");
    File parent = file.getParentFile();
    if (parent != null && !parent.exists()) parent.mkdirs();

    StringBuilder sb = new StringBuilder();
    sb.append("[app]\n");
    sb.append("name = ").append(q(nv(cfg.get("app.name"), "EPMS"))).append('\n');
    sb.append("base_url = ").append(q(nv(cfg.get("app.base_url"), "http://localhost:8080"))).append("\n\n");

    sb.append("[database]\n");
    sb.append("jndi_name = ").append(q(nv(cfg.get("database.jndi_name"), "java:comp/env/jdbc/epms"))).append('\n');
    sb.append("server = ").append(q(nv(cfg.get("database.server"), "localhost,1433"))).append('\n');
    sb.append("name = ").append(q(nv(cfg.get("database.name"), "EPMS"))).append('\n');
    sb.append("user = ").append(q(nv(cfg.get("database.user"), "sa"))).append('\n');
    sb.append("password = ").append(q(nv(cfg.get("database.password"), ""))).append('\n');
    sb.append("encrypt = ").append(q(nv(cfg.get("database.encrypt"), "true"))).append('\n');
    sb.append("trust_server_certificate = ").append(q(nv(cfg.get("database.trust_server_certificate"), "true"))).append("\n\n");

    sb.append("[backup]\n");
    sb.append("dir = ").append(q(nv(cfg.get("backup.dir"), "C:\\backup"))).append('\n');
    sb.append("retain_days = ").append(nv(cfg.get("backup.retain_days"), "7")).append('\n');
    sb.append("schedule = ").append(q(nv(cfg.get("backup.schedule"), "02:00"))).append("\n\n");

    sb.append("[plc]\n");
    sb.append("default_polling_ms = ").append(nv(cfg.get("plc.default_polling_ms"), "3000")).append('\n');
    sb.append("default_write_interval_sec = ").append(nv(cfg.get("plc.default_write_interval_sec"), "3")).append("\n\n");

    sb.append("[agent]\n");
    sb.append("properties_path = ").append(q(nv(cfg.get("agent.properties_path"), "epms/agent_model.properties"))).append('\n');

    Writer writer = null;
    try {
        writer = new OutputStreamWriter(new FileOutputStream(file), "UTF-8");
        writer.write(sb.toString());
    } finally {
        try { if (writer != null) writer.close(); } catch (Exception ignore) {}
    }
}

private Connection openSqlServerConnection(String server, String databaseName, String user, String password, String encrypt, String trustServerCertificate) throws Exception {
    Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
    String url =
        "jdbc:sqlserver://" + server +
        ";databaseName=" + databaseName +
        ";encrypt=" + encrypt +
        ";trustServerCertificate=" + trustServerCertificate +
        ";loginTimeout=5;";
    return DriverManager.getConnection(url, user, password);
}

private boolean databaseExists(Connection conn, String dbName) throws Exception {
    PreparedStatement ps = null;
    ResultSet rs = null;
    try {
        ps = conn.prepareStatement("SELECT CASE WHEN DB_ID(?) IS NULL THEN 0 ELSE 1 END");
        ps.setString(1, dbName);
        rs = ps.executeQuery();
        return rs.next() && rs.getInt(1) == 1;
    } finally {
        try { if (rs != null) rs.close(); } catch (Exception ignore) {}
        try { if (ps != null) ps.close(); } catch (Exception ignore) {}
    }
}

private boolean tableExists(Connection conn, String tableName) throws Exception {
    PreparedStatement ps = null;
    ResultSet rs = null;
    try {
        ps = conn.prepareStatement("SELECT CASE WHEN OBJECT_ID(?, 'U') IS NULL THEN 0 ELSE 1 END");
        ps.setString(1, tableName);
        rs = ps.executeQuery();
        return rs.next() && rs.getInt(1) == 1;
    } finally {
        try { if (rs != null) rs.close(); } catch (Exception ignore) {}
        try { if (ps != null) ps.close(); } catch (Exception ignore) {}
    }
}

private String readScript(String relativePath) throws Exception {
    String fullPath = getServletContext().getRealPath(relativePath);
    if (fullPath == null || fullPath.isEmpty()) {
        throw new IOException("Unable to resolve script path: " + relativePath);
    }
    StringBuilder sb = new StringBuilder();
    BufferedReader reader = null;
    try {
        reader = new BufferedReader(new InputStreamReader(new FileInputStream(fullPath), "UTF-8"));
        String line;
        while ((line = reader.readLine()) != null) {
            sb.append(line).append('\n');
        }
    } finally {
        try { if (reader != null) reader.close(); } catch (Exception ignore) {}
    }
    return sb.toString();
}

private String adaptSchemaScript(String sql, String dbName) {
    String escaped = dbName.replace("]", "]]").replace("'", "''");
    String out = sql;
    out = out.replace("DB_ID(N'epms')", "DB_ID(N'" + escaped + "')");
    out = out.replace("CREATE DATABASE [epms]", "CREATE DATABASE [" + escaped + "]");
    out = out.replace("USE [epms];", "USE [" + escaped + "];");
    out = out.replace("USE [epms]", "USE [" + escaped + "]");
    return out;
}

private void executeSqlBatches(Connection conn, String script) throws Exception {
    BufferedReader reader = new BufferedReader(new StringReader(script));
    StringBuilder batch = new StringBuilder();
    String line;
    while ((line = reader.readLine()) != null) {
        if (line.trim().matches("(?i)^GO$")) {
            String sql = batch.toString().trim();
            if (!sql.isEmpty()) {
                Statement st = null;
                try {
                    st = conn.createStatement();
                    st.execute(sql);
                } finally {
                    try { if (st != null) st.close(); } catch (Exception ignore) {}
                }
            }
            batch.setLength(0);
        } else {
            batch.append(line).append('\n');
        }
    }
    String tail = batch.toString().trim();
    if (!tail.isEmpty()) {
        Statement st = null;
        try {
            st = conn.createStatement();
            st.execute(tail);
        } finally {
            try { if (st != null) st.close(); } catch (Exception ignore) {}
        }
    }
}

private void bootstrapSchema(String server, String dbName, String user, String password, String encrypt, String trustServerCertificate) throws Exception {
    Connection masterConn = null;
    Connection dbConn = null;
    try {
        masterConn = openSqlServerConnection(server, "master", user, password, encrypt, trustServerCertificate);
        executeSqlBatches(masterConn, adaptSchemaScript(readScript("/docs/sql/create_epms_schema.sql"), dbName));
        dbConn = openSqlServerConnection(server, dbName, user, password, encrypt, trustServerCertificate);
        executeSqlBatches(dbConn, readScript("/docs/sql/create_plc_mapping_master.sql"));
    } finally {
        try { if (dbConn != null) dbConn.close(); } catch (Exception ignore) {}
        try { if (masterConn != null) masterConn.close(); } catch (Exception ignore) {}
    }
}

private int countSeedMeters(Connection conn) throws Exception {
    PreparedStatement ps = null;
    ResultSet rs = null;
    try {
        ps = conn.prepareStatement("SELECT COUNT(*) FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%'");
        rs = ps.executeQuery();
        return rs.next() ? rs.getInt(1) : 0;
    } finally {
        try { if (rs != null) rs.close(); } catch (Exception ignore) {}
        try { if (ps != null) ps.close(); } catch (Exception ignore) {}
    }
}

private void createMinimalSeedData(String server, String dbName, String user, String password, String encrypt, String trustServerCertificate) throws Exception {
    Connection conn = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    Integer parentMeterId = null;
    Integer childMeterId = null;

    try {
        conn = openSqlServerConnection(server, dbName, user, password, encrypt, trustServerCertificate);
        conn.setAutoCommit(false);

        ps = conn.prepareStatement(
            "INSERT INTO dbo.meters (name, panel_name, building_name, usage_type, rated_voltage, rated_current) " +
            "SELECT ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM dbo.meters WHERE name = ?)");
        ps.setString(1, "SEED_EPMS_MAIN");
        ps.setString(2, "SEED_PANEL_A");
        ps.setString(3, "SEED_BUILDING");
        ps.setString(4, "SEED");
        ps.setDouble(5, 380.0d);
        ps.setDouble(6, 100.0d);
        ps.setString(7, "SEED_EPMS_MAIN");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement(
            "INSERT INTO dbo.meters (name, panel_name, building_name, usage_type, rated_voltage, rated_current) " +
            "SELECT ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM dbo.meters WHERE name = ?)");
        ps.setString(1, "SEED_EPMS_SUB");
        ps.setString(2, "SEED_PANEL_B");
        ps.setString(3, "SEED_BUILDING");
        ps.setString(4, "SEED");
        ps.setDouble(5, 220.0d);
        ps.setDouble(6, 60.0d);
        ps.setString(7, "SEED_EPMS_SUB");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement("SELECT meter_id, name FROM dbo.meters WHERE name IN ('SEED_EPMS_MAIN','SEED_EPMS_SUB')");
        rs = ps.executeQuery();
        while (rs.next()) {
            String meterName = rs.getString("name");
            if ("SEED_EPMS_MAIN".equals(meterName)) parentMeterId = Integer.valueOf(rs.getInt("meter_id"));
            if ("SEED_EPMS_SUB".equals(meterName)) childMeterId = Integer.valueOf(rs.getInt("meter_id"));
        }
        rs.close();
        ps.close();

        ps = conn.prepareStatement(
            "INSERT INTO dbo.metric_catalog (metric_key, display_name, source_type, enabled, created_at, updated_at) " +
            "SELECT ?, ?, 'AI', 1, SYSUTCDATETIME(), SYSUTCDATETIME() " +
            "WHERE NOT EXISTS (SELECT 1 FROM dbo.metric_catalog WHERE metric_key = ?)");
        ps.setString(1, "SEED_EPMS_POWER_KW");
        ps.setString(2, "Seed Power kW");
        ps.setString(3, "SEED_EPMS_POWER_KW");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement(
            "INSERT INTO dbo.metric_catalog_tag_map (metric_key, source_token, sort_no, enabled, created_at, updated_at) " +
            "SELECT ?, ?, 1, 1, SYSUTCDATETIME(), SYSUTCDATETIME() " +
            "WHERE NOT EXISTS (SELECT 1 FROM dbo.metric_catalog_tag_map WHERE metric_key = ? AND source_token = ?)");
        ps.setString(1, "SEED_EPMS_POWER_KW");
        ps.setString(2, "KW");
        ps.setString(3, "SEED_EPMS_POWER_KW");
        ps.setString(4, "KW");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement(
            "INSERT INTO dbo.alarm_rule (rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, duration_sec, severity, enabled, description, created_at, updated_at, source_token, message_template) " +
            "SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, SYSUTCDATETIME(), SYSUTCDATETIME(), ?, ? " +
            "WHERE NOT EXISTS (SELECT 1 FROM dbo.alarm_rule WHERE rule_code = ?)");
        ps.setString(1, "SEED_EPMS_HIGH_KW");
        ps.setString(2, "Seed High kW");
        ps.setString(3, "THRESHOLD");
        ps.setString(4, "METER");
        ps.setString(5, "SEED_EPMS_POWER_KW");
        ps.setString(6, ">=");
        ps.setBigDecimal(7, new java.math.BigDecimal("100"));
        ps.setInt(8, 0);
        ps.setString(9, "WARN");
        ps.setBoolean(10, true);
        ps.setString(11, "Seed rule for first-boot verification");
        ps.setString(12, "KW");
        ps.setString(13, "Seed alarm fired for {meter_name}");
        ps.setString(14, "SEED_EPMS_HIGH_KW");
        ps.executeUpdate();
        ps.close();

        if (parentMeterId != null && childMeterId != null) {
            ps = conn.prepareStatement(
                "INSERT INTO dbo.meter_tree (parent_meter_id, child_meter_id, is_active, sort_order, note, created_at, updated_at) " +
                "SELECT ?, ?, 1, 1, ?, SYSUTCDATETIME(), SYSUTCDATETIME() " +
                "WHERE NOT EXISTS (SELECT 1 FROM dbo.meter_tree WHERE parent_meter_id = ? AND child_meter_id = ?)");
            ps.setInt(1, parentMeterId.intValue());
            ps.setInt(2, childMeterId.intValue());
            ps.setString(3, "SEED_EPMS_TREE");
            ps.setInt(4, parentMeterId.intValue());
            ps.setInt(5, childMeterId.intValue());
            ps.executeUpdate();
            ps.close();
        }

        conn.commit();
    } catch (Exception e) {
        try { if (conn != null) conn.rollback(); } catch (Exception ignore) {}
        throw e;
    } finally {
        try { if (rs != null) rs.close(); } catch (Exception ignore) {}
        try { if (ps != null) ps.close(); } catch (Exception ignore) {}
        try { if (conn != null) conn.close(); } catch (Exception ignore) {}
    }
}

private void deleteMinimalSeedData(String server, String dbName, String user, String password, String encrypt, String trustServerCertificate) throws Exception {
    Connection conn = null;
    PreparedStatement ps = null;

    try {
        conn = openSqlServerConnection(server, dbName, user, password, encrypt, trustServerCertificate);
        conn.setAutoCommit(false);

        ps = conn.prepareStatement(
            "IF EXISTS (SELECT 1 FROM dbo.measurements WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.harmonic_measurements WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.flicker_measurements WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.daily_measurements WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.monthly_measurements WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.yearly_measurements WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.alarm_log WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.device_events WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.plc_ai_mapping_master WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "   OR EXISTS (SELECT 1 FROM dbo.plc_di_mapping_master WHERE meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')) " +
            "BEGIN THROW 51000, 'Seed meters are already referenced by operational data. Delete dependent data first.', 1; END");
        ps.execute();
        ps.close();

        ps = conn.prepareStatement("DELETE FROM dbo.meter_tree WHERE note = 'SEED_EPMS_TREE' OR parent_meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%') OR child_meter_id IN (SELECT meter_id FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%')");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement("DELETE FROM dbo.alarm_rule WHERE rule_code LIKE 'SEED_EPMS_%'");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement("DELETE FROM dbo.metric_catalog_tag_map WHERE metric_key LIKE 'SEED_EPMS_%'");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement("DELETE FROM dbo.metric_catalog WHERE metric_key LIKE 'SEED_EPMS_%'");
        ps.executeUpdate();
        ps.close();

        ps = conn.prepareStatement("DELETE FROM dbo.meters WHERE name LIKE 'SEED_EPMS_%'");
        ps.executeUpdate();
        ps.close();

        conn.commit();
    } catch (Exception e) {
        try { if (conn != null) conn.rollback(); } catch (Exception ignore) {}
        throw e;
    } finally {
        try { if (ps != null) ps.close(); } catch (Exception ignore) {}
        try { if (conn != null) conn.close(); } catch (Exception ignore) {}
    }
}

private String buildBackupJobSql(String scriptPath, String dbServer, String dbName, String dbUser, String dbPassword, String backupDir, String retainDays, String scheduleName, String startTime) {
    StringBuilder sb = new StringBuilder();
    sb.append("USE [msdb];\n\n");
    sb.append("DECLARE @jobName sysname = N'EPMS Daily Full Backup';\n");
    sb.append("DECLARE @scriptPath nvarchar(4000) = N'").append(scriptPath.replace("'", "''")).append("';\n");
    sb.append("DECLARE @dbServer nvarchar(4000) = N'").append(dbServer.replace("'", "''")).append("';\n");
    sb.append("DECLARE @dbName nvarchar(4000) = N'").append(dbName.replace("'", "''")).append("';\n");
    sb.append("DECLARE @dbUser nvarchar(4000) = N'").append(dbUser.replace("'", "''")).append("';\n");
    sb.append("DECLARE @dbPassword nvarchar(4000) = N'").append(dbPassword.replace("'", "''")).append("';\n");
    sb.append("DECLARE @backupDir nvarchar(4000) = N'").append(backupDir.replace("'", "''")).append("';\n");
    sb.append("DECLARE @retainDays int = ").append(retainDays).append(";\n");
    sb.append("DECLARE @startTime int = ").append(startTime).append(";\n");
    sb.append("DECLARE @scheduleName sysname = N'").append(scheduleName.replace("'", "''")).append("';\n");
    sb.append("DECLARE @command nvarchar(max) =\n");
    sb.append("    N'powershell -NoProfile -ExecutionPolicy Bypass -File \"' + @scriptPath +\n");
    sb.append("    N'\" -Server \"' + @dbServer +\n");
    sb.append("    N'\" -Database \"' + @dbName +\n");
    sb.append("    N'\" -User \"' + @dbUser +\n");
    sb.append("    N'\" -Password \"' + @dbPassword +\n");
    sb.append("    N'\" -BackupDir \"' + @backupDir +\n");
    sb.append("    N'\" -RetainDays ' + CAST(@retainDays AS nvarchar(20));\n\n");
    sb.append("IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @jobName)\nBEGIN\n");
    sb.append("    EXEC dbo.sp_delete_job @job_name = @jobName, @delete_unused_schedule = 1;\n");
    sb.append("END;\n\n");
    sb.append("EXEC dbo.sp_add_job @job_name = N'EPMS Daily Full Backup', @enabled = 1, @description = N'Compressed daily full backup for EPMS with cleanup of old .bak files.';\n");
    sb.append("EXEC dbo.sp_add_jobstep @job_name = N'EPMS Daily Full Backup', @step_name = N'Run Backup Script', @subsystem = N'CmdExec', @command = @command, @retry_attempts = 1, @retry_interval = 5;\n");
    sb.append("EXEC dbo.sp_add_schedule @schedule_name = @scheduleName, @enabled = 1, @freq_type = 4, @freq_interval = 1, @active_start_time = @startTime;\n");
    sb.append("EXEC dbo.sp_attach_schedule @job_name = N'EPMS Daily Full Backup', @schedule_name = @scheduleName;\n");
    sb.append("EXEC dbo.sp_add_jobserver @job_name = N'EPMS Daily Full Backup';\n");
    return sb.toString();
}
%>
<%
request.setCharacterEncoding("UTF-8");
response.setCharacterEncoding("UTF-8");

File configFile = getConfigFile();
Map<String, String> cfg = loadToml(configFile);

String appName = nv(cfg.get("app.name"), "EPMS");
String baseUrl = nv(cfg.get("app.base_url"), "http://localhost:8080");
String dbJndiName = nv(cfg.get("database.jndi_name"), "java:comp/env/jdbc/epms");
String dbServer = nv(cfg.get("database.server"), "localhost,1433");
String dbName = nv(cfg.get("database.name"), "EPMS");
String dbUser = nv(cfg.get("database.user"), "sa");
String dbPassword = nv(cfg.get("database.password"), "");
String dbEncrypt = nv(cfg.get("database.encrypt"), "true");
String dbTrust = nv(cfg.get("database.trust_server_certificate"), "true");
String backupDir = nv(cfg.get("backup.dir"), "C:\\backup");
String backupRetainDays = nv(cfg.get("backup.retain_days"), "7");
String backupSchedule = nv(cfg.get("backup.schedule"), "02:00");
String plcPollingMs = nv(cfg.get("plc.default_polling_ms"), "3000");
String plcWriteIntervalSec = nv(cfg.get("plc.default_write_interval_sec"), "3");
String agentPropertiesPath = nv(cfg.get("agent.properties_path"), "epms/agent_model.properties");

String message = null;
String error = null;
String backupJobSql = null;
int seedMeterCount = 0;

if ("POST".equalsIgnoreCase(request.getMethod())) {
    String action = nv(request.getParameter("action"), "");

    appName = nv(request.getParameter("app_name"), appName);
    baseUrl = nv(request.getParameter("base_url"), baseUrl);
    dbJndiName = nv(request.getParameter("db_jndi_name"), dbJndiName);
    dbServer = nv(request.getParameter("db_server"), dbServer);
    dbName = nv(request.getParameter("db_name"), dbName);
    dbUser = nv(request.getParameter("db_user"), dbUser);
    dbPassword = nv(request.getParameter("db_password"), dbPassword);
    dbEncrypt = nv(request.getParameter("db_encrypt"), dbEncrypt);
    dbTrust = nv(request.getParameter("db_trust"), dbTrust);
    backupDir = nv(request.getParameter("backup_dir"), backupDir);
    backupRetainDays = nv(request.getParameter("backup_retain_days"), backupRetainDays);
    backupSchedule = nv(request.getParameter("backup_schedule"), backupSchedule);
    plcPollingMs = nv(request.getParameter("plc_polling_ms"), plcPollingMs);
    plcWriteIntervalSec = nv(request.getParameter("plc_write_interval_sec"), plcWriteIntervalSec);
    agentPropertiesPath = nv(request.getParameter("agent_properties_path"), agentPropertiesPath);

    Map<String, String> newCfg = new LinkedHashMap<String, String>();
    newCfg.put("app.name", appName);
    newCfg.put("app.base_url", baseUrl);
    newCfg.put("database.jndi_name", dbJndiName);
    newCfg.put("database.server", dbServer);
    newCfg.put("database.name", dbName);
    newCfg.put("database.user", dbUser);
    newCfg.put("database.password", dbPassword);
    newCfg.put("database.encrypt", dbEncrypt);
    newCfg.put("database.trust_server_certificate", dbTrust);
    newCfg.put("backup.dir", backupDir);
    newCfg.put("backup.retain_days", backupRetainDays);
    newCfg.put("backup.schedule", backupSchedule);
    newCfg.put("plc.default_polling_ms", plcPollingMs);
    newCfg.put("plc.default_write_interval_sec", plcWriteIntervalSec);
    newCfg.put("agent.properties_path", agentPropertiesPath);

    try {
        saveToml(configFile, newCfg);
        if ("save".equals(action)) {
            message = "Configuration saved to WEB-INF/config.toml.";
        } else if ("test_db".equals(action)) {
            Connection conn = null;
            try {
                conn = openSqlServerConnection(dbServer, "master", dbUser, dbPassword, dbEncrypt, dbTrust);
                boolean exists = databaseExists(conn, dbName);
                message = exists
                    ? ("Connected successfully. Database [" + dbName + "] already exists.")
                    : ("Connected successfully. Database [" + dbName + "] does not exist yet.");
            } finally {
                try { if (conn != null) conn.close(); } catch (Exception ignore) {}
            }
        } else if ("init_db".equals(action)) {
            bootstrapSchema(dbServer, dbName, dbUser, dbPassword, dbEncrypt, dbTrust);
            message = "Schema bootstrap completed using create_epms_schema.sql and create_plc_mapping_master.sql.";
        } else if ("generate_backup_job".equals(action)) {
            String rootPath = getServletContext().getRealPath("/");
            String scriptPath = rootPath == null ? "C:\\Tomcat 9.0\\webapps\\ROOT\\scripts\\backup_epms_daily.ps1" : new File(rootPath, "scripts\\backup_epms_daily.ps1").getAbsolutePath();
            backupJobSql = buildBackupJobSql(scriptPath, dbServer, dbName, dbUser, dbPassword, backupDir, backupRetainDays, "EPMS Daily " + backupSchedule.replace(":", ""), backupSchedule.replace(":", "") + "00");
            message = "Server-specific backup job SQL generated below.";
        } else if ("create_seed".equals(action)) {
            createMinimalSeedData(dbServer, dbName, dbUser, dbPassword, dbEncrypt, dbTrust);
            message = "Minimal EPMS seed data created successfully.";
        } else if ("delete_seed".equals(action)) {
            deleteMinimalSeedData(dbServer, dbName, dbUser, dbPassword, dbEncrypt, dbTrust);
            message = "Minimal EPMS seed data removed successfully.";
        }
    } catch (Exception e) {
        error = e.getMessage();
    }
}

boolean canReachServer = false;
boolean targetDbExists = false;
boolean coreTableExists = false;
Connection statusMasterConn = null;
Connection statusDbConn = null;
try {
    statusMasterConn = openSqlServerConnection(dbServer, "master", dbUser, dbPassword, dbEncrypt, dbTrust);
    canReachServer = true;
    targetDbExists = databaseExists(statusMasterConn, dbName);
    if (targetDbExists) {
        statusDbConn = openSqlServerConnection(dbServer, dbName, dbUser, dbPassword, dbEncrypt, dbTrust);
        coreTableExists = tableExists(statusDbConn, "dbo.meters");
        seedMeterCount = countSeedMeters(statusDbConn);
    }
} catch (Exception ignore) {
} finally {
    try { if (statusDbConn != null) statusDbConn.close(); } catch (Exception ignore) {}
    try { if (statusMasterConn != null) statusMasterConn.close(); } catch (Exception ignore) {}
}
%>
<html>
<head>
    <title>EPMS 초기 설정</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1100px; margin: 0 auto; }
        .setup-grid { display: grid; grid-template-columns: repeat(2, minmax(260px, 1fr)); gap: 12px 16px; }
        .setup-card, .status-card {
            background: #fff;
            border: 1px solid #dbe5f2;
            border-radius: 14px;
            padding: 16px;
            box-shadow: 0 10px 24px rgba(31, 51, 71, 0.06);
        }
        .setup-card h3, .status-card h3 { margin: 0 0 10px; color: #1f3347; }
        .setup-card h4 { margin: 12px 0 8px; color: #304860; font-size: 13px; }
        .field { display: flex; flex-direction: column; gap: 4px; margin-bottom: 10px; }
        .field label { font-size: 12px; font-weight: 700; color: #475569; }
        .field input, .field select { width: 100%; margin: 0; box-sizing: border-box; }
        .actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 16px; }
        .actions button { min-width: 150px; }
        .info-box, .err-box {
            margin: 12px 0;
            padding: 12px 14px;
            border-radius: 10px;
            font-size: 13px;
        }
        .info-box { background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; }
        .err-box { background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-weight: 700; }
        .status-grid { display: grid; grid-template-columns: repeat(3, minmax(180px, 1fr)); gap: 12px; margin: 14px 0; }
        .status-value { font-size: 24px; font-weight: 700; color: #1f3347; margin-top: 6px; }
        .status-label { color: #64748b; font-size: 12px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .hint { color: #64748b; font-size: 12px; margin-top: 8px; }
        .sql-preview {
            width: 100%;
            min-height: 260px;
            box-sizing: border-box;
            font-family: Consolas, "Courier New", monospace;
            font-size: 12px;
            line-height: 1.4;
        }
        .checklist { margin: 0; padding-left: 18px; color: #304860; }
        .checklist li { margin: 6px 0; }
        @media (max-width: 900px) {
            .setup-grid, .status-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>EPMS 초기 설정</h2>
        <div class="inline-actions">
            <button class="back-btn" type="button" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        Tomcat은 올라와 있고 SQL Server만 설치된 초기 서버에서 사용하는 설정 화면입니다.<br/>
        이 페이지에서 <span class="mono">WEB-INF/config.toml</span> 저장, SQL Server 직접 연결 테스트, EPMS 스키마 초기화까지 한 번에 진행할 수 있습니다.
    </div>

    <% if (message != null) { %>
    <div class="info-box"><%= h(message) %></div>
    <% } %>
    <% if (error != null) { %>
    <div class="err-box"><%= h(error) %></div>
    <% } %>

    <div class="status-grid">
        <div class="status-card">
            <div class="status-label">설정 파일</div>
            <div class="status-value"><%= (configFile != null && configFile.exists()) ? "준비됨" : "없음" %></div>
            <div class="hint"><%= configFile == null ? "-" : h(configFile.getAbsolutePath()) %></div>
        </div>
        <div class="status-card">
            <div class="status-label">DB 서버 연결</div>
            <div class="status-value"><%= canReachServer ? "정상" : "실패" %></div>
            <div class="hint"><%= h(dbServer) %></div>
        </div>
        <div class="status-card">
            <div class="status-label">스키마 준비 상태</div>
            <div class="status-value"><%= coreTableExists ? "완료" : (targetDbExists ? "부분" : "미완료") %></div>
            <div class="hint">DB <span class="mono"><%= h(dbName) %></span> / table <span class="mono">dbo.meters</span></div>
        </div>
        <div class="status-card">
            <div class="status-label">Seed Meter 건수</div>
            <div class="status-value"><%= seedMeterCount %></div>
            <div class="hint"><span class="mono">SEED_EPMS_%</span> 기준</div>
        </div>
    </div>

    <form method="POST">
        <div class="setup-grid">
            <div class="setup-card">
                <h3>앱 설정</h3>
                <div class="field">
                    <label for="app_name">앱 이름</label>
                    <input id="app_name" name="app_name" type="text" value="<%= h(appName) %>">
                </div>
                <div class="field">
                    <label for="base_url">기본 URL</label>
                    <input id="base_url" name="base_url" type="text" value="<%= h(baseUrl) %>">
                </div>
                <div class="field">
                    <label for="agent_properties_path">Agent 설정 파일 경로</label>
                    <input id="agent_properties_path" name="agent_properties_path" type="text" value="<%= h(agentPropertiesPath) %>">
                </div>
            </div>

            <div class="setup-card">
                <h3>데이터베이스 설정</h3>
                <div class="field">
                    <label for="db_jndi_name">JNDI 이름</label>
                    <input id="db_jndi_name" name="db_jndi_name" type="text" value="<%= h(dbJndiName) %>">
                </div>
                <div class="field">
                    <label for="db_server">서버</label>
                    <input id="db_server" name="db_server" type="text" value="<%= h(dbServer) %>">
                </div>
                <div class="field">
                    <label for="db_name">DB 이름</label>
                    <input id="db_name" name="db_name" type="text" value="<%= h(dbName) %>">
                </div>
                <div class="field">
                    <label for="db_user">사용자</label>
                    <input id="db_user" name="db_user" type="text" value="<%= h(dbUser) %>">
                </div>
                <div class="field">
                    <label for="db_password">비밀번호</label>
                    <input id="db_password" name="db_password" type="password" value="<%= h(dbPassword) %>">
                </div>
                <div class="field">
                    <label for="db_encrypt">암호화 사용</label>
                    <select id="db_encrypt" name="db_encrypt">
                        <option value="true" <%= "true".equalsIgnoreCase(dbEncrypt) ? "selected" : "" %>>true</option>
                        <option value="false" <%= "false".equalsIgnoreCase(dbEncrypt) ? "selected" : "" %>>false</option>
                    </select>
                </div>
                <div class="field">
                    <label for="db_trust">서버 인증서 신뢰</label>
                    <select id="db_trust" name="db_trust">
                        <option value="true" <%= "true".equalsIgnoreCase(dbTrust) ? "selected" : "" %>>true</option>
                        <option value="false" <%= "false".equalsIgnoreCase(dbTrust) ? "selected" : "" %>>false</option>
                    </select>
                </div>
            </div>

            <div class="setup-card">
                <h3>백업 설정</h3>
                <div class="field">
                    <label for="backup_dir">백업 폴더</label>
                    <input id="backup_dir" name="backup_dir" type="text" value="<%= h(backupDir) %>">
                </div>
                <div class="field">
                    <label for="backup_retain_days">보관 일수</label>
                    <input id="backup_retain_days" name="backup_retain_days" type="number" min="1" value="<%= h(backupRetainDays) %>">
                </div>
                <div class="field">
                    <label for="backup_schedule">실행 시간</label>
                    <input id="backup_schedule" name="backup_schedule" type="text" value="<%= h(backupSchedule) %>">
                </div>
            </div>

            <div class="setup-card">
                <h3>PLC 기본 설정</h3>
                <div class="field">
                    <label for="plc_polling_ms">기본 Polling 주기(ms)</label>
                    <input id="plc_polling_ms" name="plc_polling_ms" type="number" min="100" value="<%= h(plcPollingMs) %>">
                </div>
                <div class="field">
                    <label for="plc_write_interval_sec">기본 Write 주기(초)</label>
                    <input id="plc_write_interval_sec" name="plc_write_interval_sec" type="number" min="1" value="<%= h(plcWriteIntervalSec) %>">
                </div>
                <div class="hint">
                    스키마 초기화 시 <span class="mono">docs/sql/create_epms_schema.sql</span> 과 <span class="mono">docs/sql/create_plc_mapping_master.sql</span> 을 사용합니다.<br/>
                    PLC 등록은 초기화 후 <span class="mono">/epms/plc/plc_register.jsp</span> 에서 진행하세요.
                </div>
            </div>

            <div class="setup-card">
                <h3>최소 Seed 데이터</h3>
                <div class="hint">
                    설치 직후 화면 점검용 최소 데이터만 넣습니다.<br/>
                    생성 대상: <span class="mono">meters</span>, <span class="mono">metric_catalog</span>, <span class="mono">metric_catalog_tag_map</span>, <span class="mono">alarm_rule</span>, <span class="mono">meter_tree</span><br/>
                    표식: <span class="mono">SEED_EPMS_%</span>
                </div>
                <div class="field">
                    <label>현재 Seed 상태</label>
                    <input type="text" value="<%= seedMeterCount > 0 ? ("생성됨 (" + seedMeterCount + " meter)") : "없음" %>" readonly>
                </div>
                <div class="hint">
                    삭제 시에는 seed meter가 운영 데이터에 연결되어 있으면 안전을 위해 중단됩니다.
                </div>
            </div>
        </div>

        <div class="actions">
            <button type="submit" name="action" value="save">설정 저장</button>
            <button type="submit" name="action" value="test_db">저장 후 DB 연결 테스트</button>
            <button type="submit" name="action" value="init_db" onclick="return confirm('지금 EPMS 데이터베이스 스키마를 생성 또는 갱신할까요?');">저장 후 스키마 초기화</button>
            <button type="submit" name="action" value="generate_backup_job">저장 후 백업 Job SQL 생성</button>
            <button type="submit" name="action" value="create_seed" onclick="return confirm('최소 seed 데이터를 생성할까요?');">최소 Seed 생성</button>
            <button type="submit" name="action" value="delete_seed" onclick="return confirm('최소 seed 데이터를 삭제할까요? 운영 데이터와 연결된 경우 삭제가 중단됩니다.');">최소 Seed 삭제</button>
            <button type="button" onclick="location.href='/epms/plc/plc_register.jsp'">PLC 등록 화면으로 이동</button>
        </div>
    </form>

    <div class="setup-grid" style="margin-top:16px;">
        <div class="setup-card">
            <h3>백업 Job SQL</h3>
            <div class="hint">서버 환경에 맞는 SQL Server Agent Job 스크립트를 생성합니다. 생성 후 SSMS에서 관리자 권한으로 실행하세요.</div>
            <textarea class="sql-preview" readonly><%= h(backupJobSql == null ? "'저장 후 백업 Job SQL 생성' 버튼을 누르면 여기에 스크립트가 표시됩니다." : backupJobSql) %></textarea>
        </div>

        <div class="setup-card">
            <h3>초기 관리자 체크리스트</h3>
            <ul class="checklist">
                <li><span class="mono">저장 후 DB 연결 테스트</span>를 실행해 SQL Server 연결을 먼저 확인합니다.</li>
                <li>메인 화면을 열기 전에 <span class="mono">저장 후 스키마 초기화</span>를 실행합니다.</li>
                <li>테스트가 필요하면 <span class="mono">최소 Seed 생성</span>으로 기본 데이터만 넣습니다.</li>
                <li>PLC는 <span class="mono">/epms/plc/plc_register.jsp</span> 에서 정식 등록합니다.</li>
                <li>생성된 백업 Job SQL을 대상 서버의 <span class="mono">msdb</span>에서 실행합니다.</li>
                <li><span class="mono">SQLSERVERAGENT</span> 서비스를 <span class="mono">Automatic</span>으로 두고 <span class="mono">Running</span> 상태인지 확인합니다.</li>
                <li><span class="mono">/epms/epms_main.jsp</span>, <span class="mono">/epms/plc/plc_register.jsp</span>, <span class="mono">/epms/di_mapping.jsp</span> 접근을 확인합니다.</li>
                <li>신규 서버라면 PLC 등록 후 AI/DI 매핑을 import 합니다.</li>
                <li>운영 전에는 필요 시 <span class="mono">최소 Seed 삭제</span>로 테스트 데이터를 제거합니다.</li>
            </ul>
        </div>
    </div>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
