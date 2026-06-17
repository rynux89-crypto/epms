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
        <nav class="nav" id="dashNav">
            <a class="dash-nav-link" href="ups_main.jsp" data-title="UPS 메인">▣ UPS 메인</a>
            <a class="dash-nav-link active" href="ups_dash.jsp<%= h(fragmentModel.selectedLinkQuery) %>" data-dashboard="true" data-title="UPS 통합 모니터링">▣ UPS 통합 모니터링</a>
            <a class="dash-nav-link" href="monitoring/ups_overview.jsp" data-title="UPS 전체 현황">▤ UPS 전체 현황</a>
            <a class="dash-nav-link" href="monitoring/ups_status.jsp" data-title="UPS 모니터링">⌁ UPS 모니터링</a>
            <a class="dash-nav-link" href="monitoring/phasor_diagram.jsp<%= h(fragmentModel.selectedLinkQuery) %>" data-title="UPS Phasor Diagram">◌ UPS Phasor Diagram</a>
            <a class="dash-nav-link" href="alarm/alarm_view.jsp?status=ACTIVE" data-title="UPS 알람">△ UPS 알람</a>
            <a class="dash-nav-link" href="alarm/event_view.jsp" data-title="UPS 이벤트">◇ UPS 이벤트</a>
            <a class="dash-nav-link" href="history/measurement_history.jsp" data-title="UPS 측정 이력">▦ UPS 측정 이력</a>
            <a class="dash-nav-link" href="report/ups_report.jsp" data-title="UPS 레포트">□ UPS 레포트</a>
            <a class="dash-nav-link" href="system/ups_register.jsp" data-title="UPS 등록">⚙ UPS 등록</a>
            <a class="dash-nav-link" href="system/setup.jsp" data-title="UPS 초기 설정">⚙ UPS 초기 설정</a>
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
            <h1 id="dashTitle">UPS 통합 모니터링</h1>
            <div class="meta">
                <span id="dashClock">◷ <%= new java.text.SimpleDateFormat("HH:mm:ss").format(new java.util.Date()) %></span>
                <span id="dashDate">▣ <%= new java.text.SimpleDateFormat("yyyy-MM-dd (E)", java.util.Locale.KOREAN).format(new java.util.Date()) %></span>
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
        <iframe id="dashContentFrame" class="dash-content-frame" title="UPS 화면" src="about:blank"></iframe>
        <%@ include file="includes/ups_footer.jspf" %>
    </main>
</div>
<script>
(function () {
    var root = document.getElementById('dashboardRefresh');
    var frame = document.getElementById('dashContentFrame');
    var title = document.getElementById('dashTitle');
    var navLinks = Array.prototype.slice.call(document.querySelectorAll('.dash-nav-link'));
    if (!root || !window.fetch) return;
    var busy = false;
    var lastOk = Date.now();
    var dashboardVisible = true;
    var clockEl = document.getElementById('dashClock');
    var dateEl = document.getElementById('dashDate');
    function pad2(value) {
        return String(value).padStart(2, '0');
    }
    function updateDashClock() {
        var now = new Date();
        if (clockEl) {
            clockEl.textContent = '◷ ' + pad2(now.getHours()) + ':' + pad2(now.getMinutes()) + ':' + pad2(now.getSeconds());
        }
        if (dateEl) {
            var days = ['일', '월', '화', '수', '목', '금', '토'];
            dateEl.textContent = '▣ ' + now.getFullYear() + '-' + pad2(now.getMonth() + 1) + '-' + pad2(now.getDate()) + ' (' + days[now.getDay()] + ')';
        }
    }
    function setActive(link) {
        navLinks.forEach(function (item) {
            item.classList.toggle('active', item === link);
        });
    }
    function sameDashboardTarget(link, href) {
        try {
            var linkUrl = new URL(link.getAttribute('href'), window.location.href);
            var targetUrl = new URL(href, window.location.href);
            return linkUrl.pathname === targetUrl.pathname && linkUrl.search === targetUrl.search;
        } catch (e) {
            return false;
        }
    }
    function setActiveByHref(href) {
        var matched = navLinks.find(function (link) {
            return sameDashboardTarget(link, href);
        });
        if (matched) setActive(matched);
        return matched;
    }
    function showDashboard(link) {
        dashboardVisible = true;
        root.classList.remove('hidden');
        if (frame) {
            frame.classList.remove('active');
            frame.setAttribute('src', 'about:blank');
        }
        if (title) title.textContent = (link && link.getAttribute('data-title')) || 'UPS 통합 모니터링';
        if (link) setActive(link);
    }
    function showFrame(link) {
        if (!frame || !link) return;
        dashboardVisible = false;
        root.classList.add('hidden');
        frame.classList.add('active');
        frame.setAttribute('src', embedUrl(link.getAttribute('href')));
        if (title) title.textContent = link.getAttribute('data-title') || link.textContent.replace(/^[^A-Za-z가-힣]+/, '').trim();
        setActive(link);
    }
    function embedUrl(href) {
        var url = new URL(href, window.location.href);
        url.searchParams.set('embed', '1');
        return url.pathname + url.search + url.hash;
    }
    function showFrameHref(href, frameTitle) {
        if (!frame || !href) return;
        var matched = setActiveByHref(href);
        dashboardVisible = false;
        root.classList.add('hidden');
        frame.classList.add('active');
        frame.setAttribute('src', embedUrl(href));
        if (title) title.textContent = frameTitle || (matched && matched.getAttribute('data-title')) || '';
    }
    navLinks.forEach(function (link) {
        link.addEventListener('click', function (event) {
            if (event.ctrlKey || event.metaKey || event.shiftKey || event.button !== 0) return;
            event.preventDefault();
            if (link.getAttribute('data-dashboard') === 'true') showDashboard(link);
            else showFrame(link);
        });
    });
    document.addEventListener('click', function (event) {
        if (event.ctrlKey || event.metaKey || event.shiftKey || event.button !== 0) return;
        var link = event.target.closest('a.kpi-link, a.row-link, a.dash-frame-link, .panel-head a, .meta .icon-btn');
        if (!link || link.classList.contains('dash-nav-link')) return;
        if (!root.contains(link) && !link.closest('.meta')) return;
        if (link.closest('.ups-picker')) return;
        event.preventDefault();
        showFrameHref(link.getAttribute('href'), link.getAttribute('title'));
    });
    function selectedUpsId() {
        var params = new URLSearchParams(window.location.search);
        return params.get('ups_id') || root.getAttribute('data-ups-id') || '';
    }
    function refreshDashboard() {
        if (!dashboardVisible || busy || document.hidden || document.querySelector('.ups-picker[open]')) return;
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
    updateDashClock();
    setInterval(updateDashClock, 1000);
    setInterval(refreshDashboard, 1000);
})();
</script>
</body>
</html>






