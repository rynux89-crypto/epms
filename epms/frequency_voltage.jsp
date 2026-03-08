<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page import="com.fasterxml.jackson.databind.ObjectMapper" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconn.jsp" %>

<%!
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
    private static float avgFloat(List<Float> a) {
        if (a == null || a.isEmpty()) return 0f;
        float s = 0f;
        for (float v : a) s += v;
        return s / a.size();
    }
    private static float percentileAbs(List<Float> a, double p) {
        if (a == null || a.isEmpty()) return 0f;
        ArrayList<Float> b = new ArrayList<>(a.size());
        for (float v : a) b.add(Math.abs(v));
        Collections.sort(b);
        if (p <= 0) return b.get(0);
        if (p >= 100) return b.get(b.size() - 1);
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

    List<String> labels = new ArrayList<>();
    List<Float> freqRaw = new ArrayList<>();
    List<Float> vabRaw = new ArrayList<>();
    List<Float> vbcRaw = new ArrayList<>();
    List<Float> vcaRaw = new ArrayList<>();

    List<Float> rateAB = new ArrayList<>();
    List<Float> rateBC = new ArrayList<>();
    List<Float> rateCA = new ArrayList<>();
    List<Float> upper = new ArrayList<>();
    List<Float> lower = new ArrayList<>();

    float vabRef = 0f, vbcRef = 0f, vcaRef = 0f;
    final float EPS = 0.000001f;

    try {
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT measured_at, frequency, voltage_ab, voltage_bc, voltage_ca ")
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

                    freqRaw.add(rs.getFloat("frequency"));
                    vabRaw.add(rs.getFloat("voltage_ab"));
                    vbcRaw.add(rs.getFloat("voltage_bc"));
                    vcaRaw.add(rs.getFloat("voltage_ca"));
                }
            }
        }
    } catch (Exception e) {
        out.println("DB 오류: " + e.getMessage());
    }

    if (!vabRaw.isEmpty()) {
        vabRef = avgFloat(vabRaw);
        vbcRef = avgFloat(vbcRaw);
        vcaRef = avgFloat(vcaRaw);

        boolean abSafe = Math.abs(vabRef) > EPS;
        boolean bcSafe = Math.abs(vbcRef) > EPS;
        boolean caSafe = Math.abs(vcaRef) > EPS;

        for (int i = 0; i < labels.size(); i++) {
            float vab = vabRaw.get(i);
            float vbc = vbcRaw.get(i);
            float vca = vcaRaw.get(i);

            rateAB.add(abSafe ? ((vab - vabRef) / vabRef * 100f) : 0f);
            rateBC.add(bcSafe ? ((vbc - vbcRef) / vbcRef * 100f) : 0f);
            rateCA.add(caSafe ? ((vca - vcaRef) / vcaRef * 100f) : 0f);

            upper.add(5f);
            lower.add(-5f);
        }
    }

    float abP95 = percentileAbs(rateAB, 95);
    float bcP95 = percentileAbs(rateBC, 95);
    float caP95 = percentileAbs(rateCA, 95);
    String worst = "Vab";
    float worstScore = abP95;
    if (bcP95 > worstScore) { worst = "Vbc"; worstScore = bcP95; }
    if (caP95 > worstScore) { worst = "Vca"; worstScore = caP95; }

    float freqMin = minFloat(freqRaw);
    float freqMax = maxFloat(freqRaw);
    float freqAvg = avgFloat(freqRaw);

    boolean noData = labels.isEmpty();

    ObjectMapper mapper = new ObjectMapper();
    String jsonLabels = mapper.writeValueAsString(labels);
    String jsonFreq = mapper.writeValueAsString(freqRaw);
    String jsonRateAB = mapper.writeValueAsString(rateAB);
    String jsonRateBC = mapper.writeValueAsString(rateBC);
    String jsonRateCA = mapper.writeValueAsString(rateCA);
    String jsonUpper = mapper.writeValueAsString(upper);
    String jsonLower = mapper.writeValueAsString(lower);
