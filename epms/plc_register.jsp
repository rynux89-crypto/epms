<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconn.jsp" %>
<%!
    private static boolean isValidIpv4(String ip) {
        if (ip == null) return false;
        String s = ip.trim();
        return s.matches("^(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)(\\.(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}$");
    }

    private static Integer parseIntRange(String value, int min, int max) {
        if (value == null) return null;
        try {
            int n = Integer.parseInt(value.trim());
            return (n >= min && n <= max) ? n : null;
        } catch (Exception e) {
            return null;
        }
    }
%>
<%
    String message = request.getParameter("msg");
    String error = request.getParameter("err");
    String self = request.getRequestURI();

    if ("POST".equalsIgnoreCase(request.getMethod())) {
        String action = request.getParameter("action");

        if ("add".equals(action)) {
            String plcIp = request.getParameter("plc_ip");
            Integer plcPort = parseIntRange(request.getParameter("plc_port"), 1, 65535);
            Integer unitId = parseIntRange(request.getParameter("unit_id"), 1, 255);
            Integer pollingSeconds = parseIntRange(request.getParameter("polling_seconds"), 1, 86400);

            plcIp = (plcIp == null) ? "" : plcIp.trim();

            if (!isValidIpv4(plcIp)) {
                error = "유효한 IPv4 주소를 입력하세요. 예: 192.168.0.190";
            } else if (plcPort == null) {
                error = "포트는 1~65535 범위여야 합니다.";
            } else if (unitId == null) {
                error = "Unit ID는 1~255 범위여야 합니다.";
            } else if (pollingSeconds == null) {
                error = "Polling 시간(초)은 1~86400 범위여야 합니다.";
            } else {
                boolean oldAutoCommit = conn.getAutoCommit();
                try {
                    conn.setAutoCommit(false);

                    String dupSql =
                        "SELECT COUNT(*) FROM dbo.plc_config WHERE plc_ip = ? AND plc_port = ? AND unit_id = ?";
                    try (PreparedStatement ps = conn.prepareStatement(dupSql)) {
                        ps.setString(1, plcIp);
                        ps.setInt(2, plcPort);
                        ps.setInt(3, unitId);
                        try (ResultSet rs = ps.executeQuery()) {
                            if (rs.next() && rs.getInt(1) > 0) {
                                throw new SQLException("이미 등록된 PLC(IP/Port/Unit)입니다.");
                            }
                        }
                    }

                    int nextId;
                    String idSql = "SELECT ISNULL(MAX(plc_id), 0) + 1 FROM dbo.plc_config WITH (UPDLOCK, HOLDLOCK)";
                    try (PreparedStatement ps = conn.prepareStatement(idSql);
                         ResultSet rs = ps.executeQuery()) {
                        rs.next();
                        nextId = rs.getInt(1);
                    }

                    String insSql =
                        "INSERT INTO dbo.plc_config " +
                        "(plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled, updated_at, insert_ms) " +
                        "VALUES (?, ?, ?, ?, ?, 1, SYSUTCDATETIME(), 600000)";
                    try (PreparedStatement ps = conn.prepareStatement(insSql)) {
                        ps.setInt(1, nextId);
                        ps.setString(2, plcIp);
                        ps.setInt(3, plcPort);
                        ps.setInt(4, unitId);
                        ps.setInt(5, pollingSeconds * 1000);
                        ps.executeUpdate();
                    }

                    conn.commit();
                    conn.setAutoCommit(oldAutoCommit);
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("PLC가 등록되었습니다.", "UTF-8"));
                    return;
                } catch (Exception e) {
                    try { conn.rollback(); } catch (Exception ignore) {}
                    try { conn.setAutoCommit(oldAutoCommit); } catch (Exception ignore) {}
                    error = "등록 실패: " + e.getMessage();
                }
            }
        } else if ("update".equals(action)) {
            Integer plcId = parseIntRange(request.getParameter("plc_id"), 1, Integer.MAX_VALUE);
            String plcIp = request.getParameter("plc_ip");
            Integer plcPort = parseIntRange(request.getParameter("plc_port"), 1, 65535);
            Integer unitId = parseIntRange(request.getParameter("unit_id"), 1, 255);
            Integer pollingSeconds = parseIntRange(request.getParameter("polling_seconds"), 1, 86400);

            plcIp = (plcIp == null) ? "" : plcIp.trim();

            if (plcId == null) {
                error = "잘못된 PLC ID입니다.";
            } else if (!isValidIpv4(plcIp)) {
                error = "유효한 IPv4 주소를 입력하세요.";
            } else if (plcPort == null || unitId == null || pollingSeconds == null) {
                error = "포트/Unit/Polling 값이 유효하지 않습니다.";
            } else {
                String updSql =
                    "UPDATE dbo.plc_config " +
                    "SET plc_ip = ?, plc_port = ?, unit_id = ?, polling_ms = ?, updated_at = SYSUTCDATETIME() " +
                    "WHERE plc_id = ?";
                try (PreparedStatement ps = conn.prepareStatement(updSql)) {
                    ps.setString(1, plcIp);
                    ps.setInt(2, plcPort);
                    ps.setInt(3, unitId);
                    ps.setInt(4, pollingSeconds * 1000);
                    ps.setInt(5, plcId);
                    ps.executeUpdate();
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("PLC 설정이 수정되었습니다.", "UTF-8"));
                    return;
                } catch (Exception e) {
                    error = "수정 실패: " + e.getMessage();
                }
            }
        } else if ("toggle".equals(action)) {
            Integer plcId = parseIntRange(request.getParameter("plc_id"), 1, Integer.MAX_VALUE);
            if (plcId == null) {
                error = "잘못된 PLC ID입니다.";
            } else {
                String sql =
                    "UPDATE dbo.plc_config " +
                    "SET enabled = CASE WHEN enabled = 1 THEN 0 ELSE 1 END, updated_at = SYSUTCDATETIME() " +
                    "WHERE plc_id = ?";
                try (PreparedStatement ps = conn.prepareStatement(sql)) {
                    ps.setInt(1, plcId);
                    ps.executeUpdate();
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("PLC 상태가 변경되었습니다.", "UTF-8"));
                    return;
                } catch (Exception e) {
                    error = "상태 변경 실패: " + e.getMessage();
                }
            }
        } else if ("delete".equals(action)) {
            Integer plcId = parseIntRange(request.getParameter("plc_id"), 1, Integer.MAX_VALUE);
            if (plcId == null) {
                error = "잘못된 PLC ID입니다.";
            } else {
                String sql = "DELETE FROM dbo.plc_config WHERE plc_id = ?";
                try (PreparedStatement ps = conn.prepareStatement(sql)) {
                    ps.setInt(1, plcId);
                    ps.executeUpdate();
                    response.sendRedirect(self + "?msg=" + URLEncoder.encode("PLC가 삭제되었습니다.", "UTF-8"));
                    return;
                } catch (Exception e) {
                    error = "삭제 실패: " + e.getMessage();
                }
            }
        }
    }

    List<Map<String, Object>> rows = new ArrayList<>();
    String listSql =
        "SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled, updated_at, insert_ms " +
        "FROM dbo.plc_config ORDER BY plc_id";
    try (PreparedStatement ps = conn.prepareStatement(listSql);
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            Map<String, Object> r = new HashMap<>();
            r.put("plc_id", rs.getInt("plc_id"));
            r.put("plc_ip", rs.getString("plc_ip"));
            r.put("plc_port", rs.getInt("plc_port"));
            r.put("unit_id", rs.getInt("unit_id"));
            r.put("polling_ms", rs.getInt("polling_ms"));
            r.put("enabled", rs.getBoolean("enabled"));
            r.put("updated_at", rs.getTimestamp("updated_at"));
            r.put("insert_ms", rs.getInt("insert_ms"));
            rows.add(r);
        }
    } catch (Exception e) {
        error = "목록 조회 실패: " + e.getMessage();
    }

    try {
        if (conn != null && !conn.isClosed()) conn.close();
    } catch (Exception ignore) {}
