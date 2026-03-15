<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.text.DecimalFormat" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static final DecimalFormat DF_2 = new DecimalFormat("0.00");

    private static String fmtNum2(Object value) {
        if (value == null) return "-";
        if (value instanceof Number) return DF_2.format(((Number)value).doubleValue());
        return String.valueOf(value);
    }

    private static String classifyTokenGroup(String token) {
        if (token == null) return "기타";
        String t = token.trim().toUpperCase(Locale.ROOT);
        if (t.startsWith("H_V")) return "전압 고조파";
        if (t.startsWith("H_I")) return "전류 고조파";
        if (t.startsWith("PV") || t.startsWith("PI")) return "위상각";
        if ("PF".equals(t) || "HZ".equals(t) || "KW".equals(t) || "KWH".equals(t) || "KVAR".equals(t) || "KVARH".equals(t) || "PEAK".equals(t)) return "전력/에너지";
        if (t.startsWith("A")) return "전류";
        if (t.startsWith("V")) return "전압";
        return "기타";
    }

    private static String describeTokenMeaning(String token) {
        if (token == null) return "";
        String t = token.trim().toUpperCase(Locale.ROOT);
        if ("PV1".equals(t)) return "A상 전압 위상각";
        if ("PV2".equals(t)) return "B상 전압 위상각";
        if ("PV3".equals(t)) return "C상 전압 위상각";
        if ("PI1".equals(t)) return "A상 전류 위상각";
        if ("PI2".equals(t)) return "B상 전류 위상각";
        if ("PI3".equals(t)) return "C상 전류 위상각";
        if ("PF".equals(t)) return "역률";
        if ("HZ".equals(t)) return "주파수";
        if ("KW".equals(t)) return "유효전력";
        if ("KHH".equals(t)) return "유효전력량";
        if ("VA".equals(t)) return "무효전력";
        if ("VAH".equals(t)) return "무효전력량";
        if ("PEAK".equals(t)) return "전력 피크";
        return "";
    }
