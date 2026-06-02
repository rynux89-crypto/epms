<%@ page import="java.io.*" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="javax.servlet.ServletContext" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String readUpsSqlFile(ServletContext ctx, String webPath) throws Exception {
        String path = ctx.getRealPath(webPath);
        if (path == null) throw new FileNotFoundException(webPath);
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
            try { reader.close(); } catch (Exception ignore) {}
        }
        return sb.toString();
    }

    private String readUpsSchemaSql(ServletContext ctx) throws Exception {
        return readUpsSqlFile(ctx, "/scripts/create_ups_monitor.sql")
            + "\n--GO--\n"
            + readUpsSqlFile(ctx, "/scripts/create_schneider_easy_ups_profile.sql");
    }

    private List<String> splitUpsSqlBatches(String sql) {
        List<String> out = new ArrayList<String>();
        if (sql == null) return out;
        String[] chunks = sql.split("(?m)^--GO--$");
        for (String chunk : chunks) {
            String x = chunk == null ? "" : chunk.trim();
            if (!x.isEmpty()) out.add(x);
        }
        return out;
    }

    private int countUpsTable(Connection conn, String tableName) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(1) FROM " + tableName);
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    private String displayDateTime(Object value) {
        if (value == null) return "-";
        if (value instanceof Timestamp) {
            return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format((Timestamp)value);
        }
        String s = String.valueOf(value);
        return s.length() > 19 ? s.substring(0, 19) : s;
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String action = request.getParameter("action");
String msg = null;
String err = null;

if ("init_schema".equals(action)) {
    Connection adminConn = null;
    try {
        Map<String, String> cfg = loadUpsConfigToml();
        String server = upsFirstNonBlank(System.getenv("UPS_DB_SERVER"), cfg.get("ups_database.server"));
        String user = upsFirstNonBlank(System.getenv("UPS_DB_USER"), cfg.get("ups_database.user"));
        String password = upsFirstNonNull(System.getenv("UPS_DB_PASSWORD"), cfg.get("ups_database.password"));
        String encrypt = upsFirstNonBlank(System.getenv("UPS_DB_ENCRYPT"), cfg.get("ups_database.encrypt"));
        String trust = upsFirstNonBlank(System.getenv("UPS_DB_TRUST_SERVER_CERTIFICATE"), cfg.get("ups_database.trust_server_certificate"));
        if (encrypt == null || encrypt.trim().isEmpty()) encrypt = "true";
        if (trust == null || trust.trim().isEmpty()) trust = "true";

        Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
        String url = "jdbc:sqlserver://" + normalizeUpsSqlServerJdbcHost(server) +
            ";databaseName=master;encrypt=" + encrypt + ";trustServerCertificate=" + trust + ";loginTimeout=5;";
        adminConn = DriverManager.getConnection(url, user, password);
        String sql = readUpsSchemaSql(application);
        List<String> batches = splitUpsSqlBatches(sql);
        for (String batch : batches) {
            try (Statement st = adminConn.createStatement()) {
                st.execute(batch);
            }
        }
        msg = "UPS_MONITOR 데이터베이스와 기본 테이블을 초기화했습니다.";
    } catch (Exception e) {
        err = e.getMessage();
    } finally {
        closeUpsQuietly(adminConn);
    }
}

if ("clear_history".equals(action)) {
    Connection conn = null;
    try {
        conn = openUpsDbConnection();
        conn.setAutoCommit(false);
        int alarmDeleted = 0;
        int measurementDeleted = 0;
        int commDeleted = 0;
        try (Statement st = conn.createStatement()) {
            alarmDeleted = st.executeUpdate("DELETE FROM dbo.ups_alarm_log");
            commDeleted = st.executeUpdate("DELETE FROM dbo.ups_comm_status");
            measurementDeleted = st.executeUpdate("DELETE FROM dbo.ups_measurement");
            st.executeUpdate("UPDATE dbo.ups_device SET last_comm_status='UNKNOWN', last_success_at=NULL, last_error_at=NULL, last_error_message=NULL, updated_at=sysdatetime()");
        }
        conn.commit();
        msg = "UPS 이력 데이터를 삭제했습니다. 측정 " + measurementDeleted + "건, 알람 " + alarmDeleted + "건, 통신상태 " + commDeleted + "건";
    } catch (Exception e) {
        if (conn != null) {
            try { conn.rollback(); } catch (Exception ignore) {}
        }
        err = e.getMessage();
    } finally {
        if (conn != null) {
            try { conn.setAutoCommit(true); } catch (Exception ignore) {}
        }
        closeUpsQuietly(conn);
    }
}

boolean canConnect = false;
String connectError = null;
int deviceCount = 0;
int profileCount = 0;
int pointCount = 0;
int alarmCount = 0;
int measurementCount = 0;
int commCount = 0;
String collectorStatus = String.valueOf(application.getAttribute("ups.collector.status"));
if (collectorStatus == null || "null".equals(collectorStatus)) collectorStatus = "UNKNOWN";
Object collectorLastStart = application.getAttribute("ups.collector.lastStartAt");
Object collectorLastSuccess = application.getAttribute("ups.collector.lastSuccessAt");
Object collectorLastErrorAt = application.getAttribute("ups.collector.lastErrorAt");
Object collectorLastDuration = application.getAttribute("ups.collector.lastDurationMs");
Object collectorLastError = application.getAttribute("ups.collector.lastError");
Object collectorInterval = application.getAttribute("ups.collector.intervalSeconds");
try (Connection conn = openUpsDbConnection()) {
    canConnect = true;
    deviceCount = countUpsTable(conn, "dbo.ups_device");
    profileCount = countUpsTable(conn, "dbo.ups_modbus_profile");
    pointCount = countUpsTable(conn, "dbo.ups_modbus_point");
    alarmCount = countUpsTable(conn, "dbo.ups_alarm_log");
    measurementCount = countUpsTable(conn, "dbo.ups_measurement");
    commCount = countUpsTable(conn, "dbo.ups_comm_status");
} catch (Exception e) {
    connectError = e.getMessage();
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 초기 설정</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .status-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:12px; margin:16px 0; }
        .status-card { padding:14px; border:1px solid #dbe5f2; border-radius:8px; background:#fff; }
        .status-card span { display:block; color:#64748b; font-size:12px; }
        .status-card strong { display:block; margin-top:6px; color:#1f3347; font-size:22px; }
        .setup-actions { display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
        .setup-actions form { margin:0; }
        .ok-box { margin:12px 0; padding:12px 14px; border-radius:8px; background:#ebfff1; border:1px solid #b7ebc6; color:#0f7a2a; font-weight:700; }
        .err-box { margin:12px 0; padding:12px 14px; border-radius:8px; background:#fff1f1; border:1px solid #ffc9c9; color:#b42318; font-weight:700; white-space:pre-wrap; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div>
            <h2>UPS 초기 설정</h2>
            <p class="muted">기본 SQL Server 인스턴스의 UPS_MONITOR 데이터베이스를 확인합니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <% if (msg != null) { %><div class="ok-box"><%= h(msg) %></div><% } %>
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <div class="status-grid">
        <div class="status-card"><span>DB 연결</span><strong><%= canConnect ? "정상" : "실패" %></strong></div>
        <div class="status-card"><span>등록 UPS</span><strong><%= deviceCount %></strong></div>
        <div class="status-card"><span>프로파일</span><strong><%= profileCount %></strong></div>
        <div class="status-card"><span>Modbus 포인트</span><strong><%= pointCount %></strong></div>
        <div class="status-card"><span>측정 이력</span><strong><%= measurementCount %></strong></div>
        <div class="status-card"><span>알람 이력</span><strong><%= alarmCount %></strong></div>
        <div class="status-card"><span>통신 상태</span><strong><%= commCount %></strong></div>
        <div class="status-card"><span>수집기 상태</span><strong><%= h(collectorStatus) %></strong></div>
    </div>

    <div class="panel" style="margin-bottom:14px;">
        <h3 style="margin-top:0;">수집기 진단</h3>
        <p class="muted" style="margin:4px 0;">주기: <%= h(collectorInterval == null ? "5" : collectorInterval) %>초</p>
        <p class="muted" style="margin:4px 0;">마지막 시작: <%= h(displayDateTime(collectorLastStart)) %></p>
        <p class="muted" style="margin:4px 0;">마지막 성공: <%= h(displayDateTime(collectorLastSuccess)) %></p>
        <p class="muted" style="margin:4px 0;">마지막 실패: <%= h(displayDateTime(collectorLastErrorAt)) %></p>
        <p class="muted" style="margin:4px 0;">소요 시간: <%= h(collectorLastDuration == null ? "-" : collectorLastDuration + " ms") %></p>
        <% if (collectorLastError != null) { %>
            <div class="err-box">수집 오류: <%= h(collectorLastError) %></div>
        <% } %>
    </div>

    <% if (!canConnect) { %>
        <div class="err-box">UPS DB 연결 실패: <%= h(connectError) %></div>
    <% } %>

    <div class="setup-actions">
        <form method="post" onsubmit="return confirm('UPS_MONITOR 데이터베이스와 기본 테이블을 생성 또는 갱신할까요?');">
            <input type="hidden" name="action" value="init_schema">
            <button type="submit">DB 초기화 실행</button>
        </form>
        <form method="post" onsubmit="return confirm('측정 이력, 알람 이력, 통신 상태를 삭제할까요? UPS 등록 정보와 Modbus 프로파일은 유지됩니다.');">
            <input type="hidden" name="action" value="clear_history">
            <button type="submit">이력 데이터 삭제</button>
        </form>
    </div>
</div>
</body>
</html>
