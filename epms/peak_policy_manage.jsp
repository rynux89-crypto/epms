<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page import="epms.peak.*" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%
String msg = request.getParameter("msg");
String err = request.getParameter("err");
String returnFloor = request.getParameter("return_floor");
String returnCategory = request.getParameter("return_category");
String returnStatus = request.getParameter("return_status");
String returnSection = request.getParameter("return_section");
if (returnFloor == null) returnFloor = "";
if (returnCategory == null) returnCategory = "";
if (returnStatus == null) returnStatus = "";
if (returnSection == null) returnSection = "";
returnFloor = returnFloor.trim();
returnCategory = returnCategory.trim();
returnStatus = returnStatus.trim();
returnSection = returnSection.trim();

Long editId = null;
try {
    String editIdQ = request.getParameter("edit_id");
    if (editIdQ != null && !editIdQ.trim().isEmpty()) editId = Long.valueOf(editIdQ.trim());
} catch (Exception ignore) {}

PeakPolicyService peakPolicyService = new PeakPolicyService();
PeakPolicyPageData pageData = null;
try {
    pageData = peakPolicyService.loadPageData(editId);
} catch (Exception e) {
    err = e.getMessage();
}

String postAction = request.getContextPath() + "/peak-policy-action";
List<PeakStoreOption> storeOptions = pageData == null ? Collections.<PeakStoreOption>emptyList() : pageData.getStoreOptions();
List<PeakPolicyRow> rows = pageData == null ? Collections.<PeakPolicyRow>emptyList() : pageData.getRows();
PeakPolicyRow selectedRow = pageData == null ? null : pageData.getSelectedRow();

String encodedReturnFloor = returnFloor.isEmpty() ? "" : URLEncoder.encode(returnFloor, StandardCharsets.UTF_8.name());
String encodedReturnCategory = returnCategory.isEmpty() ? "" : URLEncoder.encode(returnCategory, StandardCharsets.UTF_8.name());
String encodedReturnStatus = returnStatus.isEmpty() ? "" : URLEncoder.encode(returnStatus, StandardCharsets.UTF_8.name());
String encodedReturnSection = returnSection.isEmpty() ? "" : URLEncoder.encode(returnSection, StandardCharsets.UTF_8.name());

StringBuilder peakDashboardHrefBuilder = new StringBuilder("peak_management.jsp");
boolean peakDashboardHasQuery = false;
if (!encodedReturnFloor.isEmpty()) {
    peakDashboardHrefBuilder.append(peakDashboardHasQuery ? '&' : '?').append("floor=").append(encodedReturnFloor);
    peakDashboardHasQuery = true;
}
if (!encodedReturnCategory.isEmpty()) {
    peakDashboardHrefBuilder.append(peakDashboardHasQuery ? '&' : '?').append("category=").append(encodedReturnCategory);
    peakDashboardHasQuery = true;
}
if (!encodedReturnStatus.isEmpty()) {
    peakDashboardHrefBuilder.append(peakDashboardHasQuery ? '&' : '?').append("status=").append(encodedReturnStatus);
}
String peakDashboardHref = peakDashboardHrefBuilder.toString();
if (!encodedReturnSection.isEmpty()) {
    peakDashboardHref += "#" + encodedReturnSection;
}

