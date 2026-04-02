<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%!
  private static double nz(Double v){ return v==null?0.0:v.doubleValue(); }
  private static final int QUERY_TIMEOUT_SEC = 15;
%>
<%
try (Connection conn = openDbConnection()) {
  LocalDate today=LocalDate.now();
  LocalDate dailyStart=today.minusDays(29);
  YearMonth nowYm=YearMonth.from(today);
  LocalDate monthStart=nowYm.atDay(1);
  YearMonth monthlyStartYm=nowYm.minusMonths(11);
  LocalDate monthlyStart=monthlyStartYm.atDay(1);
  int currentYear=today.getYear();
  int yearlyStartYear=currentYear-4;
  LocalDate yearlyStart=LocalDate.of(yearlyStartYear,1,1);
  java.sql.Date todaySql=java.sql.Date.valueOf(today);
  java.sql.Date dailyStartSql=java.sql.Date.valueOf(dailyStart);
  java.sql.Date monthStartSql=java.sql.Date.valueOf(monthStart);
  java.sql.Date monthlyStartSql=java.sql.Date.valueOf(monthlyStart);
  java.sql.Date yearlyStartSql=java.sql.Date.valueOf(yearlyStart);

  LinkedHashMap<LocalDate,Double> dailyTotals=new LinkedHashMap<>();
  LinkedHashMap<String,Double> monthlyTotals=new LinkedHashMap<>();
  LinkedHashMap<Integer,Double> yearlyTotals=new LinkedHashMap<>();
  LinkedHashMap<String,Double> buildingTotals=new LinkedHashMap<>();
  LinkedHashMap<String,Double> usageTotals=new LinkedHashMap<>();
  LinkedHashMap<String,Integer> openSeverity=new LinkedHashMap<>();
  LinkedHashMap<String,Integer> alarmTypeRatio=new LinkedHashMap<>();
  LinkedHashMap<String,Integer> topMeterAlarmCount=new LinkedHashMap<>();
  int[][] alarmHeat=new int[7][24];
  List<Map<String,Object>> openAlarmRows=new ArrayList<>();
  List<Map<String,Object>> unresolvedTopRows=new ArrayList<>();

  String queryError=null;
  double todayKwh=0.0, monthKwh=0.0, openAlarmCount=0.0, criticalOpenCount=0.0, openAvgHours=0.0, openMaxHours=0.0;
  int new24hCount=0, cleared24hCount=0;

  try{
    for(LocalDate d=dailyStart; !d.isAfter(today); d=d.plusDays(1)) dailyTotals.put(d,0.0);
    for(YearMonth ym=monthlyStartYm; !ym.isAfter(nowYm); ym=ym.plusMonths(1)) monthlyTotals.put(ym.toString(),0.0);
    for(int y=yearlyStartYear; y<=currentYear; y++) yearlyTotals.put(Integer.valueOf(y),0.0);

    try(Statement st=conn.createStatement()){
      st.setQueryTimeout(QUERY_TIMEOUT_SEC);
      st.execute("IF OBJECT_ID('tempdb..#overview_day_diff') IS NOT NULL DROP TABLE #overview_day_diff");
      st.execute("CREATE TABLE #overview_day_diff (meter_id INT NOT NULL, d DATE NOT NULL, day_kwh FLOAT NULL)");
    }

    String populateDayDiffSql=
      "WITH base AS ( " +
      "  SELECT ms.meter_id, CAST(ms.measured_at AS date) AS d, ms.measured_at, CAST(ms.energy_consumed_total AS float) AS energy_total " +
      "  FROM dbo.measurements ms " +
      "  WHERE ms.measured_at >= DATEADD(day,-1,?) AND ms.measured_at < DATEADD(day,1,?) " +
      "), day_last AS ( " +
      "  SELECT meter_id,d,energy_total, ROW_NUMBER() OVER (PARTITION BY meter_id,d ORDER BY measured_at DESC) rn " +
      "  FROM base WHERE energy_total IS NOT NULL " +
      "), day_meter AS ( " +
      "  SELECT meter_id,d,energy_total AS end_total FROM day_last WHERE rn=1 " +
      "), day_diff AS ( " +
      "  SELECT meter_id,d,end_total - LAG(end_total) OVER (PARTITION BY meter_id ORDER BY d) AS day_kwh FROM day_meter " +
      ") " +
      "INSERT INTO #overview_day_diff (meter_id, d, day_kwh) SELECT meter_id, d, day_kwh FROM day_diff";
    try(PreparedStatement ps=conn.prepareStatement(populateDayDiffSql)){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      ps.setDate(1, yearlyStartSql);
      ps.setDate(2, todaySql);
      ps.executeUpdate();
    }
    try(Statement st=conn.createStatement()){
      st.setQueryTimeout(QUERY_TIMEOUT_SEC);
      st.execute("CREATE CLUSTERED INDEX IX_overview_day_diff_d_meter ON #overview_day_diff (d, meter_id)");
    }

    String dailySql="SELECT d, SUM(CASE WHEN day_kwh>=0 THEN day_kwh ELSE 0 END) AS sum_kwh FROM #overview_day_diff WHERE d BETWEEN ? AND ? GROUP BY d ORDER BY d";
    try(PreparedStatement ps=conn.prepareStatement(dailySql)){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      int i=1; ps.setDate(i++,dailyStartSql); ps.setDate(i++,todaySql);
      try(ResultSet rs=ps.executeQuery()){ while(rs.next()){ java.sql.Date dObj=rs.getDate("d"); if(dObj==null) continue; LocalDate d=dObj.toLocalDate(); if(dailyTotals.containsKey(d)) dailyTotals.put(d, rs.getDouble("sum_kwh")); } }
    }

    String monthlySql="SELECT CONVERT(char(7),d,126) AS ym, SUM(CASE WHEN day_kwh>=0 THEN day_kwh ELSE 0 END) AS sum_kwh FROM #overview_day_diff WHERE d BETWEEN ? AND ? GROUP BY CONVERT(char(7),d,126) ORDER BY ym";
    try(PreparedStatement ps=conn.prepareStatement(monthlySql)){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      int i=1; ps.setDate(i++,monthlyStartSql); ps.setDate(i++,todaySql);
      try(ResultSet rs=ps.executeQuery()){ while(rs.next()){ String k=rs.getString("ym"); if(k!=null && monthlyTotals.containsKey(k)) monthlyTotals.put(k, rs.getDouble("sum_kwh")); } }
    }

    String yearlySql="SELECT YEAR(d) AS yy, SUM(CASE WHEN day_kwh>=0 THEN day_kwh ELSE 0 END) AS sum_kwh FROM #overview_day_diff WHERE d BETWEEN ? AND ? GROUP BY YEAR(d) ORDER BY yy";
    try(PreparedStatement ps=conn.prepareStatement(yearlySql)){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      int i=1; ps.setDate(i++,yearlyStartSql); ps.setDate(i++,todaySql);
      try(ResultSet rs=ps.executeQuery()){ while(rs.next()){ Integer yy=Integer.valueOf(rs.getInt("yy")); if(yearlyTotals.containsKey(yy)) yearlyTotals.put(yy, rs.getDouble("sum_kwh")); } }
    }

    String byBuildingSql="SELECT ISNULL(m.building_name,N'(미지정)') AS building_name, SUM(CASE WHEN dd.day_kwh>=0 THEN dd.day_kwh ELSE 0 END) AS sum_kwh FROM #overview_day_diff dd INNER JOIN dbo.meters m ON m.meter_id=dd.meter_id WHERE dd.d BETWEEN ? AND ? GROUP BY ISNULL(m.building_name,N'(미지정)') ORDER BY sum_kwh DESC";
    try(PreparedStatement ps=conn.prepareStatement(byBuildingSql)){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      int i=1; ps.setDate(i++,monthStartSql); ps.setDate(i++,todaySql);
      try(ResultSet rs=ps.executeQuery()){ while(rs.next()) buildingTotals.put(rs.getString("building_name"), rs.getDouble("sum_kwh")); }
    }

    String byUsageSql="SELECT ISNULL(m.usage_type,N'(미지정)') AS usage_type, SUM(CASE WHEN dd.day_kwh>=0 THEN dd.day_kwh ELSE 0 END) AS sum_kwh FROM #overview_day_diff dd INNER JOIN dbo.meters m ON m.meter_id=dd.meter_id WHERE dd.d BETWEEN ? AND ? GROUP BY ISNULL(m.usage_type,N'(미지정)') ORDER BY sum_kwh DESC";
    try(PreparedStatement ps=conn.prepareStatement(byUsageSql)){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      int i=1; ps.setDate(i++,monthStartSql); ps.setDate(i++,todaySql);
      try(ResultSet rs=ps.executeQuery()){ while(rs.next()) usageTotals.put(rs.getString("usage_type"), rs.getDouble("sum_kwh")); }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT ISNULL(severity,'UNKNOWN') AS severity, COUNT(1) AS cnt FROM dbo.vw_alarm_log WHERE cleared_at IS NULL GROUP BY ISNULL(severity,'UNKNOWN')")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      while(rs.next()){ String sev=rs.getString("severity"); int cnt=rs.getInt("cnt"); openSeverity.put(sev, Integer.valueOf(cnt)); openAlarmCount+=cnt; String s=sev==null?"":sev.toUpperCase(java.util.Locale.ROOT); if(s.contains("CRITICAL")||s.contains("HIGH")||s.contains("ALARM")) criticalOpenCount+=cnt; }
      }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT TOP 7 meter_name,alarm_type,severity,triggered_at FROM dbo.vw_alarm_log WHERE cleared_at IS NULL ORDER BY triggered_at DESC")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      while(rs.next()){ Map<String,Object> r=new HashMap<>(); r.put("meter_name",rs.getString("meter_name")); r.put("alarm_type",rs.getString("alarm_type")); r.put("severity",rs.getString("severity")); r.put("triggered_at",rs.getTimestamp("triggered_at")); openAlarmRows.add(r); }
      }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT AVG(CAST(DATEDIFF(SECOND,triggered_at,SYSDATETIME()) AS float))/3600.0 AS avg_h, MAX(CAST(DATEDIFF(SECOND,triggered_at,SYSDATETIME()) AS float))/3600.0 AS max_h FROM dbo.vw_alarm_log WHERE cleared_at IS NULL AND triggered_at IS NOT NULL")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      if(rs.next()){ openAvgHours=rs.getDouble("avg_h"); openMaxHours=rs.getDouble("max_h"); }
      }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT TOP 7 meter_name,alarm_type,severity,DATEDIFF(MINUTE,triggered_at,SYSDATETIME()) AS open_min FROM dbo.vw_alarm_log WHERE cleared_at IS NULL AND triggered_at IS NOT NULL ORDER BY open_min DESC, triggered_at ASC")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      while(rs.next()){ Map<String,Object> r=new HashMap<>(); r.put("meter_name",rs.getString("meter_name")); r.put("alarm_type",rs.getString("alarm_type")); r.put("severity",rs.getString("severity")); r.put("open_min",Integer.valueOf(rs.getInt("open_min"))); unresolvedTopRows.add(r); }
      }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT SUM(CASE WHEN triggered_at>=DATEADD(HOUR,-24,SYSDATETIME()) THEN 1 ELSE 0 END) AS new_24h, SUM(CASE WHEN cleared_at>=DATEADD(HOUR,-24,SYSDATETIME()) THEN 1 ELSE 0 END) AS cleared_24h FROM dbo.vw_alarm_log")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      if(rs.next()){ new24hCount=rs.getInt("new_24h"); cleared24hCount=rs.getInt("cleared_24h"); }
      }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT triggered_at FROM dbo.vw_alarm_log WHERE triggered_at >= DATEADD(DAY,-7,SYSDATETIME()) AND triggered_at IS NOT NULL")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      while(rs.next()){ Timestamp ts=rs.getTimestamp("triggered_at"); if(ts==null) continue; LocalDateTime ldt=ts.toLocalDateTime(); int d=ldt.getDayOfWeek().getValue()-1; int hh=ldt.getHour(); if(d>=0&&d<7&&hh>=0&&hh<24) alarmHeat[d][hh]++; }
      }
    }

    try(PreparedStatement ps=conn.prepareStatement("SELECT TOP 10 ISNULL(meter_name,N'(미지정)') AS meter_name, COUNT(1) AS cnt FROM dbo.vw_alarm_log WHERE triggered_at >= DATEADD(DAY,-30,SYSDATETIME()) GROUP BY ISNULL(meter_name,N'(미지정)') ORDER BY cnt DESC, meter_name")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      while(rs.next()) topMeterAlarmCount.put(rs.getString("meter_name"), Integer.valueOf(rs.getInt("cnt")));
      }
    }

    try(PreparedStatement ps=conn.prepareStatement(
      "SELECT " +
      "  r.rule_code AS alarm_type_grp, " +
      "  COUNT(1) AS cnt " +
      "FROM dbo.alarm_log a " +
      "INNER JOIN dbo.alarm_rule r " +
      "  ON r.rule_id = a.rule_id " +
      "  OR (NULLIF(LTRIM(RTRIM(a.rule_code)), '') IS NOT NULL AND r.rule_code = a.rule_code) " +
      "WHERE a.triggered_at >= DATEADD(DAY,-30,SYSDATETIME()) " +
      "  AND r.enabled = 1 " +
      "GROUP BY r.rule_code " +
      "ORDER BY cnt DESC, alarm_type_grp")){
      ps.setQueryTimeout(QUERY_TIMEOUT_SEC);
      try(ResultSet rs=ps.executeQuery()){
      while(rs.next()) alarmTypeRatio.put(rs.getString("alarm_type_grp"), Integer.valueOf(rs.getInt("cnt")));
      }
    }
  } catch(Exception e){ queryError=e.getMessage(); }

  todayKwh=dailyTotals.getOrDefault(today,0.0);
  for(Double v: monthlyTotals.values()) monthKwh += nz(v);
