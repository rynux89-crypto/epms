<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String nvl(String v) {
        return v == null ? "" : v.trim();
    }

    private static String normText(String v) {
        String s = nvl(v).toUpperCase(Locale.ROOT);
        s = s.replace("\n", " ").replace("\r", " ");
        s = s.replaceAll("\\s+", " ");
        return s.trim();
    }

    private static boolean containsAny(String s, String... parts) {
        if (s == null || s.isEmpty() || parts == null) return false;
        for (String p : parts) {
            if (p != null && !p.isEmpty() && s.contains(p)) return true;
        }
        return false;
    }

    private static LinkedHashSet<String> inferGroupKeys(String tagName, String itemName, String panelName) {
        String tag = normText(tagName);
        String item = normText(itemName);
        String panel = normText(panelName);
        LinkedHashSet<String> out = new LinkedHashSet<>();

        if (containsAny(tag, "TRIP", "TR ALARM", "TR_ALARM")) out.add("TRIP");
        if (containsAny(tag, "OCGR", "51G", "50G")) out.add("OCGR");
        if ((containsAny(tag, "OCR", "\\50", "\\51", " 50", " 51") || containsAny(item, "OCR"))
                && !containsAny(tag, "OCGR", "51G", "50G")) {
            out.add("OCR");
        }
        if ((containsAny(tag, "OVR", "\\59", " 59") || containsAny(item, "OVR"))
                && !containsAny(tag, "OCR", "OCGR", "51G", "50G")) {
            out.add("OVR");
        }
        if (containsAny(tag, "ELD") || containsAny(item, "ELD") || containsAny(panel, "ELD")) out.add("ELD");
        if (containsAny(tag, "\\TM", "_TM", " TEMP", "TEMP") || containsAny(item, "TEMP", "TM")) out.add("TM");
        return out;
    }

    private static String metricKeyOf(String groupKey) {
        return "DI_GROUP_" + groupKey;
    }

    private static String displayNameOf(String groupKey) {
        if ("OCR".equals(groupKey)) return "DI 그룹 OCR";
        if ("OCGR".equals(groupKey)) return "DI 그룹 OCGR";
        if ("OVR".equals(groupKey)) return "DI 그룹 OVR";
        if ("TRIP".equals(groupKey)) return "DI 그룹 TRIP";
        if ("ELD".equals(groupKey)) return "DI 그룹 ELD";
        if ("TM".equals(groupKey)) return "DI 그룹 TM";
        if ("LIGHT".equals(groupKey)) return "DI 그룹 LIGHT";
        return "DI 그룹 " + groupKey;
    }

    private static List<String[]> defaultPatterns(String groupKey) {
        List<String[]> rows = new ArrayList<>();
        if ("OCR".equals(groupKey)) {
            rows.add(new String[]{"TAG_NAME", "OCR"});
            rows.add(new String[]{"TAG_NAME", "\\50"});
            rows.add(new String[]{"TAG_NAME", "\\51"});
        } else if ("OCGR".equals(groupKey)) {
            rows.add(new String[]{"TAG_NAME", "OCGR"});
            rows.add(new String[]{"TAG_NAME", "51G"});
            rows.add(new String[]{"TAG_NAME", "50G"});
        } else if ("OVR".equals(groupKey)) {
            rows.add(new String[]{"TAG_NAME", "OVR"});
            rows.add(new String[]{"TAG_NAME", "\\59"});
            rows.add(new String[]{"TAG_NAME", " 59"});
        } else if ("TRIP".equals(groupKey)) {
            rows.add(new String[]{"TAG_NAME", "TRIP"});
            rows.add(new String[]{"TAG_NAME", "TR ALARM"});
            rows.add(new String[]{"TAG_NAME", "TR_ALARM"});
        } else if ("ELD".equals(groupKey)) {
            rows.add(new String[]{"TAG_NAME", "ELD"});
        } else if ("TM".equals(groupKey)) {
            rows.add(new String[]{"TAG_NAME", "\\TM"});
            rows.add(new String[]{"TAG_NAME", "TEMP"});
        }
        return rows;
    }
