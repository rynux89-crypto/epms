<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>

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

    private static float percentileAbs(List<Float> a, double p) {
        if (a == null || a.isEmpty()) return 0f;
        ArrayList<Float> b = new ArrayList<>(a.size());
        for (float v : a) b.add(Math.abs(v));
        Collections.sort(b);
        if (p <= 0) return b.get(0);
        if (p >= 100) return b.get(b.size() - 1);
        double rank = (p / 100.0) * (b.size() - 1);
        int lo = (int) Math.floor(rank);
        int hi = (int) Math.ceil(rank);
        if (lo == hi) return b.get(lo);
        double w = rank - lo;
        return (float) (b.get(lo) * (1.0 - w) + b.get(hi) * w);
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }
%>

<%
    try (Connection conn = openDbConnection()) {
    LocalDate today = LocalDate.now();

    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");

    if (startDate == null || startDate.trim().isEmpty()) startDate = today.toString();
    if (endDate == null || endDate.trim().isEmpty()) endDate = today.toString();
    if (startTime == null || startTime.isEmpty()) startTime = "00:00:00";
    if (endTime == null || endTime.isEmpty()) endTime = "23:59:59";

    String meter;
    String paramMeter = request.getParameter("meter");
    meter = (paramMeter != null && !paramMeter.trim().isEmpty()) ? paramMeter : "1";

    String building = request.getParameter("building");
    String usage = request.getParameter("usage");

    float warn1 = safeParseFloat(request.getParameter("warn1"), 10f);
    float warn2 = safeParseFloat(request.getParameter("warn2"), 15f);
    float warn3 = safeParseFloat(request.getParameter("warn3"), 20f);

    List<String[]> meterOptions = new ArrayList<>();
    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();

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
%>

<html>
<head>
    <title>전류 불평형 분석</title>
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
      .summary-table th .th-main { display: block; }
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
      .summary-table tbody tr:last-child td { border-bottom: none; }
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
      .ref-box input[type="number"] { width: 110px; }
      .content-row { display: flex; gap: 12px; align-items: stretch; }
      .content-row .summary-wrap { flex: 0 0 360px; max-width: 360px; margin: 0; }
      .content-row .chart-container { flex: 1 1 auto; min-width: 0; height: 640px; margin: 0; }
      .chart-stack { display:flex; flex-direction:column; gap:12px; width:100%; height:100%; }
      .chart-box { flex:1 1 0; min-height: 0; background:#fff; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,.06); padding:10px; }
      .chart-title { margin:0 0 8px 0; font-size: 15px; }
      .chart-inner { width:100%; height: calc(100% - 26px); }
      .top-actions { display:flex; gap:8px; align-items:center; }
      .filter-form { display:flex; flex-direction:column; gap:10px; margin-bottom: 12px; }
      .filter-row {
        display:flex;
        align-items:center;
        gap:10px;
        flex-wrap:nowrap;
        overflow-x:auto;
        white-space: nowrap;
      }
      .field { display:flex; align-items:center; gap:6px; font-size:13px; font-weight:600; color:#334155; }
      .field span { white-space: nowrap; }
      .period-group { display:flex; align-items:center; gap:6px; flex-wrap:nowrap; }
      .query-btn { min-width: 74px; }
      .empty-box { margin:12px 0; padding:10px 12px; border:1px solid #ffd6d6; background:#fff3f3; color:#b42318; border-radius:10px; font-weight:700; }
      @media (max-width: 1100px) {
        .content-row { flex-direction: column; }
        .content-row .summary-wrap { max-width: none; }
        .content-row .chart-container { height: 560px; }
      }
    </style>
</head>
<body>
<div class="title-bar">
    <h2>🔀 전류 불평형 분석 (Ia / Ib / Ic)</h2>
    <div class="top-actions">
        <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        <button class="back-btn" onclick="location.href='voltage_unbalance.jsp' + location.search">전압 불평형</button>
    </div>
</div>

<form method="GET" class="filter-form">
    <div class="ref-box">
        <label>Warn1(%): <input type="number" name="warn1" step="0.1" value="<%= warn1 %>"></label>
        <label>Warn2(%): <input type="number" name="warn2" step="0.1" value="<%= warn2 %>"></label>
        <label>Warn3(%): <input type="number" name="warn3" step="0.1" value="<%= warn3 %>"></label>
    </div>

    <div class="filter-row">
      <label class="field">
        <span>건물</span>
        <select name="building" onchange="this.form.meter.value=''; this.form.submit();">
            <option value="">전체</option>
            <% for (String opt : buildingOptions) { %>
            <option value="<%= opt %>" <%= opt.equals(building) ? "selected" : "" %>><%= opt %></option>
            <% } %>
        </select>
      </label>

      <label class="field">
        <span>용도</span>
        <select name="usage" onchange="this.form.meter.value=''; this.form.submit();">
            <option value="">전체</option>
            <% for (String opt : usageOptions) { %>
            <option value="<%= opt %>" <%= opt.equals(usage) ? "selected" : "" %>><%= opt %></option>
            <% } %>
        </select>
      </label>

      <label class="field">
        <span>Meter</span>
        <select name="meter">
            <option value="">전체</option>
            <% for (String[] opt : meterOptions) { %>
            <option value="<%= opt[0] %>" <%= opt[0].equals(meter) ? "selected" : "" %>><%= opt[1] %></option>
            <% } %>
        </select>
      </label>

      <div class="field period-group">
        <span>기간</span>
        <input type="date" name="startDate" value="<%= startDate %>">
        <input type="time" name="startTime" step="1" value="<%= startTime %>">
        <span>~</span>
        <input type="date" name="endDate" value="<%= endDate %>">
        <input type="time" name="endTime" step="1" value="<%= endTime %>">
      </div>
      <button type="submit" class="query-btn">조회</button>
    </div>
</form>

<%
    List<String> labels = new ArrayList<>();
    List<Float> unbalanceCurrent = new ArrayList<>();
    List<Float> warn1Line = new ArrayList<>();
    List<Float> warn2Line = new ArrayList<>();
    List<Float> warn3Line = new ArrayList<>();

    String dbError = null;
    final float EPS = 0.000001f;

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

                    float ia = rs.getFloat("current_a");
                    float ib = rs.getFloat("current_b");
                    float ic = rs.getFloat("current_c");

                    float iavg = (ia + ib + ic) / 3f;
                    float currentU = 0f;
                    if (Math.abs(iavg) > EPS) {
                        float dmax = Math.max(Math.abs(ia - iavg), Math.max(Math.abs(ib - iavg), Math.abs(ic - iavg)));
                        currentU = (dmax / iavg) * 100f;
                    }
                    unbalanceCurrent.add(currentU);
                }
            }
        }
    } catch (Exception e) {
        dbError = e.getMessage();
    }

    for (int i = 0; i < labels.size(); i++) {
        warn1Line.add(warn1);
        warn2Line.add(warn2);
        warn3Line.add(warn3);
    }

    float maxCurrent = maxFloat(unbalanceCurrent);
    float p95Current = percentileAbs(unbalanceCurrent, 95);

    int cntWarn1 = 0, cntWarn2 = 0, cntWarn3 = 0;
    for (int i = 0; i < unbalanceCurrent.size(); i++) {
        float v = Math.abs(unbalanceCurrent.get(i));
        if (v >= warn1) cntWarn1++;
        if (v >= warn2) cntWarn2++;
        if (v >= warn3) cntWarn3++;
    }

    int n = Math.max(1, labels.size());
    float warn1pct = (cntWarn1 * 100f) / n;
    float warn2pct = (cntWarn2 * 100f) / n;
    float warn3pct = (cntWarn3 * 100f) / n;
    boolean noData = labels.isEmpty();

    StringBuilder labelsJson = new StringBuilder("[");
    for (int i = 0; i < labels.size(); i++) {
        if (i > 0) labelsJson.append(',');
        labelsJson.append('"').append(escapeJson(labels.get(i))).append('"');
    }
    labelsJson.append(']');

    StringBuilder currentJson = new StringBuilder("[");
    for (int i = 0; i < unbalanceCurrent.size(); i++) {
        if (i > 0) currentJson.append(',');
        currentJson.append(String.format(java.util.Locale.US, "%.6f", unbalanceCurrent.get(i)));
    }
    currentJson.append(']');

    StringBuilder warn1Json = new StringBuilder("[");
    for (int i = 0; i < warn1Line.size(); i++) {
        if (i > 0) warn1Json.append(',');
        warn1Json.append(String.format(java.util.Locale.US, "%.6f", warn1Line.get(i)));
    }
    warn1Json.append(']');

    StringBuilder warn2Json = new StringBuilder("[");
    for (int i = 0; i < warn2Line.size(); i++) {
        if (i > 0) warn2Json.append(',');
        warn2Json.append(String.format(java.util.Locale.US, "%.6f", warn2Line.get(i)));
    }
    warn2Json.append(']');

    StringBuilder warn3Json = new StringBuilder("[");
    for (int i = 0; i < warn3Line.size(); i++) {
        if (i > 0) warn3Json.append(',');
        warn3Json.append(String.format(java.util.Locale.US, "%.6f", warn3Line.get(i)));
    }
    warn3Json.append(']');
