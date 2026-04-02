<%@ page contentType="application/json; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*"%>
<%@ page import="java.util.*"%>

<%!
public String esc(String s){
  if(s==null) return "";
  return s.replace("\\","\\\\").replace("\"","\\\"");
}
%>

<%
String action = request.getParameter("action");
if(action==null) action="data";

/* ===== DB ===== */
String jdbcUrl  = "jdbc:sqlserver://192.168.0.201:1433;databaseName=EPMS;encrypt=false";
String jdbcUser = "sa";
String jdbcPass = "1234";

/* ===== DTO ===== */
class EnergyData{
  double today=0, yesterday=0;
  double[] month = new double[12];
  double[] hour  = new double[24];
}

PreparedStatement ps=null;
ResultSet rs=null;

try{
  Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
  try (Connection conn = DriverManager.getConnection(jdbcUrl,jdbcUser,jdbcPass)) {

  /* =====================================================
     META : building / usage
  ===================================================== */
  if("meta".equalsIgnoreCase(action)){
    List<String> buildings=new ArrayList<>();
    List<String> usages=new ArrayList<>();

    ps = conn.prepareStatement(
      "SELECT DISTINCT LTRIM(RTRIM(building_name)) AS b " +
      "FROM vw_meter_measurements " +
      "WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name))<>'' " +
      "ORDER BY b"
    );
    rs=ps.executeQuery();
    while(rs.next()) buildings.add(rs.getString(1));
    rs.close(); ps.close();

    ps = conn.prepareStatement(
      "SELECT DISTINCT LTRIM(RTRIM(usage_type)) AS u " +
      "FROM vw_meter_measurements " +
      "WHERE usage_type IS NOT NULL AND LTRIM(RTRIM(usage_type))<>'' " +
      "ORDER BY u"
    );
    rs=ps.executeQuery();
    while(rs.next()) usages.add(rs.getString(1));
    rs.close(); ps.close();

    StringBuilder j=new StringBuilder("{\"buildings\":[");
    for(int i=0;i<buildings.size();i++){
      if(i>0) j.append(",");
      j.append("\"").append(esc(buildings.get(i))).append("\"");
    }
    j.append("],\"usages\":[");
    for(int i=0;i<usages.size();i++){
      if(i>0) j.append(",");
      j.append("\"").append(esc(usages.get(i))).append("\"");
    }
    j.append("]}");
    out.print(j.toString());
    return;
  }

  /* =====================================================
     PARAM
  ===================================================== */
  String building = request.getParameter("building");
  if(building==null||building.trim().isEmpty()) building="TOTAL";
  building=building.trim();
  boolean isTotal="TOTAL".equalsIgnoreCase(building);

  int month;
  try{ month=Integer.parseInt(request.getParameter("month")); }
  catch(Exception e){ month=Calendar.getInstance().get(Calendar.MONTH)+1; }

  int yearCount=3;
  try{ yearCount=Integer.parseInt(request.getParameter("years")); }
  catch(Exception e){}
  if(yearCount<2) yearCount=2;

  String metric=request.getParameter("metric");
  if(metric==null) metric="PEAK";
  metric=metric.toUpperCase();

  /* =====================================================
     baseDate (선택 월 기준 최신일)
  ===================================================== */
  java.sql.Date baseDate=null;
  ps=conn.prepareStatement(
    "SELECT CAST(MAX(measured_at) AS date) " +
    "FROM vw_meter_measurements WHERE MONTH(measured_at)=?"
  );
  ps.setInt(1,month);
  rs=ps.executeQuery();
  if(rs.next()) baseDate=rs.getDate(1);
  rs.close(); ps.close();

  if(baseDate==null){
    ps=conn.prepareStatement(
      "SELECT CAST(MAX(measured_at) AS date) FROM vw_meter_measurements"
    );
    rs=ps.executeQuery();
    if(rs.next()) baseDate=rs.getDate(1);
    rs.close(); ps.close();
  }

  /* =====================================================
     year range
  ===================================================== */
  int endYear=Calendar.getInstance().get(Calendar.YEAR);
  ps=conn.prepareStatement(
    "SELECT YEAR(MAX(measured_at)) FROM vw_meter_measurements"
  );
  rs=ps.executeQuery();
  if(rs.next() && rs.getInt(1)>0) endYear=rs.getInt(1);
  rs.close(); ps.close();
  int startYear=endYear-(yearCount-1);

  /* =====================================================
     building slots (3)
  ===================================================== */
  List<String> bs=new ArrayList<>();
  if(!isTotal) bs.add(building);

  ps=conn.prepareStatement(
    "SELECT DISTINCT TOP 3 LTRIM(RTRIM(building_name)) AS b " +
    "FROM vw_meter_measurements " +
    "WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name))<>'' " +
    "ORDER BY b"
  );
  rs=ps.executeQuery();
  while(rs.next() && bs.size()<3){
    String b=rs.getString(1);
    if(!bs.contains(b)) bs.add(b);
  }
  rs.close(); ps.close();
  while(bs.size()<3) bs.add("N/A");

  Map<String,EnergyData> map=new LinkedHashMap<>();
  for(String b:bs) map.put(b,new EnergyData());
  String in3="?,?,?";

  /* =====================================================
     1) today / yesterday peak dP
  ===================================================== */
  ps=conn.prepareStatement(
    "SELECT LTRIM(RTRIM(building_name)) b, CAST(measured_at AS date) d, " +
    "MAX(CAST(active_power_total AS float)) v " +
    "FROM vw_meter_measurements " +
    "WHERE CAST(measured_at AS date) IN (?,DATEADD(day,-1,?)) " +
    "AND LTRIM(RTRIM(building_name)) IN ("+in3+") " +
    "GROUP BY LTRIM(RTRIM(building_name)), CAST(measured_at AS date)"
  );
  ps.setDate(1,baseDate);
  ps.setDate(2,baseDate);
  ps.setString(3,bs.get(0));
  ps.setString(4,bs.get(1));
  ps.setString(5,bs.get(2));
  rs=ps.executeQuery();
  while(rs.next()){
    EnergyData ed=map.get(rs.getString("b"));
    if(ed==null) continue;
    if(rs.getDate("d").equals(baseDate)) ed.today=rs.getDouble("v");
    else ed.yesterday=rs.getDouble("v");
  }
  rs.close(); ps.close();


  /* =====================================================
    1-1) 월 최대 수요전력(kW): 선택 월 전체에서 MAX(active_power_total)
    ===================================================== */
    Map<String, Double> monthMaxKw = new LinkedHashMap<>();

    ps = conn.prepareStatement(
    "SELECT LTRIM(RTRIM(building_name)) AS b, " +
    "       MAX(CAST(active_power_total AS float)) AS max_kw " +
    "FROM vw_meter_measurements " +
    "WHERE YEAR(measured_at) = ? AND MONTH(measured_at) = ? " +
    "  AND LTRIM(RTRIM(building_name)) IN (" + in3 + ") " +
    "GROUP BY LTRIM(RTRIM(building_name))"
    );

    ps.setInt(1, endYear);      // endYear(데이터 최대 연도) 기준
    ps.setInt(2, month);
    ps.setString(3, bs.get(0));
    ps.setString(4, bs.get(1));
    ps.setString(5, bs.get(2));

    rs = ps.executeQuery();
    while (rs.next()) {
    monthMaxKw.put(rs.getString("b"), rs.getDouble("max_kw"));
    }
    rs.close(); ps.close();

  /* =====================================================
     2) 월 kWh : MAX - MIN (누적치)
  ===================================================== */
  ps=conn.prepareStatement(
    "SELECT b, mm, SUM(maxv-minv) kwh FROM ( " +
    " SELECT meter_id, LTRIM(RTRIM(building_name)) b, MONTH(measured_at) mm, " +
    " MAX(energy_consumed_total) maxv, MIN(energy_consumed_total) minv " +
    " FROM vw_meter_measurements " +
    " WHERE LTRIM(RTRIM(building_name)) IN ("+in3+") " +
    " GROUP BY meter_id, LTRIM(RTRIM(building_name)), MONTH(measured_at) " +
    ") t GROUP BY b, mm"
  );
  ps.setString(1,bs.get(0));
  ps.setString(2,bs.get(1));
  ps.setString(3,bs.get(2));
  rs=ps.executeQuery();
  while(rs.next()){
    EnergyData ed=map.get(rs.getString("b"));
    int mm=rs.getInt("mm");
    if(ed!=null && mm>=1 && mm<=12) ed.month[mm-1]=rs.getDouble("kwh");
  }
  rs.close(); ps.close();

  /* =====================================================
     3) hourly dP (b1)
  ===================================================== */
  String b1=bs.get(0);
  ps=conn.prepareStatement(
    "SELECT DATEPART(hour,measured_at) h, " +
    "MAX(CAST(active_power_total AS float)) v " +
    "FROM vw_meter_measurements " +
    "WHERE CAST(measured_at AS date)=? " +
    "AND LTRIM(RTRIM(building_name))=? " +
    "GROUP BY DATEPART(hour,measured_at)"
  );
  ps.setDate(1,baseDate);
  ps.setString(2,b1);
  rs=ps.executeQuery();
  while(rs.next()){
    int h=rs.getInt("h");
    if(h>=0&&h<24) map.get(b1).hour[h]=rs.getDouble("v");
  }
  rs.close(); ps.close();

  /* =====================================================
     4) usage pie (선택일 kWh)
  ===================================================== */
  Map<String,Double> usagePie=new LinkedHashMap<>();
  ps=conn.prepareStatement(
    "SELECT LTRIM(RTRIM(usage_type)) u, SUM(v) kwh FROM ( " +
    " SELECT meter_id, usage_type, " +
    " MAX(energy_consumed_total)-MIN(energy_consumed_total) v " +
    " FROM vw_meter_measurements " +
    " WHERE CAST(measured_at AS date)=? " +
    " AND LTRIM(RTRIM(building_name)) IN ("+in3+") " +
    " GROUP BY meter_id, usage_type " +
    ") t GROUP BY LTRIM(RTRIM(usage_type)) ORDER BY kwh DESC"
  );
  ps.setDate(1,baseDate);
  ps.setString(2,bs.get(0));
  ps.setString(3,bs.get(1));
  ps.setString(4,bs.get(2));
  rs=ps.executeQuery();
  while(rs.next()) usagePie.put(rs.getString(1),rs.getDouble(2));
  rs.close(); ps.close();

  /* =====================================================
     5) year compare
  ===================================================== */
  String agg;
  String metricLabel;
  if("AVG".equals(metric)){
    agg="AVG(CAST(active_power_total AS float))";
    metricLabel="평균 수요전력";
  }else{
    agg="MAX(CAST(active_power_total AS float))";
    metricLabel="피크 수요전력";
  }

  Map<Integer,Map<String,Double>> yc=new LinkedHashMap<>();
  for(int y=startYear;y<=endYear;y++) yc.put(y,new HashMap<>());

  ps=conn.prepareStatement(
    "SELECT YEAR(measured_at) y, LTRIM(RTRIM(building_name)) b, "+agg+" v " +
    "FROM vw_meter_measurements " +
    "WHERE MONTH(measured_at)=? AND YEAR(measured_at) BETWEEN ? AND ? " +
    "AND LTRIM(RTRIM(building_name)) IN ("+in3+") " +
    "GROUP BY YEAR(measured_at), LTRIM(RTRIM(building_name))"
  );
  ps.setInt(1,month);
  ps.setInt(2,startYear);
  ps.setInt(3,endYear);
  ps.setString(4,bs.get(0));
  ps.setString(5,bs.get(1));
  ps.setString(6,bs.get(2));
  rs=ps.executeQuery();
  while(rs.next()){
    yc.get(rs.getInt("y")).put(rs.getString("b"),rs.getDouble("v"));
  }
  rs.close(); ps.close();

  /* =====================================================
     JSON
  ===================================================== */
  StringBuilder j=new StringBuilder("{");

  String[] keys={"Electricity","Water","Gas"};
  for(int i=0;i<3;i++){
    EnergyData ed=map.get(bs.get(i));
    if(i>0) j.append(",");
    j.append("\"").append(keys[i]).append("\":{");
    j.append("\"today\":").append(ed.today).append(",");
    j.append("\"yesterday\":").append(ed.yesterday).append(",");
    for(int m=1;m<=12;m++){
      j.append("\"month_").append(String.format("%02d",m)).append("\":").append(ed.month[m-1]).append(",");
    }
    for(int h=0;h<24;h++){
      j.append("\"hour_").append(String.format("%02d",h)).append("\":").append(ed.hour[h]);
      if(h<23) j.append(",");
    }
    j.append("}");
  }

  j.append(",\"selectedBuildings\":[");
  for(int i=0;i<3;i++){
    if(i>0) j.append(",");
    j.append("\"").append(esc(bs.get(i))).append("\"");
  }
  j.append("]");

  j.append(",\"baseDate\":\"").append(baseDate).append("\"");

  j.append(",\"usagePie\":[");
  int c=0;
  for(Map.Entry<String,Double> e:usagePie.entrySet()){
    if(c++>0) j.append(",");
    j.append("{\"name\":\"").append(esc(e.getKey()))
     .append("\",\"value\":").append(e.getValue()).append("}");
  }
  j.append("]");

  j.append(",\"yearCompare\":{");
  j.append("\"selectedMonth\":").append(month).append(",");
  j.append("\"yearCount\":").append(yearCount).append(",");
  j.append("\"metricLabel\":\"").append(metricLabel).append("\",");
  j.append("\"unit\":\"kW\",");
  j.append("\"series\":[");
  int ycIdx=0;
  for(int y:yc.keySet()){
    if(ycIdx++>0) j.append(",");
    j.append("{\"year\":").append(y).append(",\"values\":[");
    for(int i=0;i<3;i++){
      if(i>0) j.append(",");
      j.append(yc.get(y).getOrDefault(bs.get(i),0.0));
    }
    j.append("]}");
  }
  j.append("]}");

  j.append("}");
  out.print(j.toString());
  }
}catch(Exception e){
  out.print("{\"error\":\""+esc(e.getMessage())+"\"}");
}finally{
  try{if(rs!=null)rs.close();}catch(Exception e){}
  try{if(ps!=null)ps.close();}catch(Exception e){}
}
%>