%>
<%
    request.setCharacterEncoding("UTF-8");
    String self = request.getRequestURI();
    String msg = request.getParameter("msg");
    String err = request.getParameter("err");
    String plcParam = request.getParameter("plc_id");
    Integer plcId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}

    List<Map<String, Object>> plcList = new ArrayList<>();
    LinkedHashMap<String, Map<String, Object>> inferred = new LinkedHashMap<>();
    List<Map<String, Object>> groupMapRows = new ArrayList<>();
    List<Map<String, Object>> groupRuleRows = new ArrayList<>();

    try {
        String ensureSql =
            "IF OBJECT_ID('dbo.di_signal_group_map','U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.di_signal_group_map ( " +
            "    group_map_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY, " +
            "    group_key VARCHAR(100) NOT NULL, " +
            "    metric_key VARCHAR(100) NOT NULL, " +
            "    match_type VARCHAR(30) NOT NULL, " +
            "    match_value VARCHAR(200) NOT NULL, " +
            "    priority INT NOT NULL DEFAULT 100, " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    description NVARCHAR(300) NULL, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "  CREATE UNIQUE INDEX ux_di_signal_group_map_key ON dbo.di_signal_group_map(group_key, metric_key, match_type, match_value); " +
            "END; " +
            "IF OBJECT_ID('dbo.di_group_rule_map','U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.di_group_rule_map ( " +
            "    group_rule_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY, " +
            "    metric_key VARCHAR(100) NOT NULL, " +
            "    match_mode VARCHAR(20) NOT NULL DEFAULT 'ANY_ON', " +
            "    count_threshold INT NULL, " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    description NVARCHAR(300) NULL, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "  CREATE UNIQUE INDEX ux_di_group_rule_map_metric ON dbo.di_group_rule_map(metric_key); " +
            "END; " +
            "IF OBJECT_ID('dbo.metric_catalog','U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.metric_catalog ( " +
            "    metric_key VARCHAR(100) NOT NULL PRIMARY KEY, " +
            "    display_name NVARCHAR(150) NULL, " +
            "    source_type VARCHAR(20) NOT NULL DEFAULT 'AI', " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "END;";
        try (Statement st = conn.createStatement()) {
            st.execute(ensureSql);
        }

        if ("POST".equalsIgnoreCase(request.getMethod()) && "seed_defaults".equals(request.getParameter("action"))) {
            StringBuilder where = new StringBuilder(" WHERE enabled = 1 ");
            List<Integer> seedParams = new ArrayList<>();
            if (plcId != null) { where.append("AND plc_id = ? "); seedParams.add(plcId); }

            LinkedHashSet<String> keysToSeed = new LinkedHashSet<>();
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT tag_name, item_name, panel_name FROM dbo.plc_di_tag_map " + where.toString())) {
                for (int i = 0; i < seedParams.size(); i++) ps.setInt(i + 1, seedParams.get(i));
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        keysToSeed.addAll(inferGroupKeys(rs.getString("tag_name"), rs.getString("item_name"), rs.getString("panel_name")));
                    }
                }
            }

            String mergeMetricSql =
                "MERGE dbo.metric_catalog t USING (SELECT ? AS metric_key) s ON (t.metric_key = s.metric_key) " +
                "WHEN MATCHED THEN UPDATE SET display_name=?, source_type='DI', enabled=1, updated_at=SYSUTCDATETIME() " +
                "WHEN NOT MATCHED THEN INSERT (metric_key, display_name, source_type, enabled, created_at, updated_at) VALUES (?, ?, 'DI', 1, SYSUTCDATETIME(), SYSUTCDATETIME());";
            String mergeGroupRuleSql =
                "MERGE dbo.di_group_rule_map t USING (SELECT ? AS metric_key) s ON (t.metric_key = s.metric_key) " +
                "WHEN MATCHED THEN UPDATE SET match_mode='ANY_ON', enabled=1, updated_at=SYSUTCDATETIME(), description=? " +
                "WHEN NOT MATCHED THEN INSERT (metric_key, match_mode, count_threshold, enabled, description, created_at, updated_at) VALUES (?, 'ANY_ON', NULL, 1, ?, SYSUTCDATETIME(), SYSUTCDATETIME());";
            String mergeGroupMapSql =
                "MERGE dbo.di_signal_group_map t USING (SELECT ? AS group_key, ? AS metric_key, ? AS match_type, ? AS match_value) s " +
                "ON (t.group_key=s.group_key AND t.metric_key=s.metric_key AND t.match_type=s.match_type AND t.match_value=s.match_value) " +
                "WHEN MATCHED THEN UPDATE SET enabled=1, updated_at=SYSUTCDATETIME(), description=? " +
                "WHEN NOT MATCHED THEN INSERT (group_key, metric_key, match_type, match_value, priority, enabled, description, created_at, updated_at) VALUES (?, ?, ?, ?, 100, 1, ?, SYSUTCDATETIME(), SYSUTCDATETIME());";
            String mergeAlarmRuleSql =
                "MERGE dbo.alarm_rule t USING (SELECT ? AS rule_code) s ON (t.rule_code = s.rule_code) " +
                "WHEN MATCHED THEN UPDATE SET metric_key=?, target_scope='PLC', operator='>=', threshold1=1, threshold2=NULL, duration_sec=0, hysteresis=NULL, severity=?, enabled=1, source_token=?, message_template=?, description=?, updated_at=SYSUTCDATETIME() " +
                "WHEN NOT MATCHED THEN INSERT (rule_code, rule_name, category, target_scope, metric_key, operator, threshold1, threshold2, duration_sec, hysteresis, severity, enabled, source_token, message_template, description, created_at, updated_at) " +
                "VALUES (?, ?, 'PROTECTION', 'PLC', ?, '>=', 1, NULL, 0, NULL, ?, 1, ?, ?, ?, SYSUTCDATETIME(), SYSUTCDATETIME());";

            try (
                PreparedStatement psMetric = conn.prepareStatement(mergeMetricSql);
                PreparedStatement psRule = conn.prepareStatement(mergeGroupRuleSql);
                PreparedStatement psMap = conn.prepareStatement(mergeGroupMapSql);
                PreparedStatement psAlarmRule = conn.prepareStatement(mergeAlarmRuleSql)
            ) {
                for (String groupKey : keysToSeed) {
                    String metricKey = metricKeyOf(groupKey);
                    String displayName = displayNameOf(groupKey);
                    String desc = "DI 매핑 추론 기반 기본 그룹";
                    String ruleCode = metricKey;
                    String severity = ("TM".equals(groupKey) ? "ALARM" : "CRITICAL");
                    String msgTpl = "{metric_key}=1 감지";

                    psMetric.setString(1, metricKey);
                    psMetric.setString(2, displayName);
                    psMetric.setString(3, metricKey);
                    psMetric.setString(4, displayName);
                    psMetric.executeUpdate();

                    psRule.setString(1, metricKey);
                    psRule.setString(2, desc);
                    psRule.setString(3, metricKey);
                    psRule.setString(4, desc);
                    psRule.executeUpdate();

                    psAlarmRule.setString(1, ruleCode);
                    psAlarmRule.setString(2, metricKey);
                    psAlarmRule.setString(3, severity);
                    psAlarmRule.setString(4, metricKey);
                    psAlarmRule.setString(5, msgTpl);
                    psAlarmRule.setString(6, desc);
                    psAlarmRule.setString(7, ruleCode);
                    psAlarmRule.setString(8, displayName);
                    psAlarmRule.setString(9, metricKey);
                    psAlarmRule.setString(10, severity);
                    psAlarmRule.setString(11, metricKey);
                    psAlarmRule.setString(12, msgTpl);
                    psAlarmRule.setString(13, desc);
                    psAlarmRule.executeUpdate();

                    for (String[] pattern : defaultPatterns(groupKey)) {
                        psMap.setString(1, groupKey);
                        psMap.setString(2, metricKey);
                        psMap.setString(3, pattern[0]);
                        psMap.setString(4, pattern[1]);
                        psMap.setString(5, desc);
                        psMap.setString(6, groupKey);
                        psMap.setString(7, metricKey);
                        psMap.setString(8, pattern[0]);
                        psMap.setString(9, pattern[1]);
                        psMap.setString(10, desc);
                        psMap.executeUpdate();
                    }
                }
            }
            response.sendRedirect(self + (plcId == null ? "" : ("?plc_id=" + plcId)) + (plcId == null ? "?msg=" : "&msg=") + URLEncoder.encode("추론 그룹 기본 등록을 완료했습니다.", "UTF-8"));
            return;
        }

        try (PreparedStatement ps = conn.prepareStatement("SELECT plc_id, plc_ip, plc_port, unit_id, enabled FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> p = new HashMap<>();
                p.put("plc_id", rs.getInt("plc_id"));
                p.put("plc_ip", rs.getString("plc_ip"));
                p.put("plc_port", rs.getInt("plc_port"));
                p.put("unit_id", rs.getInt("unit_id"));
                p.put("enabled", rs.getBoolean("enabled"));
                plcList.add(p);
            }
        }

        StringBuilder infSql = new StringBuilder(
            "SELECT plc_id, point_id, di_address, bit_no, tag_name, item_name, panel_name " +
            "FROM dbo.plc_di_tag_map WHERE enabled = 1 ");
        List<Integer> infParams = new ArrayList<>();
        if (plcId != null) { infSql.append("AND plc_id = ? "); infParams.add(plcId); }
        infSql.append("ORDER BY plc_id, di_address, bit_no");
        try (PreparedStatement ps = conn.prepareStatement(infSql.toString())) {
            for (int i = 0; i < infParams.size(); i++) ps.setInt(i + 1, infParams.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String tagName = rs.getString("tag_name");
                    String itemName = rs.getString("item_name");
                    String panelName = rs.getString("panel_name");
                    for (String groupKey : inferGroupKeys(tagName, itemName, panelName)) {
                        Map<String, Object> bucket = inferred.get(groupKey);
                        if (bucket == null) {
                            bucket = new LinkedHashMap<>();
                            bucket.put("group_key", groupKey);
                            bucket.put("metric_key", metricKeyOf(groupKey));
                            bucket.put("bit_count", 0);
                            bucket.put("samples", new LinkedHashSet<String>());
                            inferred.put(groupKey, bucket);
                        }
                        bucket.put("bit_count", ((Integer) bucket.get("bit_count")) + 1);
                        @SuppressWarnings("unchecked")
                        LinkedHashSet<String> samples = (LinkedHashSet<String>) bucket.get("samples");
                        if (samples.size() < 8) {
                            samples.add(nvl(tagName).isEmpty() ? (nvl(itemName) + " / " + nvl(panelName)) : tagName);
                        }
                    }
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT group_map_id, group_key, metric_key, match_type, match_value, priority, enabled, updated_at " +
                "FROM dbo.di_signal_group_map ORDER BY group_key, match_type, match_value");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("group_map_id", rs.getInt("group_map_id"));
                r.put("group_key", rs.getString("group_key"));
                r.put("metric_key", rs.getString("metric_key"));
                r.put("match_type", rs.getString("match_type"));
                r.put("match_value", rs.getString("match_value"));
                r.put("priority", rs.getInt("priority"));
                r.put("enabled", rs.getBoolean("enabled"));
                r.put("updated_at", rs.getTimestamp("updated_at"));
                groupMapRows.add(r);
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT group_rule_id, metric_key, match_mode, count_threshold, enabled, updated_at, description " +
                "FROM dbo.di_group_rule_map ORDER BY metric_key");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("group_rule_id", rs.getInt("group_rule_id"));
                r.put("metric_key", rs.getString("metric_key"));
                r.put("match_mode", rs.getString("match_mode"));
                r.put("count_threshold", rs.getObject("count_threshold"));
                r.put("enabled", rs.getBoolean("enabled"));
                r.put("updated_at", rs.getTimestamp("updated_at"));
                r.put("description", rs.getString("description"));
                groupRuleRows.add(r);
            }
        }
    } catch (Exception e) {
        err = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%>
<html>
<head>
    <title>DI 그룹 관리</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1500px; margin: 0 auto; }
        .note-box, .ok-box, .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; font-size: 13px; }
        .note-box { background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; }
        .ok-box { background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; }
        .err-box { background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; }
        .toolbar { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .badge { display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; font-weight:700; }
        .on { background:#e8f7ec; border:1px solid #b9e6c6; color:#1b7f3b; }
        .off { background:#fff3e0; border:1px solid #ffd8a8; color:#b45309; }
        .section-title { margin:14px 0 6px; font-size:15px; font-weight:700; color:#1f3347; }
        .sample-list { margin:0; padding-left:18px; }
        .sample-list li { margin:2px 0; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🧩 DI 그룹 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/alarm_rule_manage.jsp'">알람 규칙 관리</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="ok-box"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="err-box"><%= h(err) %></div><% } %>

    <div class="note-box">
        활성 DI 매핑(<span class="mono">plc_di_tag_map.enabled=1</span>)을 기준으로 그룹 후보를 추론합니다.<br/>
        현재 프로젝트에 존재하는 DI만 후보로 보이며, 없는 그룹(예: ELD)은 나타나지 않습니다.
    </div>

    <form method="get" class="toolbar">
        <label for="plc_id">PLC:</label>
        <select id="plc_id" name="plc_id">
            <option value="">전체</option>
            <% for (Map<String, Object> p : plcList) { String v = String.valueOf(p.get("plc_id")); %>
            <option value="<%= v %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                PLC <%= p.get("plc_id") %> - <%= h(p.get("plc_ip")) %>:<%= p.get("plc_port") %>
            </option>
            <% } %>
        </select>
        <button type="submit">조회</button>
    </form>

    <form method="post" class="toolbar" style="margin-top:8px;">
        <input type="hidden" name="action" value="seed_defaults">
        <% if (plcId != null) { %><input type="hidden" name="plc_id" value="<%= plcId %>"><% } %>
        <button type="submit" onclick="return confirm('현재 추론된 그룹 후보를 기본 규칙/매핑으로 등록하시겠습니까?');">추론 그룹 기본 등록</button>
    </form>

    <div class="section-title">1) 추론 그룹 후보</div>
    <table>
        <thead>
        <tr>
            <th>group_key</th>
            <th>metric_key</th>
            <th>bit_count</th>
            <th>sample tags</th>
        </tr>
        </thead>
        <tbody>
        <% if (inferred.isEmpty()) { %>
        <tr><td colspan="4">추론된 그룹 후보가 없습니다.</td></tr>
        <% } else { for (Map<String, Object> r : inferred.values()) { %>
        <tr>
            <td class="mono"><%= h(r.get("group_key")) %></td>
            <td class="mono"><%= h(r.get("metric_key")) %></td>
            <td class="mono"><%= h(r.get("bit_count")) %></td>
            <td>
                <ul class="sample-list">
                    <% @SuppressWarnings("unchecked") LinkedHashSet<String> samples = (LinkedHashSet<String>) r.get("samples");
                       for (String s : samples) { %>
                    <li><%= h(s) %></li>
                    <% } %>
                </ul>
            </td>
        </tr>
        <% }} %>
        </tbody>
    </table>

    <div class="section-title">2) 그룹 비트 매핑</div>
    <table>
        <thead>
        <tr>
            <th>id</th>
            <th>group_key</th>
            <th>metric_key</th>
            <th>match_type</th>
            <th>match_value</th>
            <th>priority</th>
            <th>enabled</th>
            <th>updated_at</th>
        </tr>
        </thead>
        <tbody>
        <% if (groupMapRows.isEmpty()) { %>
        <tr><td colspan="8">등록된 그룹 비트 매핑이 없습니다.</td></tr>
        <% } else { for (Map<String, Object> r : groupMapRows) { %>
        <tr>
            <td class="mono"><%= h(r.get("group_map_id")) %></td>
            <td class="mono"><%= h(r.get("group_key")) %></td>
            <td class="mono"><%= h(r.get("metric_key")) %></td>
            <td class="mono"><%= h(r.get("match_type")) %></td>
            <td class="mono"><%= h(r.get("match_value")) %></td>
            <td class="mono"><%= h(r.get("priority")) %></td>
            <td><% if ((Boolean) r.get("enabled")) { %><span class="badge on">ON</span><% } else { %><span class="badge off">OFF</span><% } %></td>
            <td class="mono"><%= h(r.get("updated_at")) %></td>
        </tr>
        <% }} %>
        </tbody>
    </table>

    <div class="section-title">3) 그룹 집계 규칙</div>
    <table>
        <thead>
        <tr>
            <th>id</th>
            <th>metric_key</th>
            <th>match_mode</th>
            <th>count_threshold</th>
            <th>enabled</th>
            <th>description</th>
            <th>updated_at</th>
        </tr>
        </thead>
        <tbody>
        <% if (groupRuleRows.isEmpty()) { %>
        <tr><td colspan="7">등록된 그룹 집계 규칙이 없습니다.</td></tr>
        <% } else { for (Map<String, Object> r : groupRuleRows) { %>
        <tr>
            <td class="mono"><%= h(r.get("group_rule_id")) %></td>
            <td class="mono"><%= h(r.get("metric_key")) %></td>
            <td class="mono"><%= h(r.get("match_mode")) %></td>
            <td class="mono"><%= h(r.get("count_threshold")) %></td>
            <td><% if ((Boolean) r.get("enabled")) { %><span class="badge on">ON</span><% } else { %><span class="badge off">OFF</span><% } %></td>
            <td><%= h(r.get("description")) %></td>
            <td class="mono"><%= h(r.get("updated_at")) %></td>
        </tr>
        <% }} %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