String returnQuery = ""
        + (encodedReturnFloor.isEmpty() ? "" : "&return_floor=" + encodedReturnFloor)
        + (encodedReturnCategory.isEmpty() ? "" : "&return_category=" + encodedReturnCategory)
        + (encodedReturnStatus.isEmpty() ? "" : "&return_status=" + encodedReturnStatus)
        + (encodedReturnSection.isEmpty() ? "" : "&return_section=" + encodedReturnSection);
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Peak Policy Management</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1500px;margin:14px auto;padding:0 12px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff}
        .panel-box{padding:12px;border:1px solid #d9dfe8;border-radius:8px;background:#fff;box-shadow:none}
        .content-grid{display:grid;grid-template-columns:minmax(0,1fr) 430px;gap:12px;align-items:start}
        .context-bar{display:flex;flex-wrap:wrap;gap:8px}
        .context-chip{display:inline-flex;align-items:center;padding:6px 10px;border-radius:999px;background:#eff6ff;color:#1d4ed8;border:1px solid #bfdbfe;font-size:12px;font-weight:700}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .form-grid,.edit-form{display:grid;gap:8px;grid-template-columns:repeat(2,minmax(0,1fr))}
        .field input,.field select,.field textarea{width:100%;min-width:0}
        .field textarea{min-height:72px;resize:vertical;grid-column:1 / -1}
        .table-wrap{overflow-x:auto}
        table{min-width:1080px}
        .notice{padding:12px 14px;border-radius:10px;font-weight:700;transition:opacity .35s ease,transform .35s ease}
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .notice-dismiss{opacity:0;transform:translateY(-4px)}
        .edit-panel{position:sticky;top:16px}
        .actions,.table-actions,.edit-form-actions{display:flex;gap:8px;align-items:center}
        .table-actions{justify-content:flex-end;flex-wrap:wrap}
        .edit-form-actions{justify-content:flex-end;margin-top:8px}
        .empty-note{padding:18px 14px;border:1px dashed #d9dfe8;border-radius:8px;color:var(--muted);background:#fafcff}
        @media (max-width:1100px){.content-grid,.form-grid,.edit-form{grid-template-columns:1fr}.edit-panel{position:static}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>Peak Policy Management</h1>
            <p>매장별 피크 한도, 경고 기준, 제어 기준, 우선순위와 적용 기간을 관리합니다.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="<%= h(peakDashboardHref) %>">Peak 대시보드</a>
            <a class="btn" href="tenant_meter_store_tiles.jsp">원격검침 운영</a>
            <a class="btn" href="epms_main.jsp">EPMS 홈</a>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="notice ok"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="notice err"><%= h(err) %></div><% } %>

    <% if (!returnFloor.isEmpty() || !returnCategory.isEmpty() || !returnStatus.isEmpty()) { %>
    <div class="panel-box">
        <div class="context-bar">
            <% if (!returnFloor.isEmpty()) { %><span class="context-chip">층: <%= h(returnFloor) %></span><% } %>
            <% if (!returnCategory.isEmpty()) { %><span class="context-chip">업종: <%= h(returnCategory) %></span><% } %>
            <% if (!returnStatus.isEmpty()) { %><span class="context-chip">상태: <%= h(returnStatus) %></span><% } %>
            <a class="btn" href="<%= h(peakDashboardHref) %>">이 필터로 대시보드 복귀</a>
        </div>
    </div>
    <% } %>

    <div class="panel-box">
        <h2>정책 등록</h2>
        <form method="post" action="<%= h(postAction) %>" class="form-grid">
            <input type="hidden" name="action" value="add">
            <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
            <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
            <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
            <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
            <div class="field">
                <label>매장</label>
                <select name="store_id" required>
                    <option value="">선택</option>
                    <% for (PeakStoreOption opt : storeOptions) { %>
                    <option value="<%= h(opt.getValue()) %>"><%= h(opt.getLabel()) %></option>
                    <% } %>
                </select>
            </div>
            <div class="field"><label>피크 한도 (kW)</label><input type="text" name="peak_limit_kw" value="0"></div>
            <div class="field"><label>경고 기준 (%)</label><input type="text" name="warning_threshold_pct" value="80"></div>
            <div class="field"><label>제어 기준 (%)</label><input type="text" name="control_threshold_pct" value="95"></div>
            <div class="field"><label>우선순위 (1-9)</label><input type="text" name="priority_level" value="5"></div>
            <div class="field">
                <label>자동 제어 사용</label>
                <select name="control_enabled">
                    <option value="true">사용</option>
                    <option value="false">미사용</option>
                </select>
            </div>
            <div class="field"><label>적용 시작일</label><input type="date" name="effective_from" value="<%= new java.sql.Date(System.currentTimeMillis()) %>"></div>
            <div class="field"><label>적용 종료일</label><input type="date" name="effective_to"></div>
            <div class="field" style="grid-column:1 / -1;"><label>비고</label><textarea name="notes"></textarea></div>
            <div class="actions" style="grid-column:1 / -1;">
                <button type="submit" class="btn btn-primary">정책 등록</button>
                <button type="submit" name="redirect_to_dashboard" value="true" class="btn">등록 후 대시보드 복귀</button>
            </div>
        </form>
    </div>

    <div class="content-grid">
        <div class="panel-box">
            <h2>정책 목록</h2>
            <div class="table-wrap">
                <table>
                    <thead>
                    <tr>
                        <th>ID</th>
                        <th>매장</th>
                        <th>피크 한도 (kW)</th>
                        <th>경고 (%)</th>
                        <th>제어 (%)</th>
                        <th>우선순위</th>
                        <th>자동 제어</th>
                        <th>적용 기간</th>
                        <th>작업</th>
                    </tr>
                    </thead>
                    <tbody>
                    <% if (rows.isEmpty()) { %><tr><td colspan="9" class="empty-note">등록된 peak 정책이 없습니다.</td></tr><% } %>
                    <% for (PeakPolicyRow row : rows) { %>
                    <tr>
                        <td><%= row.getPolicyId() %></td>
                        <td><%= h(row.getStoreCode()) %> / <%= h(row.getStoreName()) %></td>
                        <td><%= h(row.getPeakLimitKw()) %></td>
                        <td><%= h(row.getWarningThresholdPct()) %></td>
                        <td><%= h(row.getControlThresholdPct()) %></td>
                        <td><%= h(row.getPriorityLevel()) %></td>
                        <td><%= row.isControlEnabled() ? "사용" : "미사용" %></td>
                        <td><%= h(row.getEffectiveFrom()) %> ~ <%= h(row.getEffectiveTo()) %></td>
                        <td>
                            <div class="table-actions">
                                <a class="btn btn-primary" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %><%= h(returnQuery) %>">수정</a>
                                <form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('이 peak 정책을 삭제하시겠습니까?');">
                                    <input type="hidden" name="action" value="delete">
                                    <input type="hidden" name="policy_id" value="<%= row.getPolicyId() %>">
                                    <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                                    <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                                    <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                                    <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                                    <button type="submit" class="btn">삭제</button>
                                </form>
                            </div>
                        </td>
                    </tr>
                    <% } %>
                    </tbody>
                </table>
            </div>
        </div>
        <div class="panel-box edit-panel">
            <h2>정책 수정</h2>
            <% if (selectedRow == null) { %>
            <div class="empty-note">목록에서 수정할 정책을 선택하면 여기서 상세 기준을 변경할 수 있습니다.</div>
            <% } else { %>
            <form method="post" action="<%= h(postAction) %>" class="edit-form" id="edit-peak-policy-panel">
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="policy_id" value="<%= selectedRow.getPolicyId() %>">
                <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                <div class="field">
                    <label>매장</label>
                    <select name="store_id">
                        <% for (PeakStoreOption opt : storeOptions) { %>
                        <option value="<%= h(opt.getValue()) %>" <%= String.valueOf(selectedRow.getStoreId()).equals(opt.getValue()) ? "selected" : "" %>><%= h(opt.getLabel()) %></option>
                        <% } %>
                    </select>
                </div>
                <div class="field"><label>피크 한도 (kW)</label><input type="text" name="peak_limit_kw" value="<%= h(selectedRow.getPeakLimitKw()) %>"></div>
                <div class="field"><label>경고 기준 (%)</label><input type="text" name="warning_threshold_pct" value="<%= h(selectedRow.getWarningThresholdPct()) %>"></div>
                <div class="field"><label>제어 기준 (%)</label><input type="text" name="control_threshold_pct" value="<%= h(selectedRow.getControlThresholdPct()) %>"></div>
                <div class="field"><label>우선순위 (1-9)</label><input type="text" name="priority_level" value="<%= h(selectedRow.getPriorityLevel()) %>"></div>
                <div class="field">
                    <label>자동 제어 사용</label>
                    <select name="control_enabled">
                        <option value="true" <%= selectedRow.isControlEnabled() ? "selected" : "" %>>사용</option>
                        <option value="false" <%= !selectedRow.isControlEnabled() ? "selected" : "" %>>미사용</option>
                    </select>
                </div>
                <div class="field"><label>적용 시작일</label><input type="date" name="effective_from" value="<%= h(selectedRow.getEffectiveFrom()) %>"></div>
                <div class="field"><label>적용 종료일</label><input type="date" name="effective_to" value="<%= h(selectedRow.getEffectiveTo()) %>"></div>
                <div class="field" style="grid-column:1 / -1;"><label>비고</label><textarea name="notes"><%= h(selectedRow.getNotes()) %></textarea></div>
            </form>
            <div class="edit-form-actions">
                <button type="submit" form="edit-peak-policy-panel" class="btn btn-primary">저장</button>
                <button type="submit" form="edit-peak-policy-panel" name="redirect_to_dashboard" value="true" class="btn">저장 후 대시보드 복귀</button>
                <a class="btn" href="<%= h(peakDashboardHref) %>">대시보드로 돌아가기</a>
                <form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('이 peak 정책을 삭제하시겠습니까?');">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="policy_id" value="<%= selectedRow.getPolicyId() %>">
                    <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                    <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                    <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                    <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                    <button type="submit" class="btn">삭제</button>
                </form>
            </div>
            <% } %>
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
