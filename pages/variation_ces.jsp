<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconn.jsp" %>

<%! 
    private static float safeParseFloat(String s, float defVal) {
        if (s == null) return defVal;
        try {
            String t = s.trim();
            if (t.isEmpty()) return defVal;
            return Float.parseFloat(t);
        } catch (Exception e) {
            return defVal;
        }
    }
    private static float maxFloat(List<Float> a) {
        if (a == null || a.isEmpty()) return 0f;
        float m = -Float.MAX_VALUE;
        for (float v : a) if (v > m) m = v;
        return m;
    }
    private static float minFloat(List<Float> a) {
        if (a == null || a.isEmpty()) return 0f;
        float m = Float.MAX_VALUE;
        for (float v : a) if (v < m) m = v;
        return m;
    }
    private static float percentileAbs(List<Float> a, double p) {
        if (a == null || a.isEmpty()) return 0f;
        ArrayList<Float> b = new ArrayList<>(a.size());
        for (float v : a) b.add(Math.abs(v));
        Collections.sort(b);
        if (p <= 0) return b.get(0);
        if (p >= 100) return b.get(b.size()-1);
        double rank = (p / 100.0) * (b.size() - 1);
        int lo = (int)Math.floor(rank);
        int hi = (int)Math.ceil(rank);
        if (lo == hi) return b.get(lo);
        double w = rank - lo;
        return (float)(b.get(lo) * (1.0 - w) + b.get(hi) * w);
    }
%>

<%
    LocalDate today = LocalDate.now();
    LocalDate yesterday = today;

    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");

    if (startDate == null || startDate.trim().isEmpty()) startDate = yesterday.toString();
    if (endDate == null || endDate.trim().isEmpty()) endDate = today.toString();
    if (startTime == null || startTime.isEmpty()) startTime = "00:00:00";
    if (endTime == null || endTime.isEmpty()) endTime = "23:59:59";

    String meter;
    String paramMeter = request.getParameter("meter");
    meter = (paramMeter != null && !paramMeter.trim().isEmpty()) ? paramMeter : "1";

    String building = request.getParameter("building");
    String usage = request.getParameter("usage");

    // 湲곗? ?좏깮: avg(조회구간 평균) / rated(?뺢꺽 湲곗?-李멸퀬??
    String refMode = request.getParameter("refMode");
    if (refMode == null || refMode.trim().isEmpty()) refMode = "avg";

    float ratedIDefault = 100f; // ?꾩슂???꾩옣 湲곗??꾨쪟(?? 李⑤떒湲??뺢꺽 ??濡?議곗젙
    float ratedI = safeParseFloat(request.getParameter("ratedI"), ratedIDefault);

    List<String[]> meterOptions = new ArrayList<>();
    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();

    try {
        try (Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery("SELECT DISTINCT building_name FROM meters WHERE building_name IS NOT NULL ORDER BY building_name");
            while (rs.next()) buildingOptions.add(rs.getString(1).trim());
            rs.close();

            rs = stmt.executeQuery("SELECT DISTINCT usage_type FROM meters WHERE usage_type IS NOT NULL ORDER BY usage_type");
            while (rs.next()) usageOptions.add(rs.getString(1).trim());
            rs.close();

        }
        StringBuilder meterSql = new StringBuilder("SELECT meter_id, name FROM meters WHERE 1=1 ");
        List<Object> meterParams = new ArrayList<>();
        if (building != null && !building.trim().isEmpty()) {
            meterSql.append("AND building_name = ? ");
            meterParams.add(building.trim());
        }
        if (usage != null && !usage.trim().isEmpty()) {
            meterSql.append("AND usage_type = ? ");
            meterParams.add(usage.trim());
        }
        meterSql.append("ORDER BY meter_id");

        try (PreparedStatement psMeter = conn.prepareStatement(meterSql.toString())) {
            for (int i = 0; i < meterParams.size(); i++) psMeter.setObject(i + 1, meterParams.get(i));
            try (ResultSet rsMeter = psMeter.executeQuery()) {
                while (rsMeter.next()) meterOptions.add(new String[]{rsMeter.getString("meter_id"), rsMeter.getString("name")});
            }
        }

        boolean meterExists = false;
        for (String[] opt : meterOptions) {
            if (opt[0].equals(meter)) {
                meterExists = true;
                break;
            }
        }
        if (!meterExists) meter = "";
    } catch (Exception e) {
        e.printStackTrace();
    }
