<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*, java.util.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%
try (Connection conn = openDbConnection()) {
    //request.setCharacterEncoding("UTF-8");

    // meter_id는 문자열
    String meterId = request.getParameter("meter_id");
    boolean hasMeterId = (meterId != null && !meterId.trim().isEmpty());
    boolean hasData    = false;   // 실제 측정 데이터 존재 여부
    
    int selectedIndex = -1;

    if (meterId != null && !meterId.isEmpty()) {
        selectedIndex = Integer.parseInt(meterId);
    }


    //if (!hasMeterId) { meterId = ""; }
    

    // meter 목록 조회용
    List<String[]> meterOptions = new ArrayList<>(); // [id, name]
    try (PreparedStatement psOpt = conn.prepareStatement(
            "SELECT meter_id, name " +
            "FROM meters " +
            "WHERE UPPER(COALESCE(name, '')) LIKE '%VCB%' " +
            "   OR UPPER(COALESCE(name, '')) LIKE '%ACB%' " +
            "   OR UPPER(COALESCE(panel_name, '')) LIKE '%VCB%' " +
            "   OR UPPER(COALESCE(panel_name, '')) LIKE '%ACB%' " +
            "ORDER BY meter_id")) {
        try (ResultSet rsOpt = psOpt.executeQuery()) {
            while(rsOpt.next()) {
                meterOptions.add(new String[]{ rsOpt.getString("meter_id"), rsOpt.getString("name") });
            }
        }
    } catch(Exception e) { out.println("옵션 조회 오류: " + e.getMessage()); }

    // 선택된 인덱스로 meter_id, meter_name 결정
    String meter_id = null;
    String meterName = null;

    if (selectedIndex >= 0 && selectedIndex < meterOptions.size()) {
        meter_id = meterOptions.get(selectedIndex)[0];
        meterName = meterOptions.get(selectedIndex)[1];
    }


    //out.println(meter_id );
    //out.println(selectedIndex);
    //out.println(meterId);

    meterId = meter_id;


    // ====== 공통 메타 정보 ======
    // meterName    = "-";
    String panelName    = "-";
    String buildingName = "-";
    String usageType    = "-";

    // ====== measurements / vw_meter_measurements 기준 계측값 ======
    Timestamp measuredAt         = null;
    double voltage_ab            = 0;
    double voltage_bc            = 0;
    double voltage_ca            = 0;
    double voltage_an            = 0;
    double voltage_bn            = 0;
    double voltage_cn            = 0;
    double current_a             = 0;
    double current_b             = 0;
    double current_c             = 0;
    double current_n             = 0;
    double average_voltage       = 0;
    double phase_voltage_avg     = 0;
    double line_voltage_avg      = 0;
    double average_current       = 0;
    double frequency             = 0;
    double power_factor_a        = 0;
    double power_factor_b        = 0;
    double power_factor_c        = 0;
    double active_power_total    = 0;
    double reactive_power_total  = 0;
    double apparent_power_total  = 0;
    double energy_consumed_total = 0;
    double energy_generated_total= 0;
    double voltage_unbalance_rate= 0;
    double harmonic_distortion_rate = 0;
    String quality_status        = "";

    // ====== harmonic_measurements / vw_harmonic_measurements 기준 ======
    double thd_voltage_a = 0, thd_voltage_b = 0, thd_voltage_c = 0;
    double voltage_h3_a = 0, voltage_h5_a = 0, voltage_h7_a = 0, voltage_h9_a = 0, voltage_h11_a = 0;
    double voltage_h3_b = 0, voltage_h5_b = 0, voltage_h7_b = 0, voltage_h9_b = 0, voltage_h11_b = 0;
    double voltage_h3_c = 0, voltage_h5_c = 0, voltage_h7_c = 0, voltage_h9_c = 0, voltage_h11_c = 0;

    // ====== flicker_measurements / vw_flicker_with_meter 기준 ======
    double flicker_pst = 0;
    double flicker_plt = 0;

    // ====== voltage_events / vw_voltage_event_log 기준 이벤트 집계 ======
    int sagCount = 0;
    int swellCount = 0;
    int otherVoltageEvents = 0;

    // ====== alarm_log / vw_alarm_log 기준 알람 집계 ======
    int totalAlarms = 0;

    try {
        if (hasMeterId) {
            // 1) 최신 계측값: vw_meter_measurements
            String sqlMeas =
                "SELECT TOP 1 " +
                "  meter_id, meter_name, panel_name, building_name, usage_type, " +
                "  measured_at, " +
                "  voltage_ab, voltage_bc, voltage_ca, " +
                "  voltage_an, voltage_bn, voltage_cn, " +
                "  current_a, current_b, current_c, current_n, " +
                "  average_voltage, average_current, " +
                "  frequency, " +
                "  power_factor_a, power_factor_b, power_factor_c, " +
                "  active_power_total, reactive_power_total, apparent_power_total, " +
                "  energy_consumed_total, energy_generated_total, " +
                "  voltage_unbalance_rate, harmonic_distortion_rate, quality_status " +
                "FROM vw_meter_measurements " +
                "WHERE meter_id = ? " +
                "ORDER BY measured_at DESC";

            try (PreparedStatement ps = conn.prepareStatement(sqlMeas)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        hasData = true;

                        meterName    = rs.getString("meter_name");
                        panelName    = rs.getString("panel_name");
                        buildingName = rs.getString("building_name");
                        usageType    = rs.getString("usage_type");

                        measuredAt   = rs.getTimestamp("measured_at");

                        voltage_ab   = rs.getDouble("voltage_ab");
                        voltage_bc   = rs.getDouble("voltage_bc");
                        voltage_ca   = rs.getDouble("voltage_ca");
                        voltage_an   = rs.getDouble("voltage_an");
                        voltage_bn   = rs.getDouble("voltage_bn");
                        voltage_cn   = rs.getDouble("voltage_cn");

                        current_a    = rs.getDouble("current_a");
                        current_b    = rs.getDouble("current_b");
                        current_c    = rs.getDouble("current_c");
                        current_n    = rs.getDouble("current_n");

                        average_voltage = rs.getDouble("average_voltage");
                        average_current = rs.getDouble("average_current");
                        phase_voltage_avg = (voltage_an + voltage_bn + voltage_cn) / 3.0;
                        line_voltage_avg  = (voltage_ab + voltage_bc + voltage_ca) / 3.0;

                        frequency    = rs.getDouble("frequency");
                        power_factor_a = rs.getDouble("power_factor_a");
                        power_factor_b = rs.getDouble("power_factor_b");
                        power_factor_c = rs.getDouble("power_factor_c");

                        active_power_total   = rs.getDouble("active_power_total");
                        reactive_power_total = rs.getDouble("reactive_power_total");
                        apparent_power_total = rs.getDouble("apparent_power_total");

                        energy_consumed_total = rs.getDouble("energy_consumed_total");
                        energy_generated_total = rs.getDouble("energy_generated_total");

                        voltage_unbalance_rate   = rs.getDouble("voltage_unbalance_rate");
                        harmonic_distortion_rate = rs.getDouble("harmonic_distortion_rate");
                        quality_status           = rs.getString("quality_status");
                    }
                }
            }

            // 데이터가 하나도 없으면 나머지 쿼리는 굳이 안 해도 되지만
            // 그래도 meter_id 기준으로 고조파/플리커/이벤트는 있을 수 있으니 계속 진행
            // (필요하면 if (hasData) { ... } 로 감싸도 됨)

            // 2) 최신 고조파: vw_harmonic_measurements
            String sqlHarm =
                "SELECT TOP 1 " +
                "  thd_voltage_a, thd_voltage_b, thd_voltage_c, " +
                "  voltage_h3_a, voltage_h5_a, voltage_h7_a, voltage_h9_a, voltage_h11_a, " +
                "  voltage_h3_b, voltage_h5_b, voltage_h7_b, voltage_h9_b, voltage_h11_b, " +
                "  voltage_h3_c, voltage_h5_c, voltage_h7_c, voltage_h9_c, voltage_h11_c " +
                "FROM vw_harmonic_measurements " +
                "WHERE meter_id = ? " +
                "ORDER BY measured_at DESC";

            try (PreparedStatement ps = conn.prepareStatement(sqlHarm)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        thd_voltage_a = rs.getDouble("thd_voltage_a");
                        thd_voltage_b = rs.getDouble("thd_voltage_b");
                        thd_voltage_c = rs.getDouble("thd_voltage_c");

                        voltage_h3_a = rs.getDouble("voltage_h3_a");
                        voltage_h5_a = rs.getDouble("voltage_h5_a");
                        voltage_h7_a = rs.getDouble("voltage_h7_a");
                        voltage_h9_a = rs.getDouble("voltage_h9_a");
                        voltage_h11_a = rs.getDouble("voltage_h11_a");

                        voltage_h3_b = rs.getDouble("voltage_h3_b");
                        voltage_h5_b = rs.getDouble("voltage_h5_b");
                        voltage_h7_b = rs.getDouble("voltage_h7_b");
                        voltage_h9_b = rs.getDouble("voltage_h9_b");
                        voltage_h11_b = rs.getDouble("voltage_h11_b");

                        voltage_h3_c = rs.getDouble("voltage_h3_c");
                        voltage_h5_c = rs.getDouble("voltage_h5_c");
                        voltage_h7_c = rs.getDouble("voltage_h7_c");
                        voltage_h9_c = rs.getDouble("voltage_h9_c");
                        voltage_h11_c = rs.getDouble("voltage_h11_c");
                    }
                }
            }

            // 3) 최신 플리커: vw_flicker_with_meter
            String sqlFlicker =
                "SELECT TOP 1 flicker_pst, flicker_plt " +
                "FROM vw_flicker_with_meter " +
                "WHERE meter_id = ? " +
                "ORDER BY measured_at DESC";

            try (PreparedStatement ps = conn.prepareStatement(sqlFlicker)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        flicker_pst = rs.getDouble("flicker_pst");
                        flicker_plt = rs.getDouble("flicker_plt");
                    }
                }
            }

            // 4) 최근 7일 전압 이벤트 집계: vw_voltage_event_log
            String sqlVoltEvent =
                "SELECT event_type, COUNT(*) AS cnt " +
                "FROM vw_voltage_event_log " +
                "WHERE meter_id = ? " +
                "  AND triggered_at >= DATEADD(DAY, -7, GETDATE()) " +
                "GROUP BY event_type";

            try (PreparedStatement ps = conn.prepareStatement(sqlVoltEvent)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        String etype = rs.getString("event_type");
                        int cnt = rs.getInt("cnt");
                        if ("sag".equalsIgnoreCase(etype)) {
                            sagCount += cnt;
                        } else if ("swell".equalsIgnoreCase(etype)) {
                            swellCount += cnt;
                        } else {
                            otherVoltageEvents += cnt;
                        }
                    }
                }
            }

            // 5) 최근 7일 알람 건수: vw_alarm_log
            String sqlAlarm =
                "SELECT COUNT(*) AS cnt " +
                "FROM vw_alarm_log " +
                "WHERE meter_id = ? " +
                "  AND triggered_at >= DATEADD(DAY, -7, GETDATE())";

            try (PreparedStatement ps = conn.prepareStatement(sqlAlarm)) {
                ps.setString(1, meterId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        totalAlarms = rs.getInt("cnt");
                    }
                }
            }
        }
    } catch (Exception e) {
        e.printStackTrace();
    }

    String measuredAtStr = (measuredAt != null ? measuredAt.toString() : "-");
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>계측기 상태 모니터링</title>
    <script src="../js/chart.js"></script>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
