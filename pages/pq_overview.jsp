<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page import="com.fasterxml.jackson.databind.ObjectMapper" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>

<%!
    private static float avgFloat(List<Float> a) {
        if (a == null || a.isEmpty()) return 0f;
        float s = 0f;
        for (float v : a) s += v;
        return s / a.size();
    }
    private static float minFloat(List<Float> a) {
        if (a == null || a.isEmpty()) return 0f;
        float m = Float.MAX_VALUE;
        for (float v : a) if (v < m) m = v;
        return m;
    }
    private static float maxFloat(List<Float> a) {
        if (a == null || a.isEmpty()) return 0f;
        float m = -Float.MAX_VALUE;
        for (float v : a) if (v > m) m = v;
        return m;
    }
%>

<%
    try (Connection conn = openDbConnection()) {
    LocalDate today = LocalDate.now();
    LocalDate yesterday = today.minusDays(1);
    String recentMinParam = request.getParameter("recent_min");
    int recentMin = 0;
    try { recentMin = Integer.parseInt(recentMinParam); } catch (Exception ignore) {}
    if (!(recentMin == 1 || recentMin == 5 || recentMin == 10)) recentMin = 0;

    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");

    if (startDate == null || startDate.trim().isEmpty()) startDate = yesterday.toString();
    if (endDate == null || endDate.trim().isEmpty()) endDate = today.toString();
    if (startTime == null || startTime.isEmpty()) startTime = "00:00:00";
    if (endTime == null || endTime.isEmpty()) endTime = "23:59:59";

    String meter = "1";
    String paramMeter = request.getParameter("meter");
    if (paramMeter != null && !paramMeter.trim().isEmpty()) meter = paramMeter;

    String building = request.getParameter("building");
    String usage = request.getParameter("usage");

    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String[]> meterOptions = new ArrayList<>();

    try {
        try (Statement stmt = conn.createStatement()) {
            try (ResultSet rs = stmt.executeQuery("SELECT DISTINCT building_name FROM meters WHERE building_name IS NOT NULL ORDER BY building_name")) {
                while (rs.next()) buildingOptions.add(rs.getString(1).trim());
            }
            try (ResultSet rs = stmt.executeQuery("SELECT DISTINCT usage_type FROM meters WHERE usage_type IS NOT NULL ORDER BY usage_type")) {
                while (rs.next()) usageOptions.add(rs.getString(1).trim());
            }
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

    List<String> labels = new ArrayList<>();
    List<Float> freq = new ArrayList<>();
    List<Float> vab = new ArrayList<>();
    List<Float> vbc = new ArrayList<>();
    List<Float> vca = new ArrayList<>();
    List<Float> iA = new ArrayList<>();
    List<Float> iB = new ArrayList<>();
    List<Float> iC = new ArrayList<>();
    List<Float> pfA = new ArrayList<>();
    List<Float> pfB = new ArrayList<>();
    List<Float> pfC = new ArrayList<>();

    List<Float> vAvg = new ArrayList<>();
    List<Float> iAvg = new ArrayList<>();
    List<Float> pfAvg = new ArrayList<>();

    try {
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT measured_at, frequency, ")
           .append("voltage_ab, voltage_bc, voltage_ca, ")
           .append("current_a, current_b, current_c, ")
           .append("COALESCE(power_factor_a, power_factor, 0) AS pf_a_eff, ")
           .append("COALESCE(power_factor_b, power_factor, 0) AS pf_b_eff, ")
           .append("COALESCE(power_factor_c, power_factor, 0) AS pf_c_eff, ")
           .append("(COALESCE(power_factor_a, power_factor, 0) + ")
           .append(" COALESCE(power_factor_b, power_factor, 0) + ")
           .append(" COALESCE(power_factor_c, power_factor, 0)) / 3.0 AS pf_avg_eff ")
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

                    float freqVal = rs.getFloat("frequency");
                    float vabVal = rs.getFloat("voltage_ab");
                    float vbcVal = rs.getFloat("voltage_bc");
                    float vcaVal = rs.getFloat("voltage_ca");
                    float iAVal = rs.getFloat("current_a");
                    float iBVal = rs.getFloat("current_b");
                    float iCVal = rs.getFloat("current_c");
                    float pfAVal = rs.getFloat("pf_a_eff");
                    float pfBVal = rs.getFloat("pf_b_eff");
                    float pfCVal = rs.getFloat("pf_c_eff");
                    float pfAvgVal = rs.getFloat("pf_avg_eff");

                    freq.add(freqVal);
                    vab.add(vabVal); vbc.add(vbcVal); vca.add(vcaVal);
                    iA.add(iAVal); iB.add(iBVal); iC.add(iCVal);
                    pfA.add(pfAVal); pfB.add(pfBVal); pfC.add(pfCVal);

                    vAvg.add((vabVal + vbcVal + vcaVal) / 3f);
                    iAvg.add((iAVal + iBVal + iCVal) / 3f);
                    pfAvg.add(pfAvgVal);
                }
            }
        }
    } catch (Exception e) {
        out.println("DB 오류: " + e.getMessage());
    }

    boolean noData = labels.isEmpty();

    float freqAvg = avgFloat(freq), freqMin = minFloat(freq), freqMax = maxFloat(freq);
    float vAvgMean = avgFloat(vAvg), vAvgMin = minFloat(vAvg), vAvgMax = maxFloat(vAvg);
    float iAvgMean = avgFloat(iAvg), iAvgMin = minFloat(iAvg), iAvgMax = maxFloat(iAvg);
    float pfAvgMean = avgFloat(pfAvg), pfAvgMin = minFloat(pfAvg), pfAvgMax = maxFloat(pfAvg);

    ObjectMapper mapper = new ObjectMapper();
    String jsonLabels = mapper.writeValueAsString(labels);
    String jsonFreq = mapper.writeValueAsString(freq);
    String jsonVab = mapper.writeValueAsString(vab);
    String jsonVbc = mapper.writeValueAsString(vbc);
    String jsonVca = mapper.writeValueAsString(vca);
    String jsonVA = mapper.writeValueAsString(vAvg);
    String jsonIA = mapper.writeValueAsString(iA);
    String jsonIB = mapper.writeValueAsString(iB);
    String jsonIC = mapper.writeValueAsString(iC);
    String jsonIAVG = mapper.writeValueAsString(iAvg);
    String jsonPFA = mapper.writeValueAsString(pfA);
    String jsonPFB = mapper.writeValueAsString(pfB);
    String jsonPFC = mapper.writeValueAsString(pfC);
    String jsonPFAVG = mapper.writeValueAsString(pfAvg);
