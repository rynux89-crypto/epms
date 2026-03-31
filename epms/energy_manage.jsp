<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%!
    private static double nz(Double v) { return v == null ? 0.0 : v; }

    private static String meterLabel(int meterId, Map<Integer, String> names) {
        String n = names.get(meterId);
        if (n == null || n.trim().isEmpty()) n = "Meter " + meterId;
        return n + " (#" + meterId + ")";
    }

    private static String treemapNodeJson(
            int nodeId,
            Map<Integer, List<Integer>> childrenByParent,
            Map<Integer, Double> leafValues,
            Map<Integer, String> meterNames,
            Set<Integer> visiting) {
        if (visiting.contains(nodeId)) {
            return "{\"name\":\"" + jsq(meterLabel(nodeId, meterNames)) + "\",\"value\":0}";
        }
        visiting.add(nodeId);

        List<Integer> children = childrenByParent.get(nodeId);
        boolean hasChildren = children != null && !children.isEmpty();

        StringBuilder sb = new StringBuilder();
        sb.append("{\"name\":\"").append(jsq(meterLabel(nodeId, meterNames))).append("\"");
        if (hasChildren) {
            sb.append(",\"children\":[");
            for (int i = 0; i < children.size(); i++) {
                if (i > 0) sb.append(',');
                sb.append(treemapNodeJson(children.get(i), childrenByParent, leafValues, meterNames, visiting));
            }
            sb.append(']');
        } else {
            sb.append(",\"value\":").append(String.format(java.util.Locale.US, "%.6f", leafValues.getOrDefault(nodeId, 0.0)));
        }
        sb.append('}');

        visiting.remove(nodeId);
        return sb.toString();
    }
