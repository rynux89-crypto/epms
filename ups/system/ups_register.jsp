<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
String msg = request.getParameter("msg");
String err = request.getParameter("err");

if ("POST".equalsIgnoreCase(request.getMethod())) {
    String upsName = request.getParameter("ups_name");
    String location = request.getParameter("location");
    String ipAddress = request.getParameter("ip_address");
    String modbusPortRaw = request.getParameter("modbus_port");
    String unitIdRaw = request.getParameter("unit_id");
    String profileIdRaw = request.getParameter("profile_id");
    String capacityRaw = request.getParameter("rated_capacity_kva");
    String enabledRaw = request.getParameter("enabled");

    try {
        int modbusPort = (modbusPortRaw == null || modbusPortRaw.trim().isEmpty()) ? 502 : Integer.parseInt(modbusPortRaw.trim());
        int unitId = (unitIdRaw == null || unitIdRaw.trim().isEmpty()) ? 1 : Integer.parseInt(unitIdRaw.trim());
        Integer profileId = (profileIdRaw == null || profileIdRaw.trim().isEmpty()) ? null : Integer.valueOf(profileIdRaw.trim());
        java.math.BigDecimal capacity = (capacityRaw == null || capacityRaw.trim().isEmpty()) ? null : new java.math.BigDecimal(capacityRaw.trim());
        boolean enabled = "1".equals(enabledRaw);

        if (upsName == null || upsName.trim().isEmpty()) throw new IllegalArgumentException("UPS 이름을 입력하세요.");
        if (ipAddress == null || ipAddress.trim().isEmpty()) throw new IllegalArgumentException("IP 주소를 입력하세요.");

        try (Connection conn = openUpsDbConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "INSERT INTO dbo.ups_device (ups_name, location, ip_address, modbus_port, unit_id, profile_id, rated_capacity_kva, enabled, updated_at) " +
                 "VALUES (?, ?, ?, ?, ?, ?, ?, ?, sysdatetime())")) {
            ps.setString(1, upsName.trim());
            ps.setString(2, location == null || location.trim().isEmpty() ? null : location.trim());
            ps.setString(3, ipAddress.trim());
            ps.setInt(4, modbusPort);
            ps.setInt(5, unitId);
            if (profileId == null) ps.setNull(6, java.sql.Types.INTEGER); else ps.setInt(6, profileId.intValue());
            if (capacity == null) ps.setNull(7, java.sql.Types.DECIMAL); else ps.setBigDecimal(7, capacity);
            ps.setBoolean(8, enabled);
            ps.executeUpdate();
        }
        response.sendRedirect("ups_register.jsp?msg=" + URLEncoder.encode("UPS가 등록되었습니다.", "UTF-8"));
        return;
    } catch (Exception e) {
        response.sendRedirect("ups_register.jsp?err=" + URLEncoder.encode(e.getMessage(), "UTF-8"));
        return;
    }
}

List<Map<String, Object>> profiles = new ArrayList<Map<String, Object>>();
List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
try (Connection conn = openUpsDbConnection()) {
    try (PreparedStatement ps = conn.prepareStatement("SELECT profile_id, profile_name FROM dbo.ups_modbus_profile WHERE enabled = 1 ORDER BY profile_name");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            Map<String, Object> row = new HashMap<String, Object>();
            row.put("profile_id", rs.getInt("profile_id"));
            row.put("profile_name", rs.getString("profile_name"));
            profiles.add(row);
        }
    }
    try (PreparedStatement ps = conn.prepareStatement(
        "SELECT d.ups_id, d.ups_name, d.location, d.ip_address, d.modbus_port, d.unit_id, d.enabled, p.profile_name " +
        "FROM dbo.ups_device d LEFT JOIN dbo.ups_modbus_profile p ON p.profile_id = d.profile_id ORDER BY d.ups_id DESC");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            Map<String, Object> row = new HashMap<String, Object>();
            row.put("ups_id", rs.getInt("ups_id"));
            row.put("ups_name", rs.getString("ups_name"));
            row.put("location", rs.getString("location"));
            row.put("ip_address", rs.getString("ip_address"));
            row.put("modbus_port", rs.getInt("modbus_port"));
            row.put("unit_id", rs.getInt("unit_id"));
            row.put("enabled", rs.getBoolean("enabled"));
            row.put("profile_name", rs.getString("profile_name"));
            devices.add(row);
        }
    }
} catch (Exception e) {
    err = e.getMessage();
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 등록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div><h2>UPS 등록</h2><p class="muted">신규 UPS는 IP와 Modbus 기본값만 입력하면 수집 대상에 포함됩니다.</p></div>
        <div class="inline-actions"><button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button></div>
    </div>

    <% if (msg != null) { %><div class="ok-box"><%= h(msg) %></div><% } %>
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form method="post" class="panel">
        <div class="toolbar">
            <label>UPS 이름 <input name="ups_name" required></label>
            <label>위치 <input name="location"></label>
            <label>IP 주소 <input name="ip_address" required placeholder="192.168.0.10"></label>
            <label>Port <input name="modbus_port" type="number" value="502"></label>
            <label>Unit ID <input name="unit_id" type="number" value="1"></label>
            <label>용량(kVA) <input name="rated_capacity_kva" type="number" step="0.001"></label>
            <label>프로파일
                <select name="profile_id">
                    <% for (Map<String, Object> p : profiles) { %>
                    <option value="<%= p.get("profile_id") %>"><%= h(p.get("profile_name")) %></option>
                    <% } %>
                </select>
            </label>
            <label>활성 <input type="checkbox" name="enabled" value="1" checked></label>
            <button type="submit">등록</button>
        </div>
    </form>

    <div class="panel" style="margin-top:16px;">
        <h3>등록된 UPS</h3>
        <table class="data-table">
            <thead><tr><th>ID</th><th>이름</th><th>위치</th><th>IP</th><th>Port</th><th>Unit</th><th>프로파일</th><th>활성</th></tr></thead>
            <tbody>
            <% if (devices.isEmpty()) { %>
            <tr><td colspan="8">등록된 UPS가 없습니다.</td></tr>
            <% } %>
            <% for (Map<String, Object> d : devices) { %>
            <tr>
                <td><%= d.get("ups_id") %></td>
                <td><%= h(d.get("ups_name")) %></td>
                <td><%= h(d.get("location")) %></td>
                <td><%= h(d.get("ip_address")) %></td>
                <td><%= d.get("modbus_port") %></td>
                <td><%= d.get("unit_id") %></td>
                <td><%= h(d.get("profile_name")) %></td>
                <td><%= Boolean.TRUE.equals(d.get("enabled")) ? "Y" : "N" %></td>
            </tr>
            <% } %>
            </tbody>
        </table>
    </div>
</div>
</body>
</html>
