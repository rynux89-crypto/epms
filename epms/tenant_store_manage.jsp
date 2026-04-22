<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="epms.tenant.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
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
    <meta charset="UTF-8">
    <title>&#47588;&#51109; &#44288;&#47532;</title>
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
        .editor-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;align-items:start}
        .edit-form{grid-template-columns:repeat(4,minmax(0,1fr))}
        .edit-form input,.edit-form select,.edit-form textarea,.form-grid input,.form-grid select,.form-grid textarea{width:100%;min-width:0}
        .edit-form textarea,.form-grid textarea{grid-column:1 / -1}
        .edit-form-actions{display:flex;justify-content:flex-start;gap:8px;margin-top:8px;flex-wrap:nowrap;align-items:center}
        .edit-form-actions form{margin:0}
        .edit-form-actions .btn{display:inline-flex;align-items:center;justify-content:center;min-width:72px}
        .edit-form-actions a.btn,
        .edit-form-actions a.btn:visited{
            color:#fff !important;
            text-decoration:none;
        }
        .edit-form-actions a.btn.btn-primary{
            display:inline-flex;
            align-items:center;
            justify-content:center;
            min-width:72px;
            height:34px;
            padding:0 14px;
            border-radius:999px !important;
            background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%) !important;
            border:1px solid transparent !important;
            box-shadow:0 6px 16px rgba(31,111,235,.22);
        }
        .edit-form-actions a.btn.btn-primary:hover{
            background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%) !important;
            color:#fff !important;
        }
        .panel-head{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:10px}
        .panel-head h2{margin:0}
        .hint-note{font-size:12px;color:var(--muted)}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        textarea{min-height:64px;resize:vertical}
        .field-wide{grid-column:1 / -1}
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
        .store-list-table th:nth-child(9),.store-list-table td:nth-child(9){width:128px;text-align:center}
        .status-pill{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px;font-weight:800}
        .status-active{background:#ecfdf3;color:#166534;border:1px solid #b7ebc6}
        .status-closed{background:#fff4e5;color:#9a6700;border:1px solid #f5d28a}
        .actions,.table-actions{display:flex;gap:3px;align-items:center}
        .table-actions{justify-content:center;flex-wrap:nowrap;white-space:nowrap;width:100%}
        .table-actions form{margin:0}
        .action-chip{
            min-width:44px;
            display:inline-flex;
            align-items:center;
            justify-content:center;
            height:24px;
            padding:0 8px;
            border:0 !important;
            outline:none;
            appearance:none;
            -webkit-appearance:none;
            box-sizing:border-box;
            border-radius:999px;
            background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);
            color:#fff !important;
            text-decoration:none;
            font-weight:700;
            font-size:11px;
            line-height:1;
            box-shadow:0 6px 16px rgba(31,111,235,.22);
            cursor:pointer;
        }
        button.action-chip,
        button.action-chip:hover,
        button.action-chip:focus,
        button.action-chip:active{
            border:0 !important;
            border-color:transparent !important;
            outline:none !important;
            background-clip:padding-box;
            box-shadow:0 6px 16px rgba(31,111,235,.22) !important;
        }
        button.action-chip::-moz-focus-inner{border:0;padding:0}
        .action-chip:hover{
            background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);
            color:#fff !important;
            transform:translateY(-1px);
            box-shadow:0 10px 20px rgba(21,87,186,.24);
        }
        .muted{color:var(--muted);font-size:11px}
        .empty-note{padding:18px 14px;border:1px dashed #d9dfe8;border-radius:8px;color:var(--muted);background:#fafcff}
        .page-footer{margin-top:18px;text-align:center;color:#6d8298;font-size:12px}
        .choice-backdrop{position:fixed;inset:0;background:rgba(15,23,42,.35);display:none;align-items:center;justify-content:center;padding:16px;z-index:1000}
        .choice-backdrop.open{display:flex}
        .choice-dialog{width:min(420px,100%);background:#fff;border:1px solid #d9dfe8;border-radius:16px;padding:18px;box-shadow:0 20px 40px rgba(15,23,42,.18)}
        .choice-dialog h3{margin:0 0 8px;font-size:20px;color:#19324d}
        .choice-dialog p{margin:0 0 14px;color:#4a6078;line-height:1.5}
        .choice-actions{display:grid;gap:8px}
        .choice-actions .btn{justify-content:center}
        .choice-actions .btn-secondary{background:#eef4ff;color:#1d4ed8;border:1px solid #bfd3f2}
        .choice-actions .btn-danger{background:#fff1f1;color:#b42318;border:1px solid #fecaca}
        .choice-meta{margin-bottom:12px;font-size:12px;color:#64748b}
        h1,h2{margin-bottom:10px}
        @media (max-width:1100px){.stats,.form-grid,.filter-row,.editor-grid,.edit-form{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>&#47588;&#51109; &#44288;&#47532;</h1>
            <p>&#48177;&#54868;&#51216; &#51077;&#51216; &#47588;&#51109;&#51012; &#46321;&#47197;&#54616;&#44256; &#51221;&#49328; &#45824;&#49345; &#49345;&#53468;&#47484; &#44288;&#47532;&#54633;&#45768;&#45796;.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="download_tenant_store_template.jsp">&#53588;&#54540;&#47551; &#45796;&#50868;&#47196;&#46300;</a>
            <a class="btn" href="tenant_store_excel_import.jsp">&#50641;&#49472; &#51068;&#44292; &#46321;&#47197;</a>
            <a class="btn" href="tenant_meter_map_manage.jsp">&#47588;&#51109;-&#44228;&#52769;&#44592; &#50672;&#44208;</a>
            <a class="btn" href="tenant_billing_manage.jsp">&#47588;&#51109; &#51221;&#49328;</a>
            <a class="btn" href="epms_main.jsp">EPMS Home</a>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="notice ok"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="notice err"><%= h(err) %></div><% } %>

    <div class="stats">
        <div class="stat-card"><span>&#51204;&#52404; &#47588;&#51109;</span><strong><%= totalCnt %></strong></div>
        <div class="stat-card"><span>&#50868;&#50689; &#51473; &#47588;&#51109;</span><strong><%= activeCnt %></strong></div>
        <div class="stat-card"><span>&#51333;&#47308; &#47588;&#51109;</span><strong><%= closedCnt %></strong></div>
    </div>

    <div class="panel-box">
        <h2>&#44160;&#49353;</h2>
        <form method="get" class="filter-row">
            <div class="field">
                <label>&#44160;&#49353;&#50612;</label>
                <input type="text" name="q" value="<%= h(searchQ) %>" placeholder="&#47588;&#51109; &#53076;&#46300;, &#47588;&#51109;&#47749;, 층, &#54840;&#49892;, &#44396;&#50669;">
            </div>
            <div class="field">
                <label>&#49345;&#53468;</label>
                <select name="status">
                    <option value="" <%= statusQ.isEmpty() ? "selected" : "" %>>&#51204;&#52404;</option>
                    <option value="ACTIVE" <%= "ACTIVE".equals(statusQ) ? "selected" : "" %>>&#50868;&#50689;&#51473;</option>
                    <option value="CLOSED" <%= "CLOSED".equals(statusQ) ? "selected" : "" %>>&#51333;&#47308;</option>
                </select>
            </div>
            <div class="actions"><button type="submit" class="btn btn-primary">&#44160;&#49353;</button></div>
        </form>
    </div>

    <div class="editor-grid">
        <div class="panel-box">
            <div class="panel-head">
                <h2>&#47588;&#51109; &#46321;&#47197;</h2>
                <span class="hint-note">&#49352; &#47588;&#51109; &#51221;&#48372;&#47484; &#51077;&#47141;&#54616;&#49464;&#50836;.</span>
            </div>
            <form method="post" action="<%= h(postAction) %>" class="form-grid">
                <input type="hidden" name="action" value="add">
                <input type="hidden" name="q" value="<%= h(searchQ) %>">
                <input type="hidden" name="status" value="<%= h(statusQ) %>">
                <div class="field"><label>&#47588;&#51109; &#53076;&#46300;</label><input type="text" name="store_code" value="<%= h(generatedStoreCode) %>" readonly></div>
                <div class="field"><label>&#47588;&#51109;&#47749;</label><input type="text" name="store_name" required></div>
                <div class="field"><label>&#49324;&#50629;&#51088;&#48264;&#54840;</label><input type="text" name="business_number"></div>
                <div class="field"><label>&#49345;&#53468;</label><select name="store_status"><option value="ACTIVE">&#50868;&#50689;&#51473;</option><option value="CLOSED">&#51333;&#47308;</option></select></div>
                <div class="field"><label>층</label><input type="text" name="floor_name"></div>
                <div class="field"><label>&#54840;&#49892;</label><input type="text" name="room_name"></div>
                <div class="field"><label>&#44396;&#50669;</label><input type="text" name="zone_name"></div>
                <div class="field"><label>&#50629;&#51333;</label><input type="text" name="category_name"></div>
                <div class="field"><label>&#45812;&#45817;&#51088;</label><input type="text" name="contact_name"></div>
                <div class="field"><label>&#50672;&#46973;&#52376;</label><input type="text" name="contact_phone"></div>
                <div class="field"><label>&#50724;&#54536;&#51068;</label><input type="date" name="opened_on"></div>
                <div class="field"><label>&#51333;&#47308;&#51068;</label><input type="date" name="closed_on"></div>
                <div class="field field-wide"><label>&#48708;&#44256;</label><textarea name="notes"></textarea></div>
                <div class="actions" style="grid-column:1 / -1;"><button type="submit" class="btn btn-primary">&#47588;&#51109; &#46321;&#47197;</button></div>
            </form>
        </div>

        <div class="panel-box">
            <div class="panel-head">
                <h2>&#47588;&#51109; &#49688;&#51221;</h2>
                <span class="hint-note">&#47785;&#47197;&#50640;&#49436; &#47588;&#51109;&#51012; &#49440;&#53469;&#54616;&#47732; &#50668;&#44592;&#49436; &#48148;&#47196; &#49688;&#51221;&#54624; &#49688; &#51080;&#49845;&#45768;&#45796;.</span>
            </div>
            <% if (selectedRow == null) { %>
            <div class="empty-note">&#47785;&#47197;&#50640;&#49436; &#49688;&#51221;&#54624; &#47588;&#51109;&#51012; &#49440;&#53469;&#54616;&#47732; &#50668;&#44592;&#49436; &#49345;&#49464; &#51221;&#48372;&#47484; &#54200;&#51665;&#54624; &#49688; &#51080;&#49845;&#45768;&#45796;.</div>
            <% } else { %>
            <form method="post" action="<%= h(postAction) %>" class="edit-form" id="edit-store-panel">
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="store_id" value="<%= selectedRow.getStoreId() %>">
                <input type="hidden" name="q" value="<%= h(searchQ) %>">
                <input type="hidden" name="status" value="<%= h(statusQ) %>">
                <div class="field"><label>&#47588;&#51109; &#53076;&#46300;</label><input type="text" name="store_code" value="<%= h(selectedRow.getStoreCode()) %>" readonly></div>
                <div class="field"><label>&#47588;&#51109;&#47749;</label><input type="text" name="store_name" value="<%= h(selectedRow.getStoreName()) %>" required></div>
                <div class="field"><label>&#49324;&#50629;&#51088;&#48264;&#54840;</label><input type="text" name="business_number" value="<%= h(selectedRow.getBusinessNumber()) %>"></div>
                <div class="field"><label>&#49345;&#53468;</label><select name="store_status"><option value="ACTIVE" <%= "ACTIVE".equals(selectedRow.getStatus()) ? "selected" : "" %>>&#50868;&#50689;&#51473;</option><option value="CLOSED" <%= "CLOSED".equals(selectedRow.getStatus()) ? "selected" : "" %>>&#51333;&#47308;</option></select></div>
                <div class="field"><label>층</label><input type="text" name="floor_name" value="<%= h(selectedRow.getFloorName()) %>"></div>
                <div class="field"><label>&#54840;&#49892;</label><input type="text" name="room_name" value="<%= h(selectedRow.getRoomName()) %>"></div>
                <div class="field"><label>&#44396;&#50669;</label><input type="text" name="zone_name" value="<%= h(selectedRow.getZoneName()) %>"></div>
                <div class="field"><label>&#50629;&#51333;</label><input type="text" name="category_name" value="<%= h(selectedRow.getCategoryName()) %>"></div>
                <div class="field"><label>&#45812;&#45817;&#51088;</label><input type="text" name="contact_name" value="<%= h(selectedRow.getContactName()) %>"></div>
                <div class="field"><label>&#50672;&#46973;&#52376;</label><input type="text" name="contact_phone" value="<%= h(selectedRow.getContactPhone()) %>"></div>
                <div class="field"><label>&#50724;&#54536;&#51068;</label><input type="date" name="opened_on" value="<%= h(selectedRow.getOpenedOn()) %>"></div>
                <div class="field"><label>&#51333;&#47308;&#51068;</label><input type="date" name="closed_on" value="<%= h(selectedRow.getClosedOn()) %>"></div>
                <div class="field field-wide"><label>&#48708;&#44256;</label><textarea name="notes"><%= h(selectedRow.getNotes()) %></textarea></div>
                <div class="edit-form-actions" style="grid-column:1 / -1;">
                    <button type="submit" class="btn btn-primary">&#51200;&#51109;</button>
                    <a class="btn btn-primary" href="#" onclick="openStoreDeleteChoice(<%= selectedRow.getStoreId() %>, '<%= h(selectedRow.getStoreCode()) %>', '<%= h(searchQ) %>', '<%= h(statusQ) %>', true); return false;">&#49325;&#51228;</a>
                </div>
            </form>
            <% } %>
        </div>
    </div>

    <div class="panel-box">
        <h2>&#47588;&#51109; &#47785;&#47197;</h2>
        <div class="table-wrap">
            <table class="store-list-table">
                <thead><tr><th>ID</th><th>&#53076;&#46300;</th><th>&#47588;&#51109;&#47749;</th><th>층/&#54840;&#49892;/&#44396;&#50669;</th><th>&#50629;&#51333;</th><th>&#50672;&#46973;&#52376;</th><th>&#49345;&#53468;</th><th>&#50689;&#50629;&#44592;&#44036;</th><th>&#51089;&#50629;</th></tr></thead>
                <tbody>
                <% if (rows.isEmpty()) { %><tr><td colspan="9" class="muted">&#46321;&#47197;&#46108; &#47588;&#51109;&#51060; &#50630;&#49845;&#45768;&#45796;.</td></tr><% } %>
                <% for (TenantStoreRow row : rows) { %>
                <tr>
                    <td><%= row.getStoreId() %></td>
                    <td><strong><%= h(row.getStoreCode()) %></strong></td>
                    <td><%= h(row.getStoreName()) %><br><span class="muted"><%= h(row.getBusinessNumber()) %></span></td>
                    <td><%= h(row.getFloorName()) %> / <%= h(row.getRoomName()) %> / <%= h(row.getZoneName()) %></td>
                    <td><%= h(row.getCategoryName()) %></td>
                    <td><%= h(row.getContactName()) %><br><span class="muted"><%= h(row.getContactPhone()) %></span></td>
                    <td><span class="status-pill <%= "ACTIVE".equals(row.getStatus()) ? "status-active" : "status-closed" %>"><%= "ACTIVE".equals(row.getStatus()) ? "&#50868;&#50689;&#51473;" : "&#51333;&#47308;" %></span></td>
                    <td><%= h(row.getOpenedOn()) %> ~ <%= h(row.getClosedOn()) %></td>
                    <td>
                        <div class="table-actions">
                            <a class="action-chip" href="tenant_store_manage.jsp?q=<%= enc(searchQ) %>&status=<%= enc(statusQ) %>&edit_id=<%= row.getStoreId() %>">&#49688;&#51221;</a>
                            <a class="action-chip" href="#" onclick="openStoreDeleteChoice(<%= row.getStoreId() %>, '<%= h(row.getStoreCode()) %>', '<%= h(searchQ) %>', '<%= h(statusQ) %>', false); return false;">&#49325;&#51228;</a>
                        </div>
                    </td>
                </tr>
                <% } %>
                </tbody>
            </table>
        </div>
    </div>
</div>
<div class="choice-backdrop" id="store-delete-choice">
    <div class="choice-dialog">
        <h3>&#47588;&#51109; &#52376;&#47532; &#48169;&#49885; &#49440;&#53469;</h3>
        <div class="choice-meta" id="store-delete-choice-code"></div>
        <p>&#49325;&#51228; &#45824;&#49888; &#48708;&#54876;&#49457;&#54868;&#54624;&#51648;, &#44288;&#47144; &#45936;&#51060;&#53552;&#47484; &#51221;&#47532;&#54616;&#44256; &#50756;&#51204; &#49325;&#51228;&#54624;&#51648; &#49440;&#53469;&#54644;&#51452;&#49464;&#50836;.</p>
        <div class="choice-actions">
            <a href="#" class="btn btn-secondary" onclick="submitStoreDeleteChoice('disable'); return false;">&#48708;&#54876;&#49457;&#54868;</a>
            <a href="#" class="btn btn-danger" onclick="submitStoreDeleteChoice('cascade'); return false;">&#44288;&#47144; &#45936;&#51060;&#53552; &#51221;&#47532; &#54980; &#50756;&#51204; &#49325;&#51228;</a>
            <a href="#" class="btn" onclick="closeStoreDeleteChoice(); return false;">&#52712;&#49548;</a>
        </div>
    </div>
</div>
<footer class="page-footer">EPMS Dashboard | SNUT CNT</footer>
<script>
let storeDeleteChoice = { storeId: '', storeCode: '', q: '', status: '', keepEdit: false };

function openStoreDeleteChoice(storeId, storeCode, q, status, keepEdit) {
    storeDeleteChoice = {
        storeId: String(storeId || ''),
        storeCode: storeCode || '',
        q: q || '',
        status: status || '',
        keepEdit: !!keepEdit
    };
    document.getElementById('store-delete-choice-code').textContent = storeDeleteChoice.storeCode ? ('대상 매장: ' + storeDeleteChoice.storeCode) : '';
    document.getElementById('store-delete-choice').classList.add('open');
}

function closeStoreDeleteChoice() {
    document.getElementById('store-delete-choice').classList.remove('open');
}

function submitStoreDeleteChoice(mode) {
    const form = document.createElement('form');
    form.method = 'post';
    form.action = '<%= h(postAction) %>';
    form.style.display = 'none';
    appendHidden(form, 'action', 'delete');
    appendHidden(form, 'delete_mode', mode);
    appendHidden(form, 'store_id', storeDeleteChoice.storeId);
    appendHidden(form, 'q', storeDeleteChoice.q);
    appendHidden(form, 'status', storeDeleteChoice.status);
    if (storeDeleteChoice.keepEdit) {
        appendHidden(form, 'edit_id', storeDeleteChoice.storeId);
    }
    document.body.appendChild(form);
    form.submit();
}

function appendHidden(form, name, value) {
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value || '';
    form.appendChild(input);
}

document.getElementById('store-delete-choice').addEventListener('click', function (event) {
    if (event.target === this) closeStoreDeleteChoice();
});
</script>
</body>
</html>

