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
        .summary-grid { display:grid; grid-template-columns:repeat(5,minmax(120px,1fr)); gap:10px; margin:14px 0; }
        .summary-item { background:#fff; border:1px solid #dbe5f2; border-radius:8px; padding:12px; }
        .summary-item span { display:block; color:#64748b; font-size:12px; margin-bottom:4px; }
        .summary-item strong { font-size:24px; color:#172033; }
        .tiles-wrap { display:grid; grid-template-columns:repeat(auto-fill,minmax(245px,1fr)); gap:12px; }
        .ups-board.tiles { display:block; }
        .ups-tile { display:block; color:#172033; text-decoration:none; background:#fff; border:1px solid #dbe5f2; border-left:7px solid #94a3b8; border-radius:8px; padding:13px; min-height:188px; }
        .ups-tile.normal { border-left-color:#16a34a; }
        .ups-tile.alarm { border-left-color:#f59e0b; }
        .ups-tile.comm { border-left-color:#dc2626; }
        .ups-tile.unknown { border-left-color:#64748b; }
        .ups-tile.disabled { border-left-color:#94a3b8; opacity:.72; }
        .tile-head { display:flex; justify-content:space-between; gap:10px; align-items:flex-start; margin-bottom:10px; }
        .tile-name { font-size:17px; font-weight:800; line-height:1.25; }
        .tile-meta { color:#64748b; font-size:12px; margin-top:3px; line-height:1.35; }
        .status-badge { display:inline-flex; align-items:center; min-width:62px; justify-content:center; border-radius:999px; padding:4px 8px; font-size:12px; font-weight:800; background:#eef2f7; color:#334155; white-space:nowrap; }
        .status-badge.normal { background:#dcfce7; color:#166534; }
        .status-badge.alarm { background:#fef3c7; color:#92400e; }
        .status-badge.comm { background:#fee2e2; color:#991b1b; }
        .status-badge.unknown { background:#e2e8f0; color:#334155; }
        .status-badge.disabled { background:#e5e7eb; color:#4b5563; }
        .tile-metrics { display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:10px; }
        .metric { border-top:1px solid #edf2f7; padding-top:7px; }
        .metric span { display:block; color:#64748b; font-size:12px; margin-bottom:2px; }
        .metric strong { font-size:18px; font-weight:400; }
        .tile-footer { display:flex; justify-content:space-between; gap:8px; color:#64748b; font-size:12px; margin-top:10px; padding-top:9px; border-top:1px solid #edf2f7; }
        .list-panel { display:none; background:#fff; border:1px solid #dbe5f2; border-radius:8px; overflow:auto; }
        .ups-board.list { display:block; }
        .ups-board.list .tiles-wrap { display:none; }
        .ups-board.list .list-panel { display:block; }
        .overview-table { width:100%; min-width:1120px; border-collapse:collapse; table-layout:fixed; }
        .overview-table th, .overview-table td { border-bottom:1px solid #edf2f7; padding:10px 11px; text-align:left; white-space:nowrap; }
        .overview-table th { background:#f8fafc; font-size:12px; color:#475569; }
        .overview-table td.num { text-align:right; }
        .overview-table .col-status { width:82px; }
        .overview-table .col-name { width:150px; }
        .overview-table .col-location { width:130px; }
        .overview-table .col-ip { width:150px; }
        .overview-table .col-measured { width:168px; }
        .overview-table .col-small { width:78px; }
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
        <div>
            <h2>UPS 전체 현황</h2>
            <p class="muted">등록된 UPS의 최신 수집 상태를 타일 또는 리스트로 확인합니다.</p>
        </div>
        <div class="inline-actions overview-actions">
            <span class="refresh-state" id="refreshState">5초 후 갱신</span>
            <div class="view-toggle" aria-label="보기 방식">
                <button type="button" id="tileBtn" class="active">타일</button>
                <button type="button" id="listBtn">리스트</button>
            </div>
        </div>
    </div>

    <% if (overviewModel.err != null) { %><div class="err-box"><%= h(overviewModel.err) %></div><% } %>

    <div class="summary-grid">
        <div class="summary-item"><span><%= overviewModel.includeInactive ? "전체" : "활성" %></span><strong><%= overviewModel.items.size() %></strong></div>
        <div class="summary-item"><span>정상</span><strong><%= overviewModel.normalCount %></strong></div>
        <div class="summary-item"><span>알람</span><strong><%= overviewModel.alarmCount %></strong></div>
        <div class="summary-item"><span>통신불량</span><strong><%= overviewModel.commCount %></strong></div>
        <div class="summary-item"><span><%= overviewModel.includeInactive ? "비활성/미수집" : "미수집" %></span><strong><%= overviewModel.inactiveOrUnknownCount() %></strong></div>
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
            <a class="ups-tile <%= cls %>" href="<%= detailUrl %>" data-filter="<%= h(filterText) %>">
                <div class="tile-head">
                    <div>
                        <div class="tile-name"><%= h(item.upsName) %></div>
                        <div class="tile-meta"><%= h(item.location) %><br><%= h(item.ipAddress) %>:<%= h(item.modbusPort) %> / Unit <%= h(item.unitId) %></div>
                    </div>
                    <span class="status-badge <%= cls %>"><%= h(item.statusText) %></span>
                </div>
                <div class="tile-metrics">
                    <div class="metric"><span>부하율</span><strong><%= h(item.loadText) %></strong></div>
                    <div class="metric"><span>배터리</span><strong><%= h(item.batteryText) %></strong></div>
                    <div class="metric"><span>출력</span><strong><%= h(item.outputKwText) %> kW</strong></div>
                    <div class="metric"><span>주파수</span><strong><%= h(item.frequencyText) %> Hz</strong></div>
                </div>
                <div class="tile-footer">
                    <span>알람 <%= item.activeAlarmCount %></span>
                    <span><%= h(item.measuredAtText) %></span>
                </div>
            </a>
            <% } %>
        </div>

        <div class="list-panel">
            <table class="overview-table">
                <colgroup>
                    <col class="col-status">
                    <col class="col-name">
                    <col class="col-location">
                    <col class="col-ip">
                    <col class="col-measured">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-small">
                    <col class="col-remain">
                    <col class="col-small">
                </colgroup>
                <thead>
                    <tr>
                        <th>상태</th><th>UPS</th><th>위치</th><th>IP</th><th>최근 수집</th>
                        <th>부하율</th><th>출력 kW</th><th>출력 kVA</th><th>주파수</th><th>배터리</th><th>온도</th><th>잔여시간</th><th>알람</th>
                    </tr>
                </thead>
                <tbody>
                <% for (UpsOverviewItem item : overviewModel.items) {
                    String cls = item.statusClass;
                    String filterText = item.filterText();
                %>
                    <tr data-filter="<%= h(filterText) %>" onclick="location.href='<%= h(item.detailUrl()) %>'" style="cursor:pointer;">
                        <td><span class="status-badge <%= cls %>"><%= h(item.statusText) %></span></td>
                        <td><%= h(item.upsName) %></td>
                        <td><%= h(item.location) %></td>
                        <td><%= h(item.ipAddress) %>:<%= h(item.modbusPort) %></td>
                        <td class="measured-cell"><%= h(item.measuredAtText) %></td>
                        <td class="num"><%= h(item.loadText) %></td>
                        <td class="num"><%= h(item.outputKwText) %></td>
                        <td class="num"><%= h(item.outputKvaText) %></td>
                        <td class="num"><%= h(item.frequencyText) %></td>
                        <td class="num"><%= h(item.batteryText) %></td>
                        <td class="num"><%= h(item.batteryTempText) %></td>
                        <td class="num"><%= h(item.remainingText) %></td>
                        <td class="num"><%= item.activeAlarmCount %></td>
                    </tr>
                <% } %>
                </tbody>
            </table>
        </div>
    </div>
    <% } %>
</div>
<script>
(function () {
    var board = document.getElementById('upsBoard');
    var tileBtn = document.getElementById('tileBtn');
    var listBtn = document.getElementById('listBtn');
    var refreshState = document.getElementById('refreshState');
    var filterInput = document.getElementById('upsFilter');
    var clearFilter = document.getElementById('clearFilter');
    var filterCount = document.getElementById('filterCount');
    var filterEmpty = document.getElementById('filterEmpty');
    var includeInactive = document.getElementById('includeInactive');
    if (!board || !tileBtn || !listBtn) return;
    function setView(view) {
        board.className = 'ups-board ' + view;
        tileBtn.classList.toggle('active', view === 'tiles');
        listBtn.classList.toggle('active', view === 'list');
        try { localStorage.setItem('upsOverviewView', view); } catch (ignore) {}
    }
    tileBtn.onclick = function () { setView('tiles'); };
    listBtn.onclick = function () { setView('list'); };
    var saved = 'tiles';
    try { saved = localStorage.getItem('upsOverviewView') || 'tiles'; } catch (ignore) {}
    setView(saved === 'list' ? 'list' : 'tiles');
    function normalize(value) {
        return (value || '').toString().toLowerCase().replace(/\s+/g, ' ').trim();
    }
    function applyFilter() {
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
    var remain = 5;
    function tick() {
        if (refreshState) refreshState.textContent = remain + '초 후 갱신';
        if (remain <= 0) {
            window.location.reload();
            return;
        }
        remain -= 1;
    }
    tick();
    setInterval(tick, 1000);
})();
</script>
</body>
</html>


