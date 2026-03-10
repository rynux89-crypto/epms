<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%! 

  private static String numJson(double v) {
    if (Double.isNaN(v) || Double.isInfinite(v)) return "0";
    return String.format(java.util.Locale.US, "%.6f", v);
  }

%>
<%
  String meterParam = request.getParameter("meter");
  String ajax = request.getParameter("ajax");
  boolean isAjax = "1".equals(ajax);
  String va0Param = request.getParameter("va0");
  boolean vaZero = "1".equals(va0Param) || "on".equalsIgnoreCase(va0Param);

  List<String[]> meterOptions = new ArrayList<>();
  String selectedMeter = null;
  String measuredAt = "-";
  Timestamp measuredAtTs = null;
  String responseError = null;
  boolean responseOk = true;

  double voltage_an = 0, voltage_bn = 0, voltage_cn = 0;
  double current_a = 0, current_b = 0, current_c = 0;
  double voltage_phase_a = 0, voltage_phase_b = 0, voltage_phase_c = 0;
  double current_phase_a = 0, current_phase_b = 0, current_phase_c = 0;

  try {
    if (meterParam != null && !meterParam.trim().isEmpty()) {
      Integer meterId = parsePositiveInt(meterParam);
      if (meterId != null) {
        selectedMeter = String.valueOf(meterId);
      } else if (isAjax) {
        responseOk = false;
        responseError = "invalid meter parameter";
      }
    }

    if (!isAjax) {
      try (PreparedStatement psMeters = conn.prepareStatement(
          "SELECT meter_id, name FROM meters " +
          "WHERE (UPPER(name) LIKE '%VCB%' OR UPPER(name) LIKE '%ACB%') " +
          "ORDER BY meter_id");
           ResultSet rsMeters = psMeters.executeQuery()) {
        while (rsMeters.next()) {
          meterOptions.add(new String[]{ rsMeters.getString("meter_id"), rsMeters.getString("name") });
        }
      }

      if ((selectedMeter == null || selectedMeter.isEmpty()) && !meterOptions.isEmpty()) {
        selectedMeter = meterOptions.get(0)[0];
      }
    }

    if (selectedMeter != null && !selectedMeter.isEmpty()) {
      String sql =
        "SELECT TOP 1 measured_at, " +
        "voltage_an, voltage_bn, voltage_cn, " +
        "current_a, current_b, current_c, " +
        "voltage_phase_a, voltage_phase_b, voltage_phase_c, " +
        "current_phase_a, current_phase_b, current_phase_c " +
        "FROM vw_meter_measurements " +
        "WHERE meter_id = ? " +
        "ORDER BY measured_at DESC";

      try (PreparedStatement ps = conn.prepareStatement(sql)) {
        ps.setInt(1, Integer.parseInt(selectedMeter));
        try (ResultSet rs = ps.executeQuery()) {
          if (rs.next()) {
            Timestamp ts = rs.getTimestamp("measured_at");
            measuredAtTs = ts;
            measuredAt = (ts != null) ? ts.toString() : "-";

            voltage_an = rs.getDouble("voltage_an");
            voltage_bn = rs.getDouble("voltage_bn");
            voltage_cn = rs.getDouble("voltage_cn");
            current_a = rs.getDouble("current_a");
            current_b = rs.getDouble("current_b");
            current_c = rs.getDouble("current_c");

            voltage_phase_a = rs.getDouble("voltage_phase_a");
            voltage_phase_b = rs.getDouble("voltage_phase_b");
            voltage_phase_c = rs.getDouble("voltage_phase_c");
            current_phase_a = rs.getDouble("current_phase_a");
            current_phase_b = rs.getDouble("current_phase_b");
            current_phase_c = rs.getDouble("current_phase_c");
          }
        }
      }
    }
  } catch (Exception e) {
    responseOk = false;
    responseError = e.getMessage();
    e.printStackTrace();
  } finally {
    try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
  }

  StringBuilder phasorJson = new StringBuilder("{");
  phasorJson.append("\"ok\":").append(responseOk ? "true" : "false").append(",");
  if (!responseOk) {
    phasorJson.append("\"error\":\"").append(escJson(responseError == null ? "request failed" : responseError)).append("\",");
  }
  phasorJson.append("\"meter_id\":\"").append(escJson(selectedMeter == null ? "" : selectedMeter)).append("\",");
  phasorJson.append("\"measured_at\":\"").append(escJson(measuredAt)).append("\",");
  phasorJson.append("\"measured_at_epoch\":").append(measuredAtTs != null ? measuredAtTs.getTime() : -1).append(",");
  phasorJson.append("\"measured_at_iso\":\"")
            .append(escJson(measuredAtTs != null ? measuredAtTs.toInstant().toString() : ""))
            .append("\",");
  phasorJson.append("\"voltage_an\":").append(numJson(voltage_an)).append(",");
  phasorJson.append("\"voltage_bn\":").append(numJson(voltage_bn)).append(",");
  phasorJson.append("\"voltage_cn\":").append(numJson(voltage_cn)).append(",");
  phasorJson.append("\"current_a\":").append(numJson(current_a)).append(",");
  phasorJson.append("\"current_b\":").append(numJson(current_b)).append(",");
  phasorJson.append("\"current_c\":").append(numJson(current_c)).append(",");
  phasorJson.append("\"voltage_phase_a\":").append(numJson(voltage_phase_a)).append(",");
  phasorJson.append("\"voltage_phase_b\":").append(numJson(voltage_phase_b)).append(",");
  phasorJson.append("\"voltage_phase_c\":").append(numJson(voltage_phase_c)).append(",");
  phasorJson.append("\"current_phase_a\":").append(numJson(current_phase_a)).append(",");
  phasorJson.append("\"current_phase_b\":").append(numJson(current_phase_b)).append(",");
  phasorJson.append("\"current_phase_c\":").append(numJson(current_phase_c));
  phasorJson.append("}");

  if (isAjax) {
    response.setContentType("application/json; charset=UTF-8");
    out.print(phasorJson.toString());
    return;
  }