%>

<html>
<head>
    <title>전류 변동율 분석</title>
    <script src="../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
            .summary-wrap {
        margin: 0;
        padding: 14px;
        background: linear-gradient(180deg, #ffffff 0%, #f8fbff 100%);
        border: 1px solid #dbe7f5;
        border-radius: 14px;
        box-shadow: 0 10px 24px rgba(16,24,40,.08);
      }
      .summary-wrap h3 {
        margin: 0 0 12px 0;
        font-size: 16px;
        font-weight: 700;
        color: #16324f;
        letter-spacing: -0.2px;
      }
      .summary-meta { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:10px; }
      .summary-table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        font-size: 12px;
        border: 1px solid #dbe4ef;
        border-radius: 10px;
        overflow: hidden;
        background: #fff;
      }
      .summary-table th {
        font-size: 12px;
        font-weight: 700;
        padding: 7px 6px;
        line-height: 1.2;
        background: #eef3fa;
        color: #274567;
        border-bottom: 1px solid #dbe4ef;
        white-space: nowrap;
      }
      .summary-table th .th-main {
        display: block;
      }
      .summary-table th .th-sub {
        display: block;
        margin-top: 2px;
        font-size: 11px;
        font-weight: 600;
        color: #4e6580;
      }
      .summary-table td {
        padding: 7px 6px;
        text-align: center;
        color: #243b53;
        border-bottom: 1px solid #eef2f7;
      }
      .summary-table tbody tr:last-child td { border-bottom: 1px solid #dbe4ef; }
      .summary-table tbody tr.worst-row td { background: #fff1f1; color: #8f1f1f; font-weight: 700; }
      .badge {
        display: inline-flex;
        align-items: center;
        padding: 4px 10px;
        border-radius: 999px;
        border: 1px solid #d4e2f3;
        background: #eef4fb;
        color: #24496e;
        font-size: 12px;
        font-weight: 600;
      }
      .badge-worst { background: #ffe9e9; border-color: #ffc6c6; color: #9f1c1c; }
      .badge-line { width: 100%; justify-content: flex-start; }
      .summary-note {
        margin-top: 10px;
        padding: 8px 10px;
        border-radius: 8px;
        background: #f3f7fc;
        color: #4b5d73;
        font-size: 12px;
        line-height: 1.4;
        border: 1px dashed #cdd9e8;
      }
      .summary-error {
        margin-top: 8px;
        padding: 8px 10px;
        border-radius: 8px;
        background: #fff2f2;
        color: #b00020;
        font-size: 12px;
        white-space: pre-wrap;
        border: 1px solid #ffd0d0;
      }
      .ref-box { display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin-top:8px; }
      .ref-box label { display:flex; gap:6px; align-items:center; }
      .ref-box input[type="number"]{ width: 110px; }

      .content-row { display: flex; gap: 12px; align-items: stretch; }
      /* summary left, chart right */
      .content-row .summary-wrap { flex: 0 0 360px; max-width: 360px; margin: 0; }
      .content-row .chart-container { flex: 1 1 auto; min-width: 0; height: 520px; margin: 0; }
      @media (max-width: 1100px) {
        .content-row { flex-direction: column; }
        .content-row .summary-wrap { max-width: none; }
        .content-row .chart-container { height: 420px; }
      }

</style>
</head>
<body>
<div class="title-bar">
    <h2>📈 전류 변동율 분석 (Ia / Ib / Ic)</h2>
    <div style="display:flex; gap:8px; align-items:center;">
        <button class="back-btn" onclick="location.href='/pages/epms_main.jsp'">EPMS 홈</button>
        <button class="back-btn" onclick="location.href='variation_ves.jsp' + location.search">전압 변동율</button>
    </div>
</div>

<form method="GET">
    <div class="ref-box">
        <span>기준: </span>
        <label><input type="radio" name="refMode" value="avg" <%= "avg".equals(refMode) ? "checked" : "" %> > 조회구간 평균</label>
        <label><input type="radio" name="refMode" value="rated" <%= "rated".equals(refMode) ? "checked" : "" %> > 기준전류(참고)</label>
        <label>기준전류(A): <input type="number" name="ratedI" step="0.1" value="<%= ratedI %>"></label>
    </div>

    건물:
    <select name="building" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String opt : buildingOptions) { %>
        <option value="<%= opt %>" <%= opt.equals(building) ? "selected" : "" %>><%= opt %></option>
        <% } %>
    </select>

    용도:
    <select name="usage" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String opt : usageOptions) { %>
        <option value="<%= opt %>" <%= opt.equals(usage) ? "selected" : "" %>><%= opt %></option>
        <% } %>
    </select>

    Meter:
    <select name="meter">
        <option value="">전체</option>
        <% for (String[] opt : meterOptions) { %>
        <option value="<%= opt[0] %>" <%= opt[0].equals(meter) ? "selected" : "" %>><%= opt[1] %></option>
        <% } %>
    </select>

    기간: <input type="date" name="startDate" value="<%= startDate %>">
    <input type="time" name="startTime" step="1" value="<%= startTime %>"> ~
    <input type="date" name="endDate" value="<%= endDate %>">
    <input type="time" name="endTime" step="1" value="<%= endTime %>">

    

    <button type="submit">조회</button>
</form>

<%
    List<String> labels = new ArrayList<>();

    List<Float> currentRateA = new ArrayList<>();
    List<Float> currentRateB = new ArrayList<>();
    List<Float> currentRateC = new ArrayList<>();
    List<Float> currentUpper = new ArrayList<>();
    List<Float> currentLower = new ArrayList<>();

    List<Float> iaRaw = new ArrayList<>();
    List<Float> ibRaw = new ArrayList<>();
    List<Float> icRaw = new ArrayList<>();

    float iaAvg = 0f, ibAvg = 0f, icAvg = 0f;
    float iaRef = 0f, ibRef = 0f, icRef = 0f;

    try {
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT measured_at, current_a, current_b, current_c ")
           .append("FROM vw_meter_measurements ")
           .append("WHERE measured_at BETWEEN ? AND ? ");

        List<Object> params = new ArrayList<>();
        params.add(startDate + " " + startTime);
        params.add(endDate + " " + endTime);

        if (building != null && !building.trim().isEmpty()) { sql.append(" AND building_name = ? "); params.add(building.trim()); }
        if (usage != null && !usage.trim().isEmpty()) { sql.append(" AND usage_type = ? "); params.add(usage.trim()); }
        if (meter != null && !meter.trim().isEmpty()) { sql.append(" AND meter_id = ? "); params.add(meter.trim()); }

        sql.append(" ORDER BY measured_at ASC");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) ps.setObject(i + 1, params.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Timestamp ts = rs.getTimestamp("measured_at");
                    labels.add(startDate.equals(endDate) ? ts.toString().substring(11, 16) : ts.toString().substring(0, 16));

                    iaRaw.add(rs.getFloat("current_a"));
                    ibRaw.add(rs.getFloat("current_b"));
                    icRaw.add(rs.getFloat("current_c"));
                }
            }
        }
    } catch (Exception e) {
        out.println("DB 오류: " + e.getMessage());
    }

    final float EPS = 0.000001f;

    if (!iaRaw.isEmpty()) {
        float iaSum = 0f, ibSum = 0f, icSum = 0f;
        for (int i = 0; i < iaRaw.size(); i++) {
            iaSum += iaRaw.get(i);
            ibSum += ibRaw.get(i);
            icSum += icRaw.get(i);
        }
        iaAvg = iaSum / iaRaw.size();
        ibAvg = ibSum / ibRaw.size();
        icAvg = icSum / icRaw.size();

        // 湲곗?媛?寃곗젙
        if ("rated".equals(refMode) && Math.abs(ratedI) > EPS) {
            iaRef = ratedI;
            ibRef = ratedI;
            icRef = ratedI;
        } else {
            iaRef = iaAvg;
            ibRef = ibAvg;
            icRef = icAvg;
        }

        boolean iaSafe = Math.abs(iaRef) > EPS;
        boolean ibSafe = Math.abs(ibRef) > EPS;
        boolean icSafe = Math.abs(icRef) > EPS;

        for (int i = 0; i < labels.size(); i++) {
            float ia = iaRaw.get(i);
            float ib = ibRaw.get(i);
            float ic = icRaw.get(i);

            currentRateA.add(iaSafe ? ((ia - iaRef) / iaRef * 100f) : 0f);
            currentRateB.add(ibSafe ? ((ib - ibRef) / ibRef * 100f) : 0f);
            currentRateC.add(icSafe ? ((ic - icRef) / icRef * 100f) : 0f);

            currentUpper.add(10f);
            currentLower.add(-10f);
        }
    }

    // ?붿빟 ?듦퀎 + worst phase ?좏깮(95% |蹂?숈쑉| 湲곗?)
    float aMax = maxFloat(currentRateA), aMin = minFloat(currentRateA), aP95 = percentileAbs(currentRateA, 95);
    float bMax = maxFloat(currentRateB), bMin = minFloat(currentRateB), bP95 = percentileAbs(currentRateB, 95);
    float cMax = maxFloat(currentRateC), cMin = minFloat(currentRateC), cP95 = percentileAbs(currentRateC, 95);

    String worst = "Ia";
    float worstScore = aP95;
    if (bP95 > worstScore) { worst = "Ib"; worstScore = bP95; }
    if (cP95 > worstScore) { worst = "Ic"; worstScore = cP95; }
    boolean noData = labels.isEmpty();
