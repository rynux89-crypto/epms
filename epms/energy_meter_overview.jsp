<%@ page import="java.sql.*, java.util.*" %>
<%@ page import="java.time.*" %>
<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%
try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String building = request.getParameter("building");
    String usage = request.getParameter("usage");
    String keyword = request.getParameter("keyword");
    if (building == null) building = "";
    if (usage == null) usage = "";
    if (keyword == null) keyword = "";
    building = building.trim();
    usage = usage.trim();
    keyword = keyword.trim();

    LocalDate today = LocalDate.now();
    YearMonth currentYm = YearMonth.from(today);
    YearMonth prevYm = currentYm.minusMonths(1);
    LocalDate prevMonthStart = prevYm.atDay(1);
    LocalDate prevMonthEnd = prevYm.atEndOfMonth();

    List<String> buildingOptions = new ArrayList<String>();
    List<String> usageOptions = new ArrayList<String>();
    List<Map<String, Object>> meterCards = new ArrayList<Map<String, Object>>();
    String queryError = null;

    try {
        try (PreparedStatement ps = conn.prepareStatement("SELECT DISTINCT building_name FROM dbo.meters WHERE building_name IS NOT NULL AND LTRIM(RTRIM(building_name)) <> '' ORDER BY building_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) buildingOptions.add(rs.getString(1));
        }
        try (PreparedStatement ps = conn.prepareStatement("SELECT DISTINCT usage_type FROM dbo.meters WHERE usage_type IS NOT NULL AND LTRIM(RTRIM(usage_type)) <> '' ORDER BY usage_type");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) usageOptions.add(rs.getString(1));
        }

        StringBuilder sql = new StringBuilder();
        sql.append("WITH meter_scope AS ( ")
           .append("    SELECT m.meter_id, m.name, m.panel_name, m.building_name, m.usage_type ")
           .append("    FROM dbo.meters m WHERE 1=1 ");

        List<Object> params = new ArrayList<Object>();
        if (!building.isEmpty()) {
            sql.append(" AND m.building_name = ? ");
            params.add(building);
        }
        if (!usage.isEmpty()) {
            sql.append(" AND m.usage_type = ? ");
            params.add(usage);
        }
        if (!keyword.isEmpty()) {
            sql.append(" AND (ISNULL(m.name,'') LIKE ? OR ISNULL(m.panel_name,'') LIKE ? OR CAST(m.meter_id AS varchar(20)) LIKE ?) ");
            String like = "%" + keyword + "%";
            params.add(like);
            params.add(like);
            params.add(like);
        }

        sql.append("), latest_power AS ( ")
           .append("    SELECT x.meter_id, x.measured_at, x.active_power_total ")
           .append("    FROM ( ")
           .append("        SELECT ms.meter_id, ms.measured_at, CAST(ms.active_power_total AS float) AS active_power_total, ")
           .append("               ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn ")
           .append("        FROM dbo.measurements ms ")
           .append("        INNER JOIN meter_scope s ON s.meter_id = ms.meter_id ")
           .append("        WHERE ms.active_power_total IS NOT NULL ")
           .append("    ) x WHERE x.rn = 1 ")
           .append("), latest_valid_power AS ( ")
           .append("    SELECT x.meter_id, x.measured_at, x.active_power_total ")
           .append("    FROM ( ")
           .append("        SELECT ms.meter_id, ms.measured_at, CAST(ms.active_power_total AS float) AS active_power_total, ")
           .append("               ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn ")
           .append("        FROM dbo.measurements ms ")
           .append("        INNER JOIN meter_scope s ON s.meter_id = ms.meter_id ")
           .append("        WHERE ms.active_power_total IS NOT NULL AND ABS(CAST(ms.active_power_total AS float)) > 0.0001 ")
           .append("    ) x WHERE x.rn = 1 ")
           .append("), day_last AS ( ")
           .append("    SELECT ms.meter_id, CAST(ms.measured_at AS date) AS d, CAST(ms.energy_consumed_total AS float) AS energy_total, ")
           .append("           ROW_NUMBER() OVER (PARTITION BY ms.meter_id, CAST(ms.measured_at AS date) ORDER BY ms.measured_at DESC) AS rn ")
           .append("    FROM dbo.measurements ms ")
           .append("    INNER JOIN meter_scope s ON s.meter_id = ms.meter_id ")
           .append("    WHERE ms.energy_consumed_total IS NOT NULL ")
           .append("      AND ms.measured_at >= DATEADD(day, -1, ?) ")
           .append("      AND ms.measured_at < DATEADD(day, 1, ?) ")
           .append("), day_meter AS ( ")
           .append("    SELECT meter_id, d, energy_total AS end_total FROM day_last WHERE rn = 1 ")
           .append("), day_diff AS ( ")
           .append("    SELECT meter_id, d, end_total - LAG(end_total) OVER (PARTITION BY meter_id ORDER BY d) AS day_kwh ")
           .append("    FROM day_meter ")
           .append("), prev_month_usage AS ( ")
           .append("    SELECT meter_id, SUM(CASE WHEN day_kwh >= 0 THEN day_kwh ELSE 0 END) AS last_month_kwh ")
           .append("    FROM day_diff WHERE d BETWEEN ? AND ? GROUP BY meter_id ")
           .append(") ")
           .append("SELECT s.meter_id, s.name, s.panel_name, s.building_name, s.usage_type, ")
           .append("       lp.measured_at AS current_measured_at, lp.active_power_total AS current_kw, ")
           .append("       lvp.measured_at AS current_valid_measured_at, lvp.active_power_total AS current_valid_kw, ")
           .append("       pmu.last_month_kwh ")
           .append("FROM meter_scope s ")
           .append("LEFT JOIN latest_power lp ON lp.meter_id = s.meter_id ")
           .append("LEFT JOIN latest_valid_power lvp ON lvp.meter_id = s.meter_id ")
           .append("LEFT JOIN prev_month_usage pmu ON pmu.meter_id = s.meter_id ")
           .append("ORDER BY ISNULL(pmu.last_month_kwh, 0) DESC, s.meter_id ASC");

        try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            for (Object p : params) ps.setObject(idx++, p);
            ps.setDate(idx++, java.sql.Date.valueOf(prevMonthStart));
            ps.setDate(idx++, java.sql.Date.valueOf(prevMonthEnd));
            ps.setDate(idx++, java.sql.Date.valueOf(prevMonthStart));
            ps.setDate(idx++, java.sql.Date.valueOf(prevMonthEnd));

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<String, Object>();
                    row.put("meter_id", Integer.valueOf(rs.getInt("meter_id")));
                    row.put("name", rs.getString("name"));
                    row.put("panel_name", rs.getString("panel_name"));
                    row.put("building_name", rs.getString("building_name"));
                    row.put("usage_type", rs.getString("usage_type"));
                    row.put("current_measured_at", rs.getTimestamp("current_measured_at"));
                    row.put("current_kw", (Double) rs.getObject("current_kw"));
                    row.put("current_valid_measured_at", rs.getTimestamp("current_valid_measured_at"));
                    row.put("current_valid_kw", (Double) rs.getObject("current_valid_kw"));
                    row.put("last_month_kwh", (Double) rs.getObject("last_month_kwh"));
                    meterCards.add(row);
                }
            }
        }
    } catch (Exception e) {
        queryError = e.getMessage();
    }
