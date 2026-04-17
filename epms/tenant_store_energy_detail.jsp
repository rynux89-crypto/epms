<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="epms.remote.*" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%!
    private static Integer parsePositiveIntSafe(String value) {
        try {
            Integer parsed = Integer.valueOf(value);
            return parsed.intValue() > 0 ? parsed : null;
        } catch (Exception ignore) {
            return null;
        }
    }
%>
<%
request.setCharacterEncoding("UTF-8");

Integer storeId = parsePositiveIntSafe(request.getParameter("store_id"));
Integer meterId = parsePositiveIntSafe(request.getParameter("meter_id"));
if (storeId == null || meterId == null) {
%>
<!doctype html>
<html>
<head>
    <meta charset="UTF-8">
    <title>&#47588;&#51109;&#48324; &#51204;&#47141; &#49324;&#50857;&#47049; &#49345;&#49464;</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
</head>
<body>
<div class="err-box">store_id and meter_id are required.</div>
</body>
</html>
<%
    return;
}

RemoteReadingService remoteReadingService = new RemoteReadingService();
EnergyDetailPageData pageData = remoteReadingService.loadEnergyDetailPage(storeId.intValue(), meterId.intValue());
%>
<!doctype html>
<html>
<head>
    <meta charset="UTF-8">
    <title>&#47588;&#51109;&#48324; &#51204;&#47141; &#49324;&#50857;&#47049; &#49345;&#49464;</title>
    <script src="../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1440px;margin:0 auto;padding:10px 12px}
        .page-wrap{display:grid;gap:10px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:8px;margin-top:-2px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;padding:8px 14px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff}
        .hero{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;align-items:stretch}
        .hero-main{display:grid;gap:10px;align-content:start;min-height:100%;grid-template-rows:auto 1fr}
        .panel-box,.summary-card,.stat-card,.info-card{background:#fff;border:1px solid #d9dfe8;border-radius:8px;box-shadow:none}
        .summary-card{padding:12px}
        .summary-title{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
        .summary-title h1{margin:0;font-size:24px;line-height:1.1;color:#19324d}
        .store-badge{display:inline-flex;align-items:center;padding:4px 9px;border:1px solid #d9dfe8;border-radius:999px;background:#f5f7fa;color:#334155;font-size:11px;font-weight:700}
        .summary-meta{margin-top:6px;font-size:12px;color:#64748b}
        .summary-meter{margin-top:6px;font-size:12px;color:#334155;font-weight:700}
        .stats-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;align-content:start}
        .stat-card{padding:9px 10px}
        .stat-label{font-size:11px;color:#64748b;font-weight:700}
        .stat-value{margin-top:4px;font-size:20px;font-weight:900;color:#19324d}
        .stat-unit{font-size:12px;color:#64748b;margin-left:4px}
        .stat-sub{margin-top:4px;font-size:11px;color:#64748b}
        .info-card{padding:10px;height:100%}
        .info-card h3,.chart-panel h3{margin:0 0 8px;color:#1f3347;font-size:15px}
        .info-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
        .info-item{background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;padding:8px}
        .info-label{font-size:10px;color:#64748b;font-weight:700}
        .info-value{margin-top:4px;font-size:13px;font-weight:800;color:#243446}
        .chart-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
        .chart-panel{background:#fff;border:1px solid #d9dfe8;border-radius:8px;padding:10px}
        .chart-box{height:330px}
        .err-box{margin:0;padding:12px 14px;border-radius:8px;background:#fff1f1;border:1px solid #ffc9c9;color:#b42318;font-weight:700}
        @media (max-width:1280px){.stats-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
        @media (max-width:1080px){.hero,.chart-grid{grid-template-columns:1fr}}
        @media (max-width:760px){.page-head{flex-direction:column}.stats-grid,.info-grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>&#47588;&#51109;&#48324; &#51204;&#47141; &#49324;&#50857;&#47049; &#49345;&#49464;</h1>
            <p>&#47588;&#51109; &#50724;&#54532;&#51068;&#44284; &#44228;&#52769;&#44592; &#51201;&#50857;&#51068;&#51012; &#44592;&#51456;&#51004;&#47196; &#49324;&#50857;&#47049;&#51012; &#54869;&#51064;&#54633;&#45768;&#45796;.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="tenant_meter_store_tiles.jsp">&#44228;&#52769;&#44592;&#48324; &#50672;&#44208; &#47588;&#51109;</a>
            <a class="btn" href="tenant_billing_manage.jsp">&#50900; &#51221;&#49328;</a>
            <a class="btn" href="epms_main.jsp">EPMS &#54856;</a>
        </div>
    </div>

    <% if (pageData.getQueryError() != null && !pageData.getQueryError().trim().isEmpty()) { %>
    <div class="err-box">Query error: <%= h(pageData.getQueryError()) %></div>
    <% } %>

    <div class="hero">
        <div class="hero-main">
            <div class="summary-card">
                <div class="summary-title">
                    <h1><%= h(pageData.getStoreName()) %></h1>
                    <span class="store-badge"><%= h(pageData.getStoreCode()) %></span>
                </div>
                <div class="summary-meta"><%= h(pageData.getLocationText()) %> / <%= h(pageData.getCategoryName() == null || pageData.getCategoryName().trim().isEmpty() ? "-" : pageData.getCategoryName()) %></div>
                <div class="summary-meta">&#45812;&#45817;&#51088;: <%= h(pageData.getContactName() == null || pageData.getContactName().trim().isEmpty() ? "-" : pageData.getContactName()) %> / &#50672;&#46973;&#52376;: <%= h(pageData.getContactPhone() == null || pageData.getContactPhone().trim().isEmpty() ? "-" : pageData.getContactPhone()) %></div>
                <div class="summary-meter">&#50672;&#44208; &#44228;&#52769;&#44592; #<%= pageData.getMeterId() %> / <%= h(pageData.getMeterName()) %> / <%= h(pageData.getBuildingName() == null ? "-" : pageData.getBuildingName()) %> / <%= h(pageData.getPanelName() == null ? "-" : pageData.getPanelName()) %> / <%= h(pageData.getUsageType() == null ? "-" : pageData.getUsageType()) %></div>
            </div>

            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-label">&#54788;&#51116; &#49324;&#50857;&#47049;</div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.2f", pageData.getShownCurrentKw()) %><span class="stat-unit">kW</span></div>
                    <div class="stat-sub"><%= pageData.isUsingFallbackCurrent() ? "fallback valid reading" : h(pageData.getCurrentMeasuredAt() == null ? "-" : pageData.getCurrentMeasuredAt().toString()) %></div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">&#44552;&#51068; &#49324;&#50857;&#47049;</div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.1f", pageData.getTodayKwh()) %><span class="stat-unit">kWh</span></div>
                    <div class="stat-sub"><%= h(pageData.getTodayText()) %></div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">&#51060;&#48264;&#45804; &#49324;&#50857;&#47049;</div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.1f", pageData.getCurrentMonthKwh()) %><span class="stat-unit">kWh</span></div>
                    <div class="stat-sub"><%= h(pageData.getCurrentMonthText()) %></div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">&#51648;&#45212;&#45804; &#49324;&#50857;&#47049;</div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.1f", pageData.getPrevMonthKwh()) %><span class="stat-unit">kWh</span></div>
                    <div class="stat-sub"><%= h(pageData.getPrevMonthText()) %></div>
                </div>
            </div>
        </div>
        <div class="info-card">
            <h3>&#51221;&#49328; &#44592;&#51456; &#51221;&#48372;</h3>
            <div class="info-grid">
                <div class="info-item"><div class="info-label">&#50724;&#54532;&#51068;</div><div class="info-value"><%= h(pageData.getOpenedOn()) %></div></div>
                <div class="info-item"><div class="info-label">&#51333;&#47308;&#51068;</div><div class="info-value"><%= h(pageData.getClosedOn()) %></div></div>
                <div class="info-item"><div class="info-label">&#51201;&#50857; &#49884;&#51089;&#51068;</div><div class="info-value"><%= h(pageData.getValidFrom()) %></div></div>
                <div class="info-item"><div class="info-label">&#51201;&#50857; &#51333;&#47308;&#51068;</div><div class="info-value"><%= h(pageData.getValidTo()) %></div></div>
                <div class="info-item"><div class="info-label">&#49892;&#51228; &#44228;&#49328; &#49884;&#51089;&#51068;</div><div class="info-value"><%= h(pageData.getEffectiveStart()) %></div></div>
                <div class="info-item"><div class="info-label">&#49892;&#51228; &#44228;&#49328; &#51333;&#47308;&#51068;</div><div class="info-value"><%= h(pageData.getEffectiveEnd()) %></div></div>
                <div class="info-item"><div class="info-label">&#48176;&#48516; &#48708;&#50984;</div><div class="info-value"><%= pageData.getAllocationRatio() == null ? "-" : String.format(java.util.Locale.US, "%,.4f", pageData.getAllocationRatio().doubleValue()) %></div></div>
                <div class="info-item"><div class="info-label">&#51221;&#49328; &#48276;&#50948; / &#51452;&#44228;&#52769;&#44592;&#50668;&#48512;</div><div class="info-value"><%= h(pageData.getBillingScope() == null ? "-" : pageData.getBillingScope()) %> / <%= Boolean.TRUE.equals(pageData.getIsPrimary()) ? "Yes" : "No" %></div></div>
            </div>
        </div>
    </div>

    <div class="chart-grid">
        <div class="chart-panel">
            <h3>&#52572;&#44540; 31&#51068; &#51068;&#48324; &#49324;&#50857;&#47049;</h3>
            <div id="dailyChart" class="chart-box"></div>
        </div>
        <div class="chart-panel">
            <h3>&#52572;&#44540; 12&#44060;&#50900; &#50900;&#48324; &#49324;&#50857;&#47049;</h3>
            <div id="monthlyChart" class="chart-box"></div>
        </div>
    </div>
</div>
<footer>짤 EPMS Dashboard | SNUT CNT</footer>

<script>
const dailyLabels = [<%
    boolean first = true;
    for (String label : pageData.getDailyUsage().keySet()) {
        if (!first) out.print(",");
        out.print("\"" + escJson(label) + "\"");
        first = false;
    }
%>];
const dailyValues = [<%
    first = true;
    for (Double value : pageData.getDailyUsage().values()) {
        if (!first) out.print(",");
        out.print(String.format(java.util.Locale.US, "%.4f", value.doubleValue()));
        first = false;
    }
%>];
const monthlyLabels = [<%
    first = true;
    for (String label : pageData.getMonthlyUsage().keySet()) {
        if (!first) out.print(",");
        out.print("\"" + escJson(label) + "\"");
        first = false;
    }
%>];
const monthlyValues = [<%
    first = true;
    for (Double value : pageData.getMonthlyUsage().values()) {
        if (!first) out.print(",");
        out.print(String.format(java.util.Locale.US, "%.4f", value.doubleValue()));
        first = false;
    }
%>];

const dailyChart = echarts.init(document.getElementById('dailyChart'));
dailyChart.setOption({
  tooltip: { trigger: 'axis' },
  grid: { left: 46, right: 16, top: 28, bottom: 40 },
  xAxis: { type: 'category', data: dailyLabels, axisLabel: { rotate: 45 } },
  yAxis: { type: 'value', name: 'kWh' },
  series: [{ type: 'bar', data: dailyValues, itemStyle: { color: '#1f6feb' } }]
});

const monthlyChart = echarts.init(document.getElementById('monthlyChart'));
monthlyChart.setOption({
  tooltip: { trigger: 'axis' },
  grid: { left: 46, right: 16, top: 28, bottom: 40 },
  xAxis: { type: 'category', data: monthlyLabels, axisLabel: { rotate: 45 } },
  yAxis: { type: 'value', name: 'kWh' },
  series: [{ type: 'line', smooth: true, data: monthlyValues, itemStyle: { color: '#18a36b' }, areaStyle: { color: 'rgba(24,163,107,0.12)' } }]
});

window.addEventListener('resize', function () {
  dailyChart.resize();
  monthlyChart.resize();
});
</script>
</body>
</html>