%>

<% if (noData) { %>
<div class="empty-box">데이터가 없습니다</div>
<% } %>

<div class="content-row">
  <div class="summary-wrap">
      <h3>요약</h3>
      <div class="summary-meta">
          <span class="badge">Warn1: <%= String.format(java.util.Locale.US, "%.1f", warn1) %>%</span>
          <span class="badge">Warn2: <%= String.format(java.util.Locale.US, "%.1f", warn2) %>%</span>
          <span class="badge">Warn3: <%= String.format(java.util.Locale.US, "%.1f", warn3) %>%</span>
          <span class="badge badge-worst">P95 |불평형| = <%= String.format(java.util.Locale.US, "%.2f", p95Current) %>%</span>
      </div>

      <table class="summary-table">
          <thead>
          <tr>
              <th><span class="th-main">구분</span><span class="th-sub">항목</span></th>
              <th><span class="th-main">Max</span><span class="th-sub">(|%|)</span></th>
              <th><span class="th-main">P95</span><span class="th-sub">|불평형|(%)</span></th>
              <th><span class="th-main">Warn1</span><span class="th-sub">이상(%)</span></th>
              <th><span class="th-main">Warn2</span><span class="th-sub">이상(%)</span></th>
              <th><span class="th-main">Warn3</span><span class="th-sub">이상(%)</span></th>
          </tr>
          </thead>
          <tbody>
          <tr>
              <td>전류 불평형</td>
              <td><%= String.format(java.util.Locale.US, "%.2f", maxCurrent) %></td>
              <td><%= String.format(java.util.Locale.US, "%.2f", p95Current) %></td>
              <td><%= String.format(java.util.Locale.US, "%.1f", warn1pct) %></td>
              <td><%= String.format(java.util.Locale.US, "%.1f", warn2pct) %></td>
              <td><%= String.format(java.util.Locale.US, "%.1f", warn3pct) %></td>
          </tr>
          </tbody>
      </table>

      <div class="summary-note">
        전류 불평형율(NEMA-style) = max(|Ix - Iavg|) / Iavg × 100<br/>
        기준 전류: current_a / current_b / current_c
      </div>

      <% if (dbError != null) { %>
        <div class="summary-error">DB 오류: <%= dbError %></div>
      <% } %>
  </div>

  <div class="chart-container">
      <div class="chart-stack">
          <div class="chart-box">
              <h3 class="chart-title">전류 불평형 (%)</h3>
              <div id="chartCurrent" class="chart-inner"></div>
          </div>
      </div>
  </div>
