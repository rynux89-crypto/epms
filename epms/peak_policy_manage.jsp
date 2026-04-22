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
Set<Integer> selectedStoreIds = new LinkedHashSet<Integer>();
if (selectedRow != null) {
    selectedStoreIds.addAll(selectedRow.getAssignedStoreIds());
}

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
    peakDashboardHasQuery = true;
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
String newPolicyHref = "peak_policy_manage.jsp" + (returnQuery.isEmpty() ? "" : "?" + returnQuery.substring(1));
List<String> policyNameExamples = Arrays.asList(
        "의류 기본 25kW",
        "식음 고부하 40kW",
        "명품 존 35kW",
        "3층 공통 30kW",
        "앵커테넌트 45kW",
        "팝업 매장 20kW");
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Peak Policy Management</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1520px;margin:14px auto;padding:0 12px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff}
        .panel-box{padding:12px;border:1px solid #d9dfe8;border-radius:8px;background:#fff;box-shadow:none}
        .top-workspace{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;align-items:start}
        .bottom-panel{display:grid}
        .context-bar{display:flex;flex-wrap:wrap;gap:8px}
        .context-chip{display:inline-flex;align-items:center;padding:6px 10px;border-radius:999px;background:#eff6ff;color:#1d4ed8;border:1px solid #bfdbfe;font-size:12px;font-weight:700}
        .field{display:grid;gap:3px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .form-grid,.edit-form{display:grid;gap:7px;grid-template-columns:repeat(2,minmax(0,1fr))}
        .field input,.field select,.field textarea{width:100%;min-width:0}
        .field textarea{min-height:56px;resize:vertical;grid-column:1 / -1}
        .policy-name-field{grid-column:1 / -1}
        .policy-name-tools{display:grid;gap:6px}
        .policy-name-chips{display:flex;gap:6px;flex-wrap:wrap}
        .policy-name-chip{display:inline-flex;align-items:center;justify-content:center;padding:5px 10px;border:1px solid #cbd8ea;border-radius:999px;background:#f8fbff;color:#2758a5;font-size:12px;font-weight:700;cursor:pointer}
        .policy-name-chip:hover{background:#eaf2ff}
        .field-hint{font-size:11px;color:#6d8298}
        .store-select-box{grid-column:1 / -1;display:grid;gap:10px;padding:10px;border:1px solid #d9e2ef;border-radius:12px;background:#fafcff}
        .store-select-head{display:flex;justify-content:space-between;align-items:flex-end;gap:8px;flex-wrap:wrap}
        .store-dual-layout{display:grid;grid-template-columns:minmax(0,1fr) 56px minmax(0,1fr);gap:10px;align-items:stretch}
        .store-pane{display:grid;gap:8px;padding:10px;border:1px solid #d9e2ef;border-radius:14px;background:#fff}
        .store-pane-head{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
        .store-pane-title{font-size:12px;font-weight:800;color:#23436d}
        .store-select-tools{display:grid;gap:6px}
        .store-search-row{display:grid;gap:6px}
        .store-search-input{width:100%;min-width:0}
        .store-select-actions{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
        .mini-btn{display:inline-flex;align-items:center;justify-content:center;padding:0;border:0;background:none;color:#2758a5;font-size:12px;font-weight:700;cursor:pointer;text-decoration:none}
        .mini-btn:hover{background:none;color:#143f84;text-decoration:underline}
        .store-selection-meta{font-size:12px;color:#55708d;font-weight:700}
        .store-transfer-actions{display:flex;flex-direction:column;gap:8px;justify-content:center;align-items:center}
        .transfer-btn{display:inline-flex;align-items:center;justify-content:center;width:44px;height:36px;border:1px solid #cdd9eb;border-radius:12px;background:#fff;color:#1d63da;font-weight:800;box-shadow:0 4px 10px rgba(31,111,235,.08);cursor:pointer}
        .transfer-btn:hover{background:#eef5ff}
        .transfer-hint{font-size:11px;color:#6d8298;text-align:center;line-height:1.35}
        .store-grid{display:grid;gap:6px;max-height:220px;overflow:auto;padding-right:4px}
        .store-chip{display:flex;align-items:flex-start;gap:7px;padding:8px 9px;border:1px solid #d9e2ef;border-radius:10px;background:#fff;font-size:12px}
        .store-chip input{width:auto;margin:0}
        .store-chip.is-hidden{display:none}
        .store-chip.is-assigned{border-color:#bfdbfe;background:#f8fbff}
        .store-chip .store-chip-text{display:grid;gap:2px}
        .store-chip .store-chip-caption{font-size:11px;color:#6d8298}
        .panel-head-row{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
        .table-wrap{overflow-x:auto}
        .table-wrap.list-scroll{max-height:calc(100vh - 260px);overflow:auto;border-radius:10px}
        table{min-width:920px}
        .compact-table{min-width:920px;font-size:11px;table-layout:fixed}
        .compact-table th,.compact-table td{padding:6px 6px;vertical-align:middle;line-height:1.2}
        .compact-table th{font-size:11px;letter-spacing:-0.01em}
        .compact-table td:first-child,.compact-table th:first-child{width:42px;text-align:center}
        .compact-table td:nth-child(2),.compact-table th:nth-child(2){width:150px;max-width:150px}
        .compact-table td:nth-child(2){white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        .compact-table td:nth-child(3),.compact-table th:nth-child(3){width:170px;max-width:170px}
        .compact-table td:nth-child(3){white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        .compact-table td:nth-child(4),.compact-table th:nth-child(4){width:60px}
        .compact-table td:nth-child(5),.compact-table th:nth-child(5){width:56px}
        .compact-table td:nth-child(6),.compact-table th:nth-child(6){width:56px}
        .compact-table td:nth-child(7),.compact-table th:nth-child(7){width:62px}
        .compact-table td:nth-child(8),.compact-table th:nth-child(8){width:64px;white-space:nowrap;font-size:11px}
        .compact-table td:nth-child(9),.compact-table th:nth-child(9){width:74px;white-space:nowrap}
        .compact-table td:nth-child(10),.compact-table th:nth-child(10){width:72px}
        .notice{padding:12px 14px;border-radius:10px;font-weight:700;transition:opacity .35s ease,transform .35s ease}
        .ok{background:#ecfdf3;border:1px solid #b7ebc6;color:#166534}
        .err{background:#fff1f1;border:1px solid #fecaca;color:#b42318}
        .notice-dismiss{opacity:0;transform:translateY(-4px)}
        .edit-panel{max-height:none;overflow:visible}
        .actions,.table-actions,.edit-form-actions{display:flex;gap:8px;align-items:center}
        .table-actions{justify-content:flex-end;flex-wrap:wrap}
        .edit-form-actions{justify-content:space-between;margin-top:10px;gap:12px;flex-wrap:wrap}
        .edit-primary-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
        .edit-side-actions{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-left:auto}
        .text-link-btn{color:#1d63da;text-decoration:none;font-weight:700;white-space:nowrap}
        .text-link-btn:hover{color:#144fb3;text-decoration:underline}
        .empty-note{padding:18px 14px;border:1px dashed #d9dfe8;border-radius:8px;color:var(--muted);background:#fafcff}
        .action-card{display:inline-flex;align-items:center;justify-content:center;width:64px;height:36px;padding:4px 6px;border-radius:12px;border:1px solid #d7e1f1;background:linear-gradient(180deg,#ffffff 0%,#f7fbff 100%);box-shadow:0 6px 14px rgba(33,73,135,.06);box-sizing:border-box}
        .action-card form{margin:0}
        .action-pill{display:inline-flex;align-items:center;justify-content:center;min-width:42px;height:24px;padding:0 10px;border:0;border-radius:999px;background:linear-gradient(180deg,#2f7df5 0%,#1d63da 100%);color:#fff;font-weight:700;line-height:1;white-space:nowrap;text-decoration:none;box-shadow:inset 0 1px 0 rgba(255,255,255,.35),0 6px 12px rgba(29,99,218,.18);cursor:pointer;font-size:11px}
        .action-pill:hover{background:linear-gradient(180deg,#3f88fa 0%,#1f69e8 100%);color:#fff}
        .action-pill:focus{outline:2px solid rgba(29,99,218,.22);outline-offset:2px}
        .compact-table .table-actions{gap:4px}
        .compact-table .action-card{width:56px;height:32px;padding:4px 6px;border-radius:10px}
        .compact-table .action-pill{min-width:38px;height:22px;padding:0 8px;font-size:10px}
        .page-footer{margin-top:18px;text-align:center;color:#6d8298;font-size:12px}
        @media (max-width:1200px){.store-dual-layout{grid-template-columns:1fr}.store-transfer-actions{flex-direction:row;justify-content:flex-start;flex-wrap:wrap}.transfer-hint{width:100%;text-align:left}}
        @media (max-width:1100px){.top-workspace,.form-grid,.edit-form{grid-template-columns:1fr}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>Peak Policy Management</h1>
            <p>&#44592;&#48376; &#51221;&#52293;&#51012; &#47700;&#51060;&#51200;&#47196; &#44288;&#47532;&#54616;&#44256;, &#44033; &#51221;&#52293;&#51060; &#51201;&#50857;&#46112; &#47588;&#51109;&#51012; &#49440;&#53469;&#54633;&#45768;&#45796;.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="<%= h(peakDashboardHref) %>">Peak Dashboard</a>
            <a class="btn" href="tenant_meter_store_tiles.jsp">&#50896;&#44201;&#44160;&#52840; &#50868;&#50689;</a>
            <a class="btn" href="epms_main.jsp">EPMS Home</a>
        </div>
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %><div class="notice ok"><%= h(msg) %></div><% } %>
    <% if (err != null && !err.trim().isEmpty()) { %><div class="notice err"><%= h(err) %></div><% } %>

    <% if (!returnFloor.isEmpty() || !returnCategory.isEmpty() || !returnStatus.isEmpty()) { %>
    <div class="panel-box">
        <div class="context-bar">
            <% if (!returnFloor.isEmpty()) { %><span class="context-chip">&#52735;: <%= h(returnFloor) %></span><% } %>
            <% if (!returnCategory.isEmpty()) { %><span class="context-chip">&#50629;&#51333;: <%= h(returnCategory) %></span><% } %>
            <% if (!returnStatus.isEmpty()) { %><span class="context-chip">&#49345;&#53468;: <%= h(returnStatus) %></span><% } %>
            <a class="btn" href="<%= h(peakDashboardHref) %>">&#44057;&#51008; &#54596;&#53552;&#47196; &#45824;&#49884;&#48372;&#46300; &#48373;&#44480;</a>
        </div>
    </div>
    <% } %>

    <div class="top-workspace">
        <div class="panel-box">
            <div class="panel-head-row">
                <h2>&#51221;&#52293; &#46321;&#47197;</h2>
            </div>
            <form method="post" action="<%= h(postAction) %>" class="edit-form" id="edit-peak-policy-panel">
                <input type="hidden" name="action" value="add">
                <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                <div class="field policy-name-field">
                    <label>&#51221;&#52293;&#47749;</label>
                    <div class="policy-name-tools">
                        <input type="text" name="policy_name" value="" list="policy-name-examples" data-role="policy-name-input" placeholder="&#50696;: &#51032;&#47448; &#44592;&#48376; 25kW">
                        <div class="field-hint">&#50500;&#47000; &#50696;&#49884;&#47484; &#53364;&#47533;&#54616;&#47732; &#51221;&#52293;&#47749;&#51004;&#47196; &#48148;&#47196; &#51077;&#47141;&#46121;&#45768;&#45796;.</div>
                        <div class="policy-name-chips">
                            <% for (String exampleName : policyNameExamples) { %>
                            <button type="button" class="policy-name-chip" data-role="policy-name-example" data-value="<%= h(exampleName) %>"><%= h(exampleName) %></button>
                            <% } %>
                        </div>
                    </div>
                </div>
                <div class="field"><label>&#54588;&#53356; &#54620;&#46020; (kW)</label><input type="text" name="peak_limit_kw" value="0"></div>
                <div class="field"><label>&#44221;&#44256; &#44592;&#51456; (%)</label><input type="text" name="warning_threshold_pct" value="80"></div>
                <div class="field"><label>&#51228;&#50612; &#44592;&#51456; (%)</label><input type="text" name="control_threshold_pct" value="95"></div>
                <div class="field"><label>&#50864;&#49440;&#49692;&#50948; (1-9)</label><input type="text" name="priority_level" value="5"></div>
                <div class="field">
                    <label>&#51088;&#46041; &#51228;&#50612; &#49324;&#50857;</label>
                    <select name="control_enabled">
                        <option value="true" selected>&#49324;&#50857;</option>
                        <option value="false">&#48120;&#49324;&#50857;</option>
                    </select>
                </div>
                <div class="field"><label>&#51201;&#50857; &#49884;&#51089;&#51068;</label><input type="date" name="effective_from" value="<%= new java.sql.Date(System.currentTimeMillis()) %>"></div>
                <div class="field"><label>&#51201;&#50857; &#51333;&#47308;&#51068;</label><input type="date" name="effective_to" value=""></div>
                <div class="field" style="grid-column:1 / -1;"><label>&#48708;&#44256;</label><textarea name="notes"></textarea></div>
                <div class="store-select-box" data-store-picker="add">
                    <div class="store-select-head">
                        <div class="field">
                            <label>&#51201;&#50857; &#47588;&#51109; &#49440;&#53469;</label>
                        </div>
                        <div class="store-selection-meta" data-role="selection-meta">&#49440;&#53469; 0&#44148;</div>
                    </div>
                    <div class="store-dual-layout">
                        <div class="store-pane">
                            <div class="store-pane-head">
                                <div class="store-pane-title">&#51201;&#50857; &#44032;&#45733; &#47588;&#51109;</div>
                                <div class="store-selection-meta" data-role="available-meta">&#51204;&#52404; <%= storeOptions.size() %>&#44148;</div>
                            </div>
                            <div class="store-select-tools">
                                <div class="store-search-row">
                                    <input type="text" class="store-search-input" data-role="available-search" placeholder="&#47588;&#51109;&#53076;&#46300; / &#47588;&#51109;&#47749; &#44160;&#49353;">
                                    <div class="store-select-actions">
                                        <button type="button" class="mini-btn" data-action="add-filtered">&#44160;&#49353; &#44208;&#44284; &#51204;&#52404; &#52628;&#44032;</button>
                                        <button type="button" class="mini-btn" data-action="clear-available-search">&#52488;&#44592;&#54868;</button>
                                    </div>
                                </div>
                            </div>
                            <div class="store-grid" data-role="available-list">
                                <% for (PeakStoreOption opt : storeOptions) { %>
                                <label class="store-chip" data-store-label="<%= h(opt.getLabel()) %>" data-store-id="<%= h(opt.getValue()) %>">
                                    <input type="checkbox" data-role="store-toggle">
                                    <input type="checkbox" name="store_ids" value="<%= h(opt.getValue()) %>" data-role="store-submit" style="display:none">
                                    <span class="store-chip-text">
                                        <span><%= h(opt.getLabel()) %></span>
                                        <span class="store-chip-caption">&#51201;&#50857; &#45824;&#49345; &#47588;&#51109;</span>
                                    </span>
                                </label>
                                <% } %>
                            </div>
                        </div>
                        <div class="store-transfer-actions">
                            <button type="button" class="transfer-btn" data-action="add-selected" title="&#49440;&#53469; &#52628;&#44032;">&gt;</button>
                            <button type="button" class="transfer-btn" data-action="remove-selected" title="&#49440;&#53469; &#54644;&#51228;">&lt;</button>
                            <button type="button" class="transfer-btn" data-action="add-filtered-all" title="&#44160;&#49353; &#44208;&#44284; &#51204;&#52404; &#52628;&#44032;">&gt;&gt;</button>
                            <button type="button" class="transfer-btn" data-action="remove-all" title="&#51204;&#52404; &#54644;&#51228;">&lt;&lt;</button>
                            <div class="transfer-hint">&#51473;&#50521; &#48260;&#53948;&#51004;&#47196; &#51201;&#50857; &#47588;&#51109;&#51012; &#51221;&#54633;&#45768;&#45796;.</div>
                        </div>
                        <div class="store-pane">
                            <div class="store-pane-head">
                                <div class="store-pane-title">&#49352; &#51221;&#52293;&#50640; &#51201;&#50857;&#46108; &#47588;&#51109;</div>
                                <div class="store-selection-meta" data-role="assigned-meta">&#49440;&#53469; 0&#44148;</div>
                            </div>
                            <div class="store-select-tools">
                                <div class="store-search-row">
                                    <input type="text" class="store-search-input" data-role="assigned-search" placeholder="&#51201;&#50857;&#46108; &#47588;&#51109; &#45236; &#44160;&#49353;">
                                    <div class="store-select-actions">
                                        <button type="button" class="mini-btn" data-action="remove-filtered">&#44160;&#49353; &#44208;&#44284; &#51204;&#52404; &#54644;&#51228;</button>
                                        <button type="button" class="mini-btn" data-action="clear-assigned-search">&#52488;&#44592;&#54868;</button>
                                    </div>
                                </div>
                            </div>
                            <div class="store-grid" data-role="assigned-list"></div>
                        </div>
                    </div>
                </div>
            </form>
            <div class="edit-form-actions">
                <div class="edit-primary-actions">
                    <button type="submit" form="edit-peak-policy-panel" class="btn btn-primary">&#51221;&#52293; &#46321;&#47197;</button>
                    <button type="submit" form="edit-peak-policy-panel" name="redirect_to_dashboard" value="true" class="btn">&#46321;&#47197; &#54980; &#45824;&#49884;&#48372;&#46300; &#48373;&#44480;</button>
                </div>
            </div>
        </div>

        <div class="panel-box edit-panel">
            <div class="panel-head-row">
                <h2>&#51221;&#52293; &#49688;&#51221;</h2>
                <% if (selectedRow != null) { %>
                <a class="text-link-btn" href="<%= h(newPolicyHref) %>">&#49440;&#53469; &#54644;&#51228;</a>
                <% } %>
            </div>
            <% if (selectedRow == null) { %>
            <div class="empty-note">&#50500;&#47000; &#51221;&#52293; &#47785;&#47197;&#50640;&#49436; &#49688;&#51221;&#54624; &#51221;&#52293;&#51012; &#49440;&#53469;&#54616;&#47732; &#50668;&#44592;&#50640; &#44592;&#51456;&#44284; &#51201;&#50857; &#47588;&#51109;&#51060; &#54364;&#49884;&#46121;&#45768;&#45796;.</div>
            <% } else { %>
            <form method="post" action="<%= h(postAction) %>" class="edit-form" id="update-peak-policy-panel">
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="policy_id" value="<%= selectedRow.getPolicyId() %>">
                <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                <div class="field policy-name-field">
                    <label>&#51221;&#52293;&#47749;</label>
                    <div class="policy-name-tools">
                        <input type="text" name="policy_name" value="<%= h(selectedRow.getPolicyName()) %>" list="policy-name-examples" data-role="policy-name-input" placeholder="&#50696;: &#51032;&#47448; &#44592;&#48376; 25kW">
                        <div class="field-hint">&#50696;&#49884; &#51221;&#52293;&#47749;&#51012; &#44592;&#48152;&#51004;&#47196; &#49688;&#51221;&#54624; &#49688; &#51080;&#49845;&#45768;&#45796;.</div>
                        <div class="policy-name-chips">
                            <% for (String exampleName : policyNameExamples) { %>
                            <button type="button" class="policy-name-chip" data-role="policy-name-example" data-value="<%= h(exampleName) %>"><%= h(exampleName) %></button>
                            <% } %>
                        </div>
                    </div>
                </div>
                <div class="field"><label>&#54588;&#53356; &#54620;&#46020; (kW)</label><input type="text" name="peak_limit_kw" value="<%= h(selectedRow.getPeakLimitKw()) %>"></div>
                <div class="field"><label>&#44221;&#44256; &#44592;&#51456; (%)</label><input type="text" name="warning_threshold_pct" value="<%= h(selectedRow.getWarningThresholdPct()) %>"></div>
                <div class="field"><label>&#51228;&#50612; &#44592;&#51456; (%)</label><input type="text" name="control_threshold_pct" value="<%= h(selectedRow.getControlThresholdPct()) %>"></div>
                <div class="field"><label>&#50864;&#49440;&#49692;&#50948; (1-9)</label><input type="text" name="priority_level" value="<%= h(selectedRow.getPriorityLevel()) %>"></div>
                <div class="field">
                    <label>&#51088;&#46041; &#51228;&#50612; &#49324;&#50857;</label>
                    <select name="control_enabled">
                        <option value="true" <%= selectedRow.isControlEnabled() ? "selected" : "" %>>&#49324;&#50857;</option>
                        <option value="false" <%= !selectedRow.isControlEnabled() ? "selected" : "" %>>&#48120;&#49324;&#50857;</option>
                    </select>
                </div>
                <div class="field"><label>&#51201;&#50857; &#49884;&#51089;&#51068;</label><input type="date" name="effective_from" value="<%= h(selectedRow.getEffectiveFrom()) %>"></div>
                <div class="field"><label>&#51201;&#50857; &#51333;&#47308;&#51068;</label><input type="date" name="effective_to" value="<%= h(selectedRow.getEffectiveTo()) %>"></div>
                <div class="field" style="grid-column:1 / -1;"><label>&#48708;&#44256;</label><textarea name="notes"><%= h(selectedRow.getNotes()) %></textarea></div>
                <div class="store-select-box" data-store-picker="edit">
                    <div class="store-select-head">
                        <div class="field">
                            <label>&#51201;&#50857; &#47588;&#51109; &#49440;&#53469;</label>
                        </div>
                        <div class="store-selection-meta" data-role="selection-meta">&#49440;&#53469; <%= selectedStoreIds.size() %>&#44148;</div>
                    </div>
                    <div class="store-dual-layout">
                        <div class="store-pane">
                            <div class="store-pane-head">
                                <div class="store-pane-title">&#51201;&#50857; &#44032;&#45733; &#47588;&#51109;</div>
                                <div class="store-selection-meta" data-role="available-meta">&#51204;&#52404; <%= storeOptions.size() %>&#44148;</div>
                            </div>
                            <div class="store-select-tools">
                                <div class="store-search-row">
                                    <input type="text" class="store-search-input" data-role="available-search" placeholder="&#47588;&#51109;&#53076;&#46300; / &#47588;&#51109;&#47749; &#44160;&#49353;">
                                    <div class="store-select-actions">
                                        <button type="button" class="mini-btn" data-action="add-filtered">&#44160;&#49353; &#44208;&#44284; &#51204;&#52404; &#52628;&#44032;</button>
                                        <button type="button" class="mini-btn" data-action="clear-available-search">&#52488;&#44592;&#54868;</button>
                                    </div>
                                </div>
                            </div>
                            <div class="store-grid" data-role="available-list">
                                <% for (PeakStoreOption opt : storeOptions) { Integer optStoreId = null; try { optStoreId = Integer.valueOf(opt.getValue()); } catch (Exception ignore) {} %>
                                <label class="store-chip" data-store-label="<%= h(opt.getLabel()) %>" data-store-id="<%= h(opt.getValue()) %>">
                                    <input type="checkbox" data-role="store-toggle">
                                    <input type="checkbox" name="store_ids" value="<%= h(opt.getValue()) %>" data-role="store-submit" style="display:none" <%= (optStoreId != null && selectedStoreIds.contains(optStoreId)) ? "checked" : "" %>>
                                    <span class="store-chip-text">
                                        <span><%= h(opt.getLabel()) %></span>
                                        <span class="store-chip-caption">&#51201;&#50857; &#50668;&#48512;&#47484; &#50864;&#52769;&#50640;&#49436; &#54869;&#51064;</span>
                                    </span>
                                </label>
                                <% } %>
                            </div>
                        </div>
                        <div class="store-transfer-actions">
                            <button type="button" class="transfer-btn" data-action="add-selected" title="&#49440;&#53469; &#52628;&#44032;">&gt;</button>
                            <button type="button" class="transfer-btn" data-action="remove-selected" title="&#49440;&#53469; &#54644;&#51228;">&lt;</button>
                            <button type="button" class="transfer-btn" data-action="add-filtered-all" title="&#44160;&#49353; &#44208;&#44284; &#51204;&#52404; &#52628;&#44032;">&gt;&gt;</button>
                            <button type="button" class="transfer-btn" data-action="remove-all" title="&#51204;&#52404; &#54644;&#51228;">&lt;&lt;</button>
                            <div class="transfer-hint">&#51473;&#50521; &#48260;&#53948;&#51004;&#47196; &#51221;&#52293; &#51201;&#50857; &#47588;&#51109;&#51012; &#51060;&#46041;&#54633;&#45768;&#45796;.</div>
                        </div>
                        <div class="store-pane">
                            <div class="store-pane-head">
                                <div class="store-pane-title">&#51221;&#52293;&#50640; &#51201;&#50857;&#46108; &#47588;&#51109;</div>
                                <div class="store-selection-meta" data-role="assigned-meta">&#49440;&#53469; <%= selectedStoreIds.size() %>&#44148;</div>
                            </div>
                            <div class="store-select-tools">
                                <div class="store-search-row">
                                    <input type="text" class="store-search-input" data-role="assigned-search" placeholder="&#51201;&#50857;&#46108; &#47588;&#51109; &#45236; &#44160;&#49353;">
                                    <div class="store-select-actions">
                                        <button type="button" class="mini-btn" data-action="remove-filtered">&#44160;&#49353; &#44208;&#44284; &#51204;&#52404; &#54644;&#51228;</button>
                                        <button type="button" class="mini-btn" data-action="clear-assigned-search">&#52488;&#44592;&#54868;</button>
                                    </div>
                                </div>
                            </div>
                            <div class="store-grid" data-role="assigned-list"></div>
                        </div>
                    </div>
                </div>
            </form>
            <div class="edit-form-actions">
                <div class="edit-primary-actions">
                    <button type="submit" form="update-peak-policy-panel" class="btn btn-primary">&#51200;&#51109;</button>
                    <button type="submit" form="update-peak-policy-panel" name="redirect_to_dashboard" value="true" class="btn">&#51200;&#51109; &#54980; &#45824;&#49884;&#48372;&#46300; &#48373;&#44480;</button>
                </div>
                <div class="edit-side-actions">
                    <a class="text-link-btn" href="<%= h(peakDashboardHref) %>">&#45824;&#49884;&#48372;&#46300;&#47196; &#46028;&#50500;&#44032;&#44592;</a>
                    <span class="action-card">
                        <form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('&#51060; peak &#51221;&#52293;&#51012; &#49325;&#51228;&#54616;&#49884;&#44192;&#49845;&#45768;&#44620;?');">
                            <input type="hidden" name="action" value="delete">
                            <input type="hidden" name="policy_id" value="<%= selectedRow.getPolicyId() %>">
                            <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                            <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                            <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                            <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                            <button type="submit" class="action-pill">&#49325;&#51228;</button>
                        </form>
                    </span>
                </div>
            </div>
            <% } %>
        </div>
    </div>

    <div class="panel-box bottom-panel">
        <div class="panel-head-row">
            <h2>&#46321;&#47197;&#46108; &#51221;&#52293; &#47785;&#47197;</h2>
            <a class="text-link-btn" href="<%= h(newPolicyHref) %>">&#49352; &#51221;&#52293; &#46321;&#47197;</a>
        </div>
        <div class="table-wrap list-scroll">
            <table class="compact-table">
                <thead>
                <tr>
                    <th>ID</th>
                    <th>&#51221;&#52293;&#47749;</th>
                    <th>&#51201;&#50857; &#47588;&#51109;</th>
                    <th>&#54588;&#53356; &#54620;&#46020; (kW)</th>
                    <th>&#44221;&#44256; (%)</th>
                    <th>&#51228;&#50612; (%)</th>
                    <th>&#50864;&#49440;&#49692;&#50948;</th>
                    <th>&#51088;&#46041; &#51228;&#50612;</th>
                    <th>&#51201;&#50857; &#44592;&#44036;</th>
                    <th>&#51089;&#50629;</th>
                </tr>
                </thead>
                <tbody>
                <% if (rows.isEmpty()) { %><tr><td colspan="10" class="empty-note">&#46321;&#47197;&#46108; peak &#51221;&#52293;&#51060; &#50630;&#49845;&#45768;&#45796;.</td></tr><% } %>
                <% for (PeakPolicyRow row : rows) { %>
                <tr>
                    <td><%= row.getPolicyId() %></td>
                    <td><%= h(row.getPolicyName()) %></td>
                    <td title="<%= h(row.getAssignedStoreSummary()) %>"><%= h(row.getAssignedStoreSummary()) %></td>
                    <td><%= h(row.getPeakLimitKw()) %></td>
                    <td><%= h(row.getWarningThresholdPct()) %></td>
                    <td><%= h(row.getControlThresholdPct()) %></td>
                    <td><%= h(row.getPriorityLevel()) %></td>
                    <td><%= row.isControlEnabled() ? "&#49324;&#50857;" : "&#48120;&#49324;&#50857;" %></td>
                    <td><%= h(row.getEffectiveFrom()) %> ~ <%= h(row.getEffectiveTo()) %></td>
                    <td>
                        <div class="table-actions">
                            <span class="action-card">
                                <a class="action-pill" href="peak_policy_manage.jsp?edit_id=<%= row.getPolicyId() %><%= h(returnQuery) %>">&#49688;&#51221;</a>
                            </span>
                            <span class="action-card">
                                <form method="post" action="<%= h(postAction) %>" onsubmit="return confirm('&#51060; peak &#51221;&#52293;&#51012; &#49325;&#51228;&#54616;&#49884;&#44192;&#49845;&#45768;&#44620;?');">
                                    <input type="hidden" name="action" value="delete">
                                    <input type="hidden" name="policy_id" value="<%= row.getPolicyId() %>">
                                    <input type="hidden" name="return_floor" value="<%= h(returnFloor) %>">
                                    <input type="hidden" name="return_category" value="<%= h(returnCategory) %>">
                                    <input type="hidden" name="return_status" value="<%= h(returnStatus) %>">
                                    <input type="hidden" name="return_section" value="<%= h(returnSection) %>">
                                    <button type="submit" class="action-pill">&#49325;&#51228;</button>
                                </form>
                            </span>
                        </div>
                    </td>
                </tr>
                <% } %>
                </tbody>
            </table>
        </div>
    </div>
</div>
<footer class="page-footer">EPMS Dashboard | SNUT CNT</footer>
<datalist id="policy-name-examples">
    <% for (String exampleName : policyNameExamples) { %>
    <option value="<%= h(exampleName) %>"></option>
    <% } %>
</datalist>
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

(function() {
    var exampleButtons = document.querySelectorAll('[data-role="policy-name-example"]');
    if (!exampleButtons.length) return;
    exampleButtons.forEach(function(button) {
        button.addEventListener('click', function() {
            var container = button.closest('.policy-name-tools');
            if (!container) return;
            var input = container.querySelector('[data-role="policy-name-input"]');
            if (!input) return;
            input.value = button.getAttribute('data-value') || '';
            input.focus();
        });
    });
})();

(function() {
    var pickers = document.querySelectorAll('[data-store-picker]');
    if (!pickers.length) return;

    function normalize(text) {
        return (text || '').toLowerCase().replace(/\s+/g, ' ').trim();
    }

    pickers.forEach(function(picker) {
        var meta = picker.querySelector('[data-role="selection-meta"]');
        var availableMeta = picker.querySelector('[data-role="available-meta"]');
        var assignedMeta = picker.querySelector('[data-role="assigned-meta"]');
        var availableSearch = picker.querySelector('[data-role="available-search"]');
        var assignedSearch = picker.querySelector('[data-role="assigned-search"]');
        var availableList = picker.querySelector('[data-role="available-list"]');
        var assignedList = picker.querySelector('[data-role="assigned-list"]');
        var chips = Array.prototype.slice.call(picker.querySelectorAll('.store-chip'));

        function getSubmitCheckbox(chip) {
            return chip.querySelector('[data-role="store-submit"]');
        }

        function getToggleCheckbox(chip) {
            return chip.querySelector('[data-role="store-toggle"]');
        }

        function syncPlacement() {
            chips.forEach(function(chip) {
                var submit = getSubmitCheckbox(chip);
                var toggle = getToggleCheckbox(chip);
                var isAssigned = !!(submit && submit.checked);
                chip.classList.toggle('is-assigned', isAssigned);
                chip.classList.remove('is-hidden');
                if (toggle) toggle.checked = false;
                if (isAssigned) {
                    assignedList.appendChild(chip);
                } else {
                    availableList.appendChild(chip);
                }
            });
        }

        function filterList(listEl, keyword) {
            var listChips = Array.prototype.slice.call(listEl.querySelectorAll('.store-chip'));
            var normalizedKeyword = normalize(keyword);
            listChips.forEach(function(chip) {
                var label = normalize(chip.getAttribute('data-store-label'));
                var match = !normalizedKeyword || label.indexOf(normalizedKeyword) >= 0;
                chip.classList.toggle('is-hidden', !match);
            });
            return listChips.filter(function(chip) { return !chip.classList.contains('is-hidden'); }).length;
        }

        function updateMeta() {
            var assignedCount = chips.filter(function(chip) {
                var submit = getSubmitCheckbox(chip);
                return submit && submit.checked;
            }).length;
            var availableVisible = filterList(availableList, availableSearch ? availableSearch.value : '');
            var assignedVisible = filterList(assignedList, assignedSearch ? assignedSearch.value : '');
            if (meta) meta.textContent = '적용 ' + assignedCount + '건 / 전체 ' + chips.length + '건';
            if (availableMeta) availableMeta.textContent = '검색 결과 ' + availableVisible + '건';
            if (assignedMeta) assignedMeta.textContent = '적용 ' + assignedCount + '건 / 검색 결과 ' + assignedVisible + '건';
        }

        function moveMatching(sourceList, toAssigned, onlyChecked) {
            var sourceChips = Array.prototype.slice.call(sourceList.querySelectorAll('.store-chip'));
            sourceChips.forEach(function(chip) {
                if (chip.classList.contains('is-hidden')) return;
                var toggle = getToggleCheckbox(chip);
                var submit = getSubmitCheckbox(chip);
                if (!submit) return;
                if (onlyChecked && (!toggle || !toggle.checked)) return;
                submit.checked = toAssigned;
                if (toggle) toggle.checked = false;
            });
            syncPlacement();
            updateMeta();
        }

        chips.forEach(function(chip) {
            var toggle = getToggleCheckbox(chip);
            if (toggle) {
                toggle.addEventListener('change', updateMeta);
            }
        });

        picker.addEventListener('click', function(event) {
            var target = event.target;
            if (!target || !target.matches('[data-action]')) return;
            var action = target.getAttribute('data-action');
            if (action === 'clear-available-search' && availableSearch) {
                availableSearch.value = '';
                updateMeta();
                availableSearch.focus();
                return;
            }
            if (action === 'clear-assigned-search' && assignedSearch) {
                assignedSearch.value = '';
                updateMeta();
                assignedSearch.focus();
                return;
            }
            if (action === 'add-selected') return moveMatching(availableList, true, true);
            if (action === 'remove-selected') return moveMatching(assignedList, false, true);
            if (action === 'add-filtered' || action === 'add-filtered-all') return moveMatching(availableList, true, false);
            if (action === 'remove-filtered') return moveMatching(assignedList, false, false);
            if (action === 'remove-all') {
                chips.forEach(function(chip) {
                    var submit = getSubmitCheckbox(chip);
                    var toggle = getToggleCheckbox(chip);
                    if (submit) submit.checked = false;
                    if (toggle) toggle.checked = false;
                });
                syncPlacement();
                updateMeta();
            }
        });

        if (availableSearch) availableSearch.addEventListener('input', updateMeta);
        if (assignedSearch) assignedSearch.addEventListener('input', updateMeta);

        syncPlacement();
        updateMeta();
    });
})();
</script>
</body>
</html>

