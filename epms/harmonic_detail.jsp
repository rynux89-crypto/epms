<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.Locale" %>
<%@ include file="../includes/dbconn.jsp" %>

<%
    String harmonicId = request.getParameter("harmonic_id");
    String mode = request.getParameter("mode");
    if (mode == null || mode.trim().isEmpty()) mode = "current";
    mode = "voltage".equalsIgnoreCase(mode) ? "voltage" : "current";

    String modeLabel = "current".equals(mode) ? "전류" : "전압";
    String backPage = "current".equals(mode) ? "harmonics_i.jsp" : "harmonics_v.jsp";
    double limitValue = "current".equals(mode) ? 20.0 : 3.0;

    String meterName = "-";
    String buildingName = "-";
    String usageType = "-";
    String panelName = "-";
    String measuredAt = "-";

    double h3a = 0, h5a = 0, h7a = 0, h9a = 0, h11a = 0, thdA = 0;
    double h3b = 0, h5b = 0, h7b = 0, h9b = 0, h11b = 0, thdB = 0;
    double h3c = 0, h5c = 0, h7c = 0, h9c = 0, h11c = 0, thdC = 0;

    boolean hasData = false;

    if (harmonicId != null && !harmonicId.trim().isEmpty()) {
        try {
            String sql = "SELECT meter_name, panel_name, building_name, usage_type, measured_at, " +
                         "thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
                         "thd_current_a, thd_current_b, thd_current_c, " +
                         "voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
                         "voltage_h3_b, voltage_h5_b, voltage_h7_b, voltage_h9_b, voltage_h11_b, " +
                         "voltage_h3_c, voltage_h5_c, voltage_h7_c, voltage_h9_c, voltage_h11_c, " +
                         "current_h3_a, current_h5_a, current_h7_a, current_h9_a, current_h11_a, " +
                         "current_h3_b, current_h5_b, current_h7_b, current_h9_b, current_h11_b, " +
                         "current_h3_c, current_h5_c, current_h7_c, current_h9_c, current_h11_c " +
                         "FROM vw_harmonic_measurements WHERE harmonic_id = ?";

            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, harmonicId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        hasData = true;
                        meterName = rs.getString("meter_name");
                        panelName = rs.getString("panel_name");
                        buildingName = rs.getString("building_name");
                        usageType = rs.getString("usage_type");

                        Timestamp ts = rs.getTimestamp("measured_at");
                        measuredAt = (ts != null) ? ts.toString() : "-";

                        if ("current".equals(mode)) {
                            thdA = rs.getDouble("thd_current_a");
                            h3a = rs.getDouble("current_h3_a"); h5a = rs.getDouble("current_h5_a");
                            h7a = rs.getDouble("current_h7_a"); h9a = rs.getDouble("current_h9_a"); h11a = rs.getDouble("current_h11_a");

                            thdB = rs.getDouble("thd_current_b");
                            h3b = rs.getDouble("current_h3_b"); h5b = rs.getDouble("current_h5_b");
                            h7b = rs.getDouble("current_h7_b"); h9b = rs.getDouble("current_h9_b"); h11b = rs.getDouble("current_h11_b");

                            thdC = rs.getDouble("thd_current_c");
                            h3c = rs.getDouble("current_h3_c"); h5c = rs.getDouble("current_h5_c");
                            h7c = rs.getDouble("current_h7_c"); h9c = rs.getDouble("current_h9_c"); h11c = rs.getDouble("current_h11_c");
                        } else {
                            thdA = rs.getDouble("thd_voltage_a");
                            h3a = rs.getDouble("voltage_h3_a"); h5a = rs.getDouble("voltage_h5_a");
                            h7a = rs.getDouble("voltage_h7_a"); h9a = rs.getDouble("voltage_h9_a"); h11a = rs.getDouble("voltage_h11_a");

                            thdB = rs.getDouble("thd_voltage_b");
                            h3b = rs.getDouble("voltage_h3_b"); h5b = rs.getDouble("voltage_h5_b");
                            h7b = rs.getDouble("voltage_h7_b"); h9b = rs.getDouble("voltage_h9_b"); h11b = rs.getDouble("voltage_h11_b");

                            thdC = rs.getDouble("thd_voltage_c");
                            h3c = rs.getDouble("voltage_h3_c"); h5c = rs.getDouble("voltage_h5_c");
                            h7c = rs.getDouble("voltage_h7_c"); h9c = rs.getDouble("voltage_h9_c"); h11c = rs.getDouble("voltage_h11_c");
                        }
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
%>

<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <title>고조파 상세 분석</title>
  <script src="../js/echarts.js"></script>
  <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
  <style>
    .chartBox { width: 100%; height: 250px; margin-top: 10px; }
    .panel { background: #fff; border: 1px solid #ddd; padding: 15px; border-radius: 5px; margin-bottom: 10px; }
    .title-A { color: #5a3908; }
    .title-B { color: #9C27B0; }
    .title-C { color: #607D8B; }
    .title-actions { margin-left: auto; display: inline-flex; gap: 8px; align-items: center; }
    .mode-chip {
      display: inline-flex;
      align-items: center;
      padding: 4px 10px;
      border-radius: 999px;
      border: 1px solid #cdd9e8;
      background: #eef4fb;
      color: #24496e;
      font-size: 12px;
      font-weight: 700;
    }
    .back-btn.active-mode {
      background: #1f6feb;
      color: #fff;
      border-color: #1f6feb;
      cursor: default;
      opacity: 1;
    }
  </style>
</head>
<body>
<header>
  <div class="title-bar">
    <h2>🎵 고조파 상세 분석 (<%= modeLabel %>)</h2>
    <div class="title-actions">
      <span class="mode-chip">현재: <%= "current".equals(mode) ? "전류보기" : "전압보기" %></span>
      <button class="back-btn" onclick="location.href='<%= backPage %>'">돌아가기</button>
      <% if ("voltage".equals(mode)) { %>
      <button class="back-btn" onclick="switchMode('current')">전류보기</button>
      <% } else { %>
      <button class="back-btn" onclick="switchMode('voltage')">전압보기</button>
      <% } %>
    </div>
  </div>
  <div class="meta-bar">
    <div class="meta-info" style="width:100%; background:#f0f2f5; border-left:4px solid #007bff; padding:8px 12px; border-radius:0 4px 4px 0; font-size:13px; color:#444; margin-top:5px;">
      <span style="font-weight:bold;">Current View:</span>
      <span style="margin-left:10px;">계량기: <strong><%= meterName %></strong></span>
      <span style="margin-left:10px;">패널: <%= panelName %></span>
      <span style="margin-left:10px;">건물: <%= buildingName %></span>
      <span style="margin-left:10px;">용도: <%= usageType %></span>
      <span style="margin-left:10px;">구분: <%= modeLabel %> 고조파</span>
      <span style="margin-left:10px; color:#666;">(<%= measuredAt %>)</span>
    </div>
  </div>
</header>

<% if (!hasData) { %>
  <div style="margin:12px 0;padding:10px 12px;border:1px solid #ffd6d6;background:#fff3f3;color:#b42318;border-radius:10px;font-weight:700;">데이터가 없습니다</div>
<% } %>

<main>
  <section class="grid_h">
    <div class="panel">
      <h3 class="title-A">A상 (Phase A)</h3>
      <div>THD: <span id="thdA" style="font-weight:bold; color:#5a3908;">-</span>%</div>
      <div class="chartBox"><div id="waveA" style="width:100%; height:100%;"></div></div>
      <div class="chartBox"><div id="fftA"  style="width:100%; height:100%;"></div></div>
    </div>

    <div class="panel">
      <h3 class="title-B">B상 (Phase B)</h3>
      <div>THD: <span id="thdB" style="font-weight:bold; color:#9C27B0;">-</span>%</div>
      <div class="chartBox"><div id="waveB" style="width:100%; height:100%;"></div></div>
      <div class="chartBox"><div id="fftB"  style="width:100%; height:100%;"></div></div>
    </div>

    <div class="panel">
      <h3 class="title-C">C상 (Phase C)</h3>
      <div>THD: <span id="thdC" style="font-weight:bold; color:#607D8B;">-</span>%</div>
      <div class="chartBox"><div id="waveC" style="width:100%; height:100%;"></div></div>
      <div class="chartBox"><div id="fftC"  style="width:100%; height:100%;"></div></div>
    </div>
  </section>
</main>

<script>
  const f0 = 60;
  const LIMIT = <%= String.format(Locale.US, "%.1f", limitValue) %>;

  const PHASE_COLORS = {
    A: '#5a3908',
    B: '#9C27B0',
    C: '#607D8B'
  };

  const dataStore = {
    A: { h1: 100, h3: <%= h3a %>, h5: <%= h5a %>, h7: <%= h7a %>, h9: <%= h9a %>, h11: <%= h11a %>, thd: <%= thdA %> },
    B: { h1: 100, h3: <%= h3b %>, h5: <%= h5b %>, h7: <%= h7b %>, h9: <%= h9b %>, h11: <%= h11b %>, thd: <%= thdB %> },
    C: { h1: 100, h3: <%= h3c %>, h5: <%= h5c %>, h7: <%= h7c %>, h9: <%= h9c %>, h11: <%= h11c %>, thd: <%= thdC %> }
  };

  ['A', 'B', 'C'].forEach(p => {
    const el = document.getElementById('thd' + p);
    if (el) el.textContent = Number(dataStore[p].thd || 0).toFixed(2);
  });

  function switchMode(nextMode) {
    const u = new URL(window.location.href);
    u.searchParams.set('mode', nextMode);
    window.location.href = u.toString();
  }

  const N = 1000;
  const T = 1 / f0;
  const dt = T / N;
  const timeMs = Array.from({ length: N }, (_, i) => i * dt * 1000);

  function makeSignal(amps) {
    const orders = [1, 3, 5, 7, 9, 11];
    return timeMs.map((_, i) => {
      const t = i * dt;
      return orders.reduce((sum, h) => sum + Math.sin(2 * Math.PI * h * f0 * t) * ((amps['h' + h] || 0) / 100), 0);
    });
  }

  const chartInstances = [];

  function drawWave(id, pKey) {
    const dom = document.getElementById(id);
    if (!dom) return;
    const chart = echarts.init(dom);
    const signal = makeSignal(dataStore[pKey]);
    chart.setOption({
      title: { text: pKey + '상 합성 파형', left: 'center', textStyle: { color: PHASE_COLORS[pKey] } },
      grid: { left: 45, right: 15, bottom: 52, top: 40, containLabel: true },
      xAxis: {
        type: 'value',
        name: '시간 (ms)',
        nameLocation: 'middle',
        nameGap: 30,
        axisLabel: {
          show: true,
          formatter: function(v) { return Number(v).toFixed(1); }
        }
      },
      yAxis: { type: 'value', scale: true },
      series: [{
        type: 'line',
        data: timeMs.map((t, i) => [t, signal[i]]),
        showSymbol: false,
        lineStyle: { color: PHASE_COLORS[pKey], width: 2 }
      }]
    });
    chartInstances.push(chart);
  }

  function drawFFT(id, pKey) {
    const dom = document.getElementById(id);
    if (!dom) return;
    const chart = echarts.init(dom);
    const orders = [3, 5, 7, 9, 11];
    const amps = dataStore[pKey];

    chart.setOption({
      title: { text: pKey + '상 차수별 고조파', left: 'center', textStyle: { color: PHASE_COLORS[pKey] } },
      tooltip: {
        trigger: 'axis',
        formatter: function(params) {
          if (!params || !params.length) return '';
          const p = params[0];
          const v = Number(p.value);
          return p.axisValue + '<br/>' + (Number.isFinite(v) ? v.toFixed(2) : '0.00') + '%';
        }
      },
      grid: { left: 45, right: 15, bottom: 30, top: 40 },
      xAxis: { type: 'category', data: orders.map(h => h + '차') },
      yAxis: { type: 'value', max: v => Math.max(5, Math.ceil(v.max / 5) * 5) },
      series: [
        {
          type: 'bar',
          data: orders.map(h => ({
            value: amps['h' + h],
            itemStyle: { color: amps['h' + h] > LIMIT ? '#FF0000' : PHASE_COLORS[pKey] }
          })),
          label: {
            show: true,
            position: 'top',
            formatter: function(p) {
              const v = Number(p.value);
              return (Number.isFinite(v) ? v.toFixed(2) : '0.00') + '%';
            }
          }
        },
        {
          type: 'line',
          symbol: 'none',
          data: new Array(5).fill(LIMIT),
          lineStyle: { type: 'dashed', color: '#FF0000', width: 2 }
        }
      ]
    });
    chartInstances.push(chart);
  }

  window.addEventListener('load', function() {
    ['A', 'B', 'C'].forEach(function(p) {
      drawWave('wave' + p, p);
      drawFFT('fft' + p, p);
    });
  });

  window.addEventListener('resize', function() {
    chartInstances.forEach(c => c.resize());
  });
</script>
</body>
</html>
