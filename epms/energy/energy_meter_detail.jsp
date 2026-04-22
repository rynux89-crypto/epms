<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../../includes/dbconfig.jspf" %>
<%@ include file="../../includes/epms_html.jspf" %>
<%@ include file="../../includes/epms_json.jspf" %>
<%
try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    Integer meterId = null;
    try {
        String meterParam = request.getParameter("meter_id");
        if (meterParam != null && !meterParam.trim().isEmpty()) meterId = Integer.valueOf(meterParam.trim());
    } catch (Exception ignore) {}

    if (meterId == null) {
%>
<!doctype html>
<html>
<head>
    <title>媛쒕퀎 ?ъ슜??愿由?/title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
</head>
<body>
<div class="err-box">meter_id 媛 ?꾩슂?⑸땲??</div>
</body>
</html>
<%
        return;
    }

    String meterName = null;
    String panelName = null;
    String buildingName = null;
    String usageType = null;
    Double ratedVoltage = null;
    Double ratedCurrent = null;
    String queryError = null;

    LocalDate today = LocalDate.now();
    LocalDate dailyStart = today.minusDays(30);
    YearMonth currentYm = YearMonth.from(today);
    YearMonth prevYm = currentYm.minusMonths(1);
    LocalDate prevMonthStart = prevYm.atDay(1);
    LocalDate prevMonthEnd = prevYm.atEndOfMonth();
    LocalDate currentMonthStart = currentYm.atDay(1);
    LocalDate monthSeriesStart = currentYm.minusMonths(11).atDay(1);

    Double currentKw = null;
    Timestamp currentMeasuredAt = null;
    Double currentValidKw = null;
    Timestamp currentValidMeasuredAt = null;
    Double currentPf = null;
    Double currentEnergyTotal = null;
    double todayKwh = 0.0;
    double currentMonthKwh = 0.0;
    double prevMonthKwh = 0.0;
    double avgDailyKwh = 0.0;
    double peakKw = 0.0;

    LinkedHashMap<LocalDate, Double> dailyUsage = new LinkedHashMap<LocalDate, Double>();
    LinkedHashMap<String, Double> monthlyUsage = new LinkedHashMap<String, Double>();

    for (LocalDate d = dailyStart; !d.isAfter(today); d = d.plusDays(1)) dailyUsage.put(d, 0.0d);
    for (YearMonth ym = currentYm.minusMonths(11); !ym.isAfter(currentYm); ym = ym.plusMonths(1)) monthlyUsage.put(ym.toString(), 0.0d);

    try {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT meter_id, name, panel_name, building_name, usage_type, rated_voltage, rated_current " +
                "FROM dbo.meters WHERE meter_id = ?")) {
            ps.setInt(1, meterId.intValue());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    meterName = rs.getString("name");
                    panelName = rs.getString("panel_name");
                    buildingName = rs.getString("building_name");
                    usageType = rs.getString("usage_type");
                    ratedVoltage = (Double) rs.getObject("rated_voltage");
                    ratedCurrent = (Double) rs.getObject("rated_current");
                }
            }
        }

        if (meterName == null || meterName.trim().isEmpty()) meterName = "Meter " + meterId;

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 measured_at, CAST(active_power_total AS float) AS active_kw, CAST(power_factor AS float) AS pf, CAST(energy_consumed_total AS float) AS energy_total " +
                "FROM dbo.measurements WHERE meter_id = ? ORDER BY measured_at DESC")) {
            ps.setInt(1, meterId.intValue());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    currentMeasuredAt = rs.getTimestamp("measured_at");
                    currentKw = (Double) rs.getObject("active_kw");
                    currentPf = (Double) rs.getObject("pf");
                    currentEnergyTotal = (Double) rs.getObject("energy_total");
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 measured_at, CAST(active_power_total AS float) AS active_kw " +
                "FROM dbo.measurements WHERE meter_id = ? AND active_power_total IS NOT NULL AND ABS(CAST(active_power_total AS float)) > 0.0001 ORDER BY measured_at DESC")) {
            ps.setInt(1, meterId.intValue());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    currentValidMeasuredAt = rs.getTimestamp("measured_at");
                    currentValidKw = (Double) rs.getObject("active_kw");
                }
            }
        }

        String diffSql =
            "WITH day_last AS ( " +
            "    SELECT CAST(measured_at AS date) AS d, CAST(energy_consumed_total AS float) AS energy_total, " +
            "           ROW_NUMBER() OVER (PARTITION BY CAST(measured_at AS date) ORDER BY measured_at DESC) AS rn " +
            "    FROM dbo.measurements " +
            "    WHERE meter_id = ? " +
            "      AND energy_consumed_total IS NOT NULL " +
            "      AND measured_at >= DATEADD(day, -1, ?) " +
            "      AND measured_at < DATEADD(day, 1, ?) " +
            "), day_meter AS ( " +
            "    SELECT d, energy_total AS end_total FROM day_last WHERE rn = 1 " +
            "), day_diff AS ( " +
            "    SELECT d, end_total - LAG(end_total) OVER (ORDER BY d) AS day_kwh " +
            "    FROM day_meter " +
            ") " +
            "SELECT d, day_kwh FROM day_diff WHERE d BETWEEN ? AND ? ORDER BY d";

        try (PreparedStatement ps = conn.prepareStatement(diffSql)) {
            ps.setInt(1, meterId.intValue());
            ps.setDate(2, java.sql.Date.valueOf(monthSeriesStart));
            ps.setDate(3, java.sql.Date.valueOf(today));
            ps.setDate(4, java.sql.Date.valueOf(monthSeriesStart));
            ps.setDate(5, java.sql.Date.valueOf(today));

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    java.sql.Date dObj = rs.getDate("d");
                    if (dObj == null) continue;
                    LocalDate d = dObj.toLocalDate();
                    Double raw = (Double) rs.getObject("day_kwh");
                    double safe = raw != null && raw.doubleValue() >= 0.0 ? raw.doubleValue() : 0.0;

                    if (dailyUsage.containsKey(d)) dailyUsage.put(d, safe);
                    String ymKey = String.format(java.util.Locale.ROOT, "%04d-%02d", d.getYear(), d.getMonthValue());
                    if (monthlyUsage.containsKey(ymKey)) monthlyUsage.put(ymKey, monthlyUsage.get(ymKey) + safe);

                    if (d.equals(today)) todayKwh += safe;
                    if (!d.isBefore(currentMonthStart)) currentMonthKwh += safe;
                    if (!d.isBefore(prevMonthStart) && !d.isAfter(prevMonthEnd)) prevMonthKwh += safe;
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT MAX(CAST(active_power_total AS float)) AS peak_kw " +
                "FROM dbo.measurements WHERE meter_id = ? AND measured_at >= ? AND measured_at < DATEADD(day,1,?)")) {
            ps.setInt(1, meterId.intValue());
            ps.setDate(2, java.sql.Date.valueOf(dailyStart));
            ps.setDate(3, java.sql.Date.valueOf(today));
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) peakKw = rs.getDouble("peak_kw");
            }
        }

        double total = 0.0;
        int count = 0;
        for (Double v : dailyUsage.values()) {
            total += v.doubleValue();
            if (v.doubleValue() > 0.0) count++;
        }
        avgDailyKwh = count > 0 ? total / count : 0.0;
    } catch (Exception e) {
        queryError = e.getMessage();
    }
    double shownCurrentKw = 0.0d;
    boolean usingFallbackCurrent = false;
    if (currentKw != null && Math.abs(currentKw.doubleValue()) > 0.0001d) {
        shownCurrentKw = currentKw.doubleValue();
    } else if (currentValidKw != null) {
        shownCurrentKw = currentValidKw.doubleValue();
        usingFallbackCurrent = true;
    }
