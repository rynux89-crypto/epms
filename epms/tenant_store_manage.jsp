<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="epms.tenant.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static java.sql.Date parseDateNullable(String s) {
        if (s == null) return null;
        String v = s.trim();
        if (v.isEmpty()) return null;
        try { return java.sql.Date.valueOf(v); } catch (Exception ignore) { return null; }
    }
    private static String enc(String s) {
        try { return URLEncoder.encode(s == null ? "" : s, "UTF-8"); } catch (Exception ignore) { return ""; }
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String msg = request.getParameter("msg");
String err = request.getParameter("err");
String searchQ = request.getParameter("q");
String statusQ = request.getParameter("status");
String editIdQ = request.getParameter("edit_id");
if (searchQ == null) searchQ = "";
if (statusQ == null) statusQ = "";
searchQ = searchQ.trim();
statusQ = statusQ.trim();
Integer editId = parsePositiveInt(editIdQ);
String postAction = request.getContextPath() + "/tenant-store-action";

TenantStoreService storeService = new TenantStoreService();

TenantStorePageData pageData = null;
try {
    pageData = storeService.loadPageData(searchQ, statusQ, editId);
} catch (Exception e) {
    err = e.getMessage();
}

int totalCnt = pageData == null ? 0 : pageData.getTotalCount();
int activeCnt = pageData == null ? 0 : pageData.getActiveCount();
int closedCnt = pageData == null ? 0 : pageData.getClosedCount();
List<TenantStoreRow> rows = pageData == null ? Collections.<TenantStoreRow>emptyList() : pageData.getRows();
TenantStoreRow selectedRow = pageData == null ? null : pageData.getSelectedRow();
String generatedStoreCode = pageData == null ? "STORE0001" : pageData.getGeneratedStoreCode();
%>
<!DOCTYPE html>
<html>
<head>
    <title>매장 관리</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1360px;margin:14px auto;padding:0 12px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px;margin-top:-4px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff;transform:translateY(-1px);box-shadow:0 10px 20px rgba(21,87,186,.24)}
        .stats{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
        .stat-card,.panel-box{padding:12px;border:1px solid #d9dfe8;border-radius:6px;background:#fff;box-shadow:none}
        .stat-card strong{display:block;font-size:20px;margin-top:4px}
        .filter-row,.form-grid,.edit-form{display:grid;gap:8px}
        .filter-row{grid-template-columns:2fr 1fr auto;align-items:end}
        .form-grid{grid-template-columns:repeat(4,minmax(0,1fr))}
        .content-grid{display:grid;grid-template-columns:minmax(0,1fr) 400px;gap:12px;align-items:start}
        .edit-panel{position:sticky;top:16px}
        .edit-form{grid-template-columns:repeat(2,minmax(0,1fr))}
        .edit-form input,.edit-form select,.edit-form textarea{width:100%;min-width:0}
        .edit-form textarea{grid-column:1 / -1}
        .edit-form-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:8px}
        .edit-form-actions form{margin:0}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        textarea{min-height:68px;resize:vertical}
        .notice{padding:12px 14px;border-radius:10px;font-weight:700}
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .table-wrap{overflow-x:auto}
        table{min-width:1080px}
        .store-list-table th,.store-list-table td{word-break:keep-all;vertical-align:middle}
        .store-list-table th:nth-child(1),.store-list-table td:nth-child(1){width:56px}
        .store-list-table th:nth-child(2),.store-list-table td:nth-child(2){width:110px}
        .store-list-table th:nth-child(3),.store-list-table td:nth-child(3){width:180px}
        .store-list-table th:nth-child(4),.store-list-table td:nth-child(4){width:170px}
        .store-list-table th:nth-child(5),.store-list-table td:nth-child(5){width:100px}
        .store-list-table th:nth-child(6),.store-list-table td:nth-child(6){width:130px}
        .store-list-table th:nth-child(7),.store-list-table td:nth-child(7){width:88px}
        .store-list-table th:nth-child(8),.store-list-table td:nth-child(8){width:150px}
        .store-list-table th:nth-child(9),.store-list-table td:nth-child(9){width:132px}
        .status-pill{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px;font-weight:800}
        .status-active{background:#ecfdf3;color:#166534;border:1px solid #b7ebc6}
        .status-closed{background:#fff4e5;color:#9a6700;border:1px solid #f5d28a}
        .actions,.table-actions{display:flex;gap:6px;align-items:center}
        .table-actions{justify-content:flex-end;flex-wrap:wrap}
        .muted{color:var(--muted);font-size:11px}
        .empty-note{padding:18px 14px;border:1px dashed #d9dfe8;border-radius:8px;color:var(--muted);background:#fafcff}
        h1,h2{margin-bottom:10px}
        @media (max-width:1100px){.stats,.form-grid,.filter-row,.content-grid,.edit-form{grid-template-columns:1fr}.edit-panel{position:static}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head"><div><h1>매장 관리</h1><p>백화점 입점 매장을 등록하고 정산 대상 상태를 관리합니다.</p></div><div class="top-links"><a class="btn" href="download_tenant_store_template.jsp">템플릿 다운로드</a><a class="btn" href="tenant_store_excel_import.jsp">엑셀 일괄 등록</a><a class="btn" href="tenant_meter_map_manage.jsp">매장-계량기 연결</a><a class="btn" href="tenant_billing_manage.jsp">월 정산</a><a class="btn" href="epms_main.jsp">EPMS 홈</a></div></div>
    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="notice ok"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="notice err"><%= h(err) %></div><% } %>
    <div class="stats"><div class="stat-card"><span>전체 매장</span><strong><%= totalCnt %></strong></div><div class="stat-card"><span>운영 중 매장</span><strong><%= activeCnt %></strong></div><div class="stat-card"><span>종료 매장</span><strong><%= closedCnt %></strong></div></div>
    <div class="panel-box">
        <h2>검색</h2>
        <form method="get" class="filter-row">
            <div class="field"><label>검색어</label><input type="text" name="q" value="<%= h(searchQ) %>" placeholder="매장 코드, 매장명, 층, 호실, 구역"></div>
            <div class="field"><label>상태</label><select name="status"><option value="" <%= statusQ.isEmpty() ? "selected" : "" %>>전체</option><option value="ACTIVE" <%= "ACTIVE".equals(statusQ) ? "selected" : "" %>>운영중</option><option value="CLOSED" <%= "CLOSED".equals(statusQ) ? "selected" : "" %>>종료</option></select></div>
            <div class="actions"><button type="submit" class="btn btn-primary">검색</button></div>
        </form>
    </div>
    <div class="panel-box">
        <h2>매장 등록</h2>
        <form method="post" action="<%= h(postAction) %>" class="form-grid">
            <input type="hidden" name="action" value="add">
            <input type="hidden" name="q" value="<%= h(searchQ) %>">
            <input type="hidden" name="status" value="<%= h(statusQ) %>">
            <div class="field"><label>매장 코드</label><input type="text" name="store_code" value="<%= h(generatedStoreCode) %>" readonly></div>
            <div class="field"><label>매장명</label><input type="text" name="store_name" required></div>
            <div class="field"><label>사업자번호</label><input type="text" name="business_number"></div>
            <div class="field"><label>상태</label><select name="store_status"><option value="ACTIVE">운영중</option><option value="CLOSED">종료</option></select></div>
            <div class="field"><label>층</label><input type="text" name="floor_name"></div>
            <div class="field"><label>호실</label><input type="text" name="room_name"></div>
            <div class="field"><label>구역</label><input type="text" name="zone_name"></div>
            <div class="field"><label>업종</label><input type="text" name="category_name"></div>
            <div class="field"><label>담당자</label><input type="text" name="contact_name"></div>
            <div class="field"><label>연락처</label><input type="text" name="contact_phone"></div>
            <div class="field"><label>오픈일</label><input type="date" name="opened_on"></div>
            <div class="field"><label>종료일</label><input type="date" name="closed_on"></div>
            <div class="field" style="grid-column:1 / -1;"><label>비고</label><textarea name="notes"></textarea></div>
            <div class="actions" style="grid-column:1 / -1;"><button type="submit" class="btn btn-primary">매장 등록</button></div>
        </form>
    </div>
    <div class="content-grid">
        <div class="panel-box">
            <h2>매장 목록</h2>
            <div class="table-wrap">
                <table class="store-list-table">
                    <thead><tr><th>ID</th><th>코드</th><th>매장명</th><th>층 / 호실 / 구역</th><th>업종</th><th>연락처</th><th>상태</th><th>영업기간</th><th>작업</th></tr></thead>
                    <tbody>
                    <% if (rows.isEmpty()) { %><tr><td colspan="9" class="muted">등록된 매장이 없습니다.</td></tr><% } %>
                    <% for (TenantStoreRow row : rows) { %>
                    <tr>
                        <td><%= row.getStoreId() %></td>
                        <td><strong><%= h(row.getStoreCode()) %></strong></td>
                        <td><%= h(row.getStoreName()) %><br><span class="muted"><%= h(row.getBusinessNumber()) %></span></td>
                        <td><%= h(row.getFloorName()) %> / <%= h(row.getRoomName()) %> / <%= h(row.getZoneName()) %></td>
                        <td><%= h(row.getCategoryName()) %></td>
                        <td><%= h(row.getContactName()) %><br><span class="muted"><%= h(row.getContactPhone()) %></span></td>
                        <td><span class="status-pill <%= "ACTIVE".equals(row.getStatus()) ? "status-active" : "status-closed" %>"><%= "ACTIVE".equals(row.getStatus()) ? "운영중" : "종료" %></span></td>
                        <td><%= h(row.getOpenedOn()) %> ~ <%= h(row.getClosedOn()) %></td>
                        <td><div class="table-actions"><a class="btn btn-primary" href="tenant_store_manage.jsp?q=<%= enc(searchQ) %>&status=<%= enc(statusQ) %>&edit_id=<%= row.getStoreId() %>">수정</a><form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('이 매장을 삭제하시겠습니까?');"><input type="hidden" name="action" value="delete"><input type="hidden" name="store_id" value="<%= row.getStoreId() %>"><input type="hidden" name="q" value="<%= h(searchQ) %>"><input type="hidden" name="status" value="<%= h(statusQ) %>"><button type="submit" class="btn">삭제</button></form></div></td>
                    </tr>
                    <% } %>
                    </tbody>
                </table>
            </div>
        </div>
        <div class="panel-box edit-panel">
            <h2>매장 수정</h2>
            <% if (selectedRow == null) { %>
            <div class="empty-note">목록에서 수정할 매장을 선택하면 여기서 상세 정보를 편집할 수 있습니다.</div>
            <% } else { %>
            <form method="post" action="<%= h(postAction) %>" class="edit-form" id="edit-store-panel">
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="store_id" value="<%= selectedRow.getStoreId() %>">
                <input type="hidden" name="q" value="<%= h(searchQ) %>">
                <input type="hidden" name="status" value="<%= h(statusQ) %>">
                <div class="field"><label>매장 코드</label><input type="text" name="store_code" value="<%= h(selectedRow.getStoreCode()) %>" readonly></div>
                <div class="field"><label>매장명</label><input type="text" name="store_name" value="<%= h(selectedRow.getStoreName()) %>" required></div>
                <div class="field"><label>층</label><input type="text" name="floor_name" value="<%= h(selectedRow.getFloorName()) %>"></div>
                <div class="field"><label>호실</label><input type="text" name="room_name" value="<%= h(selectedRow.getRoomName()) %>"></div>
                <div class="field"><label>구역</label><input type="text" name="zone_name" value="<%= h(selectedRow.getZoneName()) %>"></div>
                <div class="field"><label>상태</label><select name="store_status"><option value="ACTIVE" <%= "ACTIVE".equals(selectedRow.getStatus()) ? "selected" : "" %>>운영중</option><option value="CLOSED" <%= "CLOSED".equals(selectedRow.getStatus()) ? "selected" : "" %>>종료</option></select></div>
                <div class="field"><label>사업자번호</label><input type="text" name="business_number" value="<%= h(selectedRow.getBusinessNumber()) %>"></div>
                <div class="field"><label>업종</label><input type="text" name="category_name" value="<%= h(selectedRow.getCategoryName()) %>"></div>
                <div class="field"><label>담당자</label><input type="text" name="contact_name" value="<%= h(selectedRow.getContactName()) %>"></div>
                <div class="field"><label>연락처</label><input type="text" name="contact_phone" value="<%= h(selectedRow.getContactPhone()) %>"></div>
                <div class="field"><label>오픈일</label><input type="date" name="opened_on" value="<%= h(selectedRow.getOpenedOn()) %>"></div>
                <div class="field"><label>종료일</label><input type="date" name="closed_on" value="<%= h(selectedRow.getClosedOn()) %>"></div>
                <div class="field" style="grid-column:1 / -1;"><label>비고</label><textarea name="notes"><%= h(selectedRow.getNotes()) %></textarea></div>
            </form>
            <div class="edit-form-actions"><button type="submit" form="edit-store-panel" class="btn btn-primary">저장</button><form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('이 매장을 삭제하시겠습니까?');"><input type="hidden" name="action" value="delete"><input type="hidden" name="store_id" value="<%= selectedRow.getStoreId() %>"><input type="hidden" name="q" value="<%= h(searchQ) %>"><input type="hidden" name="status" value="<%= h(statusQ) %>"><button type="submit" class="btn">삭제</button></form></div>
            <% } %>
        </div>
    </div>
</div>
</body>
</html>
