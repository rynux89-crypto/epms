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
    // ===== 湲곕낯 ?뚮씪誘명꽣 ?명똿 (variation_ves.jsp? ?숈씪??UX) =====
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

    // Thresholds (%)
    // Fixed criteria
    float warn1 = 1f;
    float warn2 = 2f;
    float warn3 = 3f;

    // ?듭뀡 紐⑸줉 (variation_ves.jsp? ?숈씪)
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
    <title>전압 불평형 분석</title>
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
      .ref-box input[type="number"]{ width: 110px; }

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
        .content-row .chart-container { height: 640px; }
      }
    </style>
</head>
<body>
<div class="title-bar">
    <h2>🔀 전압 불평형 분석 (상전압 AN/BN/CN, 선간전압 AB/BC/CA)</h2>
    <div class="top-actions">
        <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        
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
    // ===== ?곗씠??議고쉶 諛?遺덊룊??怨꾩궛 =====
    List<String> labels = new ArrayList<>();

    List<Float> unbPhase = new ArrayList<>(); // ?곸쟾??遺덊룊??%)
    List<Float> unbLine = new ArrayList<>();  // ?좉컙?꾩븬 遺덊룊??%)

    List<Float> phaseWarn2Line = new ArrayList<>();
    List<Float> phaseWarn3Line = new ArrayList<>();
    List<Float> lineWarn1Line = new ArrayList<>();

    String dbError = null;
    final float EPS = 0.000001f;

    try {
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT measured_at, voltage_an, voltage_bn, voltage_cn, voltage_ab, voltage_bc, voltage_ca ")
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

                    float va = rs.getFloat("voltage_an");
                    float vb = rs.getFloat("voltage_bn");
                    float vc = rs.getFloat("voltage_cn");

                    float vab = rs.getFloat("voltage_ab");
                    float vbc = rs.getFloat("voltage_bc");
                    float vca = rs.getFloat("voltage_ca");

                    // ?곸쟾??遺덊룊??NEMA-style)
                    float vavgP = (va + vb + vc) / 3f;
                    float phaseU = 0f;
                    if (Math.abs(vavgP) > EPS) {
                        float dmax = Math.max(Math.abs(va - vavgP), Math.max(Math.abs(vb - vavgP), Math.abs(vc - vavgP)));
                        phaseU = (dmax / vavgP) * 100f;
                    }

                    // ?좉컙?꾩븬 遺덊룊??NEMA-style)
                    float vavgL = (vab + vbc + vca) / 3f;
                    float lineU = 0f;
                    if (Math.abs(vavgL) > EPS) {
                        float dmax = Math.max(Math.abs(vab - vavgL), Math.max(Math.abs(vbc - vavgL), Math.abs(vca - vavgL)));
                        lineU = (dmax / vavgL) * 100f;
                    }

                    unbPhase.add(phaseU);
                    unbLine.add(lineU);
                }
            }
        }
    } catch (Exception e) {
        dbError = e.getMessage();
    }

    for (int i = 0; i < labels.size(); i++) {
        phaseWarn2Line.add(warn2);
        phaseWarn3Line.add(warn3);
        lineWarn1Line.add(warn1);
    }

    // ?붿빟 ?듦퀎
    float maxPhase = maxFloat(unbPhase);
    float maxLine = maxFloat(unbLine);
    float p95Phase = percentileAbs(unbPhase, 95);
    float p95Line = percentileAbs(unbLine, 95);

    String worst = (p95Phase >= p95Line) ? "phase" : "line";
    float worstScore = (p95Phase >= p95Line) ? p95Phase : p95Line;

    // Threshold exceedance counts
    int cntPhase2 = 0, cntPhase3 = 0, cntLine1 = 0;
    for (int i = 0; i < unbPhase.size(); i++) {
        float v = Math.abs(unbPhase.get(i));
        if (v >= warn2) cntPhase2++;
        if (v >= warn3) cntPhase3++;
    }
    for (int i = 0; i < unbLine.size(); i++) {
        float v = Math.abs(unbLine.get(i));
        if (v >= warn1) cntLine1++;
    }

    int n = Math.max(1, labels.size());
    float phase2pct = (cntPhase2 * 100f) / n;
    float phase3pct = (cntPhase3 * 100f) / n;
    float line1pct = (cntLine1 * 100f) / n;
    boolean noData = labels.isEmpty();

    // ===== JSON 臾몄옄???앹꽦 (stream/toList 誘몄궗?? ?댁쁺 ?섍꼍 ?명솚?? =====
    StringBuilder labelsJson = new StringBuilder("[");
    for (int i = 0; i < labels.size(); i++) {
        if (i > 0) labelsJson.append(',');
        labelsJson.append('"').append(escapeJson(labels.get(i))).append('"');
    }
    labelsJson.append(']');

    StringBuilder phaseJson = new StringBuilder("[");
    for (int i = 0; i < unbPhase.size(); i++) {
        if (i > 0) phaseJson.append(',');
        phaseJson.append(String.format(java.util.Locale.US, "%.6f", unbPhase.get(i)));
    }
    phaseJson.append(']');

    StringBuilder lineJson = new StringBuilder("[");
    for (int i = 0; i < unbLine.size(); i++) {
        if (i > 0) lineJson.append(',');
        lineJson.append(String.format(java.util.Locale.US, "%.6f", unbLine.get(i)));
    }
    lineJson.append(']');

    StringBuilder phaseWarn2Json = new StringBuilder("[");
    for (int i = 0; i < phaseWarn2Line.size(); i++) {
        if (i > 0) phaseWarn2Json.append(',');
        phaseWarn2Json.append(String.format(java.util.Locale.US, "%.6f", phaseWarn2Line.get(i)));
    }
    phaseWarn2Json.append(']');

    StringBuilder phaseWarn3Json = new StringBuilder("[");
    for (int i = 0; i < phaseWarn3Line.size(); i++) {
        if (i > 0) phaseWarn3Json.append(',');
        phaseWarn3Json.append(String.format(java.util.Locale.US, "%.6f", phaseWarn3Line.get(i)));
    }
    phaseWarn3Json.append(']');

    StringBuilder lineWarn1Json = new StringBuilder("[");
    for (int i = 0; i < lineWarn1Line.size(); i++) {
        if (i > 0) lineWarn1Json.append(',');
        lineWarn1Json.append(String.format(java.util.Locale.US, "%.6f", lineWarn1Line.get(i)));
    }
    lineWarn1Json.append(']');
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
          <span class="badge">상전압 기준: Warn2/3, 선간 기준: Warn1</span>
          <span class="badge badge-worst">Worst: <%= worst %> (P95 |Unbalance| = <%= String.format(java.util.Locale.US, "%.2f", worstScore) %>%)</span>
      </div>

      <table class="summary-table">
          <thead>
          <tr>
              <th><span class="th-main">구분</span><span class="th-sub">항목</span></th>
              <th><span class="th-main">Max</span><span class="th-sub">(|%|)</span></th>
              <th><span class="th-main">P95</span><span class="th-sub">|불평형|(%)</span></th>
              <th><span class="th-main">Warn2/1</span><span class="th-sub">이상(%)</span></th>
              <th><span class="th-main">Warn3</span><span class="th-sub">이상(%)</span></th>
          </tr>
          </thead>
          <tbody>
          <tr>
              <td>상전압 불평형</td>
              <td><%= String.format(java.util.Locale.US, "%.2f", maxPhase) %></td>
              <td><%= String.format(java.util.Locale.US, "%.2f", p95Phase) %></td>
              <td><%= String.format(java.util.Locale.US, "%.1f", phase2pct) %></td>
              <td><%= String.format(java.util.Locale.US, "%.1f", phase3pct) %></td>
          </tr>
          <tr>
              <td>선간전압 불평형</td>
              <td><%= String.format(java.util.Locale.US, "%.2f", maxLine) %></td>
              <td><%= String.format(java.util.Locale.US, "%.2f", p95Line) %></td>
              <td><%= String.format(java.util.Locale.US, "%.1f", line1pct) %></td>
              <td>-</td>
          </tr>
          </tbody>
      </table>

      <div class="summary-note">
        불평형율(NEMA-style) = max(|Vx - Vavg|) / Vavg × 100<br/>
        상전압: voltage_an/bn/cn, 선간전압: voltage_ab/bc/ca
      </div>

      <% if (dbError != null) { %>
        <div class="summary-error">DB 오류: <%= dbError %></div>
      <% } %>
  </div>

  <div class="chart-container">
      <div class="chart-stack">
          <div class="chart-box">
              <h3 class="chart-title">상전압 불평형 (%)</h3>
              <div id="chartPhase" class="chart-inner"></div>
          </div>
          <div class="chart-box">
              <h3 class="chart-title">선간전압 불평형 (%)</h3>
              <div id="chartLine" class="chart-inner"></div>
          </div>
      </div>
  </div>