%>

<% if (noData) { %>
<div style="margin:12px 0;padding:10px 12px;border:1px solid #ffd6d6;background:#fff3f3;color:#b42318;border-radius:10px;font-weight:700;">데이터가 없습니다</div>
<% } %>

<div class="content-row">
<div class="summary-wrap">
    <h3>요약</h3>
    <div class="summary-meta">
        <span class="badge">기준: <%= "rated".equals(refMode) ? ("기준전류 " + ratedI + "A") : "조회구간 평균" %></span>
        <span class="badge <%= (("Ia".equals(worst) || "Ib".equals(worst) || "Ic".equals(worst)) ? "badge-worst" : "") %>">Worst: <%= worst %> (P95 |변동| = <%= String.format(java.util.Locale.US, "%.2f", worstScore) %>%)</span>
        <span class="badge badge-line">Ia 기준값: <%= String.format(java.util.Locale.US, "%.2f", iaRef) %> A</span>
        <span class="badge badge-line">Ib 기준값: <%= String.format(java.util.Locale.US, "%.2f", ibRef) %> A</span>
        <span class="badge badge-line">Ic 기준값: <%= String.format(java.util.Locale.US, "%.2f", icRef) %> A</span>
    </div>

    <table class="summary-table">
        <thead>
        <tr>
            <th><span class="th-main">항목</span><span class="th-sub">지표</span></th>
            <th><span class="th-main">최소</span><span class="th-sub">(%)</span></th>
            <th><span class="th-main">최대</span><span class="th-sub">(%)</span></th>
            <th><span class="th-main">P95</span><span class="th-sub">|변동|(%)</span></th>
            <th><span class="th-main">비고</span><span class="th-sub">판정</span></th>
        </tr>
        </thead>
        <tbody>
        <tr class="<%= "Ia".equals(worst) ? "worst-row" : "" %>">
            <td>Ia</td>
            <td><%= String.format(java.util.Locale.US, "%.2f", aMin) %></td>
            <td><%= String.format(java.util.Locale.US, "%.2f", aMax) %></td>
            <td><%= String.format(java.util.Locale.US, "%.2f", aP95) %></td>
            <td><%= "Ia".equals(worst) ? "Worst" : "" %></td>
        </tr>
        <tr class="<%= "Ib".equals(worst) ? "worst-row" : "" %>">
            <td>Ib</td>
            <td><%= String.format(java.util.Locale.US, "%.2f", bMin) %></td>
            <td><%= String.format(java.util.Locale.US, "%.2f", bMax) %></td>
            <td><%= String.format(java.util.Locale.US, "%.2f", bP95) %></td>
            <td><%= "Ib".equals(worst) ? "Worst" : "" %></td>
        </tr>
        <tr class="<%= "Ic".equals(worst) ? "worst-row" : "" %>">
            <td>Ic</td>
            <td><%= String.format(java.util.Locale.US, "%.2f", cMin) %></td>
            <td><%= String.format(java.util.Locale.US, "%.2f", cMax) %></td>
            <td><%= String.format(java.util.Locale.US, "%.2f", cP95) %></td>
            <td><%= "Ic".equals(worst) ? "Worst" : "" %></td>
        </tr>
        </tbody>
    </table>