%>
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Phasor Diagram</title>
  <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
  <script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
  <style>
    body {
      margin:0;
      font-family: 'Segoe UI', Arial, sans-serif;
      background:#f4f7fb;
      overflow:hidden;
      min-height:100svh;
      height:100svh;
      display:flex;
      flex-direction:column;
    }
    .page {
      padding: 10px 12px 8px;
      box-sizing: border-box;
      overflow: hidden;
      flex: 1 1 auto;
      min-height: 0;
      display: flex;
      flex-direction: column;
    }
    .toolbar { display:grid; grid-template-columns: 1fr auto 1fr; gap:10px; align-items:center; margin-bottom:8px; }
    .toolbar form { display:flex; gap:8px; align-items:center; justify-self:start; }
    .toolbar select, .toolbar button { height:32px; }
    .toolbar .meta { justify-self:end; font-size:12px; color:#475569; font-weight:700; }
    .scan-box { justify-self:end; display:inline-flex; align-items:center; gap:6px; flex-wrap:wrap; }
    .scan-top { display:inline-flex; align-items:center; gap:6px; }
    .scan-top .meta { width:auto; text-align:right; white-space:nowrap; }
    .scan-actions { display:inline-flex; align-items:center; gap:6px; }
    .scan-box select, .scan-box button { height:32px; }
    .va0-wrap {
      display:inline-flex;
      align-items:center;
      justify-content:center;
      gap:6px;
      min-width:140px;
      text-align:center;
      justify-self:center;
      padding:5px 10px;
      border-radius:999px;
      border:1px solid #cbd5e1;
      background:#f8fafc;
      color:#334155;
      font-weight:800;
      transition:all .15s ease;
    }
    .va0-wrap input { accent-color:#dc2626; }
    .va0-wrap.active {
      border-color:#dc2626;
      background:#fff1f2;
      color:#7f1d1d;
      box-shadow:0 0 0 2px rgba(220,38,38,0.15);
    }

    .phasor-grid {
      display:grid;
      grid-template-columns:minmax(0,1fr) 360px;
      gap:12px;
      align-items:stretch;
      flex: 1 1 auto;
      height: 100%;
      min-height:0;
    }
    #chart {
      width:100%;
      height:100%;
      min-height:0;
      background:#fff;
      border-radius:14px;
      box-shadow:0 10px 24px rgba(0,0,0,0.06);
    }
    .side {
      background:#fff;
      border-radius:14px;
      padding:12px;
      box-shadow:0 10px 24px rgba(0,0,0,0.06);
      overflow:hidden;
      min-height:0;
    }
    .top-actions { display:flex; gap:8px; align-items:center; }
    .time-diff { font-weight:700; color:#64748b; }

    .summary-sec { margin-top: 8px; }
    .sec-toggle{
      width:100%;
      margin:6px 0 0;
      padding:4px 4px 6px;
      display:flex;
      align-items:center;
      gap:6px;
      background:transparent;
      border:0;
      cursor:pointer;
      font-size:12px;
      font-weight:900;
      color:#111827;
      letter-spacing:0.2px;
      text-align:left;
      border-bottom:1px solid #eef2f7;
    }
    .sec-toggle .tri{
      width:12px;
      color:#475569;
      font-size:12px;
      line-height:1;
      transform:rotate(0deg);
      transition:transform .15s ease;
    }
    .summary-sec.collapsed .sec-toggle .tri{
      transform:rotate(-90deg);
    }
    .summary-sec.collapsed .kv{
      display:none;
    }

    .kv {
      display:grid;
      grid-template-columns: 1fr auto;
      gap:4px 8px;
      padding:6px 6px;
    }
    .kv .k { font-size:12px; color:#6b7280; }
    .kv .v { font-size:13px; font-weight:800; color:#111827; text-align:right; white-space:nowrap; }
    .v.muted{ font-weight:700; color:#475569; font-size:12px; }

    .ok{ color:#16a34a !important; }
    .warn{ color:#f59e0b !important; }
    .alarm{ color:#dc2626 !important; }

    .badge {
      display:inline-flex;
      align-items:center;
      gap:6px;
      padding:2px 10px;
      border-radius:999px;
      font-size:11px;
      font-weight:900;
      letter-spacing:0.2px;
    }
    .badge.ok{ background:#dcfce7; color:#166534 !important; }
    .badge.warn{ background:#fef3c7; color:#92400e !important; }
    .badge.alarm{ background:#fee2e2; color:#991b1b !important; }

    .tag{
      display:inline-flex;
      align-items:center;
      padding:1px 8px;
      border-radius:999px;
      font-size:11px;
      font-weight:800;
      margin-left:6px;
    }
    .tag.lag{ background:#dcfce7; color:#166534; }
    .tag.lead{ background:#dbeafe; color:#1d4ed8; }

    .v .num{ font-variant-numeric: tabular-nums; }
    .v .unit{ font-size:11px; color:#94a3b8; font-weight:800; margin-left:4px; }

    .status-text {
      display:flex; justify-content:space-between; align-items:center;
      margin-top:8px;
      padding:8px 10px;
      background:#f8fafc;
      border:1px solid #eef2f7;
      border-radius:12px;
      font-size:12px;
      color:#64748b;
      line-height:1.4;
    }

    @media (max-width: 980px) {
      .toolbar { grid-template-columns: 1fr; }
      .toolbar form, .toolbar .meta, .va0-wrap, .scan-box { justify-self:start; align-items:center; }
      .phasor-grid { grid-template-columns: 1fr; height:auto; }
      #chart { min-height:380px; }
      .page { overflow: auto; }
    }
  </style>
</head>
<body>
  <div class="title-bar">
    <h2>📐 페이저 모니터링</h2>
    <div class="top-actions">
      <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
    </div>
  </div>

  <div class="page">
    <div class="toolbar">
      <form id="phasorForm" method="GET">
        <label for="meter">Meter</label>
        <select id="meter" name="meter">
          <% for (String[] opt : meterOptions) { %>
            <option value="<%= h(opt[0]) %>" <%= Objects.equals(opt[0], selectedMeter) ? "selected" : "" %>><%= h(opt[1]) %></option>
          <% } %>
        </select>
        <button type="submit">조회</button>
      </form>
      <label class="va0-wrap" id="va0Wrap">
        <input type="checkbox" id="va0Opt" name="va0" value="1" form="phasorForm" <%= vaZero ? "checked" : "" %>>
        <span>Va=0° 기준</span>
      </label>
      <div class="scan-box">
        <div class="scan-top">
          <label for="scanInterval" class="meta" id="scanLabel">스캔주기(수동 모드)</label>
          <select id="scanInterval">
            <option value="3000" selected>3초</option>
            <option value="5000">5초</option>
            <option value="10000">10초</option>
          </select>
        </div>
        <div class="scan-actions">
          <button type="button" id="scanStart">스캔 시작</button>
          <button type="button" id="scanStop" disabled>스캔 중지</button>
        </div>
      </div>
    </div>

    <div class="phasor-grid">
      <div id="chart"></div>
      <div class="side">
        <div class="summary-sec" id="secPf">
          <button type="button" class="sec-toggle" data-target="pfBox" aria-expanded="true">
            <span class="tri">▾</span><span>역률 / 부하</span>
          </button>
          <div class="kv" id="pfBox"></div>
        </div>

        <div class="summary-sec" id="secAlarm">
          <button type="button" class="sec-toggle" data-target="alarmBox" aria-expanded="true">
            <span class="tri">▾</span><span>알람</span>
          </button>
          <div class="kv" id="alarmBox"></div>
        </div>

        <div class="summary-sec" id="secSeq">
          <button type="button" class="sec-toggle" data-target="seqBox" aria-expanded="true">
            <span class="tri">▾</span><span>대칭분 / 불평형</span>
          </button>
          <div class="kv" id="seqBox"></div>
        </div>

        <div class="status-text">
          <span>측정 시각</span>
          <span id="timeDiff" class="time-diff"></span>
        </div>
      </div>
    </div>
  </div>
  <footer>© EPMS Dashboard | SNUT CNT</footer>

<script>
(function(){
  let data = <%= phasorJson.toString() %>;
  let selectedMeter = (typeof data.meter_id === 'string') ? data.meter_id : '';
  let lockVaZero = <%= vaZero ? "true" : "false" %>;
  let POLL_MS = 10000;
  let pollTimer = null;
  let scanTimer = null;
  let isScanning = false;
  let scanIndex = 0;

  let TH_V_UNBAL_WARN = 2.0;
  let TH_V_UNBAL_ALARM = 3.0;
  let TH_PF_WARN = 0.90;
  let TH_PF_ALARM = 0.80;
  let TH_V_OVER = 1.10;
  let TH_V_UNDER = 0.90;

  function num(k){ return (typeof data[k] === 'number' && isFinite(data[k])) ? data[k] : 0; }
  function strv(k){ return (typeof data[k] === 'string') ? data[k] : ''; }
  function deg2rad(d){ return d * Math.PI / 180; }
  function rad2deg(r){ return r * 180 / Math.PI; }

  function norm180(deg){
    let a = deg % 360;
    if (a > 180) a -= 360;
    if (a <= -180) a += 360;
    return a;
  }
  function norm360(deg){
    let a = deg % 360;
    if (a < 0) a += 360;
    return a;
  }
  function chartAngle(rawDeg){
    let a = rawDeg;
    if (lockVaZero) a = a - num('voltage_phase_a');
    return norm360(a);
  }
  function shortestDelta(startDeg, endDeg){
    let s = norm360(startDeg);
    let e = norm360(endDeg);
    let d = e - s;
    // JS modulo can stay negative, so shift by +540 for stable [-180,180) normalization.
    d = ((d + 540) % 360) - 180;
    return d;
  }
  function arcShortInfo(startDeg, endDeg){
    let s = norm360(startDeg);
    let d = shortestDelta(startDeg, endDeg);
    let e = s + d;
    let midDeg = s + d/2;
    return { sDeg:s, eDeg:e, midDeg:midDeg, dDeg:d, diffAbs: Math.abs(d) };
  }
  function toCanvasRad(deg){ return -deg2rad(deg); }

  function cFromPolar(mag, deg){
    let r = deg2rad(deg);
    return { re: mag*Math.cos(r), im: mag*Math.sin(r) };
  }
  function cAdd(a,b){ return { re:a.re+b.re, im:a.im+b.im }; }
  function cMul(a,b){ return { re:a.re*b.re - a.im*b.im, im:a.re*b.im + a.im*b.re }; }
  function cScale(a,k){ return { re:a.re*k, im:a.im*k }; }
  function cAbs(a){ return Math.hypot(a.re,a.im); }
  function cArgDeg(a){ return rad2deg(Math.atan2(a.im,a.re)); }

  let A = cFromPolar(1, 120);
  let A2 = cFromPolar(1, 240);
  function symComp(Va, Vb, Vc){
    let V0 = cScale(cAdd(cAdd(Va,Vb),Vc), 1/3);
    let V1 = cScale(cAdd(cAdd(Va, cMul(A, Vb)), cMul(A2, Vc)), 1/3);
    let V2 = cScale(cAdd(cAdd(Va, cMul(A2, Vb)), cMul(A, Vc)), 1/3);
    return { V0:V0, V1:V1, V2:V2 };
  }

  function makeArc(startDeg, endDeg, radiusFrac, labelPrefix, color, labelRScale, labelOffsetPx){
    return {
      type: 'custom',
      coordinateSystem: 'polar',
      silent: true,
      renderItem: function(params){
        let cx = params.coordSys.cx;
        let cy = params.coordSys.cy;
        let r = params.coordSys.r * radiusFrac;
        let info = arcShortInfo(startDeg, endDeg);

        let a1 = toCanvasRad(info.sDeg);
        let a2 = toCanvasRad(info.eDeg);
        let amid = toCanvasRad(info.midDeg);

        let labelR = r * (labelRScale || 1.10);
        let txt = (labelPrefix ? (labelPrefix + ' ') : '') + info.diffAbs.toFixed(1) + '°';
        let clockwise = info.dDeg < 0;
        let labelShift = (typeof labelOffsetPx === 'number') ? labelOffsetPx : 0;

        // Arc endpoints
        let sx = cx + r * Math.cos(a1);
        let sy = cy + r * Math.sin(a1);
        let ex = cx + r * Math.cos(a2);
        let ey = cy + r * Math.sin(a2);

        function tangent(theta, cw){
          // CCW tangent: (-sin, cos), CW is opposite
          return cw ? { x: Math.sin(theta), y: -Math.cos(theta) } : { x: -Math.sin(theta), y: Math.cos(theta) };
        }
        function arrowPoints(px, py, tx, ty, size){
          let len = Math.hypot(tx, ty) || 1;
          let ux = tx / len, uy = ty / len;
          let bx = px - ux * size;
          let by = py - uy * size;
          let nx = -uy, ny = ux;
          let half = size * 0.55;
          return [
            [px, py],
            [bx + nx * half, by + ny * half],
            [bx - nx * half, by - ny * half]
          ];
        }
        let tStart = tangent(a1, clockwise);
        let tEnd = tangent(a2, clockwise);
        // 양방향 화살표 방향 보정
        let startArrow = arrowPoints(sx, sy, tStart.x, tStart.y, 9);
        let endArrow = arrowPoints(ex, ey, -tEnd.x, -tEnd.y, 9);

        let tMid = tangent(amid, clockwise);
        let labelX = cx + labelR * Math.cos(amid) + tMid.x * labelShift;
        let labelY = cy + labelR * Math.sin(amid) + tMid.y * labelShift;

        return {
          type: 'group',
          children: [
            {
              type: 'arc',
              shape: {
                cx: cx,
                cy: cy,
                r: r,
                startAngle: a1,
                endAngle: a2,
                clockwise: clockwise
              },
              style: { stroke: color || '#888', lineWidth: 1.3, fill: 'none' }
            },
            { type: 'polygon', shape: { points: startArrow }, style: { fill: color || '#888' } },
            { type: 'polygon', shape: { points: endArrow }, style: { fill: color || '#888' } },
            {
              type: 'text',
              style: {
                x: labelX,
                y: labelY,
                text: txt,
                fill: '#334155',
                fontSize: 11,
                align: 'center',
                verticalAlign: 'middle',
                backgroundColor: 'rgba(255,255,255,0.90)',
                padding: [2,4],
                borderRadius: 4,
                borderColor: 'rgba(148,163,184,0.55)',
                borderWidth: 1
              }
            }
          ]
        };
      },
      data: [0]
    };
  }

  function makeOuterRing(){
    return {
      name: 'outer-ring',
      type: 'custom',
      coordinateSystem: 'polar',
      silent: true,
      z: 1,
      renderItem: function(params){
        return {
          type: 'circle',
          shape: { cx: params.coordSys.cx, cy: params.coordSys.cy, r: params.coordSys.r },
          style: {
            stroke: 'rgba(71,85,105,0.65)',
            lineWidth: 1.2,
            fill: 'none',
            shadowBlur: 2,
            shadowColor: 'rgba(15,23,42,0.08)'
          }
        };
      },
      data: [0]
    };
  }

  function makeCardinalLines(){
    return {
      name: 'cardinal-lines',
      type: 'custom',
      coordinateSystem: 'polar',
      silent: true,
      z: 1,
      renderItem: function(params){
        let cx = params.coordSys.cx;
        let cy = params.coordSys.cy;
        let r = params.coordSys.r;
        let degs = [0, 90, 180, 270];
        let children = [];
        for (let i = 0; i < degs.length; i++) {
          let th = toCanvasRad(degs[i]);
          children.push({
            type: 'line',
            shape: {
              x1: cx,
              y1: cy,
              x2: cx + r * Math.cos(th),
              y2: cy + r * Math.sin(th)
            },
            style: {
              stroke: 'rgba(100,116,139,0.55)',
              lineWidth: 1.1,
              lineDash: [4,4]
            }
          });
        }
        return { type: 'group', children: children };
      },
      data: [0]
    };
  }

  function makeVaZeroReference(){
    return {
      name: 'Va=0 reference',
      type: 'custom',
      coordinateSystem: 'polar',
      silent: true,
      z: 7,
      renderItem: function(params){
        let cx = params.coordSys.cx;
        let cy = params.coordSys.cy;
        let r = params.coordSys.r;
        let th = toCanvasRad(0);
        let ex = cx + r * Math.cos(th);
        let ey = cy + r * Math.sin(th);
        let active = !!lockVaZero;
        return {
          type: 'group',
          children: [
            {
              type: 'line',
              shape: { x1:cx, y1:cy, x2:ex, y2:ey },
              style: {
                stroke: active ? '#dc2626' : 'rgba(148,163,184,0.9)',
                lineWidth: active ? 3.2 : 1.8,
                lineDash: active ? null : [5,4]
              }
            }
          ]
        };
      },
      data: [0]
    };
  }

  let phasors = [
    { name:'Va', magKey:'voltage_an', angKey:'voltage_phase_a', color:'#ef4444', dashed:true, unit:'V', offset:[8,-14] },
    { name:'Vb', magKey:'voltage_bn', angKey:'voltage_phase_b', color:'#22c55e', dashed:true, unit:'V', offset:[-6,10] },
    { name:'Vc', magKey:'voltage_cn', angKey:'voltage_phase_c', color:'#0ea5e9', dashed:true, unit:'V', offset:[10,6] },
    { name:'Ia', magKey:'current_a',  angKey:'current_phase_a', color:'#b91c1c', dashed:false, unit:'A', offset:[4,-14] },
    { name:'Ib', magKey:'current_b',  angKey:'current_phase_b', color:'#166534', dashed:false, unit:'A', offset:[-6,10] },
    { name:'Ic', magKey:'current_c',  angKey:'current_phase_c', color:'#1d4ed8', dashed:false, unit:'A', offset:[10,2] }
  ];

  let chart = echarts.init(document.getElementById('chart'));

  function makePhasorSeries(p){
    return {
      name: p.name,
      type: 'custom',
      coordinateSystem: 'polar',
      data: [[Math.abs(num(p.magKey)), chartAngle(num(p.angKey))]],
      renderItem: function(params, api){
        let cx = params.coordSys.cx, cy = params.coordSys.cy;
        let mag = api.value(0), ang = norm360(api.value(1));
        let end = api.coord([mag, ang]);

        let sx = cx, sy = cy, ex = end[0], ey = end[1];
        let size = p.dashed ? 12 : 14;
        let half = size * 0.55;

        let dx = ex - sx, dy = ey - sy;
        let len = Math.hypot(dx, dy) || 1;
        dx /= len; dy /= len;

        let bx = ex - dx * size;
        let by = ey - dy * size;
        let px = -dy, py = dx;

        let t1 = [ex, ey];
        let t2 = [bx + px * half, by + py * half];
        let t3 = [bx - px * half, by - py * half];

        let ox = p.offset ? p.offset[0] : 0;
        let oy = p.offset ? p.offset[1] : 0;
        let labelText = p.name + ' ' + (mag||0).toFixed(2) + p.unit + ' @ ' + (ang||0).toFixed(1) + '°';

        return {
          type: 'group',
          children: [
            { type: 'line', shape: { x1:sx, y1:sy, x2:ex, y2:ey }, style: { stroke:p.color, lineWidth:p.dashed?2.5:3.2, lineDash:p.dashed?[6,4]:null } },
            { type: 'polygon', shape: { points:[t1,t2,t3] }, style: { fill:p.color } },
            {
              type: 'text',
              style: {
                x: ex + ox,
                y: ey + oy,
                text: labelText,
                fill: p.color,
                fontSize: p.dashed ? 11 : 12,
                align: 'left',
                verticalAlign: 'middle',
                backgroundColor: 'rgba(255,255,255,0.75)',
                padding: [2,4],
                borderRadius: 4
              }
            }
          ]
        };
      }
    };
  }

  function buildOption(){
    let mags = phasors.map(function(p){ return Math.abs(num(p.magKey)); });
    let rMax = Math.max(10, Math.ceil(Math.max.apply(null, mags) * 1.25));

    let VaA = chartAngle(num('voltage_phase_a'));
    let VbA = chartAngle(num('voltage_phase_b'));
    let VcA = chartAngle(num('voltage_phase_c'));

    let legendSeries = [
      { name:'Voltage', type:'scatter', coordinateSystem:'polar', data:[[0,0]], symbolSize:0, tooltip:{show:false}, silent:true },
      { name:'Current', type:'scatter', coordinateSystem:'polar', data:[[0,0]], symbolSize:0, tooltip:{show:false}, silent:true }
    ];

    let series = legendSeries
      .concat([ makeOuterRing() ])
      .concat([ makeCardinalLines() ])
      .concat(phasors.map(makePhasorSeries))
      .concat([
        makeArc(VaA, VbA, 0.5, '', '#ef4444', 1.08),
        makeArc(VbA, VcA, 0.5, '', '#22c55e', 1.08),
        makeArc(VcA, VaA, 0.5, '', '#0ea5e9', 1.08),
        makeArc(chartAngle(num('voltage_phase_a')), chartAngle(num('current_phase_a')), 0.17, 'φa', '#ef4444', 0.62, 18),
        makeArc(chartAngle(num('voltage_phase_b')), chartAngle(num('current_phase_b')), 0.23, 'φb', '#22c55e', 0.80, 18),
        makeArc(chartAngle(num('voltage_phase_c')), chartAngle(num('current_phase_c')), 0.26, 'φc', '#0ea5e9', 0.84, 18)
      ]);

    return {
      backgroundColor: '#fff',
      tooltip: {
        trigger: 'item',
        formatter: function(params){
          if (Array.isArray(params.value) && params.value.length >= 2) {
            return params.seriesName + '<br/>' + (params.value[0]||0).toFixed(2) + ' @ ' + (params.value[1]||0).toFixed(1) + '°';
          }
          return params.seriesName;
        }
      },
      legend: {
        top: 10,
        left: 'center',
        data: ['Voltage', 'Current'],
        formatter: function(name){
          if (name === 'Voltage') {
            return 'Voltage: Va ' + num('voltage_an').toFixed(1) + 'V @ ' + chartAngle(num('voltage_phase_a')).toFixed(0) +
                   '° | Vb ' + num('voltage_bn').toFixed(1) + 'V @ ' + chartAngle(num('voltage_phase_b')).toFixed(0) +
                   '° | Vc ' + num('voltage_cn').toFixed(1) + 'V @ ' + chartAngle(num('voltage_phase_c')).toFixed(0) + '°';
          }
          return 'Current: Ia ' + num('current_a').toFixed(1) + 'A @ ' + chartAngle(num('current_phase_a')).toFixed(0) +
                 '° | Ib ' + num('current_b').toFixed(1) + 'A @ ' + chartAngle(num('current_phase_b')).toFixed(0) +
                 '° | Ic ' + num('current_c').toFixed(1) + 'A @ ' + chartAngle(num('current_phase_c')).toFixed(0) + '°';
        },
        textStyle: { fontSize: 12, lineHeight: 16 }
      },
      polar: { center:['50%','53%'], radius:'84%' },
      angleAxis: {
        startAngle:0,
        clockwise:false,
        min:0,
        max:360,
        interval:30,
        axisLabel:{ show:true, formatter:'{value}°', color:'#64748b', fontSize:11, margin:12 },
        axisLine:{ show:true, lineStyle:{ color:'#cbd5e1', width:1 } },
        axisTick:{ show:true, length:5, lineStyle:{ color:'#94a3b8' } },
        splitLine:{ show:false }
      },
      radiusAxis: { min:0, max:rMax, splitNumber:8, axisLabel:{show:false}, axisLine:{show:false}, axisTick:{show:false}, splitLine:{show:true, lineStyle:{color:'#ddd'}} },
      series: series
    };
  }

  function setKV(containerId, rows){
    let el = document.getElementById(containerId);
    el.innerHTML = '';
    for (let i = 0; i < rows.length; i++) {
      let k = document.createElement('div');
      k.className = 'k';
      k.textContent = rows[i][0];

      let v = document.createElement('div');
      let cls = rows[i][2] || '';
      v.className = 'v' + (cls ? (' ' + cls) : '');

      if (rows[i][3]) v.innerHTML = rows[i][1];
      else v.textContent = rows[i][1];

      el.appendChild(k);
      el.appendChild(v);
    }
  }

  function pfClass(pf){
    let apf = Math.abs(pf);
    if (apf < TH_PF_ALARM) return 'alarm';
    if (apf < TH_PF_WARN) return 'warn';
    return 'ok';
  }
  function badge(text, level){ return '<span class="badge ' + level + '">' + text + '</span>'; }
  function fmtNum(x, digits){ return '<span class="num">' + (isFinite(x) ? x : 0).toFixed(digits) + '</span>'; }
  function fmtUnit(unit){ return '<span class="unit">' + unit + '</span>'; }
  function leadLagTag(isLag){ return isLag ? '<span class="tag lag">Lag</span>' : '<span class="tag lead">Lead</span>'; }

  function updateTimeDiff(){
    let el = document.getElementById('timeDiff');
    if (!el) return;
    let measuredAt = strv('measured_at');
    el.textContent = measuredAt && measuredAt !== '-' ? measuredAt : '-';
    el.style.color = '#64748b';
  }

  function updatePanels(){
    let pfRows = [];
    ['a','b','c'].forEach(function(ph){
      let th = norm180(num('current_phase_' + ph) - num('voltage_phase_' + ph));
      let pf = Math.cos(deg2rad(th));
      let isLag = (th >= 0);

      pfRows.push([
        'φ(I' + ph.toUpperCase() + '-V' + ph.toUpperCase() + ')',
        fmtNum(th,1) + fmtUnit('°'),
        'muted',
        true
      ]);

      pfRows.push([
        'PF(' + ph.toUpperCase() + ')',
        fmtNum(pf,3) + ' <span class="unit">(' + (isLag ? '유도성' : '용량성') + ')</span> ' + leadLagTag(isLag),
        pfClass(pf),
        true
      ]);
    });
    setKV('pfBox', pfRows);

    let Va = num('voltage_an'), Vb = num('voltage_bn'), Vc = num('voltage_cn');
    let vavg = (Va + Vb + Vc) / 3;
    let vdev = Math.max(Math.abs(Va-vavg), Math.abs(Vb-vavg), Math.abs(Vc-vavg));
    let vunb = (vavg > 1e-9) ? (vdev / vavg * 100) : 0;
    let vunbClass = (vunb > TH_V_UNBAL_ALARM) ? 'alarm' : (vunb > TH_V_UNBAL_WARN ? 'warn' : 'ok');

    let over = (vavg > 0 && (Va/vavg > TH_V_OVER || Vb/vavg > TH_V_OVER || Vc/vavg > TH_V_OVER));
    let under = (vavg > 0 && (Va/vavg < TH_V_UNDER || Vb/vavg < TH_V_UNDER || Vc/vavg < TH_V_UNDER));

    let pfA = Math.cos(deg2rad(norm180(num('current_phase_a') - num('voltage_phase_a'))));
    let pfB = Math.cos(deg2rad(norm180(num('current_phase_b') - num('voltage_phase_b'))));
    let pfC = Math.cos(deg2rad(norm180(num('current_phase_c') - num('voltage_phase_c'))));
    let minPf = Math.min(Math.abs(pfA), Math.abs(pfB), Math.abs(pfC));

    setKV('alarmBox', [
      ['Vavg', fmtNum(vavg,2) + fmtUnit('V'), '', true],
      ['전압 불평형', fmtNum(vunb,2) + fmtUnit('%'), vunbClass, true],
      ['과전압', over ? badge('YES','alarm') : badge('NO','ok'), '', true],
      ['저전압', under ? badge('YES','alarm') : badge('NO','ok'), '', true],
      ['최소 PF', fmtNum(minPf,3), pfClass(minPf), true]
    ]);

    let VaC = cFromPolar(Va, num('voltage_phase_a'));
    let VbC = cFromPolar(Vb, num('voltage_phase_b'));
    let VcC = cFromPolar(Vc, num('voltage_phase_c'));
    let IaC = cFromPolar(num('current_a'), num('current_phase_a'));
    let IbC = cFromPolar(num('current_b'), num('current_phase_b'));
    let IcC = cFromPolar(num('current_c'), num('current_phase_c'));

    let Vs = symComp(VaC, VbC, VcC);
    let Is = symComp(IaC, IbC, IcC);

    let V0m = cAbs(Vs.V0), V1m = cAbs(Vs.V1), V2m = cAbs(Vs.V2);
    let I0m = cAbs(Is.V0), I1m = cAbs(Is.V1), I2m = cAbs(Is.V2);

    let Vunb2 = (V1m > 1e-9) ? (V2m / V1m * 100) : 0;
    let Iunb2 = (I1m > 1e-9) ? (I2m / I1m * 100) : 0;
    let Vunb0 = (V1m > 1e-9) ? (V0m / V1m * 100) : 0;
    let Iunb0 = (I1m > 1e-9) ? (I0m / I1m * 100) : 0;

    function unbClass(pct){
      if (pct >= 10) return 'alarm';
      if (pct >= 5) return 'warn';
      return 'ok';
    }

    setKV('seqBox', [
      ['V0', fmtNum(V0m,2)+fmtUnit('V')+' <span class="unit">@</span> '+fmtNum(norm180(cArgDeg(Vs.V0)),1)+fmtUnit('°'), '', true],
      ['V0/V1', fmtNum(Vunb0,2)+fmtUnit('%'), unbClass(Vunb0), true],
      ['V1', fmtNum(V1m,2)+fmtUnit('V')+' <span class="unit">@</span> '+fmtNum(norm180(cArgDeg(Vs.V1)),1)+fmtUnit('°'), '', true],
      ['V2', fmtNum(V2m,2)+fmtUnit('V')+' <span class="unit">@</span> '+fmtNum(norm180(cArgDeg(Vs.V2)),1)+fmtUnit('°'), '', true],
      ['V2/V1', fmtNum(Vunb2,2)+fmtUnit('%'), unbClass(Vunb2), true],
      ['I0', fmtNum(I0m,2)+fmtUnit('A')+' <span class="unit">@</span> '+fmtNum(norm180(cArgDeg(Is.V0)),1)+fmtUnit('°'), '', true],
      ['I0/I1', fmtNum(Iunb0,2)+fmtUnit('%'), unbClass(Iunb0), true],
      ['I1', fmtNum(I1m,2)+fmtUnit('A')+' <span class="unit">@</span> '+fmtNum(norm180(cArgDeg(Is.V1)),1)+fmtUnit('°'), '', true],
      ['I2', fmtNum(I2m,2)+fmtUnit('A')+' <span class="unit">@</span> '+fmtNum(norm180(cArgDeg(Is.V2)),1)+fmtUnit('°'), '', true],
      ['I2/I1', fmtNum(Iunb2,2)+fmtUnit('%'), unbClass(Iunb2), true]
    ]);
    updateTimeDiff();
  }

  function render(){
    chart.setOption(buildOption(), true);
    updatePanels();
    autoCollapseSideIfNeeded();
  }

  async function pollOnce(){
    try {
      let va0Query = lockVaZero ? '&va0=1' : '';
      let url = location.pathname + '?meter=' + encodeURIComponent(selectedMeter) + '&ajax=1' + va0Query;
      let res = await fetch(url, { cache: 'no-store' });
      if (!res.ok) return;
      data = await res.json();
      render();
    } catch (e) {
      // no-op
    }
  }

  window.addEventListener('resize', function(){
    chart.resize();
    autoCollapseSideIfNeeded();
  });
  let va0Opt = document.getElementById('va0Opt');
  let va0Wrap = document.getElementById('va0Wrap');
  function syncVa0Visual(){
    if (!va0Wrap || !va0Opt) return;
    va0Wrap.classList.toggle('active', !!va0Opt.checked);
  }
  syncVa0Visual();
  if (va0Opt) {
    va0Opt.addEventListener('change', function(){
      lockVaZero = !!va0Opt.checked;
      syncVa0Visual();
      render();
    });
  }
  let meterSel = document.getElementById('meter');
  let scanLabel = document.getElementById('scanLabel');
  let scanIntervalSel = document.getElementById('scanInterval');
  let scanStartBtn = document.getElementById('scanStart');
  let scanStopBtn = document.getElementById('scanStop');
  let secToggles = document.querySelectorAll('.sec-toggle');
  let sidePanel = document.querySelector('.side');
  let meterIds = meterSel ? Array.prototype.map.call(meterSel.options, function(opt){ return opt.value; }) : [];

  function setSectionCollapsed(secId, collapsed){
    let sec = document.getElementById(secId);
    if (!sec) return;
    let btn = sec.querySelector('.sec-toggle');
    sec.classList.toggle('collapsed', !!collapsed);
    if (btn) btn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
  }

  function autoCollapseSideIfNeeded(){
    if (!sidePanel) return;
    if (sidePanel.scrollHeight <= sidePanel.clientHeight) return;
    let order = ['secAlarm', 'secPf'];
    for (let i = 0; i < order.length; i++) {
      if (sidePanel.scrollHeight <= sidePanel.clientHeight) break;
      setSectionCollapsed(order[i], true);
    }
  }

  for (let t = 0; t < secToggles.length; t++) {
    secToggles[t].addEventListener('click', function(){
      let sec = this.closest('.summary-sec');
      if (!sec) return;
      sec.classList.toggle('collapsed');
      this.setAttribute('aria-expanded', sec.classList.contains('collapsed') ? 'false' : 'true');
    });
  }

  function setScanUi(running){
    isScanning = !!running;
    if (scanStartBtn) scanStartBtn.disabled = isScanning || meterIds.length === 0;
    if (scanStopBtn) scanStopBtn.disabled = !isScanning;
    if (scanIntervalSel) scanIntervalSel.disabled = (meterIds.length === 0);
    if (scanLabel) {
      if (meterIds.length === 0) scanLabel.textContent = '스캔주기(계측기 없음)';
      else if (isScanning) scanLabel.textContent = '스캔주기(스캔 중)';
      else scanLabel.textContent = '스캔주기(수동 모드)';
    }
  }

  function startManualPolling(){
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(function(){
      if (!isScanning && selectedMeter) pollOnce();
    }, POLL_MS);
  }

  function stopScan(){
    if (scanTimer) {
      clearInterval(scanTimer);
      scanTimer = null;
    }
    setScanUi(false);
    startManualPolling();
  }

  function scanTick(){
    if (!meterIds.length) return;
    if (scanIndex >= meterIds.length) scanIndex = 0;
    selectedMeter = meterIds[scanIndex];
    if (meterSel) meterSel.value = selectedMeter;
    scanIndex = (scanIndex + 1) % meterIds.length;
    pollOnce();
  }

  function startScan(){
    if (!meterIds.length) {
      setScanUi(false);
      return;
    }
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
    if (scanTimer) clearInterval(scanTimer);
    let ms = parseInt(scanIntervalSel ? scanIntervalSel.value : '3000', 10);
    if (!isFinite(ms) || ms <= 0) ms = 3000;
    let curIdx = meterIds.indexOf(selectedMeter);
    scanIndex = (curIdx >= 0) ? curIdx : 0;
    setScanUi(true);
    scanTick();
    scanTimer = setInterval(scanTick, ms);
  }

  if (scanStartBtn) scanStartBtn.addEventListener('click', startScan);
  if (scanStopBtn) scanStopBtn.addEventListener('click', stopScan);
  if (scanIntervalSel) {
    scanIntervalSel.addEventListener('change', function(){
      if (isScanning) startScan();
    });
  }

  render();
  setScanUi(false);
  startManualPolling();
})();
</script>
</body>
</html>

