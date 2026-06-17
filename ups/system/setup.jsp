<%@ page import="java.sql.Timestamp" %>
<%@ page import="java.util.Map" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
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

try {
    if ("init_schema".equals(action)) {
        msg = epms.ups.UpsSystemSetupService.initSchema(application);
    } else if ("clear_history".equals(action)) {
        msg = epms.ups.UpsSystemSetupService.clearHistory();
    }
} catch (Exception e) {
    err = e.getMessage();
}

Map<String, Object> setupStatus = epms.ups.UpsSystemSetupService.loadStatus(application);
boolean canConnect = Boolean.TRUE.equals(setupStatus.get("canConnect"));
String connectError = String.valueOf(setupStatus.get("connectError"));
int deviceCount = ((Number)setupStatus.get("deviceCount")).intValue();
int profileCount = ((Number)setupStatus.get("profileCount")).intValue();
int pointCount = ((Number)setupStatus.get("pointCount")).intValue();
int alarmCount = ((Number)setupStatus.get("alarmCount")).intValue();
int measurementCount = ((Number)setupStatus.get("measurementCount")).intValue();
int commCount = ((Number)setupStatus.get("commCount")).intValue();
String collectorStatus = String.valueOf(setupStatus.get("collectorStatus"));
Object collectorLastStart = setupStatus.get("collectorLastStart");
Object collectorLastSuccess = setupStatus.get("collectorLastSuccess");
Object collectorLastErrorAt = setupStatus.get("collectorLastErrorAt");
Object collectorLastDuration = setupStatus.get("collectorLastDuration");
Object collectorLastError = setupStatus.get("collectorLastError");
Object collectorInterval = setupStatus.get("collectorInterval");
%>
<!doctype html>
<html>
<head>
    <title>UPS 초기 설정</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
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
            <p class="muted">UPS_MONITOR 데이터베이스와 수집기 상태를 확인합니다.</p>
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
<%@ include file="../includes/ups_footer.jspf" %>
</body>
</html>