%>
<%
try (Connection conn = openDbConnection()) {
    LocalDate today = LocalDate.now();

    String startDate = request.getParameter("startDate");
    String endDate = request.getParameter("endDate");
    String building = request.getParameter("building");
    String usage = request.getParameter("usage");
    String meter = request.getParameter("meter");
    String bucket = request.getParameter("bucket");
    if (bucket == null || bucket.trim().isEmpty()) bucket = "day";

    if (endDate == null || endDate.trim().isEmpty()) endDate = today.toString();
    if (startDate == null || startDate.trim().isEmpty()) startDate = today.minusDays(6).toString();

    LocalDate startD = LocalDate.parse(startDate);
    LocalDate endD = LocalDate.parse(endDate);
    if (endD.isBefore(startD)) {
        LocalDate tmp = startD;
        startD = endD;
        endD = tmp;
        startDate = startD.toString();
        endDate = endD.toString();
    }

    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String[]> meterOptions = new ArrayList<>();
    Map<Integer, String> meterNames = new HashMap<>();

    try {
        try (Statement st = conn.createStatement()) {
            try (ResultSet rs = st.executeQuery("SELECT DISTINCT building_name FROM dbo.meters WHERE building_name IS NOT NULL ORDER BY building_name")) {
                while (rs.next()) buildingOptions.add(rs.getString(1));
            }
            try (ResultSet rs = st.executeQuery("SELECT DISTINCT usage_type FROM dbo.meters WHERE usage_type IS NOT NULL ORDER BY usage_type")) {
                while (rs.next()) usageOptions.add(rs.getString(1));
            }
        }

        StringBuilder meterSql = new StringBuilder("SELECT meter_id, name FROM dbo.meters WHERE 1=1 ");
        List<Object> meterParams = new ArrayList<>();
        if (building != null && !building.trim().isEmpty()) {
            meterSql.append(" AND building_name = ? ");
            meterParams.add(building.trim());
        }
        if (usage != null && !usage.trim().isEmpty()) {
            meterSql.append(" AND usage_type = ? ");
            meterParams.add(usage.trim());
        }
        meterSql.append(" ORDER BY meter_id");

        try (PreparedStatement ps = conn.prepareStatement(meterSql.toString())) {
            for (int i = 0; i < meterParams.size(); i++) ps.setObject(i + 1, meterParams.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String mid = rs.getString("meter_id");
                    String mname = rs.getString("name");
                    meterOptions.add(new String[]{mid, mname});
                    try { meterNames.put(Integer.parseInt(mid), mname); } catch (Exception ignore) {}
                }
            }
        }
    } catch (Exception e) {
        out.println("<div style='color:#b42318;background:#fff1f1;border:1px solid #fecaca;padding:10px;border-radius:8px;'>옵션 조회 오류: " + h(e.getMessage()) + "</div>");
    }

    Map<Integer, List<Integer>> allChildrenByParent = new LinkedHashMap<>();
    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT parent_meter_id, child_meter_id " +
            "FROM dbo.meter_tree WHERE is_active=1 " +
            "ORDER BY parent_meter_id, child_meter_id");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            int p = rs.getInt("parent_meter_id");
            int c = rs.getInt("child_meter_id");
            allChildrenByParent.computeIfAbsent(p, k -> new ArrayList<>()).add(c);
        }
    } catch (Exception ignoreNoTree) {
        // meter_tree가 없거나 조회 실패하면 단일/전체 집계로 동작
    }

    StringBuilder where = new StringBuilder();
    List<Object> whereParams = new ArrayList<>();
    if (building != null && !building.trim().isEmpty()) {
        where.append(" AND m.building_name = ? ");
        whereParams.add(building.trim());
    }
    if (usage != null && !usage.trim().isEmpty()) {
        where.append(" AND m.usage_type = ? ");
        whereParams.add(usage.trim());
    }

    Integer selectedMeterId = null;
    if (meter != null && !meter.trim().isEmpty()) {
        try { selectedMeterId = Integer.parseInt(meter.trim()); }
        catch (Exception ignore) { meter = ""; selectedMeterId = null; }
    }

    Set<Integer> scopeMeterIds = new LinkedHashSet<>();
    if (selectedMeterId != null) {
        Deque<Integer> q = new ArrayDeque<>();
        q.add(selectedMeterId);
        while (!q.isEmpty()) {
            int cur = q.poll();
            if (!scopeMeterIds.add(cur)) continue;
            List<Integer> ch = allChildrenByParent.get(cur);
            if (ch != null) for (Integer cc : ch) q.add(cc);
        }
    } else {
        for (String[] mo : meterOptions) {
            try { scopeMeterIds.add(Integer.parseInt(mo[0])); } catch (Exception ignore) {}
        }
    }
    if (!scopeMeterIds.isEmpty()) {
        StringBuilder inMarks = new StringBuilder();
        int cnt = 0;
        for (Integer ignored : scopeMeterIds) {
            if (cnt++ > 0) inMarks.append(",");
            inMarks.append("?");
        }
        where.append(" AND ms.meter_id IN (").append(inMarks).append(") ");
        for (Integer id : scopeMeterIds) whereParams.add(id);
    }

    Map<Integer, Map<LocalDate, Double>> meterDaily = new HashMap<>();
    Map<Integer, Double> meterTotalKwh = new HashMap<>();
    Map<LocalDate, Double> dayTotalKwh = new HashMap<>();
    Map<LocalDate, Double> dayPeakKw = new HashMap<>();
    Map<LocalDate, Integer> dayResetCnt = new HashMap<>();

    String meterDaySql =
        "WITH base AS ( " +
        "  SELECT ms.meter_id, CAST(ms.measured_at AS date) AS d, ms.measured_at, " +
        "         CAST(ms.energy_consumed_total AS float) AS energy_total, " +
        "         CAST(ms.active_power_total AS float) AS active_kw " +
        "  FROM dbo.measurements ms " +
        "  INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "  WHERE ms.measured_at >= DATEADD(day, -1, ?) " +
        "    AND ms.measured_at < DATEADD(day, 1, ?) " + where.toString() +
        "), day_last AS ( " +
        "  SELECT meter_id, d, energy_total, " +
        "         ROW_NUMBER() OVER (PARTITION BY meter_id, d ORDER BY measured_at DESC) rn " +
        "  FROM base WHERE energy_total IS NOT NULL " +
        "), day_peak AS ( " +
        "  SELECT meter_id, d, MAX(active_kw) AS peak_kw " +
        "  FROM base GROUP BY meter_id, d " +
        "), day_meter AS ( " +
        "  SELECT l.meter_id, l.d, l.energy_total AS end_total, p.peak_kw " +
        "  FROM day_last l " +
        "  LEFT JOIN day_peak p ON p.meter_id = l.meter_id AND p.d = l.d " +
        "  WHERE l.rn = 1 " +
        "), day_diff AS ( " +
        "  SELECT meter_id, d, peak_kw, " +
        "         end_total - LAG(end_total) OVER (PARTITION BY meter_id ORDER BY d) AS day_kwh " +
        "  FROM day_meter " +
        ") " +
        "SELECT meter_id, d, peak_kw, day_kwh " +
        "FROM day_diff WHERE d BETWEEN ? AND ? ORDER BY d, meter_id";

    try (PreparedStatement ps = conn.prepareStatement(meterDaySql)) {
        int idx = 1;
        ps.setString(idx++, startDate);
        ps.setString(idx++, endDate);
        for (Object p : whereParams) ps.setObject(idx++, p);
        ps.setString(idx++, startDate);
        ps.setString(idx++, endDate);

        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                int mid = rs.getInt("meter_id");
                java.sql.Date dObj = rs.getDate("d");
                if (dObj == null) continue;
                LocalDate d = dObj.toLocalDate();
                Double raw = (Double) rs.getObject("day_kwh");
                double rawKwh = raw == null ? 0.0 : raw.doubleValue();
                double safeKwh = rawKwh >= 0.0 ? rawKwh : 0.0;

                meterDaily.computeIfAbsent(mid, k -> new HashMap<>()).put(d, safeKwh);
                meterTotalKwh.put(mid, meterTotalKwh.getOrDefault(mid, 0.0) + safeKwh);

                dayTotalKwh.put(d, dayTotalKwh.getOrDefault(d, 0.0) + safeKwh);

                double peak = rs.getDouble("peak_kw");
                dayPeakKw.put(d, Math.max(dayPeakKw.getOrDefault(d, 0.0), peak));

                if (rawKwh < 0.0) {
                    dayResetCnt.put(d, dayResetCnt.getOrDefault(d, 0) + 1);
                }
            }
        }
    } catch (Exception e) {
        out.println("<div style='color:#b42318;background:#fff1f1;border:1px solid #fecaca;padding:10px;border-radius:8px;'>일사용량 조회 오류: " + h(e.getMessage()) + "</div>");
    }

    List<LocalDate> allDays = new ArrayList<>();
    for (LocalDate d = startD; !d.isAfter(endD); d = d.plusDays(1)) allDays.add(d);

    List<LocalDate> dayLabels = new ArrayList<>(allDays);
    List<Double> dayKwh = new ArrayList<>();
    List<Double> dayPeak = new ArrayList<>();
    List<Integer> dayResets = new ArrayList<>();
    for (LocalDate d : allDays) {
        dayKwh.add(dayTotalKwh.getOrDefault(d, 0.0));
        dayPeak.add(dayPeakKw.getOrDefault(d, 0.0));
        dayResets.add(dayResetCnt.getOrDefault(d, 0));
    }

    double periodTotalKwh = 0.0;
    double peakKw = 0.0;
    int resetDays = 0;
    for (int i = 0; i < dayLabels.size(); i++) {
        periodTotalKwh += nz(dayKwh.get(i));
        peakKw = Math.max(peakKw, nz(dayPeak.get(i)));
        if (dayResets.get(i) > 0) resetDays++;
    }

    double todayKwh = dayTotalKwh.getOrDefault(endD, 0.0);
    double yesterdayKwh = dayTotalKwh.getOrDefault(endD.minusDays(1), 0.0);
    Double dayOverDayPct = null;
    if (yesterdayKwh > 0.0) dayOverDayPct = ((todayKwh - yesterdayKwh) / yesterdayKwh) * 100.0;

    YearMonth ym = YearMonth.from(endD);
    double mtdKwh = 0.0;
    for (int i = 0; i < dayLabels.size(); i++) {
        if (YearMonth.from(dayLabels.get(i)).equals(ym)) mtdKwh += nz(dayKwh.get(i));
    }

    double avgPf = 0.0;
    double avgKw = 0.0;
    double nightBaseKw = 0.0;
    String kpiSql =
        "SELECT AVG(CAST(ms.power_factor AS float)) AS avg_pf, " +
        "       AVG(CAST(ms.active_power_total AS float)) AS avg_kw, " +
        "       AVG(CASE WHEN DATEPART(HOUR, ms.measured_at) BETWEEN 0 AND 5 THEN CAST(ms.active_power_total AS float) END) AS night_kw " +
        "FROM dbo.measurements ms " +
        "INNER JOIN dbo.meters m ON m.meter_id = ms.meter_id " +
        "WHERE ms.measured_at >= ? AND ms.measured_at < DATEADD(day, 1, ?) " + where.toString();
    try (PreparedStatement ps = conn.prepareStatement(kpiSql)) {
        int idx = 1;
        ps.setString(idx++, startDate);
        ps.setString(idx++, endDate);
        for (Object p : whereParams) ps.setObject(idx++, p);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                avgPf = rs.getDouble("avg_pf");
                avgKw = rs.getDouble("avg_kw");
                nightBaseKw = rs.getDouble("night_kw");
            }
        }
    } catch (Exception e) {
        out.println("<div style='color:#b42318;background:#fff1f1;border:1px solid #fecaca;padding:10px;border-radius:8px;'>KPI 조회 오류: " + h(e.getMessage()) + "</div>");
    }

    int spikeDays = 0;
    for (int i = 1; i < dayKwh.size(); i++) {
        double prev = nz(dayKwh.get(i - 1));
        double cur = nz(dayKwh.get(i));
        if (prev > 0.0 && cur > prev * 1.2) spikeDays++;
    }
    boolean nightHigh = (avgKw > 0.0 && nightBaseKw >= avgKw * 0.6);

    if (scopeMeterIds.isEmpty()) scopeMeterIds.addAll(meterTotalKwh.keySet());

    Map<Integer, List<Integer>> childrenByParent = new HashMap<>();
    Set<Integer> childSet = new HashSet<>();
    for (Map.Entry<Integer, List<Integer>> e : allChildrenByParent.entrySet()) {
        int p = e.getKey().intValue();
        if (!scopeMeterIds.contains(p)) continue;
        for (Integer c : e.getValue()) {
            if (!scopeMeterIds.contains(c)) continue;
            childrenByParent.computeIfAbsent(p, k -> new ArrayList<>()).add(c);
            childSet.add(c);
        }
    }

    for (Map.Entry<Integer, List<Integer>> e : childrenByParent.entrySet()) {
        Collections.sort(e.getValue());
    }

    Map<Integer, Integer> depthMap = new HashMap<>();
    Deque<Integer> dq = new ArrayDeque<>();
    Set<Integer> allTreeNodes = new HashSet<>();
    allTreeNodes.addAll(allChildrenByParent.keySet());
    for (Map.Entry<Integer, List<Integer>> e : allChildrenByParent.entrySet()) {
        allTreeNodes.addAll(e.getValue());
    }
    Set<Integer> allTreeChildren = new HashSet<>();
    for (List<Integer> ch : allChildrenByParent.values()) allTreeChildren.addAll(ch);
    for (Integer n : allTreeNodes) {
        if (!allTreeChildren.contains(n)) {
            depthMap.put(n, 0);
            dq.add(n);
        }
    }
    if (dq.isEmpty()) {
        for (Integer n : allTreeNodes) {
            depthMap.put(n, 0);
            dq.add(n);
        }
    }
    while (!dq.isEmpty()) {
        int cur = dq.poll();
        int nd = depthMap.getOrDefault(cur, 0);
        List<Integer> ch = allChildrenByParent.get(cur);
        if (ch == null) continue;
        for (Integer c : ch) {
            Integer old = depthMap.get(c);
            if (old == null || nd + 1 < old.intValue()) {
                depthMap.put(c, nd + 1);
                dq.add(c);
            }
        }
    }

    int minDepthInScope = Integer.MAX_VALUE;
    for (Integer id : scopeMeterIds) {
        int d = depthMap.getOrDefault(id, 999999);
        if (d < minDepthInScope) minDepthInScope = d;
    }

    List<Integer> roots = new ArrayList<>();
    for (Integer id : scopeMeterIds) {
        int d = depthMap.getOrDefault(id, 999999);
        if (d == minDepthInScope) roots.add(id);
    }
    if (roots.isEmpty()) roots.addAll(scopeMeterIds);
    List<String> rootNameList = new ArrayList<>();
    for (Integer r : roots) rootNameList.add(meterLabel(r, meterNames));
    String rootSummary = rootNameList.isEmpty() ? "-" : String.join(", ", rootNameList);

    Map<Integer, Set<Integer>> rootLeaves = new HashMap<>();
    for (Integer r : roots) {
        Set<Integer> leaves = new LinkedHashSet<>();
        Set<Integer> visited = new HashSet<>();
        Deque<Integer> stack = new ArrayDeque<>();
        stack.push(r);
        while (!stack.isEmpty()) {
            int cur = stack.pop();
            if (!visited.add(cur)) continue;
            List<Integer> ch = childrenByParent.get(cur);
            if (ch == null || ch.isEmpty()) {
                leaves.add(cur);
            } else {
                for (Integer cc : ch) stack.push(cc);
            }
        }
        rootLeaves.put(r, leaves);
    }

    // Stacked Area 그룹: "직계 자식" 기준
    List<Integer> stackGroups = new ArrayList<>();
    if (selectedMeterId != null && scopeMeterIds.contains(selectedMeterId)) {
        List<Integer> ch = childrenByParent.get(selectedMeterId);
        if (ch != null && !ch.isEmpty()) stackGroups.addAll(ch);
        else stackGroups.add(selectedMeterId);
    } else {
        for (Integer r : roots) {
            List<Integer> ch = childrenByParent.get(r);
            if (ch != null && !ch.isEmpty()) stackGroups.addAll(ch);
            else stackGroups.add(r);
        }
    }
    LinkedHashSet<Integer> groupDedup = new LinkedHashSet<>(stackGroups);
    stackGroups.clear();
    stackGroups.addAll(groupDedup);

    List<String> stackLabels = new ArrayList<>();
    if ("month".equals(bucket)) {
        YearMonth m = YearMonth.from(startD);
        YearMonth me = YearMonth.from(endD);
        while (!m.isAfter(me)) {
            stackLabels.add(m.toString());
            m = m.plusMonths(1);
        }
    } else {
        for (LocalDate d : allDays) stackLabels.add(d.toString());
    }

    Map<Integer, Set<Integer>> groupLeaves = new HashMap<>();
    for (Integer g : stackGroups) {
        Set<Integer> leaves = new LinkedHashSet<>();
        Set<Integer> visited = new HashSet<>();
        Deque<Integer> stack = new ArrayDeque<>();
        stack.push(g);
        while (!stack.isEmpty()) {
            int cur = stack.pop();
            if (!visited.add(cur)) continue;
            List<Integer> ch = childrenByParent.get(cur);
            if (ch == null || ch.isEmpty()) {
                leaves.add(cur);
            } else {
                for (Integer cc : ch) stack.push(cc);
            }
        }
        groupLeaves.put(g, leaves);
    }

    Map<Integer, List<Double>> groupSeries = new LinkedHashMap<>();
    Map<Integer, Double> groupSeriesTotals = new HashMap<>();
    for (Integer g : stackGroups) {
        List<Double> values = new ArrayList<>();
        double total = 0.0;
        for (String x : stackLabels) {
            double v = 0.0;
            if ("month".equals(bucket)) {
                YearMonth xm = YearMonth.parse(x);
                for (Integer leaf : groupLeaves.getOrDefault(g, Collections.emptySet())) {
                    Map<LocalDate, Double> dm = meterDaily.get(leaf);
                    if (dm == null) continue;
                    for (Map.Entry<LocalDate, Double> ent : dm.entrySet()) {
                        if (YearMonth.from(ent.getKey()).equals(xm)) v += nz(ent.getValue());
                    }
                }
            } else {
                LocalDate xd = LocalDate.parse(x);
                for (Integer leaf : groupLeaves.getOrDefault(g, Collections.emptySet())) {
                    Map<LocalDate, Double> dm = meterDaily.get(leaf);
                    if (dm == null) continue;
                    v += dm.getOrDefault(xd, 0.0);
                }
            }
            values.add(v);
            total += v;
        }
        groupSeries.put(g, values);
        groupSeriesTotals.put(g, total);
    }

    List<Integer> sortedGroups = new ArrayList<>(stackGroups);
    sortedGroups.sort((a, b) -> Double.compare(groupSeriesTotals.getOrDefault(b, 0.0), groupSeriesTotals.getOrDefault(a, 0.0)));

    int GROUP_LIMIT = 8;
    List<Integer> shownGroups = new ArrayList<>();
    shownGroups.addAll(sortedGroups.subList(0, Math.min(GROUP_LIMIT, sortedGroups.size())));
    List<Double> otherSeries = new ArrayList<>();
    for (int i = 0; i < stackLabels.size(); i++) otherSeries.add(0.0);
    for (int i = GROUP_LIMIT; i < sortedGroups.size(); i++) {
        Integer g = sortedGroups.get(i);
        List<Double> v = groupSeries.get(g);
        for (int j = 0; j < otherSeries.size(); j++) otherSeries.set(j, otherSeries.get(j) + nz(v.get(j)));
    }
    boolean hasOther = false;
    for (Double v : otherSeries) { if (v > 0.0) { hasOther = true; break; } }

    Map<Integer, Double> treemapRootTotals = new HashMap<>();
    for (Integer r : roots) {
        double t = 0.0;
        for (Integer leaf : rootLeaves.getOrDefault(r, Collections.emptySet())) t += meterTotalKwh.getOrDefault(leaf, 0.0);
        treemapRootTotals.put(r, t);
    }
    List<Integer> sortedRoots = new ArrayList<>(roots);
    sortedRoots.sort((a, b) -> Double.compare(treemapRootTotals.getOrDefault(b, 0.0), treemapRootTotals.getOrDefault(a, 0.0)));

    Map<Integer, Double> leafValues = new HashMap<>();
    for (Integer id : scopeMeterIds) {
        List<Integer> ch = childrenByParent.get(id);
        if (ch == null || ch.isEmpty()) {
            leafValues.put(id, meterTotalKwh.getOrDefault(id, 0.0));
        } else {
            leafValues.put(id, 0.0);
        }
    }

    StringBuilder treemapDataJson = new StringBuilder();
    treemapDataJson.append("[");
    for (int i = 0; i < sortedRoots.size(); i++) {
        if (i > 0) treemapDataJson.append(',');
        treemapDataJson.append(treemapNodeJson(sortedRoots.get(i), childrenByParent, leafValues, meterNames, new HashSet<Integer>()));
    }
    treemapDataJson.append("]");
    double treemapTotal = 0.0;
    for (Double v : leafValues.values()) treemapTotal += nz(v);
    boolean noData = dayLabels.isEmpty();
