<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="epms.peak.*" %>
<%@ include file="../includes/epms_html.jspf" %>
<%
PeakComputationService peakService = new PeakComputationService();
PeakDashboardData pageData = null;
String err = null;
String msg = request.getParameter("msg");
String floorFilter = request.getParameter("floor");
String categoryFilter = request.getParameter("category");
String statusFilter = request.getParameter("status");
if (floorFilter == null) floorFilter = "";
if (categoryFilter == null) categoryFilter = "";
if (statusFilter == null) statusFilter = "";
floorFilter = floorFilter.trim();
categoryFilter = categoryFilter.trim();
statusFilter = statusFilter.trim();
String encodedFloorFilter = floorFilter.isEmpty() ? "" : URLEncoder.encode(floorFilter, StandardCharsets.UTF_8.name());
String encodedCategoryFilter = categoryFilter.isEmpty() ? "" : URLEncoder.encode(categoryFilter, StandardCharsets.UTF_8.name());
String encodedStatusFilter = statusFilter.isEmpty() ? "" : URLEncoder.encode(statusFilter, StandardCharsets.UTF_8.name());
try {
    pageData = peakService.loadDashboard();
} catch (Exception e) {
    err = e.getMessage();
}
List<PeakMeterRow> rows = pageData == null ? Collections.<PeakMeterRow>emptyList() : pageData.getTopPeakMeters();
List<PeakPolicyStatusRow> policyRows = pageData == null ? Collections.<PeakPolicyStatusRow>emptyList() : pageData.getPolicyStatusRows();
Set<String> floorOptions = new TreeSet<String>();
Set<String> categoryOptions = new TreeSet<String>();
List<PeakPolicyStatusRow> filteredPolicyRows = new ArrayList<PeakPolicyStatusRow>();
List<PeakPolicyStatusRow> actionRows = new ArrayList<PeakPolicyStatusRow>();
List<PeakPolicyStatusRow> repeatedExceededRows = new ArrayList<PeakPolicyStatusRow>();
int urgentRepeatedCount = 0;
Map<String, Integer> repeatedFloorSummary = new LinkedHashMap<String, Integer>();
Map<String, Integer> urgentRepeatedFloorSummary = new LinkedHashMap<String, Integer>();
Map<String, Integer> floorSummary = new LinkedHashMap<String, Integer>();
Map<String, Integer> categorySummary = new LinkedHashMap<String, Integer>();
for (PeakPolicyStatusRow row : policyRows) {
    if (row.getFloorName() != null && !row.getFloorName().trim().isEmpty()) floorOptions.add(row.getFloorName().trim());
    if (row.getCategoryName() != null && !row.getCategoryName().trim().isEmpty()) categoryOptions.add(row.getCategoryName().trim());
    boolean matchesFloor = floorFilter.isEmpty() || floorFilter.equals(row.getFloorName() == null ? "" : row.getFloorName().trim());
    boolean matchesCategory = categoryFilter.isEmpty() || categoryFilter.equals(row.getCategoryName() == null ? "" : row.getCategoryName().trim());
    boolean matchesStatus = statusFilter.isEmpty()
            || ("WARNING".equals(statusFilter) && row.isWarningTarget() && !row.isControlTarget())
            || ("CONTROL".equals(statusFilter) && row.isControlTarget());
    if (matchesFloor && matchesCategory && matchesStatus) {
        filteredPolicyRows.add(row);
        String floorKey = row.getFloorName() == null || row.getFloorName().trim().isEmpty() ? "-" : row.getFloorName().trim();
        String categoryKey = row.getCategoryName() == null || row.getCategoryName().trim().isEmpty() ? "-" : row.getCategoryName().trim();
        floorSummary.put(floorKey, Integer.valueOf(floorSummary.getOrDefault(floorKey, Integer.valueOf(0)).intValue() + 1));
        categorySummary.put(categoryKey, Integer.valueOf(categorySummary.getOrDefault(categoryKey, Integer.valueOf(0)).intValue() + 1));
        if (row.isWarningTarget()) actionRows.add(row);
    }
}
repeatedExceededRows.addAll(actionRows);
Collections.sort(repeatedExceededRows, new Comparator<PeakPolicyStatusRow>() {
    @Override
    public int compare(PeakPolicyStatusRow left, PeakPolicyStatusRow right) {
        int byToday = Integer.compare(right.getExceededCountToday(), left.getExceededCountToday());
        if (byToday != 0) return byToday;
        int byConsecutive = Integer.compare(right.getConsecutiveExceededCount(), left.getConsecutiveExceededCount());
        if (byConsecutive != 0) return byConsecutive;
        int byLastHour = Integer.compare(right.getExceededCountLastHour(), left.getExceededCountLastHour());
        if (byLastHour != 0) return byLastHour;
        return Double.compare(right.getUsagePct(), left.getUsagePct());
    }
});
for (PeakPolicyStatusRow row : repeatedExceededRows) {
    boolean urgentRepeated = row.isControlTarget() || row.getExceededCountToday() >= 4 || row.getConsecutiveExceededCount() >= 3;
    String repeatedFloorKey = row.getFloorName() == null || row.getFloorName().trim().isEmpty() ? "-" : row.getFloorName().trim();
    repeatedFloorSummary.put(repeatedFloorKey, Integer.valueOf(repeatedFloorSummary.getOrDefault(repeatedFloorKey, Integer.valueOf(0)).intValue() + 1));
    if (urgentRepeated) {
        urgentRepeatedCount++;
        urgentRepeatedFloorSummary.put(repeatedFloorKey, Integer.valueOf(urgentRepeatedFloorSummary.getOrDefault(repeatedFloorKey, Integer.valueOf(0)).intValue() + 1));
    }
}
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Peak 愿由?/title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1540px;margin:14px auto;padding:0 12px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff}
        .panel-box,.stat-card{padding:12px;border:1px solid #d9dfe8;border-radius:8px;background:#fff;box-shadow:none}
        .stats{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:10px}
        .stat-card strong{display:block;font-size:22px;margin-top:4px}
        .notice{padding:12px 14px;border-radius:10px;font-weight:700;transition:opacity .35s ease,transform .35s ease}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .notice-dismiss{opacity:0;transform:translateY(-4px)}
        .guide-grid{display:grid;grid-template-columns:1.3fr .7fr;gap:12px}
        .guide-list{display:grid;gap:8px}
        .guide-item{padding:10px 12px;border:1px solid #e2e8f0;border-radius:8px;background:#fafcff}
        .sub-grid{display:grid;grid-template-columns:1fr;gap:12px}
        .filter-row{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;align-items:end;margin-bottom:12px}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field.actions-field{display:flex;gap:8px;align-items:flex-end}
        .chip-row{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}
        .section-nav{display:flex;flex-wrap:wrap;gap:8px}
        .summary-chip{display:inline-flex;align-items:center;gap:6px;padding:8px 10px;border-radius:999px;border:1px solid #d9dfe8;background:#f8fafc;font-size:12px}
        .alert-chip{display:inline-flex;align-items:center;gap:6px;padding:8px 10px;border-radius:999px;font-size:12px;font-weight:700;border:1px solid #fecaca;background:#fff1f2;color:#b42318}
        .warning-chip{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;font-size:12px;font-weight:700;border:1px solid #fde68a;background:#fffbeb;color:#b45309}
        .control-chip{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;font-size:12px;font-weight:700;border:1px solid #fecaca;background:#fff1f2;color:#b42318}
        .active-filter-bar{display:flex;flex-wrap:wrap;gap:8px}
        .active-filter-chip{display:inline-flex;align-items:center;gap:6px;padding:8px 10px;border-radius:999px;background:#eef2ff;border:1px solid #c7d2fe;color:#3730a3;font-size:12px;font-weight:700}
        a.summary-chip,a.alert-chip,a.warning-chip,a.control-chip{text-decoration:none}
        a.active-filter-chip{text-decoration:none}
        .rank-critical{background:#fff7f7}
        .rank-watch{background:#fffdf5}
        .table-wrap{overflow-x:auto}
        table{min-width:1240px}
        .muted{color:var(--muted);font-size:11px}
        @media (max-width:1280px){.stats{grid-template-columns:repeat(2,minmax(0,1fr))}}
        @media (max-width:1100px){.guide-grid,.filter-row{grid-template-columns:1fr}}
        @media (max-width:760px){.stats{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>Peak 愿由?/h1>
            <p>理쒓렐 30??湲곗??쇰줈 `?쒓컙 理쒕? kW`? `15遺??섏슂?꾨젰 peak`瑜??④퍡 蹂댁뿬以섏꽌 peak ?댁쁺 ??곸쓣 鍮좊Ⅴ寃??먮떒?⑸땲??</p>
        </div>
        <div class="top-links">
            <a class="btn" href="peak_policy_manage.jsp">Peak ?뺤콉</a>
            <a class="btn" href="tenant_meter_store_tiles.jsp">?먭꺽寃移??댁쁺</a>
            <a class="btn" href="tenant_billing_manage.jsp">留ㅼ옣 ?뺤궛</a>
            <a class="btn" href="energy_manage.jsp">?먮꼫吏 遺꾩꽍</a>
            <a class="btn" href="epms_main.jsp">EPMS ??/a>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %>
    <div class="notice ok"><%= h(msg) %></div>
    <% } %>
    <% if (err != null && !err.trim().isEmpty()) { %>
    <div class="notice err"><%= h(err) %></div>
    <% } %>

    <% if (!floorFilter.isEmpty() || !categoryFilter.isEmpty() || !statusFilter.isEmpty()) { %>
    <div class="panel-box">
        <div class="active-filter-bar">
            <% if (!floorFilter.isEmpty()) { %>
            <a class="active-filter-chip" href="peak_management.jsp?<%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) + "&" %><%= statusFilter.isEmpty() ? "" : "status=" + h(encodedStatusFilter) %>">痢? <%= h(floorFilter) %> ?댁젣</a>
            <% } %>
            <% if (!categoryFilter.isEmpty()) { %>
            <a class="active-filter-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= statusFilter.isEmpty() ? "" : "status=" + h(encodedStatusFilter) %>">?낆쥌: <%= h(categoryFilter) %> ?댁젣</a>
            <% } %>
            <% if (!statusFilter.isEmpty()) { %>
            <a class="active-filter-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) %>">?곹깭: <%= h(statusFilter) %> ?댁젣</a>
            <% } %>
            <a class="summary-chip" href="peak_management.jsp">?꾩껜 ?꾪꽣 珥덇린??/a>
        </div>
    </div>
    <% } %>

    <div class="panel-box">
        <div class="section-nav">
            <a class="summary-chip" href="#top_peak">?곸쐞 怨꾩륫湲?/a>
            <a class="summary-chip" href="#repeated_exceeded">諛섎났 珥덇낵</a>
            <a class="summary-chip" href="#action_targets">寃쎄퀬/?쒖뼱 ???/a>
            <a class="summary-chip" href="#policy_status">?뺤콉 ?곸슜 ?곹깭</a>
        </div>
    </div>

    <div class="stats">
        <div class="stat-card"><span>?댁쁺以?留ㅼ옣</span><strong><%= pageData == null ? 0 : pageData.getActiveStoreCount() %></strong></div>
        <div class="stat-card"><span>?꾩옱 留ㅽ븨 怨꾩륫湲?/span><strong><%= pageData == null ? 0 : pageData.getActiveMappedMeterCount() %></strong></div>
        <div class="stat-card"><span>留ㅽ븨 ?꾨씫 留ㅼ옣</span><strong><%= pageData == null ? 0 : pageData.getUnmappedActiveStoreCount() %></strong></div>
        <div class="stat-card"><span>?쒖꽦 ?뺤콉 留ㅼ옣</span><strong><%= pageData == null ? 0 : pageData.getActivePolicyCount() %></strong></div>
        <div class="stat-card"><span>寃쎄퀬 ???/span><strong><%= pageData == null ? 0 : pageData.getWarningTargetCount() %></strong></div>
        <div class="stat-card"><span>?쒖뼱 ???/span><strong><%= pageData == null ? 0 : pageData.getControlTargetCount() %></strong></div>
        <div class="stat-card"><span>理쒕? ?쒓컙 ?쇳겕</span><strong><%= pageData == null ? "0.00" : String.format(java.util.Locale.US, "%,.2f", pageData.getTopInstantPeakKw()) %></strong><span class="muted">kW</span></div>
        <div class="stat-card"><span>理쒕? 15遺??섏슂?꾨젰</span><strong><%= pageData == null ? "0.00" : String.format(java.util.Locale.US, "%,.2f", pageData.getTopDemandPeakKw()) %></strong><span class="muted">kW</span></div>
    </div>

    <div class="panel-box">
        <div class="guide-list">
            <% if (pageData != null && pageData.isPeakSummaryTableReady()) { %>
            <div class="guide-item">
                <strong>15분 집계 테이블 사용 중</strong>
                <div class="muted">마지막 집계 시각: <%= h(pageData.getPeakSummaryUpdatedAt()) %></div>
                <% if (pageData.isPeakSummaryStale()) { %>
                <div class="notice err" style="margin-top:8px;">집계 지연 경고: 마지막 집계가 <%= pageData.getPeakSummaryLagMinutes() %>분 전입니다.</div>
                <% } else { %>
                <div class="muted">집계 지연: <%= pageData.getPeakSummaryLagMinutes() %>분</div>
                <% } %>
                <div class="muted">권장 배치: `docs/sql/create_peak_15min_summary_agent_job.sql` 실행 후 15분 주기 SQL Agent Job 운영</div>
            </div>
            <% } else { %>
            <div class="guide-item">
                <strong>실시간 measurements 계산 사용 중</strong>
                <div class="muted">`docs/sql/create_epms_peak_15min_summary.sql` 적용 전까지는 조회 시점에 15분 수요전력을 직접 계산합니다.</div>
                <div class="muted">다음 단계: `create_epms_peak_15min_summary.sql` 적용 후 `create_peak_15min_summary_agent_job.sql`로 배치 연결</div>
            </div>
            <% } %>
        </div>
    </div>

    <div class="guide-grid">
        <div class="sub-grid">
            <div class="panel-box" id="top_peak">
                <h2>理쒓렐 30??15遺??섏슂?꾨젰 ?곸쐞 怨꾩륫湲?/h2>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>?쒖쐞</th>
                            <th>怨꾩륫湲?/th>
                            <th>嫄대Ъ / ?⑤꼸</th>
                            <th>???留ㅼ옣</th>
                            <th>?쒓컙 ?쇳겕(kW)</th>
                            <th>15遺??섏슂?꾨젰(kW)</th>
                            <th>?쒓컙 ?쇳겕 ?쒓컖</th>
                            <th>15遺??섏슂?꾨젰 ?쒓컖</th>
                            <th>Action</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (rows.isEmpty()) { %>
                        <tr><td colspan="8" class="muted">?쒖떆??peak ?곗씠?곌? ?놁뒿?덈떎.</td></tr>
                        <% } %>
                        <% for (int i = 0; i < rows.size(); i++) { PeakMeterRow row = rows.get(i); %>
                        <tr>
                            <td><%= i + 1 %></td>
                            <td>#<%= row.getMeterId() %> / <%= h(row.getMeterName()) %></td>
                            <td><%= h(row.getBuildingName()) %> / <%= h(row.getPanelName()) %></td>
                            <td><%= h(row.getStoreCode()) %> / <%= h(row.getStoreName()) %></td>
                            <td><strong><%= String.format(java.util.Locale.US, "%,.2f", row.getInstantPeakKw()) %></strong></td>
                            <td><strong><%= String.format(java.util.Locale.US, "%,.2f", row.getDemandPeakKw()) %></strong></td>
                            <td><%= h(row.getInstantPeakMeasuredAt()) %></td>
                            <td><%= h(row.getDemandPeakMeasuredAt()) %></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="panel-box" id="repeated_exceeded">
                <h2>諛섎났 珥덇낵 留ㅼ옣 ?쒖쐞</h2>
                <% if (pageData != null && !pageData.isPolicyTableReady()) { %>
                <div class="guide-item">?뺤콉 ?뚯씠釉붿씠 ?꾩쭅 ?놁뼱 諛섎났 珥덇낵 ?쒖쐞瑜?怨꾩궛?섏? 紐삵빀?덈떎.</div>
                <% } else { %>
                <div class="chip-row">
                    <span class="summary-chip">?꾪꽣 寃곌낵 <strong><%= repeatedExceededRows.size() %></strong>嫄?/span>
                    <span class="alert-chip">利됱떆 ?뺤씤 ?꾩슂 <strong><%= urgentRepeatedCount %></strong>嫄?/span>
                </div>
                <div class="chip-row">
                    <% for (Map.Entry<String, Integer> entry : repeatedFloorSummary.entrySet()) { %>
                    <a class="summary-chip" href="peak_management.jsp?floor=<%= h(URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8.name())) %><%= categoryFilter.isEmpty() ? "" : "&category=" + h(encodedCategoryFilter) %><%= statusFilter.isEmpty() ? "" : "&status=" + h(encodedStatusFilter) %>">痢?<strong><%= h(entry.getKey()) %></strong> <%= entry.getValue() %>嫄?/a>
                    <% } %>
                </div>
                <% if (!urgentRepeatedFloorSummary.isEmpty()) { %>
                <div class="chip-row">
                    <% for (Map.Entry<String, Integer> entry : urgentRepeatedFloorSummary.entrySet()) { %>
                    <a class="alert-chip" href="peak_management.jsp?floor=<%= h(URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8.name())) %><%= categoryFilter.isEmpty() ? "" : "&category=" + h(encodedCategoryFilter) %><%= statusFilter.isEmpty() ? "" : "&status=" + h(encodedStatusFilter) %>">湲닿툒 痢?<strong><%= h(entry.getKey()) %></strong> <%= entry.getValue() %>嫄?/a>
                    <% } %>
                </div>
                <% } %>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>?쒖쐞</th>
                            <th>留ㅼ옣</th>
                            <th>痢?/ ?낆쥌</th>
                            <th>?ㅻ뒛 珥덇낵</th>
                            <th>理쒓렐 1?쒓컙</th>
                            <th>?곗냽 珥덇낵</th>
                            <th>?ъ슜瑜?%)</th>
                            <th>?곹깭</th>
                            <th>?묒뾽</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (repeatedExceededRows.isEmpty()) { %>
                        <tr><td colspan="9" class="muted">?꾩옱 諛섎났 珥덇낵濡?蹂?留ㅼ옣???놁뒿?덈떎.</td></tr>
                        <% } %>
                        <% for (int i = 0; i < repeatedExceededRows.size() && i < 5; i++) { PeakPolicyStatusRow row = repeatedExceededRows.get(i); boolean urgentRepeated = row.isControlTarget() || row.getExceededCountToday() >= 4 || row.getConsecutiveExceededCount() >= 3; boolean watchRepeated = !urgentRepeated && (row.getExceededCountToday() >= 2 || row.getExceededCountLastHour() >= 2); %>
                        <tr class="<%= urgentRepeated ? "rank-critical" : (watchRepeated ? "rank-watch" : "") %>">
                            <td><strong><%= i + 1 %></strong></td>
                            <td><%= h(row.getStoreCode()) %> / <%= h(row.getStoreName()) %></td>
                            <td><%= h(row.getFloorName()) %> / <%= h(row.getCategoryName()) %></td>
                            <td><%= row.getExceededCountToday() %></td>
                            <td><%= row.getExceededCountLastHour() %></td>
                            <td><%= row.getConsecutiveExceededCount() %></td>
                            <td><strong><%= String.format(java.util.Locale.US, "%,.1f", row.getUsagePct()) %></strong></td>
                            <td><% if (urgentRepeated) { %><a class="control-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) + "&" %>status=CONTROL">利됱떆 議곗튂</a><% } else if (watchRepeated) { %><a class="warning-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) + "&" %>status=WARNING">吏묒쨷 愿李?/a><% } %> <strong><%= h(row.getStatusLabel()) %></strong></td>
                            <td><a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %>&return_floor=<%= h(floorFilter) %>&return_category=<%= h(categoryFilter) %>&return_status=<%= h(statusFilter) %>&return_section=repeated_exceeded">?뺤콉 蹂닿린</a></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
                <% } %>
            </div>

            <div class="panel-box" id="action_targets">
                <h2>寃쎄퀬/?쒖뼱 ???留ㅼ옣</h2>
                <% if (pageData != null && !pageData.isPolicyTableReady()) { %>
                <div class="guide-item">?뺤콉 ?뚯씠釉붿씠 ?꾩쭅 ?놁뼱??寃쎄퀬/?쒖뼱 ??곸쓣 怨꾩궛?섏? ?딆뒿?덈떎.</div>
                <% } else { %>
                <form method="get" class="filter-row">
                    <div class="field">
                        <label>痢?/label>
                        <select name="floor">
                            <option value="">?꾩껜</option>
                            <% for (String opt : floorOptions) { %>
                            <option value="<%= h(opt) %>" <%= opt.equals(floorFilter) ? "selected" : "" %>><%= h(opt) %></option>
                            <% } %>
                        </select>
                    </div>
                    <div class="field">
                        <label>?낆쥌</label>
                        <select name="category">
                            <option value="">?꾩껜</option>
                            <% for (String opt : categoryOptions) { %>
                            <option value="<%= h(opt) %>" <%= opt.equals(categoryFilter) ? "selected" : "" %>><%= h(opt) %></option>
                            <% } %>
                        </select>
                    </div>
                    <div class="field">
                        <label>?곹깭</label>
                        <select name="status">
                            <option value="">?꾩껜</option>
                            <option value="WARNING" <%= "WARNING".equals(statusFilter) ? "selected" : "" %>>寃쎄퀬</option>
                            <option value="CONTROL" <%= "CONTROL".equals(statusFilter) ? "selected" : "" %>>?쒖뼱</option>
                        </select>
                    </div>
                    <div class="field">
                        <label>?꾪꽣</label>
                        <button type="submit" class="btn btn-primary">?곸슜</button>
                    </div>
                </form>
                <div class="chip-row">
                    <a class="summary-chip" href="peak_management.jsp">?꾪꽣 珥덇린??/a>
                </div>
                <div class="chip-row">
                    <% for (Map.Entry<String, Integer> entry : floorSummary.entrySet()) { %>
                    <a class="summary-chip" href="peak_management.jsp?floor=<%= h(URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8.name())) %><%= categoryFilter.isEmpty() ? "" : "&category=" + h(encodedCategoryFilter) %><%= statusFilter.isEmpty() ? "" : "&status=" + h(encodedStatusFilter) %>">痢?<strong><%= h(entry.getKey()) %></strong> <%= entry.getValue() %>嫄?/a>
                    <% } %>
                </div>
                <div class="chip-row">
                    <% for (Map.Entry<String, Integer> entry : categorySummary.entrySet()) { %>
                    <a class="summary-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %>category=<%= h(URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8.name())) %><%= statusFilter.isEmpty() ? "" : "&status=" + h(encodedStatusFilter) %>">?낆쥌 <strong><%= h(entry.getKey()) %></strong> <%= entry.getValue() %>嫄?/a>
                    <% } %>
                </div>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>留ㅼ옣</th>
                            <th>痢?/ ?낆쥌</th>
                            <th>?쒕룄(kW)</th>
                            <th>理쒓렐 15遺??쇳겕(kW)</th>
                            <th>?ъ슜瑜?%)</th>
                            <th>理쒓렐 珥덇낵 ?쒓컖</th>
                            <th>理쒓렐 1?쒓컙</th>
                            <th>?ㅻ뒛</th>
                            <th>?곗냽 珥덇낵</th>
                            <th>?곹깭</th>
                            <th>?묒뾽</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (actionRows.isEmpty()) { %>
                        <tr><td colspan="11" class="muted">?꾩옱 寃쎄퀬 ?먮뒗 ?쒖뼱 ???留ㅼ옣???놁뒿?덈떎.</td></tr>
                        <% } %>
                        <% for (PeakPolicyStatusRow row : actionRows) { %>
                        <tr>
                            <td><%= h(row.getStoreCode()) %> / <%= h(row.getStoreName()) %></td>
                            <td><%= h(row.getFloorName()) %> / <%= h(row.getCategoryName()) %></td>
                            <td><%= row.getPeakLimitKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", row.getPeakLimitKw().doubleValue()) %></td>
                            <td><%= row.getDemandPeakKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", row.getDemandPeakKw().doubleValue()) %></td>
                            <td><strong><%= String.format(java.util.Locale.US, "%,.1f", row.getUsagePct()) %></strong></td>
                            <td><%= h(row.getLatestExceededAt()) %></td>
                            <td><%= row.getExceededCountLastHour() %></td>
                            <td><%= row.getExceededCountToday() %></td>
                            <td><%= row.getConsecutiveExceededCount() %></td>
                            <td><strong><%= h(row.getStatusLabel()) %></strong></td>
                            <td><a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %>&return_floor=<%= h(floorFilter) %>&return_category=<%= h(categoryFilter) %>&return_status=<%= h(statusFilter) %>&return_section=action_targets">?뺤콉 蹂닿린</a></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
                <% } %>
            </div>

            <div class="panel-box" id="policy_status">
                <h2>?뺤콉 ?곸슜 ?곹깭</h2>
                <% if (pageData != null && !pageData.isPolicyTableReady()) { %>
                <div class="guide-item">`peak_policy` ?뚯씠釉붿씠 ?꾩쭅 ?놁뼱 ?뺤콉 ?곹깭瑜??쒖떆?섏? ?딆뒿?덈떎. 癒쇱? `docs/sql/create_epms_peak_policy_schema.sql`???곸슜??二쇱꽭??</div>
                <% } else { %>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>留ㅼ옣</th>
                            <th>?쒕룄(kW)</th>
                            <th>理쒓렐 15遺??쇳겕(kW)</th>
                            <th>?ъ슜瑜?%)</th>
                            <th>?곹깭</th>
                            <th>Action</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (filteredPolicyRows.isEmpty()) { %>
                        <tr><td colspan="6" class="muted">?쒖꽦 peak ?뺤콉???놁뒿?덈떎.</td></tr>
                        <% } %>
                        <% for (PeakPolicyStatusRow row : filteredPolicyRows) { %>
                        <tr>
                            <td><%= h(row.getStoreCode()) %> / <%= h(row.getStoreName()) %></td>
                            <td><%= row.getPeakLimitKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", row.getPeakLimitKw().doubleValue()) %></td>
                            <td><%= row.getDemandPeakKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", row.getDemandPeakKw().doubleValue()) %></td>
                            <td><%= String.format(java.util.Locale.US, "%,.1f", row.getUsagePct()) %></td>
                            <td><strong><%= h(row.getStatusLabel()) %></strong></td>
                            <td><a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %>&return_floor=<%= h(floorFilter) %>&return_category=<%= h(categoryFilter) %>&return_status=<%= h(statusFilter) %>&return_section=policy_status">?뺤콉 蹂닿린</a></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
                <% } %>
            </div>
        </div>
        <div class="panel-box">
            <h2>?ㅼ쓬 ?④퀎</h2>
            <div class="guide-list">
                <div class="guide-item">?꾩옱??議고쉶 ?쒖젏??15遺??섏슂?꾨젰??怨꾩궛?⑸땲?? ?ㅼ쓬 ?④퀎?먯꽌??`peak_15min_summary` 媛숈? 吏묎퀎 ?뚯씠釉붾줈 ??꺼 ?ъ궗?⑹꽦???믪씠??寃?醫뗭뒿?덈떎.</div>
                <div class="guide-item">?뺤콉 湲곗?? `Peak ?뺤콉` ?붾㈃?먯꽌 愿由ы븯怨? ?댄썑?먮뒗 留ㅼ옣蹂?珥덇낵?④낵 ?쒖뼱 ?곗꽑?쒖쐞 怨꾩궛??吏곸젒 ?곌껐?????덉뒿?덈떎.</div>
                <div class="guide-item">留ㅼ옣蹂?`?쇳겕 ?쒕룄`, `二쇱쓽/寃쎄퀬/?쒖뼱 湲곗?`????ν븯???뺤콉 ?뚯씠釉붿씠 異붽??섎㈃ ?ㅼ젣 peak ?댁쁺 ?붾㈃?쇰줈 ?뺤옣?????덉뒿?덈떎.</div>
                <div class="guide-item">諛섎났 珥덇낵 留ㅼ옣, ?쒓컙?蹂?peak 湲곗뿬?? 怨꾩빟?꾨젰 ?鍮?珥덇낵?⑥쓣 遺숈씠硫??뺤궛怨?遺꾨━??peak ?댁쁺 ??쒕낫?쒓? ?꾩꽦?⑸땲??</div>
                <div class="guide-item">`留ㅽ븨 ?꾨씫 留ㅼ옣`??癒쇱? 以꾩뿬??peak 梨낆엫 諛곕텇怨??쒖뼱 ?곗꽑?쒖쐞媛 ?덉젙?⑸땲??</div>
            </div>
        </div>
    </div>
</div>
<script>
(function() {
    var notices = document.querySelectorAll('.notice.ok');
    if (!notices.length) return;
    window.setTimeout(function() {
        notices.forEach(function(el) { el.classList.add('notice-dismiss'); });
    }, 2200);
    window.setTimeout(function() {
        notices.forEach(function(el) {
            if (el && el.parentNode) el.parentNode.removeChild(el);
        });
    }, 2700);
})();
</script>
</body>
</html>