%>
<!doctype html>
<html>
<head>
  <title>에너지 현황</title>
  <script src="../js/echarts.js"></script>
  <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
  <style>
    :root{--panel-border:#d7e0ea;--panel-shadow:0 10px 24px rgba(15,23,42,.08);--axis:#6b7a90;--grid:#e7edf3;--title:#12263a;--bg-soft:#f7fafc}
    .kpi-grid{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:8px;margin:8px 0}
    .kpi-card{background:#fff;border:1px solid #d9e2ec;border-radius:10px;padding:8px 10px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
    .kpi-label{font-size:11px;color:#486581;margin-bottom:4px}.kpi-value{font-size:18px;font-weight:700;color:#102a43;line-height:1.2}.kpi-sub{font-size:12px;color:#627d98}
    .grid-2{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px}.grid-3{display:grid;grid-template-columns:2fr 2fr 1.4fr;gap:8px;margin-top:8px}
    .panel{background:linear-gradient(180deg,#fff 0%,var(--bg-soft) 100%);border:1px solid var(--panel-border);border-radius:14px;padding:10px 10px 6px;box-shadow:var(--panel-shadow)}.panel h3{font-size:15px;letter-spacing:-.01em;color:var(--title);margin:0 0 8px 0!important}
    .chart-container{margin:0;min-width:0;height:220px;min-height:220px}.chart-container.short{height:184px;min-height:184px}
    .meta-line{font-size:11px;color:#64748b;margin-top:2px}.err-box{margin:10px 0;padding:10px 12px;border-radius:8px;background:#fff1f1;border:1px solid #ffc9c9;color:#b42318;font-size:13px;font-weight:700}
    .alarm-list{margin:0;padding-left:18px;font-size:12px;max-height:160px;overflow:auto}.alarm-list li{margin:4px 0}
    @media (max-width:1200px){.kpi-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.grid-2,.grid-3{grid-template-columns:1fr}.chart-container{height:240px;min-height:240px}.chart-container.short{height:200px;min-height:200px}}
  </style>
</head>
<body>
<div class="title-bar">
  <h2>📌 에너지 현황</h2>
  <div style="display:flex;gap:8px;align-items:center;">
    <label style="font-size:12px;color:#334155;display:flex;align-items:center;gap:4px;"><input type="checkbox" id="autoRefreshOn"> 자동갱신</label>
    <select id="autoRefreshSec" style="font-size:12px;padding:4px 6px;"><option value="30">30초</option><option value="60" selected>60초</option></select>
    <button class="back-btn" onclick="location.href='/epms/energy_manage.jsp'">상세 분석</button>
    <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
  </div>
</div>
<div class="meta-line">전체 현황 화면 | 일: 최근 30일 / 월: 최근 12개월 / 년: 최근 5개년 | 건물/용도 차트 클릭 시 상세 분석으로 이동</div>
<% if(queryError!=null && !queryError.trim().isEmpty()){ %><div class="err-box">조회 오류: <%= h(queryError) %></div><% } %>

<div class="kpi-grid">
  <div class="kpi-card"><div class="kpi-label">금일 사용량 (kWh)</div><div class="kpi-value"><%= String.format(java.util.Locale.US,"%,.1f",todayKwh) %></div><div class="kpi-sub"><%= today.toString() %></div></div>
  <div class="kpi-card"><div class="kpi-label">최근 12개월 누적 (kWh)</div><div class="kpi-value"><%= String.format(java.util.Locale.US,"%,.1f",monthKwh) %></div><div class="kpi-sub"><%= monthlyStartYm.toString() %> ~ <%= nowYm.toString() %></div></div>
  <div class="kpi-card"><div class="kpi-label">현재 오픈 알람</div><div class="kpi-value"><%= String.format(java.util.Locale.US,"%,.0f",openAlarmCount) %></div><div class="kpi-sub">cleared_at IS NULL</div></div>
  <div class="kpi-card"><div class="kpi-label">주의 이상 알람</div><div class="kpi-value"><%= String.format(java.util.Locale.US,"%,.0f",criticalOpenCount) %></div><div class="kpi-sub">ALARM/HIGH/CRITICAL</div></div>
  <div class="kpi-card"><div class="kpi-label">24시간 신규 알람</div><div class="kpi-value"><%= String.format(java.util.Locale.US,"%,d",new24hCount) %></div><div class="kpi-sub">최근 24시간 발생</div></div>
  <div class="kpi-card"><div class="kpi-label">24시간 해제 알람</div><div class="kpi-value"><%= String.format(java.util.Locale.US,"%,d",cleared24hCount) %></div><div class="kpi-sub">최근 24시간 복구</div></div>
</div>

<div class="grid-2"><div class="panel"><h3>건물별 사용량 (당월 누적)</h3><div id="buildingChart" class="chart-container short"></div></div><div class="panel"><h3>용도별 사용량 (당월 누적)</h3><div id="usageChart" class="chart-container short"></div></div></div>
<div class="grid-3"><div class="panel"><h3>일별 사용량 (최근 30일)</h3><div id="dailyChart" class="chart-container"></div></div><div class="panel"><h3>월별 사용량 (최근 12개월)</h3><div id="monthlyChart" class="chart-container"></div></div><div class="panel"><h3>년도별 사용량 (최근 5개년)</h3><div id="yearlyChart" class="chart-container"></div></div></div>
<div class="grid-2">
  <div class="panel"><h3>미복구 Top 7 (지속시간)</h3><ul class="alarm-list"><% if(unresolvedTopRows.isEmpty()){ %><li>현재 오픈 알람이 없습니다.</li><% } else { for(Map<String,Object> r: unresolvedTopRows){ %><li><strong><%= h(String.valueOf(r.get("severity"))) %></strong> | <%= h(String.valueOf(r.get("meter_name"))) %> | <%= h(String.valueOf(r.get("alarm_type"))) %> | <%= String.format(java.util.Locale.US,"%,.1f",((Integer)r.get("open_min")).doubleValue()/60.0) %>h</li><% }} %></ul></div>
  <div class="panel"><h3>최근 오픈 알람</h3><ul class="alarm-list"><% if(openAlarmRows.isEmpty()){ %><li>현재 오픈 알람이 없습니다.</li><% } else { for(Map<String,Object> r: openAlarmRows){ %><li><strong><%= h(String.valueOf(r.get("severity"))) %></strong> | <%= h(String.valueOf(r.get("meter_name"))) %> | <%= h(String.valueOf(r.get("alarm_type"))) %> | <%= h(String.valueOf(r.get("triggered_at"))) %></li><% }} %></ul></div>
</div>
<div class="grid-3"><div class="panel"><h3>알람 발생 밀집 시간대 (최근 7일)</h3><div id="alarmHeatChart" class="chart-container short"></div></div><div class="panel"><h3>계측기별 알람 빈도 Top 10 (최근 30일)</h3><div id="alarmTopMeterChart" class="chart-container short"></div></div><div class="panel"><h3>알람 유형별 비중 (최근 30일)</h3><div id="alarmTypeChart" class="chart-container short"></div></div></div>

<script>
function fmtNum(v,d){const n=Number(v);if(!Number.isFinite(n))return '-';return n.toLocaleString('en-US',{minimumFractionDigits:d,maximumFractionDigits:d});}
function makeAxisTooltip(params,unit,frac){if(!params||!params.length)return '';const lines=[params[0].axisValue||''];params.forEach(function(p){lines.push(p.marker+p.seriesName+': '+fmtNum(p.value,frac)+' '+unit);});return lines.join('<br/>');}
const chartPalette={blue:'#2f6fed',teal:'#17a2b8',green:'#20a46b',orange:'#f08c2e',red:'#dc5a5a',gold:'#d9a441',slate:'#64748b',violet:'#6e59cf'};
const piePalette=['#2f6fed','#20a46b','#f08c2e','#dc5a5a','#6e59cf','#17a2b8','#d9a441','#94a3b8'];
const axisStyle={axisLine:{show:false},axisTick:{show:false},axisLabel:{color:'#6b7a90',fontSize:11}};
const tooltipTextStyle={fontSize:12,color:'#e8eef5',fontWeight:500,lineHeight:18};
const tooltipBoxStyle={backgroundColor:'rgba(30,41,59,.88)',borderColor:'#d8e1eb',borderWidth:1,padding:[9,11],textStyle:tooltipTextStyle,extraCssText:'box-shadow:0 8px 18px rgba(15,23,42,.16);border-radius:10px;white-space:normal;'};
function makeValueAxis(unitFrac){return {type:'value',axisLine:{show:false},axisTick:{show:false},axisLabel:{color:'#6b7a90',fontSize:11,formatter:v=>fmtNum(v,unitFrac)},splitLine:{lineStyle:{color:'#e7edf3'}}};}
function makeCategoryAxis(data, extra){return Object.assign({type:'category',data:data,axisLine:{lineStyle:{color:'#dbe4ee'}},axisTick:{show:false},axisLabel:{color:'#6b7a90',fontSize:11}}, extra||{});}
function makeEmptyGraphic(text){return {type:'text',left:'center',top:'middle',style:{text:text,fill:'#7b8794',fontSize:13,fontWeight:600}};}
const dailyLabels=[<%
boolean first=true;
for(LocalDate d: dailyTotals.keySet()){ if(!first) out.print(','); out.print("\""+jsq(d.toString())+"\""); first=false; }
%>];
const dailyValues=[<%
first=true; for(Double v: dailyTotals.values()){ if(!first) out.print(','); out.print(String.format(java.util.Locale.US,"%.6f",nz(v))); first=false; }
%>];
const monthlyLabels=[<%
first=true; for(String k: monthlyTotals.keySet()){ if(!first) out.print(','); out.print("\""+jsq(k)+"\""); first=false; }
%>];
const monthlyValues=[<%
first=true; for(Double v: monthlyTotals.values()){ if(!first) out.print(','); out.print(String.format(java.util.Locale.US,"%.6f",nz(v))); first=false; }
%>];
const yearlyLabels=[<%
first=true; for(Integer y: yearlyTotals.keySet()){ if(!first) out.print(','); out.print("\""+y+"\""); first=false; }
%>];
const yearlyValues=[<%
first=true; for(Double v: yearlyTotals.values()){ if(!first) out.print(','); out.print(String.format(java.util.Locale.US,"%.6f",nz(v))); first=false; }
%>];
const buildingNames=[<%
first=true; for(String k: buildingTotals.keySet()){ if(!first) out.print(','); out.print("\""+jsq(k)+"\""); first=false; }
%>];
const buildingVals=[<%
first=true; for(Double v: buildingTotals.values()){ if(!first) out.print(','); out.print(String.format(java.util.Locale.US,"%.6f",nz(v))); first=false; }
%>];
const usagePie=[<%
first=true; for(Map.Entry<String,Double> e: usageTotals.entrySet()){ if(!first) out.print(','); out.print("{name:\""+jsq(e.getKey())+"\",value:"+String.format(java.util.Locale.US,"%.6f",nz(e.getValue()))+"}"); first=false; }
%>];
const heatDays=['월','화','수','목','금','토','일'];
const heatHours=Array.from({length:24},(_,i)=>String(i));
const heatData=[<%
boolean firstHeat=true;
for(int d=0; d<7; d++){ for(int hh=0; hh<24; hh++){ if(!firstHeat) out.print(','); out.print("["+hh+","+d+","+alarmHeat[d][hh]+"]"); firstHeat=false; }}
%>];
const topMeterNames=[<%
first=true; for(String k: topMeterAlarmCount.keySet()){ if(!first) out.print(','); out.print("\""+jsq(k)+"\""); first=false; }
%>];
const topMeterVals=[<%
first=true; for(Integer v: topMeterAlarmCount.values()){ if(!first) out.print(','); out.print(v.intValue()); first=false; }
%>];
const alarmTypePie=[<%
first=true; for(Map.Entry<String,Integer> e: alarmTypeRatio.entrySet()){ if(!first) out.print(','); out.print("{name:\""+jsq(e.getKey())+"\",value:"+e.getValue().intValue()+"}"); first=false; }
%>];

const buildingChart=echarts.init(document.getElementById('buildingChart'));
buildingChart.setOption({color:[chartPalette.blue],tooltip:Object.assign({trigger:'axis',formatter:p=>makeAxisTooltip(p,'kWh',1)},tooltipBoxStyle),grid:{left:44,right:14,top:16,bottom:42,containLabel:true},xAxis:makeCategoryAxis(buildingNames,{axisLabel:{color:'#6b7a90',fontSize:11,interval:0,rotate:18}}),yAxis:makeValueAxis(0),graphic:buildingVals.length?undefined:makeEmptyGraphic('데이터 없음'),series:[{name:'사용량',type:'bar',barWidth:'48%',data:buildingVals,showBackground:true,backgroundStyle:{color:'#edf2f7',borderRadius:[8,8,0,0]},itemStyle:{color:chartPalette.blue,borderRadius:[8,8,0,0]}}]});
const usageChart=echarts.init(document.getElementById('usageChart'));
usageChart.setOption({color:piePalette,tooltip:Object.assign({trigger:'item',formatter:p=>p.name+'<br/>'+fmtNum(p.value,1)+' kWh'},tooltipBoxStyle),legend:{type:'scroll',top:0,left:'center',itemWidth:10,itemHeight:10,textStyle:{fontSize:10,color:'#6b7a90'}},graphic:usagePie.length?undefined:makeEmptyGraphic('데이터 없음'),series:[{name:'용도별',type:'pie',radius:['40%','66%'],center:['50%','58%'],minAngle:6,avoidLabelOverlap:true,itemStyle:{borderColor:'#fff',borderWidth:2},label:{color:'#516072',fontSize:11,formatter:'{b}'},labelLine:{length:10,length2:8},data:usagePie}]});
const dailyChart=echarts.init(document.getElementById('dailyChart'));
dailyChart.setOption({color:[chartPalette.green],tooltip:Object.assign({trigger:'axis',formatter:p=>makeAxisTooltip(p,'kWh',1),axisPointer:{type:'line',lineStyle:{color:'#9db5d1'}}},tooltipBoxStyle),grid:{left:46,right:16,top:16,bottom:34,containLabel:true},xAxis:makeCategoryAxis(dailyLabels,{axisLabel:{color:'#6b7a90',fontSize:11,interval:4}}),yAxis:makeValueAxis(0),series:[{name:'일사용량',type:'line',smooth:true,symbol:'circle',symbolSize:5,showSymbol:false,lineStyle:{width:3,color:chartPalette.green},areaStyle:{color:new echarts.graphic.LinearGradient(0,0,0,1,[{offset:0,color:'rgba(32,164,107,.28)'},{offset:1,color:'rgba(32,164,107,.03)'}])},data:dailyValues}]});
const monthlyChart=echarts.init(document.getElementById('monthlyChart'));
monthlyChart.setOption({color:[chartPalette.orange],tooltip:Object.assign({trigger:'axis',formatter:p=>makeAxisTooltip(p,'kWh',1)},tooltipBoxStyle),grid:{left:46,right:16,top:16,bottom:34,containLabel:true},xAxis:makeCategoryAxis(monthlyLabels),yAxis:makeValueAxis(0),series:[{name:'월사용량',type:'bar',barMaxWidth:28,data:monthlyValues,showBackground:true,backgroundStyle:{color:'#f3f4f6',borderRadius:[8,8,0,0]},itemStyle:{color:chartPalette.orange,borderRadius:[8,8,0,0]}}]});
const yearlyChart=echarts.init(document.getElementById('yearlyChart'));
yearlyChart.setOption({color:[chartPalette.violet],tooltip:Object.assign({trigger:'axis',formatter:p=>makeAxisTooltip(p,'kWh',1)},tooltipBoxStyle),grid:{left:46,right:16,top:16,bottom:34,containLabel:true},xAxis:makeCategoryAxis(yearlyLabels),yAxis:makeValueAxis(0),series:[{name:'년사용량',type:'bar',barMaxWidth:34,data:yearlyValues,showBackground:true,backgroundStyle:{color:'#f3f4f6',borderRadius:[8,8,0,0]},itemStyle:{color:chartPalette.violet,borderRadius:[8,8,0,0]}}]});
const heatMax=heatData.reduce((mx,r)=>Math.max(mx,r[2]||0),0);
const alarmHeatChart=echarts.init(document.getElementById('alarmHeatChart'));
alarmHeatChart.setOption({tooltip:Object.assign({position:'top',formatter:p=>heatDays[p.data[1]]+' '+p.data[0]+'시<br/>알람 '+fmtNum(p.data[2],0)+'건'},tooltipBoxStyle),grid:{left:34,right:14,top:10,bottom:28,containLabel:true},xAxis:{type:'category',data:heatHours,splitArea:{show:true,areaStyle:{color:['#f8fafc','#f8fafc']}},axisLine:{show:false},axisTick:{show:false},axisLabel:{fontSize:10,color:'#6b7a90'}},yAxis:{type:'category',data:heatDays,splitArea:{show:true,areaStyle:{color:['#f8fafc','#f8fafc']}},axisLine:{show:false},axisTick:{show:false},axisLabel:{fontSize:11,color:'#6b7a90'}},visualMap:{min:0,max:Math.max(1,heatMax),orient:'horizontal',left:'center',bottom:0,calculable:false,text:['많음','적음'],textStyle:{color:'#6b7a90',fontSize:10},inRange:{color:['#edf6ff','#b9d9ff','#6aa9ff','#2f6fed']}},series:[{type:'heatmap',data:heatData,label:{show:false},emphasis:{itemStyle:{shadowBlur:10,shadowColor:'rgba(47,111,237,.35)'}}}]});
const alarmTopMeterChart=echarts.init(document.getElementById('alarmTopMeterChart'));
alarmTopMeterChart.setOption({color:[chartPalette.red],tooltip:Object.assign({trigger:'axis',axisPointer:{type:'shadow'},formatter:p=>makeAxisTooltip(p,'건',0)},tooltipBoxStyle),grid:{left:120,right:18,top:12,bottom:18,containLabel:true},xAxis:makeValueAxis(0),yAxis:{type:'category',data:topMeterNames,inverse:true,axisLine:{show:false},axisTick:{show:false},axisLabel:{fontSize:10,color:'#6b7a90'}},graphic:topMeterVals.length?undefined:makeEmptyGraphic('데이터 없음'),series:[{name:'알람건수',type:'bar',barMaxWidth:20,data:topMeterVals,label:{show:true,position:'right',color:'#7a2e2e',fontSize:10},itemStyle:{color:chartPalette.red,borderRadius:[0,8,8,0]}}]});
const alarmTypeChart=echarts.init(document.getElementById('alarmTypeChart'));
alarmTypeChart.setOption({color:piePalette,tooltip:Object.assign({trigger:'item',formatter:p=>p.name+'<br/>'+fmtNum(p.value,0)+' 건'},tooltipBoxStyle),legend:{type:'scroll',bottom:0,textStyle:{fontSize:10,color:'#6b7a90'}},graphic:alarmTypePie.length?undefined:makeEmptyGraphic('데이터 없음'),series:[{name:'알람유형',type:'pie',radius:['38%','64%'],center:['50%','44%'],minAngle:6,itemStyle:{borderColor:'#fff',borderWidth:2},data:alarmTypePie,label:{color:'#516072',fontSize:10,formatter:'{d}%'}}]});

function goEnergyManage(filterKey, filterValue){
  const value=(filterValue||'').trim();
  if(!value) return;
  const qs=new URLSearchParams();
  qs.set(filterKey, value);
  window.location.href='/epms/energy_manage.jsp?'+qs.toString();
}
buildingChart.on('click',function(p){ if(p&&p.name) goEnergyManage('building', p.name); });
usageChart.on('click',function(p){ if(p&&p.name) goEnergyManage('usage', p.name); });
const buildingEl=document.getElementById('buildingChart');
const usageEl=document.getElementById('usageChart');
if(buildingEl) buildingEl.style.cursor='pointer';
if(usageEl) usageEl.style.cursor='pointer';
window.addEventListener('resize',function(){buildingChart.resize();usageChart.resize();dailyChart.resize();monthlyChart.resize();yearlyChart.resize();alarmHeatChart.resize();alarmTopMeterChart.resize();alarmTypeChart.resize();});
const REFRESH_KEY_ON='energyOverviewAutoRefreshOn', REFRESH_KEY_SEC='energyOverviewAutoRefreshSec';
const autoRefreshOn=document.getElementById('autoRefreshOn'), autoRefreshSec=document.getElementById('autoRefreshSec');
let refreshTimer=null; function clearRefreshTimer(){ if(refreshTimer){ clearInterval(refreshTimer); refreshTimer=null; }}
function applyAutoRefresh(){ clearRefreshTimer(); if(!autoRefreshOn||!autoRefreshSec||!autoRefreshOn.checked) return; const sec=Number(autoRefreshSec.value||60); if(!Number.isFinite(sec)||sec<5) return; refreshTimer=setInterval(()=>window.location.reload(),sec*1000); }
if(autoRefreshOn&&autoRefreshSec){ const savedOn=localStorage.getItem(REFRESH_KEY_ON), savedSec=localStorage.getItem(REFRESH_KEY_SEC); autoRefreshOn.checked=(savedOn==='1'); if(savedSec==='30'||savedSec==='60') autoRefreshSec.value=savedSec; autoRefreshOn.addEventListener('change',()=>{localStorage.setItem(REFRESH_KEY_ON,autoRefreshOn.checked?'1':'0');applyAutoRefresh();}); autoRefreshSec.addEventListener('change',()=>{localStorage.setItem(REFRESH_KEY_SEC,autoRefreshSec.value);applyAutoRefresh();}); applyAutoRefresh(); }
</script>
<%
} // end try-with-resources
%>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
