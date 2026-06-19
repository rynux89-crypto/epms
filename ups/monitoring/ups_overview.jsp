<%@ page import="java.util.*" %>
<%@ page import="epms.ups.UpsOverviewItem" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/ups_html.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
epms.ups.UpsOverviewPageModel overviewModel = epms.ups.UpsOverviewPageService.build("1".equals(request.getParameter("include_inactive")));
%><!doctype html>
<html lang="ko">
<head>
    <title>UPS 전체 현황</title>
    <%@ include file="../includes/ups_head_assets.jspf" %>
    <style>
        .overview-actions { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
        .refresh-state { color:#64748b; font-size:12px; min-width:98px; text-align:right; }
        .filter-bar { display:flex; justify-content:space-between; align-items:center; gap:10px; margin:0 0 12px; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:10px; }
        .filter-input-wrap { display:flex; align-items:center; gap:8px; flex:1; min-width:260px; }
        .filter-input-wrap label { color:#475569; font-size:13px; font-weight:800; white-space:nowrap; }
        .filter-input-wrap input { width:100%; max-width:420px; border:1px solid #cbd8e6; border-radius:6px; padding:9px 10px; font-size:14px; }
        .filter-count { color:#64748b; font-size:13px; white-space:nowrap; }
        .include-inactive { display:inline-flex; align-items:center; gap:6px; color:#475569; font-size:13px; font-weight:800; white-space:nowrap; }
        .include-inactive input { width:auto; }
        .clear-filter { border:1px solid #cbd8e6; border-radius:6px; background:#fff; color:#172033; padding:8px 11px; cursor:pointer; }
        .view-toggle { display:inline-flex; border:1px solid #cbd8e6; border-radius:6px; overflow:hidden; background:#fff; }
        .view-toggle button { border:0; border-right:1px solid #cbd8e6; background:#fff; color:#172033; padding:8px 12px; cursor:pointer; }
        .view-toggle button:last-child { border-right:0; }
        .view-toggle button.active { background:#1267b1; color:#fff; }
        .summary-grid { display:grid; grid-template-columns:repeat(5,minmax(110px,1fr)); gap:8px; margin:10px 0; }
        .summary-item { background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:9px 11px; }
        .summary-item span { display:block; color:#64748b; font-size:11px; margin-bottom:2px; }
        .summary-item strong { font-size:21px; color:#172033; }
        .tiles-wrap { display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); gap:10px; }
        .ups-board.tiles { display:block; }
        .ups-tile { display:block; color:#172033; text-decoration:none; background:#fff; border:1px solid #dbe5f2; border-left:6px solid #94a3b8; border-radius:8px; padding:10px 11px; min-height:154px; font-family:"Segoe UI","Noto Sans KR",Arial,sans-serif; }
        .ups-tile.normal { border-left-color:#16a34a; }
        .ups-tile.alarm { border-left-color:#f59e0b; }
        .ups-tile.comm { border-left-color:#dc2626; }
        .ups-tile.unknown { border-left-color:#64748b; }
        .ups-tile.disabled { border-left-color:#94a3b8; background:#fbfcfe; }
        .tile-head { display:flex; justify-content:space-between; gap:10px; align-items:flex-start; margin-bottom:6px; }
        .tile-name { font-size:17px; font-weight:800; line-height:1.18; letter-spacing:0; }
        .tile-meta { color:#64748b; font-size:12px; margin-top:2px; line-height:1.2; }
        .status-badge { display:inline-flex; align-items:center; min-width:60px; justify-content:center; border-radius:999px; padding:4px 8px; font-size:12px; font-weight:800; background:#eef2f7; color:#334155; white-space:nowrap; }
        .status-badge.normal { background:#dcfce7; color:#166534; }
        .status-badge.alarm { background:#fef3c7; color:#92400e; }
        .status-badge.comm { background:#fee2e2; color:#991b1b; }
        .status-badge.unknown { background:#e2e8f0; color:#334155; }
        .status-badge.disabled { background:#e5e7eb; color:#4b5563; }
        .tile-metrics { display:grid; grid-template-columns:1fr 1fr 1fr; gap:5px 8px; margin-top:6px; }
        .metric { border-top:1px solid #edf2f7; padding-top:4px; min-width:0; }
        .metric > span { display:block; color:#667085; font-size:12px; font-weight:700; margin-bottom:2px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .metric strong { display:flex; align-items:baseline; gap:3px; color:#172033; font-size:16px; font-weight:800; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .metric strong [data-field] { min-width:0; overflow:hidden; text-overflow:ellipsis; }
        .unit { display:inline-block !important; color:#64748b; font-size:.72em !important; font-weight:700; flex:0 0 auto; margin-left:0; }
        .overview-table .unit { vertical-align:baseline; margin-left:2px; }
        .tile-footer { display:flex; justify-content:space-between; gap:8px; color:#64748b; font-size:11px; margin-top:6px; padding-top:5px; border-top:1px solid #edf2f7; }
        .enabled-text { color:#1267b1; font-weight:800; }
        .ups-tile.disabled .enabled-text { color:#64748b; }
        .list-panel { display:none; background:#fff; border:1px solid #dbe5f2; border-radius:8px; overflow:auto; }
        .ups-board.list { display:block; }
        .ups-board.list .tiles-wrap { display:none; }
        .ups-board.list .list-panel { display:block; }
        .overview-table { width:100%; min-width:1200px; border-collapse:collapse; table-layout:fixed; }
        .overview-table th, .overview-table td { border-bottom:1px solid #edf2f7; padding:10px 11px; text-align:left; white-space:nowrap; }
        .overview-table th { background:#f8fafc; font-size:12px; color:#475569; }
        .overview-table td.num { text-align:right; }
        .overview-table .col-status { width:82px; }
        .overview-table .col-name { width:150px; }
        .overview-table .col-location { width:130px; }
        .overview-table .col-ip { width:150px; }
        .overview-table .col-measured { width:168px; }
        .overview-table .col-small { width:78px; }
        .overview-table .col-mode { width:92px; }
        .overview-table .col-remain { width:92px; }
        .overview-table .measured-cell { font-family:Consolas,"Segoe UI",monospace; letter-spacing:0; }
        .empty-box { background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:22px; color:#64748b; text-align:center; }
        .filter-empty { display:none; background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:22px; color:#64748b; text-align:center; }
        @media (max-width: 860px) {
            .summary-grid { grid-template-columns:repeat(2,minmax(120px,1fr)); }
            .filter-bar { display:block; }
            .filter-count { display:block; margin-top:8px; }
            .title-bar { display:block; }
            .overview-actions { margin-top:10px; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <div class="page-title"><h2>UPS 전체 현황</h2></div>
        <div class="inline-actions overview-actions">
            <span class="refresh-state" id="refreshState">1초 알람 갱신</span>
            <div class="view-toggle" aria-label="보기 방식">
                <button type="button" id="tileBtn" class="active">타일</button>
                <button type="button" id="listBtn">리스트</button>
            </div>
        </div>
    </div>

    <% if (overviewModel.err != null) { %><div class="err-box"><%= h(overviewModel.err) %></div><% } %>
    <div id="overviewContent">
    <div class="summary-grid">
        <div class="summary-item"><span><%= overviewModel.includeInactive ? "전체" : "활성" %></span><strong data-summary="total"><%= overviewModel.items.size() %></strong></div>
        <div class="summary-item"><span>정상</span><strong data-summary="normal"><%= overviewModel.normalCount %></strong></div>
        <div class="summary-item"><span>알람</span><strong data-summary="alarm"><%= overviewModel.alarmCount %></strong></div>
        <div class="summary-item"><span>통신불량</span><strong data-summary="comm"><%= overviewModel.commCount %></strong></div>
        <div class="summary-item"><span><%= overviewModel.includeInactive ? "비활성/미수집" : "미수집" %></span><strong data-summary="inactiveOrUnknown"><%= overviewModel.inactiveOrUnknownCount() %></strong></div>
    </div>

    <div class="filter-bar">
        <div class="filter-input-wrap">
            <label for="upsFilter">검색</label>
            <input id="upsFilter" type="search" autocomplete="off" placeholder="UPS 이름 또는 위치">
            <button class="clear-filter" id="clearFilter" type="button">전체</button>
            <label class="include-inactive"><input id="includeInactive" type="checkbox" <%= overviewModel.includeInactive ? "checked" : "" %>> 비활성 포함</label>
        </div>
        <div class="filter-count" id="filterCount">전체 <%= overviewModel.items.size() %>대</div>
    </div>

    <% if (overviewModel.items.isEmpty()) { %>
        <div class="empty-box">등록된 UPS가 없습니다.</div>
    <% } else { %>
    <div class="filter-empty" id="filterEmpty">검색 조건에 맞는 UPS가 없습니다.</div>
    <div id="upsBoard" class="ups-board tiles">
        <div class="tiles-wrap">
            <% for (UpsOverviewItem item : overviewModel.items) {
                String cls = item.statusClass;
                String detailUrl = item.detailUrl();
                String filterText = item.filterText();
            %>
            <a class="ups-tile <%= cls %>" href="<%= detailUrl %>" data-ups-id="<%= h(item.upsId) %>" data-filter="<%= h(filterText) %>">
                <div class="tile-head">
                    <div>
                        <div class="tile-name"><%= h(item.upsName) %></div>
                        <div class="tile-meta"><%= h(item.location) %><br><%= h(item.ipAddress) %>:<%= h(item.modbusPort) %> / Unit <%= h(item.unitId) %></div>
                    </div>
                    <span class="status-badge <%= cls %>" data-field="statusText"><%= h(item.statusText) %></span>
                </div>
                <div class="tile-metrics">
                    <div class="metric"><span>부하율</span><strong><span data-field="loadText"><%= h(item.loadText) %></span><small class="unit">%</small></strong></div>
                    <div class="metric"><span>배터리</span><strong><span data-field="batteryText"><%= h(item.batteryText) %></span><small class="unit">%</small></strong></div>
                    <div class="metric"><span>출력전압</span><strong><span data-field="outputVoltageText"><%= h(item.outputVoltageText) %></span><small class="unit">V</small></strong></div>
                    <div class="metric"><span>출력</span><strong><span data-field="outputKwText"><%= h(item.outputKwText) %></span><small class="unit">kW</small></strong></div>
                    <div class="metric"><span>출력 주파수</span><strong><span data-field="frequencyText"><%= h(item.frequencyText) %></span><small class="unit">Hz</small></strong></div>
                    <div class="metric"><span>운전모드</span><strong data-field="operationModeText"><%= h(item.operationModeText) %></strong></div>
                </div>
                <div class="tile-footer">
                    <span class="enabled-text" data-field="enabledText"><%= h(item.enabledText) %></span>
                    <span>알람 <span data-field="activeAlarmCount"><%= item.activeAlarmCount %></span></span>
                    <span data-field="measuredAtText"><%= h(item.measuredAtText) %></span>
                </div>
            </a>
            <% } %>
        </div>

        <div class="list-panel">
            <table class="overview-table">
                <colgroup>
                    <col class="col-status">
                    <col class="col-small">
                    <col class="col-name">
                    <col class="col-location">
                    <col class="col-ip">
                    <col class="col-measured">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-mode">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-remain">
                    <col class="col-small">
                </colgroup>
                <thead>
                    <tr>
                        <th>상태</th><th>활성</th><th>UPS</th><th>위치</th><th>IP</th><th>최근 수집</th>
                        <th>부하율</th><th>출력전압</th><th>출력 kW</th><th>출력 kVA</th><th>출력 주파수</th><th>운전모드</th><th>배터리</th><th>온도</th><th>잔여시간</th><th>알람</th>
                    </tr>
                </thead>
                <tbody>
                <% for (UpsOverviewItem item : overviewModel.items) {
                    String cls = item.statusClass;
                    String filterText = item.filterText();
                %>
                    <tr data-ups-id="<%= h(item.upsId) %>" data-filter="<%= h(filterText) %>" onclick="location.href='<%= h(item.detailUrl()) %>'" style="cursor:pointer;">
                        <td><span class="status-badge <%= cls %>" data-field="statusText"><%= h(item.statusText) %></span></td>
                        <td class="enabled-text" data-field="enabledText"><%= h(item.enabledText) %></td>
                        <td><%= h(item.upsName) %></td>
                        <td><%= h(item.location) %></td>
                        <td><%= h(item.ipAddress) %>:<%= h(item.modbusPort) %></td>
                        <td class="measured-cell" data-field="measuredAtText"><%= h(item.measuredAtText) %></td>
                        <td class="num"><span data-field="loadText"><%= h(item.loadText) %></span><small class="unit">%</small></td>
                        <td class="num"><span data-field="outputVoltageText"><%= h(item.outputVoltageText) %></span><small class="unit">V</small></td>
                        <td class="num"><span data-field="outputKwText"><%= h(item.outputKwText) %></span><small class="unit">kW</small></td>
                        <td class="num"><span data-field="outputKvaText"><%= h(item.outputKvaText) %></span><small class="unit">kVA</small></td>
                        <td class="num"><span data-field="frequencyText"><%= h(item.frequencyText) %></span><small class="unit">Hz</small></td>
                        <td data-field="operationModeText"><%= h(item.operationModeText) %></td>
                        <td class="num"><span data-field="batteryText"><%= h(item.batteryText) %></span><small class="unit">%</small></td>
                        <td class="num"><span data-field="batteryTempText"><%= h(item.batteryTempText) %></span><small class="unit">℃</small></td>
                        <td class="num"><span data-field="remainingText"><%= h(item.remainingText) %></span><small class="unit">Min</small></td>
                        <td class="num" data-field="activeAlarmCount"><%= item.activeAlarmCount %></td>
                    </tr>
                <% } %>
                </tbody>
            </table>
        </div>
    </div>
    <% } %>
    </div>
</div>
<script>
(function () {
    var refreshState = document.getElementById('refreshState');
    var content = document.getElementById('overviewContent');
    var busy = false;
    function setView(view) {
        var board = document.getElementById('upsBoard');
        var tileBtn = document.getElementById('tileBtn');
        var listBtn = document.getElementById('listBtn');
        if (!board || !tileBtn || !listBtn) return;
        board.className = 'ups-board ' + view;
        tileBtn.classList.toggle('active', view === 'tiles');
        listBtn.classList.toggle('active', view === 'list');
        try { localStorage.setItem('upsOverviewView', view); } catch (ignore) {}
    }
    function normalize(value) {
        return (value || '').toString().toLowerCase().replace(/\s+/g, ' ').trim();
    }
    function applyFilter() {
        var board = document.getElementById('upsBoard');
        var filterInput = document.getElementById('upsFilter');
        var filterCount = document.getElementById('filterCount');
        var filterEmpty = document.getElementById('filterEmpty');
        var query = normalize(filterInput ? filterInput.value : '');
        var tiles = Array.prototype.slice.call(document.querySelectorAll('.ups-tile'));
        var rows = Array.prototype.slice.call(document.querySelectorAll('.overview-table tbody tr'));
        var visible = 0;
        tiles.forEach(function (tile) {
            var matched = !query || normalize(tile.getAttribute('data-filter')).indexOf(query) >= 0;
            tile.style.display = matched ? '' : 'none';
            if (matched) visible += 1;
        });
        rows.forEach(function (row) {
            var matched = !query || normalize(row.getAttribute('data-filter')).indexOf(query) >= 0;
            row.style.display = matched ? '' : 'none';
        });
        if (filterCount) filterCount.textContent = (query ? '표시 ' + visible + '대 / 전체 ' + tiles.length + '대' : '전체 ' + tiles.length + '대');
        if (filterEmpty) filterEmpty.style.display = visible === 0 && tiles.length > 0 ? 'block' : 'none';
        if (board) board.style.display = visible === 0 && tiles.length > 0 ? 'none' : '';
        try { localStorage.setItem('upsOverviewFilter', filterInput ? filterInput.value : ''); } catch (ignore) {}
    }
    function updateUnits(root) {
        Array.prototype.slice.call((root || document).querySelectorAll('.unit')).forEach(function (unit) {
            var valueNode = unit.previousElementSibling;
            var value = valueNode ? valueNode.textContent.trim() : '';
            unit.style.display = (!value || value === '-' || value === '--') ? 'none' : '';
        });
    }
    function bindControls() {
        var board = document.getElementById('upsBoard');
        var tileBtn = document.getElementById('tileBtn');
        var listBtn = document.getElementById('listBtn');
        var filterInput = document.getElementById('upsFilter');
        var clearFilter = document.getElementById('clearFilter');
        var includeInactive = document.getElementById('includeInactive');
        if (tileBtn) tileBtn.onclick = function () { setView('tiles'); };
        if (listBtn) listBtn.onclick = function () { setView('list'); };
        var saved = 'tiles';
        try { saved = localStorage.getItem('upsOverviewView') || 'tiles'; } catch (ignore) {}
        if (board && tileBtn && listBtn) setView(saved === 'list' ? 'list' : 'tiles');
        if (filterInput) {
        try { filterInput.value = localStorage.getItem('upsOverviewFilter') || ''; } catch (ignore) {}
        filterInput.addEventListener('input', applyFilter);
        }
        if (clearFilter) {
            clearFilter.onclick = function () {
                if (filterInput) filterInput.value = '';
                applyFilter();
                if (filterInput) filterInput.focus();
            };
        }
        if (includeInactive) {
            includeInactive.onchange = function () {
                var url = new URL(window.location.href);
                if (includeInactive.checked) url.searchParams.set('include_inactive', '1');
                else url.searchParams.delete('include_inactive');
                window.location.href = url.toString();
            };
        }
        applyFilter();
        updateUnits(document);
    }
    function setText(root, field, value) {
        if (!root) return;
        var nodes = root.querySelectorAll('[data-field="' + field + '"]');
        nodes.forEach(function (node) {
            var next = value == null ? '' : String(value);
            if (node.textContent !== next) node.textContent = next;
        });
    }
    function setStatus(root, statusClass, statusText) {
        if (!root) return;
        root.classList.remove('normal', 'alarm', 'comm', 'unknown', 'disabled');
        root.classList.add(statusClass || 'unknown');
        var badge = root.querySelector('.status-badge');
        if (badge) {
            badge.classList.remove('normal', 'alarm', 'comm', 'unknown', 'disabled');
            badge.classList.add(statusClass || 'unknown');
            badge.textContent = statusText || '';
        }
    }
    function updateItem(item) {
        if (!item || !item.upsId) return;
        var roots = Array.prototype.slice.call(document.querySelectorAll('[data-ups-id="' + item.upsId + '"]'));
        roots.forEach(function (root) {
            var oldMeasuredAt = root.getAttribute('data-measured-at') || '';
            setStatus(root, item.statusClass, item.statusText);
            setText(root, 'activeAlarmCount', item.activeAlarmCount);
            setText(root, 'enabledText', item.enabledText);
            if (oldMeasuredAt !== item.measuredAtText) {
                setText(root, 'measuredAtText', item.measuredAtText);
                setText(root, 'loadText', item.loadText);
                setText(root, 'batteryText', item.batteryText);
                setText(root, 'outputVoltageText', item.outputVoltageText);
                setText(root, 'outputKwText', item.outputKwText);
                setText(root, 'outputKvaText', item.outputKvaText);
                setText(root, 'frequencyText', item.frequencyText);
                setText(root, 'operationModeText', item.operationModeText);
                setText(root, 'batteryTempText', item.batteryTempText);
                setText(root, 'remainingText', item.remainingText);
                root.setAttribute('data-measured-at', item.measuredAtText || '');
            }
            updateUnits(root);
        });
    }
    function updateSummary(summary) {
        if (!summary) return;
        Object.keys(summary).forEach(function (key) {
            var node = document.querySelector('[data-summary="' + key + '"]');
            if (node && typeof summary[key] !== 'boolean') node.textContent = summary[key];
        });
    }
    function refreshOverview() {
        if (!content || !window.fetch || busy || document.hidden) return;
        busy = true;
        var url = new URL('../api/overview_status.jsp', window.location.href);
        if (new URL(window.location.href).searchParams.get('include_inactive') === '1') url.searchParams.set('include_inactive', '1');
        fetch(url.toString(), {cache:'no-store', headers:{'X-Requested-With':'fetch'}})
            .then(function (response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.json();
            })
            .then(function (data) {
                if (!data || data.ok === false) throw new Error(data && data.error ? data.error : 'overview update failed');
                updateSummary(data.summary);
                (data.items || []).forEach(updateItem);
                applyFilter();
                if (refreshState) refreshState.textContent = '1초 알람 갱신';
            })
            .catch(function () {
                if (refreshState) refreshState.textContent = '갱신 실패';
            })
            .finally(function () {
                busy = false;
            });
    }
    bindControls();
    refreshOverview();
    setInterval(refreshOverview, 1000);
})();
</script>
</body>
</html>


