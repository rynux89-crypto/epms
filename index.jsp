<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" %>
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
    <p>전력 품질 모니터링 시스템에 오신 것을 환영합니다.</p>
    <div class="links">
      <a href="/epms/epms_main.jsp">EPMS 상세 화면 보기</a>
    </div>
    <hr/>
    <p>오른쪽 하단의 <strong>EPMS Chat</strong> 버튼으로 질문하세요.</p>
  </div>
  <script src="<%= request.getContextPath() %>/js/epms_agent.js"></script>
</body>
</html>