</head>
<body class="page-meter-status">
  <div class="dash">
    <div class="dash-top">
      <div class="title-bar">
          <h2>📊 계측기 상세 모니터링</h2>
          <div class="inline-actions">
              <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'" >EPMS 홈</button>
          </div>
      </div>

      <!-- 🔍 조회 조건 폼 -->
      <form method="GET" class="search-form">
        <div class="form-row">
          <div class="card meter-box">
            <label>Meter:</label>
            <select name="meter_id">
              <% for(int i=0; i<meterOptions.size(); i++) { %>
                <option value="<%= i %>" <%= (i == selectedIndex ? "selected" : "") %>>
                  <%= meterOptions.get(i)[1] %>
                </option>
              <% } %>
            </select>
            <button type="submit">조회</button>
          </div>

          <!-- 🔄 자동 새로고침 -->
          <div class="card refresh-box">
            <span>자동 새로고침:</span>
            <label><input type="radio" name="refresh" value="5000"> 5초</label>
            <label><input type="radio" name="refresh" value="10000"> 10초</label>
            <label><input type="radio" name="refresh" value="30000"> 30초</label>
            <label><input type="radio" name="refresh" value="60000"> 1분</label>
            <label><input type="radio" name="refresh" value="off"> 해제</label>
          </div>
        </div>
      </form>

      <% if (!hasData) { %>
        <div style="margin:12px 0;padding:10px 12px;border:1px solid #ffd6d6;background:#fff3f3;color:#b42318;border-radius:10px;font-weight:700;">데이터가 없습니다</div>
      <% } %>

      <script>
        (function () {
          let refreshTimer = null;

          function startRefresh(ms) {
            if (refreshTimer) clearInterval(refreshTimer);
            refreshTimer = null;

            if (ms && Number.isFinite(ms) && ms > 0) {
              refreshTimer = setInterval(() => location.reload(), ms);
            }
          }

          function selectedFromQuery() {
            const params = new URLSearchParams(location.search);
            const v = params.get("refresh"); // "10000" | "30000" | "60000" | null
            return (v && /^\d+$/.test(v)) ? v : "off";
          }

          function syncUIAndTimer() {
            const selected = selectedFromQuery();

            // ✅ 화면 표시(체크) 확실히 반영
            document.querySelectorAll('input[name="refresh"]').forEach(r => {
              r.checked = (r.value === selected);
            });

            // ✅ 타이머 반영
            startRefresh(selected === "off" ? null : Number(selected));
          }

          function setQueryAndReload(value) {
            const params = new URLSearchParams(location.search);

            if (value === "off") params.delete("refresh");
            else params.set("refresh", value);

            location.search = params.toString(); // 즉시 반영 + 리로드
          }

          window.addEventListener("DOMContentLoaded", () => {
            // 로드시 체크 복원 + 타이머 시작
            syncUIAndTimer();

            // 이벤트 바인딩 (DOM 로드된 뒤라 100% 붙음)
            document.querySelectorAll('input[name="refresh"]').forEach(radio => {
              radio.addEventListener("change", function () {
                setQueryAndReload(this.value);
              });
            });
          });
        })();
      </script>

      <% if (!hasMeterId) { %>
          <div class="alert-box">
              meter_id 파라미터가 없습니다. 계측기를 선택한 뒤 다시 시도하세요.
          </div>
      <% } else if (!hasData) { %>
          <div class="alert-box">
              지정한 계측기(<strong><%= meterId %></strong>)에 대한 최근 계측 데이터가 없습니다.
          </div>
      <% } else { %>
      <div class="meta-info" style="margin-top:5px;">
          <span>Meter : <strong><%= meterName %></strong></span>
          <span>Panel : <strong><%= panelName %></strong></span>
          <span>Building : <strong><%= buildingName %></strong></span>
          <span>Usage : <strong><%= usageType %></strong></span>
          <span>마지막 계측시각: <strong><%= measuredAtStr.substring(0,19) %></strong></span>      
      </div>
      <br>
      <% } %>  

    <%
        // meter_id도 있고 데이터도 있을 때만 대시보드 렌더링
        if (hasMeterId && hasData) {
    %>
  </div>
  <div class="dash-main">
    <main class="dash-grid">
        <!-- 1. 품질 상태 -->
        <section class="panel_s">
            <h3>품질 상태</h3>
            <div class="chartBox_s">
                <canvas id="qualityChart"></canvas>
            </div>
            <div class="status-text">
                전압 불평형율: <strong><%= String.format("%.2f", voltage_unbalance_rate) %> %</strong><br/>
                전압 왜형율(THD): <strong><%= String.format("%.2f", harmonic_distortion_rate) %> %</strong><br/>
                품질 상태: <strong><%= (quality_status == null ? "-" : quality_status) %></strong>
            </div>
        </section>

        <!-- 2. 전력 상태 -->
        <section class="panel_s">
            <h3>부하 / 전력 상태</h3>
            <div class="chartBox_s">
                <canvas id="powerChart"></canvas>
            </div>
            <div class="status-text">
                유효전력 P: <strong><%= String.format("%.1f", active_power_total) %> kW</strong>, 
                무효전력 Q: <strong><%= String.format("%.1f", reactive_power_total) %> kVar</strong>, 
                피상전력 S: <strong><%= String.format("%.1f", apparent_power_total) %> kVA</strong><br/>
                상별 역률: 
                <strong>A=<%= String.format("%.3f", power_factor_a) %>, 
                        B=<%= String.format("%.3f", power_factor_b) %>, 
                        C=<%= String.format("%.3f", power_factor_c) %></strong><br/>
                주파수: <strong><%= String.format("%.3f", frequency) %> Hz</strong>
            </div>
        </section>

        <!-- 3. 고조파 -->
        <section class="panel_s">
            <h3>고조파 (전압 3·5·7·9·11차)</h3>
            <div class="chartBox_s">
                <canvas id="harmonicChart"></canvas>
            </div>
            <div class="status-text">
                THD-V(A/B/C): 
                <strong><%= String.format("%.1f", thd_voltage_a) %> / 
                        <%= String.format("%.1f", thd_voltage_b) %> / 
                        <%= String.format("%.1f", thd_voltage_c) %> %</strong>
            </div>
        </section>

        <!-- 4. 플리커 -->
        <section class="panel_s">
            <h3>플리커 지수</h3>
            <div class="chartBox_s">
                <canvas id="flickerChart"></canvas>
            </div>
            <div class="status-text">
                단기 플리커(Pst): <strong><%= String.format("%.2f", flicker_pst) %></strong><br/>
                장기 플리커(Plt): <strong><%= String.format("%.2f", flicker_plt) %></strong>
            </div>
        </section>

        <!-- 5. 이벤트 / 알람 -->
        <section class="panel_s">
            <h3>최근 7일 이벤트 / 알람</h3>
            <div class="chartBox_s">
                <canvas id="eventChart"></canvas>
            </div>
            <div class="status-text">
                Sag: <strong><%= sagCount %></strong>,
                Swell: <strong><%= swellCount %></strong>,
                기타 전압 이벤트: <strong><%= otherVoltageEvents %></strong><br/>
                알람 발생 총 건수: <strong><%= totalAlarms %></strong>
            </div>
        </section>

        <!-- 6. 전압/전류 기본 정보 -->
        <section class="panel_s panel-text-only">
            <h3>전압 / 전류 기본 정보</h3>
            <div class="status-text auto-fit-text">
                선간 전압 (V) :<strong>
                AB: <%= String.format("%.1f", voltage_ab) %>, 
                BC: <%= String.format("%.1f", voltage_bc) %>, 
                CA: <%= String.format("%.1f", voltage_ca) %></strong><br/>

                상간 전압 (V) :<strong>
                AN: <%= String.format("%.1f", voltage_an) %>, 
                BN: <%= String.format("%.1f", voltage_bn) %>, 
                CN: <%= String.format("%.1f", voltage_cn) %></strong><br/>

                상 전류 (A) :<strong>
                A: <%= String.format("%.1f", current_a) %>, 
                B: <%= String.format("%.1f", current_b) %>, 
                C: <%= String.format("%.1f", current_c) %>, 
                N: <%= String.format("%.1f", current_n) %></strong><br/>

                상전압 평균: <strong><%= String.format("%.1f", phase_voltage_avg) %> V</strong><br/>
                선간전압 평균: <strong><%= String.format("%.1f", line_voltage_avg) %> V</strong><br/>
                평균 전류: <strong><%= String.format("%.1f", average_current) %> A</strong><br/>

                누적 사용 에너지: <strong><%= String.format("%.1f", energy_consumed_total) %> kWh</strong>, <br/>
                누적 발전 에너지: <strong><%= String.format("%.1f", energy_generated_total) %> kWh</strong>
            </div>
        </section>
    </main>
  </div>
  <%
      } // if (hasMeterId && hasData)
  %>

  <footer class="dash-footer">© EPMS Dashboard • SNUT CNT</footer>


  <%
      // meter_id 없거나 데이터 없으면 차트 캔버스 자체가 없으므로 JS는 실행해도 안전하지만
      // 불필요한 렌더를 줄이고 싶으면 hasMeterId && hasData인 경우에만 스크립트 출력
      if (hasMeterId && hasData) {
  %>
  <script>
    // ===== JSP 값 → JS 상수 =====
    const vUnbalance = <%= voltage_unbalance_rate %>;
    const vThd       = <%= harmonic_distortion_rate %>;

    const pTotal = <%= active_power_total %>;
    const qTotal = <%= reactive_power_total %>;
    const sTotal = <%= apparent_power_total %>;

    const pfA = <%= power_factor_a %>;
    const pfB = <%= power_factor_b %>;
    const pfC = <%= power_factor_c %>;
    const freq = <%= frequency %>;

    const thdVa = <%= thd_voltage_a %>;
    const thdVb = <%= thd_voltage_b %>;
    const thdVc = <%= thd_voltage_c %>;

    const h3a = <%= voltage_h3_a %>, h5a = <%= voltage_h5_a %>, h7a = <%= voltage_h7_a %>, h9a = <%= voltage_h9_a %>, h11a = <%= voltage_h11_a %>;
    const h3b = <%= voltage_h3_b %>, h5b = <%= voltage_h5_b %>, h7b = <%= voltage_h7_b %>, h9b = <%= voltage_h9_b %>, h11b = <%= voltage_h11_b %>;
    const h3c = <%= voltage_h3_c %>, h5c = <%= voltage_h5_c %>, h7c = <%= voltage_h7_c %>, h9c = <%= voltage_h9_c %>, h11c = <%= voltage_h11_c %>;

    const flickerPst = <%= flicker_pst %>;
    const flickerPlt = <%= flicker_plt %>;

    const sagCnt   = <%= sagCount %>;
    const swellCnt = <%= swellCount %>;
    const otherEvt = <%= otherVoltageEvents %>;
    const alarmCnt = <%= totalAlarms %>;

    // 1. 품질 상태 차트
    const ctxQuality = document.getElementById('qualityChart');
    if (ctxQuality) {
      new Chart(ctxQuality, {
        type: 'bar',
        data: {
          labels: ['전압 불평형율', '전압 왜형율(THD)'],
          datasets: [{
            data: [vUnbalance, vThd]
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '값 (%)' }
            }
          }
        }
      });
    }

    // 2. 전력 상태 차트 (P, Q, S)
    const ctxPower = document.getElementById('powerChart');
    if (ctxPower) {
      new Chart(ctxPower, {
        type: 'bar',
        data: {
          labels: ['P(kW)', 'Q(kVar)', 'S(kVA)'],
          datasets: [{
            data: [pTotal, qTotal, sTotal]
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              callbacks: {
                afterBody: function() {
                  return 'PF A/B/C: ' +
                    pfA.toFixed(3) + ' / ' +
                    pfB.toFixed(3) + ' / ' +
                    pfC.toFixed(3) + '\\n' +
                    '주파수: ' + freq.toFixed(3) + ' Hz';
                }
              }
            }
          },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '전력' }
            }
          }
        }
      });
    }

    // 3. 고조파 차트 (3,5,7,9,11차, 상별)
    const ctxHarm = document.getElementById('harmonicChart');
    if (ctxHarm) {
      new Chart(ctxHarm, {
        type: 'bar',
        data: {
          labels: ['3차', '5차', '7차', '9차', '11차'],
          datasets: [
            { label: 'A상', data: [h3a, h5a, h7a, h9a, h11a] },
            { label: 'B상', data: [h3b, h5b, h7b, h9b, h11b] },
            { label: 'C상', data: [h3c, h5c, h7c, h9c, h11c] }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { position: 'bottom' } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '전압 고조파 (단위: %)' }
            }
          }
        }
      });
    }

    // 4. 플리커 차트
    const ctxFlicker = document.getElementById('flickerChart');
    if (ctxFlicker) {
      new Chart(ctxFlicker, {
        type: 'bar',
        data: {
          labels: ['Pst', 'Plt'],
          datasets: [{
            data: [flickerPst, flickerPlt]
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '플리커 지수' }
            }
          }
        }
      });
    }

    // 5. 이벤트 / 알람 차트
    const ctxEvent = document.getElementById('eventChart');
    if (ctxEvent) {
      new Chart(ctxEvent, {
        type: 'bar',
        data: {
          labels: ['Sag', 'Swell', '기타전압이벤트', '알람'],
          datasets: [{
            data: [sagCnt, swellCnt, otherEvt, alarmCnt]
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: {
            x: { grid: { display: false } },
            y: {
              beginAtZero: true,
              title: { display: true, text: '발생 건수' }
            }
          }
        }
      });
    }
  </script>
  <%
      } // end if (hasMeterId && hasData)
  } // end try-with-resources
  %>
  </div>
</body>
</html>
