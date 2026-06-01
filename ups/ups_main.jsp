<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<!doctype html>
<html>
<head>
    <title>UPS 모니터링</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .ups-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:14px; margin-top:16px; }
        .ups-card { display:block; padding:18px; border:1px solid #dbe5f2; border-radius:8px; background:#fff; color:#1f3347; text-decoration:none; }
        .ups-card h3 { margin:0 0 8px; font-size:18px; }
        .ups-card p { margin:0; color:#64748b; font-size:13px; line-height:1.5; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div>
            <h2>UPS 모니터링</h2>
            <p class="muted">Modbus TCP UPS 장비를 등록하고 상태, 배터리, 알람을 확인합니다.</p>
        </div>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='<%= request.getContextPath() %>/index.jsp'">홈</button>
        </div>
    </div>

    <div class="ups-grid">
        <a class="ups-card" href="monitoring/ups_status.jsp">
            <h3>실시간 상태</h3>
            <p>등록된 UPS의 통신 상태와 최근 계측값을 확인합니다.</p>
        </a>
        <a class="ups-card" href="monitoring/phasor_diagram.jsp">
            <h3>Phasor Diagram</h3>
            <p>출력 전압과 역률 기반 추정 전류 위상도를 확인합니다.</p>
        </a>
        <a class="ups-card" href="history/measurement_history.jsp">
            <h3>측정 이력</h3>
            <p>DB에 저장된 UPS 과거 측정값을 기간별로 조회합니다.</p>
        </a>
        <a class="ups-card" href="system/ups_register.jsp">
            <h3>UPS 등록</h3>
            <p>IP, 포트, Unit ID, 프로파일을 등록하면 수집 대상에 포함됩니다.</p>
        </a>
        <a class="ups-card" href="system/setup.jsp">
            <h3>초기 설정</h3>
            <p>UPS_MONITOR 데이터베이스와 기본 테이블을 확인합니다.</p>
        </a>
        <a class="ups-card" href="alarm/alarm_view.jsp">
            <h3>알람</h3>
            <p>활성 알람과 이력을 확인합니다.</p>
        </a>
        <a class="ups-card" href="simulator/index.jsp">
            <h3>UPS 시뮬레이터</h3>
            <p>로컬 시뮬레이터의 상태 시나리오를 버튼으로 변경합니다.</p>
        </a>
    </div>
</div>
</body>
</html>