</div>

<script>
  const labels = <%= labelsJson.toString() %>;
  const currentUnb = <%= currentJson.toString() %>;
  const warn1Arr = <%= warn1Json.toString() %>;
  const warn2Arr = <%= warn2Json.toString() %>;
  const warn3Arr = <%= warn3Json.toString() %>;
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
  const currentPlot = pickByIndex(currentUnb, sampleIdx);
  const warn1Plot = pickByIndex(warn1Arr, sampleIdx);
  const warn2Plot = pickByIndex(warn2Arr, sampleIdx);
  const warn3Plot = pickByIndex(warn3Arr, sampleIdx);

  function fmt2(v) {
    const n = Number(v);
    return Number.isFinite(n) ? n.toFixed(2) : '-';
  }

  const chart = echarts.init(document.getElementById('chartCurrent'));
  chart.setOption({
    tooltip: {
      trigger: 'axis',
      formatter: function(params) {
        if (!params || !params.length) return '';
        const lines = [params[0].axisValueLabel || params[0].axisValue || ''];
        params.forEach(function(p) {
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
      {
        name: '전류 불평형',
        type: 'line',
        data: currentPlot,
        animation: false,
        showSymbol: false,
        sampling: 'lttb',
        progressive: 2000,
        progressiveThreshold: 5000,
        lineStyle: { color: '#c92a2a', width: 2 }
      },
      {
        name: 'Warn1',
        type: 'line',
        data: warn1Plot,
        showSymbol: false,
        lineStyle: { type:'dashed', width:1, color:'#0f766e' },
        tooltip: { show: false }
      },
      {
        name: 'Warn2',
        type: 'line',
        data: warn2Plot,
        showSymbol: false,
        lineStyle: { type:'dashed', width:1, color:'#b08900' },
        tooltip: { show: false }
      },
      {
        name: 'Warn3',
        type: 'line',
        data: warn3Plot,
        showSymbol: false,
        lineStyle: { type:'dashed', width:1, color:'#9c1111' },
        tooltip: { show: false }
      }
    ]
  });

  window.addEventListener('resize', () => { chart.resize(); });
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
<%
    }
%>
</body>
</html>