%>

<html>
<head>
    <title>통합 전력품질 모니터링</title>
    <script src="../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
      .pq-overview-layout {
        display: grid;
        grid-template-columns: minmax(320px, 380px) minmax(0, 1fr);
        gap: 12px;
        align-items: stretch;
      }
      .summary-wrap h3 {
        margin: 0 0 12px 0;
        font-size: 14px;
        font-weight: 700;
        color: #16324f;
      }
      .summary-wrap {
        margin: 0;
        padding: 14px;
        height: 100%;
        display: flex;
        flex-direction: column;
      }
      .summary-meta { margin-bottom:10px; }
      .summary-wrap .badge {
        font-size: 12px;
        padding: 3px 8px;
      }
      .summary-wrap .summary-table {
        font-size: 12px;
      }
      .summary-wrap .summary-table th {
        font-size: 12px;
        padding: 6px 5px;
      }
      .summary-wrap .summary-table td {
        font-size: 12px;
        padding: 6px 5px;
      }
      .pq-overview-layout .summary-wrap { max-width:none; }
      .pq-overview-layout .chart-container {
        min-width: 0;
        height: calc(100vh - 245px);
        min-height: 520px;
        margin: 0;
      }
      .chart-stack { display:flex; flex-direction:column; gap:12px; width:100%; height:100%; }
      .chart-box { flex:1 1 0; min-height: 0; background:#fff; border:1px solid var(--border); border-radius:10px; box-shadow:var(--shadow-soft); padding:10px; }
      .chart-title { margin:0 0 8px 0; font-size: 15px; }
      .chart-inner { width:100%; height: calc(100% - 26px); }
      @media (max-width: 1100px) {
        .pq-overview-layout {
          grid-template-columns: 1fr;
        }
        .pq-overview-layout .chart-container {
          height: 700px;
        }
      }
    </style>
</head>
<body>
<div class="title-bar">
    <h2>🧭 통합 전력품질 모니터링 (주파수 / 역률 / 전압 / 전류)</h2>
    <div class="inline-actions">
        <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
    </div>
</div>

<form method="GET" class="filter-card">
    <label for="building">건물</label>
    <select name="building" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String opt : buildingOptions) { %>
        <option value="<%= opt %>" <%= opt.equals(building) ? "selected" : "" %>><%= opt %></option>
        <% } %>
    </select>

    <label for="usage">용도</label>
    <select name="usage" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String opt : usageOptions) { %>
        <option value="<%= opt %>" <%= opt.equals(usage) ? "selected" : "" %>><%= opt %></option>
        <% } %>
    </select>

    <label for="meter">Meter</label>
    <select name="meter">
        <option value="">전체</option>
        <% for (String[] opt : meterOptions) { %>
        <option value="<%= opt[0] %>" <%= opt[0].equals(meter) ? "selected" : "" %>><%= opt[1] %></option>
        <% } %>
    </select>

    <label for="recent_min">자동재조회</label>
    <select name="recent_min" onchange="this.form.submit()">
        <option value="" <%= recentMin == 0 ? "selected" : "" %>>사용안함</option>
        <option value="1" <%= recentMin == 1 ? "selected" : "" %>>1분</option>
        <option value="5" <%= recentMin == 5 ? "selected" : "" %>>5분</option>
        <option value="10" <%= recentMin == 10 ? "selected" : "" %>>10분</option>
    </select>

    <label for="startDate">기간</label>
    <input type="date" name="startDate" value="<%= startDate %>">
    <input type="time" name="startTime" step="1" value="<%= startTime %>"> ~
    <input type="date" name="endDate" value="<%= endDate %>">
    <input type="time" name="endTime" step="1" value="<%= endTime %>">

    <button type="submit">조회</button>
