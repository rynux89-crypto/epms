<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="includes/ups_html.jspf" %>
<%
request.setCharacterEncoding("UTF-8");
epms.ups.UpsDashboardModel dashModel = epms.ups.UpsDashboardViewService.build(request.getParameter("ups_id"));
epms.ups.UpsDashboardFragmentRenderModel fragmentModel = new epms.ups.UpsDashboardFragmentRenderModel(dashModel);
long dashCssVersion = new java.io.File(application.getRealPath("/css/ups_dash.css")).lastModified();
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>UPS 통합 모니터링</title>
    <%@ include file="includes/ups_head_assets.jspf" %>
    <link rel="stylesheet" type="text/css" href="<%= upsAssetBase %>/css/ups_dash.css?v=<%= dashCssVersion %>">
</head>
<body>
<div class="ups-dashboard">
    <aside class="side">
        <div class="brand">
            <div class="brand-mark">⚡</div>
            <div><strong>UPS WATCH</strong><span>통합 모니터링 시스템</span></div>
        </div>
        <nav class="nav">
            <a class="active" href="ups_main.jsp">▣ 대시보드</a>
            <a href="monitoring/ups_overview.jsp">▤ 장비 현황</a>
            <a href="monitoring/ups_status.jsp">⌁ 실시간 상태</a>
            <a href="monitoring/phasor_diagram.jsp<%= h(fragmentModel.selectedLinkQuery) %>">◌ 페이저 다이어그램</a>
            <a href="alarm/alarm_view.jsp?status=ACTIVE">△ 경고 알림</a>
            <a href="alarm/event_view.jsp">◇ 이벤트</a>
            <a href="history/measurement_history.jsp">▦ 이력 관리</a>
            <a href="report/ups_report.jsp">□ 보고서</a>
            <a href="system/ups_register.jsp">⚙ 설정 관리</a>
            <a href="system/setup.jsp">⚙ 시스템 관리</a>
        </nav>
        <div class="side-status">
            <small>시스템 상태</small>
            <strong><%= dashModel.err == null ? "정상 운영 중" : "확인 필요" %></strong>
            <small>마지막 업데이트</small>
            <div><%= new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new java.util.Date()) %></div>
        </div>
        <div class="user"><div class="avatar"></div><div><strong>관리자</strong><br><span class="muted">admin</span></div></div>
    </aside>

    <main class="main">
        <div class="topbar">
            <h1>UPS 통합 모니터링</h1>
            <div class="meta">
                <span>◷ <%= new java.text.SimpleDateFormat("HH:mm:ss").format(new java.util.Date()) %></span>
                <span>▣ <%= new java.text.SimpleDateFormat("yyyy-MM-dd (E)", java.util.Locale.KOREAN).format(new java.util.Date()) %></span>
                <a class="icon-btn" href="alarm/alarm_view.jsp?status=ACTIVE">!</a>
                <a class="icon-btn" href="monitoring/ups_overview.jsp">↗</a>
            </div>
        </div>

        <section id="dashboardRefresh" data-ups-id="<%= h(fragmentModel.selectedUpsId) %>">
            <% if (dashModel.err != null) { %><div class="err-box"><%= h(dashModel.err) %></div><% } %>

            <%@ include file="includes/dashboard/kpi_cards.jspf" %>

            <%@ include file="includes/dashboard/main_cards.jspf" %>

            <%@ include file="includes/dashboard/bottom_cards.jspf" %>
        </section>
    </main>
</div>
<%@ include file="includes/ups_footer.jspf" %>
<script>
(function () {
    var root = document.getElementById('dashboardRefresh');
    if (!root || !window.fetch) return;
    var busy = false;
    var lastOk = Date.now();
    function selectedUpsId() {
        var params = new URLSearchParams(window.location.search);
        return params.get('ups_id') || root.getAttribute('data-ups-id') || '';
    }
    function refreshDashboard() {
        if (busy || document.hidden || document.querySelector('.ups-picker[open]')) return;
        busy = true;
        var url = 'api/dashboard_fragment.jsp';
        var upsId = selectedUpsId();
        if (upsId) url += '?ups_id=' + encodeURIComponent(upsId);
        fetch(url, {cache:'no-store', headers:{'X-Requested-With':'fetch'}})
            .then(function (response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.text();
            })
            .then(function (html) {
                if (html && html.indexOf('UPS 통합 모니터링') < 0) {
                    root.innerHTML = html;
                    lastOk = Date.now();
                }
            })
            .catch(function () {
                if (Date.now() - lastOk > 30000) window.location.reload();
            })
            .finally(function () {
                busy = false;
            });
    }
    setInterval(refreshDashboard, 1000);
})();
</script>
</body>
</html>






