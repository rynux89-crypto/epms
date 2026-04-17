<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="java.time.*" %>
<%@ page import="java.util.*" %>
<%@ page import="epms.billing.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static String encB(String s) {
        try { return URLEncoder.encode(s == null ? "" : s, "UTF-8"); } catch (Exception ignore) { return ""; }
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String self = request.getRequestURI();
String msg = request.getParameter("msg");
String err = request.getParameter("err");
String cycleFilter = request.getParameter("cycle_id");
String billingMonth = request.getParameter("billing_month");
if (cycleFilter == null) cycleFilter = "";
cycleFilter = cycleFilter.trim();
if (billingMonth == null || billingMonth.trim().isEmpty()) billingMonth = YearMonth.now().toString();
billingMonth = billingMonth.trim();
LocalDate todayLocal = LocalDate.now();
BillingService billingService = new BillingService();
String postAction = request.getContextPath() + "/tenant-billing-action";

BillingManagePageData pageData = null;
try {
    pageData = billingService.loadPageData(billingMonth, cycleFilter, todayLocal);
} catch (Exception e) {
    err = e.getMessage();
}

String effectiveCycleFilter = pageData == null || pageData.getCycleFilter() == null ? cycleFilter : pageData.getCycleFilter();
BillingCycleRow selectedCycle = pageData == null ? null : pageData.getSelectedCycle();
List<BillingOption> storeOptions = pageData == null ? Collections.<BillingOption>emptyList() : pageData.getStoreOptions();
List<BillingOption> rateOptions = pageData == null ? Collections.<BillingOption>emptyList() : pageData.getRateOptions();
List<BillingRateRow> rates = pageData == null ? Collections.<BillingRateRow>emptyList() : pageData.getRates();
List<BillingContractRow> contracts = pageData == null ? Collections.<BillingContractRow>emptyList() : pageData.getContracts();
List<BillingCycleRow> cycles = pageData == null ? Collections.<BillingCycleRow>emptyList() : pageData.getCycles();
List<BillingStatementRow> statements = pageData == null ? Collections.<BillingStatementRow>emptyList() : pageData.getStatements();
int statementCnt = pageData == null ? 0 : pageData.getStatementCount();
int snapshotCnt = pageData == null ? 0 : pageData.getSnapshotCount();
String nextRateCode = pageData == null ? "RATE0001" : pageData.getNextRateCode();
boolean allowClosingRun = pageData != null && pageData.isAllowClosingRun();
boolean allowStatementRun = pageData != null && pageData.isAllowStatementRun();
String runBlockMessage = pageData == null ? null : pageData.getRunBlockMessage();
%>
<!DOCTYPE html>
<html>
<head>
    <title>매장별 월 정산 / 청구 관리</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1360px;margin:14px auto;padding:0 12px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px;margin-top:-4px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff;transform:translateY(-1px);box-shadow:0 10px 20px rgba(21,87,186,.24)}
        .stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}
        .stat-card,.panel-box{padding:12px;border:1px solid #d9dfe8;border-radius:8px;background:#fff;box-shadow:none}
        .panel-box,.stat-card,.primary-run > *, .summary-stack, .summary-stack > *{box-sizing:border-box;min-width:0}
        .panel-box{overflow:hidden}
        .stat-card span{display:block;font-size:12px;color:var(--muted);font-weight:700}
        .stat-card strong{display:block;font-size:22px;line-height:1.1;margin-top:6px;color:#18324a}
        .two-col{display:grid;grid-template-columns:1fr 1fr;gap:10px}
        .form-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}
        .compact-form{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
        .compact-form .wide{grid-column:1 / -1}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field input,.field select{width:100%;box-sizing:border-box}
        .notice{padding:12px 14px;border-radius:10px;font-weight:700}
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .table-wrap{overflow-x:auto}
        table{min-width:1060px}
        .mini-form{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
        .badge{display:inline-block;padding:3px 8px;border-radius:999px;background:#eef4ff;color:#1d4ed8;font-weight:800;font-size:11px}
        .compact-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .muted{color:var(--muted);font-size:11px}
        details.compact-box{border:1px solid #d9dfe8;border-radius:8px;background:#fff;box-shadow:none}
        details.compact-box summary{list-style:none;cursor:pointer;padding:12px;font-weight:800;display:flex;justify-content:space-between;align-items:center}
        details.compact-box summary::-webkit-details-marker{display:none}
        details.compact-box .details-body{padding:0 12px 12px}
        details.compact-box.scroll-box .details-body{max-height:360px;overflow:auto;border-top:1px solid #eef2f6}
        details.compact-box.scroll-box[open] summary{border-bottom:1px solid #eef2f6}
        details.compact-box summary::after{content:'펼치기';font-size:12px;color:var(--muted);font-weight:700}
        details.compact-box[open] summary::after{content:'접기'}
        .primary-run{display:grid;grid-template-columns:minmax(0,1.2fr) minmax(320px,.8fr);gap:10px;align-items:stretch}
        .run-card{display:grid;gap:12px}
        .run-filter{display:grid;grid-template-columns:1fr 1fr 1.1fr auto;gap:8px;align-items:end}
        .action-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
        .action-grid form,.summary-stack .stat-card{height:100%}
        .action-grid .btn{width:100%;min-height:42px}
        .summary-stack{display:grid;grid-template-columns:minmax(0,1fr);gap:8px;height:100%;width:100%}
        .summary-stack .stat-card{width:100%;max-width:100%;overflow:hidden}
        .section-title{margin:0 0 6px;color:#17324a}
        .table-toolbar{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:10px}
        table{min-width:980px}
        th{white-space:nowrap}
        h1,h2{margin-bottom:10px}
        @media (max-width:1200px){.stats,.two-col,.form-grid,.primary-run,.run-filter,.action-grid,.compact-form{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>매장별 월 정산 / 청구 관리</h1>
            <p>매장 기준 계약, 월별 청구 생성, 청구 상태 관리를 한 화면에서 처리합니다.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="tenant_store_manage.jsp">매장 관리</a>
            <a class="btn" href="tenant_meter_map_manage.jsp">매장-계측기 연결</a>
            <a class="btn" href="tenant_meter_store_tiles.jsp">계측기별 연결 매장</a>
            <a class="btn" href="epms_main.jsp">EPMS홈</a>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="notice ok"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="notice err"><%= h(err) %></div><% } %>

    <div class="stats">
        <div class="stat-card"><span>선택 정산월</span><strong><%= h(billingMonth) %></strong></div>
        <div class="stat-card"><span>계약 매장</span><strong><%= contracts.size() %></strong></div>
        <div class="stat-card"><span>선택 월 청구서</span><strong><%= statements.size() %></strong></div>
        <div class="stat-card"><span>전체 청구서</span><strong><%= statementCnt %></strong></div>
    </div>

    <div class="primary-run">
        <div class="panel-box run-card">
            <div class="compact-head">
                <div>
                    <h2 class="section-title">매장별 청구 실행</h2>
                    <p class="muted">정산월을 선택하면 내부 월 주기를 자동으로 맞추고, 매장 청구 계산을 순서대로 실행합니다.</p>
                </div>
                <% if (selectedCycle != null) { %><span class="badge">주기 #<%= h(selectedCycle.getCycleId()) %></span><% } %>
            </div>
            <form method="get" class="run-filter">
                <div class="field"><label>청구 대상 월</label><input type="month" name="billing_month" value="<%= h(billingMonth) %>" required></div>
                <div class="field"><label>월 코드</label><input type="text" value="<%= h(billingMonth) %>" readonly></div>
                <div class="field"><label>청구 기간</label><input type="text" value="<%= selectedCycle == null ? "" : h(selectedCycle.getCycleStartDate()) + " ~ " + h(selectedCycle.getCycleEndDate()) %>" readonly></div>
                <div class="field"><label>&nbsp;</label><button type="submit" class="btn btn-primary">조회</button></div>
            </form>
            <% if (runBlockMessage != null) { %>
            <div class="notice err"><%= h(runBlockMessage) %></div>
            <% } %>
            <% if (selectedCycle != null) { %>
            <div class="action-grid">
                <form method="post" action="<%= h(postAction) %>"><input type="hidden" name="action" value="generate_snapshot"><input type="hidden" name="cycle_id" value="<%= h(selectedCycle.getCycleId()) %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><input type="hidden" name="snapshot_type" value="OPENING"><button type="submit" class="btn">시작 검침 생성</button></form>
                <form method="post" action="<%= h(postAction) %>"><input type="hidden" name="action" value="generate_snapshot"><input type="hidden" name="cycle_id" value="<%= h(selectedCycle.getCycleId()) %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><input type="hidden" name="snapshot_type" value="CLOSING"><button type="submit" class="btn" <%= allowClosingRun ? "" : "disabled" %>>마감 검침 생성</button></form>
                <form method="post" action="<%= h(postAction) %>"><input type="hidden" name="action" value="generate_statement"><input type="hidden" name="cycle_id" value="<%= h(selectedCycle.getCycleId()) %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><button type="submit" class="btn btn-primary" <%= allowStatementRun ? "" : "disabled" %>>매장 청구 생성</button></form>
            </div>
            <% } %>
        </div>
        <div class="panel-box">
            <h2 class="section-title">선택 월 현황</h2>
            <div class="summary-stack">
                <div class="stat-card"><span>선택 월 청구서</span><strong><%= statements.size() %></strong></div>
                <div class="stat-card"><span>계약 매장</span><strong><%= contracts.size() %></strong></div>
                <div class="stat-card"><span>검침 준비 데이터</span><strong><%= snapshotCnt %></strong></div>
            </div>
        </div>
    </div>

    <details class="compact-box scroll-box">
        <summary>매장 청구 기준 설정</summary>
        <div class="details-body">
            <div class="two-col">
                <div class="panel-box" style="box-shadow:none;border-style:dashed;">
                    <h2 class="section-title">요금제 등록</h2>
                    <form method="post" action="<%= h(postAction) %>" class="compact-form">
                        <input type="hidden" name="action" value="rate_add"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><input type="hidden" name="cycle_id" value="<%= h(effectiveCycleFilter) %>">
                        <div class="field"><label>요금제 코드</label><input type="text" name="rate_code" value="<%= h(nextRateCode) %>" readonly></div>
                        <div class="field"><label>요금제명</label><input type="text" name="rate_name" required></div>
                        <div class="field"><label>적용 시작일</label><input type="date" name="effective_from" required></div>
                        <div class="field"><label>kWh 단가</label><input type="text" name="unit_price_per_kwh" value="0"></div>
                        <div class="field"><label>기본요금</label><input type="text" name="basic_charge_amount" value="0"></div>
                        <div class="field"><label>수요요금 단가</label><input type="text" name="demand_unit_price" value="0"></div>
                        <div class="field wide"><button type="submit" class="btn btn-primary">요금제 등록</button></div>
                    </form>
                </div>
                <div class="panel-box" style="box-shadow:none;border-style:dashed;">
                    <h2 class="section-title">계약 등록</h2>
                    <form method="post" action="<%= h(postAction) %>" class="compact-form">
                        <input type="hidden" name="action" value="contract_add"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><input type="hidden" name="cycle_id" value="<%= h(effectiveCycleFilter) %>">
                        <div class="field"><label>매장</label><select name="store_id" required><option value="">선택</option><% for (BillingOption opt : storeOptions) { %><option value="<%= h(opt.getValue()) %>"><%= h(opt.getLabel()) %></option><% } %></select></div>
                        <div class="field"><label>요금제</label><select name="rate_id" required><option value="">선택</option><% for (BillingOption opt : rateOptions) { %><option value="<%= h(opt.getValue()) %>"><%= h(opt.getLabel()) %></option><% } %></select></div>
                        <div class="field"><label>계약 시작일</label><input type="date" name="contract_start_date" required></div>
                        <div class="field"><label>계약전력(kW)</label><input type="text" name="contracted_demand_kw"></div>
                        <div class="field wide"><button type="submit" class="btn btn-primary">계약 등록</button></div>
                    </form>
                </div>
            </div>
        </div>
    </details>

    <details class="compact-box scroll-box">
        <summary>청구 기준 데이터 목록</summary>
        <div class="details-body">
            <div class="two-col">
                <div class="panel-box" style="box-shadow:none;border-style:dashed;">
                    <h2 class="section-title">요금제 목록</h2>
                    <div class="table-wrap"><table><thead><tr><th>ID</th><th>코드</th><th>이름</th><th>적용일</th><th>요금 정보</th><th>삭제</th></tr></thead><tbody>
                    <% if (rates.isEmpty()) { %><tr><td colspan="6">등록된 요금제가 없습니다.</td></tr><% } %>
                    <% for (BillingRateRow row : rates) { %>
                    <tr>
                        <td><%= row.getRateId() %></td><td><%= h(row.getRateCode()) %></td><td><%= h(row.getRateName()) %></td><td><%= h(row.getEffectiveFrom()) %></td>
                        <td>kWh <%= h(row.getUnitPricePerKwh()) %><br>기본 <%= h(row.getBasicChargeAmount()) %><br>수요 <%= h(row.getDemandUnitPrice()) %></td>
                        <td><form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('요금제를 삭제하시겠습니까?');"><input type="hidden" name="action" value="rate_delete"><input type="hidden" name="rate_id" value="<%= row.getRateId() %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><input type="hidden" name="cycle_id" value="<%= h(effectiveCycleFilter) %>"><button type="submit" class="btn">삭제</button></form></td>
                    </tr>
                    <% } %>
                    </tbody></table></div>
                </div>
                <div class="panel-box" style="box-shadow:none;border-style:dashed;">
                    <h2 class="section-title">계약 목록</h2>
                    <div class="table-wrap"><table><thead><tr><th>ID</th><th>매장</th><th>요금제</th><th>시작일</th><th>계약전력</th><th>삭제</th></tr></thead><tbody>
                    <% if (contracts.isEmpty()) { %><tr><td colspan="6">등록된 계약이 없습니다.</td></tr><% } %>
                    <% for (BillingContractRow row : contracts) { %>
                    <tr>
                        <td><%= row.getContractId() %></td><td><%= h(row.getStoreCode()) %><br><small><%= h(row.getStoreName()) %></small></td><td><%= h(row.getRateCode()) %><br><small><%= h(row.getRateName()) %></small></td><td><%= h(row.getContractStartDate()) %></td><td><%= h(row.getContractedDemandKw()) %></td>
                        <td><form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('계약을 삭제하시겠습니까?');"><input type="hidden" name="action" value="contract_delete"><input type="hidden" name="contract_id" value="<%= row.getContractId() %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><input type="hidden" name="cycle_id" value="<%= h(effectiveCycleFilter) %>"><button type="submit" class="btn">삭제</button></form></td>
                    </tr>
                    <% } %>
                    </tbody></table></div>
                </div>
            </div>
        </div>
    </details>

    <details class="compact-box scroll-box">
        <summary>월별 실행 이력</summary>
        <div class="details-body">
            <div class="panel-box" style="box-shadow:none;border-style:dashed;">
                <h2 class="section-title">월별 실행 이력</h2>
                <div class="table-wrap"><table><thead><tr><th>정산 코드</th><th>기간</th><th>상태</th><th>삭제</th></tr></thead><tbody>
                <% if (cycles.isEmpty()) { %><tr><td colspan="4">등록된 정산 주기가 없습니다.</td></tr><% } %>
                <% for (BillingCycleRow row : cycles) { %>
                <tr>
                    <td><a href="tenant_billing_manage.jsp?billing_month=<%= h(row.getCycleCode()) %>&cycle_id=<%= h(row.getCycleId()) %>"><%= h(row.getCycleCode()) %></a></td>
                    <td><%= h(row.getCycleStartDate()) %> ~ <%= h(row.getCycleEndDate()) %></td><td><%= h(row.getStatus()) %></td>
                    <td><form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('정산 주기를 삭제하시겠습니까?');"><input type="hidden" name="action" value="cycle_delete"><input type="hidden" name="cycle_id" value="<%= row.getCycleId() %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><button type="submit" class="btn">삭제</button></form></td>
                </tr>
                <% } %>
                </tbody></table></div>
            </div>
        </div>
    </details>

    <div class="panel-box">
        <div class="table-toolbar">
            <h2 class="section-title">매장별 청구 결과 <% if (selectedCycle != null) { %><span class="badge"><%= h(selectedCycle.getCycleCode()) %></span><% } %></h2>
            <span class="muted">선택 월 기준 매장별 청구 결과</span>
        </div>
        <div class="table-wrap"><table><thead><tr><th>매장</th><th>사용량</th><th>최대수요</th><th>총 청구금액</th><th>상태</th><th>처리</th></tr></thead><tbody>
        <% if (statements.isEmpty()) { %><tr><td colspan="6">선택한 월의 청구서가 없습니다.</td></tr><% } %>
        <% for (BillingStatementRow row : statements) { %>
        <tr>
            <td><%= h(row.getStoreCode()) %><br><small><%= h(row.getStoreName()) %></small></td><td><%= h(row.getUsageKwh()) %> kWh</td><td><%= h(row.getPeakDemandKw()) %> kW</td><td><strong><%= h(row.getTotalAmount()) %> KRW</strong></td><td><%= h(row.getStatementStatus()) %><br><small><%= h(row.getIssuedAt()) %></small></td>
            <td><form method="post" action="<%= h(postAction) %>" class="mini-form"><input type="hidden" name="action" value="statement_status"><input type="hidden" name="statement_id" value="<%= row.getStatementId() %>"><input type="hidden" name="cycle_id" value="<%= h(effectiveCycleFilter) %>"><input type="hidden" name="billing_month" value="<%= h(billingMonth) %>"><select name="statement_status"><option value="DRAFT" <%= "DRAFT".equals(row.getStatementStatus()) ? "selected" : "" %>>DRAFT</option><option value="ISSUED" <%= "ISSUED".equals(row.getStatementStatus()) ? "selected" : "" %>>ISSUED</option><option value="CONFIRMED" <%= "CONFIRMED".equals(row.getStatementStatus()) ? "selected" : "" %>>CONFIRMED</option></select><button type="submit" class="btn btn-primary">상태 변경</button></form></td>
        </tr>
        <% } %>
        </tbody></table></div>
    </div>
</div>
</body>
</html>
