<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../../includes/dbconn.jsp" %>
<%
    List<Map<String, Object>> plcList = new ArrayList<>();
    Map<Integer, String> meterNameMap = new HashMap<>();
    Map<Integer, String> meterPanelMap = new HashMap<>();

    try {
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
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%>
<html>
<head>
    <title>PLC Status</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1300px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-on { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-off { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; }
        th { font-size: 11px; }
        .ctrl-col { width: 280px; min-width: 280px; }
        .ctrl { display: inline-flex; gap: 6px; flex-wrap: wrap; white-space: normal; }
        .ctrl button { min-width: 52px; padding: 2px 6px; font-size: 11px; }
        .plc-table th, .plc-table td { padding: 6px 8px; }
        .plc-table th:nth-child(1), .plc-table td:nth-child(1) { width: 60px; }
        .plc-table th:nth-child(2), .plc-table td:nth-child(2) { width: 170px; }
        .plc-table td:nth-child(11), .plc-table td:nth-child(12) { white-space: nowrap; }
        .data-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; align-items: start; }
        @media (max-width: 1100px) {
            .data-grid { grid-template-columns: 1fr; }
        }
        .data-col h3 { margin: 0 0 8px 0; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>PLC 상태 / 수동 읽기</h2>
        <div style="display:flex; gap:8px;">
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="info-box">
        PLC 선택 없이 각 행에서 개별 제어합니다.<br/>
        시작: 서버 백그라운드에서 polling_ms 주기로 연속 읽기(화면 닫힘 후에도 지속), 중지: 해당 PLC 연속 읽기 중단
    </div>

    <div id="okBox" class="ok-box" style="display:none;"></div>
    <div id="errBox" class="err-box" style="display:none;"></div>

    <h3 style="margin-top:12px;">PLC 등록 상태</h3>
    <table class="plc-table">
        <thead>
        <tr>
            <th>plc_id</th>
            <th>ip</th>
            <th>port</th>
            <th>unit_id</th>
            <th>polling_ms</th>
            <th>enabled</th>
            <th class="ctrl-col">control</th>
            <th>state</th>
            <th>di_read_count</th>
            <th>ai_read_count</th>
            <th>di_read_ms</th>
            <th>ai_read_ms</th>
        </tr>
        </thead>
        <tbody>
        <% if (plcList.isEmpty()) { %>
        <tr><td colspan="12">등록된 PLC가 없습니다.</td></tr>
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
                    <% if (enabled) { %><span class="badge b-on">ACTIVE</span><% } else { %><span class="badge b-off">INACTIVE</span><% } %>
                </td>
                <td class="ctrl-col">
                    <div class="ctrl">
                        <button type="button" class="btn-read-once" data-plc-id="<%= p.get("plc_id") %>" <%= enabled ? "" : "disabled" %>>읽기 1회</button>
                        <button type="button" class="btn-start" data-plc-id="<%= p.get("plc_id") %>" data-polling-ms="<%= p.get("polling_ms") %>" <%= enabled ? "" : "disabled" %>>시작</button>
                        <button type="button" class="btn-stop" data-plc-id="<%= p.get("plc_id") %>" disabled>중지</button>
                    </div>
                </td>
                <td id="state-<%= p.get("plc_id") %>"><%= enabled ? "idle" : "inactive" %></td>
                <td id="dicount-<%= p.get("plc_id") %>">0</td>
                <td id="aicount-<%= p.get("plc_id") %>">0</td>
                <td id="dims-<%= p.get("plc_id") %>">-</td>
                <td id="aims-<%= p.get("plc_id") %>">-</td>
            </tr>
            <% } %>
        <% } %>
        </tbody>
    </table>

    <div style="display:flex; align-items:center; gap:8px; margin:6px 0 10px 0;">
        <label for="meterFilter">meter:</label>
        <select id="meterFilter">
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
  const rowsBody = document.getElementById('readRows');
  const okBox = document.getElementById('okBox');
  const errBox = document.getElementById('errBox');
  const meterFilter = document.getElementById('meterFilter');
  const diRowsBody = document.getElementById('diRows');
  const serverStates = {};
  const lastRowsByPlc = {};
  const lastDiRowsByPlc = {};
  const actionBusy = {};
  const STATUS_MS_ACTIVE = 5000;
  const SNAPSHOT_MS_ACTIVE = 15000;
  const STATUS_MS_HIDDEN = 30000;
  const SNAPSHOT_MS_HIDDEN = 60000;
  let statusTimer = null;
  let snapshotTimer = null;
  let statusSyncBusy = false;
  let snapshotSyncBusy = false;

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

  function esc(s){
    return String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
  }

  function fmt2(v){
    const n = Number(v);
    return Number.isFinite(n)
      ? n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      : String(v ?? '');
  }

  function mergedRows() {
    const plcIds = Object.keys(lastRowsByPlc).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    let idx = 1;
    const out = [];
    plcIds.forEach(function(plcId){
      (lastRowsByPlc[plcId] || []).forEach(function(r){
        out.push({
          idx: idx++,
          plc_id: plcId,
          meter_id: r.meter_id,
          panel_name: meterPanelMap[String(r.meter_id)] || '',
          token: r.token,
          reg1: r.reg1,
          reg2: r.reg2,
          value: r.value
        });
      });
    });
    return out;
  }

  function refreshMeterFilter(rows){
    const prev = meterFilter.value;
    const meterSet = new Set();
    (rows || []).forEach(function(r){
      meterSet.add(String(r.meter_id));
    });
    const meters = Array.from(meterSet).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    let html = '<option value="">전체</option>';
    meters.forEach(function(m){
      const meterName = meterNameMap[m];
      const panelName = meterPanelMap[m];
      const panelSuffix = panelName ? (' / ' + panelName) : '';
      const label = meterName ? (meterName + ' (#' + m + ')' + panelSuffix) : ('meter ' + m + panelSuffix);
      html += '<option value="' + m + '">' + esc(label) + '</option>';
    });
    meterFilter.innerHTML = html;
    meterFilter.value = meters.includes(prev) ? prev : '';
  }

  function renderRows(rows){
    const filterMeter = meterFilter.value;
    const viewRows = (rows || []).filter(function(r){
      if (!filterMeter) return true;
      return String(r.meter_id) === filterMeter;
    });

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

  function mergedDiRows() {
    const plcIds = Object.keys(lastDiRowsByPlc).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    let idx = 1;
    const out = [];
    plcIds.forEach(function(plcId){
      (lastDiRowsByPlc[plcId] || []).forEach(function(r){
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
    const filterMeter = meterFilter.value;
    const selectedPanel = filterMeter ? (meterPanelMap[filterMeter] || '') : '';
    const viewRows = (rows || []).filter(function(r){
      if (!filterMeter) return true;
      if (selectedPanel) return (r.panel_name || '') === selectedPanel;
      return false;
    });

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

  function setPlcState(plcId, text, isErr){
    const el = document.getElementById('state-' + plcId);
    if (!el) return;
    el.textContent = text;
    el.style.color = isErr ? '#b42318' : '#334155';
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
    const stop = document.querySelector('.btn-stop[data-plc-id="' + plcId + '"]');
    const busy = !!actionBusy[String(plcId)];
    if (start) start.disabled = busy || running;
    if (stop) stop.disabled = busy || !running;
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
    return await res.json();
  }

  async function refreshPollingStatus(){
    if (statusSyncBusy) return;
    statusSyncBusy = true;
    try {
      const res = await fetch(API + '?action=polling_status&_ts=' + Date.now(), { cache: 'no-store' });
      const data = await res.json();
      if (!data.ok) return;
      const states = data.states || [];
      states.forEach(function(st){
        const plcId = String(st.plc_id);
        serverStates[plcId] = st;
        const running = !!st.running;
        setButtons(plcId, running);
        setReadCounts(plcId, st.di_read_count, st.ai_read_count);
        setReadMs(plcId, st.last_read_ms, st.di_read_ms, st.ai_read_ms, st.proc_ms);
        if (running) {
          setPlcState(plcId, 'running', false);
        } else if (st.last_error) {
          setPlcState(plcId, 'error', true);
        } else {
          setPlcState(plcId, 'stopped', false);
        }
      });
    } catch (e) {
      // ignore status sync errors for UX continuity
    } finally {
      statusSyncBusy = false;
    }
  }

  async function loadSnapshot(){
    if (snapshotSyncBusy) return;
    snapshotSyncBusy = true;
    try {
      const res = await fetch(API + '?action=polling_snapshot&_ts=' + Date.now(), { cache: 'no-store' });
      const data = await res.json();
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
        setReadMs(plcId, st.last_read_ms, st.di_read_ms, st.ai_read_ms, st.proc_ms);
        if (st.running) {
          setPlcState(plcId, 'running', false);
        } else if (st.last_error) {
          setPlcState(plcId, 'error', true);
        } else {
          setPlcState(plcId, 'stopped', false);
        }
      });

      const rows = mergedRows();
      refreshMeterFilter(rows);
      renderRows(rows);
      renderDiRows(mergedDiRows());
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
      const rows = mergedRows();
      refreshMeterFilter(rows);
      renderRows(rows);
      renderDiRows(mergedDiRows());
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
      setPlcState(plcId, 'running', false);
      // 버튼 클릭 직후 대량 read 응답 파싱을 피하고, 주기 동기화에 맡긴다.
      setTimeout(function(){ refreshPollingStatus(); }, 300);
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
      setPlcState(plcId, 'stopped', false);
      setTimeout(function(){ refreshPollingStatus(); }, 300);
    } catch (e){
      showErr('통신 오류: ' + e.message);
    } finally {
      setActionBusy(plcId, false);
    }
  }

  function getPollIntervals(){
    const hidden = document.visibilityState === 'hidden';
    return {
      statusMs: hidden ? STATUS_MS_HIDDEN : STATUS_MS_ACTIVE,
      snapshotMs: hidden ? SNAPSHOT_MS_HIDDEN : SNAPSHOT_MS_ACTIVE
    };
  }

  function stopPollTimers(){
    if (statusTimer) {
      clearInterval(statusTimer);
      statusTimer = null;
    }
    if (snapshotTimer) {
      clearInterval(snapshotTimer);
      snapshotTimer = null;
    }
  }

  function startPollTimers(){
    stopPollTimers();
    const intervals = getPollIntervals();
    statusTimer = setInterval(refreshPollingStatus, intervals.statusMs);
    snapshotTimer = setInterval(loadSnapshot, intervals.snapshotMs);
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

  meterFilter.addEventListener('change', function(){
    renderRows(mergedRows());
    renderDiRows(mergedDiRows());
  });

  document.addEventListener('visibilitychange', function(){
    startPollTimers();
    if (document.visibilityState === 'visible') {
      refreshPollingStatus();
      loadSnapshot();
    }
  });

  async function initPage(){
    await loadSnapshot();
    await refreshPollingStatus();
    startPollTimers();
  }

  initPage();
})();
</script>
</body>
</html>