%>
<%
    String plcParam = request.getParameter("plc_id");
    String meterParam = request.getParameter("meter_id");
    Integer plcId = null;
    Integer meterId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}
    try { if (meterParam != null && !meterParam.trim().isEmpty()) meterId = Integer.parseInt(meterParam.trim()); } catch (Exception ignore) {}

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<Map<String, Object>> meterList = new ArrayList<>();
    List<Map<String, Object>> mappingRows = new ArrayList<>();
    List<Map<String, Object>> latestTokenRows = new ArrayList<>();
    Map<String, Object> latestMeasurement = new HashMap<>();
    Map<String, Object> latestHarmonicMeasurement = new HashMap<>();
    Map<String, List<Map<String, Object>>> latestTokenGroups = new LinkedHashMap<>();
    String error = null;

    try {
        try (PreparedStatement ps = conn.prepareStatement("SELECT plc_id, plc_ip, plc_port, unit_id, enabled FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("plc_id", rs.getInt("plc_id"));
                r.put("plc_ip", rs.getString("plc_ip"));
                r.put("plc_port", rs.getInt("plc_port"));
                r.put("unit_id", rs.getInt("unit_id"));
                r.put("enabled", rs.getBoolean("enabled"));
                plcList.add(r);
            }
        }

        String meterSql = "SELECT meter_id, name, panel_name FROM dbo.meters ORDER BY meter_id";
        try (PreparedStatement ps = conn.prepareStatement(meterSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("meter_id", rs.getInt("meter_id"));
                r.put("name", rs.getString("name"));
                r.put("panel_name", rs.getString("panel_name"));
                meterList.add(r);
            }
        }

        String mapSql =
            "SELECT token, float_index, float_registers, measurement_column, target_table, is_supported, note " +
            "FROM dbo.plc_ai_measurements_match ORDER BY float_index";
        try (PreparedStatement ps = conn.prepareStatement(mapSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("token", rs.getString("token"));
                r.put("float_index", rs.getInt("float_index"));
                r.put("float_registers", rs.getInt("float_registers"));
                r.put("measurement_column", rs.getString("measurement_column"));
                r.put("target_table", rs.getString("target_table"));
                r.put("is_supported", rs.getBoolean("is_supported"));
                r.put("note", rs.getString("note"));
                mappingRows.add(r);
            }
        }

        if (plcId != null && meterId != null) {
            String tokenSql =
                "WITH b AS ( " +
                "    SELECT plc_id, meter_id, start_address " +
                "    FROM dbo.plc_meter_map " +
                "    WHERE plc_id = ? AND meter_id = ? AND enabled = 1 " +
                "), a AS ( " +
                "    SELECT b.plc_id, b.meter_id, m.token, m.float_index, m.measurement_column, " +
                "           b.start_address + ((m.float_index - 1) * 2) AS reg_address " +
                "    FROM b CROSS JOIN dbo.plc_ai_measurements_match m " +
                "    WHERE m.is_supported = 1 AND m.measurement_column IS NOT NULL " +
                "), s AS ( " +
                "    SELECT a.token, a.float_index, a.measurement_column, a.reg_address, " +
                "           x.value_float, x.measured_at, " +
                "           ROW_NUMBER() OVER (PARTITION BY a.token ORDER BY x.measured_at DESC) AS rn " +
                "    FROM a " +
                "    LEFT JOIN dbo.plc_ai_samples x " +
                "      ON x.plc_id = a.plc_id AND x.meter_id = a.meter_id AND x.reg_address = a.reg_address " +
                ") " +
                "SELECT token, float_index, measurement_column, reg_address, value_float, measured_at " +
                "FROM s WHERE rn = 1 ORDER BY float_index";

            try (PreparedStatement ps = conn.prepareStatement(tokenSql)) {
                ps.setInt(1, plcId);
                ps.setInt(2, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Map<String, Object> r = new HashMap<>();
                        r.put("token", rs.getString("token"));
                        r.put("float_index", rs.getInt("float_index"));
                        r.put("measurement_column", rs.getString("measurement_column"));
                        r.put("reg_address", rs.getInt("reg_address"));
                        r.put("value_float", rs.getObject("value_float"));
                        r.put("measured_at", rs.getTimestamp("measured_at"));
                        latestTokenRows.add(r);
                    }
                }
            }

            String latestSql =
                "SELECT TOP 1 * FROM dbo.measurements WHERE meter_id = ? ORDER BY measured_at DESC";
            try (PreparedStatement ps = conn.prepareStatement(latestSql)) {
                ps.setInt(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        ResultSetMetaData md = rs.getMetaData();
                        for (int i = 1; i <= md.getColumnCount(); i++) {
                            latestMeasurement.put(md.getColumnName(i), rs.getObject(i));
                        }
                    }
                }
            }

            String latestHarmonicSql =
                "SELECT TOP 1 * FROM dbo.harmonic_measurements WHERE meter_id = ? ORDER BY measured_at DESC";
            try (PreparedStatement ps = conn.prepareStatement(latestHarmonicSql)) {
                ps.setInt(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        ResultSetMetaData md = rs.getMetaData();
                        for (int i = 1; i <= md.getColumnCount(); i++) {
                            latestHarmonicMeasurement.put(md.getColumnName(i), rs.getObject(i));
                        }
                    }
                }
            }
        }
    } catch (Exception e) {
        error = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }

    String[] groupOrder = new String[]{"전압", "전류", "전력/에너지", "전압 고조파", "전류 고조파", "위상각", "기타"};
    for (String groupName : groupOrder) latestTokenGroups.put(groupName, new ArrayList<Map<String, Object>>());
    for (Map<String, Object> r : latestTokenRows) {
        String groupName = classifyTokenGroup((String)r.get("token"));
        List<Map<String, Object>> bucket = latestTokenGroups.get(groupName);
        if (bucket == null) {
            bucket = new ArrayList<Map<String, Object>>();
            latestTokenGroups.put(groupName, bucket);
        }
        bucket.add(r);
    }