%>
<!doctype html>
<html>
<head>
    <title>媛쒕퀎 ?ъ슜??愿由?/title>
    <script src="../../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap{max-width:1240px;margin:0 auto}
        .hero{display:grid;grid-template-columns:1.2fr .8fr;gap:12px;margin:10px 0 12px}
        .hero-card,.meta-card,.panel{background:#fff;border:1px solid #dbe5f2;border-radius:12px;padding:12px;box-shadow:none}
        .hero-title{font-size:24px;font-weight:900;line-height:1.2;color:#17283a}
        .hero-meta{margin-top:8px;font-size:13px;color:#64748b}
        .hero-stats{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-top:12px}
        .stat{background:linear-gradient(180deg,#fffdf7 0%,#fff6e7 100%);border:1px solid #efd8aa;border-radius:10px;padding:10px}
        .stat-label{font-size:11px;color:#8a6a20;text-transform:uppercase;letter-spacing:.05em}
        .stat-value{margin-top:6px;font-size:20px;font-weight:900;color:#1f2d3d}
        .stat-value.is-muted{color:#94a3b8}
        .stat-sub{margin-top:4px;font-size:12px;color:#64748b}
        .meta-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
        .meta-item{background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:9px}
        .meta-label{font-size:11px;color:#64748b;text-transform:uppercase}
        .meta-value{margin-top:5px;font-size:14px;font-weight:800;color:#243446}
        .chart-grid{display:grid;grid-template-columns:1.5fr 1fr;gap:12px}
        .chart-box{height:320px}
        .panel h3{margin:0 0 10px;color:#1f3347}
        .data-table{font-size:12px}
        .data-table th{background:#f4f7fb}
        .data-table td,.data-table th{padding:6px 8px}
        .err-box{margin:12px 0;padding:12px 14px;border-radius:12px;background:#fff1f1;border:1px solid #ffc9c9;color:#b42318;font-weight:700}
        @media (max-width:1100px){.hero,.chart-grid{grid-template-columns:1fr}.hero-stats,.meta-grid{grid-template-columns:1fr 1fr}}
        @media (max-width:720px){.hero-stats,.meta-grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>媛쒕퀎 ?ъ슜??愿由?/h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/energy/energy_meter_overview.jsp'">?먮꼫吏 愿由?/button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS ??/button>
        </div>
    </div>

    <% if (queryError != null && !queryError.trim().isEmpty()) { %>
    <div class="err-box">議고쉶 ?ㅻ쪟: <%= h(queryError) %></div>
    <% } %>

    <div class="hero">
        <div class="hero-card">
            <div class="hero-title"><%= h(meterName) %></div>
            <div class="hero-meta">
                meter_id #<%= meterId %> /
                <%= h(String.valueOf(buildingName == null ? "-" : buildingName)) %> /
                <%= h(String.valueOf(panelName == null ? "-" : panelName)) %> /
                <%= h(String.valueOf(usageType == null ? "-" : usageType)) %>
            </div>
            <div class="hero-stats">
                <div class="stat">
                    <div class="stat-label">?꾩옱 ?ъ슜??/div>
                    <div class="stat-value <%= shownCurrentKw <= 0.0001d ? "is-muted" : "" %>"><%= String.format(java.util.Locale.US, "%,.2f", shownCurrentKw) %> <span style="font-size:12px;">kW</span></div>
                    <div class="stat-sub"><%= usingFallbackCurrent ? ("理쒓렐 ?좏슚媛?湲곗?: " + h(String.valueOf(currentValidMeasuredAt))) : (currentMeasuredAt == null ? "理쒓렐 痢≪젙媛??놁쓬" : h(String.valueOf(currentMeasuredAt))) %></div>
                </div>
                <div class="stat">
                    <div class="stat-label">吏?쒕떖 ?ъ슜??/div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.1f", prevMonthKwh) %> <span style="font-size:12px;">kWh</span></div>
                    <div class="stat-sub"><%= prevYm.toString() %> ?꾩쟻</div>
                </div>
                <div class="stat">
                    <div class="stat-label">?대쾲???꾩쟻</div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.1f", currentMonthKwh) %> <span style="font-size:12px;">kWh</span></div>
                    <div class="stat-sub"><%= currentYm.toString() %> ?꾩쟻</div>
                </div>
                <div class="stat">
                    <div class="stat-label">湲덉씪 ?ъ슜??/div>
                    <div class="stat-value"><%= String.format(java.util.Locale.US, "%,.1f", todayKwh) %> <span style="font-size:12px;">kWh</span></div>
                    <div class="stat-sub"><%= today.toString() %> 湲곗?</div>
                </div>
            </div>
        </div>

        <div class="meta-card">
            <h3>怨꾩륫湲??뺣낫</h3>
            <div class="meta-grid">
                <div class="meta-item">
                    <div class="meta-label">嫄대Ъ</div>
                    <div class="meta-value"><%= h(String.valueOf(buildingName == null ? "-" : buildingName)) %></div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">?⑤꼸</div>
                    <div class="meta-value"><%= h(String.valueOf(panelName == null ? "-" : panelName)) %></div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">?⑸룄</div>
                    <div class="meta-value"><%= h(String.valueOf(usageType == null ? "-" : usageType)) %></div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">?꾩옱 ??쪧</div>
                    <div class="meta-value"><%= String.format(java.util.Locale.US, "%,.3f", currentPf == null ? 0.0 : currentPf.doubleValue()) %></div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">?뺢꺽 ?꾩븬</div>
                    <div class="meta-value"><%= String.format(java.util.Locale.US, "%,.1f", ratedVoltage == null ? 0.0 : ratedVoltage.doubleValue()) %> V</div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">?뺢꺽 ?꾨쪟</div>
                    <div class="meta-value"><%= String.format(java.util.Locale.US, "%,.1f", ratedCurrent == null ? 0.0 : ratedCurrent.doubleValue()) %> A</div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">理쒓렐 ?꾩쟻 ?먮꼫吏</div>
                    <div class="meta-value"><%= String.format(java.util.Locale.US, "%,.1f", currentEnergyTotal == null ? 0.0 : currentEnergyTotal.doubleValue()) %> kWh</div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">30???됯퇏 ?쇱궗?⑸웾</div>
                    <div class="meta-value"><%= String.format(java.util.Locale.US, "%,.1f", avgDailyKwh) %> kWh</div>
                </div>
                <div class="meta-item">
                    <div class="meta-label">30???쇳겕?꾨젰</div>
                    <div class="meta-value"><%= String.format(java.util.Locale.US, "%,.2f", peakKw) %> kW</div>
                </div>
            </div>
        </div>
    </div>

    <div class="chart-grid">
        <div class="panel">
            <h3>?쇰퀎 ?ъ슜??異붿씠</h3>
            <div id="dailyChart" class="chart-box"></div>
        </div>
        <div class="panel">
            <h3>?붾퀎 ?ъ슜??異붿씠</h3>
            <div id="monthlyChart" class="chart-box"></div>
        </div>
    </div>

    <div class="panel" style="margin-top:16px;">
        <h3>理쒓렐 31???쇰퀎 ?ъ슜??/h3>
        <table class="data-table">
            <thead>
            <tr>
                <th>?좎쭨</th>
                <th>?ъ슜??(kWh)</th>
            </tr>
            </thead>
            <tbody>
            <% for (Map.Entry<LocalDate, Double> entry : dailyUsage.entrySet()) { %>
            <tr>
                <td><%= entry.getKey().toString() %></td>
                <td><%= String.format(java.util.Locale.US, "%,.2f", entry.getValue().doubleValue()) %></td>
            </tr>
            <% } %>
            </tbody>
        </table>
    </div>
</div>

<script>
const dailyLabels = [<%
boolean first = true;
for (LocalDate d : dailyUsage.keySet()) {
    if (!first) out.print(",");
    out.print("\"" + jsq(d.toString()) + "\"");
    first = false;
}
%>];
const dailyValues = [<%
first = true;
for (Double v : dailyUsage.values()) {
    if (!first) out.print(",");
    out.print(String.format(java.util.Locale.US, "%.6f", v.doubleValue()));
    first = false;
}
%>];

const monthlyLabels = [<%
first = true;
for (String k : monthlyUsage.keySet()) {
    if (!first) out.print(",");
    out.print("\"" + jsq(k) + "\"");
    first = false;
}
%>];
const monthlyValues = [<%
first = true;
for (Double v : monthlyUsage.values()) {
    if (!first) out.print(",");
    out.print(String.format(java.util.Locale.US, "%.6f", v.doubleValue()));
    first = false;
}
%>];

function fmtNum(v,d){
    const n = Number(v);
    if(!Number.isFinite(n)) return '-';
    return n.toLocaleString('en-US',{minimumFractionDigits:d,maximumFractionDigits:d});
}

const dailyChart = echarts.init(document.getElementById('dailyChart'));
dailyChart.setOption({
    color:['#d48a14'],
    tooltip:{trigger:'axis',formatter:function(params){
        if(!params||!params.length) return '';
        return params[0].axisValue + '<br/>' + params[0].marker + '?쇱궗?⑸웾: ' + fmtNum(params[0].value,1) + ' kWh';
    }},
    grid:{left:50,right:20,top:18,bottom:40,containLabel:true},
    xAxis:{type:'category',data:dailyLabels,axisLabel:{color:'#64748b',interval:4}},
    yAxis:{type:'value',axisLabel:{formatter:function(v){ return fmtNum(v,0); }}},
    series:[{
        name:'?쇱궗?⑸웾',
        type:'line',
        smooth:true,
        symbol:'circle',
        symbolSize:5,
        showSymbol:false,
        lineStyle:{width:3,color:'#d48a14'},
        areaStyle:{color:new echarts.graphic.LinearGradient(0,0,0,1,[{offset:0,color:'rgba(212,138,20,.28)'},{offset:1,color:'rgba(212,138,20,.04)'}])},
        data:dailyValues
    }]
});

const monthlyChart = echarts.init(document.getElementById('monthlyChart'));
monthlyChart.setOption({
    color:['#2f6fed'],
    tooltip:{trigger:'axis',formatter:function(params){
        if(!params||!params.length) return '';
        return params[0].axisValue + '<br/>' + params[0].marker + '?붿궗?⑸웾: ' + fmtNum(params[0].value,1) + ' kWh';
    }},
    grid:{left:48,right:20,top:18,bottom:40,containLabel:true},
    xAxis:{type:'category',data:monthlyLabels,axisLabel:{color:'#64748b'}},
    yAxis:{type:'value',axisLabel:{formatter:function(v){ return fmtNum(v,0); }}},
    series:[{
        name:'?붿궗?⑸웾',
        type:'bar',
        barMaxWidth:30,
        itemStyle:{color:'#2f6fed',borderRadius:[8,8,0,0]},
        data:monthlyValues
    }]
});

window.addEventListener('resize',function(){dailyChart.resize();monthlyChart.resize();});
</script>
<footer>짤 EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
<%
} // end try-with-resources
%>