</div>

<script>
  const labels   = <%= labelsJson.toString() %>;
  const phaseUnb = <%= phaseJson.toString() %>;
  const lineUnb  = <%= lineJson.toString() %>;
  const phaseWarn2Arr = <%= phaseWarn2Json.toString() %>;
  const phaseWarn3Arr = <%= phaseWarn3Json.toString() %>;
  const lineWarn1Arr = <%= lineWarn1Json.toString() %>;
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
  const phaseUnbPlot = pickByIndex(phaseUnb, sampleIdx);
  const lineUnbPlot = pickByIndex(lineUnb, sampleIdx);
  const phaseWarn2Plot = pickByIndex(phaseWarn2Arr, sampleIdx);
  const phaseWarn3Plot = pickByIndex(phaseWarn3Arr, sampleIdx);
  const lineWarn1Plot = pickByIndex(lineWarn1Arr, sampleIdx);
  function fmt2(v) {
    const n = Number(v);
    return Number.isFinite(n) ? n.toFixed(2) : '-';
  }

  function mkOption(seriesName, data, color, warnA, warnB, warnAName, warnBName, showSlider){
    const series = [
      {
        name: seriesName,
        type:'line',
        data: data,
        animation: false,
        showSymbol: false,
        sampling: 'lttb',
        progressive: 2000,
        progressiveThreshold: 5000,
        lineStyle: { color: color, width: 2 }
      }
    ];
    if (warnA) series.push({ name: warnAName || 'Warn', type:'line', data: warnA, showSymbol:false, lineStyle:{ type:'dashed', width: 1, color: '#b08900' }, tooltip:{ show:false } });
    if (warnB) series.push({ name: warnBName || 'Warn', type:'line', data: warnB, showSymbol:false, lineStyle:{ type:'dashed', width: 1, color: '#9c1111' }, tooltip:{ show:false } });
    return {
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
      grid: { left: 50, right: 20, top: 40, bottom: showSlider ? 80 : 36, containLabel: true },
      xAxis: { type: 'category', data: labelsPlot, axisLabel: { interval: 'auto' } },
      yAxis: { type: 'value', scale: true, axisLabel: { formatter: '{value} %' } },
      dataZoom: showSlider ? [
        { type: 'inside', xAxisIndex: 0, filterMode: 'none' },
        { type: 'slider', xAxisIndex: 0, filterMode: 'none', height: 24, bottom: 16 }
      ] : [
        { type: 'inside', xAxisIndex: 0, filterMode: 'none' }
      ],
      series: series
    };
  }

  const chart1 = echarts.init(document.getElementById('chartPhase'));
  const chart2 = echarts.init(document.getElementById('chartLine'));

  chart1.setOption(mkOption('상전압 불평형', phaseUnbPlot, '#c92a2a', phaseWarn2Plot, phaseWarn3Plot, 'Warn2', 'Warn3', false));
  chart2.setOption(mkOption('선간전압 불평형', lineUnbPlot, '#1864ab', lineWarn1Plot, null, 'Warn1', null, true));

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

  function syncZoom(source, target, evt) {
    if (window.__unbalanceSyncingZoom) return;
    const zoom = extractZoomWindow(evt);
    if (!zoom) return;
    window.__unbalanceSyncingZoom = true;
    try {
      target.dispatchAction(Object.assign({ type: 'dataZoom' }, zoom));
    } finally {
      window.__unbalanceSyncingZoom = false;
    }
  }

  chart1.on('dataZoom', function(evt){ syncZoom(chart1, chart2, evt); });
  chart2.on('dataZoom', function(evt){ syncZoom(chart2, chart1, evt); });

  window.addEventListener('resize', () => { chart1.resize(); chart2.resize(); });
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
