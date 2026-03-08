<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<html>
<head>
    <title>EPMS 전력 품질 관리 메인</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .section {
            display: flex;
            flex-direction: column;
            background: white;
            padding: 10px;
            margin-bottom: 5px;
            border-radius: 8px;
            box-shadow: 0 0 5px #ccc;
        }
        .section h2 { margin-top: 0; }
        .link-button {
            display: inline-block;
            width: auto;
            margin: 10px 0;
            padding: 10px 15px;
            background: #007acc;
            color: white;
            text-decoration: none;
            text-align: center;
            border-radius: 5px;
        }
        .link-button:hover { background: #005fa3; }
        .right {
            margin-top: auto;
            align-self: flex-end;
        }
        .container {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            align-items: stretch;
        }
        .button-group {
            display: flex;
            flex-direction: column;
            align-self: flex-end;
            gap: 5px;
            margin-top: auto;
        }
    </style>
</head>
<body>
<h1>📊 EPMS 전력 품질 관리 시스템 Ver 0.5</h1>

<div class="container">
    <div class="section">
        <h2>🧭 통합 전력품질 모니터링</h2>
        <p>주파수,역률, 전압, 전류를 하나의 화면에서 동시에 분석.</p>
        <div class="button-group right">
            <a href="pq_overview.jsp" class="link-button right">통합 품질 모니터링</a>
        </div>
    </div>

    <div class="section">
        <h2>🔎 계측기 상세 모니터링</h2>
        <p>계측기의 현재 상태를 모니터링.</p>
        <a href="meter_status.jsp?meter_id=0" class="link-button right">계측기 상세 모니터링</a>
    </div>

    <div class="section">
        <h2>📐 페이저 모니터링</h2>
        <p>전압과 전류의 위상값을 모니터링.</p>
        <a href="phasor_diagram.jsp?meter=0" class="link-button right">페이저 다이어그램</a>
    </div>

    <div class="section">
        <h2>🔀 불평형 분석</h2>
        <p>상시 측정된 Vab, Vbc, Vca 데이터를 기반으로 전압 불평형을 분석.</p>
        <a href="voltage_unbalance.jsp" class="link-button right">불평형 분석</a>
    </div>

    <div class="section">
        <h2>📈 변동율 분석</h2>
        <p>전압 및 전류의 시간대비 평균값을 기준으로 변동율을 계산하고 기준 초과 여부를 확인.</p>
        <a href="variation_ves.jsp" class="link-button right">전압 변동율 분석</a>
        <a href="variation_ces.jsp" class="link-button right">전류 변동율 분석</a>
    </div>

    <div class="section">
        <h2>📈 주파수 & 전압변동율 분석</h2>
        <p>주파수 변동에 따른 전압 변동율 분석.</p>
        <div class="button-group right">
            <a href="frequency_voltage.jsp" class="link-button right">주파수 & 전압변동율</a>
        </div>
    </div>

    <div class="section">
        <h2>🎵 고조파 분석</h2>
        <p>THD 및 주요 고조파 성분(3, 5, 7, 9, 11차)을 분석하여 전력 품질 저하 요인을 파악.</p>
        <div class="button-group right">
            <a href="harmonics_v.jsp" class="link-button right">전압 고조파 분석</a>
            <a href="harmonics_i.jsp" class="link-button right">전류 고조파 분석</a>
        </div>
    </div>

    <div class="section">
        <h2>⚡ 에너지 관리</h2>
        <p>적산 전력량 기준으로 일/월 사용량, 누적, 피크전력, 이상징후를 조회.</p>
        <div class="button-group right">
            <a href="energy_overview.jsp" class="link-button right">에너지 Overview</a>
            <a href="energy_manage.jsp" class="link-button right">에너지 관리</a>
            <a href="energy_sankey.jsp" class="link-button right">에너지 흐름 분석</a>
        </div>
    </div>

    <div class="section">
        <h2>🚨 알람 조회</h2>
        <p>전력 품질 이상 발생 기록의 알람 목록을 조회하고, 건물/용도/기간별로 필터링.</p>
        <div class="button-group right">
            <a href="alarm_view.jsp" class="link-button right">알람 목록</a>
            <a href="alarm_rule_manage.jsp" class="link-button right">알람 규칙 관리</a>
            <a href="alarm_rule.jsp" class="link-button right">알람 규칙 등록</a>
            <a href="metric_catalog_manage.jsp" class="link-button right">지표키 카탈로그</a>
        </div>
    </div>

    <div class="section">
        <h2>📝 이벤트 조회</h2>
        <p>PLC/계측 이벤트 이력을 조회하고, 조건별로 필터링하여 알람 상세로 이동.</p>
        <div class="button-group right">
            <a href="event_view.jsp" class="link-button right">이벤트 목록</a>
        </div>
    </div>
  

    <div class="section">
        <h2>🧾 계측기 등록 관리</h2>
        <p>건물명/판넬명 검색과 계측기 등록, 수정, 삭제를 수행.</p>
        <a href="meter_register.jsp" class="link-button right">계측기 등록 화면</a>
    </div>

    <div class="section">
        <h2>🧩 단선 계층 관리</h2>
        <p>부모-자식 계측기 트리(meter_tree) 관계를 등록/수정/삭제.</p>
        <a href="meter_tree_manage.jsp" class="link-button right">단선 계층 관리</a>
    </div>

    <div class="section">
        <h2>🧹 Data 관리</h2>
        <p>DB를 백업하고 데이터를 보관기간(5/7/10년) 기준으로 과거 계측 이력 데이터를 삭제.</p>
        <a href="data_retention_manage.jsp" class="link-button right">DB 및 Data 관리</a>
    </div>

    <div class="section">
        <h2>🛠 PLC 등록 관리</h2>
        <p>Modbus TCP PLC의 IP/Port를 등록하고 활성 상태를 관리.</p>
        <div class="button-group right">
            <a href="plc_register.jsp" class="link-button right">PLC 등록 화면</a>
            <a href="plc_status.jsp" class="link-button right">PLC 상태/읽기</a>
            <a href="plc_write.jsp" class="link-button right">PLC 샘플 쓰기</a>
            <a href="ai_mapping.jsp" class="link-button right">AI 매핑 화면</a>
            <a href="di_mapping.jsp" class="link-button right">DI 매핑 화면</a>
            <a href="plc_excel_import.jsp" class="link-button right">엑셀 자동 매핑</a>
            <a href="ai_measurements_match.jsp" class="link-button right">AI-Measurements 매칭</a>
            <a href="ai_measurements_match_manage.jsp" class="link-button right">AI-Measurements 매칭 관리</a>
            <a href="harmonic_sync.jsp" class="link-button right">고조파 동기화</a>
        </div>
    </div>    
</div>

<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
