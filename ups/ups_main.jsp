<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<!doctype html>
<html>
<head>
    <title>UPS 메인</title>
    <%@ include file="includes/ups_head_assets.jspf" %>
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
            <h2>UPS 메인</h2>
            <p class="muted">Modbus TCP UPS 장비를 등록하고 상태, 배터리, 알람, 레포트를 확인합니다.</p>
        </div>
    </div>

    <div class="ups-grid">
        <a class="ups-card" href="ups_dash.jsp">
            <h3>UPS 통합 모니터링</h3>
            <p>UPS 전체 상태, 전력 흐름, 실시간 추이, 알람과 배치도를 한 화면에서 확인합니다.</p>
        </a>
        <a class="ups-card" href="monitoring/ups_overview.jsp">
            <h3>UPS 전체 현황</h3>
            <p>등록된 모든 UPS를 타일 또는 리스트 형태로 한 번에 확인합니다.</p>
        </a>
        <a class="ups-card" href="monitoring/ups_status.jsp">
            <h3>UPS 모니터링</h3>
            <p>UPS의 통신 상태와 최근 측정값, 미믹 다이어그램을 확인합니다.</p>
        </a>
        <a class="ups-card" href="monitoring/phasor_diagram.jsp">
            <h3>UPS Phasor Diagram</h3>
            <p>출력 전압과 역률 기반 추정 전류 위상각을 확인합니다.</p>
        </a>
        <a class="ups-card" href="report/ups_report.jsp">
            <h3>UPS 레포트</h3>
            <p>기간별 운전 요약, 전력 품질, 배터리, 알람/이벤트 집계를 확인합니다.</p>
        </a>
        <a class="ups-card" href="history/measurement_history.jsp">
            <h3>UPS 측정 이력</h3>
            <p>DB에 저장된 UPS 과거 측정값을 기간별로 조회합니다.</p>
        </a>
        <a class="ups-card" href="alarm/alarm_view.jsp">
            <h3>UPS 알람</h3>
            <p>현재 발생 중이거나 해제된 알람을 확인합니다.</p>
        </a>
        <a class="ups-card" href="alarm/event_view.jsp">
            <h3>UPS 이벤트</h3>
            <p>운전 모드 변경과 스위치 조작 이력을 시간순으로 확인합니다.</p>
        </a>
        <a class="ups-card" href="system/ups_register.jsp">
            <h3>UPS 등록</h3>
            <p>IP, 포트, Unit ID, 프로파일을 등록하면 수집 대상에 포함됩니다.</p>
        </a>
        <a class="ups-card" href="system/setup.jsp">
            <h3>UPS 초기 설정</h3>
            <p>UPS_MONITOR 데이터베이스와 기본 테이블, 수집 상태를 확인합니다.</p>
        </a>
        <a class="ups-card" href="simulator/index.jsp">
            <h3>UPS 시뮬레이터</h3>
            <p>로컬 시뮬레이터의 상태 시나리오와 알람 테스트를 실행합니다.</p>
        </a>
    </div>
</div>
<%@ include file="includes/ups_footer.jspf" %>
</body>
</html>