%>
<!doctype html>
<html>
<head>
    <title>에너지 관리</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap{max-width:1280px;margin:0 auto}
        .toolbar{display:flex;gap:6px;align-items:end;flex-wrap:wrap;margin:10px 0 12px}
        .toolbar .field{display:flex;flex-direction:column;gap:4px;min-width:140px}
        .toolbar .field label{font-size:12px;font-weight:700;color:#475569}
        .toolbar input,.toolbar select{margin:0}
        .tile-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}
        .meter-tile{display:block;text-decoration:none;color:inherit;background:linear-gradient(180deg,#fff 0%,#fff8ee 100%);border:1px solid #ecd6ad;border-radius:12px;padding:12px;box-shadow:none;transition:transform .15s ease, border-color .15s ease}
        .meter-tile:hover{transform:translateY(-3px);box-shadow:0 18px 34px rgba(146,93,0,.14);border-color:#d8b26b}
        .tile-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}
        .meter-name{font-size:16px;font-weight:800;color:#2f3b49;line-height:1.3}
        .meter-meta{margin-top:4px;font-size:12px;color:#6b7280}
        .meter-id{display:inline-flex;align-items:center;justify-content:center;min-width:38px;height:24px;padding:0 8px;border-radius:999px;background:#fff3dd;border:1px solid #ead4a3;color:#8a5a00;font-size:11px;font-weight:800}
        .usage-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px}
        .usage-card{background:#fff;border:1px solid #eee2c6;border-radius:10px;padding:10px}
        .usage-label{font-size:11px;color:#7c8697;text-transform:uppercase;letter-spacing:.05em}
        .usage-value{margin-top:6px;font-size:clamp(18px,1.5vw,26px);font-weight:800;color:#15283b;line-height:1.05;word-break:break-all}
        .usage-value.is-muted{color:#94a3b8}
        .usage-value.energy-value{font-size:clamp(17px,1.3vw,22px)}
        .usage-unit{font-size:12px;color:#64748b;margin-left:4px}
        .usage-sub{margin-top:6px;font-size:12px;color:#64748b}
        .usage-sub.fallback-note{display:none}
        .usage-card.fallback-current .usage-sub{display:none}
        .usage-card.fallback-current .usage-sub.fallback-note{display:block}
        .tile-head .usage-sub.fallback-note{display:none !important}
        .tile-foot{margin-top:10px;display:flex;justify-content:flex-end;align-items:center}
        .tile-foot span:first-child{display:none}
        .go-detail{font-weight:800;color:#a66700;border:1px solid #e8c47a;background:#fff3d9;border-radius:999px;padding:6px 10px;font-size:12px}
        .empty-box,.err-box{margin:12px 0;padding:12px 14px;border-radius:12px}
        .empty-box{background:#f8fafc;border:1px solid #dbe5f2;color:#475569}
        .err-box{background:#fff1f1;border:1px solid #ffc9c9;color:#b42318;font-weight:700}
        @media (max-width:720px){.usage-grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>에너지 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/energy_overview.jsp'">에너지 현황</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        계측기별 지난달 사용량과 현재 사용량을 타일로 확인합니다. 타일을 클릭하면 개별 사용량 관리 화면으로 이동합니다.
    </div>

    <form method="GET" class="toolbar">
        <div class="field">
            <label for="building">건물</label>
            <select id="building" name="building">
                <option value="">전체</option>
                <% for (String b : buildingOptions) { %>
                <option value="<%= h(b) %>" <%= b.equals(building) ? "selected" : "" %>><%= h(b) %></option>
                <% } %>
            </select>
        </div>
        <div class="field">
            <label for="usage">용도</label>
            <select id="usage" name="usage">
                <option value="">전체</option>
                <% for (String u : usageOptions) { %>
                <option value="<%= h(u) %>" <%= u.equals(usage) ? "selected" : "" %>><%= h(u) %></option>
                <% } %>
            </select>
        </div>
        <div class="field" style="min-width:220px;">
            <label for="keyword">검색</label>
            <input id="keyword" name="keyword" type="text" value="<%= h(keyword) %>" placeholder="계측기명, 패널명, meter_id">
        </div>
        <button type="submit">조회</button>
    </form>

    <% if (queryError != null && !queryError.trim().isEmpty()) { %>
    <div class="err-box">조회 오류: <%= h(queryError) %></div>
    <% } %>

    <% if (meterCards.isEmpty()) { %>
    <div class="empty-box">조회된 계측기가 없습니다.</div>
    <% } else { %>
    <div class="tile-grid">
        <% for (Map<String, Object> row : meterCards) {
               Integer meterId = (Integer) row.get("meter_id");
               String meterName = (String) row.get("name");
               if (meterName == null || meterName.trim().isEmpty()) meterName = "Meter " + meterId;
               Double currentKw = (Double) row.get("current_kw");
               Double currentValidKw = (Double) row.get("current_valid_kw");
               Double lastMonthKwh = (Double) row.get("last_month_kwh");
               Timestamp currentMeasuredAt = (Timestamp) row.get("current_measured_at");
               Timestamp currentValidMeasuredAt = (Timestamp) row.get("current_valid_measured_at");
               double shownCurrentKw = 0.0d;
               boolean usingFallbackCurrent = false;
               if (currentKw != null && Math.abs(currentKw.doubleValue()) > 0.0001d) {
                   shownCurrentKw = currentKw.doubleValue();
               } else if (currentValidKw != null) {
                   shownCurrentKw = currentValidKw.doubleValue();
                   usingFallbackCurrent = true;
               }
        %>
        <a class="meter-tile" href="energy_meter_detail.jsp?meter_id=<%= meterId %>">
            <div class="tile-head">
                <div>
                    <div class="meter-name"><%= h(meterName) %></div>
                    <div class="meter-meta">
                        <%= h(String.valueOf(row.get("building_name") == null ? "-" : row.get("building_name"))) %>
                        /
                        <%= h(String.valueOf(row.get("panel_name") == null ? "-" : row.get("panel_name"))) %>
                        /
                        <%= h(String.valueOf(row.get("usage_type") == null ? "-" : row.get("usage_type"))) %>
                    </div>
                    <div class="usage-sub fallback-note"><%= usingFallbackCurrent ? ("최근 유효값 기준: " + h(String.valueOf(currentValidMeasuredAt))) : "" %></div>
                </div>
                <div class="meter-id">#<%= meterId %></div>
            </div>

            <div class="usage-grid">
                <div class="usage-card">
                    <div class="usage-label">지난달 사용량</div>
                    <div class="usage-value energy-value">
                        <%= String.format(java.util.Locale.US, "%,.1f", lastMonthKwh == null ? 0.0 : lastMonthKwh.doubleValue()) %>
                        <span class="usage-unit">kWh</span>
                    </div>
                    <div class="usage-sub"><%= prevYm.toString() %> 누적</div>
                </div>
                <div class="usage-card <%= usingFallbackCurrent ? "fallback-current" : "" %>">
                    <div class="usage-label">현재 사용량</div>
                    <div class="usage-value <%= shownCurrentKw <= 0.0001d ? "is-muted" : "" %>">
                        <%= String.format(java.util.Locale.US, "%,.2f", shownCurrentKw) %>
                        <span class="usage-unit">kW</span>
                    </div>
                    <div class="usage-sub"><%= currentMeasuredAt == null ? "최근 측정값 없음" : h(String.valueOf(currentMeasuredAt)) %></div>
                </div>
            </div>

            <% if (usingFallbackCurrent) { %>
            <div class="usage-sub" style="margin-top:10px;">최근 유효값 기준으로 현재 사용량을 표시했습니다.</div>
            <% } %>
            <div class="tile-foot">
                <span>개별 사용량 조회</span>
                <span class="go-detail">상세 보기</span>
            </div>
        </a>
        <% } %>
    </div>
    <% } %>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
<%
} // end try-with-resources
%>
