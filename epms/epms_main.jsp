<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<html>
<head>
    <title>EPMS 전력 품질 관리 메인</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1400px;margin:20px auto;padding:0 16px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-end;gap:12px;margin-bottom:18px}
        .page-head p{margin:0;color:var(--muted)}
        .container{align-items:start;gap:26px}
        .section{position:relative;padding:18px 18px 20px;border-width:2px;box-shadow:0 16px 30px rgba(15,23,42,.08)}
        .section::before{content:"";position:absolute;left:0;top:0;right:0;height:12px;border-radius:14px 14px 0 0}
        .section.monitoring{background:linear-gradient(180deg,#ffffff 0%,#f4f9ff 100%);border-color:#cfe0ff}
        .section.quality{background:linear-gradient(180deg,#ffffff 0%,#f7fbf6 100%);border-color:#cfe9d6}
        .section.energy{background:linear-gradient(180deg,#ffffff 0%,#fff9f1 100%);border-color:#f2ddb1}
        .section.system{background:linear-gradient(180deg,#ffffff 0%,#f8f7ff 100%);border-color:#d8cef7}
        .section.plc{background:linear-gradient(180deg,#ffffff 0%,#f6fbfb 100%);border-color:#c8e9e8}
        .section.monitoring::before{background:linear-gradient(90deg,#7da7e8 0%,#bfd6fb 100%)}
        .section.quality::before{background:linear-gradient(90deg,#7fc48f 0%,#caead1 100%)}
        .section.energy::before{background:linear-gradient(90deg,#e7b85c 0%,#f6dfac 100%)}
        .section.system::before{background:linear-gradient(90deg,#9f8ae0 0%,#ddd4f8 100%)}
        .section.plc::before{background:linear-gradient(90deg,#6cc8c5 0%,#c8efed 100%)}
        .section.monitoring .section-eyebrow{background:#eaf2ff;border-color:#cfe0ff;color:#1f4f97}
        .section.quality .section-eyebrow{background:#ecf8ef;border-color:#cfe9d6;color:#1d6a43}
        .section.energy .section-eyebrow{background:#fff3dd;border-color:#f2ddb1;color:#9a6200}
        .section.system .section-eyebrow{background:#f0ecff;border-color:#d8cef7;color:#5d49a8}
        .section.plc .section-eyebrow{background:#e8f7f7;border-color:#c8e9e8;color:#126b6a}
        .section-eyebrow .eyebrow-icon{width:14px;height:14px;display:inline-block;vertical-align:middle}
        .section-eyebrow .eyebrow-icon svg{width:14px;height:14px;stroke:currentColor;fill:none;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
        .section-header{padding-top:6px}
        .section h2{padding-bottom:10px;border-bottom:1px solid rgba(148,163,184,.22);margin-bottom:4px}
        .section-links{display:grid !important;grid-template-columns:repeat(4,minmax(0,1fr)) !important;gap:12px;align-items:start}
        .app-card{min-height:168px;height:auto;padding:0;overflow:hidden;border:1px solid #cbd7e6;border-radius:14px;background:#fff;box-shadow:0 10px 22px rgba(15,23,42,.08);align-self:start}
        .app-card a.sub-card-link{display:grid;grid-template-rows:auto auto auto;gap:10px;height:auto;min-height:168px;padding:16px 14px;color:inherit;text-decoration:none;background:linear-gradient(180deg,#ffffff 0%,#f8fbfd 100%);border-top:6px solid #b8c7da;transition:transform .15s ease, box-shadow .15s ease, background .15s ease, border-color .15s ease}
        .app-card a.sub-card-link:hover{transform:translateY(-3px);background:linear-gradient(180deg,#ffffff 0%,#eef5ff 100%);border-top-color:#4f83cc}
        .tile-head{display:flex;align-items:flex-start;gap:10px}
        .tile-icon{display:flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:10px;background:#eef4fb;flex:0 0 34px}
        .tile-icon svg{width:18px;height:18px;stroke:#23415f;fill:none;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
        .section.monitoring .tile-icon{background:#eaf2ff}
        .section.quality .tile-icon{background:#ecf8ef}
        .section.energy .tile-icon{background:#fff3dd}
        .section.system .tile-icon{background:#f0ecff}
        .section.plc .tile-icon{background:#e8f7f7}
        .app-card h3{font-size:15px;line-height:1.35;margin:0}
        .app-card p{font-size:12px;line-height:1.5;color:#5f7287}
        .sub-card-meta{margin-top:auto;font-size:11px;font-weight:800;color:var(--primary);letter-spacing:.04em;text-transform:uppercase}
        .section.monitoring .app-card a.sub-card-link{border-top-color:#7da7e8}
        .section.quality .app-card a.sub-card-link{border-top-color:#7fc48f}
        .section.energy .app-card a.sub-card-link{border-top-color:#e7b85c}
        .section.system .app-card a.sub-card-link{border-top-color:#9f8ae0}
        .section.plc .app-card a.sub-card-link{border-top-color:#6cc8c5}
        @media (max-width:1100px){.section-links{grid-template-columns:repeat(2,minmax(0,1fr)) !important}}
        @media (max-width:768px){.page-head{flex-direction:column;align-items:flex-start}.container{gap:18px}.section{padding:16px}.section-links{grid-template-columns:1fr !important}}
    </style>
</head>
<body>
<div class="page-head">
    <div>
        <h1>EPMS 전력 품질 관리 시스템</h1>
        <p>모니터링, 에너지 관리, 알람, PLC 운영 화면을 공통 대시보드 스타일로 제공합니다.</p>
    </div>
    <div class="meta-info" style="width:auto;">Version 0.5.1</div>
</div>

<div class="container">
    <div class="section monitoring">
        <div class="section-header">
            <div class="section-eyebrow"><span class="eyebrow-icon"><svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8"/><path d="M12 16v4"/></svg></span>Monitoring</div>
            <h2>모니터링</h2>
            <p>실시간 계측 상태, 이벤트, 알람을 중심으로 현재 운영 상황을 빠르게 확인합니다.</p>
        </div>
        <div class="section-links">
            <div class="app-card">
                <a href="meter_status.jsp?meter_id=0" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8"/><path d="M8 11h8"/><path d="M10 17h4"/></svg></span><h3>계측기 상세 모니터링</h3></div>
                    <p>계측기의 현재 상태와 파형을 확인합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="pq_overview.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M4 19h16"/><path d="M6 15l3-3 3 2 5-6 1 1"/></svg></span><h3>통합 품질 모니터링</h3></div>
                    <p>주파수, 역률, 전압, 전류를 한 화면에서 봅니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="phasor_diagram.jsp?meter=0" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><path d="M12 12l4-4"/><path d="M12 12V7"/></svg></span><h3>페이저 다이어그램</h3></div>
                    <p>전압과 전류의 위상 관계를 시각적으로 점검합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="event_view.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M8 7h8"/><path d="M8 11h8"/><path d="M8 15h5"/><rect x="5" y="3" width="14" height="18" rx="2"/></svg></span><h3>이벤트 목록</h3></div>
                    <p>계측 및 PLC 이벤트 이력을 조회합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="alarm_view.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M12 4v8"/><path d="M9 20h6"/><path d="M5 15a7 7 0 0 0 14 0"/><path d="M7 9a5 5 0 0 1 10 0"/></svg></span><h3>알람 목록</h3></div>
                    <p>현재 및 과거 알람을 조건별로 조회합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
        </div>
    </div>

    <div class="section quality">
        <div class="section-header">
            <div class="section-eyebrow"><span class="eyebrow-icon"><svg viewBox="0 0 24 24"><path d="M4 7h16"/><path d="M7 7v10"/><path d="M12 7v6"/><path d="M17 7v13"/></svg></span>Quality Analysis</div>
            <h2>품질분석</h2>
            <p>전압, 전류, 주파수, 고조파 관점에서 전력 품질 저하 요인을 분석합니다.</p>
        </div>
        <div class="section-links">
            <div class="app-card">
                <a href="voltage_unbalance.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M12 5v14"/><path d="M6 9h12"/><path d="M7 9l-3 5h6l-3-5z"/><path d="M17 9l-3 5h6l-3-5z"/></svg></span><h3>불평형 분석</h3></div>
                    <p>전압 불평형을 상시 계측값 기준으로 분석합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="variation_ves.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><rect x="5" y="7" width="12" height="10" rx="2"/><path d="M19 10v4"/><path d="M8 13l2-2 2 2 2-2"/></svg></span><h3>전압 변동율 분석</h3></div>
                    <p>전압 평균값 대비 변동 특성을 확인합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="variation_ces.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M9 7v5"/><path d="M15 7v5"/><path d="M8 12h8"/><path d="M12 12v7"/></svg></span><h3>전류 변동율 분석</h3></div>
                    <p>전류 변동 추세와 기준 초과 여부를 확인합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="frequency_voltage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M4 16a8 8 0 0 1 16 0"/><path d="M7 16a5 5 0 0 1 10 0"/><path d="M10 16a2 2 0 0 1 4 0"/></svg></span><h3>주파수 & 전압변동율</h3></div>
                    <p>주파수와 전압 변동의 상관을 봅니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="harmonics_v.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M3 13c2-6 4 6 6 0s4-6 6 0 4 6 6 0"/></svg></span><h3>전압 고조파 분석</h3></div>
                    <p>THD와 주요 전압 고조파 성분을 분석합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="harmonics_i.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M3 12c2-4 4 4 6 0s4-4 6 0 4 4 6 0"/></svg></span><h3>전류 고조파 분석</h3></div>
                    <p>전류 고조파와 전력 품질 저하 요인을 분석합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
        </div>
    </div>

    <div class="section energy">
        <div class="section-header">
            <div class="section-eyebrow"><span class="eyebrow-icon"><svg viewBox="0 0 24 24"><path d="M13 2L6 13h5l-1 9 8-12h-5l0-8z"/></svg></span>Energy</div>
            <h2>에너지 관리</h2>
            <p>누적 전력량 기준 사용량, 피크전력, 에너지 흐름을 분석합니다.</p>
        </div>
        <div class="section-links">
            <div class="app-card">
                <a href="energy_overview.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M5 19V9"/><path d="M12 19V5"/><path d="M19 19v-8"/><path d="M4 19h16"/></svg></span><h3>에너지 Overview</h3></div>
                    <p>전사 에너지와 알람 현황을 한 번에 봅니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="energy_manage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M4 18h16"/><path d="M6 8l4 4 3-3 5 5"/></svg></span><h3>에너지 관리</h3></div>
                    <p>기간별 사용량과 KPI, 이상 징후를 분석합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="energy_sankey.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M6 7h8a4 4 0 1 1 0 8H6"/><path d="M14 7l3-3"/><path d="M14 7l3 3"/><path d="M10 15l-3-3"/><path d="M10 15l-3 3"/></svg></span><h3>에너지 흐름 분석</h3></div>
                    <p>트리 구조 기준으로 에너지 흐름을 추적합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
        </div>
    </div>

    <div class="section system">
        <div class="section-header">
            <div class="section-eyebrow"><span class="eyebrow-icon"><svg viewBox="0 0 24 24"><path d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.2a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.2a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h.1A1.7 1.7 0 0 0 10 3.2V3a2 2 0 1 1 4 0v.2a1.7 1.7 0 0 0 1 1.5h.1a1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v.1a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.2a1.7 1.7 0 0 0-1.4 1z"/></svg></span>System Admin</div>
            <h2>시스템 관리</h2>
            <p>알람 규칙, 계측기 구성, 데이터 보관 정책 등 운영 기준 정보를 관리합니다.</p>
        </div>
        <div class="section-links">
            <div class="app-card">
                <a href="alarm_rule_manage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><rect x="6" y="4" width="12" height="16" rx="2"/><path d="M9 9h6"/><path d="M9 13h6"/></svg></span><h3>알람 규칙 관리</h3></div>
                    <p>알람 규칙을 조회하고 수정합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="alarm_rule.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M12 5v14"/><path d="M5 12h14"/></svg></span><h3>알람 규칙 등록</h3></div>
                    <p>새로운 규칙을 등록합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="metric_catalog_manage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M4 7h16v10H4z"/><path d="M9 7V5h6v2"/></svg></span><h3>지표키 카탈로그</h3></div>
                    <p>알람 및 품질 지표 키를 관리합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="meter_register.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M20 10l-8 8-8-8V4h6l10 6z"/><circle cx="7.5" cy="7.5" r="1"/></svg></span><h3>계측기 등록 화면</h3></div>
                    <p>건물/패널/계측기 정보를 관리합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="meter_tree_manage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M12 20V8"/><path d="M6 8h12"/><path d="M8 12h8"/><path d="M10 16h4"/></svg></span><h3>단선 계층 관리</h3></div>
                    <p>부모-자식 계측기 트리를 유지합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="data_retention_manage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/><path d="M5 12c0 1.7 3.1 3 7 3s7-1.3 7-3"/></svg></span><h3>DB 및 Data 관리</h3></div>
                    <p>백업과 이력 데이터 보관 정책을 관리합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
        </div>
    </div>

    <div class="section plc">
        <div class="section-header">
            <div class="section-eyebrow"><span class="eyebrow-icon"><svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/><path d="M12 3v4"/><path d="M5 12H3"/><path d="M21 12h-2"/><path d="M8 20h8"/><circle cx="10" cy="11" r="1"/><circle cx="14" cy="11" r="1"/></svg></span>PLC Operations</div>
            <h2>PLC관리</h2>
            <p>PLC 등록, 상태 확인, 샘플 쓰기와 각종 매핑 연계를 운영합니다.</p>
        </div>
        <div class="section-links">
            <div class="app-card">
                <a href="plc/plc_register.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><rect x="7" y="5" width="10" height="14" rx="2"/><path d="M10 9h4"/><path d="M10 13h4"/></svg></span><h3>PLC 등록 화면</h3></div>
                    <p>PLC 접속 정보를 등록하고 관리합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="plc/plc_status.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="1"/><path d="M8.5 15.5a5 5 0 0 1 7 0"/><path d="M6 18a8.5 8.5 0 0 1 12 0"/><path d="M8.5 8.5a5 5 0 0 1 7 0"/></svg></span><h3>PLC 상태/읽기</h3></div>
                    <p>통신 상태와 값을 확인합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="plc/plc_write.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M4 20h4l10-10-4-4L4 16v4z"/><path d="M13 7l4 4"/></svg></span><h3>PLC 샘플 쓰기</h3></div>
                    <p>테스트용 값을 PLC에 씁니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="ai_mapping.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M9 8a3 3 0 1 1 6 0c1.7 0 3 1.3 3 3 0 1.3-.8 2.3-2 2.8V16a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-2.2A3 3 0 0 1 6 11c0-1.7 1.3-3 3-3z"/><path d="M10 18v2"/><path d="M14 18v2"/></svg></span><h3>AI 매핑 화면</h3></div>
                    <p>AI 기반 태그 매핑을 수행합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="di_mapping.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M10 13a5 5 0 0 1 0-7l1-1a5 5 0 0 1 7 7l-1 1"/><path d="M14 11a5 5 0 0 1 0 7l-1 1a5 5 0 0 1-7-7l1-1"/></svg></span><h3>DI 매핑 화면</h3></div>
                    <p>디지털 입력 매핑을 관리합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="plc/plc_excel_import.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/><path d="M10 12l4 4"/><path d="M14 12l-4 4"/></svg></span><h3>엑셀 자동 매핑</h3></div>
                    <p>엑셀 기반 일괄 매핑을 수행합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="ai_measurements_match.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M10 3v5l-4 7a3 3 0 0 0 2.6 4.5h6.8A3 3 0 0 0 18 15l-4-7V3"/><path d="M9 11h6"/></svg></span><h3>AI-Measurements 매칭</h3></div>
                    <p>측정 항목과 AI 매핑 결과를 연결합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="ai_measurements_match_manage.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><rect x="4" y="6" width="16" height="4" rx="1"/><rect x="4" y="14" width="16" height="4" rx="1"/><path d="M9 8h6"/><path d="M9 16h6"/></svg></span><h3>AI-Measurements 매칭 관리</h3></div>
                    <p>기존 매칭 결과를 관리합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
            <div class="app-card">
                <a href="harmonic_sync.jsp" class="sub-card-link">
                    <div class="tile-head"><span class="tile-icon"><svg viewBox="0 0 24 24"><path d="M8 18V6l10-2v12"/><circle cx="8" cy="18" r="2"/><circle cx="18" cy="16" r="2"/></svg></span><h3>고조파 동기화</h3></div>
                    <p>고조파 관련 데이터 연계를 실행합니다.</p>
                    <span class="sub-card-meta">바로가기</span>
                </a>
            </div>
        </div>
    </div>    
</div>

<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
