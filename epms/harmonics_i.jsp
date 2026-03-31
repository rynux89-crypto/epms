<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*, java.time.format.*" %>
<%@ page import="com.fasterxml.jackson.databind.ObjectMapper" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>

<%
try (Connection conn = openDbConnection()) {
    // 湲곌컙 珥덇린??
    LocalDate today = LocalDate.now();
    LocalDate yesterday = today;

    // 1. ?뚮씪誘명꽣 ?섏떊 (?곷떒?쇰줈 ?대룞?섏뿬 ?쇱뿉???좏깮媛??좎????ъ슜)
    String startDate = request.getParameter("startDate");
    String startTime = request.getParameter("startTime");
    String endDate = request.getParameter("endDate");
    String endTime = request.getParameter("endTime");

    // 媛믪씠 ?놁쑝硫?湲곕낯媛믪쑝濡??ㅼ젙
    if (startDate == null || startDate.trim().isEmpty()) { startDate = yesterday.toString(); }  // "YYYY-MM-DD"
    if (endDate == null || endDate.trim().isEmpty()) { endDate = today.toString(); }
    if (startTime == null || startTime.isEmpty()) { startTime = "00:00:00"; }
    if (endTime == null || endTime.isEmpty()) {  endTime = "23:59:59"; }

    // meter 異붽?
    String meter = "1";   // 湲곕낯媛믪? "1"
    String paramMeter = request.getParameter("meter");

    if (paramMeter != null && !paramMeter.trim().isEmpty()) {
        meter = paramMeter;
    }
    String building = request.getParameter("building");
    String usage = request.getParameter("usage");

    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String[]> meterOptions = new ArrayList<>(); // [id, name]

    try {
        //Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
        try (Statement stmt = conn.createStatement()) {
            try (ResultSet rs = stmt.executeQuery("SELECT DISTINCT building_name FROM meters WHERE building_name IS NOT NULL ORDER BY building_name")) {
                while (rs.next()) buildingOptions.add(rs.getString(1).trim());
            }
            try (ResultSet rs = stmt.executeQuery("SELECT DISTINCT usage_type FROM meters WHERE usage_type IS NOT NULL ORDER BY usage_type")) {
                while (rs.next()) usageOptions.add(rs.getString(1).trim());
            }
        }
        StringBuilder meterSql = new StringBuilder("SELECT meter_id, name FROM meters WHERE 1=1 ");
        meterSql.append("AND (UPPER(name) LIKE '%VCB%' OR UPPER(name) LIKE '%ACB%') ");
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
                while (rsMeter.next()) {
                    meterOptions.add(new String[]{ rsMeter.getString("meter_id"), rsMeter.getString("name") });
                }
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
    } catch(Exception e) { e.printStackTrace(); }
%>
<html>
<head>
    <title>전류 고조파 분석</title>
    <script src="../js/echarts.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
      .no-data-banner {
        margin: 12px 0;
        padding: 10px 12px;
        border: 1px solid #ffd6d6;
        background: #fff3f3;
        color: #b42318;
        border-radius: 10px;
        font-weight: 700;
      }
    </style>
</head>
<body>
        <div class="title-bar">
            <h2>🎵 전류 고조파 분석</h2>
            <div class="inline-actions">
                <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'" >EPMS 홈</button>
                <button class="back-btn" onclick="goToHarmonics('v')" >전압 고조파 분석</button>
            </div>
        </div>
<form method="GET">
    건물: 
    <select name="building" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for(String opt : buildingOptions) { %>
            <option value="<%= opt %>" <%= opt.equals(building) ? "selected" : "" %>><%= opt %></option>
        <% } %>
    </select>

    용도: 
    <select name="usage" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for(String opt : usageOptions) { %>
            <option value="<%= opt %>" <%= opt.equals(usage) ? "selected" : "" %>><%= opt %></option>
        <% } %>
    </select>

    Meter:
    <select name="meter">
        <option value="">전체</option>
        <% for(String[] opt : meterOptions) { %>
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
    List<Float> thdA = new ArrayList<>(), thdB = new ArrayList<>(), thdC = new ArrayList<>();
    List<String> meters = new ArrayList<>();
    List<String> harmonics = new ArrayList<>();

    try {
        String sql = "SELECT meter_id, harmonic_id, measured_at, thd_current_a, thd_current_b, thd_current_c FROM vw_harmonic_measurements" +
                    " WHERE measured_at BETWEEN '" + startDate + " " + startTime +  "' AND '" + endDate + " " + endTime + "'";        

        if (building != null && !building.isEmpty()) sql += " AND building_name = '" + building + "'";
        if (usage != null && !usage.isEmpty()) sql += " AND usage_type = '" + usage + "'";
        if (meter != null && !meter.isEmpty()) sql += " AND meter_id = '" + meter + "'";
        sql += " Order by measured_at asc ";

        PreparedStatement ps = conn.prepareStatement(sql);
        
        //out.println(sql);

        ResultSet rs = ps.executeQuery();
        while (rs.next()) {
            if (startDate.equals(endDate) ) {
                labels.add(rs.getTimestamp("measured_at").toString().substring(11,16));
            }else {
                labels.add(rs.getTimestamp("measured_at").toString().substring(0,16));
            }

            thdA.add(rs.getFloat("thd_current_a"));
            thdB.add(rs.getFloat("thd_current_b"));
            thdC.add(rs.getFloat("thd_current_c"));

            meters.add(rs.getString("meter_id"));
            harmonics.add(rs.getString("harmonic_id"));

        }
    } catch (Exception e) { 
        if(startDate != null) out.println("DB 오류: " + e.getMessage()); 
    }

    ObjectMapper mapper = new ObjectMapper();
    String jsonLabels = mapper.writeValueAsString(labels);
    String jsonthdA = mapper.writeValueAsString(thdA);
    String jsonthdB = mapper.writeValueAsString(thdB);
    String jsonthdC = mapper.writeValueAsString(thdC);
    String jsonMeters = mapper.writeValueAsString(meters);
    String jsonHarmonics = mapper.writeValueAsString(harmonics);
    boolean noData = labels.isEmpty();

%>

<% if (noData) { %>
<div class="no-data-banner">데이터가 없습니다</div>
<% } %>

<div class="chart-container">
  <!-- ECharts??canvas ???div -->
  <div id="thdChart" style="width:100%; height:100%;"></div>
</div>

<script>
const meter = "<%= meter != null ? meter : "" %>";
const building = "<%= building != null ? building : "" %>";
const usage    = "<%= usage != null ? usage : "" %>";
const startDate = "<%= startDate != null ? startDate : "" %>";
const startTime = "<%= startTime != null ? startTime : "" %>";
const endDate = "<%= endDate != null ? endDate : "" %>";
const endTime = "<%= endTime != null ? endTime : "" %>";

function buildHarmonicsUrl(targetPath) {
  const qs = new URLSearchParams({
    meter: meter || '',
    building: building || '',
    usage: usage || '',
    startDate: startDate || '',
    startTime: startTime || '',
    endDate: endDate || '',
    endTime: endTime || ''
  });
  return targetPath + '?' + qs.toString();
}

function goToHarmonics(mode) {
  const targetPath = mode === 'i' ? '/epms/harmonics_i.jsp' : '/epms/harmonics_v.jsp';
  window.location.href = buildHarmonicsUrl(targetPath);
}

const labels = <%= jsonLabels %>;
const thdA = <%= jsonthdA %>;
const thdB = <%= jsonthdB %>;
const thdC = <%= jsonthdC %>;
const meterIds = <%= jsonMeters %>;
const harmonicIds = <%= jsonHarmonics %>;

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
const thdAPlot = pickByIndex(thdA, sampleIdx);
const thdBPlot = pickByIndex(thdB, sampleIdx);
const thdCPlot = pickByIndex(thdC, sampleIdx);
const meterIdsPlot = pickByIndex(meterIds, sampleIdx);
const harmonicIdsPlot = pickByIndex(harmonicIds, sampleIdx);
const limit20 = Array(labelsPlot.length).fill(20);

const chartDom = document.getElementById('thdChart');
const myChart = echarts.init(chartDom);

function createLargeAreaSeries(name, data, color){
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
    valueFormatter: v => v + ' %'
  },
  legend: { top: 0 },
  grid: { left: 50, right: 20, top: 40, bottom: 80, containLabel: true },
  xAxis: {
    type: 'category',
    data: labelsPlot
  },
  yAxis: {
    type: 'value',
    scale: true,
    axisLabel: { formatter: '{value} %' }
  },
  dataZoom: [
    { type: 'inside', xAxisIndex: 0, filterMode: 'none' },
    { type: 'slider', xAxisIndex: 0, filterMode: 'none', height: 24, bottom: 16 }
  ],
  series: [
    createLargeAreaSeries('THD_i A', thdAPlot, 'orange'),
    createLargeAreaSeries('THD_i B', thdBPlot, 'purple'),
    createLargeAreaSeries('THD_i C', thdCPlot, 'gray'),
    {
      name: '기준값 20%',
      type: 'line',
      data: limit20,
      showSymbol: false,
      lineStyle: { color: 'red', type: 'dashed', width: 1 }
    }
  ]
};

myChart.setOption(option);

// ?대┃ ??harmonic_detail.jsp ?대룞
myChart.on('click', function (params) {
  const index = params.dataIndex;
  const time = labelsPlot[index];
  const meterId = meterIdsPlot[index];
  const harmonicId = harmonicIdsPlot[index];

  const url = "harmonic_detail.jsp?type=harmonics"
        + "&time=" + encodeURIComponent(time)
        + "&building=" + encodeURIComponent(building)
        + "&usage=" + encodeURIComponent(usage)
        + "&meter=" + encodeURIComponent(meter)
        + "&meter_id=" + encodeURIComponent(meterId)
        + "&harmonic_id=" + encodeURIComponent(harmonicId)
        + "&mode=current";

  window.location.href = url;
});

// 由ъ궗?댁쫰 ???
window.addEventListener('resize', () => myChart.resize());
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
<%
} // end try-with-resources
%>
</body>
</html>











