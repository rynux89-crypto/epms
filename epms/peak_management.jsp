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
String peakActionUrl = request.getContextPath() + "/peak-management-action";
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
    <title>Peak 관리</title>
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
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .notice-dismiss{opacity:0;transform:translateY(-4px)}
        .guide-grid{display:grid;grid-template-columns:1fr;gap:12px}
        .guide-list{display:grid;gap:8px}
        .guide-item{padding:10px 12px;border:1px solid #e2e8f0;border-radius:8px;background:#fafcff}
        .sub-grid{display:grid;grid-template-columns:1fr;gap:12px}
        .filter-row{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;align-items:end;margin-bottom:12px}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field.actions-field{display:flex;gap:8px;align-items:flex-end}
        .chip-row{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:10px}
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
        #action_targets{order:1}
        .sub-grid{order:2}
        #policy_status{order:3}
        #repeated_exceeded{order:1}
        #top_peak{order:2}
        @media (max-width:1100px){.guide-grid,.filter-row{grid-template-columns:1fr}}
        @media (max-width:760px){.stats{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>Peak 관리</h1>
            <p>최근 30일 기준으로 `순간 최대 kW`와 `15분 수요전력 peak`를 함께 보여주어 peak 운영 대상을 빠르게 판단합니다.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="peak_policy_manage.jsp">Peak 정책</a>
            <a class="btn" href="tenant_meter_store_tiles.jsp">원격검침 운영</a>
            <a class="btn" href="tenant_billing_manage.jsp">매장 정산</a>
            <a class="btn" href="energy_manage.jsp">에너지 분석</a>
            <a class="btn" href="epms_main.jsp">EPMS 홈</a>
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
            <a class="active-filter-chip" href="peak_management.jsp?<%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) + "&" %><%= statusFilter.isEmpty() ? "" : "status=" + h(encodedStatusFilter) %>">층: <%= h(floorFilter) %> 해제</a>
            <% } %>
            <% if (!categoryFilter.isEmpty()) { %>
            <a class="active-filter-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= statusFilter.isEmpty() ? "" : "status=" + h(encodedStatusFilter) %>">업종: <%= h(categoryFilter) %> 해제</a>
            <% } %>
            <% if (!statusFilter.isEmpty()) { %>
            <a class="active-filter-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) %>">상태: <%= h(statusFilter) %> 해제</a>
            <% } %>
            <a class="summary-chip" href="peak_management.jsp">전체 필터 초기화</a>
        </div>
    </div>
    <% } %>

    <div class="stats">
        <div class="stat-card"><span>운영중 매장</span><strong><%= pageData == null ? 0 : pageData.getActiveStoreCount() %></strong></div>
        <div class="stat-card"><span>현재 매핑 계측기</span><strong><%= pageData == null ? 0 : pageData.getActiveMappedMeterCount() %></strong></div>
        <div class="stat-card"><span>매핑 누락 매장</span><strong><%= pageData == null ? 0 : pageData.getUnmappedActiveStoreCount() %></strong></div>
        <div class="stat-card"><span>활성 정책 매장</span><strong><%= pageData == null ? 0 : pageData.getActivePolicyCount() %></strong></div>
        <div class="stat-card"><span>경고 대상</span><strong><%= pageData == null ? 0 : pageData.getWarningTargetCount() %></strong></div>
        <div class="stat-card"><span>제어 대상</span><strong><%= pageData == null ? 0 : pageData.getControlTargetCount() %></strong></div>
        <div class="stat-card"><span>최대 순간 피크</span><strong><%= pageData == null ? "0.00" : String.format(java.util.Locale.US, "%,.2f", pageData.getTopInstantPeakKw()) %></strong><span class="muted">kW</span></div>
        <div class="stat-card"><span>최대 15분 수요전력</span><strong><%= pageData == null ? "0.00" : String.format(java.util.Locale.US, "%,.2f", pageData.getTopDemandPeakKw()) %></strong><span class="muted">kW</span></div>
    </div>

    <div class="guide-grid">
        <div class="sub-grid">
            <div class="panel-box" id="top_peak">
                <h2>최근 30일 15분 수요전력 상위 계측기</h2>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>순위</th>
                            <th>계측기</th>
                            <th>건물 / 분전반</th>
                            <th>대상 매장</th>
                            <th>순간 피크(kW)</th>
                            <th>15분 수요전력(kW)</th>
                            <th>순간 피크 시각</th>
                            <th>15분 수요전력 시각</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (rows.isEmpty()) { %>
                        <tr><td colspan="8" class="muted">표시할 peak 데이터가 없습니다.</td></tr>
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
                <h2>반복 초과 매장 순위</h2>
                <% if (pageData != null && !pageData.isPolicyTableReady()) { %>
                <div class="guide-item">정책 테이블이 아직 없어 반복 초과 순위를 계산하지 못합니다.</div>
                <% } else { %>
                <div class="chip-row">
                    <span class="summary-chip">필터 결과 <strong><%= repeatedExceededRows.size() %></strong>건</span>
                    <span class="alert-chip">즉시 확인 필요 <strong><%= urgentRepeatedCount %></strong>건</span>
                </div>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>순위</th>
                            <th>매장</th>
                            <th>층 / 업종</th>
                            <th>오늘 초과</th>
                            <th>최근 1시간</th>
                            <th>연속 초과</th>
                            <th>사용률(%)</th>
                            <th>상태</th>
                            <th>작업</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (repeatedExceededRows.isEmpty()) { %>
                        <tr><td colspan="9" class="muted">현재 반복 초과로 볼 매장이 없습니다.</td></tr>
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
                            <td><% if (urgentRepeated) { %><a class="control-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) + "&" %>status=CONTROL">즉시 조치</a><% } else if (watchRepeated) { %><a class="warning-chip" href="peak_management.jsp?<%= floorFilter.isEmpty() ? "" : "floor=" + h(encodedFloorFilter) + "&" %><%= categoryFilter.isEmpty() ? "" : "category=" + h(encodedCategoryFilter) + "&" %>status=WARNING">집중 관찰</a><% } %> <strong><%= h(row.getStatusLabel()) %></strong></td>
                            <td><a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %>&return_floor=<%= h(floorFilter) %>&return_category=<%= h(categoryFilter) %>&return_status=<%= h(statusFilter) %>&return_section=repeated_exceeded">정책 보기</a></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
                <% } %>
            </div>

            <div class="panel-box" id="action_targets">
                <h2>즉시 대응 대상</h2>
                <% if (pageData != null && !pageData.isPolicyTableReady()) { %>
                <div class="guide-item">정책 테이블이 아직 없어 경고/제어 대상을 계산하지 않습니다.</div>
                <% } else { %>
                <form method="get" class="filter-row">
                    <div class="field">
                        <label>층</label>
                        <select name="floor">
                            <option value="">전체</option>
                            <% for (String opt : floorOptions) { %>
                            <option value="<%= h(opt) %>" <%= opt.equals(floorFilter) ? "selected" : "" %>><%= h(opt) %></option>
                            <% } %>
                        </select>
                    </div>
                    <div class="field">
                        <label>업종</label>
                        <select name="category">
                            <option value="">전체</option>
                            <% for (String opt : categoryOptions) { %>
                            <option value="<%= h(opt) %>" <%= opt.equals(categoryFilter) ? "selected" : "" %>><%= h(opt) %></option>
                            <% } %>
                        </select>
                    </div>
                    <div class="field">
                        <label>상태</label>
                        <select name="status">
                            <option value="">전체</option>
                            <option value="WARNING" <%= "WARNING".equals(statusFilter) ? "selected" : "" %>>경고</option>
                            <option value="CONTROL" <%= "CONTROL".equals(statusFilter) ? "selected" : "" %>>제어</option>
                        </select>
                    </div>
                    <div class="field">
                        <label>필터</label>
                        <button type="submit" class="btn btn-primary">적용</button>
                    </div>
                </form>
                <div class="chip-row">
                    <span class="summary-chip">필터 결과 <strong><%= actionRows.size() %></strong>건</span>
                    <a class="summary-chip" href="peak_management.jsp">필터 초기화</a>
                </div>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>매장</th>
                            <th>층 / 업종</th>
                            <th>한도(kW)</th>
                            <th>최근 15분 피크(kW)</th>
                            <th>사용률(%)</th>
                            <th>최근 초과 시각</th>
                            <th>최근 1시간</th>
                            <th>오늘</th>
                            <th>연속 초과</th>
                            <th>상태</th>
                            <th>작업</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (actionRows.isEmpty()) { %>
                        <tr><td colspan="11" class="muted">현재 경고 또는 제어 대상 매장이 없습니다.</td></tr>
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
                            <td><a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %>&return_floor=<%= h(floorFilter) %>&return_category=<%= h(categoryFilter) %>&return_status=<%= h(statusFilter) %>&return_section=action_targets">정책 보기</a></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
                <% } %>
            </div>

            <div class="panel-box" id="policy_status">
                <h2>정책 적용 상태</h2>
                <% if (pageData != null && !pageData.isPolicyTableReady()) { %>
                <div class="guide-item">`peak_policy_master / peak_policy_store_map` 테이블이 아직 없어 정책 상태를 표시하지 않습니다. 먼저 `docs/sql/create_epms_peak_policy_schema.sql`을 적용해 주세요.</div>
                <% } else { %>
                <div class="table-wrap">
                    <table>
                        <thead>
                        <tr>
                            <th>매장</th>
                            <th>한도(kW)</th>
                            <th>최근 15분 피크(kW)</th>
                            <th>사용률(%)</th>
                            <th>상태</th>
                            <th>Action</th>
                        </tr>
                        </thead>
                        <tbody>
                        <% if (filteredPolicyRows.isEmpty()) { %>
                        <tr><td colspan="6" class="muted">활성 peak 정책이 없습니다.</td></tr>
                        <% } %>
                        <% for (PeakPolicyStatusRow row : filteredPolicyRows) { %>
                        <tr>
                            <td><%= h(row.getStoreCode()) %> / <%= h(row.getStoreName()) %></td>
                            <td><%= row.getPeakLimitKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", row.getPeakLimitKw().doubleValue()) %></td>
                            <td><%= row.getDemandPeakKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", row.getDemandPeakKw().doubleValue()) %></td>
                            <td><%= String.format(java.util.Locale.US, "%,.1f", row.getUsagePct()) %></td>
                            <td><strong><%= h(row.getStatusLabel()) %></strong></td>
                            <td><a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %>&return_floor=<%= h(floorFilter) %>&return_category=<%= h(categoryFilter) %>&return_status=<%= h(statusFilter) %>&return_section=policy_status">정책 보기</a></td>
                        </tr>
                        <% } %>
                        </tbody>
                    </table>
                </div>
                <% } %>
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
