<%@ page import="java.net.*" %>
<%@ page import="java.io.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%!
    private static final String STATUS_URL = "http://127.0.0.1:1503/api/status";

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

    private String runProcess(ProcessBuilder pb) {
        try {
            pb.redirectErrorStream(true);
            Process p = pb.start();
            boolean done = p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
            String output = readText(p.getInputStream()).trim();
            if (!done) {
                return "요청을 실행했습니다.";
            }
            if (p.exitValue() != 0) {
                return output.length() > 0 ? output : "명령 실행 중 오류가 발생했습니다.";
            }
            return output.length() > 0 ? output : "요청을 실행했습니다.";
        } catch (Exception ex) {
            return ex.getMessage();
        }
    }

    private String readText(InputStream in) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] bytes = new byte[1024];
        int len;
        while ((len = in.read(bytes)) >= 0) {
            buffer.write(bytes, 0, len);
        }
        return buffer.toString("UTF-8");
    }

    private boolean requestSimulatorShutdown() {
        HttpURLConnection conn = null;
        try {
            URL url = new URL("http://127.0.0.1:1503/api/shutdown");
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(700);
            conn.setReadTimeout(700);
            conn.setRequestMethod("POST");
            conn.setDoOutput(true);
            conn.getOutputStream().write(new byte[0]);
            return conn.getResponseCode() >= 200 && conn.getResponseCode() < 500;
        } catch (Exception ignore) {
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private String pythonExecutable() {
        return "C:\\Windows\\py.exe";
    }

    private String startSimulator(String simulatorDir) {
        try {
            ProcessBuilder pb = new ProcessBuilder(
                pythonExecutable(),
                "-3",
                "ups_modbus_simulator.py",
                "--host", "127.0.0.1",
                "--port", "1502",
                "--control-host", "127.0.0.1",
                "--control-port", "1503",
                "--scenario", "normal",
                "--no-console"
            );
            pb.directory(new File(simulatorDir));
            File log = new File(simulatorDir, "simulator-control.log");
            pb.redirectOutput(ProcessBuilder.Redirect.appendTo(log));
            pb.redirectError(ProcessBuilder.Redirect.appendTo(log));
            pb.start();
            return "시뮬레이터 실행 요청을 보냈습니다.";
        } catch (Exception ex) {
            return ex.getMessage();
        }
    }

    private String stopSimulator() {
        if (requestSimulatorShutdown()) {
            return "시뮬레이터 중지 요청을 보냈습니다.";
        }
        ProcessBuilder pb = new ProcessBuilder(
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*ups_modbus_simulator.py*' -and $_.Name -like 'python*' }; foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force }; if ($procs) { '시뮬레이터를 중지했습니다.' } else { '실행 중인 시뮬레이터가 없습니다.' }"
        );
        return runProcess(pb);
    }
%>
<%
String message = "";
String messageClass = "info";
boolean wasRunning = isOpen(STATUS_URL);
if ("POST".equalsIgnoreCase(request.getMethod())) {
    String action = request.getParameter("action");
    if ("start".equals(action)) {
        if (wasRunning) {
            message = "이미 시뮬레이터가 실행 중입니다.";
        } else {
            message = startSimulator(application.getRealPath("/simulator"));
            Thread.sleep(900);
        }
    } else if ("stop".equals(action)) {
        if (wasRunning) {
            message = stopSimulator();
            Thread.sleep(600);
        } else {
            message = "실행 중인 시뮬레이터가 없습니다.";
        }
    }
}
boolean running = isOpen(STATUS_URL);
if (message.length() > 0) {
    messageClass = running ? "ok" : ("stop".equals(request.getParameter("action")) ? "warn" : "info");
}
%>
<!doctype html>
<html>
<head>
    <title>UPS 시뮬레이터</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        .sim-box { max-width:900px; margin:0 auto; }
        .sim-status { display:flex; align-items:center; gap:10px; margin:14px 0; font-weight:800; }
        .dot { width:14px; height:14px; border-radius:50%; display:inline-block; background:<%= running ? "#169b45" : "#d92d20" %>; }
        .cmd { background:#111827; color:#f8fafc; padding:12px; border-radius:6px; font-family:Consolas,monospace; margin:10px 0; }
        .sim-actions { display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }
        .sim-actions form { margin:0; }
        .sim-actions button { min-width:130px; }
        .sim-actions .danger { background:#dc2626; border-color:#dc2626; color:#fff; }
        .sim-actions .secondary { background:#fff; color:#172033; }
        .sim-message { margin:12px 0 0; padding:10px 12px; border-radius:6px; font-weight:700; }
        .sim-message.ok { background:#ecfdf3; color:#166534; border:1px solid #bbf7d0; }
        .sim-message.warn { background:#fff7ed; color:#9a3412; border:1px solid #fed7aa; }
        .sim-message.info { background:#eff6ff; color:#1d4ed8; border:1px solid #bfdbfe; }
    </style>
</head>
<body>
<div class="page-wrap sim-box">
<div class="panel">
        <div class="sim-status"><span class="dot"></span><span><%= running ? "시뮬레이터 실행 중" : "시뮬레이터가 실행 중이 아닙니다" %></span></div>
        <% if (message.length() > 0) { %>
            <div class="sim-message <%= messageClass %>"><%= h(message) %></div>
        <% } %>
        <div class="sim-actions">
            <form method="post">
                <input type="hidden" name="action" value="start">
                <button type="submit" <%= running ? "disabled" : "" %>>시뮬레이터 실행</button>
            </form>
            <form method="post">
                <input type="hidden" name="action" value="stop">
                <button type="submit" class="danger" <%= running ? "" : "disabled" %>>시뮬레이터 중지</button>
            </form>
            <button type="button" class="secondary" onclick="location.reload()">상태 새로고침</button>
        </div>
        <% if (running) { %>
            <p class="muted">아래 버튼으로 시뮬레이터 UI를 열 수 있습니다.</p>
            <div class="sim-actions">
                <button type="button" onclick="window.open('http://127.0.0.1:1503/','_blank')">시뮬레이터 UI 열기</button>
            </div>
        <% } else { %>
            <p>실행 버튼을 사용할 수 없을 때는 PowerShell 또는 CMD에서 아래 명령을 실행하세요.</p>
            <div class="cmd">cd C:\Tomcat 9.0\webapps\ROOT\ups\simulator<br>start_simulator.bat</div>
        <% } %>
    </div>
</div>
</body>
</html>
