<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private String fmt(Object value, int scale) {
        if (value == null) return "--";
        try {
            double v = value instanceof Number ? ((Number)value).doubleValue() : Double.parseDouble(String.valueOf(value));
            return String.format(java.util.Locale.US, "%,." + scale + "f", v);
        } catch (Exception ignore) {
            return String.valueOf(value);
        }
    }

    private String dt(Object value) {
        if (value == null) return "미수집";
        String s = String.valueOf(value).replace('T', ' ').replace('-', '/');
        int dot = s.indexOf('.');
        if (dot > 0) s = s.substring(0, dot);
        if (s.length() >= 19) s = s.substring(0, 19);
        return s;
    }

    private boolean isBlank(Object value) {
        return value == null || String.valueOf(value).trim().isEmpty();
    }

    private boolean isCommBad(Map<String, Object> row) {
        Object raw = row.get("last_comm_status");
        if (raw == null) return false;
        String comm = String.valueOf(raw);
        return comm != null && !comm.trim().isEmpty() && !"OK".equalsIgnoreCase(comm);
    }

    private String statusClass(Map<String, Object> row) {
        Object measured = row.get("measured_at");
        int alarms = intValue(row.get("active_alarm_count"));
        if (isCommBad(row)) return "comm";
        if (measured == null) return "unknown";
        if (alarms > 0) return "alarm";
        return "normal";
    }

    private String statusText(Map<String, Object> row) {
        String cls = statusClass(row);
        if ("normal".equals(cls)) return "정상";
        if ("alarm".equals(cls)) return "알람";
        if ("comm".equals(cls)) return "통신불량";
        return "미수집";
    }

    private int intValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Number) return ((Number)value).intValue();
        try { return Integer.parseInt(String.valueOf(value)); } catch (Exception ignore) { return 0; }
    }

    private String overviewValue(Map<String, Object> row, String key, int scale, String unit) {
        if ("comm".equals(statusClass(row))) return "-";
        String value = fmt(row.get(key), scale);
        return unit == null || unit.isEmpty() ? value : value + unit;
    }

    private String overviewDate(Map<String, Object> row) {
        return "comm".equals(statusClass(row)) ? "-" : dt(row.get("measured_at"));
    }

    private String readUrl(String urlText, int timeoutMs) {
        java.net.HttpURLConnection conn = null;
        try {
            java.net.URL url = new java.net.URL(urlText);
            conn = (java.net.HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setRequestMethod("GET");
            try (java.io.BufferedReader br = new java.io.BufferedReader(new java.io.InputStreamReader(conn.getInputStream(), "UTF-8"))) {
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

    private java.math.BigDecimal jsonDecimal(String json, String key) {
        if (json == null) return null;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)");
            java.util.regex.Matcher m = p.matcher(json);
            return m.find() ? new java.math.BigDecimal(m.group(1)) : null;
        } catch (Exception ignore) {
            return null;
        }
    }

    private String jsonText(String json, String key, String fallback) {
        if (json == null) return fallback;
        try {
            java.util.regex.Pattern p = java.util.regex.Pattern.compile("\"" + java.util.regex.Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"");
            java.util.regex.Matcher m = p.matcher(json);
            return m.find() ? m.group(1) : fallback;
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private void putJsonDecimal(Map<String, Object> target, String json, String jsonKey, String metricKey) {
        java.math.BigDecimal value = jsonDecimal(json, jsonKey);
        if (value != null) target.put(metricKey, value);
    }

    private void putIfMissing(Map<String, Object> target, String metricKey, String value) {
        if (target.get(metricKey) == null && value != null) {
            target.put(metricKey, new java.math.BigDecimal(value));
        }
    }

    private void applySimulatorDefaults(Map<String, Object> target, String scenario) {
        putIfMissing(target, "load_percent", "42");
        putIfMissing(target, "output_power_kw", "40");
        putIfMissing(target, "output_apparent_total_kva", "43");
        putIfMissing(target, "frequency", "60.0");
        putIfMissing(target, "battery_temperature", "28.5");
        if ("battery".equals(scenario)) {
            target.put("remaining_minutes", new java.math.BigDecimal("45"));
            target.put("battery_charge_percent", new java.math.BigDecimal("72"));
        } else if ("low_battery".equals(scenario)) {
            target.put("remaining_minutes", new java.math.BigDecimal("7"));
            target.put("battery_charge_percent", new java.math.BigDecimal("8"));
        } else if ("critical".equals(scenario)) {
            target.put("remaining_minutes", new java.math.BigDecimal("120"));
            target.put("battery_charge_percent", new java.math.BigDecimal("5"));
        } else {
            target.put("remaining_minutes", new java.math.BigDecimal("120"));
            if (target.get("battery_charge_percent") == null) target.put("battery_charge_percent", new java.math.BigDecimal("96"));
        }
    }

    private void applySimulatorStatus(Map<String, Object> row) {
        if (!"127.0.0.1".equals(String.valueOf(row.get("ip_address"))) ||
            !"1502".equals(String.valueOf(row.get("modbus_port")))) {
            return;
        }
        String simStatus = readUrl("http://127.0.0.1:1503/api/status", 250);
        if (simStatus == null || simStatus.trim().isEmpty()) return;

        String scenario = jsonText(simStatus, "scenario", "normal");
        putJsonDecimal(row, simStatus, "output_load_percent", "load_percent");
        putJsonDecimal(row, simStatus, "output_power_kw", "output_power_kw");
        putJsonDecimal(row, simStatus, "output_apparent_total_kva", "output_apparent_total_kva");
        putJsonDecimal(row, simStatus, "output_frequency_hz", "frequency");
        putJsonDecimal(row, simStatus, "battery_charge_percent", "battery_charge_percent");
        putJsonDecimal(row, simStatus, "battery_temperature_c", "battery_temperature");
        putJsonDecimal(row, simStatus, "remaining_minutes", "remaining_minutes");
        applySimulatorDefaults(row, scenario);
        row.put("measured_at", new java.sql.Timestamp(System.currentTimeMillis()));
        row.put("last_comm_status", "OK");
        if ("normal".equals(scenario)) {
            row.put("active_alarm_count", Integer.valueOf(0));
        } else if (intValue(row.get("active_alarm_count")) == 0) {
            row.put("active_alarm_count", Integer.valueOf(1));
        }
    }
%>
<%
request.setCharacterEncoding("UTF-8");
List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
String err = null;

try (Connection conn = openUpsDbConnection();
     PreparedStatement ps = conn.prepareStatement(
        "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.last_comm_status, " +
        "m.measured_at, m.load_percent, m.output_power_kw, m.output_apparent_total_kva, m.frequency, " +
        "m.battery_charge_percent, m.battery_temperature, m.remaining_minutes, m.ups_operation_mode_code, " +
        "ISNULL(a.active_alarm_count, 0) AS active_alarm_count " +
        "FROM dbo.ups_device d " +
        "OUTER APPLY (SELECT TOP 1 * FROM dbo.ups_measurement m WHERE m.ups_id = d.ups_id ORDER BY m.measured_at DESC) m " +
        "OUTER APPLY (SELECT COUNT(*) AS active_alarm_count FROM dbo.ups_alarm_log a WHERE a.ups_id = d.ups_id AND a.status = 'ACTIVE') a " +
        "WHERE d.enabled = 1 ORDER BY d.ups_name")) {
    try (ResultSet rs = ps.executeQuery()) {
        ResultSetMetaData md = rs.getMetaData();
        while (rs.next()) {
            Map<String, Object> row = new HashMap<String, Object>();
            for (int i = 1; i <= md.getColumnCount(); i++) row.put(md.getColumnLabel(i), rs.getObject(i));
            rows.add(row);
        }
    }
} catch (Exception e) {
    err = e.getMessage();
}

for (Map<String, Object> row : rows) {
    applySimulatorStatus(row);
}

int normalCount = 0;
int alarmCount = 0;
int commCount = 0;
int unknownCount = 0;
for (Map<String, Object> row : rows) {
    String cls = statusClass(row);
    if ("normal".equals(cls)) normalCount++;
    else if ("alarm".equals(cls)) alarmCount++;
    else if ("comm".equals(cls)) commCount++;
    else unknownCount++;
}
%>
<!doctype html>
<html lang="ko">
<head>
    <title>UPS 전체 현황</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .overview-actions { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
        .refresh-state { color:#64748b; font-size:12px; min-width:98px; text-align:right; }
        .filter-bar { display:flex; justify-content:space-between; align-items:center; gap:10px; margin:0 0 12px; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:10px; }
        .filter-input-wrap { display:flex; align-items:center; gap:8px; flex:1; min-width:260px; }
        .filter-input-wrap label { color:#475569; font-size:13px; font-weight:800; white-space:nowrap; }
        .filter-input-wrap input { width:100%; max-width:420px; border:1px solid #cbd8e6; border-radius:6px; padding:9px 10px; font-size:14px; }
        .filter-count { color:#64748b; font-size:13px; white-space:nowrap; }
        .clear-filter { border:1px solid #cbd8e6; border-radius:6px; background:#fff; color:#172033; padding:8px 11px; cursor:pointer; }
        .view-toggle { display:inline-flex; border:1px solid #cbd8e6; border-radius:6px; overflow:hidden; background:#fff; }
        .view-toggle button { border:0; border-right:1px solid #cbd8e6; background:#fff; color:#172033; padding:8px 12px; cursor:pointer; }
        .view-toggle button:last-child { border-right:0; }
        .view-toggle button.active { background:#1267b1; color:#fff; }
        .summary-grid { display:grid; grid-template-columns:repeat(5,minmax(120px,1fr)); gap:10px; margin:14px 0; }
        .summary-item { background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:12px; }
        .summary-item span { display:block; color:#64748b; font-size:12px; margin-bottom:4px; }
        .summary-item strong { font-size:24px; color:#172033; }
        .tiles-wrap { display:grid; grid-template-columns:repeat(auto-fill,minmax(245px,1fr)); gap:12px; }
        .ups-board.tiles { display:block; }
        .ups-tile { display:block; color:#172033; text-decoration:none; background:#fff; border:1px solid #dbe5f2; border-left:7px solid #94a3b8; border-radius:8px; padding:13px; min-height:188px; }
        .ups-tile.normal { border-left-color:#16a34a; }
        .ups-tile.alarm { border-left-color:#f59e0b; }
        .ups-tile.comm { border-left-color:#dc2626; }
        .ups-tile.unknown { border-left-color:#64748b; }
        .tile-head { display:flex; justify-content:space-between; gap:10px; align-items:flex-start; margin-bottom:10px; }
        .tile-name { font-size:17px; font-weight:800; line-height:1.25; }
        .tile-meta { color:#64748b; font-size:12px; margin-top:3px; line-height:1.35; }
        .status-badge { display:inline-flex; align-items:center; min-width:62px; justify-content:center; border-radius:999px; padding:4px 8px; font-size:12px; font-weight:800; background:#eef2f7; color:#334155; white-space:nowrap; }
        .status-badge.normal { background:#dcfce7; color:#166534; }
        .status-badge.alarm { background:#fef3c7; color:#92400e; }
        .status-badge.comm { background:#fee2e2; color:#991b1b; }
        .status-badge.unknown { background:#e2e8f0; color:#334155; }
        .tile-metrics { display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:10px; }
        .metric { border-top:1px solid #edf2f7; padding-top:7px; }
        .metric span { display:block; color:#64748b; font-size:12px; margin-bottom:2px; }
        .metric strong { font-size:18px; font-weight:400; }
        .tile-footer { display:flex; justify-content:space-between; gap:8px; color:#64748b; font-size:12px; margin-top:10px; padding-top:9px; border-top:1px solid #edf2f7; }
        .list-panel { display:none; background:#fff; border:1px solid #dbe5f2; border-radius:8px; overflow:auto; }
        .ups-board.list { display:block; }
        .ups-board.list .tiles-wrap { display:none; }
        .ups-board.list .list-panel { display:block; }
        .overview-table { width:100%; min-width:1120px; border-collapse:collapse; table-layout:fixed; }
        .overview-table th, .overview-table td { border-bottom:1px solid #edf2f7; padding:10px 11px; text-align:left; white-space:nowrap; }
        .overview-table th { background:#f8fafc; font-size:12px; color:#475569; }
        .overview-table td.num { text-align:right; }
        .overview-table .col-status { width:82px; }
        .overview-table .col-name { width:150px; }
        .overview-table .col-location { width:130px; }
        .overview-table .col-ip { width:150px; }
        .overview-table .col-measured { width:168px; }
        .overview-table .col-small { width:78px; }
        .overview-table .col-remain { width:92px; }
        .overview-table .measured-cell { font-family:Consolas,"Segoe UI",monospace; letter-spacing:0; }
        .empty-box { background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:22px; color:#64748b; text-align:center; }
        .filter-empty { display:none; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:22px; color:#64748b; text-align:center; }
        @media (max-width: 860px) {
            .summary-grid { grid-template-columns:repeat(2,minmax(120px,1fr)); }
            .filter-bar { display:block; }
            .filter-count { display:block; margin-top:8px; }
            .title-bar { display:block; }
            .overview-actions { margin-top:10px; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div>
            <h2>UPS 전체 현황</h2>
            <p class="muted">등록된 UPS의 최신 수집 상태를 타일 또는 리스트로 확인합니다.</p>
        </div>
        <div class="inline-actions overview-actions">
            <span class="refresh-state" id="refreshState">5초 후 갱신</span>
            <div class="view-toggle" aria-label="보기 방식">
                <button type="button" id="tileBtn" class="active">타일</button>
                <button type="button" id="listBtn">리스트</button>
            </div>
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <div class="summary-grid">
        <div class="summary-item"><span>전체</span><strong><%= rows.size() %></strong></div>
        <div class="summary-item"><span>정상</span><strong><%= normalCount %></strong></div>
        <div class="summary-item"><span>알람</span><strong><%= alarmCount %></strong></div>
        <div class="summary-item"><span>통신불량</span><strong><%= commCount %></strong></div>
        <div class="summary-item"><span>미수집</span><strong><%= unknownCount %></strong></div>
    </div>

    <div class="filter-bar">
        <div class="filter-input-wrap">
            <label for="upsFilter">검색</label>
            <input id="upsFilter" type="search" autocomplete="off" placeholder="UPS 이름 또는 위치">
            <button class="clear-filter" id="clearFilter" type="button">전체</button>
        </div>
        <div class="filter-count" id="filterCount">전체 <%= rows.size() %>대</div>
    </div>

    <% if (rows.isEmpty()) { %>
        <div class="empty-box">등록된 UPS가 없습니다.</div>
    <% } else { %>
    <div class="filter-empty" id="filterEmpty">검색 조건에 맞는 UPS가 없습니다.</div>
    <div id="upsBoard" class="ups-board tiles">
        <div class="tiles-wrap">
            <% for (Map<String, Object> r : rows) {
                String cls = statusClass(r);
                String detailUrl = "ups_status.jsp?ups_id=" + h(r.get("ups_id"));
                String filterText = String.valueOf(r.get("ups_name")) + " " + String.valueOf(r.get("location"));
            %>
            <a class="ups-tile <%= cls %>" href="<%= detailUrl %>" data-filter="<%= h(filterText) %>">
                <div class="tile-head">
                    <div>
                        <div class="tile-name"><%= h(r.get("ups_name")) %></div>
                        <div class="tile-meta"><%= h(r.get("location")) %><br><%= h(r.get("ip_address")) %>:<%= h(r.get("modbus_port")) %> / Unit <%= h(r.get("unit_id")) %></div>
                    </div>
                    <span class="status-badge <%= cls %>"><%= statusText(r) %></span>
                </div>
                <div class="tile-metrics">
                    <div class="metric"><span>부하율</span><strong><%= overviewValue(r, "load_percent", 1, "%") %></strong></div>
                    <div class="metric"><span>배터리</span><strong><%= overviewValue(r, "battery_charge_percent", 0, "%") %></strong></div>
                    <div class="metric"><span>출력</span><strong><%= overviewValue(r, "output_power_kw", 0, " kW") %></strong></div>
                    <div class="metric"><span>주파수</span><strong><%= overviewValue(r, "frequency", 1, " Hz") %></strong></div>
                </div>
                <div class="tile-footer">
                    <span>알람 <%= intValue(r.get("active_alarm_count")) %></span>
                    <span><%= overviewDate(r) %></span>
                </div>
            </a>
            <% } %>
        </div>

        <div class="list-panel">
            <table class="overview-table">
                <colgroup>
                    <col class="col-status">
                    <col class="col-name">
                    <col class="col-location">
                    <col class="col-ip">
                    <col class="col-measured">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-remain">
                    <col class="col-small">
                </colgroup>
                <thead>
                    <tr>
                        <th>상태</th><th>UPS</th><th>위치</th><th>IP</th><th>최근 수집</th>
                        <th>부하율</th><th>출력 kW</th><th>출력 kVA</th><th>주파수</th><th>배터리</th><th>온도</th><th>잔여시간</th><th>알람</th>
                    </tr>
                </thead>
                <tbody>
                <% for (Map<String, Object> r : rows) {
                    String cls = statusClass(r);
                    String filterText = String.valueOf(r.get("ups_name")) + " " + String.valueOf(r.get("location"));
                %>
                    <tr data-filter="<%= h(filterText) %>" onclick="location.href='ups_status.jsp?ups_id=<%= h(r.get("ups_id")) %>'" style="cursor:pointer;">
                        <td><span class="status-badge <%= cls %>"><%= statusText(r) %></span></td>
                        <td><%= h(r.get("ups_name")) %></td>
                        <td><%= h(r.get("location")) %></td>
                        <td><%= h(r.get("ip_address")) %>:<%= h(r.get("modbus_port")) %></td>
                        <td class="measured-cell"><%= overviewDate(r) %></td>
                        <td class="num"><%= overviewValue(r, "load_percent", 1, "%") %></td>
                        <td class="num"><%= overviewValue(r, "output_power_kw", 0, "") %></td>
                        <td class="num"><%= overviewValue(r, "output_apparent_total_kva", 0, "") %></td>
                        <td class="num"><%= overviewValue(r, "frequency", 1, "") %></td>
                        <td class="num"><%= overviewValue(r, "battery_charge_percent", 0, "%") %></td>
                        <td class="num"><%= overviewValue(r, "battery_temperature", 1, "°C") %></td>
                        <td class="num"><%= overviewValue(r, "remaining_minutes", 0, " Min") %></td>
                        <td class="num"><%= intValue(r.get("active_alarm_count")) %></td>
                    </tr>
                <% } %>
                </tbody>
            </table>
        </div>
    </div>
    <% } %>
</div>
<script>
(function () {
    var board = document.getElementById('upsBoard');
    var tileBtn = document.getElementById('tileBtn');
    var listBtn = document.getElementById('listBtn');
    var refreshState = document.getElementById('refreshState');
    var filterInput = document.getElementById('upsFilter');
    var clearFilter = document.getElementById('clearFilter');
    var filterCount = document.getElementById('filterCount');
    var filterEmpty = document.getElementById('filterEmpty');
    if (!board || !tileBtn || !listBtn) return;
    function setView(view) {
        board.className = 'ups-board ' + view;
        tileBtn.classList.toggle('active', view === 'tiles');
        listBtn.classList.toggle('active', view === 'list');
        try { localStorage.setItem('upsOverviewView', view); } catch (ignore) {}
    }
    tileBtn.onclick = function () { setView('tiles'); };
    listBtn.onclick = function () { setView('list'); };
    var saved = 'tiles';
    try { saved = localStorage.getItem('upsOverviewView') || 'tiles'; } catch (ignore) {}
    setView(saved === 'list' ? 'list' : 'tiles');
    function normalize(value) {
        return (value || '').toString().toLowerCase().replace(/\s+/g, ' ').trim();
    }
    function applyFilter() {
        var query = normalize(filterInput ? filterInput.value : '');
        var tiles = Array.prototype.slice.call(document.querySelectorAll('.ups-tile'));
        var rows = Array.prototype.slice.call(document.querySelectorAll('.overview-table tbody tr'));
        var visible = 0;
        tiles.forEach(function (tile) {
            var matched = !query || normalize(tile.getAttribute('data-filter')).indexOf(query) >= 0;
            tile.style.display = matched ? '' : 'none';
            if (matched) visible += 1;
        });
        rows.forEach(function (row) {
            var matched = !query || normalize(row.getAttribute('data-filter')).indexOf(query) >= 0;
            row.style.display = matched ? '' : 'none';
        });
        if (filterCount) filterCount.textContent = (query ? '표시 ' + visible + '대 / 전체 ' + tiles.length + '대' : '전체 ' + tiles.length + '대');
        if (filterEmpty) filterEmpty.style.display = visible === 0 && tiles.length > 0 ? 'block' : 'none';
        if (board) board.style.display = visible === 0 && tiles.length > 0 ? 'none' : '';
        try { localStorage.setItem('upsOverviewFilter', filterInput ? filterInput.value : ''); } catch (ignore) {}
    }
    if (filterInput) {
        try { filterInput.value = localStorage.getItem('upsOverviewFilter') || ''; } catch (ignore) {}
        filterInput.addEventListener('input', applyFilter);
    }
    if (clearFilter) {
        clearFilter.onclick = function () {
            if (filterInput) filterInput.value = '';
            applyFilter();
            if (filterInput) filterInput.focus();
        };
    }
    applyFilter();
    var remain = 5;
    function tick() {
        if (refreshState) refreshState.textContent = remain + '초 후 갱신';
        if (remain <= 0) {
            window.location.reload();
            return;
        }
        remain -= 1;
    }
    tick();
    setInterval(tick, 1000);
})();
</script>
</body>
</html>

