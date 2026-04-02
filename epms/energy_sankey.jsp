<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%
    try (Connection conn = openDbConnection()) {
    LocalDate today = LocalDate.now();

    String startDate = request.getParameter("startDate");
    String endDate = request.getParameter("endDate");
    String building = request.getParameter("building");
    String usage = request.getParameter("usage");
    String meter = request.getParameter("meter");
    boolean meterParamProvided = request.getParameterMap().containsKey("meter");
    boolean firstLoad = request.getQueryString() == null || request.getQueryString().trim().isEmpty();
    String viewMode = request.getParameter("view");
    if (viewMode == null || (!"topdown".equals(viewMode) && !"sankey".equals(viewMode))) viewMode = "sankey";

    if (endDate == null || endDate.trim().isEmpty()) endDate = today.toString();
    if (startDate == null || startDate.trim().isEmpty()) startDate = today.minusDays(6).toString();

    LocalDate startD = LocalDate.parse(startDate);
    LocalDate endD = LocalDate.parse(endDate);
    if (endD.isBefore(startD)) {
        LocalDate t = startD;
        startD = endD;
        endD = t;
        startDate = startD.toString();
        endDate = endD.toString();
    }

    List<String> buildingOptions = new ArrayList<>();
    List<String> usageOptions = new ArrayList<>();
    List<String[]> meterOptions = new ArrayList<>();
    Map<Integer, String> meterNames = new HashMap<>();
    Integer defaultFocusMeterId = null;

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
                    String id = rs.getString("meter_id");
                    String name = rs.getString("name");
                    meterOptions.add(new String[]{id, name});
                    try {
                        Integer meterId = Integer.valueOf(Integer.parseInt(id));
                        meterNames.put(meterId, name);
                        if ("EAST_VCB_MAIN".equals(name)) defaultFocusMeterId = meterId;
                    } catch (Exception ignore) {}
                }
            }
        }
    } catch (Exception e) {
        out.println("<div style='color:#b42318;background:#fff1f1;border:1px solid #fecaca;padding:10px;border-radius:8px;'>옵션 조회 오류: " + h(e.getMessage()) + "</div>");
    }

    Set<Integer> candidateMeters = new LinkedHashSet<>();
    for (String[] m : meterOptions) {
        try { candidateMeters.add(Integer.parseInt(m[0])); } catch (Exception ignore) {}
    }

    Map<Integer, List<Integer>> childrenByParent = new LinkedHashMap<>();
    Map<Integer, List<Integer>> parentsByChild = new LinkedHashMap<>();
    Set<Integer> childSet = new HashSet<>();
    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT parent_meter_id, child_meter_id " +
            "FROM dbo.meter_tree " +
            "WHERE is_active=1 " +
            "ORDER BY parent_meter_id, ISNULL(sort_order, 2147483647), child_meter_id");
         ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            int p = rs.getInt("parent_meter_id");
            int c = rs.getInt("child_meter_id");
            if (!candidateMeters.contains(p) || !candidateMeters.contains(c)) continue;
            childrenByParent.computeIfAbsent(p, k -> new ArrayList<>()).add(c);
            parentsByChild.computeIfAbsent(c, k -> new ArrayList<>()).add(p);
            childSet.add(c);
        }
    } catch (Exception ignore) {
    }

    if ((firstLoad || !meterParamProvided) && defaultFocusMeterId != null && (meter == null || meter.trim().isEmpty())) {
        meter = String.valueOf(defaultFocusMeterId);
    }

    Integer selectedMeterId = parseNullableInt(meter);
    Set<Integer> scopeMeters = new LinkedHashSet<>();
    if (selectedMeterId != null && candidateMeters.contains(selectedMeterId)) {
        Deque<Integer> dq = new ArrayDeque<>();
        dq.add(selectedMeterId);
        while (!dq.isEmpty()) {
            int cur = dq.poll();
            if (!scopeMeters.add(cur)) continue;
            List<Integer> ch = childrenByParent.get(cur);
            if (ch != null) for (Integer cc : ch) dq.add(cc);
        }
    } else {
        scopeMeters.addAll(candidateMeters);
    }

    Map<Integer, Double> meterTotalKwh = new HashMap<>();
    if (!scopeMeters.isEmpty()) {
        StringBuilder inMarks = new StringBuilder();
        List<Integer> scopeList = new ArrayList<>(scopeMeters);
        for (int i = 0; i < scopeList.size(); i++) {
            if (i > 0) inMarks.append(',');
            inMarks.append('?');
        }

        String sql =
            "WITH base AS ( " +
            "  SELECT ms.meter_id, CAST(ms.measured_at AS date) AS d, ms.measured_at, CAST(ms.energy_consumed_total AS float) AS energy_total " +
            "  FROM dbo.measurements ms " +
            "  WHERE ms.measured_at >= DATEADD(day, -1, ?) AND ms.measured_at < DATEADD(day, 1, ?) " +
            "    AND ms.meter_id IN (" + inMarks.toString() + ") " +
            "), day_last AS ( " +
            "  SELECT meter_id, d, energy_total, ROW_NUMBER() OVER (PARTITION BY meter_id, d ORDER BY measured_at DESC) rn " +
            "  FROM base WHERE energy_total IS NOT NULL " +
            "), day_meter AS ( " +
            "  SELECT meter_id, d, energy_total AS end_total FROM day_last WHERE rn=1 " +
            "), day_diff AS ( " +
            "  SELECT meter_id, d, end_total - LAG(end_total) OVER (PARTITION BY meter_id ORDER BY d) AS day_kwh " +
            "  FROM day_meter " +
            ") " +
            "SELECT meter_id, SUM(CASE WHEN day_kwh >= 0 THEN day_kwh ELSE 0 END) AS sum_kwh " +
            "FROM day_diff WHERE d BETWEEN ? AND ? GROUP BY meter_id";

        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            int idx = 1;
            ps.setString(idx++, startDate);
            ps.setString(idx++, endDate);
            for (Integer id : scopeList) ps.setInt(idx++, id.intValue());
            ps.setString(idx++, startDate);
            ps.setString(idx++, endDate);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) meterTotalKwh.put(rs.getInt("meter_id"), rs.getDouble("sum_kwh"));
            }
        } catch (Exception e) {
            out.println("<div style='color:#b42318;background:#fff1f1;border:1px solid #fecaca;padding:10px;border-radius:8px;'>사용량 조회 오류: " + h(e.getMessage()) + "</div>");
        }
    }

    Map<Integer, Double> memoSubtree = new HashMap<>();
    java.util.function.Function<Integer, Double> subtree = new java.util.function.Function<Integer, Double>() {
        @Override
        public Double apply(Integer node) {
            if (memoSubtree.containsKey(node)) return memoSubtree.get(node);
            List<Integer> ch = childrenByParent.get(node);
            double v;
            if (ch == null || ch.isEmpty()) {
                v = meterTotalKwh.getOrDefault(node, 0.0);
            } else {
                v = 0.0;
                int inScopeChildCount = 0;
                for (Integer c : ch) {
                    if (!scopeMeters.contains(c)) continue;
                    inScopeChildCount++;
                    v += this.apply(c);
                }
                // 필터로 자식이 범위 밖인 경우, 부모 자체 사용량으로 fallback
                if (inScopeChildCount == 0) {
                    v = meterTotalKwh.getOrDefault(node, 0.0);
                }
            }
            memoSubtree.put(node, v);
            return v;
        }
    };

    List<Integer> roots = new ArrayList<>();
    for (Integer id : scopeMeters) if (!childSet.contains(id)) roots.add(id);
    if (selectedMeterId != null && scopeMeters.contains(selectedMeterId)) {
        roots.clear();
        roots.add(selectedMeterId);
    }
    if (roots.isEmpty()) roots.addAll(scopeMeters);

    Map<Integer, Integer> depthMap = new HashMap<>();
    Map<Integer, Integer> indegreeMap = new HashMap<>();
    for (Integer id : scopeMeters) indegreeMap.put(id, Integer.valueOf(0));
    for (Map.Entry<Integer, List<Integer>> e : childrenByParent.entrySet()) {
        Integer p = e.getKey();
        if (!scopeMeters.contains(p)) continue;
        for (Integer c : e.getValue()) {
            if (!scopeMeters.contains(c)) continue;
            indegreeMap.put(c, Integer.valueOf(indegreeMap.getOrDefault(c, Integer.valueOf(0)).intValue() + 1));
        }
    }

    Deque<Integer> dqDepth = new ArrayDeque<>();
    for (Integer id : scopeMeters) {
        if (indegreeMap.getOrDefault(id, Integer.valueOf(0)).intValue() == 0) {
            depthMap.put(id, Integer.valueOf(1));
            dqDepth.add(id);
        }
    }
    while (!dqDepth.isEmpty()) {
        int cur = dqDepth.poll();
        int nextDepth = depthMap.getOrDefault(cur, Integer.valueOf(1)).intValue() + 1;
        List<Integer> ch = childrenByParent.get(cur);
        if (ch == null) continue;
        for (Integer cc : ch) {
            if (!scopeMeters.contains(cc)) continue;
            Integer oldDepth = depthMap.get(cc);
            if (oldDepth == null || nextDepth > oldDepth.intValue()) {
                depthMap.put(cc, Integer.valueOf(nextDepth));
            }
            int nextIndegree = indegreeMap.getOrDefault(cc, Integer.valueOf(0)).intValue() - 1;
            indegreeMap.put(cc, Integer.valueOf(nextIndegree));
            if (nextIndegree == 0) dqDepth.add(cc);
        }
    }
    for (Integer id : scopeMeters) {
        if (!depthMap.containsKey(id)) depthMap.put(id, Integer.valueOf(1));
    }

    Map<Integer, Integer> displayOrderMap = new HashMap<>();
    int[] orderSeq = new int[]{0};
    java.util.function.Consumer<Integer> assignOrder = new java.util.function.Consumer<Integer>() {
        @Override
        public void accept(Integer node) {
            if (displayOrderMap.containsKey(node)) return;
            displayOrderMap.put(node, Integer.valueOf(orderSeq[0]++));
            List<Integer> ch = childrenByParent.get(node);
            if (ch == null) return;
            for (Integer c : ch) {
                if (!scopeMeters.contains(c)) continue;
                this.accept(c);
            }
        }
    };
    for (Integer r : roots) assignOrder.accept(r);
    for (Integer id : scopeMeters) {
        if (!displayOrderMap.containsKey(id)) displayOrderMap.put(id, Integer.valueOf(orderSeq[0]++));
    }

    List<Integer> orderedNodes = new ArrayList<>(scopeMeters);
    orderedNodes.sort((a, b) -> {
        int da = depthMap.getOrDefault(a, 99);
        int db = depthMap.getOrDefault(b, 99);
        if (da != db) return Integer.compare(da, db);
        int oa = displayOrderMap.getOrDefault(a, Integer.valueOf(999999)).intValue();
        int ob = displayOrderMap.getOrDefault(b, Integer.valueOf(999999)).intValue();
        if (oa != ob) return Integer.compare(oa, ob);
        return Integer.compare(a, b);
    });

    StringBuilder nodeJson = new StringBuilder("[");
    nodeJson.append("{\"name\":\"TOTAL\",\"depth\":0}");
    for (Integer id : orderedNodes) {
        String nm = meterNames.get(id);
        if (nm == null || nm.trim().isEmpty()) nm = "Meter " + id;
        List<Integer> parents = parentsByChild.get(id);
        List<String> parentLabels = new ArrayList<>();
        if (parents != null) {
            for (Integer pid : parents) {
                if (!scopeMeters.contains(pid)) continue;
                String parentName = meterNames.get(pid);
                if (parentName == null || parentName.trim().isEmpty()) parentName = "Meter " + pid;
                parentLabels.add(parentName + " (#" + pid + ")");
            }
        }
        String parentsLabel = String.join(", ", parentLabels);
        nodeJson.append(",{\"name\":\"").append(jsq(nm + " (#" + id + ")")).append("\",\"depth\":")
                .append(depthMap.getOrDefault(id, 99))
                .append(",\"parentCount\":").append(parentLabels.size())
                .append(",\"parentsLabel\":\"").append(jsq(parentsLabel)).append("\"}");
    }
    nodeJson.append("]");

    StringBuilder linkJson = new StringBuilder("[");
    boolean firstLink = true;
    double totalUsageKwh = 0.0;
    final double epsilonFlow = 0.0001;
    List<String> totalBreakdown = new ArrayList<>();
    for (Integer r : roots) {
        double rv = subtree.apply(r);
        if (rv <= 0.0) continue;
        String rName = (meterNames.get(r) == null ? "Meter " + r : meterNames.get(r)) + " (#" + r + ")";
        if (!firstLink) linkJson.append(',');
        linkJson.append("{\"source\":\"TOTAL\",\"target\":\"").append(jsq(rName)).append("\",\"value\":")
                .append(String.format(java.util.Locale.US, "%.6f", rv)).append("}");
        firstLink = false;
        totalUsageKwh += rv;
        totalBreakdown.add(rName + "\t" + String.format(java.util.Locale.US, "%,.1f", rv));
    }

    for (Integer p : childrenByParent.keySet()) {
        if (!scopeMeters.contains(p)) continue;
        String pName = (meterNames.get(p) == null ? "Meter " + p : meterNames.get(p)) + " (#" + p + ")";
        for (Integer c : childrenByParent.get(p)) {
            if (!scopeMeters.contains(c)) continue;
            double v = subtree.apply(c);
            if (v <= 0.0) continue;
            String cName = (meterNames.get(c) == null ? "Meter " + c : meterNames.get(c)) + " (#" + c + ")";
            if (!firstLink) linkJson.append(',');
            linkJson.append("{\"source\":\"").append(jsq(pName)).append("\",\"target\":\"").append(jsq(cName)).append("\",\"value\":")
                    .append(String.format(java.util.Locale.US, "%.6f", v)).append("}");
            firstLink = false;
        }
    }

    // 트리 링크가 하나도 없는 경우(측정 데이터 0/없음 포함), 하이어라키가 보이도록 구조 링크 fallback
    if (firstLink) {
        boolean hasTreeEdge = false;

        for (Integer r : roots) {
            if (!scopeMeters.contains(r)) continue;
            String rName = (meterNames.get(r) == null ? "Meter " + r : meterNames.get(r)) + " (#" + r + ")";
            if (!firstLink) linkJson.append(',');
            linkJson.append("{\"source\":\"TOTAL\",\"target\":\"").append(jsq(rName)).append("\",\"value\":")
                    .append(String.format(java.util.Locale.US, "%.6f", epsilonFlow)).append("}");
            firstLink = false;
            hasTreeEdge = true;
        }

        for (Integer p : childrenByParent.keySet()) {
            if (!scopeMeters.contains(p)) continue;
            String pName = (meterNames.get(p) == null ? "Meter " + p : meterNames.get(p)) + " (#" + p + ")";
            for (Integer c : childrenByParent.get(p)) {
                if (!scopeMeters.contains(c)) continue;
                String cName = (meterNames.get(c) == null ? "Meter " + c : meterNames.get(c)) + " (#" + c + ")";
                if (!firstLink) linkJson.append(',');
                linkJson.append("{\"source\":\"").append(jsq(pName)).append("\",\"target\":\"").append(jsq(cName)).append("\",\"value\":")
                        .append(String.format(java.util.Locale.US, "%.6f", epsilonFlow)).append("}");
                firstLink = false;
                hasTreeEdge = true;
            }
        }

        // 트리 자체가 없을 때는 TOTAL -> meter 최소 링크
        if (!hasTreeEdge) {
            List<Integer> flat = new ArrayList<>(scopeMeters);
            Collections.sort(flat);
            for (Integer id : flat) {
                String name = (meterNames.get(id) == null ? "Meter " + id : meterNames.get(id)) + " (#" + id + ")";
                if (!firstLink) linkJson.append(',');
                linkJson.append("{\"source\":\"TOTAL\",\"target\":\"").append(jsq(name)).append("\",\"value\":")
                        .append(String.format(java.util.Locale.US, "%.6f", epsilonFlow)).append("}");
                firstLink = false;
            }
        }
    }

    linkJson.append("]");

    int maxDepth = 1;
    for (Integer id : scopeMeters) maxDepth = Math.max(maxDepth, depthMap.getOrDefault(id, Integer.valueOf(1)).intValue());
    Map<Integer, List<Integer>> nodesByDepth = new LinkedHashMap<>();
    for (Integer id : orderedNodes) {
        int d = depthMap.getOrDefault(id, Integer.valueOf(1)).intValue();
        nodesByDepth.computeIfAbsent(Integer.valueOf(d), k -> new ArrayList<>()).add(id);
    }

    StringBuilder graphNodeJson = new StringBuilder("[");
    boolean firstGraphNode = true;
    int canvasWidth = 1200;
    int canvasHeight = Math.max(720, 180 * maxDepth);
    for (int depth = 1; depth <= maxDepth; depth++) {
        List<Integer> levelNodes = nodesByDepth.get(Integer.valueOf(depth));
        if (levelNodes == null || levelNodes.isEmpty()) continue;
        int levelCount = levelNodes.size();
        double y = (maxDepth == 1) ? (canvasHeight / 2.0) : (80.0 + ((double)(depth - 1) * (canvasHeight - 160.0) / (double)(maxDepth - 1)));
        for (int idx = 0; idx < levelCount; idx++) {
            Integer id = levelNodes.get(idx);
            String nm = meterNames.get(id);
            if (nm == null || nm.trim().isEmpty()) nm = "Meter " + id;
            List<Integer> parents = parentsByChild.get(id);
            List<String> parentLabels = new ArrayList<>();
            if (parents != null) {
                for (Integer pid : parents) {
                    if (!scopeMeters.contains(pid)) continue;
                    String parentName = meterNames.get(pid);
                    if (parentName == null || parentName.trim().isEmpty()) parentName = "Meter " + pid;
                    parentLabels.add(parentName + " (#" + pid + ")");
                }
            }
            double x = (levelCount == 1) ? (canvasWidth / 2.0) : (80.0 + ((double)idx * (canvasWidth - 160.0) / (double)(levelCount - 1)));
            if (!firstGraphNode) graphNodeJson.append(",");
            graphNodeJson.append("{\"id\":\"").append(jsq(String.valueOf(id))).append("\"")
                    .append(",\"name\":\"").append(jsq(nm + " (#" + id + ")")).append("\"")
                    .append(",\"x\":").append(String.format(java.util.Locale.US, "%.2f", x))
                    .append(",\"y\":").append(String.format(java.util.Locale.US, "%.2f", y))
                    .append(",\"depth\":").append(depth)
                    .append(",\"parentCount\":").append(parentLabels.size())
                    .append(",\"parentsLabel\":\"").append(jsq(String.join(", ", parentLabels))).append("\"")
                    .append("}");
            firstGraphNode = false;
        }
    }
    graphNodeJson.append("]");

    StringBuilder graphLinkJson = new StringBuilder("[");
    boolean firstGraphLink = true;
    for (Integer p : childrenByParent.keySet()) {
        if (!scopeMeters.contains(p)) continue;
        for (Integer c : childrenByParent.get(p)) {
            if (!scopeMeters.contains(c)) continue;
            double v = subtree.apply(c);
            String pName = (meterNames.get(p) == null ? "Meter " + p : meterNames.get(p)) + " (#" + p + ")";
            String cName = (meterNames.get(c) == null ? "Meter " + c : meterNames.get(c)) + " (#" + c + ")";
            if (!firstGraphLink) graphLinkJson.append(",");
            graphLinkJson.append("{\"source\":\"").append(jsq(String.valueOf(p))).append("\",\"target\":\"").append(jsq(String.valueOf(c))).append("\"")
                    .append(",\"value\":").append(String.format(java.util.Locale.US, "%.6f", Math.max(v, epsilonFlow)))
                    .append(",\"sourceLabel\":\"").append(jsq(pName)).append("\"")
                    .append(",\"targetLabel\":\"").append(jsq(cName)).append("\"")
                    .append("}");
            firstGraphLink = false;
        }
    }
    graphLinkJson.append("]");

    boolean noData = (totalUsageKwh <= 0.0);
