<%@ page import="java.net.*" %>
<%@ page import="java.io.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private boolean isOpen(String urlText) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlText);
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(500);
            conn.setReadTimeout(500);
            conn.setRequestMethod("GET");
            return conn.getResponseCode() >= 200 && conn.getResponseCode() < 500;
        } catch (Exception ignore) {
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
%>
<%
boolean running = isOpen("http://127.0.0.1:1503/api/status");
%>
<!doctype html>
<html>
<head>
    <title>UPS 시뮬레이터</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .sim-box { max-width:760px; margin:0 auto; }
        .sim-status { display:flex; align-items:center; gap:10px; margin:14px 0; font-weight:800; }
        .dot { width:14px; height:14px; border-radius:50%; display:inline-block; background:<%= running ? "#169b45" : "#d92d20" %>; }
        .cmd { background:#111827; color:#f8fafc; padding:12px; border-radius:6px; font-family:Consolas,monospace; margin:10px 0; }
        .sim-actions { display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }
    </style>
</head>
<body>
<div class="page-wrap sim-box">
    <div class="title-bar">
        <div>
            <h2>UPS 시뮬레이터</h2>
            <p class="muted">시뮬레이터 제어 UI는 별도 Python 프로세스로 실행됩니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='../ups_main.jsp'">UPS 메인</button>
        </div>
    </div>

    <div class="panel">
        <div class="sim-status"><span class="dot"></span><span><%= running ? "시뮬레이터 실행 중" : "시뮬레이터가 실행 중이 아닙니다" %></span></div>
        <% if (running) { %>
            <p class="muted">아래 버튼으로 시뮬레이터 UI를 열 수 있습니다.</p>
            <div class="sim-actions">
                <button type="button" onclick="window.open('http://127.0.0.1:1503/','_blank')">시뮬레이터 UI 열기</button>
                <button type="button" onclick="location.reload()">상태 새로고침</button>
            </div>
        <% } else { %>
            <p>PowerShell 또는 CMD에서 아래 명령을 실행한 뒤 상태를 새로고침하세요.</p>
            <div class="cmd">cd C:\Tomcat 9.0\webapps\ROOT\ups\simulator<br>start_simulator.bat</div>
            <div class="sim-actions">
                <button type="button" onclick="location.reload()">상태 새로고침</button>
            </div>
        <% } %>
    </div>
</div>
</body>
</html>