</form>

<% if (noData) { %>
<div class="msg-box">데이터가 없습니다</div>
<% } %>

<div class="split-grid one-side-one-main pq-overview-layout">
  <div class="summary-wrap panel">
      <h3>요약</h3>
      <div class="summary-meta">
          <span class="badge">데이터 개수: <%= labels.size() %></span>
      </div>
      <table class="summary-table">
          <thead>
          <tr>
              <th>항목</th>
              <th>평균</th>
              <th>최소</th>
              <th>최대</th>
          </tr>
          </thead>
          <tbody>
          <tr><td>주파수 (Hz)</td><td><%= String.format(java.util.Locale.US, "%.2f", freqAvg) %></td><td><%= String.format(java.util.Locale.US, "%.2f", freqMin) %></td><td><%= String.format(java.util.Locale.US, "%.2f", freqMax) %></td></tr>
          <tr><td>전압평균 (V)</td><td><%= String.format(java.util.Locale.US, "%.2f", vAvgMean) %></td><td><%= String.format(java.util.Locale.US, "%.2f", vAvgMin) %></td><td><%= String.format(java.util.Locale.US, "%.2f", vAvgMax) %></td></tr>
          <tr><td>전류평균 (A)</td><td><%= String.format(java.util.Locale.US, "%.2f", iAvgMean) %></td><td><%= String.format(java.util.Locale.US, "%.2f", iAvgMin) %></td><td><%= String.format(java.util.Locale.US, "%.2f", iAvgMax) %></td></tr>
          <tr><td>역률평균 (-)</td><td><%= String.format(java.util.Locale.US, "%.2f", pfAvgMean) %></td><td><%= String.format(java.util.Locale.US, "%.2f", pfAvgMin) %></td><td><%= String.format(java.util.Locale.US, "%.2f", pfAvgMax) %></td></tr>
          </tbody>
      </table>
  </div>

  <div class="chart-container">
      <div class="chart-stack">
          <div class="chart-box">
              <h3 class="chart-title">주파수 + 역률</h3>
              <div id="chartFreq" class="chart-inner"></div>
          </div>
          <div class="chart-box">
              <h3 class="chart-title">전압 (Vab / Vbc / Vca)</h3>
              <div id="chartVolt" class="chart-inner"></div>
          </div>
          <div class="chart-box">
              <h3 class="chart-title">전류 (Ia / Ib / Ic)</h3>
              <div id="chartCurr" class="chart-inner"></div>
          </div>
      </div>
  </div>