%>
<html>
<head>
    <title>주파수 & 전압 변동율 분석</title>
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
      }
      .summary-meta { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:10px; }
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
      .badge-line { width: 100%; justify-content: flex-start; }
      .badge-worst { background: #ffe9e9; border-color: #ffc6c6; color: #9f1c1c; }
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
        background: #eef3fa;
        color: #274567;
        border-bottom: 1px solid #dbe4ef;
      }
      .summary-table td {
        padding: 7px 6px;
        text-align: center;
        color: #243b53;
        border-bottom: 1px solid #eef2f7;
      }
      .summary-table tbody tr:last-child td { border-bottom: 1px solid #dbe4ef; }
      .content-row { display: flex; gap: 12px; align-items: stretch; }
      .content-row .summary-wrap { flex: 0 0 360px; max-width: 360px; margin: 0; }
      .charts-col { flex: 1 1 auto; min-width: 0; display: grid; grid-template-rows: 1fr 1fr; gap: 12px; }
      .chart-card {
        background: #fff;
        border: 1px solid #dbe7f5;
        border-radius: 14px;
        box-shadow: 0 8px 20px rgba(16,24,40,.06);
        padding: 8px 10px 10px;
        display: flex;
        flex-direction: column;
      }
      .chart-title {
        margin: 2px 2px 8px;
        font-size: 13px;
        font-weight: 800;
        color: #1f3347;
      }
      .chart-box { width: 100%; height: 320px; }
      @media (max-width: 1100px) {
        .content-row { flex-direction: column; }
        .content-row .summary-wrap { max-width: none; }
        .charts-col { grid-template-rows: none; }
        .chart-box { height: 320px; }
      }
    </style>
</head>
<body>
  <div class="title-bar">
      <h2>📈 주파수 & 전압 변동율 분석</h2>
      <div style="display:flex; gap:8px; align-items:center;">
          <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
      </div>
  </div>

  <form method="GET">
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

  <% if (noData) { %>
  <div style="margin:12px 0;padding:10px 12px;border:1px solid #ffd6d6;background:#fff3f3;color:#b42318;border-radius:10px;font-weight:700;">데이터가 없습니다</div>
  <% } %>
  <div class="content-row">
    <div class="summary-wrap">
      <h3>요약</h3>
      <div class="summary-meta">
        <span class="badge badge-line">주파수 평균/최소/최대: <%= String.format(java.util.Locale.US, "%.3f", freqAvg) %> / <%= String.format(java.util.Locale.US, "%.3f", freqMin) %> / <%= String.format(java.util.Locale.US, "%.3f", freqMax) %> Hz</span>
        <span class="badge badge-worst">Worst: <%= worst %> (P95 |변동| = <%= String.format(java.util.Locale.US, "%.2f", worstScore) %>%)</span>
      </div>
      <table class="summary-table">
        <thead>
          <tr>
            <th>항목</th>
            <th>기준전압(V)</th>
            <th>P95 |변동|(%)</th>
          </tr>
        </thead>
        <tbody>
          <tr><td>Vab</td><td><%= String.format(java.util.Locale.US, "%.2f", vabRef) %></td><td><%= String.format(java.util.Locale.US, "%.2f", abP95) %></td></tr>
          <tr><td>Vbc</td><td><%= String.format(java.util.Locale.US, "%.2f", vbcRef) %></td><td><%= String.format(java.util.Locale.US, "%.2f", bcP95) %></td></tr>
          <tr><td>Vca</td><td><%= String.format(java.util.Locale.US, "%.2f", vcaRef) %></td><td><%= String.format(java.util.Locale.US, "%.2f", caP95) %></td></tr>
        </tbody>
      </table>
    </div>

    <div class="charts-col">
      <div class="chart-card">
        <div class="chart-title">주파수 차트</div>
        <div id="frequencyChart" class="chart-box"></div>
      </div>
      <div class="chart-card">
        <div class="chart-title">전압 변동율 차트</div>
        <div id="variationChart" class="chart-box"></div>
      </div>
    </div>
  </div>

  <script>
    const labels = <%= jsonLabels %>;
    const freq = <%= jsonFreq %>;
    const rateAB = <%= jsonRateAB %>;
    const rateBC = <%= jsonRateBC %>;
    const rateCA = <%= jsonRateCA %>;
    const upper = <%= jsonUpper %>;
    const lower = <%= jsonLower %>;

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

    const sampleIdx = buildSampleIndex(labels.length, MAX_POINTS);
    const labelsPlot = pickByIndex(labels, sampleIdx);
    const freqPlot = pickByIndex(freq, sampleIdx);
    const rateABPlot = pickByIndex(rateAB, sampleIdx);
    const rateBCPlot = pickByIndex(rateBC, sampleIdx);
    const rateCAPlot = pickByIndex(rateCA, sampleIdx);
    const upperPlot = pickByIndex(upper, sampleIdx);
    const lowerPlot = pickByIndex(lower, sampleIdx);

    const freqDom = document.getElementById('frequencyChart');
    const varDom = document.getElementById('variationChart');
    const freqChart = echarts.init(freqDom);
    const varChart = echarts.init(varDom);
    const f2 = (v) => (Number.isFinite(+v) ? (+v).toFixed(2) : '0.00');

    const freqOption = {
      tooltip: {
        trigger: 'axis',
        formatter: function(params){
          if (!params || !params.length) return '';
          let html = params[0].axisValue + '<br/>';
          for (let i = 0; i < params.length; i++) {
            html += params[i].marker + params[i].seriesName + ': ' + f2(params[i].value) + ' Hz<br/>';
          }
          return html;
        }
      },
      legend: { top: 0, data: ['주파수'] },
      grid: { left: 55, right: 24, top: 34, bottom: 70, containLabel: true },
      xAxis: { type: 'category', data: labelsPlot, axisLabel: { interval: 'auto' } },
      yAxis: { type: 'value', name: '주파수 (Hz)', scale: true, axisLabel: { formatter: function(v){ return f2(v) + ' Hz'; } } },
      dataZoom: [
        { id: 'dz-inside', type: 'inside', xAxisIndex: 0, filterMode: 'none' },
        { id: 'dz-slider', type: 'slider', show: false, xAxisIndex: 0, filterMode: 'none' }
      ],
      series: [
        { name: '주파수', type: 'line', data: freqPlot, showSymbol: false, sampling: 'lttb', lineStyle: { width: 2.2, color: '#1f2937' } }
      ]
    };

    const varOption = {
      tooltip: {
        trigger: 'axis',
        formatter: function(params){
          if (!params || !params.length) return '';
          let html = params[0].axisValue + '<br/>';
          for (let i = 0; i < params.length; i++) {
            const n = params[i].seriesName || '';
            if (n.indexOf('상한') >= 0 || n.indexOf('하한') >= 0) continue;
            html += params[i].marker + n + ': ' + f2(params[i].value) + ' %<br/>';
          }
          return html;
        }
      },
      legend: { top: 0 },
      grid: { left: 55, right: 24, top: 34, bottom: 70, containLabel: true },
      xAxis: { type: 'category', data: labelsPlot, axisLabel: { interval: 'auto' } },
      yAxis: { type: 'value', name: '전압 변동율 (%)', scale: true, axisLabel: { formatter: function(v){ return f2(v) + ' %'; } } },
      dataZoom: [
        { id: 'dz-inside', type: 'inside', xAxisIndex: 0, filterMode: 'none' },
        { id: 'dz-slider', type: 'slider', xAxisIndex: 0, filterMode: 'none', height: 24, bottom: 16 }
      ],
      series: [
        { name: 'Vab 변동율', type: 'line', data: rateABPlot, showSymbol: false, sampling: 'lttb', lineStyle: { width: 2, color: '#ff6b6b' } },
        { name: 'Vbc 변동율', type: 'line', data: rateBCPlot, showSymbol: false, sampling: 'lttb', lineStyle: { width: 2, color: '#4dabf7' } },
        { name: 'Vca 변동율', type: 'line', data: rateCAPlot, showSymbol: false, sampling: 'lttb', lineStyle: { width: 2, color: '#51cf66' } },
        { name: '상한 (+5%)', type: 'line', data: upperPlot, showSymbol: false, lineStyle: { type: 'dashed', width: 1 } },
        { name: '하한 (-5%)', type: 'line', data: lowerPlot, showSymbol: false, lineStyle: { type: 'dashed', width: 1 } }
      ]
    };

    freqChart.setOption(freqOption);
    varChart.setOption(varOption);
    echarts.connect([freqChart, varChart]);
    window.addEventListener('resize', () => {
      freqChart.resize();
      varChart.resize();
    });
  </script>

  <footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
