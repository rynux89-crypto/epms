<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../../includes/dbconfig.jspf" %>
<%
    try (Connection conn = openDbConnection()) {
    List<Map<String, Object>> plcList = new ArrayList<>();
    Map<Integer, String> meterNameMap = new HashMap<>();
    Map<Integer, String> meterPanelMap = new HashMap<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("plc_id", rs.getInt("plc_id"));
                r.put("plc_ip", rs.getString("plc_ip"));
                r.put("plc_port", rs.getInt("plc_port"));
                r.put("unit_id", rs.getInt("unit_id"));
                r.put("polling_ms", rs.getInt("polling_ms"));
                r.put("enabled", rs.getBoolean("enabled"));
                plcList.add(r);
            }
        }

        try (PreparedStatement ps = conn.prepareStatement("SELECT meter_id, name, panel_name FROM dbo.meters ORDER BY meter_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                int meterId = rs.getInt("meter_id");
                meterNameMap.put(meterId, rs.getString("name"));
                meterPanelMap.put(meterId, rs.getString("panel_name"));
            }
        }
%>
<html>
<head>
    <title>PLC Status</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { width: min(96vw, 1680px); margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; box-sizing: border-box; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .plc-table-wrap { width: 100%; border: 1px solid #d9e3ee; border-radius: 18px; overflow-x: auto; overflow-y: hidden; background: rgba(255,255,255,0.92); box-sizing: border-box; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; white-space: nowrap; }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .state-badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; white-space: nowrap; }
        .state-running { background: #e9f7ef; color: #117a37; border: 1px solid #b7e5c6; }
        .state-stopped { background: #f4f6f8; color: #475569; border: 1px solid #d8e0e8; }
        .state-inactive { background: #fff4e5; color: #b45309; border: 1px solid #fed7aa; }
        .state-error { background: #fff1f2; color: #b42318; border: 1px solid #fecdd3; }
        .state-wrap { display: flex; flex-direction: column; gap: 4px; align-items: flex-start; }
        .state-reason { font-size: 11px; line-height: 1.35; color: #64748b; white-space: normal; word-break: keep-all; overflow-wrap: break-word; max-width: 165px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; }
        th { font-size: 11px; white-space: normal; word-break: keep-all; line-height: 1.25; }
        .ctrl-col { width: 184px; min-width: 184px; }
        .ctrl { display: inline-flex; gap: 6px; flex-wrap: wrap; white-space: normal; }
        .ctrl button { min-width: 52px; padding: 2px 6px; font-size: 11px; }
        .plc-table th, .plc-table td { padding: 6px 8px; }
        .plc-table { width: 100%; min-width: 1370px; table-layout: fixed; box-sizing: border-box; }
        .plc-table th:nth-child(1), .plc-table td:nth-child(1) { width: 58px; }
        .plc-table th:nth-child(2), .plc-table td:nth-child(2) { width: 122px; }
        .plc-table th:nth-child(3), .plc-table td:nth-child(3) { width: 50px; }
        .plc-table th:nth-child(4), .plc-table td:nth-child(4) { width: 54px; }
        .plc-table th:nth-child(5), .plc-table td:nth-child(5) { width: 90px; }
        .plc-table th:nth-child(6), .plc-table td:nth-child(6) { width: 72px; }
        .plc-table th:nth-child(8), .plc-table td:nth-child(8) { width: 186px; min-width: 186px; vertical-align: top; }
        .plc-table th:nth-child(9), .plc-table td:nth-child(9),
        .plc-table th:nth-child(11), .plc-table td:nth-child(11),
        .plc-table th:nth-child(12), .plc-table td:nth-child(12) { width: 78px; min-width: 78px; }
        .plc-table th:nth-child(10), .plc-table td:nth-child(10),
        .plc-table th:nth-child(13), .plc-table td:nth-child(13) { width: 136px; min-width: 136px; white-space: nowrap; }
        .plc-table th:nth-child(14), .plc-table td:nth-child(14) { width: 82px; min-width: 82px; white-space: nowrap; }
        .data-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; align-items: start; }
        @media (max-width: 1100px) {
            .data-grid { grid-template-columns: 1fr; }
        }
        .data-col h3 { margin: 0 0 8px 0; }
        .filter-row { display:flex; align-items:center; gap:8px; margin:6px 0 10px 0; flex-wrap: wrap; }
        .filter-row label { white-space: nowrap; }
        .filter-row select { min-width: 220px; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🤖 PLC 상태 / 수동 읽기</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        PLC 선택 없이 각 행에서 개별 제어합니다.<br/>
        사용 여부는 PLC 설정 활성화 상태이고, 실제 통신 상태는 운영상태 컬럼에서 확인합니다.<br/>
        DI/AI 읽기 횟수는 현재 상태가 아니라 서버 시작 후 누적 읽기 횟수입니다.<br/>
        시작: 서버 백그라운드에서 자동 읽기 주기(ms) 기준으로 연속 읽기(화면 닫힘 후에도 지속), 중지: 해당 PLC 연속 읽기 중단<br/>
        이 화면은 상태만 조회하며 PLC 연속 읽기를 자동 시작하지 않습니다. AI 읽기 주기는 각 PLC의 자동 읽기 주기(ms)와 동일합니다.
    </div>

    <div id="okBox" class="ok-box" style="display:none;"></div>
    <div id="errBox" class="err-box" style="display:none;"></div>

    <h3 style="margin-top:12px;">PLC 등록 상태</h3>
    <div class="plc-table-wrap">
    <table class="plc-table">
        <thead>
        <tr>
            <th>PLC ID</th>
            <th>PLC IP</th>
            <th>포트</th>
            <th>Unit ID</th>
            <th>자동 읽기 주기(ms)</th>
            <th>사용 여부</th>
            <th class="ctrl-col">제어</th>
            <th>운영상태</th>
            <th>DI 누적 읽기 횟수</th>
            <th>DI 마지막 읽은 시각</th>
            <th>DI 읽은 시간(ms)</th>
            <th>AI 누적 읽기 횟수</th>
            <th>AI 마지막 읽은 시각</th>
            <th>AI 읽은 시간(ms)</th>
        </tr>
        </thead>
        <tbody>
        <% if (plcList.isEmpty()) { %>
        <tr><td colspan="14">등록된 PLC가 없습니다.</td></tr>
        <% } else { %>
            <% for (Map<String, Object> p : plcList) { %>
            <% boolean enabled = (Boolean)p.get("enabled"); %>
            <tr>
                <td><%= p.get("plc_id") %></td>
                <td class="mono"><%= p.get("plc_ip") %></td>
                <td><%= p.get("plc_port") %></td>
                <td><%= p.get("unit_id") %></td>
                <td><%= p.get("polling_ms") %></td>
                <td>
                    <% if (enabled) { %><span class="badge b-on">사용</span><% } else { %><span class="badge b-off">미사용</span><% } %>
                </td>
                <td class="ctrl-col">
                    <div class="ctrl">
                        <button type="button" class="btn-read-once" data-plc-id="<%= p.get("plc_id") %>" <%= enabled ? "" : "disabled" %>>읽기 1회</button>
                        <button type="button" class="btn-start" data-plc-id="<%= p.get("plc_id") %>" data-polling-ms="<%= p.get("polling_ms") %>" <%= enabled ? "" : "disabled" %>>시작</button>
                        <button type="button" class="btn-stop" data-plc-id="<%= p.get("plc_id") %>" disabled>중지</button>
                    </div>
                </td>
                <td id="state-<%= p.get("plc_id") %>">
                    <% if (enabled) { %>
                    <span class="state-badge state-stopped">중지됨</span>
                    <% } else { %>
                    <span class="state-badge state-inactive">비활성</span>
                    <% } %>
                </td>
                <td id="dicount-<%= p.get("plc_id") %>">0</td>
                <td id="lastdirun-<%= p.get("plc_id") %>">-</td>
                <td id="dims-<%= p.get("plc_id") %>">-</td>
                <td id="aicount-<%= p.get("plc_id") %>">0</td>
                <td id="lastairun-<%= p.get("plc_id") %>">-</td>
                <td id="aims-<%= p.get("plc_id") %>">-</td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>
    </div>

    <div class="filter-row">
        <label for="panelFilter">panel:</label>
        <select id="panelFilter">
            <option value="">전체</option>
        </select>
    </div>
    <div class="data-grid">
        <div class="data-col">
            <h3>AI 데이터 (float)</h3>
            <table>
                <thead>
                <tr>
                    <th>#</th>
                    <th>plc_id</th>
                    <th>meter_id</th>
                    <th>panel_name</th>
                    <th>tag</th>
                    <th>reg1</th>
                    <th>value_float</th>
                </tr>
                </thead>
                <tbody id="readRows">
                <tr><td colspan="7">아직 AI 데이터가 없습니다.</td></tr>
                </tbody>
            </table>
        </div>
        <div class="data-col">
            <h3>DI 데이터 (bit)</h3>
            <table>
                <thead>
                <tr>
                    <th>#</th>
                    <th>plc_id</th>
                    <th>point_id</th>
                    <th>di_address</th>
                    <th>bit_no</th>
                    <th>tag_name</th>
                    <th>item_name</th>
                    <th>panel_name</th>
                    <th>value</th>
                </tr>
                </thead>
                <tbody id="diRows">
                <tr><td colspan="9">아직 DI 데이터가 없습니다.</td></tr>
                </tbody>
            </table>
        </div>
    </div>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>

<script>
(function(){
const API = 'modbus_api.jsp';
  const meterNameMap = {
    <% boolean firstMeter = true; for (Map.Entry<Integer, String> e : meterNameMap.entrySet()) { %>
      <% if (!firstMeter) { %>,<% } %>"<%= e.getKey() %>":"<%= (e.getValue() == null ? "" : e.getValue().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")) %>"<% firstMeter = false; %>
    <% } %>
  };
  const meterPanelMap = {
    <% boolean firstPanel = true; for (Map.Entry<Integer, String> e : meterPanelMap.entrySet()) { %>
      <% if (!firstPanel) { %>,<% } %>"<%= e.getKey() %>":"<%= (e.getValue() == null ? "" : e.getValue().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")) %>"<% firstPanel = false; %>
    <% } %>
  };
  const DEFAULT_PANEL = String(meterPanelMap['1'] || '').trim();
  const rowsBody = document.getElementById('readRows');
  const okBox = document.getElementById('okBox');
  const errBox = document.getElementById('errBox');
  const panelFilter = document.getElementById('panelFilter');
  const diRowsBody = document.getElementById('diRows');
  const serverStates = {};
  const lastRowsByPlc = {};
  const lastDiRowsByPlc = {};
  const actionBusy = {};
  const SNAPSHOT_MS_ACTIVE = 1000;
  const SNAPSHOT_MS_HIDDEN = 30000;
  const INITIAL_AI_RETRY_DELAY_MS = 1200;
  const INITIAL_AI_RETRY_MAX = 5;
  let snapshotTimer = null;
  let snapshotSyncBusy = false;
  let panelFilterInitialized = false;

  function showOk(msg){
    if (!msg) return;
    okBox.style.display = '';
    okBox.textContent = msg;
    errBox.style.display = 'none';
  }

  function showErr(msg){
    if (!msg) return;
    errBox.style.display = '';
    errBox.textContent = msg;
    okBox.style.display = 'none';
  }

  function summarizeHtmlResponse(text){
    const normalized = String(text || '').replace(/\s+/g, ' ').trim();
    if (!normalized) return '빈 응답';
    const lowered = normalized.toLowerCase();
    if (lowered.indexOf('<!doctype') >= 0 || lowered.indexOf('<html') >= 0) {
      return '서버가 JSON 대신 HTML 오류 페이지를 반환했습니다.';
    }
    return normalized.slice(0, 180);
  }

  async function parseJsonResponse(res){
    const contentType = String(res.headers.get('content-type') || '').toLowerCase();
    const raw = await res.text();
    if (!res.ok) {
      throw new Error('HTTP ' + res.status + ' ' + summarizeHtmlResponse(raw));
    }
    if (contentType.indexOf('application/json') < 0) {
      throw new Error(summarizeHtmlResponse(raw));
    }
    try {
      return JSON.parse(raw);
    } catch (e) {
      throw new Error('JSON 파싱 실패: ' + summarizeHtmlResponse(raw));
    }
  }

  function esc(s){
    return String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
  }

  function fmt2(v){
    const n = Number(v);
    return Number.isFinite(n)
      ? n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      : String(v ?? '');
  }

  function collectPanelNames() {
    const panels = new Set();
    const plcIds = Object.keys(lastRowsByPlc).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    plcIds.forEach(function(plcId){
      (lastRowsByPlc[plcId] || []).forEach(function(r){
        const panelName = String(meterPanelMap[String(r.meter_id)] || '').trim();
        if (panelName) panels.add(panelName);
      });
    });
    const diPlcIds = Object.keys(lastDiRowsByPlc).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    diPlcIds.forEach(function(plcId){
      (lastDiRowsByPlc[plcId] || []).forEach(function(r){
        const panelName = String(r.panel_name || '').trim();
        if (panelName) panels.add(panelName);
      });
    });
    return Array.from(panels).sort(function(a, b){ return a.localeCompare(b); });
  }

  function mergedRows(selectedPanel) {
    const plcIds = Object.keys(lastRowsByPlc).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    let idx = 1;
    const out = [];
    plcIds.forEach(function(plcId){
      (lastRowsByPlc[plcId] || []).forEach(function(r){
        const panelName = meterPanelMap[String(r.meter_id)] || '';
        if (selectedPanel && panelName !== selectedPanel) return;
        out.push({
          idx: idx++,
          plc_id: plcId,
          meter_id: r.meter_id,
          panel_name: panelName,
          token: r.token,
          reg1: r.reg1,
          reg2: r.reg2,
          value: r.value
        });
      });
    });
    return out;
  }

  function refreshPanelFilter(){
    const prev = panelFilter.value;
    const sortedPanels = collectPanelNames();

    let html = '<option value="">전체</option>';
    sortedPanels.forEach(function(panelName){
      html += '<option value="' + esc(panelName) + '">' + esc(panelName) + '</option>';
    });
    panelFilter.innerHTML = html;
    if (!panelFilterInitialized) {
      panelFilter.value = (DEFAULT_PANEL && sortedPanels.includes(DEFAULT_PANEL)) ? DEFAULT_PANEL : (sortedPanels.includes(prev) ? prev : '');
      panelFilterInitialized = true;
      return;
    }
    panelFilter.value = sortedPanels.includes(prev) ? prev : '';
  }

  function renderRows(rows){
    const viewRows = rows || [];

    if (!viewRows.length){
      rowsBody.innerHTML = '<tr><td colspan="7">아직 AI 데이터가 없습니다.</td></tr>';
      return;
    }
    const html = viewRows.map(r =>
      '<tr>' +
      '<td>' + esc(r.idx) + '</td>' +
      '<td>' + esc(r.plc_id) + '</td>' +
      '<td>' + esc(r.meter_id) + '</td>' +
      '<td>' + esc(r.panel_name || '-') + '</td>' +
      '<td class="mono">' + esc(r.token) + '</td>' +
      '<td class="mono">' + esc(r.reg1) + '</td>' +
      '<td class="mono">' + esc(fmt2(r.value)) + '</td>' +
      '</tr>'
    ).join('');
    rowsBody.innerHTML = html;
  }

  function mergedDiRows(selectedPanel) {
    const plcIds = Object.keys(lastDiRowsByPlc).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    let idx = 1;
    const out = [];
    plcIds.forEach(function(plcId){
      (lastDiRowsByPlc[plcId] || []).forEach(function(r){
        if (selectedPanel && String(r.panel_name || '') !== selectedPanel) return;
        out.push({
          idx: idx++,
          plc_id: plcId,
          point_id: r.point_id,
          di_address: r.di_address,
          bit_no: r.bit_no,
          tag_name: r.tag_name,
          item_name: r.item_name,
          panel_name: r.panel_name,
          value: r.value
        });
      });
    });
    return out;
  }

  function renderDiRows(rows){
    const viewRows = rows || [];

    if (!viewRows.length){
      diRowsBody.innerHTML = '<tr><td colspan="9">아직 DI 데이터가 없습니다.</td></tr>';
      return;
    }
    const html = viewRows.map(r =>
      '<tr>' +
      '<td>' + esc(r.idx) + '</td>' +
      '<td>' + esc(r.plc_id) + '</td>' +
      '<td>' + esc(r.point_id) + '</td>' +
      '<td class="mono">' + esc(r.di_address) + '</td>' +
      '<td class="mono">' + esc(r.bit_no) + '</td>' +
      '<td>' + esc(r.tag_name || '-') + '</td>' +
      '<td>' + esc(r.item_name || '-') + '</td>' +
      '<td>' + esc(r.panel_name || '-') + '</td>' +
      '<td class="mono">' + esc(r.value) + '</td>' +
      '</tr>'
    ).join('');
    diRowsBody.innerHTML = html;
  }

  function getStateBadgeHtml(state){
    switch (String(state || '').toLowerCase()) {
      case 'running':
        return '<span class="state-badge state-running">읽는 중</span>';
      case 'inactive':
        return '<span class="state-badge state-inactive">비활성</span>';
      case 'error':
        return '<span class="state-badge state-error">오류</span>';
      case 'stopped':
      default:
        return '<span class="state-badge state-stopped">중지됨</span>';
    }
  }

  function getStateReasonText(st, state){
    if (!st) return '';
    const normalized = String(state || '').toLowerCase();
    if (normalized === 'running') {
      return '';
    }
    return String(st.status_reason || st.last_error || st.last_info || '').trim();
  }

  function setPlcState(plcId, text, isErr, st){
    const el = document.getElementById('state-' + plcId);
    if (!el) return;
    const normalized = String(text || '').toLowerCase();
    const state = normalized === 'stopped' ? 'stopped' : (isErr ? 'error' : text);
    const reason = getStateReasonText(st, state);
    el.innerHTML = '<div class="state-wrap">' +
      getStateBadgeHtml(state) +
      (reason ? ('<div class="state-reason">' + esc(reason) + '</div>') : '') +
      '</div>';
  }

  function toNum(v){
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }

  function stateTextFromCounts(attempt, success){
    const a = toNum(attempt);
    const s = toNum(success);
    const rate = a > 0 ? (s * 100 / a) : 0;
    return a + '/' + s + '(' + rate.toFixed(1) + '%)';
  }

  function setReadCounts(plcId, diCount, aiCount){
    const diEl = document.getElementById('dicount-' + plcId);
    const aiEl = document.getElementById('aicount-' + plcId);
    if (diEl) diEl.textContent = String(toNum(diCount));
    if (aiEl) aiEl.textContent = String(toNum(aiCount));
  }

  function fmtTs(ms){
    const n = Number(ms);
    if (!Number.isFinite(n) || n <= 0) return '-';
    const d = new Date(n);
    const yyyy = d.getFullYear();
    const MM = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    const ss = String(d.getSeconds()).padStart(2, '0');
    return yyyy + '-' + MM + '-' + dd + ' ' + hh + ':' + mm + ':' + ss;
  }

  function setLastDiRunAt(plcId, lastDiRunAt){
    const el = document.getElementById('lastdirun-' + plcId);
    if (!el) return;
    el.textContent = fmtTs(lastDiRunAt);
  }

  function setLastAiRunAt(plcId, lastAiRunAt){
    const el = document.getElementById('lastairun-' + plcId);
    if (!el) return;
    el.textContent = fmtTs(lastAiRunAt);
  }

  function setReadMs(plcId, lastMs, diMs, aiMs, procMs){
    const diEl = document.getElementById('dims-' + plcId);
    const aiEl = document.getElementById('aims-' + plcId);
    if (!diEl || !aiEl) return;
    const diV = toNum(diMs);
    const aiV = toNum(aiMs);
    diEl.textContent = diV > 0 ? (diV + 'ms') : '-';
    aiEl.textContent = aiV > 0 ? (aiV + 'ms') : '-';
  }

  function setButtons(plcId, running){
    const start = document.querySelector('.btn-start[data-plc-id="' + plcId + '"]');
    const readOnce = document.querySelector('.btn-read-once[data-plc-id="' + plcId + '"]');
    const stop = document.querySelector('.btn-stop[data-plc-id="' + plcId + '"]');
    const busy = !!actionBusy[String(plcId)];
    const st = serverStates[String(plcId)];
    const enabled = !(st && st.enabled === false);
    if (readOnce) readOnce.disabled = busy || !enabled;
    if (start) start.disabled = busy || !enabled || running;
    if (stop) stop.disabled = busy || !enabled || !running;
  }

  function setActionBusy(plcId, busy){
    actionBusy[String(plcId)] = !!busy;
    const st = serverStates[String(plcId)];
    setButtons(plcId, !!(st && st.running));
  }

  async function callApi(action, plcId, pollingMs){
    const body = new URLSearchParams();
    body.append('action', action);
    body.append('plc_id', String(plcId));
    body.append('_ts', String(Date.now()));
    if (pollingMs != null) body.append('polling_ms', String(pollingMs));
    const res = await fetch(API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
      body: body.toString(),
      cache: 'no-store'
    });
    return await parseJsonResponse(res);
  }

  async function loadSnapshot(){
    if (snapshotSyncBusy) return;
    snapshotSyncBusy = true;
    try {
      const res = await fetch(API + '?action=polling_snapshot&_ts=' + Date.now(), { cache: 'no-store' });
      const data = await parseJsonResponse(res);
      if (!data.ok) return;

      Object.keys(lastRowsByPlc).forEach(function(k){ delete lastRowsByPlc[k]; });
      Object.keys(lastDiRowsByPlc).forEach(function(k){ delete lastDiRowsByPlc[k]; });

      const states = data.states || [];
      states.forEach(function(st){
        const plcId = String(st.plc_id);
        serverStates[plcId] = st;
        lastRowsByPlc[plcId] = st.rows || [];
        lastDiRowsByPlc[plcId] = st.di_rows || [];
        setButtons(plcId, !!st.running);
        setReadCounts(plcId, st.di_read_count, st.ai_read_count);
        setLastDiRunAt(plcId, st.last_di_run_at);
        setReadMs(plcId, st.last_read_ms, st.di_read_ms, st.ai_read_ms, st.proc_ms);
        setLastAiRunAt(plcId, st.last_ai_run_at);
        setPlcState(plcId, st.status || (st.running ? 'running' : 'stopped'), !!st.last_error && String(st.status || '').toLowerCase() === 'error', st);
      });

      refreshPanelFilter();
      const selectedPanel = panelFilter.value;
      renderRows(mergedRows(selectedPanel));
      renderDiRows(mergedDiRows(selectedPanel));
    } catch (e) {
      // ignore snapshot sync errors for UX continuity
    } finally {
      snapshotSyncBusy = false;
    }
  }

  async function readOnce(plcId){
    setActionBusy(plcId, true);
    try {
      const data = await callApi('read', plcId);
      if (!data.ok){
        showErr(data.error || '읽기 실패');
        return false;
      }
      showOk(data.info || '읽기 성공');
      lastRowsByPlc[plcId] = data.rows || [];
      lastDiRowsByPlc[plcId] = data.di_rows || [];
      refreshPanelFilter();
      const selectedPanel = panelFilter.value;
      renderRows(mergedRows(selectedPanel));
      renderDiRows(mergedDiRows(selectedPanel));
      return true;
    } catch (e){
      showErr('통신 오류: ' + e.message);
      return false;
    } finally {
      setActionBusy(plcId, false);
    }
  }

  async function startPolling(plcId, pollingMs){
    setActionBusy(plcId, true);
    try {
      const ms = (pollingMs && pollingMs > 0) ? pollingMs : 1000;
      const data = await callApi('start_polling', plcId, ms);
      if (!data.ok){
        showErr(data.error || '서버 폴링 시작 실패');
        return;
      }
      showOk(data.info || '서버 폴링 시작');
      setButtons(plcId, true);
      setPlcState(plcId, 'running', false, { status_reason: data.info || '' });
      setTimeout(function(){
        loadSnapshot();
      }, 300);
    } catch (e){
      showErr('통신 오류: ' + e.message);
    } finally {
      setActionBusy(plcId, false);
    }
  }

  async function stopPolling(plcId){
    setActionBusy(plcId, true);
    try {
      const data = await callApi('stop_polling', plcId);
      if (!data.ok){
        showErr(data.error || '서버 폴링 중지 실패');
        return;
      }
      showOk(data.info || '서버 폴링 중지');
      setButtons(plcId, false);
      setPlcState(plcId, 'stopped', false, { status_reason: data.info || '서버 폴링 중지' });
      setTimeout(function(){
        loadSnapshot();
      }, 300);
    } catch (e){
      showErr('통신 오류: ' + e.message);
    } finally {
      setActionBusy(plcId, false);
    }
  }

  function getPollIntervals(){
    const hidden = document.visibilityState === 'hidden';
    return {
      snapshotMs: hidden ? SNAPSHOT_MS_HIDDEN : SNAPSHOT_MS_ACTIVE
    };
  }

  function stopPollTimers(){
    if (snapshotTimer) {
      clearInterval(snapshotTimer);
      snapshotTimer = null;
    }
  }

  function startPollTimers(){
    stopPollTimers();
    const intervals = getPollIntervals();
    snapshotTimer = setInterval(loadSnapshot, intervals.snapshotMs);
  }

  function needsInitialAiRefresh(){
    const plcIds = Object.keys(serverStates);
    if (!plcIds.length) return false;
    return plcIds.some(function(plcId){
      const st = serverStates[plcId];
      if (!st || st.enabled === false) return false;
      if (st.running === false) return false;
      const diCount = toNum(st.di_read_count);
      const aiCount = toNum(st.ai_read_count);
      const rows = Array.isArray(st.rows) ? st.rows.length : 0;
      return diCount > 0 && aiCount === 0 && rows === 0;
    });
  }

  async function warmupInitialAiSnapshot(){
    for (let attempt = 0; attempt < INITIAL_AI_RETRY_MAX; attempt++) {
      if (!needsInitialAiRefresh()) return;
      await new Promise(function(resolve){
        setTimeout(resolve, INITIAL_AI_RETRY_DELAY_MS);
      });
      await loadSnapshot();
    }
  }

  document.querySelectorAll('.btn-read-once').forEach(function(btn){
    btn.addEventListener('click', function(){
      const plcId = btn.getAttribute('data-plc-id');
      readOnce(plcId);
    });
  });

  document.querySelectorAll('.btn-start').forEach(function(btn){
    btn.addEventListener('click', function(){
      const plcId = btn.getAttribute('data-plc-id');
      const ms = parseInt(btn.getAttribute('data-polling-ms') || '1000', 10);
      startPolling(plcId, ms);
    });
  });

  document.querySelectorAll('.btn-stop').forEach(function(btn){
    btn.addEventListener('click', function(){
      const plcId = btn.getAttribute('data-plc-id');
      stopPolling(plcId);
    });
  });

  panelFilter.addEventListener('change', function(){
    const selectedPanel = panelFilter.value;
    renderRows(mergedRows(selectedPanel));
    renderDiRows(mergedDiRows(selectedPanel));
  });

  document.addEventListener('visibilitychange', function(){
    startPollTimers();
    if (document.visibilityState === 'visible') {
      loadSnapshot();
    }
  });

  async function initPage(){
    await loadSnapshot();
    await warmupInitialAiSnapshot();
    startPollTimers();
  }

  initPage();
})();
</script>
<%
    }
%>
</body>
</html>
