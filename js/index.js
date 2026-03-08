(function () {
  var theme = 'westeros';
  var chartIds = ['myChart1','myChart2','myChart3','myChart4','myChart5','myChart6','myChart7'];

  function $(id){ return document.getElementById(id); }
  function must(id){
    var el = $(id);
    if(!el) console.error('[index.js] element not found:', id);
    return el;
  }

  // ===== DOM =====
  var els = {
    building: must('buildingSelector'),
    month: must('monthSelector'),
    years: must('yearCountSelector'),
    metric: must('metricSelector'),
    refresh: must('refreshBtn'),
    lastUpdate: must('lastUpdate'),
    cardTitle4: must('cardTitle4'),
    bCardTitle1: must('bCardTitle1'),
    bCardTitle2: must('bCardTitle2'),
    bCardTitle3: must('bCardTitle3'),
    rightCard1: $('rightCard1'),
    rightCard2: $('rightCard2'),
    rightCard3: $('rightCard3')
  };

  // ===== utils =====
  function fmt(n) { return (parseFloat(n) || 0).toLocaleString(); }
  function hasData(arr) { return Array.isArray(arr) && arr.some(function(v){ return Number(v) > 0; }); }
  function keyOf(s){ return String(s == null ? '' : s).trim(); }
  function normKey(s){
    return String(s == null ? '' : s).trim().replace(/\s+/g,'').replace(/[()]/g,'');
  }

  // overlay 방식: ECharts canvas DOM을 건드리지 않음
  function setNoData(chartEl, msg) {
    if (!chartEl) return;
    chartEl.style.position = 'relative';
    var overlay = chartEl.querySelector('.no-data');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.className = 'no-data';
      chartEl.appendChild(overlay);
    }
    overlay.textContent = msg || '데이터 없음';
  }
  function clearNoData(chartEl) {
    if (!chartEl) return;
    var overlay = chartEl.querySelector('.no-data');
    if (overlay) overlay.remove();
  }

  function setLastUpdate(baseDateStr) {
    var d = new Date();
    function p2(x){ return String(x).padStart(2,'0'); }
    var nowStr = d.getFullYear() + '-' + p2(d.getMonth()+1) + '-' + p2(d.getDate()) + ' ' +
                 p2(d.getHours()) + ':' + p2(d.getMinutes()) + ':' + p2(d.getSeconds());
    if (els.lastUpdate) {
      els.lastUpdate.textContent = baseDateStr
        ? ('업데이트: ' + nowStr + ' (기준일: ' + baseDateStr + ')')
        : ('업데이트: ' + nowStr);
    }
  }

  function buildUrl(action, params) {
    var q = [];
    for (var k in params) {
      if (!Object.prototype.hasOwnProperty.call(params, k)) continue;
      q.push(encodeURIComponent(k) + '=' + encodeURIComponent(params[k]));
    }
    return '../includes/bems.jsp?action=' + encodeURIComponent(action) + (q.length ? '&' + q.join('&') : '');
  }

  // ===== ECharts init =====
  var charts = [];
  function initCharts(){
    charts = chartIds.map(function(id){
      var el = $(id);
      if (!el) {
        console.error('[index.js] chart container missing:', id);
        return null;
      }
      return echarts.init(el, theme);
    });
  }

  // ===== pie table =====
  function renderUsageTable(pieData, targetId) {
    var wrap = $(targetId);
    if (!wrap) return;
    wrap.innerHTML = '';

    var table = document.createElement('table');
    table.className = 'data-table';

    var head = document.createElement('tr');
    head.innerHTML = '<th>용도</th><th style="text-align:right">사용량(kWh)</th>';
    table.appendChild(head);

    var sum = 0;
    pieData.forEach(function(item){
      var v = Number(item.value) || 0;
      sum += v;

      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + (item.name == null ? '' : String(item.name)) + '</td>' +
        '<td style="text-align:right">' + fmt(v) + ' kWh</td>';
      table.appendChild(tr);
    });

    var total = document.createElement('tr');
    total.className = 'total-row';
    total.innerHTML =
      '<td>합계</td>' +
      '<td style="text-align:right">' + fmt(sum) + ' kWh</td>';
    table.appendChild(total);

    wrap.appendChild(table);
  }

  // ===== year compare table =====
  function renderYearCompareTable(chartOption, targetId, buildingNames, unit) {
    var wrap = $(targetId);
    if (!wrap) return;
    wrap.innerHTML = '';

    var b1 = buildingNames[0] || '건물1';
    var b2 = buildingNames[1] || '건물2';
    var b3 = buildingNames[2] || '건물3';

    var series = (chartOption && chartOption.series) ? chartOption.series : [];
    var years = series.map(function(s){ return s.name; });

    var table = document.createElement('table');
    table.className = 'data-table';

    function addSection(title, dataIndex) {
      var header = document.createElement('tr');
      header.innerHTML = '<th colspan="2">' + title + '</th>';
      table.appendChild(header);

      for (var i=0;i<years.length;i++){
        var v = 0;
        if (series[i] && series[i].data && series[i].data[dataIndex] && series[i].data[dataIndex].value != null) {
          v = series[i].data[dataIndex].value;
        }
        var tr = document.createElement('tr');
        tr.innerHTML =
          '<td>' + years[i] + '</td>' +
          '<td style="text-align:right">' + fmt(v) + ' ' + (unit || '') + '</td>';
        table.appendChild(tr);
      }

      var spacer = document.createElement('tr');
      spacer.innerHTML = '<td colspan="2" class="spacer-row"></td>';
      table.appendChild(spacer);
    }

    // yAxis = [b3,b2,b1] => index 0=b3, 1=b2, 2=b1
    addSection(b1, 2);
    addSection(b2, 1);
    addSection(b3, 0);

    wrap.appendChild(table);
  }

  // ===== meta =====
  function loadMeta() {
    return fetch('../includes/bems.jsp?action=meta')
      .then(function(res){ return res.json(); })
      .then(function(meta){
        if (!els.building) return;

        els.building.innerHTML = '<option value="TOTAL">전체</option>';
        (meta.buildings || []).forEach(function(b){
          var opt = document.createElement('option');
          opt.value = b;
          opt.textContent = b;
          els.building.appendChild(opt);
        });

        // 기본 월 = 현재월
        var now = new Date();
        if (els.month) els.month.value = String(now.getMonth() + 1);
      })
      .catch(function(err){
        console.warn('[meta] failed', err);
      });
  }

  // ===== right card show/hide =====
  // ✅ monthMax가 0이거나 키가 불일치해도 "숨기지 않음"
  function shouldHideRightCard(buildingName) {
    return (!buildingName || buildingName === 'N/A');
  }

  function setCardVisible(cardEl, visible) {
    if (!cardEl) return;
    if (visible) cardEl.classList.remove('hidden');
    else cardEl.classList.add('hidden');
  }

  // ===== main fetch/render =====
  function fetchDataAndUpdateChart() {
    var building = (els.building && els.building.value) ? els.building.value : 'TOTAL';
    var month = (els.month && els.month.value) ? els.month.value : String(new Date().getMonth()+1);
    var years = (els.years && els.years.value) ? els.years.value : '3';
    var metric = (els.metric && els.metric.value) ? els.metric.value : 'PEAK';

    var url = buildUrl('data', { building: building, month: month, years: years, metric: metric });

    return fetch(url)
      .then(function(res){ return res.json(); })
      .then(function(data){
        if (!data || data.error) {
          console.warn('[data] bems.jsp error:', data && data.error);
          return;
        }

        var selectedBuildings = (data.selectedBuildings && data.selectedBuildings.length)
          ? data.selectedBuildings : ['건물1','건물2','건물3'];

        var b1 = selectedBuildings[0] || '건물1';
        var b2 = selectedBuildings[1] || '건물2';
        var b3 = selectedBuildings[2] || '건물3';

        if (els.bCardTitle1) els.bCardTitle1.textContent = b1;
        if (els.bCardTitle2) els.bCardTitle2.textContent = b2;
        if (els.bCardTitle3) els.bCardTitle3.textContent = b3;

        var E = data.Electricity || {};
        var W = data.Water || {};
        var G = data.Gas || {};

        // ---------- Chart1 ----------
        var hourVals = [];
        var hourPred = [];
        for (var h=0; h<24; h++){
          var hk = 'hour_' + String(h).padStart(2,'0');
          var pk = 'hour_Prediction' + String(h).padStart(2,'0');
          hourVals.push(Number(E[hk] || 0));
          hourPred.push(Number(E[pk] || 0));
        }
        var hourLabels = [];
        for (h=0; h<24; h++) hourLabels.push(String(h).padStart(2,'0'));

        var hourOption = {
          tooltip: { trigger:'axis', valueFormatter: function(v){ return fmt(v) + ' kW'; } },
          legend: { top: 6, right: 10, data:['수요전력(kW)','예측(kW)'] },
          grid: { top: 40, left: 45, right: 20, bottom: 35, containLabel:true },
          xAxis: { type:'category', data: hourLabels },
          yAxis: { type:'value' },
          series: [
            { name:'수요전력(kW)', type:'bar', data: hourVals },
            { name:'예측(kW)', type:'line', data: hourPred }
          ]
        };

        var chart1El = $('myChart1');
        if (!hasData(hourVals)) {
          if (charts[0]) charts[0].clear();
          setNoData(chart1El, '데이터 없음');
        } else {
          clearNoData(chart1El);
          if (charts[0]) charts[0].setOption(hourOption, true);
        }

        // ---------- Chart2 ----------
        var monthLabels = ['1월','2월','3월','4월','5월','6월','7월','8월','9월','10월','11월','12월'];
        var mE=[], mW=[], mG=[];
        for (var i=1;i<=12;i++){
          var mk = 'month_' + String(i).padStart(2,'0');
          mE.push(Number(E[mk] || 0));
          mW.push(Number(W[mk] || 0));
          mG.push(Number(G[mk] || 0));
        }

        var monthOption = {
          tooltip: { trigger:'axis', valueFormatter: function(v){ return fmt(v) + ' kWh'; } },
          legend: { top: 6, right: 10, data:[b1,b2,b3] },
          grid: { top: 40, left: 45, right: 20, bottom: 35, containLabel:true },
          xAxis: { type:'category', data: monthLabels },
          yAxis: { type:'value' },
          series: [
            { name:b1, type:'bar', data:mE },
            { name:b2, type:'bar', data:mW },
            { name:b3, type:'bar', data:mG }
          ]
        };

        var chart2El = $('myChart2');
        if (!hasData(mE) && !hasData(mW) && !hasData(mG)) {
          if (charts[1]) charts[1].clear();
          setNoData(chart2El, '데이터 없음');
        } else {
          clearNoData(chart2El);
          if (charts[1]) charts[1].setOption(monthOption, true);
        }

        // ---------- Chart3 ----------
        var usagePie = Array.isArray(data.usagePie) ? data.usagePie : [];
        var chart3El = $('myChart3');

        if (!usagePie.length || !usagePie.some(function(x){ return Number(x.value) > 0; })) {
          if (charts[2]) charts[2].clear();
          setNoData(chart3El, '데이터 없음');
          var t3 = $('myChart3_table'); if (t3) t3.innerHTML = '';
        } else {
          clearNoData(chart3El);
          var pieOption = {
            tooltip: { trigger:'item', formatter: '{b}<br/>{c} kWh ({d}%)' },
            series: [{
              type:'pie',
              radius:['35%','70%'],
              center:['50%','52%'],
              label:{ show:false },
              emphasis:{ label:{ show:true, fontSize:14, fontWeight:'bold' } },
              data: usagePie
            }]
          };
          if (charts[2]) charts[2].setOption(pieOption, true);
          renderUsageTable(usagePie, 'myChart3_table');
        }

        // ---------- Chart4 ----------
        var yc = data.yearCompare ? data.yearCompare : null;
        var unit = (yc && yc.unit) ? yc.unit : 'kW';
        var metricLabel = (yc && yc.metricLabel) ? yc.metricLabel : '지표';
        var title = yc
          ? (yc.selectedMonth + '월 ' + metricLabel + ' (최근 ' + yc.yearCount + '년)')
          : '연도 비교';
        if (els.cardTitle4) els.cardTitle4.textContent = title;

        var yAxisBuildings = [b3,b2,b1];
        var series = [];

        if (yc && Array.isArray(yc.series) && yc.series.length) {
          series = yc.series.map(function(s){
            var v = s.values || [0,0,0]; // [b1,b2,b3]
            var reordered = [v[2]||0, v[1]||0, v[0]||0].map(function(x){ return {value:x}; });
            return { name: String(s.year) + '년', type:'bar', data: reordered };
          });
        }

        var chart4El = $('myChart4');
        if (!series.length) {
          if (charts[3]) charts[3].clear();
          setNoData(chart4El, '데이터 없음');
          var t4 = $('myChart4_table'); if (t4) t4.innerHTML = '';
        } else {
          clearNoData(chart4El);
          var yearCompareOption = {
            tooltip: { trigger:'axis', axisPointer:{type:'shadow'}, valueFormatter: function(v){ return fmt(v) + ' ' + unit; } },
            legend: { top: 6, right: 10, data: series.map(function(s){ return s.name; }) },
            grid: { top: 40, left: 20, right: 20, bottom: 20, containLabel:true },
            xAxis: { type:'value' },
            yAxis: { type:'category', data: yAxisBuildings },
            series: series
          };
          if (charts[3]) charts[3].setOption(yearCompareOption, true);
          renderYearCompareTable(yearCompareOption, 'myChart4_table', [b1,b2,b3], unit);
        }

        // ---------- Right cards ----------
        var mmRaw = data.monthMax || {};
        var mm = {};
        Object.keys(mmRaw).forEach(function(k){
          mm[normKey(k)] = mmRaw[k];
        });

        var rightData = [
          { b: b1, d: E, c: charts[4], el: els.rightCard1 },
          { b: b2, d: W, c: charts[5], el: els.rightCard2 },
          { b: b3, d: G, c: charts[6], el: els.rightCard3 }
        ];

        rightData.forEach(function(item){
          if (!item.el) return;

          var hide = shouldHideRightCard(item.b);
          setCardVisible(item.el, !hide);
          if (hide) return;

          var k = normKey(item.b);
          var hasKey = Object.prototype.hasOwnProperty.call(mm, k);
          var monthMax = hasKey ? Number(mm[k] || 0) : 0;

          if (!hasKey) console.warn('[monthMax key mismatch]', item.b, '→', k, 'keys=', Object.keys(mmRaw));

          var arr = [
            Number(item.d.yesterday || 0),
            Number(item.d.today || 0),
            monthMax
          ];

          if (!item.c) return;
          item.c.setOption({
            tooltip: { trigger:'axis', axisPointer:{type:'shadow'}, valueFormatter: function(v){ return fmt(v) + ' kW'; } },
            grid: { top: 20, left: 45, right: 20, bottom: 30, containLabel:true },
            xAxis: { type:'category', data:['전일','금일','월 최대'] },
            yAxis: { type:'value' },
            series: [{ type:'bar', data: arr }]
          }, true);
        });

        requestAnimationFrame(function(){
          charts.forEach(function(c){ if (c) c.resize(); });
        });

        setLastUpdate(data.baseDate);
      })
      .catch(function(err){
        console.warn('[fetchDataAndUpdateChart] failed', err);
      });
  }

  function bindEvents() {
    if (els.building) els.building.addEventListener('change', fetchDataAndUpdateChart);
    if (els.month) els.month.addEventListener('change', fetchDataAndUpdateChart);
    if (els.years) els.years.addEventListener('change', fetchDataAndUpdateChart);
    if (els.metric) els.metric.addEventListener('change', fetchDataAndUpdateChart);
    if (els.refresh) els.refresh.addEventListener('click', fetchDataAndUpdateChart);

    window.addEventListener('resize', function(){
      charts.forEach(function(c){ if (c) c.resize(); });
    });
  }

  // ===== boot =====
  window.addEventListener('load', function(){
    requestAnimationFrame(function(){
      initCharts();
      loadMeta()
        .then(function(){
          bindEvents();
          return fetchDataAndUpdateChart();
        })
        .then(function(){
          setInterval(fetchDataAndUpdateChart, 5000);
        });
    });
  });

})();