</div>

<div class="chart-container">
    <div id="variationCurrentChart" style="width:100%; height:100%;"></div>
</div>
</div>


<script>
const labels = [<%= String.join(",", labels.stream().map(s -> "\"" + s + "\"").toList()) %>];

const currentRateA = [<%= currentRateA.stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) %>];
const currentRateB = [<%= currentRateB.stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) %>];
const currentRateC = [<%= currentRateC.stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) %>];
const currentUpper = [<%= currentUpper.stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) %>];
const currentLower = [<%= currentLower.stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) %>];
const MAX_POINTS = 2000;
function buildSampleIndex(length, maxPoints) {
  if (length <= maxPoints) return Array.from({ length }, (_, i) => i);
  const step = (length - 1) / (maxPoints - 1);
  const idx = [];
  let prev = -1;
  for (let i = 0; i < maxPoints; i++) {
    const cur = Math.round(i * step);
    if (cur !== prev) idx.push(cur);
    prev = cur;
  }
  return idx;
}
function pickByIndex(arr, idx) {
  return idx.map(i => arr[i]);
}
const sampleIdx = buildSampleIndex(labels.length, MAX_POINTS);
const labelsPlot = pickByIndex(labels, sampleIdx);
const currentRateAPlot = pickByIndex(currentRateA, sampleIdx);
const currentRateBPlot = pickByIndex(currentRateB, sampleIdx);
const currentRateCPlot = pickByIndex(currentRateC, sampleIdx);
const currentUpperPlot = pickByIndex(currentUpper, sampleIdx);
const currentLowerPlot = pickByIndex(currentLower, sampleIdx);