</div>

<script>
const labels = <%= jsonLabels %>;
const autoRefreshMin = <%= recentMin %>;
const freq = <%= jsonFreq %>;
const vab = <%= jsonVab %>;
const vbc = <%= jsonVbc %>;
const vca = <%= jsonVca %>;
const ia = <%= jsonIA %>;
const ib = <%= jsonIB %>;
const ic = <%= jsonIC %>;
const pfavg = <%= jsonPFAVG %>;

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
function pickByIndex(arr, idx) { return idx.map(i => arr[i]); }
const f2 = (v) => (Number.isFinite(+v) ? (+v).toFixed(2) : '0.00');

const sampleIdx = buildSampleIndex(labels.length, MAX_POINTS);
const x = pickByIndex(labels, sampleIdx);
const sFreq = pickByIndex(freq, sampleIdx);
const sVab = pickByIndex(vab, sampleIdx);
const sVbc = pickByIndex(vbc, sampleIdx);
const sVca = pickByIndex(vca, sampleIdx);
const sIa = pickByIndex(ia, sampleIdx);
const sIb = pickByIndex(ib, sampleIdx);
const sIc = pickByIndex(ic, sampleIdx);
const sPfavg = pickByIndex(pfavg, sampleIdx);

function optionOf(yName, unit, series, yMin, yMax, showSlider) {
  return {
    tooltip: {
      trigger: 'axis',
      formatter: function(params){
        if (!params || !params.length) return '';
        let html = params[0].axisValue + '<br/>';
        for (let i = 0; i < params.length; i++) {
          html += params[i].marker + params[i].seriesName + ': ' + f2(params[i].value) + ' ' + unit + '<br/>';
        }
        return html;
      }
    },
    legend: { top: 0 },
    grid: { left: 64, right: 48, top: 32, bottom: showSlider ? 68 : 26, containLabel: false },
    xAxis: {
      type: 'category',
      data: x,
      axisLabel: { interval: 'auto' },
      axisLine: { onZero: false }
    },
    yAxis: {
      type: 'value',
      name: yName,
      scale: true,
      min: yMin,
      max: yMax,
      axisLabel: { formatter: function(v){ return f2(v); } }
    },
    dataZoom: showSlider ? [
      { type: 'inside', xAxisIndex: 0, filterMode: 'none' },
      { type: 'slider', xAxisIndex: 0, filterMode: 'none', height: 22, bottom: 12 }
    ] : [
      { type: 'inside', xAxisIndex: 0, filterMode: 'none' }
    ],
    series: series
  };
}

function line(name, data, color, width){
  return {
    name: name,
    type: 'line',
    data: data,
    showSymbol: false,
    sampling: 'lttb',
    lineStyle: { color: color, width: width || 2 }
  };
}

