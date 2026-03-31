<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.net.URLEncoder" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/epms_json.jspf" %>
<%@ include file="../includes/epms_parse.jspf" %>
<%! 
    private static class MeterTreeRequest {
        String action;
        Integer relationId;
        Integer parentId;
        Integer childId;
        Integer sortOrder;
        boolean isActive;
        String note;
    }

    private static class MeterTreePageContext {
        Integer editId;
        Integer parentFilterId;
        String childPanelQ;
        Integer addParentId;
        String parentFilterQs;
        String childPanelQEncoded;
        String childPanelFilterQs;
    }

    private static MeterTreePageContext buildMeterTreePageContext(javax.servlet.http.HttpServletRequest request) {
        MeterTreePageContext ctx = new MeterTreePageContext();
        ctx.editId = parseNullableInt(request.getParameter("edit_id"));
        ctx.parentFilterId = parseNullableInt(request.getParameter("parent_filter"));
        ctx.childPanelQ = request.getParameter("child_panel_q");
        if (ctx.childPanelQ == null) ctx.childPanelQ = "";
        ctx.childPanelQ = ctx.childPanelQ.trim();
        ctx.addParentId = parseNullableInt(request.getParameter("add_parent_id"));
        if (ctx.addParentId == null) ctx.addParentId = parseNullableInt(request.getParameter("parent_meter_id"));
        ctx.parentFilterQs = (ctx.parentFilterId == null) ? "" : ("&parent_filter=" + ctx.parentFilterId);
        ctx.childPanelQEncoded = "";
        try { ctx.childPanelQEncoded = URLEncoder.encode(ctx.childPanelQ, "UTF-8"); } catch (Exception ignore) {}
        ctx.childPanelFilterQs = ctx.childPanelQ.isEmpty() ? "" : ("&child_panel_q=" + ctx.childPanelQEncoded);
        return ctx;
    }

    private static MeterTreeRequest buildMeterTreeRequest(javax.servlet.http.HttpServletRequest request) {
        MeterTreeRequest req = new MeterTreeRequest();
        req.action = request.getParameter("action");
        req.relationId = parseNullableInt(request.getParameter("relation_id"));
        req.parentId = parseNullableInt(request.getParameter("parent_meter_id"));
        req.childId = parseNullableInt(request.getParameter("child_meter_id"));
        req.sortOrder = parseNullableInt(request.getParameter("sort_order"));
        req.isActive = parseBoolSafe(request.getParameter("is_active"));
        req.note = request.getParameter("note");
        if (req.note != null) {
            req.note = req.note.trim();
            if (req.note.isEmpty()) req.note = null;
        }
        return req;
    }

    private static String buildChildPanelsAjaxJson(Connection conn, Integer parentFilterId) throws Exception {
        StringBuilder ajaxSql = new StringBuilder();
        ajaxSql.append("SELECT DISTINCT LTRIM(RTRIM(ISNULL(cm.panel_name, ''))) AS panel_name ")
              .append("FROM dbo.meter_tree t ")
              .append("LEFT JOIN dbo.meters cm ON cm.meter_id = t.child_meter_id ")
              .append("WHERE LTRIM(RTRIM(ISNULL(cm.panel_name, ''))) <> '' ");
        List<Object> ajaxParams = new ArrayList<>();
        if (parentFilterId != null) {
            ajaxSql.append("AND t.parent_meter_id = ? ");
            ajaxParams.add(parentFilterId);
        }
        ajaxSql.append("ORDER BY panel_name");

        StringBuilder json = new StringBuilder();
        json.append("{\"ok\":true,\"panels\":[");
        boolean first = true;
        try (PreparedStatement ps = conn.prepareStatement(ajaxSql.toString())) {
            for (int i = 0; i < ajaxParams.size(); i++) ps.setObject(i + 1, ajaxParams.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String p = rs.getString("panel_name");
                    if (p == null) continue;
                    p = p.trim();
                    if (p.isEmpty()) continue;
                    if (!first) json.append(',');
                    json.append('"').append(escJson(p)).append('"');
                    first = false;
                }
            }
        }
        json.append("]}");
        return json.toString();
    }

    private static String validateMeterTreeRequest(MeterTreeRequest req) {
        if (req == null) return "요청이 올바르지 않습니다.";
        if ("add".equalsIgnoreCase(req.action) || "update".equalsIgnoreCase(req.action)) {
            if (req.parentId == null || req.childId == null) return "부모/자식 계측기는 필수입니다.";
            if (req.parentId.intValue() == req.childId.intValue()) return "부모와 자식은 동일할 수 없습니다.";
        }
        if ("update".equalsIgnoreCase(req.action) || "delete".equalsIgnoreCase(req.action)) {
            if (req.relationId == null) return ("delete".equalsIgnoreCase(req.action) ? "삭제 대상 relation_id가 없습니다." : "수정 대상 relation_id가 없습니다.");
        }
        return null;
    }

    private static String validateMeterTreeCycle(Connection conn, MeterTreeRequest req) throws Exception {
        String cycleSql =
            "WITH g AS ( " +
            "  SELECT parent_meter_id, child_meter_id FROM dbo.meter_tree " +
            "  WHERE is_active = 1 " +
            ("update".equalsIgnoreCase(req.action) ? "    AND relation_id <> ? " : "") +
            "), r AS ( " +
            "  SELECT parent_meter_id, child_meter_id FROM g WHERE parent_meter_id = ? " +
            "  UNION ALL " +
            "  SELECT g.parent_meter_id, g.child_meter_id " +
            "  FROM g INNER JOIN r ON g.parent_meter_id = r.child_meter_id " +
            ") " +
            "SELECT TOP 1 1 FROM r WHERE child_meter_id = ?";
        try (PreparedStatement ps = conn.prepareStatement(cycleSql)) {
            int p = 1;
            if ("update".equalsIgnoreCase(req.action)) {
                ps.setInt(p++, req.relationId.intValue());
            }
            ps.setInt(p++, req.childId.intValue());
            ps.setInt(p++, req.parentId.intValue());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return "순환 참조가 발생합니다. (자식 아래로 부모가 이미 연결됨)";
            }
        }
        return null;
    }

    private static String handleMeterTreeAdd(Connection conn, MeterTreeRequest req) {
        String insSql =
            "INSERT INTO dbo.meter_tree " +
            "(parent_meter_id, child_meter_id, is_active, sort_order, note, updated_at) " +
            "VALUES (?, ?, ?, ?, ?, sysutcdatetime())";
        try (PreparedStatement ps = conn.prepareStatement(insSql)) {
            ps.setInt(1, req.parentId.intValue());
            ps.setInt(2, req.childId.intValue());
            ps.setBoolean(3, req.isActive);
            if (req.sortOrder == null) ps.setNull(4, Types.INTEGER); else ps.setInt(4, req.sortOrder.intValue());
            if (req.note == null) ps.setNull(5, Types.NVARCHAR); else ps.setString(5, req.note);
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleMeterTreeUpdate(Connection conn, MeterTreeRequest req) {
        String updSql =
            "UPDATE dbo.meter_tree " +
            "SET parent_meter_id=?, child_meter_id=?, is_active=?, sort_order=?, note=?, updated_at=sysutcdatetime() " +
            "WHERE relation_id=?";
        try (PreparedStatement ps = conn.prepareStatement(updSql)) {
            ps.setInt(1, req.parentId.intValue());
            ps.setInt(2, req.childId.intValue());
            ps.setBoolean(3, req.isActive);
            if (req.sortOrder == null) ps.setNull(4, Types.INTEGER); else ps.setInt(4, req.sortOrder.intValue());
            if (req.note == null) ps.setNull(5, Types.NVARCHAR); else ps.setString(5, req.note);
            ps.setInt(6, req.relationId.intValue());
            int changed = ps.executeUpdate();
            return changed == 0 ? "수정 대상이 없습니다." : null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String handleMeterTreeDelete(Connection conn, MeterTreeRequest req) {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.meter_tree WHERE relation_id=?")) {
            ps.setInt(1, req.relationId.intValue());
            ps.executeUpdate();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }
%>
<%
try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    String msg = request.getParameter("msg");
    String err = null;
    MeterTreePageContext pageCtx = buildMeterTreePageContext(request);
    Integer editId = pageCtx.editId;
    Integer parentFilterId = pageCtx.parentFilterId;
    String childPanelQ = pageCtx.childPanelQ;
    Integer addParentId = pageCtx.addParentId;
    String parentFilterQs = pageCtx.parentFilterQs;
    String childPanelQEncoded = pageCtx.childPanelQEncoded;
    String childPanelFilterQs = pageCtx.childPanelFilterQs;

    List<Map<String, Object>> meters = new ArrayList<>();
    List<Map<String, Object>> rows = new ArrayList<>();
    LinkedHashSet<String> childPanelOptions = new LinkedHashSet<>();
    Map<String, Object> editRow = null;
    Map<Integer, Integer> nodeDepth = new HashMap<>();
    Map<Integer, Integer> nextSortByParent = new HashMap<>();

    String ajax = request.getParameter("ajax");
    if ("child_panels".equalsIgnoreCase(ajax)) {
        response.setContentType("application/json;charset=UTF-8");
        Integer ajaxParentFilterId = parseNullableInt(request.getParameter("parent_filter"));
        try {
            out.print(buildChildPanelsAjaxJson(conn, ajaxParentFilterId));
        } catch (Exception ex) {
            out.print("{\"ok\":false,\"error\":\"" + escJson(ex.getMessage()) + "\"}");
        }
        return;
    }

    try {
        try (Statement st = conn.createStatement()) {
            st.execute(
                "IF OBJECT_ID('dbo.meter_tree', 'U') IS NULL " +
                "BEGIN " +
                "  CREATE TABLE dbo.meter_tree ( " +
                "    relation_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY, " +
                "    parent_meter_id INT NOT NULL, " +
                "    child_meter_id INT NOT NULL, " +
                "    is_active BIT NOT NULL CONSTRAINT DF_meter_tree_active DEFAULT(1), " +
                "    sort_order INT NULL, " +
                "    note NVARCHAR(400) NULL, " +
                "    created_at DATETIME2(7) NOT NULL CONSTRAINT DF_meter_tree_created DEFAULT(sysutcdatetime()), " +
                "    updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_meter_tree_updated DEFAULT(sysutcdatetime()), " +
                "    CONSTRAINT CK_meter_tree_not_self CHECK (parent_meter_id <> child_meter_id), " +
                "    CONSTRAINT UQ_meter_tree_parent_child UNIQUE(parent_meter_id, child_meter_id), " +
                "    CONSTRAINT FK_meter_tree_parent FOREIGN KEY(parent_meter_id) REFERENCES dbo.meters(meter_id), " +
                "    CONSTRAINT FK_meter_tree_child FOREIGN KEY(child_meter_id) REFERENCES dbo.meters(meter_id) " +
                "  ); " +
                "  CREATE INDEX IX_meter_tree_parent ON dbo.meter_tree(parent_meter_id, is_active, sort_order); " +
                "  CREATE INDEX IX_meter_tree_child ON dbo.meter_tree(child_meter_id, is_active); " +
                "END"
            );
        }

        if ("POST".equalsIgnoreCase(request.getMethod())) {
            try {
                MeterTreeRequest formReq = buildMeterTreeRequest(request);
                if ("add".equalsIgnoreCase(formReq.action) || "update".equalsIgnoreCase(formReq.action)) {
                    err = validateMeterTreeRequest(formReq);
                    if (err == null) err = validateMeterTreeCycle(conn, formReq);
                    if (err == null) {
                        if ("add".equalsIgnoreCase(formReq.action)) {
                            err = handleMeterTreeAdd(conn, formReq);
                            if (err == null) {
                                response.sendRedirect("meter_tree_manage.jsp?msg=" + URLEncoder.encode("등록 완료", "UTF-8") + parentFilterQs + childPanelFilterQs + "&add_parent_id=" + formReq.parentId);
                                return;
                            }
                        } else {
                            err = handleMeterTreeUpdate(conn, formReq);
                            if (err == null) {
                                response.sendRedirect("meter_tree_manage.jsp?msg=" + URLEncoder.encode("수정 완료", "UTF-8") + parentFilterQs + childPanelFilterQs);
                                return;
                            }
                        }
                    }
                } else if ("delete".equalsIgnoreCase(formReq.action)) {
                    err = validateMeterTreeRequest(formReq);
                    if (err == null) {
                        err = handleMeterTreeDelete(conn, formReq);
                        if (err == null) {
                            response.sendRedirect("meter_tree_manage.jsp?msg=" + URLEncoder.encode("삭제 완료", "UTF-8") + parentFilterQs + childPanelFilterQs);
                            return;
                        }
                    }
                }
            } catch (Exception postEx) {
                if (err == null || err.trim().isEmpty()) err = postEx.getMessage();
            }
        }

        String meterSql =
            "SELECT meter_id, name, panel_name, building_name " +
            "FROM dbo.meters ORDER BY meter_id";
        try (PreparedStatement ps = conn.prepareStatement(meterSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> m = new HashMap<>();
                m.put("meter_id", rs.getInt("meter_id"));
                m.put("name", rs.getString("name"));
                m.put("panel_name", rs.getString("panel_name"));
                m.put("building_name", rs.getString("building_name"));
                meters.add(m);
            }
        }

        String nextSortSql =
            "SELECT parent_meter_id, " +
            "       CASE WHEN MAX(sort_order) IS NULL THEN COUNT(*) + 1 ELSE MAX(sort_order) + 1 END AS next_sort " +
            "FROM dbo.meter_tree " +
            "GROUP BY parent_meter_id";
        try (PreparedStatement ps = conn.prepareStatement(nextSortSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                nextSortByParent.put(Integer.valueOf(rs.getInt("parent_meter_id")), Integer.valueOf(rs.getInt("next_sort")));
            }
        }

        StringBuilder childPanelOptSql = new StringBuilder();
        childPanelOptSql.append("SELECT DISTINCT LTRIM(RTRIM(ISNULL(cm.panel_name, ''))) AS panel_name ")
                        .append("FROM dbo.meter_tree t ")
                        .append("LEFT JOIN dbo.meters cm ON cm.meter_id = t.child_meter_id ")
                        .append("WHERE LTRIM(RTRIM(ISNULL(cm.panel_name, ''))) <> '' ");
        if (parentFilterId != null) {
            childPanelOptSql.append("AND t.parent_meter_id = ? ");
        }
        childPanelOptSql.append("ORDER BY panel_name");
        try (PreparedStatement ps = conn.prepareStatement(childPanelOptSql.toString())) {
            if (parentFilterId != null) ps.setInt(1, parentFilterId.intValue());
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String cp = rs.getString("panel_name");
                    if (cp == null) continue;
                    cp = cp.trim();
                    if (!cp.isEmpty()) childPanelOptions.add(cp);
                }
            }
        }

        StringBuilder listSql = new StringBuilder();
        listSql.append("SELECT t.relation_id, t.parent_meter_id, t.child_meter_id, t.is_active, t.sort_order, t.note, ")
               .append("       pm.name AS parent_name, pm.panel_name AS parent_panel, ")
               .append("       cm.name AS child_name, cm.panel_name AS child_panel ")
               .append("FROM dbo.meter_tree t ")
               .append("LEFT JOIN dbo.meters pm ON pm.meter_id = t.parent_meter_id ")
               .append("LEFT JOIN dbo.meters cm ON cm.meter_id = t.child_meter_id ")
               .append("WHERE 1=1 ");
        if (parentFilterId != null) {
            listSql.append("AND t.parent_meter_id = ? ");
        }
        if (!childPanelQ.isEmpty()) {
            listSql.append("AND REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(cm.panel_name, ''))), CHAR(9), ''), CHAR(10), ''), CHAR(13), '') ")
                   .append("= REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(?)), CHAR(9), ''), CHAR(10), ''), CHAR(13), '') ");
        }
        listSql.append("ORDER BY t.is_active DESC, t.parent_meter_id, ISNULL(t.sort_order, 999999), t.child_meter_id");

        try (PreparedStatement ps = conn.prepareStatement(listSql.toString())) {
            int idx = 1;
            if (parentFilterId != null) ps.setInt(idx++, parentFilterId.intValue());
            if (!childPanelQ.isEmpty()) ps.setNString(idx++, childPanelQ);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("relation_id", rs.getLong("relation_id"));
                    r.put("parent_meter_id", rs.getInt("parent_meter_id"));
                    r.put("child_meter_id", rs.getInt("child_meter_id"));
                    r.put("is_active", rs.getBoolean("is_active"));
                    r.put("sort_order", rs.getObject("sort_order"));
                    r.put("note", rs.getString("note"));
                    r.put("parent_name", rs.getString("parent_name"));
                    r.put("parent_panel", rs.getString("parent_panel"));
                    r.put("child_name", rs.getString("child_name"));
                    r.put("child_panel", rs.getString("child_panel"));
                    rows.add(r);
                    if (editId != null && editId.longValue() == ((Long)r.get("relation_id")).longValue()) editRow = r;
                }
            }
        }

        // depth 계산(활성 meter_tree 기준): root=0
        Map<Integer, List<Integer>> childrenByParent = new HashMap<>();
        Set<Integer> allNodes = new HashSet<>();
        Set<Integer> childNodes = new HashSet<>();
        try (PreparedStatement ps = conn.prepareStatement("SELECT parent_meter_id, child_meter_id FROM dbo.meter_tree WHERE is_active=1");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                int p = rs.getInt("parent_meter_id");
                int c = rs.getInt("child_meter_id");
                childrenByParent.computeIfAbsent(p, k -> new ArrayList<>()).add(c);
                allNodes.add(p);
                allNodes.add(c);
                childNodes.add(c);
            }
        }

        Deque<Integer> q = new ArrayDeque<>();
        for (Integer n : allNodes) {
            if (!childNodes.contains(n)) {
                nodeDepth.put(n, 0);
                q.add(n);
            }
        }
        if (q.isEmpty()) {
            for (Integer n : allNodes) {
                nodeDepth.put(n, 0);
                q.add(n);
            }
        }
        while (!q.isEmpty()) {
            Integer cur = q.poll();
            int nd = nodeDepth.getOrDefault(cur, 0);
            List<Integer> ch = childrenByParent.get(cur);
            if (ch == null) continue;
            for (Integer c : ch) {
                Integer old = nodeDepth.get(c);
                if (old == null || nd + 1 < old.intValue()) {
                    nodeDepth.put(c, nd + 1);
                    q.add(c);
                }
            }
        }

        for (Map<String, Object> r : rows) {
            Integer p = Integer.valueOf(String.valueOf(r.get("parent_meter_id")));
            Integer c = Integer.valueOf(String.valueOf(r.get("child_meter_id")));
            r.put("parent_depth", nodeDepth.getOrDefault(p, 0));
            r.put("child_depth", nodeDepth.getOrDefault(c, 0));
        }
    } catch (Exception e) {
        err = e.getMessage();
    }
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Meter Tree 관리</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1500px; margin: 0 auto; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eefbf1; border: 1px solid #c2efcc; color: #1f7a38; font-size: 13px; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .section-title { margin: 0 0 8px; font-size: 15px; font-weight: 700; color: #1f3347; }
        .section-card { background:#fff; border:1px solid #ddd; border-radius:10px; box-shadow:0 1px 3px rgba(0,0,0,0.1); padding:12px; margin:12px 0; }
        .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
        .mid-input { width: 220px; }
        .small-input { width: 90px; }
        .wide-input { width: 300px; }
        .btn-mini { padding: 6px 10px; font-size: 12px; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .guide { margin: 8px 0; color: #475569; font-size: 12px; }
        td, th { font-size: 12px; white-space: nowrap; vertical-align: middle; padding: 4px 6px; line-height: 1.15; }
        .tree-table { width: 100%; table-layout: fixed; }
        .tree-table td { overflow: hidden; text-overflow: ellipsis; }
        .table-wrap { width:100%; overflow-x:auto; }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🧭 단선 계층 (meter_tree) 관리</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="guide">
        관계 규칙: 부모/자식 동일 금지, 순환 참조 금지. 이 페이지를 처음 열면 <span class="mono">dbo.meter_tree</span> 테이블이 없을 경우 자동 생성됩니다.
    </div>

    <% if (msg != null && !msg.trim().isEmpty()) { %>
    <div class="ok-box"><%= h(msg) %></div>
    <% } %>
    <% if (err != null && !err.trim().isEmpty()) { %>
    <div class="err-box">오류: <%= h(err) %></div>
    <% } %>

    <div class="section-card">
        <div class="section-title">신규 등록</div>
        <form method="post" class="toolbar">
            <input type="hidden" name="action" value="add" />
            <input type="hidden" name="parent_filter" value="<%= parentFilterId == null ? "" : parentFilterId %>" />
            <input type="hidden" name="child_panel_q" value="<%= h(childPanelQ) %>" />
            부모:
            <select id="add_parent_meter_id" name="parent_meter_id" class="mid-input" required>
                <option value="">선택</option>
                <% for (Map<String, Object> m : meters) { %>
                <option value="<%= h(m.get("meter_id")) %>" <%= String.valueOf(m.get("meter_id")).equals(String.valueOf(addParentId)) ? "selected" : "" %>>
                    #<%= h(m.get("meter_id")) %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
                </option>
                <% } %>
            </select>
            자식:
            <select name="child_meter_id" class="mid-input" required>
                <option value="">선택</option>
                <% for (Map<String, Object> m : meters) { %>
                <option value="<%= h(m.get("meter_id")) %>">
                    #<%= h(m.get("meter_id")) %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
                </option>
                <% } %>
            </select>
            정렬:
            <input id="add_sort_order" type="number" name="sort_order" class="small-input" placeholder="sort" />
            <label>활성 <input type="checkbox" name="is_active" value="1" checked /></label>
            <input type="text" name="note" class="wide-input" placeholder="note" />
            <button type="submit" class="btn-mini">등록</button>
        </form>
    </div>

    <% if (editRow != null) { %>
    <div class="section-card">
        <div class="section-title">수정</div>
        <form method="post" class="toolbar">
            <input type="hidden" name="action" value="update" />
            <input type="hidden" name="parent_filter" value="<%= parentFilterId == null ? "" : parentFilterId %>" />
            <input type="hidden" name="child_panel_q" value="<%= h(childPanelQ) %>" />
            <input type="hidden" name="relation_id" value="<%= h(editRow.get("relation_id")) %>" />
            부모:
            <select name="parent_meter_id" class="mid-input" required>
                <% for (Map<String, Object> m : meters) { %>
                <option value="<%= h(m.get("meter_id")) %>" <%= String.valueOf(m.get("meter_id")).equals(String.valueOf(editRow.get("parent_meter_id"))) ? "selected" : "" %>>
                    #<%= h(m.get("meter_id")) %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
                </option>
                <% } %>
            </select>
            자식:
            <select name="child_meter_id" class="mid-input" required>
                <% for (Map<String, Object> m : meters) { %>
                <option value="<%= h(m.get("meter_id")) %>" <%= String.valueOf(m.get("meter_id")).equals(String.valueOf(editRow.get("child_meter_id"))) ? "selected" : "" %>>
                    #<%= h(m.get("meter_id")) %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
                </option>
                <% } %>
            </select>
            정렬:
            <input type="number" name="sort_order" class="small-input" value="<%= h(editRow.get("sort_order")) %>" />
            <label>활성 <input type="checkbox" name="is_active" value="1" <%= ((Boolean)editRow.get("is_active")) ? "checked" : "" %> /></label>
            <input type="text" name="note" class="wide-input" value="<%= h(editRow.get("note")) %>" />
            <button type="submit" class="btn-mini">수정 저장</button>
            <button type="button" class="btn-mini" onclick="location.href='meter_tree_manage.jsp?<%= (parentFilterId != null ? ("parent_filter=" + parentFilterId + "&") : "") %>child_panel_q=<%= childPanelQEncoded %>'">취소</button>
        </form>
    </div>
    <% } %>

    <div class="section-card">
        <div class="section-title">목록</div>
        <form id="list_filter_form" method="get" class="toolbar" style="margin-bottom:8px;">
            <label>부모 계측기:</label>
            <select id="list_parent_filter" name="parent_filter" class="mid-input">
                <option value="">전체</option>
                <% for (Map<String, Object> m : meters) { %>
                <option value="<%= h(m.get("meter_id")) %>" <%= String.valueOf(m.get("meter_id")).equals(String.valueOf(parentFilterId)) ? "selected" : "" %>>
                    #<%= h(m.get("meter_id")) %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
                </option>
                <% } %>
            </select>
            <label>child 판넬명:</label>
            <select id="list_child_panel_q" name="child_panel_q" class="mid-input">
                <option value="">전체</option>
                <% for (String cp : childPanelOptions) { %>
                <option value="<%= h(cp) %>" <%= cp.equals(childPanelQ) ? "selected" : "" %>><%= h(cp) %></option>
                <% } %>
            </select>
            <button id="list_filter_submit" type="submit" class="btn-mini">검색</button>
            <button type="button" class="btn-mini" onclick="location.href='meter_tree_manage.jsp'">초기화</button>
        </form>

        <div class="table-wrap">
            <table class="tree-table">
                <colgroup>
                    <col style="width:70px;">
                    <col style="width:260px;">
                    <col style="width:70px;">
                    <col style="width:300px;">
                    <col style="width:70px;">
                    <col style="width:80px;">
                    <col style="width:90px;">
                    <col style="width:130px;">
                    <col style="width:130px;">
                </colgroup>
                <thead>
                <tr>
                    <th>relation_id</th>
                    <th>parent</th>
                    <th>p_depth</th>
                    <th>child</th>
                    <th>c_depth</th>
                    <th>is_active</th>
                    <th>sort_order</th>
                    <th>note</th>
                    <th>동작</th>
                </tr>
                </thead>
                <tbody>
                <% if (rows.isEmpty()) { %>
                <tr><td colspan="9">데이터가 없습니다.</td></tr>
                <% } else { %>
                <% for (Map<String, Object> r : rows) { %>
                <tr>
                    <td class="mono"><%= h(r.get("relation_id")) %></td>
                    <td>#<%= h(r.get("parent_meter_id")) %> - <%= h(r.get("parent_name")) %> (<%= h(r.get("parent_panel")) %>)</td>
                    <td class="mono"><%= h(r.get("parent_depth")) %></td>
                    <td>#<%= h(r.get("child_meter_id")) %> - <%= h(r.get("child_name")) %> (<%= h(r.get("child_panel")) %>)</td>
                    <td class="mono"><%= h(r.get("child_depth")) %></td>
                    <td><%= ((Boolean)r.get("is_active")) ? "1" : "0" %></td>
                    <td><%= h(r.get("sort_order")) %></td>
                    <td><%= h(r.get("note")) %></td>
                    <td>
                        <button type="button" class="btn-mini" onclick="location.href='meter_tree_manage.jsp?edit_id=<%= h(r.get("relation_id")) %><%= (parentFilterId != null ? ("&parent_filter=" + parentFilterId) : "") %>&child_panel_q=<%= childPanelQEncoded %>'">편집</button>
                        <form method="post" style="display:inline;" onsubmit="return confirm('정말 삭제하시겠습니까?');">
                            <input type="hidden" name="action" value="delete" />
                            <input type="hidden" name="parent_filter" value="<%= parentFilterId == null ? "" : parentFilterId %>" />
                            <input type="hidden" name="child_panel_q" value="<%= h(childPanelQ) %>" />
                            <input type="hidden" name="relation_id" value="<%= h(r.get("relation_id")) %>" />
                            <button type="submit" class="btn-mini">삭제</button>
                        </form>
                    </td>
                </tr>
                <% } %>
                <% } %>
                </tbody>
            </table>
        </div>
    </div>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
const nextSortByParent = {
<%
    boolean firstNs = true;
    for (Map.Entry<Integer, Integer> e : nextSortByParent.entrySet()) {
        if (!firstNs) out.print(",");
        out.print("\"" + e.getKey() + "\":" + e.getValue());
        firstNs = false;
    }
%>
};
const addParentSel = document.getElementById('add_parent_meter_id');
const addSortInput = document.getElementById('add_sort_order');

function applyNextSortFromParent(force) {
    if (!addParentSel || !addSortInput) return;
    const pid = addParentSel.value;
    if (!pid) return;
    const nextSort = (nextSortByParent[pid] == null) ? 1 : nextSortByParent[pid];
    if (force || !addSortInput.value) addSortInput.value = String(nextSort);
}

if (addParentSel) {
    addParentSel.addEventListener('change', function() { applyNextSortFromParent(true); });
}
applyNextSortFromParent(false);

(function(){
    const parentSel = document.getElementById('list_parent_filter');
    const childPanelSel = document.getElementById('list_child_panel_q');
    const listFilterForm = document.getElementById('list_filter_form');
    const listFilterSubmit = document.getElementById('list_filter_submit');
    if (!parentSel || !childPanelSel || !listFilterForm) return;
    let lastParentFilter = parentSel.value || '';

    function buildApiUrl(parentFilter) {
        const u = new URL(window.location.href);
        u.searchParams.set('ajax', 'child_panels');
        if (parentFilter) u.searchParams.set('parent_filter', parentFilter);
        else u.searchParams.delete('parent_filter');
        u.searchParams.delete('child_panel_q');
        u.searchParams.delete('edit_id');
        u.searchParams.delete('msg');
        return u.toString();
    }

    async function reloadChildPanelOptions() {
        const currentParent = parentSel.value || '';
        if (currentParent === lastParentFilter) return;
        lastParentFilter = currentParent;

        const prev = childPanelSel.value || '';
        try {
            const res = await fetch(buildApiUrl(currentParent), { headers: { 'Accept': 'application/json' } });
            const data = await res.json();
            if (!data || !data.ok || !Array.isArray(data.panels)) return;

            childPanelSel.innerHTML = '';
            const allOpt = document.createElement('option');
            allOpt.value = '';
            allOpt.textContent = '전체';
            childPanelSel.appendChild(allOpt);

            let matched = false;
            data.panels.forEach(function(panel){
                const v = String(panel || '');
                if (!v) return;
                const opt = document.createElement('option');
                opt.value = v;
                opt.textContent = v;
                if (v === prev) {
                    opt.selected = true;
                    matched = true;
                }
                childPanelSel.appendChild(opt);
            });

            if (!matched) childPanelSel.value = '';
        } catch (e) {
            console.warn('child panel options reload failed', e);
        }
    }

    parentSel.addEventListener('change', reloadChildPanelOptions);
    childPanelSel.addEventListener('change', function(){
        if (listFilterSubmit && typeof listFilterSubmit.click === 'function') {
            listFilterSubmit.click();
        } else if (typeof listFilterForm.requestSubmit === 'function') {
            listFilterForm.requestSubmit();
        } else {
            listFilterForm.submit();
        }
    });
})();
</script>
<%
} // end try-with-resources
%>
</body>
</html>