%>
<!doctype html>
<html>
<head>
    <title>에너지 흐름 분석</title>
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
        .kpi-grid { display:grid; grid-template-columns:repeat(1,minmax(0,1fr)); gap:10px; margin:10px 0 12px; }
        .kpi-card { background:#fff; border:1px solid #d9e2ec; border-radius:10px; padding:10px 12px; box-shadow:0 1px 3px rgba(0,0,0,.06); }
        .kpi-label { font-size:12px; color:#486581; margin-bottom:6px; }
        .kpi-value { font-size:20px; font-weight:700; color:#102a43; }
        .kpi-sub { font-size:12px; color:#627d98; }
        .kpi-breakdown { margin-top:8px; border-top:1px dashed #d9e2ec; padding-top:8px; max-height:140px; overflow:auto; }
        .kpi-breakdown-row { display:flex; justify-content:space-between; gap:12px; font-size:12px; color:#334155; line-height:1.5; }
        .kpi-breakdown-row .name { flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
        .kpi-breakdown-row .val { font-weight:700; white-space:nowrap; }
        .chart-container {
            height: 60vh;
            min-height: 420px;
        }
        .filter-row {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: 10px 12px;
        }
        .view-mode-group {
            margin-left: auto;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            white-space: nowrap;
            font-weight: 600;
            color: #334155;
        }
        .view-mode-group label {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            font-weight: 500;
            color: #475569;
        }
        @media (max-width: 920px) {
            .view-mode-group {
                margin-left: 0;
                width: 100%;
            }
        }
    </style>
</head>
<body>
<div class="title-bar">
    <h2>🔀 에너지 흐름 분석</h2>
    <div class="inline-actions">
        <button class="back-btn" onclick="location.href='/epms/energy_manage.jsp<%= request.getQueryString()==null?"":"?"+request.getQueryString() %>'">에너지 관리</button>
        <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
    </div>
</div>

<form method="GET" class="filter-row">
    건물:
    <select name="building" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String b : buildingOptions) { %>
        <option value="<%= h(b) %>" <%= b.equals(building) ? "selected" : "" %>><%= h(b) %></option>
        <% } %>
    </select>

    용도:
    <select name="usage" onchange="this.form.meter.value=''; this.form.submit();">
        <option value="">전체</option>
        <% for (String u : usageOptions) { %>
        <option value="<%= h(u) %>" <%= u.equals(usage) ? "selected" : "" %>><%= h(u) %></option>
        <% } %>
    </select>

    계측기:
    <select name="meter">
        <option value="">전체</option>
        <% for (String[] m : meterOptions) { %>
        <option value="<%= h(m[0]) %>" <%= m[0].equals(meter) ? "selected" : "" %>><%= h(m[1]) %> (#<%= h(m[0]) %>)</option>
        <% } %>
    </select>

    기간:
    <input type="date" name="startDate" value="<%= startDate %>">
    ~
    <input type="date" name="endDate" value="<%= endDate %>">
    <span class="view-mode-group">
        보기:
        <label><input type="radio" name="view" value="sankey" <%= "sankey".equals(viewMode) ? "checked" : "" %>> 좌우 흐름</label>
        <label><input type="radio" name="view" value="topdown" <%= "topdown".equals(viewMode) ? "checked" : "" %>> 상하 계통도</label>
    </span>
    <button type="submit">조회</button>
</form>

<div class="kpi-grid">
    <div class="kpi-card">
        <div class="kpi-label">TOTAL 사용량 (kWh)</div>
        <div class="kpi-value"><%= String.format(java.util.Locale.US, "%,.1f", totalUsageKwh) %></div>
        <div class="kpi-sub"><%= startDate %> ~ <%= endDate %></div>
        <% if (!noData && !totalBreakdown.isEmpty()) { %>
        <div class="kpi-breakdown">
            <% for (String row : totalBreakdown) {
                   String[] p = row.split("\\t", 2);
            %>
            <div class="kpi-breakdown-row">
                <span class="name"><%= h(p.length > 0 ? p[0] : "") %></span>
                <span class="val"><%= h(p.length > 1 ? p[1] : "0.0") %> kWh</span>
            </div>
            <% } %>
        </div>
        <% } %>
    </div>
</div>

<% if (noData) { %>
<div class="no-data-banner">데이터가 없습니다</div>
<% } %>
<div class="chart-container">
    <div id="sankeyChart" style="width:100%; height:100%;"></div>
</div>

<script>
const sankeyNodes = <%= nodeJson.toString() %>;
const sankeyLinks = <%= linkJson.toString() %>;
const topDownNodes = <%= graphNodeJson.toString() %>;
const topDownLinks = <%= graphLinkJson.toString() %>;
const viewMode = "<%= jsq(viewMode) %>";

const chart = echarts.init(document.getElementById('sankeyChart'));
const commonTooltip = {
  tooltip: {
    trigger: 'item',
    formatter: function(p) {
      if (p.dataType === 'edge') {
        const sourceLabel = (p.data && p.data.sourceLabel) ? p.data.sourceLabel : p.data.source;
        const targetLabel = (p.data && p.data.targetLabel) ? p.data.targetLabel : p.data.target;
        return sourceLabel + ' → ' + targetLabel + '<br/>' + Number(p.data.value || 0).toLocaleString('en-US', {maximumFractionDigits:1}) + ' kWh';
      }
      var html = p.name;
      if (p.data && p.data.parentCount > 1) {
        html += '<br/>복수 전원 경로: ' + p.data.parentCount + '개';
      }
      if (p.data && p.data.parentsLabel) {
        html += '<br/>상위 노드: ' + p.data.parentsLabel;
      }
      return html;
    }
  }
};

const sankeyOption = {
  series: [{
    type: 'sankey',
    data: sankeyNodes,
    links: sankeyLinks,
    left: 20,
    right: 140,
    top: 24,
    bottom: 10,
    edgeLabel: {
      show: true,
      position: 'inside',
      align: 'center',
      verticalAlign: 'middle',
      color: '#334155',
      fontSize: 11,
      backgroundColor: 'rgba(255,255,255,0.7)',
      padding: [1, 3],
      formatter: function(p) {
        return Number(p.data.value || 0).toLocaleString('en-US', { maximumFractionDigits: 1 }) + ' kWh';
      }
    },
    label: {
      position: 'right',
      align: 'left',
      verticalAlign: 'middle',
      width: 160,
      overflow: 'break'
    },
    nodeWidth: 14,
    nodeGap: 14,
    nodeAlign: 'left',
    layoutIterations: 0,
    draggable: false,
    emphasis: { focus: 'adjacency' },
    lineStyle: { color: 'gradient', curveness: 0.35 }
  }]
};

const topDownOption = {
  animationDurationUpdate: 300,
  series: [{
    type: 'graph',
    layout: 'none',
    data: topDownNodes,
    links: topDownLinks,
    roam: true,
    draggable: false,
    left: 20,
    top: 24,
    right: 20,
    bottom: 24,
    symbol: 'roundRect',
    symbolSize: [120, 22],
    edgeSymbol: ['none', 'arrow'],
    edgeSymbolSize: [4, 8],
    label: {
      show: true,
      position: 'inside',
      fontSize: 11,
      overflow: 'truncate',
      width: 110,
      color: '#0f172a'
    },
    edgeLabel: {
      show: true,
      formatter: function(p) {
        return Number(p.data.value || 0).toLocaleString('en-US', { maximumFractionDigits: 1 }) + ' kWh';
      },
      fontSize: 10,
      color: '#475569',
      backgroundColor: 'rgba(255,255,255,0.72)',
      padding: [1, 3]
    },
    lineStyle: {
      color: '#94a3b8',
      width: 1.5,
      curveness: 0.12
    },
    itemStyle: {
      color: '#dbeafe',
      borderColor: '#3b82f6',
      borderWidth: 1
    },
    emphasis: { focus: 'adjacency' }
  }]
};

chart.setOption(Object.assign({}, commonTooltip, viewMode === 'topdown' ? topDownOption : sankeyOption));
window.addEventListener('resize', function(){ chart.resize(); });
</script>

<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
<%
    } // end try-with-resources
%>
