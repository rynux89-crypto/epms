<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.math.BigDecimal" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_dbconfig.jspf" %>
<%@ include file="../includes/ups_html.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
String msg = request.getParameter("msg");
String err = request.getParameter("err");
String editId = request.getParameter("edit_id");

if ("POST".equalsIgnoreCase(request.getMethod())) {
    try {
        String action = request.getParameter("action");
        if ("delete".equals(action)) {
            epms.ups.UpsDeviceDeleteService.deleteDevice(request.getParameter("ups_id"));
            response.sendRedirect("ups_register.jsp?msg=" + URLEncoder.encode("UPS가 삭제되었습니다.", "UTF-8"));
            return;
        }
        String upsIdRaw = request.getParameter("ups_id");
        String upsName = request.getParameter("ups_name");
        String location = request.getParameter("location");
        String ipAddress = request.getParameter("ip_address");
        String modbusPortRaw = request.getParameter("modbus_port");
        String unitIdRaw = request.getParameter("unit_id");
        String profileIdRaw = request.getParameter("profile_id");
        String capacityRaw = request.getParameter("rated_capacity_kva");
        String pollIntervalRaw = request.getParameter("poll_interval_seconds");
        boolean enabled = "1".equals(request.getParameter("enabled"));
        int modbusPort = (modbusPortRaw == null || modbusPortRaw.trim().isEmpty()) ? 502 : Integer.parseInt(modbusPortRaw.trim());
        int unitId = (unitIdRaw == null || unitIdRaw.trim().isEmpty()) ? 1 : Integer.parseInt(unitIdRaw.trim());
        Integer profileId = (profileIdRaw == null || profileIdRaw.trim().isEmpty()) ? null : Integer.valueOf(profileIdRaw.trim());
        BigDecimal capacity = (capacityRaw == null || capacityRaw.trim().isEmpty()) ? null : new BigDecimal(capacityRaw.trim());
        int pollIntervalSeconds = (pollIntervalRaw == null || pollIntervalRaw.trim().isEmpty()) ? 2 : Integer.parseInt(pollIntervalRaw.trim());
        if (upsName == null || upsName.trim().isEmpty()) throw new IllegalArgumentException("UPS 이름을 입력하세요.");
        if (ipAddress == null || ipAddress.trim().isEmpty()) throw new IllegalArgumentException("IP 주소를 입력하세요.");
        if (pollIntervalSeconds < 1) throw new IllegalArgumentException("수집주기는 1초 이상 입력하세요.");
        if (pollIntervalSeconds > 86400) throw new IllegalArgumentException("수집주기는 86400초 이하로 입력하세요.");

        try (Connection conn = openUpsDbConnection()) {
            try (Statement st = conn.createStatement()) {
                st.execute("IF COL_LENGTH('dbo.ups_device', 'poll_interval_seconds') IS NULL ALTER TABLE dbo.ups_device ADD poll_interval_seconds int NOT NULL CONSTRAINT DF_ups_device_poll_interval_seconds DEFAULT (2)");
            }
            if (upsIdRaw == null || upsIdRaw.trim().isEmpty()) {
                try (PreparedStatement ps = conn.prepareStatement(
                        "INSERT INTO dbo.ups_device (ups_name, location, ip_address, modbus_port, unit_id, profile_id, rated_capacity_kva, poll_interval_seconds, enabled, updated_at) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, sysdatetime())")) {
                    ps.setString(1, upsName.trim());
                    ps.setString(2, (location == null || location.trim().isEmpty()) ? null : location.trim());
                    ps.setString(3, ipAddress.trim());
                    ps.setInt(4, modbusPort);
                    ps.setInt(5, unitId);
                    if (profileId == null) ps.setNull(6, Types.INTEGER); else ps.setInt(6, profileId.intValue());
                    if (capacity == null) ps.setNull(7, Types.DECIMAL); else ps.setBigDecimal(7, capacity);
                    ps.setInt(8, pollIntervalSeconds);
                    ps.setBoolean(9, enabled);
                    ps.executeUpdate();
                }
            } else {
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE dbo.ups_device SET ups_name=?, location=?, ip_address=?, modbus_port=?, unit_id=?, profile_id=?, rated_capacity_kva=?, poll_interval_seconds=?, enabled=?, updated_at=sysdatetime() " +
                        "WHERE ups_id=?")) {
                    ps.setString(1, upsName.trim());
                    ps.setString(2, (location == null || location.trim().isEmpty()) ? null : location.trim());
                    ps.setString(3, ipAddress.trim());
                    ps.setInt(4, modbusPort);
                    ps.setInt(5, unitId);
                    if (profileId == null) ps.setNull(6, Types.INTEGER); else ps.setInt(6, profileId.intValue());
                    if (capacity == null) ps.setNull(7, Types.DECIMAL); else ps.setBigDecimal(7, capacity);
                    ps.setInt(8, pollIntervalSeconds);
                    ps.setBoolean(9, enabled);
                    ps.setInt(10, Integer.parseInt(upsIdRaw.trim()));
                    if (ps.executeUpdate() == 0) throw new IllegalArgumentException("수정할 UPS를 찾을 수 없습니다.");
                }
            }
        }
        response.sendRedirect("ups_register.jsp?msg=" + URLEncoder.encode((upsIdRaw == null || upsIdRaw.trim().isEmpty()) ? "UPS가 등록되었습니다." : "UPS 정보가 수정되었습니다.", "UTF-8"));
        return;
    } catch (Exception e) {
        response.sendRedirect("ups_register.jsp?err=" + URLEncoder.encode(e.getMessage(), "UTF-8"));
        return;
    }
}

