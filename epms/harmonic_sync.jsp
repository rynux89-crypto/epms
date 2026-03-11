<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%
    String message = null;
    String error = null;
    int pendingCount = 0;
    int insertedCount = 0;
    List<Map<String, Object>> latestRows = new ArrayList<>();

    String baseCte =
        "WITH m AS ( " +
        "    SELECT plc_id, meter_id, start_address " +
        "    FROM dbo.plc_meter_map " +
        "    WHERE enabled = 1 " +
        "), t AS ( " +
        "    SELECT token, float_index, measurement_column " +
        "    FROM dbo.plc_ai_measurements_match " +
        "    WHERE target_table = 'harmonic_measurements' " +
        "      AND is_supported = 1 " +
        "      AND measurement_column IS NOT NULL " +
        "), a AS ( " +
        "    SELECT m.plc_id, m.meter_id, t.token, t.float_index, t.measurement_column, " +
        "           m.start_address + ((t.float_index - 1) * 2) AS reg_address " +
        "    FROM m CROSS JOIN t " +
        "), s AS ( " +
        "    SELECT a.plc_id, a.meter_id, a.measurement_column, x.value_float, x.measured_at, " +
        "           ROW_NUMBER() OVER (PARTITION BY a.plc_id, a.meter_id, a.measurement_column ORDER BY x.measured_at DESC) AS rn " +
        "    FROM a " +
        "    JOIN dbo.plc_ai_samples x " +
        "      ON x.plc_id = a.plc_id AND x.meter_id = a.meter_id AND x.reg_address = a.reg_address " +
        "), l AS ( " +
        "    SELECT plc_id, meter_id, measurement_column, value_float, measured_at " +
        "    FROM s WHERE rn = 1 " +
        "), p AS ( " +
        "    SELECT meter_id, " +
        "           MAX(measured_at) AS measured_at, " +
        "           MAX(CASE WHEN measurement_column='thd_voltage_a' THEN value_float END) AS thd_voltage_a, " +
        "           MAX(CASE WHEN measurement_column='thd_voltage_b' THEN value_float END) AS thd_voltage_b, " +
        "           MAX(CASE WHEN measurement_column='thd_voltage_c' THEN value_float END) AS thd_voltage_c, " +
        "           MAX(CASE WHEN measurement_column='voltage_h3_a' THEN value_float END) AS voltage_h3_a, " +
        "           MAX(CASE WHEN measurement_column='voltage_h5_a' THEN value_float END) AS voltage_h5_a, " +
        "           MAX(CASE WHEN measurement_column='voltage_h7_a' THEN value_float END) AS voltage_h7_a, " +
        "           MAX(CASE WHEN measurement_column='voltage_h9_a' THEN value_float END) AS voltage_h9_a, " +
        "           MAX(CASE WHEN measurement_column='voltage_h11_a' THEN value_float END) AS voltage_h11_a, " +
        "           MAX(CASE WHEN measurement_column='voltage_h3_b' THEN value_float END) AS voltage_h3_b, " +
        "           MAX(CASE WHEN measurement_column='voltage_h5_b' THEN value_float END) AS voltage_h5_b, " +
        "           MAX(CASE WHEN measurement_column='voltage_h7_b' THEN value_float END) AS voltage_h7_b, " +
        "           MAX(CASE WHEN measurement_column='voltage_h9_b' THEN value_float END) AS voltage_h9_b, " +
        "           MAX(CASE WHEN measurement_column='voltage_h11_b' THEN value_float END) AS voltage_h11_b, " +
        "           MAX(CASE WHEN measurement_column='voltage_h3_c' THEN value_float END) AS voltage_h3_c, " +
        "           MAX(CASE WHEN measurement_column='voltage_h5_c' THEN value_float END) AS voltage_h5_c, " +
        "           MAX(CASE WHEN measurement_column='voltage_h7_c' THEN value_float END) AS voltage_h7_c, " +
        "           MAX(CASE WHEN measurement_column='voltage_h9_c' THEN value_float END) AS voltage_h9_c, " +
        "           MAX(CASE WHEN measurement_column='voltage_h11_c' THEN value_float END) AS voltage_h11_c, " +
        "           MAX(CASE WHEN measurement_column='thd_current_a' THEN value_float END) AS thd_current_a, " +
        "           MAX(CASE WHEN measurement_column='thd_current_b' THEN value_float END) AS thd_current_b, " +
        "           MAX(CASE WHEN measurement_column='thd_current_c' THEN value_float END) AS thd_current_c, " +
        "           MAX(CASE WHEN measurement_column='current_h3_a' THEN value_float END) AS current_h3_a, " +
        "           MAX(CASE WHEN measurement_column='current_h5_a' THEN value_float END) AS current_h5_a, " +
        "           MAX(CASE WHEN measurement_column='current_h7_a' THEN value_float END) AS current_h7_a, " +
        "           MAX(CASE WHEN measurement_column='current_h9_a' THEN value_float END) AS current_h9_a, " +
        "           MAX(CASE WHEN measurement_column='current_h11_a' THEN value_float END) AS current_h11_a, " +
        "           MAX(CASE WHEN measurement_column='current_h3_b' THEN value_float END) AS current_h3_b, " +
        "           MAX(CASE WHEN measurement_column='current_h5_b' THEN value_float END) AS current_h5_b, " +
        "           MAX(CASE WHEN measurement_column='current_h7_b' THEN value_float END) AS current_h7_b, " +
        "           MAX(CASE WHEN measurement_column='current_h9_b' THEN value_float END) AS current_h9_b, " +
        "           MAX(CASE WHEN measurement_column='current_h11_b' THEN value_float END) AS current_h11_b, " +
        "           MAX(CASE WHEN measurement_column='current_h3_c' THEN value_float END) AS current_h3_c, " +
        "           MAX(CASE WHEN measurement_column='current_h5_c' THEN value_float END) AS current_h5_c, " +
        "           MAX(CASE WHEN measurement_column='current_h7_c' THEN value_float END) AS current_h7_c, " +
        "           MAX(CASE WHEN measurement_column='current_h9_c' THEN value_float END) AS current_h9_c, " +
        "           MAX(CASE WHEN measurement_column='current_h11_c' THEN value_float END) AS current_h11_c " +
        "    FROM l " +
        "    GROUP BY meter_id " +
        "), n AS ( " +
        "    SELECT p.* " +
        "    FROM p " +
        "    WHERE p.measured_at > ISNULL((SELECT MAX(h.measured_at) FROM dbo.harmonic_measurements h WHERE h.meter_id = p.meter_id), '1900-01-01') " +
        ") ";

    try {
        String pendingSql = baseCte + "SELECT COUNT(*) AS pending_count FROM n;";
        try (PreparedStatement ps = conn.prepareStatement(pendingSql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) pendingCount = rs.getInt("pending_count");
        }

        if ("POST".equalsIgnoreCase(request.getMethod())) {
            String insertSql = baseCte +
                "INSERT INTO dbo.harmonic_measurements ( " +
                "    meter_id, measured_at, " +
                "    thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
                "    voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
                "    voltage_h3_b, voltage_h5_b, voltage_h7_b, voltage_h9_b, voltage_h11_b, " +
                "    voltage_h3_c, voltage_h5_c, voltage_h7_c, voltage_h9_c, voltage_h11_c, " +
                "    thd_current_a, thd_current_b, thd_current_c, " +
                "    current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a, " +
                "    current_h3_b, current_h5_b, current_h7_b, current_h9_b, current_h11_b, " +
                "    current_h3_c, current_h5_c, current_h7_c, current_h9_c, current_h11_c " +
                ") " +
                "SELECT " +
                "    meter_id, measured_at, " +
                "    thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
                "    voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
                "    voltage_h3_b, voltage_h5_b, voltage_h7_b, voltage_h9_b, voltage_h11_b, " +
                "    voltage_h3_c, voltage_h5_c, voltage_h7_c, voltage_h9_c, voltage_h11_c, " +
                "    thd_current_a, thd_current_b, thd_current_c, " +
                "    current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a, " +
                "    current_h3_b, current_h5_b, current_h7_b, current_h9_b, current_h11_b, " +
                "    current_h3_c, current_h5_c, current_h7_c, current_h9_c, current_h11_c " +
                "FROM n;";
            try (PreparedStatement ps = conn.prepareStatement(insertSql)) {
                insertedCount = ps.executeUpdate();
                message = "고조파 동기화 완료: " + insertedCount + "건 INSERT";
            }

            try (PreparedStatement ps = conn.prepareStatement(pendingSql);
                 ResultSet rs = ps.executeQuery()) {
                if (rs.next()) pendingCount = rs.getInt("pending_count");
            }
        }

        String latestSql =
            "SELECT TOP 20 meter_id, measured_at, thd_voltage_a, thd_voltage_b, thd_voltage_c, thd_current_a, thd_current_b, thd_current_c " +
            "FROM dbo.harmonic_measurements ORDER BY measured_at DESC, harmonic_id DESC";
        try (PreparedStatement ps = conn.prepareStatement(latestSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("meter_id", rs.getInt("meter_id"));
                r.put("measured_at", rs.getTimestamp("measured_at"));
                r.put("thd_voltage_a", rs.getObject("thd_voltage_a"));
                r.put("thd_voltage_b", rs.getObject("thd_voltage_b"));
                r.put("thd_voltage_c", rs.getObject("thd_voltage_c"));
                r.put("thd_current_a", rs.getObject("thd_current_a"));
                r.put("thd_current_b", rs.getObject("thd_current_b"));
                r.put("thd_current_c", rs.getObject("thd_current_c"));
                latestRows.add(r);
            }
        }
    } catch (Exception e) {
        error = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%>
<html>
<head>
    <title>Harmonic Sync</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1300px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🎵 고조파 동기화 (plc_ai_samples → harmonic_measurements)</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/ai_measurements_match.jsp'">AI-Measurements 매칭</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        소스: <span class="mono">plc_ai_samples</span> + <span class="mono">plc_meter_map</span> + <span class="mono">plc_ai_measurements_match</span><br/>
        타겟: <span class="mono">harmonic_measurements</span><br/>
        정책: meter별 최신 시각보다 <b>새로운 시각</b> 데이터만 INSERT (중복 방지)
    </div>

    <% if (message != null) { %><div class="ok-box"><%= message %></div><% } %>
    <% if (error != null) { %><div class="err-box">오류: <%= error %></div><% } %>

    <form method="POST">
        <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">
            <span>현재 미적재 건수: <b><%= pendingCount %></b></span>
            <button type="submit">고조파 동기화 실행</button>
            <% if ("POST".equalsIgnoreCase(request.getMethod())) { %>
            <span>이번 실행 INSERT: <b><%= insertedCount %></b></span>
            <% } %>
        </div>
    </form>

    <h3 style="margin-top:14px;">최근 적재 데이터(상위 20)</h3>
    <table>
        <thead>
        <tr>
            <th>meter_id</th>
            <th>measured_at</th>
            <th>thd_voltage_a</th>
            <th>thd_voltage_b</th>
            <th>thd_voltage_c</th>
            <th>thd_current_a</th>
            <th>thd_current_b</th>
            <th>thd_current_c</th>
        </tr>
        </thead>
        <tbody>
        <% if (latestRows.isEmpty()) { %>
        <tr><td colspan="8">데이터가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : latestRows) { %>
            <tr>
                <td><%= r.get("meter_id") %></td>
                <td><%= r.get("measured_at") %></td>
                <td class="mono"><%= r.get("thd_voltage_a") == null ? "-" : r.get("thd_voltage_a") %></td>
                <td class="mono"><%= r.get("thd_voltage_b") == null ? "-" : r.get("thd_voltage_b") %></td>
                <td class="mono"><%= r.get("thd_voltage_c") == null ? "-" : r.get("thd_voltage_c") %></td>
                <td class="mono"><%= r.get("thd_current_a") == null ? "-" : r.get("thd_current_a") %></td>
                <td class="mono"><%= r.get("thd_current_b") == null ? "-" : r.get("thd_current_b") %></td>
                <td class="mono"><%= r.get("thd_current_c") == null ? "-" : r.get("thd_current_c") %></td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