const worst = "<%= worst %>";

const chartDom = document.getElementById('variationCurrentChart');
const myChart = echarts.init(chartDom);
function fmt2(v){
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(2) : '-';
}

function lineWidthFor(name){
  return (name === worst) ? 3 : 1.5;
}

function createLargeAreaSeries(name, data, key, color){
  return {
    name,
    type: 'line',
    data,
    animation: false,
    showSymbol: false,
    sampling: 'lttb',
    progressive: 2000,
    progressiveThreshold: 5000,
    lineStyle: { color, width: 2 }
  };
}

const option = {
  tooltip: {
    trigger: 'axis',
    formatter: function(params) {
      if (!params || !params.length) return '';
      const lines = [params[0].axisValueLabel || params[0].axisValue || ''];
      params.forEach(function(p) {
        if (p.seriesName.indexOf('상한') !== -1 || p.seriesName.indexOf('하한') !== -1) return;
        lines.push(p.marker + p.seriesName + ': ' + fmt2(p.value) + '%');
      });
      return lines.join('<br/>');
    }
  },
  legend: { top: 0 },
  grid: { left: 50, right: 20, top: 40, bottom: 80, containLabel: true },
  xAxis: { type: 'category', data: labelsPlot, axisLabel: { interval: 'auto' } },
  yAxis: { type: 'value', scale: true, axisLabel: { formatter: '{value} %' } },
      dataZoom: [
        { type: 'inside', xAxisIndex: 0, filterMode: 'none' },
        { type: 'slider', xAxisIndex: 0, filterMode: 'none', height: 24, bottom: 16 }
      ],
  series: [
    createLargeAreaSeries('Ia 변동율', currentRateAPlot, 'Ia', '#ff922b'),
    createLargeAreaSeries('Ib 변동율', currentRateBPlot, 'Ib', '#845ef7'),
    createLargeAreaSeries('Ic 변동율', currentRateCPlot, 'Ic', '#20c997'),
    { name: '전류 상한(+10%)', type: 'line', data: currentUpperPlot, showSymbol: false, lineStyle: { type: 'dashed', width: 1 } },
    { name: '전류 하한(-10%)', type: 'line', data: currentLowerPlot, showSymbol: false, lineStyle: { type: 'dashed', width: 1 } }
  ]
};

myChart.setOption(option);
window.addEventListener('resize', () => myChart.resize());
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>












