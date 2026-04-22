<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="epms.tenant.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%!
    private static String encMap(String s) {
        try { return URLEncoder.encode(s == null ? "" : s, "UTF-8"); } catch (Exception ignore) { return ""; }
    }
%>
<%
request.setCharacterEncoding("UTF-8");
String msg = request.getParameter("msg");
String err = request.getParameter("err");
String storeFilter = request.getParameter("filter_store_id");
String buildingFilter = request.getParameter("filter_building");
String editIdQ = request.getParameter("edit_id");
if (storeFilter == null) storeFilter = "";
if (buildingFilter == null) buildingFilter = "";
storeFilter = storeFilter.trim();
buildingFilter = buildingFilter.trim();

Long editId = null;
try {
    if (editIdQ != null && !editIdQ.trim().isEmpty()) editId = Long.valueOf(editIdQ.trim());
} catch (Exception ignore) {}

TenantMeterMapService meterMapService = new TenantMeterMapService();
String postAction = request.getContextPath() + "/tenant-meter-map-action";

TenantMeterMapPageData pageData = null;
try {
    pageData = meterMapService.loadPageData(storeFilter, buildingFilter, editId);
} catch (Exception e) {
    err = e.getMessage();
}

List<TenantOption> storeOptions = pageData == null ? Collections.<TenantOption>emptyList() : pageData.getStoreOptions();
List<TenantOption> meterOptions = pageData == null ? Collections.<TenantOption>emptyList() : pageData.getMeterOptions();
List<String> buildingOptions = pageData == null ? Collections.<String>emptyList() : pageData.getBuildingOptions();
List<TenantMeterMapRow> rows = pageData == null ? Collections.<TenantMeterMapRow>emptyList() : pageData.getRows();
TenantMeterMapRow selectedRow = pageData == null ? null : pageData.getSelectedRow();
int totalMapCnt = pageData == null ? 0 : pageData.getTotalMapCount();
int primaryCnt = pageData == null ? 0 : pageData.getPrimaryCount();
%>
<!DOCTYPE html>
<html>
<head>
    <title>&#47588;&#51109;-&#44228;&#52769;&#44592; &#50672;&#44208;</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1360px;margin:14px auto;padding:0 12px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px;margin-top:-4px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff;transform:translateY(-1px);box-shadow:0 10px 20px rgba(21,87,186,.24)}
        .panel-box,.stat-card{padding:12px;border:1px solid #d9dfe8;border-radius:6px;background:#fff;box-shadow:none}
        .stats{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
        .stat-card strong{display:block;font-size:20px;margin-top:4px}
        .filter-row,.form-grid,.edit-form{display:grid;gap:8px}
        .filter-row{grid-template-columns:1.4fr 1fr auto;align-items:end}
        .form-grid{grid-template-columns:repeat(4,minmax(0,1fr))}
        .content-grid{display:grid;grid-template-columns:minmax(0,1fr) 420px;gap:12px;align-items:start}
        .edit-panel{position:sticky;top:16px}
        .edit-form{grid-template-columns:repeat(2,minmax(0,1fr))}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field input,.field select,.field textarea{width:100%;min-width:0}
        .field textarea{min-height:72px;resize:vertical}
        .notice{padding:12px 14px;border-radius:10px;font-weight:700}
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .table-wrap{overflow-x:auto}
        table{min-width:1120px}
        .map-table th,.map-table td{word-break:keep-all;vertical-align:middle}
        .map-table th:nth-child(1),.map-table td:nth-child(1){width:72px}
        .map-table th:nth-child(2),.map-table td:nth-child(2){width:170px}
        .map-table th:nth-child(3),.map-table td:nth-child(3){width:250px}
        .map-table th:nth-child(4),.map-table td:nth-child(4){width:110px}
        .map-table th:nth-child(5),.map-table td:nth-child(5){width:100px}
        .map-table th:nth-child(6),.map-table td:nth-child(6){width:96px}
        .map-table th:nth-child(7),.map-table td:nth-child(7){width:180px}
        .map-table th:nth-child(8),.map-table td:nth-child(8){width:180px}
        .map-table th:nth-child(9),.map-table td:nth-child(9){width:132px}
        .muted{color:var(--muted);font-size:11px}
        .primary-tag{display:inline-block;padding:3px 8px;border-radius:999px;background:#eef4ff;color:#1d4ed8;font-weight:800}
        .actions,.table-actions,.edit-form-actions{display:flex;gap:8px;align-items:center}
        .table-actions{justify-content:flex-end;flex-wrap:wrap}
        .edit-form textarea{grid-column:1 / -1}
        .edit-form-actions{grid-column:1 / -1;justify-content:flex-end;margin-top:8px}
        .empty-note{padding:18px 14px;border:1px dashed #d9dfe8;border-radius:8px;color:var(--muted);background:#fafcff}
        .page-footer{margin-top:18px;text-align:center;color:#6d8298;font-size:12px}
        h1,h2{margin-bottom:10px}
        @media (max-width:1100px){.stats,.filter-row,.form-grid,.content-grid,.edit-form{grid-template-columns:1fr}.edit-panel{position:static}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>&#47588;&#51109;-&#44228;&#52769;&#44592; &#50672;&#44208;</h1>
            <p>&#50612;&#45712; &#44228;&#52769;&#44592;&#44032; &#50612;&#45712; &#47588;&#51109; &#52397;&#44396;&#50640; &#44480;&#49549;&#46104;&#45716;&#51648;&#50752; &#51201;&#50857; &#44592;&#44036;, &#48176;&#48516; &#48708;&#50984;&#51012; &#44288;&#47532;&#54633;&#45768;&#45796;.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="tenant_store_manage.jsp">&#47588;&#51109; &#44288;&#47532;</a>
            <a class="btn" href="tenant_meter_store_tiles.jsp">&#47588;&#51109; &#51204;&#47141;&#49324;&#50857;&#47049; &#51312;&#54924;</a>
            <a class="btn" href="tenant_billing_manage.jsp">&#50900; &#51221;&#49328;</a>
            <a class="btn" href="epms_main.jsp">EPMS &#54856;</a>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="notice ok"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="notice err"><%= h(err) %></div><% } %>

    <div class="stats">
        <div class="stat-card"><span>&#51204;&#52404; &#50672;&#44208; &#44148;&#49688;</span><strong><%= totalMapCnt %></strong></div>
        <div class="stat-card"><span>&#54788;&#51116; &#51312;&#54924; &#44208;&#44284;</span><strong><%= rows.size() %></strong></div>
        <div class="stat-card"><span>&#51452; &#44228;&#52769;&#44592; &#50668;&#48512; &#50672;&#44208;</span><strong><%= primaryCnt %></strong></div>
    </div>

    <div class="panel-box">
        <h2>&#44160;&#49353;</h2>
        <form method="get" class="filter-row">
            <div class="field">
                <label>&#47588;&#51109;</label>
                <select name="filter_store_id">
                    <option value="">&#51204;&#52404; &#47588;&#51109;</option>
                    <% for (TenantOption opt : storeOptions) { %>
                    <option value="<%= h(opt.getValue()) %>" <%= opt.getValue().equals(storeFilter) ? "selected" : "" %>><%= h(opt.getLabel()) %></option>
                    <% } %>
                </select>
            </div>
            <div class="field">
                <label>&#44148;&#47932;</label>
                <select name="filter_building">
                    <option value="">&#51204;&#52404; &#44148;&#47932;</option>
                    <% for (String opt : buildingOptions) { %>
                    <option value="<%= h(opt) %>" <%= opt.equals(buildingFilter) ? "selected" : "" %>><%= h(opt) %></option>
                    <% } %>
                </select>
            </div>
            <div class="actions">
                <button type="submit" class="btn btn-primary">&#44160;&#49353;</button>
            </div>
        </form>
    </div>

    <div class="panel-box">
        <h2>&#50672;&#44208; &#46321;&#47197;</h2>
        <form method="post" action="<%= h(postAction) %>" class="form-grid">
            <input type="hidden" name="action" value="add">
            <input type="hidden" name="filter_store_id" value="<%= h(storeFilter) %>">
            <input type="hidden" name="filter_building" value="<%= h(buildingFilter) %>">
            <div class="field">
                <label>&#47588;&#51109;</label>
                <select name="store_id" required>
                    <option value="">&#49440;&#53469;</option>
                    <% for (TenantOption opt : storeOptions) { %>
                    <option value="<%= h(opt.getValue()) %>" <%= opt.getValue().equals(storeFilter) ? "selected" : "" %>><%= h(opt.getLabel()) %></option>
                    <% } %>
                </select>
            </div>
            <div class="field">
                <label>&#44228;&#52769;&#44592;</label>
                <select name="meter_id" required>
                    <option value="">&#49440;&#53469;</option>
                    <% for (TenantOption opt : meterOptions) { %>
                    <option value="<%= h(opt.getValue()) %>"><%= h(opt.getLabel()) %></option>
                    <% } %>
                </select>
                <span class="muted"><% if (!buildingFilter.isEmpty()) { %>&#49440;&#53469;&#54620; &#44148;&#47932;&#51032; &#44228;&#52769;&#44592;&#47564; &#54364;&#49884;&#46121;&#45768;&#45796;.<% } else { %>&#51204;&#52404; &#44148;&#47932;&#51032; &#44228;&#52769;&#44592;&#44032; &#54364;&#49884;&#46121;&#45768;&#45796;.<% } %></span>
            </div>
            <div class="field">
                <label>&#51221;&#49328; &#48276;&#50948;</label>
                <select name="billing_scope">
                    <option value="DIRECT">DIRECT</option>
                    <option value="SHARED">SHARED</option>
                    <option value="SUB">SUB</option>
                </select>
            </div>
            <div class="field">
                <label>&#48176;&#48516; &#48708;&#50984;</label>
                <input type="text" name="allocation_ratio" value="1.0">
            </div>
            <div class="field">
                <label>&#51201;&#50857; &#49884;&#51089;&#51068;</label>
                <input type="date" name="valid_from" value="<%= new java.sql.Date(System.currentTimeMillis()) %>" required>
            </div>
            <div class="field">
                <label>&#51201;&#50857; &#51333;&#47308;&#51068;</label>
                <input type="date" name="valid_to">
            </div>
            <div class="field">
                <label>&#51452; &#44228;&#52769;&#44592;&#50668;&#48512;</label>
                <select name="is_primary">
                    <option value="true" selected>&#50696;</option>
                    <option value="false">&#50500;&#45768;&#50724;</option>
                </select>
            </div>
            <div class="field" style="grid-column:span 3;">
                <label>&#48708;&#44256;</label>
                <input type="text" name="notes">
            </div>
            <div class="actions">
                <button type="submit" class="btn btn-primary">&#50672;&#44208; &#46321;&#47197;</button>
            </div>
        </form>
    </div>

    <div class="content-grid">
        <div class="panel-box">
            <h2>&#50672;&#44208; &#47785;&#47197;</h2>
            <div class="table-wrap">
                <table class="map-table">
                    <thead>
                    <tr>
                        <th>ID</th>
                        <th>&#47588;&#51109;</th>
                        <th>&#44228;&#52769;&#44592;</th>
                        <th>&#51221;&#49328; &#48276;&#50948;</th>
                        <th>&#48176;&#48516; &#48708;&#50984;</th>
                        <th>&#51452; &#44228;&#52769;&#44592;&#50668;&#48512;</th>
                        <th>&#51201;&#50857; &#44592;&#44036;</th>
                        <th>&#48708;&#44256;</th>
                        <th>&#51089;&#50629;</th>
                    </tr>
                    </thead>
                    <tbody>
                    <% if (rows.isEmpty()) { %>
                    <tr><td colspan="9" class="muted">&#46321;&#47197;&#46108; &#50672;&#44208; &#51221;&#48372;&#44032; &#50630;&#49845;&#45768;&#45796;.</td></tr>
                    <% } %>
                    <% for (TenantMeterMapRow row : rows) { %>
                    <tr>
                        <td><%= row.getMapId() %></td>
                        <td><strong><%= h(row.getStoreCode()) %></strong><br><span class="muted"><%= h(row.getStoreName()) %></span></td>
                        <td>#<%= row.getMeterId() %> / <%= h(row.getMeterName()) %><br><span class="muted"><%= h(row.getBuildingName()) %> / <%= h(row.getPanelName()) %></span></td>
                        <td><%= h(row.getBillingScope()) %></td>
                        <td><%= String.format(java.util.Locale.US, "%.4f", row.getAllocationRatio()) %></td>
                        <td><% if (row.isPrimary()) { %><span class="primary-tag">&#51452; &#44228;&#52769;&#44592;</span><% } %></td>
                        <td><%= h(row.getValidFrom()) %> ~ <%= h(row.getValidTo()) %></td>
                        <td><%= h(row.getNotes()) %></td>
                        <td>
                            <div class="table-actions">
                                <a class="btn btn-primary" href="tenant_meter_map_manage.jsp?filter_store_id=<%= encMap(storeFilter) %>&filter_building=<%= encMap(buildingFilter) %>&edit_id=<%= row.getMapId() %>">&#49688;&#51221;</a>
                                <form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('&#51060; &#50672;&#44208; &#51221;&#48372;&#47484; &#49325;&#51228;&#54616;&#49884;&#44192;&#49845;&#45768;&#44620;?');">
                                    <input type="hidden" name="action" value="delete">
                                    <input type="hidden" name="map_id" value="<%= row.getMapId() %>">
                                    <input type="hidden" name="filter_store_id" value="<%= h(storeFilter) %>">
                                    <input type="hidden" name="filter_building" value="<%= h(buildingFilter) %>">
                                    <button type="submit" class="btn">&#49325;&#51228;</button>
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
            <h2>&#50672;&#44208; &#49688;&#51221;</h2>
            <% if (selectedRow == null) { %>
            <div class="empty-note">&#47785;&#47197;&#50640;&#49436; &#49688;&#51221;&#54624; &#50672;&#44208;&#51012; &#49440;&#53469;&#54616;&#47732; &#50668;&#44592;&#49436; &#49345;&#49464; &#51221;&#48372;&#47484; &#54200;&#51665;&#54624; &#49688; &#51080;&#49845;&#45768;&#45796;.</div>
            <% } else { %>
            <form method="post" action="<%= h(postAction) %>" class="edit-form" id="edit-map-panel">
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="map_id" value="<%= selectedRow.getMapId() %>">
                <input type="hidden" name="filter_store_id" value="<%= h(storeFilter) %>">
                <input type="hidden" name="filter_building" value="<%= h(buildingFilter) %>">
                <div class="field">
                    <label>&#47588;&#51109;</label>
                    <select name="store_id">
                        <% for (TenantOption opt : storeOptions) { %>
                        <option value="<%= h(opt.getValue()) %>" <%= String.valueOf(selectedRow.getStoreId()).equals(opt.getValue()) ? "selected" : "" %>><%= h(opt.getLabel()) %></option>
                        <% } %>
                    </select>
                </div>
                <div class="field">
                    <label>&#44228;&#52769;&#44592;</label>
                    <select name="meter_id">
                        <% for (TenantOption opt : meterOptions) { %>
                        <option value="<%= h(opt.getValue()) %>" <%= String.valueOf(selectedRow.getMeterId()).equals(opt.getValue()) ? "selected" : "" %>><%= h(opt.getLabel()) %></option>
                        <% } %>
                    </select>
                </div>
                <div class="field">
                    <label>&#51221;&#49328; &#48276;&#50948;</label>
                    <select name="billing_scope">
                        <option value="DIRECT" <%= "DIRECT".equals(selectedRow.getBillingScope()) ? "selected" : "" %>>DIRECT</option>
                        <option value="SHARED" <%= "SHARED".equals(selectedRow.getBillingScope()) ? "selected" : "" %>>SHARED</option>
                        <option value="SUB" <%= "SUB".equals(selectedRow.getBillingScope()) ? "selected" : "" %>>SUB</option>
                    </select>
                </div>
                <div class="field">
                    <label>&#48176;&#48516; &#48708;&#50984;</label>
                    <input type="text" name="allocation_ratio" value="<%= h(selectedRow.getAllocationRatio()) %>">
                </div>
                <div class="field">
                    <label>&#51201;&#50857; &#49884;&#51089;&#51068;</label>
                    <input type="date" name="valid_from" value="<%= h(selectedRow.getValidFrom()) %>">
                </div>
                <div class="field">
                    <label>&#51201;&#50857; &#51333;&#47308;&#51068;</label>
                    <input type="date" name="valid_to" value="<%= h(selectedRow.getValidTo()) %>">
                </div>
                <div class="field">
                    <label>&#51452; &#44228;&#52769;&#44592;&#50668;&#48512;</label>
                    <select name="is_primary">
                        <option value="true" <%= selectedRow.isPrimary() ? "selected" : "" %>>&#50696;</option>
                        <option value="false" <%= !selectedRow.isPrimary() ? "selected" : "" %>>&#50500;&#45768;&#50724;</option>
                    </select>
                </div>
                <div class="field" style="grid-column:1 / -1;">
                    <label>&#48708;&#44256;</label>
                    <textarea name="notes"><%= h(selectedRow.getNotes()) %></textarea>
                </div>
                <div class="edit-form-actions">
                    <button type="submit" class="btn btn-primary">&#51200;&#51109;</button>
                </div>
            </form>
            <div class="edit-form-actions">
                <form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('&#51060; &#50672;&#44208; &#51221;&#48372;&#47484; &#49325;&#51228;&#54616;&#49884;&#44192;&#49845;&#45768;&#44620;?');">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="map_id" value="<%= selectedRow.getMapId() %>">
                    <input type="hidden" name="filter_store_id" value="<%= h(storeFilter) %>">
                    <input type="hidden" name="filter_building" value="<%= h(buildingFilter) %>">
                    <button type="submit" class="btn">&#49325;&#51228;</button>
                </form>
            </div>
            <% } %>
        </div>
    </div>
</div>
<footer class="page-footer">EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