%>
<html>
<head>
    <title>PLC Register</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1280px; margin: 0 auto; }
        .notice { padding: 10px 12px; border-radius: 8px; margin-bottom: 10px; font-weight: 700; }
        .ok-msg { border: 1px solid #b7ebc6; background: #ebfff1; color: #0f7a2a; }
        .err-msg { border: 1px solid #ffc9c9; background: #fff1f1; color: #b42318; }
        .form-grid { display: grid; grid-template-columns: 1fr 0.7fr 0.7fr 0.8fr auto; gap: 8px; align-items: end; }
        .input-group { display: flex; flex-direction: column; gap: 4px; }
        .input-group label { font-size: 12px; color: #334155; font-weight: 600; }
        .submit-btn { height: 34px; padding: 0 14px; background: #007acc; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-weight: 700; }
        .submit-btn:hover { background: #005fa3; }
        .state-badge { display: inline-block; min-width: 64px; padding: 4px 8px; border-radius: 999px; font-size: 12px; font-weight: 700; text-align: center; }
        .state-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .state-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .action-btn { border: none; border-radius: 6px; padding: 6px 10px; font-size: 12px; font-weight: 700; cursor: pointer; color: #fff; }
        .btn-update { background: #006d77; }
        .btn-toggle-on { background: #ef6c00; }
        .btn-toggle-off { background: #2e7d32; }
        .btn-delete { background: #c62828; }
        .actions-wrap { display: flex; gap: 6px; justify-content: center; }
        .row-form { margin: 0; padding: 0; box-shadow: none; background: transparent; display: inline; }
        .in-cell { width: 100%; min-width: 84px; margin: 0; }
        @media (max-width: 1100px) {
            .form-grid { grid-template-columns: 1fr; }
            .submit-btn { width: 100%; }
            .actions-wrap { flex-direction: column; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>PLC Register (plc_config)</h2>
        <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS Home</button>
    </div>

    <% if (message != null && !message.trim().isEmpty()) { %>
    <div class="notice ok-msg"><%= message %></div>
    <% } %>
    <% if (error != null && !error.trim().isEmpty()) { %>
    <div class="notice err-msg"><%= error %></div>
    <% } %>

    <form method="POST">
        <input type="hidden" name="action" value="add">
        <div class="form-grid">
            <div class="input-group">
                <label for="plc_ip">PLC IP (IPv4)</label>
                <input id="plc_ip" type="text" name="plc_ip" placeholder="192.168.0.190" required>
            </div>
            <div class="input-group">
                <label for="plc_port">Port</label>
                <input id="plc_port" type="number" name="plc_port" min="1" max="65535" value="502" required>
            </div>
            <div class="input-group">
                <label for="unit_id">Unit ID</label>
                <input id="unit_id" type="number" name="unit_id" min="1" max="255" value="1" required>
            </div>
            <div class="input-group">
                <label for="polling_seconds">Polling (sec)</label>
                <input id="polling_seconds" type="number" name="polling_seconds" min="1" max="86400" value="1" required>
            </div>
            <button class="submit-btn" type="submit">Add PLC</button>
        </div>
    </form>

    <table>
        <thead>
        <tr>
            <th>PLC ID</th>
            <th>IP</th>
            <th>Port</th>
            <th>Unit</th>
            <th>Polling (sec)</th>
            <th>Status</th>
            <th>Update</th>
            <th>Control</th>
        </tr>
        </thead>
        <tbody>
        <% if (rows.isEmpty()) { %>
        <tr><td colspan="8">No PLC configured.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> r : rows) { %>
            <% String updFormId = "upd_" + r.get("plc_id"); %>
            <tr>
                <td><%= r.get("plc_id") %></td>
                <td><input class="in-cell" type="text" name="plc_ip" value="<%= r.get("plc_ip") %>" form="<%= updFormId %>" required></td>
                <td><input class="in-cell" type="number" name="plc_port" min="1" max="65535" value="<%= r.get("plc_port") %>" form="<%= updFormId %>" required></td>
                <td><input class="in-cell" type="number" name="unit_id" min="1" max="255" value="<%= r.get("unit_id") %>" form="<%= updFormId %>" required></td>
                <td><input class="in-cell" type="number" name="polling_seconds" min="1" max="86400" value="<%= ((Integer)r.get("polling_ms")) / 1000 %>" form="<%= updFormId %>" required></td>
                <td>
                    <% if ((Boolean)r.get("enabled")) { %>
                    <span class="state-badge state-on">ACTIVE</span>
                    <% } else { %>
                    <span class="state-badge state-off">INACTIVE</span>
                    <% } %>
                </td>
                <td>
                    <form id="<%= updFormId %>" class="row-form" method="POST">
                        <input type="hidden" name="action" value="update">
                        <input type="hidden" name="plc_id" value="<%= r.get("plc_id") %>">
                        <button type="submit" class="action-btn btn-update">Save</button>
                    </form>
                </td>
                <td>
                    <div class="actions-wrap">
                        <form class="row-form" method="POST">
                            <input type="hidden" name="action" value="toggle">
                            <input type="hidden" name="plc_id" value="<%= r.get("plc_id") %>">
                            <% if ((Boolean)r.get("enabled")) { %>
                            <button type="submit" class="action-btn btn-toggle-on">Disable</button>
                            <% } else { %>
                            <button type="submit" class="action-btn btn-toggle-off">Enable</button>
                            <% } %>
                        </form>
                        <form class="row-form" method="POST" onsubmit="return confirm('Delete this PLC config?');">
                            <input type="hidden" name="action" value="delete">
                            <input type="hidden" name="plc_id" value="<%= r.get("plc_id") %>">
                            <button type="submit" class="action-btn btn-delete">Delete</button>
                        </form>
                    </div>
                </td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