%>
<html>
<head>
    <title>AI Tag - Measurements Matching</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1500px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .section-title { margin: 14px 0 6px; font-size: 15px; font-weight: 700; color: #1f3347; }
        .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-ok { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-no { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; }
        .match-groups { display: flex; flex-direction: column; gap: 16px; margin-top: 8px; }
        .match-group { border: 1px solid #d8e2ee; border-radius: 14px; background: #f9fbfd; overflow: hidden; }
        .match-group-head { display: flex; justify-content: space-between; align-items: center; padding: 10px 14px; background: #eef4fa; border-bottom: 1px solid #d8e2ee; }
        .match-group-title { font-size: 15px; font-weight: 700; color: #1f3347; }
        .match-group-count { font-size: 12px; color: #54708b; }
        .match-card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; padding: 12px; }
        .match-card { border: 1px solid #dbe6f0; border-radius: 12px; background: #fff; padding: 12px; box-shadow: 0 1px 2px rgba(20, 48, 76, 0.06); }
        .match-card-top { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin-bottom: 8px; }
        .match-card-token { font-size: 15px; font-weight: 700; color: #15324b; }
        .match-card-index { font-size: 11px; color: #6b7f93; }
        .match-card-meta { display: grid; grid-template-columns: 96px 1fr; gap: 4px 8px; font-size: 12px; margin-top: 8px; }
        .match-card-meta dt { margin: 0; color: #70859a; font-weight: 700; }
        .match-card-meta dd { margin: 0; color: #1f3347; }
        .match-values { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
        .match-value-box { border-radius: 10px; padding: 10px; }
        .match-value-box.plc { background: #edf7ff; border: 1px solid #cfe7fb; }
        .match-value-box.target { background: #eef9f0; border: 1px solid #d7efd8; }
        .match-value-label { font-size: 11px; color: #587086; margin-bottom: 4px; }
        .match-value-num { font-size: 20px; font-weight: 700; color: #14324a; line-height: 1.1; }
        .match-empty { padding: 16px; border: 1px dashed #c7d4e2; border-radius: 12px; background: #f8fbfe; color: #60768a; font-size: 13px; }
        @media (max-width: 768px) {
            .match-card-grid { grid-template-columns: 1fr; }
            .match-values { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🔗 AI 태그 - measurements 매칭</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/ai_mapping.jsp'">AI 매핑</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        기준: <span class="mono">dbo.plc_ai_measurements_match</span>와 현재 <span class="mono">plc_meter_map</span> 매핑 기준 비교 화면입니다.<br/>
        참고: <span class="mono">PV1/PV2/PV3</span>, <span class="mono">PI1/PI2/PI3</span>는 현재 화면에서 위상각 의미로 표시됩니다.
    </div>

    <% if (error != null) { %>
    <div class="err-box">DB 오류: <%= h(error) %></div>
    <% } %>

    <form method="GET" class="toolbar">
        <label for="plc_id">PLC:</label>
        <select id="plc_id" name="plc_id">
            <option value="">선택</option>
            <% for (Map<String, Object> p : plcList) { %>
            <% String v = String.valueOf(p.get("plc_id")); %>
            <option value="<%= v %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                PLC <%= p.get("plc_id") %> - <%= h(p.get("plc_ip")) %>:<%= p.get("plc_port") %>
            </option>
            <% } %>
        </select>

        <label for="meter_id">Meter:</label>
        <select id="meter_id" name="meter_id">
            <option value="">선택</option>
            <% for (Map<String, Object> m : meterList) { %>
            <% String v = String.valueOf(m.get("meter_id")); %>
            <option value="<%= v %>" <%= (meterId != null && meterId.toString().equals(v)) ? "selected" : "" %>>
                #<%= m.get("meter_id") %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
            </option>
            <% } %>
        </select>
        <button type="submit">검증 조회</button>
    </form>

    <div class="section-title">1) 실측 비교 결과</div>
    <% if (latestTokenRows.isEmpty()) { %>
    <div class="match-empty">PLC와 Meter를 선택한 뒤 검증 데이터를 조회하세요.</div>
    <% } else { %>
    <div class="match-groups">
        <% for (Map.Entry<String, List<Map<String, Object>>> entry : latestTokenGroups.entrySet()) { %>
            <% if (entry.getValue().isEmpty()) continue; %>
            <div class="match-group">
                <div class="match-group-head">
                    <div class="match-group-title"><%= h(entry.getKey()) %></div>
                    <div class="match-group-count"><%= entry.getValue().size() %>개 항목</div>
                </div>
                <div class="match-card-grid">
                    <% for (Map<String, Object> r : entry.getValue()) { %>
                        <%
                            String col = (String)r.get("measurement_column");
                            String tokenMeaning = describeTokenMeaning((String)r.get("token"));
                            String targetTable = null;
                            for (Map<String, Object> mr : mappingRows) {
                                if (col != null && col.equals(mr.get("measurement_column")) && String.valueOf(r.get("float_index")).equals(String.valueOf(mr.get("float_index")))) {
                                    targetTable = (String)mr.get("target_table");
                                    break;
                                }
                            }
                            Object mv = null;
                            if (col != null) {
                                if ("harmonic_measurements".equalsIgnoreCase(targetTable)) mv = latestHarmonicMeasurement.get(col);
                                else mv = latestMeasurement.get(col);
                            }
                        %>
                        <div class="match-card">
                            <div class="match-card-top">
                                <div class="match-card-token mono"><%= h(r.get("token")) %></div>
                                <div class="match-card-index mono">#<%= r.get("float_index") %></div>
                            </div>
                            <div class="match-values">
                                <div class="match-value-box plc">
                                    <div class="match-value-label">PLC 샘플값</div>
                                    <div class="match-value-num mono"><%= h(fmtNum2(r.get("value_float"))) %></div>
                                </div>
                                <div class="match-value-box target">
                                    <div class="match-value-label">최신 적재값</div>
                                    <div class="match-value-num mono"><%= h(fmtNum2(mv)) %></div>
                                </div>
                            </div>
                            <dl class="match-card-meta">
                                <dt>실제 의미</dt><dd><%= tokenMeaning == null || tokenMeaning.isEmpty() ? "-" : h(tokenMeaning) %></dd>
                                <dt>컬럼</dt><dd class="mono"><%= h(col) %></dd>
                                <dt>대상 테이블</dt><dd class="mono"><%= targetTable == null ? "-" : h(targetTable) %></dd>
                                <dt>레지스터</dt><dd class="mono"><%= r.get("reg_address") %></dd>
                                <dt>PLC 샘플시각</dt><dd><%= r.get("measured_at") == null ? "-" : h(r.get("measured_at")) %></dd>
                            </dl>
                        </div>
                    <% } %>
                </div>
            </div>
        <% } %>
    </div>
    <% } %>

    <div class="section-title">2) 매핑 정의</div>
    <table>
        <thead>
        <tr>
            <th>float_index</th>
            <th>tag token</th>
            <th>float_regs</th>
            <th>measurement_column</th>
            <th>supported</th>
            <th>target_table</th>
            <th>note</th>
        </tr>
        </thead>
        <tbody>
        <% for (Map<String, Object> r : mappingRows) { %>
        <tr>
            <td class="mono"><%= r.get("float_index") %></td>
            <td class="mono"><%= h(r.get("token")) %></td>
            <td class="mono"><%= r.get("float_registers") %></td>
            <td class="mono"><%= r.get("measurement_column") == null ? "-" : h(r.get("measurement_column")) %></td>
            <td>
                <% if ((Boolean)r.get("is_supported")) { %><span class="badge b-ok">YES</span><% } else { %><span class="badge b-no">NO</span><% } %>
            </td>
            <td class="mono"><%= h(r.get("target_table")) %></td>
            <td><%= r.get("note") == null ? "-" : h(r.get("note")) %></td>
        </tr>
        <% } %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