const chartFreq = echarts.init(document.getElementById('chartFreq'));
const chartVolt = echarts.init(document.getElementById('chartVolt'));
const chartCurr = echarts.init(document.getElementById('chartCurr'));

chartFreq.setOption({
  tooltip: {
    trigger: 'axis',
    formatter: function(params){
      if (!params || !params.length) return '';
      let html = params[0].axisValue + '<br/>';
      for (let i = 0; i < params.length; i++) {
        const unit = params[i].seriesName === 'PF' ? '' : ' Hz';
        html += params[i].marker + params[i].seriesName + ': ' + f2(params[i].value) + unit + '<br/>';
      }
      return html;
    }
  },
  legend: { top: 0, data: ['Frequency', 'PF'] },
  grid: { left: 64, right: 68, top: 32, bottom: 26, containLabel: false },
  xAxis: {
    type: 'category',
    data: x,
    axisLabel: { interval: 'auto' },
    axisLine: { onZero: false }
  },
  yAxis: [
    { type: 'value', name: 'Hz', scale: true, axisLabel: { formatter: function(v){ return f2(v); } } },
    {
      type: 'value',
      name: 'PF',
      min: -1,
      max: 1,
      position: 'right',
      interval: 0.5,
      nameGap: 14,
      axisLabel: {
        formatter: function(v){ return '{pf|' + f2(v) + '}'; },
        rich: {
          pf: {
            width: 44,
            align: 'right'
          }
        }
      }
    }
  ],
  dataZoom: [
    { type: 'inside', xAxisIndex: 0, filterMode: 'none' }
  ],
  series: [
    { name: 'Frequency', type: 'line', yAxisIndex: 0, data: sFreq, showSymbol: false, sampling: 'lttb', lineStyle: { color: '#1f2937', width: 2.2 } },
    { name: 'PF', type: 'line', yAxisIndex: 1, data: sPfavg, showSymbol: false, sampling: 'lttb', lineStyle: { color: '#dc2626', width: 2.0 } }
  ]
});
chartVolt.setOption(optionOf('V', 'V', [
  line('Vab', sVab, '#ef4444'),
  line('Vbc', sVbc, '#3b82f6'),
  line('Vca', sVca, '#22c55e')
], null, null, false));
chartCurr.setOption(optionOf('A', 'A', [
  line('Ia', sIa, '#f97316'),
  line('Ib', sIb, '#8b5cf6'),
  line('Ic', sIc, '#14b8a6')
], null, null, true));

echarts.connect([chartFreq, chartVolt, chartCurr]);

function extractZoomWindow(evt) {
  const z = (evt && evt.batch && evt.batch.length) ? evt.batch[0] : evt;
  if (!z) return null;
  const p = { dataZoomIndex: 0 };
  if (z.start != null) p.start = z.start;
  if (z.end != null) p.end = z.end;
  if (z.startValue != null) p.startValue = z.startValue;
  if (z.endValue != null) p.endValue = z.endValue;
  return p;
}

chartCurr.on('dataZoom', function(evt){
  if (window.__pqSyncingZoom) return;
  const zoom = extractZoomWindow(evt);
  if (!zoom) return;
  window.__pqSyncingZoom = true;
  try {
    chartFreq.dispatchAction(Object.assign({ type: 'dataZoom' }, zoom));
    chartVolt.dispatchAction(Object.assign({ type: 'dataZoom' }, zoom));
  } finally {
    window.__pqSyncingZoom = false;
  }
});

window.addEventListener('resize', function(){
  chartFreq.resize();
  chartVolt.resize();
  chartCurr.resize();
});

if (autoRefreshMin > 0) {
  setTimeout(function() {
    const u = new URL(window.location.href);
    u.searchParams.set('_ts', String(Date.now()));
    window.location.replace(u.toString());
  }, autoRefreshMin * 60 * 1000);
}
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
<%
    }
%>
</body>
</html>