List<Map<String, Object>> profiles = new ArrayList<Map<String, Object>>();
List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
try {
    profiles = epms.ups.UpsDeviceService.listProfiles();
    devices = epms.ups.UpsDeviceService.listDevices();
} catch (Exception e) {
    err = e.getMessage();
}

Map<String, Object> editDevice = null;
if (editId != null && editId.trim().length() > 0) {
    for (Map<String, Object> d : devices) {
        if (editId.trim().equals(String.valueOf(d.get("ups_id")))) {
            editDevice = d;
            break;
        }
    }
}
boolean editMode = editDevice != null;
%>
<!doctype html>
<html>
<head>
    <title>UPS 등록</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        .ups-register-form .toolbar {
            display:grid;
            grid-template-columns:minmax(120px,1.05fr) minmax(110px,.95fr) minmax(140px,1.1fr) 76px 76px 96px 96px minmax(170px,1.25fr) 70px 86px 70px;
            gap:8px;
            align-items:end;
        }
        .ups-register-form label {
            display:flex;
            flex-direction:column;
            gap:4px;
            min-width:0;
            margin:0;
            font-size:12px;
            color:#60758a;
            font-weight:700;
        }
        .ups-register-form input,
        .ups-register-form select {
            width:100%;
            min-width:0;
        }
        .ups-register-form label.enabled-field {
            align-items:center;
            justify-content:center;
            flex-direction:row;
            height:38px;
            color:#163047;
        }
        .ups-register-form label.enabled-field input {
            width:auto;
        }
        .ups-register-form button {
            white-space:nowrap;
            height:38px;
            padding:8px 12px;
            width:100%;
        }
        .ups-device-table-wrap { overflow:auto; }
        .ups-device-table { min-width:1420px; table-layout:fixed; }
        .ups-device-table th, .ups-device-table td {
            overflow:hidden;
            text-overflow:ellipsis;
            vertical-align:middle;
            white-space:nowrap;
        }
        .ups-device-table .col-id { width:56px; }
        .ups-device-table .col-name { width:150px; }
        .ups-device-table .col-location { width:130px; }
        .ups-device-table .col-ip { width:140px; }
        .ups-device-table .col-port { width:70px; }
        .ups-device-table .col-unit { width:70px; }
        .ups-device-table .col-capacity { width:96px; }
        .ups-device-table .col-poll { width:116px; }
        .ups-device-table .col-profile { width:280px; }
        .ups-device-table .col-enabled { width:80px; }
        .ups-device-table .col-manage { width:140px; }
        .ups-device-table th:nth-child(10),
        .ups-device-table td:nth-child(10) { text-align:center; }
        .ups-device-table th:last-child,
        .ups-device-table td:last-child { text-align:center; }
        .manage-actions { display:flex; gap:6px; align-items:center; justify-content:center; flex-wrap:nowrap; white-space:nowrap; }
        .manage-actions form {
            display:inline-flex;
            margin:0;
            padding:0;
            border:0;
            border-radius:0;
            background:transparent;
            box-shadow:none;
        }
        .manage-actions button { height:30px; padding:5px 10px; }
        .manage-actions button.delete-btn,
        .manage-actions button.delete-btn:hover,
        .manage-actions button.delete-btn:active {
            background:#dc2626;
            border:none;
            box-shadow:none;
            color:#fff;
            outline:none;
        }
        .manage-actions button.delete-btn:hover { background:#b91c1c; }
        @media (max-width: 1200px) {
            .ups-register-form .toolbar {
                grid-template-columns:repeat(4,minmax(140px,1fr));
            }
        }
        @media (max-width: 720px) {
            .ups-register-form .toolbar {
                grid-template-columns:1fr;
            }
        }
    </style>
</head>
<body>
<div class="page-wrap">
<% if (msg != null) { %><div class="ok-box"><%= h(msg) %></div><% } %>
    <% if (err != null) { %><div class="err-box"><%= h(err) %></div><% } %>

    <form method="post" class="panel ups-register-form">
        <% if (editMode) { %><input type="hidden" name="ups_id" value="<%= h(editDevice.get("ups_id")) %>"><% } %>
        <div class="toolbar">
            <label>UPS 이름 <input name="ups_name" required value="<%= editMode ? h(editDevice.get("ups_name")) : "" %>"></label>
            <label>위치 <input name="location" value="<%= editMode ? h(editDevice.get("location")) : "" %>"></label>
            <label>IP 주소 <input name="ip_address" required placeholder="192.168.0.10" value="<%= editMode ? h(editDevice.get("ip_address")) : "" %>"></label>
            <label>Port <input name="modbus_port" type="number" value="<%= editMode ? h(editDevice.get("modbus_port")) : "502" %>"></label>
            <label>Unit ID <input name="unit_id" type="number" value="<%= editMode ? h(editDevice.get("unit_id")) : "1" %>"></label>
            <label>용량(kVA) <input name="rated_capacity_kva" type="number" step="0.001" value="<%= editMode && editDevice.get("rated_capacity_kva") != null ? h(editDevice.get("rated_capacity_kva")) : "" %>"></label>
            <label>수집주기(초) <input name="poll_interval_seconds" type="number" min="1" max="86400" value="<%= editMode ? h(editDevice.get("poll_interval_seconds")) : "2" %>"></label>
            <label>프로파일
                <select name="profile_id">
                    <% for (Map<String, Object> p : profiles) { %>
                    <option value="<%= p.get("profile_id") %>" <%= editMode && String.valueOf(p.get("profile_id")).equals(String.valueOf(editDevice.get("profile_id"))) ? "selected" : "" %>><%= h(p.get("profile_name")) %></option>
                    <% } %>
                </select>
            </label>
            <label class="enabled-field">활성 <input type="checkbox" name="enabled" value="1" <%= !editMode || Boolean.TRUE.equals(editDevice.get("enabled")) ? "checked" : "" %>></label>
            <button type="submit"><%= editMode ? "수정 저장" : "등록" %></button>
            <% if (editMode) { %><button type="button" onclick="location.href='ups_register.jsp'">취소</button><% } %>
        </div>
    </form>

    <div class="panel" style="margin-top:16px;">
        <h3>등록된 UPS</h3>
        <div class="ups-device-table-wrap">
        <table class="data-table ups-device-table">
            <colgroup>
                <col class="col-id"><col class="col-name"><col class="col-location"><col class="col-ip">
                <col class="col-port"><col class="col-unit"><col class="col-capacity"><col class="col-poll">
                <col class="col-profile"><col class="col-enabled"><col class="col-manage">
            </colgroup>
            <thead><tr><th>ID</th><th>이름</th><th>위치</th><th>IP</th><th>Port</th><th>Unit</th><th>용량(kVA)</th><th>수집주기(초)</th><th>프로파일</th><th>활성</th><th>관리</th></tr></thead>
            <tbody>
            <% if (devices.isEmpty()) { %>
            <tr><td colspan="11">등록된 UPS가 없습니다.</td></tr>
            <% } %>
            <% for (Map<String, Object> d : devices) { %>
            <tr>
                <td><%= d.get("ups_id") %></td>
                <td><%= h(d.get("ups_name")) %></td>
                <td><%= h(d.get("location")) %></td>
                <td><%= h(d.get("ip_address")) %></td>
                <td><%= d.get("modbus_port") %></td>
                <td><%= d.get("unit_id") %></td>
                <td><%= h(d.get("rated_capacity_kva")) %></td>
                <td><%= h(d.get("poll_interval_seconds")) %></td>
                <td title="<%= h(d.get("profile_name")) %>"><%= h(d.get("profile_name")) %></td>
                <td><%= Boolean.TRUE.equals(d.get("enabled")) ? "Y" : "N" %></td>
                <td>
                    <div class="manage-actions">
                        <button type="button" onclick="location.href='ups_register.jsp?edit_id=<%= h(d.get("ups_id")) %>'">수정</button>
                        <form method="post" onsubmit="return confirm('UPS <%= h(d.get("ups_name")) %> 및 관련 측정/알람 이력을 삭제하시겠습니까?');">
                            <input type="hidden" name="action" value="delete">
                            <input type="hidden" name="ups_id" value="<%= h(d.get("ups_id")) %>">
                            <button type="submit" class="delete-btn">삭제</button>
                        </form>
                    </div>
                </td>
            </tr>
            <% } %>
            </tbody>
        </table>
        </div>
    </div>
</div>
</body>
</html>
