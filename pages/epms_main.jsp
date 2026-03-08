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
            grid-template-columns: repeat(3, 1fr);
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
<h1>📊 EPMS 전력 품질 관리 시스템</h1>

<div class="container">
    <div class="section">
        <h2>🧭 통합 전력품질 모니터링</h2>
        <p>역률, 주파수, 전압, 전류를 하나의 화면에서 동시에 분석.</p>
        <a href="pq_overview.jsp" class="link-button right">통합 품질 모니터링</a>
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
        <h2>🎵 고조파 분석</h2>
        <p>THD 및 주요 고조파 성분(3, 5, 7, 9, 11차)을 분석하여 전력 품질 저하 요인을 파악.</p>
        <div class="button-group right">
            <a href="harmonics_v.jsp" class="link-button right">전압 고조파 분석</a>
            <a href="harmonics_i.jsp" class="link-button right">전류 고조파 분석</a>
        </div>
    </div>

    <div class="section">
        <h2>🧾 계측기 등록 관리</h2>
        <p>건물명/판넬명 검색과 계측기 등록, 수정, 삭제를 수행.</p>
        <a href="/pages/meter_register.jsp" class="link-button right">계측기 등록 화면</a>
    </div>

    
</div>

<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
