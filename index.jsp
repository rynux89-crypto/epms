<%@ page import="java.io.*,java.util.*" contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" %>
<%@ include file="/WEB-INF/include/app_version.jspf" %>
<%!
private int parseIntOrDefault(String v, int defVal, int min, int max) {
    try {
        int n = Integer.parseInt(v == null ? "" : v.trim());
        if (n < min) return min;
        if (n > max) return max;
        return n;
    } catch (Exception ignore) {
        return defVal;
    }
}
%>
<%
int chatWidthPx = 360;
int chatMaxHeightVh = 60;
int chatFontSizePx = 13;
try {
    String epmsPath = application.getRealPath("/epms");
    if (epmsPath != null && !epmsPath.isEmpty()) {
        File f = new File(epmsPath, "agent_model.properties");
        if (f.exists() && f.isFile()) {
            Properties p = new Properties();
            try (InputStream in = new FileInputStream(f);
                 Reader reader = new InputStreamReader(in, "UTF-8")) {
                p.load(reader);
            }
            chatWidthPx = parseIntOrDefault(p.getProperty("chat_width_px"), 360, 300, 560);
            chatMaxHeightVh = parseIntOrDefault(p.getProperty("chat_max_height_vh"), 60, 40, 90);
            chatFontSizePx = parseIntOrDefault(p.getProperty("chat_font_size_px"), 13, 12, 20);
        }
    }
} catch (Exception ignore) {
}
%>
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="utf-8" />
    <title>EPMS 메인</title>
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <style>
        body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#f5f7fb}
        .card{background:#fff;padding:18px;border-radius:8px;box-shadow:0 6px 18px rgba(0,0,0,.06);max-width:980px}
        .links a{display:inline-block;margin:8px 12px;padding:8px 12px;background:#007acc;color:#fff;border-radius:6px;text-decoration:none}
    </style>
</head>
<body>
  <div class="card">
    <h1>EPMS 대시보드</h1>
    <p>전력 모니터링 시스템에 오신 것을 환영합니다.</p>
    <p>Version <%= APP_VERSION %></p>
    <div class="links">
      <a href="/epms/epms_main.jsp">EPMS 상세 화면 보기</a>
    </div>
    <hr/>
    <p>오른쪽 하단의 <strong>EPMS Chat</strong> 버튼으로 질문하세요.</p>
  </div>
  <script>
    window.EPMS_AGENT_UI_DEFAULTS = {
      widthPx: <%= chatWidthPx %>,
      maxHeightVh: <%= chatMaxHeightVh %>,
      fontSizePx: <%= chatFontSizePx %>
    };
  </script>
  <script src="<%= request.getContextPath() %>/js/epms_agent.js?v=<%= ASSET_VERSION %>"></script>
</body>
</html>
