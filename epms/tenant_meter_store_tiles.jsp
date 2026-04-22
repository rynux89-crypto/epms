<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<%@ page import="epms.remote.*" %>
<%@ include file="../includes/epms_html.jspf" %>
<%
String q = request.getParameter("q");
String floor = request.getParameter("floor");
String zone = request.getParameter("zone");
String category = request.getParameter("category");
String openedOn = request.getParameter("opened_on");
String contact = request.getParameter("contact");
if (q == null) q = "";
if (floor == null) floor = "";
if (zone == null) zone = "";
if (category == null) category = "";
if (openedOn == null) openedOn = "";
if (contact == null) contact = "";
q = q.trim();
floor = floor.trim();
zone = zone.trim();
category = category.trim();
openedOn = openedOn.trim();
contact = contact.trim();

RemoteReadingService remoteReadingService = new RemoteReadingService();
MeterStoreTilesPageData pageData = null;
String err = null;
try {
    pageData = remoteReadingService.loadMeterStoreTilesPage(q, floor, zone, category, openedOn, contact);
} catch (Exception e) {
    err = e.getMessage();
}

List<String> floorOptions = pageData == null ? Collections.<String>emptyList() : pageData.getFloorOptions();
List<String> zoneOptions = pageData == null ? Collections.<String>emptyList() : pageData.getZoneOptions();
List<String> categoryOptions = pageData == null ? Collections.<String>emptyList() : pageData.getCategoryOptions();
List<MeterStoreTileRow> tiles = pageData == null ? Collections.<MeterStoreTileRow>emptyList() : pageData.getTiles();
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>&#47588;&#51109; &#51204;&#47141;&#49324;&#50857;&#47049; &#51312;&#54924;</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        body{max-width:1680px;margin:14px auto;padding:0 10px}
        .page-wrap{display:grid;gap:12px}
        .page-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
        .top-links{display:flex;flex-wrap:wrap;gap:10px;margin-top:-4px}
        .top-links .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:9px 16px;border-radius:999px;background:linear-gradient(180deg,var(--primary) 0%,#1659c9 100%);color:#fff;text-decoration:none;box-shadow:0 6px 16px rgba(31,111,235,.22)}
        .top-links .btn:hover{background:linear-gradient(180deg,var(--primary-hover) 0%,#10479f 100%);color:#fff;transform:translateY(-1px);box-shadow:0 10px 20px rgba(21,87,186,.24)}
        .panel-box{padding:12px;border:1px solid #d9dfe8;border-radius:6px;background:#fff;box-shadow:none}
        .filter-row{display:grid;grid-template-columns:repeat(6,minmax(0,1fr)) auto;gap:8px;align-items:end}
        .field{display:grid;gap:4px}
        .field label{font-size:11px;color:var(--muted);font-weight:700}
        .field label,.field input,.field select,.btn{font-family:"Noto Sans KR","Segoe UI",Arial,sans-serif}
        .tile-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}
        .meter-tile{border:1px solid #d9dfe8;border-radius:6px;background:#fff;padding:10px;box-shadow:none}
        .tile-head{display:flex;justify-content:flex-start;gap:8px;align-items:flex-start;margin-bottom:10px}
        .tile-title h2{margin:0;font-size:16px;line-height:1.2}
        .tile-title h2 a{color:inherit;text-decoration:none}
        .tile-title h2 a:hover{color:var(--primary)}
        .tile-meta{color:var(--muted);font-size:11px;margin-top:3px}
        .kv{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-bottom:8px}
        .kv-card{border:1px solid #e2e8f0;border-radius:6px;padding:8px;background:#fafbfc}
        .kv-card .label{font-size:11px;color:var(--muted);font-weight:700}
        .kv-card .value{margin-top:4px;font-size:14px;font-weight:700;color:#1f3147}
        .kv-card .unit{display:block;margin-top:4px;font-size:10px;color:var(--muted);font-weight:700}
        .store-list{display:flex;flex-wrap:wrap;gap:6px}
        .store-chip{display:inline-flex;align-items:center;padding:6px 10px;border-radius:999px;background:#f5f7fa;color:#334155;border:1px solid #d9dfe8;font-size:12px;font-weight:700;text-decoration:none}
        .store-chip:hover{color:var(--primary);border-color:#bfd3f2;background:#f8fbff}
        .empty-note{padding:16px;border:1px dashed #cbd5e1;border-radius:8px;color:var(--muted);text-align:center;background:#fff}
        .err-box{margin:0;padding:12px 14px;border-radius:8px;background:#fff1f1;border:1px solid #ffc9c9;color:#b42318;font-weight:700}
        .page-footer{margin-top:18px;text-align:center;color:#6d8298;font-size:12px}
        @media (max-width:1500px){.tile-grid{grid-template-columns:repeat(4,minmax(0,1fr))}.filter-row{grid-template-columns:repeat(3,minmax(0,1fr)) auto}}
        @media (max-width:1200px){.tile-grid{grid-template-columns:repeat(3,minmax(0,1fr))}.filter-row{grid-template-columns:repeat(2,minmax(0,1fr))}}
        @media (max-width:900px){.tile-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.filter-row{grid-template-columns:1fr}}
        @media (max-width:760px){.tile-grid,.filter-row,.kv{grid-template-columns:1fr}.tile-title h2{font-size:22px}}
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="page-head">
        <div>
            <h1>&#47588;&#51109; &#51204;&#47141;&#49324;&#50857;&#47049; &#51312;&#54924;</h1>
            <p>&#54788;&#51116; &#50976;&#54952;&#54620; &#47588;&#51109;-&#44228;&#52769;&#44592; &#50672;&#44208;&#51012; &#44592;&#51456;&#51004;&#47196; &#47588;&#51109;&#51032; &#51204;&#47141; &#49324;&#50857; &#54788;&#54889;&#51012; &#54869;&#51064;&#54633;&#45768;&#45796;.</p>
        </div>
        <div class="top-links">
            <a class="btn" href="tenant_meter_map_manage.jsp">&#47588;&#51109;-&#44228;&#52769;&#44592; &#50672;&#44208; &#44288;&#47532;</a>
            <a class="btn" href="tenant_store_manage.jsp">&#47588;&#51109; &#44288;&#47532;</a>
            <a class="btn" href="tenant_billing_manage.jsp">&#50900; &#51221;&#49328;</a>
            <a class="btn" href="epms_main.jsp">EPMS &#54856;</a>
        </div>
    </div>

    <% if (err != null && !err.trim().isEmpty()) { %>
    <div class="err-box"><%= h(err) %></div>
    <% } %>

    <div class="panel-box">
        <form method="get" class="filter-row">
            <div class="field">
                <label>&#52789;</label>
                <select name="floor">
                    <option value="">&#51204;&#52404;</option>
                    <% for (String opt : floorOptions) { %>
                    <option value="<%= h(opt) %>" <%= opt.equals(floor) ? "selected" : "" %>><%= h(opt) %></option>
                    <% } %>
                </select>
            </div>
            <div class="field">
                <label>&#44396;&#50669;</label>
                <select name="zone">
                    <option value="">&#51204;&#52404;</option>
                    <% for (String opt : zoneOptions) { %>
                    <option value="<%= h(opt) %>" <%= opt.equals(zone) ? "selected" : "" %>><%= h(opt) %></option>
                    <% } %>
                </select>
            </div>
            <div class="field">
                <label>&#50629;&#51333;</label>
                <select name="category">
                    <option value="">&#51204;&#52404;</option>
                    <% for (String opt : categoryOptions) { %>
                    <option value="<%= h(opt) %>" <%= opt.equals(category) ? "selected" : "" %>><%= h(opt) %></option>
                    <% } %>
                </select>
            </div>
            <div class="field">
                <label>&#50724;&#54532;&#51068;</label>
                <input type="date" name="opened_on" value="<%= h(openedOn) %>">
            </div>
            <div class="field">
                <label>&#45812;&#45817;&#51088;</label>
                <input type="text" name="contact" value="<%= h(contact) %>" placeholder="&#45812;&#45817;&#51088;">
            </div>
            <div class="field">
                <label>&#44160;&#49353;</label>
                <input type="text" name="q" value="<%= h(q) %>" placeholder="&#44228;&#52769;&#44592;&#47749;, &#47588;&#51109;&#47749;, &#44396;&#50669;, &#45812;&#45817;&#51088;">
            </div>
            <div class="actions"><button type="submit" class="btn btn-primary">&#51312;&#54924;</button></div>
        </form>
    </div>

    <% if (tiles.isEmpty()) { %>
    <div class="empty-note">&#54788;&#51116; &#51312;&#44148;&#50640; &#47582;&#45716; &#50672;&#44208; &#47588;&#51109;&#51060; &#50630;&#49845;&#45768;&#45796;.</div>
    <% } else { %>
    <div class="tile-grid">
        <% for (MeterStoreTileRow tile : tiles) { %>
        <div class="meter-tile">
            <div class="tile-head">
                <div class="tile-title">
                    <h2><a href="tenant_store_energy_detail.jsp?store_id=<%= h(tile.getDisplayStoreId()) %>&meter_id=<%= h(tile.getMeterId()) %>"><%= h(tile.getTileTitle()) %><%= h(tile.getLocationText()) %></a></h2>
                    <div class="tile-meta">#<%= h(tile.getMeterId()) %> / <%= h(tile.getMeterName()) %> / <%= h(tile.getBuildingName()) %> / <%= h(tile.getPanelName()) %></div>
                </div>
            </div>
            <div class="kv">
                <div class="kv-card">
                    <div class="label">&#51648;&#45212;&#45804; &#49324;&#50857;&#47049;</div>
                    <div class="value"><%= tile.getLastMonthKwh() == null ? "-" : String.format(java.util.Locale.US, "%,.1f", tile.getLastMonthKwh().doubleValue()) %></div>
                    <span class="unit">kWh</span>
                </div>
                <div class="kv-card">
                    <div class="label">&#54788;&#51116; &#49324;&#50857;&#47049;</div>
                    <div class="value"><%= tile.getResolvedCurrentKw() == null ? "-" : String.format(java.util.Locale.US, "%,.2f", tile.getResolvedCurrentKw().doubleValue()) %></div>
                    <span class="unit">kW</span>
                </div>
            </div>
            <div class="store-list">
                <% for (String chip : tile.getStoreChipLabels()) { %>
                <a class="store-chip" href="tenant_store_energy_detail.jsp?store_id=<%= h(tile.getDisplayStoreId()) %>&meter_id=<%= h(tile.getMeterId()) %>"><%= h(chip) %></a>
                <% } %>
            </div>
        </div>
        <% } %>
    </div>
    <% } %>
</div>
<footer class="page-footer">EPMS Dashboard | SNUT CNT</footer>
</body>
</html>