%>
<!doctype html>
<html>
<head>
    <title>에너지 관리</title>
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
        .kpi-grid { display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:10px; margin:10px 0 14px; }
        .kpi-card { background:#fff; border:1px solid #d9e2ec; border-radius:10px; padding:10px 12px; box-shadow:0 1px 3px rgba(0,0,0,.06); }
        .kpi-label { font-size:12px; color:#486581; margin-bottom:6px; }
        .kpi-value { font-size:20px; font-weight:700; color:#102a43; }
        .kpi-sub { font-size:12px; color:#627d98; }
        .chart-grid { display:grid; grid-template-columns:2fr 1fr; gap:12px; }
        .chart-container { margin:0; min-width:0; height:360px; min-height:360px; }
        .layout { display:grid; grid-template-columns:2fr 1fr; gap:12px; margin-top:12px; }
        .warn-list { margin:0; padding-left:18px; }
        .warn-list li { margin:8px 0; }
        .data-table { font-size:13px; }
        .data-table th { background:#f4f7fb; }
        .pos { color:#0b6e4f; font-weight:700; }
        .neg { color:#b42318; font-weight:700; }
        @media (max-width: 1200px) {
            .kpi-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }
            .chart-grid, .layout { grid-template-columns:1fr; }
        }
    </style>
</head>
<body>
<div class="title-bar">
    <h2>📊 에너지 관리</h2>
    <div style="display:flex; gap:8px; align-items:center;">
        <button class="back-btn" onclick="location.href='/epms/energy_sankey.jsp' + location.search">에너지 흐름 분석</button>
        <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
    </div>
</div>

<form method="GET">
    집계:
    <select name="bucket">
        <option value="day" <%= "day".equals(bucket) ? "selected" : "" %>>일</option>
        <option value="month" <%= "month".equals(bucket) ? "selected" : "" %>>월</option>
    </select>

    건물:
    <select name="building" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String b : buildingOptions) { %>
        <option value="<%= h(b) %>" <%= (b != null && b.equals(building)) ? "selected" : "" %>><%= h(b) %></option>
        <% } %>
    </select>

    용도:
    <select name="usage" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String u : usageOptions) { %>
        <option value="<%= h(u) %>" <%= (u != null && u.equals(usage)) ? "selected" : "" %>><%= h(u) %></option>
        <% } %>
    </select>

    계측기:
    <select name="meter">
        <option value="">전체</option>
        <% for (String[] m : meterOptions) { %>
        <option value="<%= h(m[0]) %>" <%= (m[0] != null && m[0].equals(meter)) ? "selected" : "" %>><%= h(m[1]) %> (#<%= h(m[0]) %>)</option>
        <% } %>
    </select>

    기간:
    <input type="date" name="startDate" value="<%= startDate %>">
    ~
    <input type="date" name="endDate" value="<%= endDate %>">
    <button type="submit">조회</button>
</form>

<% if (noData) { %>
<div class="no-data-banner">데이터가 없습니다</div>
<% } %>

<div class="kpi-grid">
    <div class="kpi-card">
        <div class="kpi-label">당일 사용량 (kWh)</div>
        <div class="kpi-value"><%= String.format(java.util.Locale.US, "%,.1f", todayKwh) %></div>
        <div class="kpi-sub"><%= endDate %> 기준</div>
    </div>
    <div class="kpi-card">
        <div class="kpi-label">전일 대비</div>
        <div class="kpi-value <%= (dayOverDayPct != null && dayOverDayPct < 0) ? "pos" : "neg" %>">
            <%= dayOverDayPct == null ? "-" : String.format(java.util.Locale.US, "%+,.1f%%", dayOverDayPct) %>
        </div>
        <div class="kpi-sub">전일 사용량 대비</div>
    </div>
    <div class="kpi-card">
        <div class="kpi-label">이번달 누적 (kWh)</div>
        <div class="kpi-value"><%= String.format(java.util.Locale.US, "%,.1f", mtdKwh) %></div>
        <div class="kpi-sub"><%= ym.toString() %></div>
    </div>
    <div class="kpi-card">
        <div class="kpi-label">피크전력 (kW)</div>
        <div class="kpi-value"><%= String.format(java.util.Locale.US, "%,.1f", peakKw) %></div>
        <div class="kpi-sub">조회기간 최대</div>
    </div>
    <div class="kpi-card">
        <div class="kpi-label">역률 평균</div>
        <div class="kpi-value"><%= String.format(java.util.Locale.US, "%,.3f", avgPf) %></div>
        <div class="kpi-sub">조회기간 평균</div>
    </div>
</div>

<div class="chart-grid">
    <div class="panel">
        <h3 style="margin:0 0 8px 0;">사용량 추이 (Stacked Area)</h3>
        <div class="chart-container">
            <div id="stackedChart" style="width:100%; height:100%;"></div>
        </div>
    </div>
    <div class="panel">
        <h3 style="margin:0 0 8px 0;">기여도 (Treemap)</h3>
        <div style="font-size:12px; color:#64748b; margin-bottom:6px;">최상위 노드: <%= h(rootSummary) %></div>
        <div class="chart-container">
            <div id="treeChart" style="width:100%; height:100%;"></div>
        </div>
    </div>
</div>

<div class="layout">
    <div class="panel">
        <h3 style="margin:0 0 8px 0;">상세 테이블</h3>
        <table class="data-table">
            <thead>
            <tr>
                <th>날짜</th>
                <th>사용량(kWh)</th>
                <th>전일대비(%)</th>
                <th>피크전력(kW)</th>
                <th>리셋의심건수</th>
            </tr>
            </thead>
            <tbody>
            <%
                for (int i = 0; i < dayLabels.size(); i++) {
                    double prev = (i > 0) ? nz(dayKwh.get(i - 1)) : 0.0;
                    Double pct = (i > 0 && prev > 0.0) ? ((nz(dayKwh.get(i)) - prev) / prev * 100.0) : null;
            %>
            <tr>
                <td><%= dayLabels.get(i).toString() %></td>
                <td><%= String.format(java.util.Locale.US, "%,.2f", nz(dayKwh.get(i))) %></td>
                <td class="<%= (pct != null && pct < 0) ? "pos" : "neg" %>"><%= pct == null ? "-" : String.format(java.util.Locale.US, "%+,.1f%%", pct) %></td>
                <td><%= String.format(java.util.Locale.US, "%,.2f", nz(dayPeak.get(i))) %></td>
                <td><%= String.format(java.util.Locale.US, "%,d", dayResets.get(i)) %></td>
            </tr>
            <% } %>
            <% if (dayLabels.isEmpty()) { %>
            <tr><td colspan="5">조회된 데이터가 없습니다.</td></tr>
            <% } %>
            </tbody>
        </table>
    </div>
    <div class="panel">
        <h3 style="margin:0 0 8px 0;">이상 징후</h3>
        <ul class="warn-list">
            <li>음수 일사용량(리셋/교체 의심): <strong><%= String.format(java.util.Locale.US, "%,d", resetDays) %>일</strong></li>
            <li>전일대비 20% 초과 급증: <strong><%= String.format(java.util.Locale.US, "%,d", spikeDays) %>일</strong></li>
            <li>야간 기저부하 과다(00~05시): <strong><%= nightHigh ? "주의" : "정상" %></strong></li>
        </ul>
        <div style="margin-top:8px; font-size:12px; color:#627d98;">
            야간 평균 <%= String.format(java.util.Locale.US, "%,.2f", nightBaseKw) %> kW /
            전체 평균 <%= String.format(java.util.Locale.US, "%,.2f", avgKw) %> kW
        </div>
        <hr style="border:none;border-top:1px solid #e4e7eb;margin:12px 0;">
        <div style="font-size:13px;">기간 누적 사용량: <strong><%= String.format(java.util.Locale.US, "%,.1f", periodTotalKwh) %> kWh</strong></div>
    </div>
</div>

<script>
function fmtNum(v, d) {
  const n = Number(v);
  if (!Number.isFinite(n)) return '-';
  return n.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
}

const curBuilding = "<%= jsq(building == null ? "" : building) %>";
const curUsage = "<%= jsq(usage == null ? "" : usage) %>";
const curMeter = "<%= jsq(meter == null ? "" : meter) %>";
const curBucket = "<%= jsq(bucket == null ? "day" : bucket) %>";

const stackLabels = [<%
for (int i = 0; i < stackLabels.size(); i++) {
    if (i > 0) out.print(',');
    out.print("\"" + jsq(stackLabels.get(i)) + "\"");
}
%>];

const stackSeries = [
<%
    for (int i = 0; i < shownGroups.size(); i++) {
        Integer r = shownGroups.get(i);
        if (i > 0) out.print(',');
        out.print("{name:\"" + jsq(meterLabel(r, meterNames)) + "\",type:\"line\",stack:\"kwh\",smooth:true,symbol:\"none\",areaStyle:{},data:[");
        List<Double> v = groupSeries.get(r);
        for (int j = 0; j < v.size(); j++) {
            if (j > 0) out.print(',');
            out.print(String.format(java.util.Locale.US, "%.6f", nz(v.get(j))));
        }
        out.print("]}");
    }
    if (hasOther) {
        if (!shownGroups.isEmpty()) out.print(',');
        out.print("{name:\"기타\",type:\"line\",stack:\"kwh\",smooth:true,symbol:\"none\",areaStyle:{},data:[");
        for (int j = 0; j < otherSeries.size(); j++) {
            if (j > 0) out.print(',');
            out.print(String.format(java.util.Locale.US, "%.6f", nz(otherSeries.get(j))));
        }
        out.print("]}");
    }
%>
];

const stackedChart = echarts.init(document.getElementById('stackedChart'));
stackedChart.setOption({
  tooltip: {
    trigger: 'axis',
    formatter: function(params) {
      if (!params || !params.length) return '';
      const lines = [params[0].axisValue || ''];
      params.forEach(function(p){ lines.push(p.marker + p.seriesName + ': ' + fmtNum(p.value, 1) + ' kWh'); });
      return lines.join('<br/>');
    }
  },
  legend: { type: 'scroll', top: 6 },
  grid: { left: 50, right: 20, top: 78, bottom: 30, containLabel: true },
  xAxis: { type: 'category', data: stackLabels, triggerEvent: true },
  yAxis: { type: 'value', axisLabel: { formatter: function(v){ return fmtNum(v, 0); } } },
  series: stackSeries
});

function toLastDayOfMonth(yyyyMm) {
  const parts = (yyyyMm || "").split("-");
  if (parts.length !== 2) return null;
  const y = Number(parts[0]);
  const m = Number(parts[1]);
  if (!Number.isFinite(y) || !Number.isFinite(m)) return null;
  const dt = new Date(y, m, 0); // JS month is 0-based, day=0 -> previous month end
  const yy = dt.getFullYear();
  const mm = String(dt.getMonth() + 1).padStart(2, "0");
  const dd = String(dt.getDate()).padStart(2, "0");
  return yy + "-" + mm + "-" + dd;
}

function goSankeyDrill(label) {
  const x = (label || '').trim();
  if (!x) return;

  let drillStart = x;
  let drillEnd = x;
  if (curBucket === 'month') {
    drillStart = x + "-01";
    drillEnd = toLastDayOfMonth(x) || drillStart;
  }

  const qs = new URLSearchParams({
    building: curBuilding,
    usage: curUsage,
    meter: curMeter,
    startDate: drillStart,
    endDate: drillEnd
  });
  window.location.href = "/epms/energy_sankey.jsp?" + qs.toString();
}

stackedChart.on('click', function(p) {
  if (!p) return;
  if (p.componentType === 'series' || p.componentType === 'xAxis') {
    goSankeyDrill(p.name || p.value || '');
  }
});

// 그리드 빈 영역 클릭도 가장 가까운 x축 라벨로 드릴다운
stackedChart.getZr().on('click', function(e) {
  const px = [e.offsetX, e.offsetY];
  const inGrid = stackedChart.containPixel('grid', px);
  if (!inGrid) return;
  const xVal = stackedChart.convertFromPixel({ xAxisIndex: 0 }, px[0]);
  if (xVal == null) return;
  const idx = Math.round(Number(xVal));
  if (!Number.isFinite(idx)) return;
  if (idx < 0 || idx >= stackLabels.length) return;
  goSankeyDrill(stackLabels[idx]);
});

const treeChart = echarts.init(document.getElementById('treeChart'));
const treeData = <%= treemapDataJson.toString() %>;
const treeHasData = <%= treemapTotal > 0.0 ? "true" : "false" %>;
treeChart.setOption({
  tooltip: treeHasData ? {
    formatter: function(info){
      const v = info.value == null ? 0 : Number(info.value);
      return (info.name || '') + '<br/>' + fmtNum(v, 1) + ' kWh';
    }
  } : undefined,
  graphic: treeHasData ? undefined : {
    type: 'text',
    left: 'center',
    top: 'middle',
    style: {
      text: 'Treemap 데이터 없음',
      fill: '#64748b',
      fontSize: 14,
      fontWeight: 600
    }
  },
  series: [{
    type: 'treemap',
    roam: false,
    breadcrumb: { show: true },
    nodeClick: 'zoomToNode',
    color: ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#17becf', '#bcbd22', '#9467bd', '#8c564b'],
    colorMappingBy: 'index',
    label: { show: true, formatter: '{b}' },
    upperLabel: { show: false },
    levels: [
      { itemStyle: { borderColor: '#ffffff', borderWidth: 2, gapWidth: 2 } },
      { colorSaturation: [0.55, 0.85], itemStyle: { borderColor: '#ffffff', borderWidth: 1, gapWidth: 1 } },
      { colorSaturation: [0.35, 0.65], itemStyle: { borderColor: '#f8fafc', borderWidth: 1, gapWidth: 1 } }
    ],
    data: treeHasData ? treeData : []
  }]
});

window.addEventListener('resize', function(){ stackedChart.resize(); treeChart.resize(); });
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
<%
} // end try-with-resources
%>
</body>
</html>
