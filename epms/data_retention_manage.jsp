<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.time.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static class DataRetentionRequest {
        int retentionYears;
        String action;
        boolean isPost;
        boolean doBackup;
        boolean doDelete;
        boolean confirmedDelete;
        String backupPath;
        LocalDate today;
        LocalDate cutoffDate;
        Timestamp cutoffTimestamp;
    }

    private static class DataRetentionResult {
        List<Map<String, String>> activeTargets = new ArrayList<>();
        LinkedHashMap<String, Long> previewCounts = new LinkedHashMap<>();
        long previewTotalCount = 0L;
        long deletedTotalCount = 0L;
        String successMsg;
        String errorMsg;
        String backupPathUsed;
    }

    private static boolean tableExists(Connection conn, String schema, String table) throws SQLException {
        String sql = "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, schema);
            ps.setString(2, table);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    private static String resolveTimeColumn(Connection conn, String schema, String table, List<String> candidates) throws SQLException {
        String sql = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?";
        Set<String> cols = new HashSet<>();
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, schema);
            ps.setString(2, table);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) cols.add(rs.getString("COLUMN_NAME").toLowerCase(Locale.ROOT));
            }
        }
        for (String c : candidates) {
            if (cols.contains(c.toLowerCase(Locale.ROOT))) return c;
        }
        return null;
    }

    private static int parseRetentionYears(String value) {
        try {
            int y = Integer.parseInt(value);
            if (y == 5 || y == 7 || y == 10) return y;
        } catch (Exception ignore) {}
        return 5;
    }

    private static String defaultBackupPath(LocalDate today) {
        return "F:\\backup\\epms_" + today + ".bak";
    }

    private static DataRetentionRequest buildDataRetentionRequest(javax.servlet.http.HttpServletRequest request) {
        DataRetentionRequest req = new DataRetentionRequest();
        req.retentionYears = parseRetentionYears(request.getParameter("retention_years"));
        req.action = request.getParameter("action");
        req.isPost = "POST".equalsIgnoreCase(request.getMethod());
        req.doBackup = req.isPost && "backup".equalsIgnoreCase(req.action);
        req.doDelete = req.isPost && "delete".equalsIgnoreCase(req.action);
        req.confirmedDelete = "Y".equalsIgnoreCase(request.getParameter("confirm_delete"));
        req.today = LocalDate.now();
        req.cutoffDate = req.today.minusYears(req.retentionYears);
        req.cutoffTimestamp = Timestamp.valueOf(req.cutoffDate.atStartOfDay());

        String backupPath = request.getParameter("backup_path");
        if (backupPath == null || backupPath.trim().isEmpty()) {
            req.backupPath = defaultBackupPath(req.today);
        } else {
            req.backupPath = backupPath.trim();
        }
        return req;
    }

    private static List<Map<String, String>> findActiveTargets(Connection conn, List<String> candidateTables, List<String> timeCols) throws SQLException {
        List<Map<String, String>> activeTargets = new ArrayList<>();
        for (String fqtn : candidateTables) {
            String[] p = fqtn.split("\\.");
            if (p.length != 2) continue;
            String schema = p[0];
            String table = p[1];

            if (!tableExists(conn, schema, table)) continue;
            String timeCol = resolveTimeColumn(conn, schema, table, timeCols);
            if (timeCol == null) continue;

            Map<String, String> target = new HashMap<>();
            target.put("fqtn", fqtn);
            target.put("timeCol", timeCol);
            activeTargets.add(target);
        }
        return activeTargets;
    }

    private static void refreshPreviewCounts(Connection conn, DataRetentionRequest req, DataRetentionResult result) throws SQLException {
        result.previewCounts.clear();
        result.previewTotalCount = 0L;
        for (Map<String, String> t : result.activeTargets) {
            String fqtn = t.get("fqtn");
            String timeCol = t.get("timeCol");
            String cntSql = "SELECT COUNT(*) AS cnt FROM " + fqtn + " WHERE " + timeCol + " < ?";
            try (PreparedStatement ps = conn.prepareStatement(cntSql)) {
                ps.setTimestamp(1, req.cutoffTimestamp);
                try (ResultSet rs = ps.executeQuery()) {
                    long cnt = rs.next() ? rs.getLong("cnt") : 0L;
                    result.previewCounts.put(fqtn, cnt);
                    result.previewTotalCount += cnt;
                }
            }
        }
    }

    private static String executeBackup(Connection conn, String backupPath) {
        if (backupPath == null || backupPath.length() < 3) return "백업 경로를 확인해 주세요.";
        String backupSql =
            "DECLARE @p nvarchar(4000) = ?; " +
            "DECLARE @sql nvarchar(max) = N'BACKUP DATABASE [epms] TO DISK = N''' + REPLACE(@p, '''', '''''') + N''' WITH INIT, COMPRESSION, STATS = 10'; " +
            "EXEC(@sql);";
        try (PreparedStatement ps = conn.prepareStatement(backupSql)) {
            ps.setString(1, backupPath);
            ps.execute();
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String executeDelete(Connection conn, DataRetentionRequest req, DataRetentionResult result) {
        boolean oldAutoCommit = true;
        try {
            oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);
            result.deletedTotalCount = 0L;
            for (Map<String, String> t : result.activeTargets) {
                String fqtn = t.get("fqtn");
                String timeCol = t.get("timeCol");
                String delSql = "DELETE FROM " + fqtn + " WHERE " + timeCol + " < ?";
                try (PreparedStatement ps = conn.prepareStatement(delSql)) {
                    ps.setTimestamp(1, req.cutoffTimestamp);
                    result.deletedTotalCount += ps.executeUpdate();
                }
            }
            conn.commit();
            return null;
        } catch (Exception e) {
            try { conn.rollback(); } catch (Exception ignore) {}
            return e.getMessage();
        } finally {
            try { conn.setAutoCommit(oldAutoCommit); } catch (Exception ignore) {}
        }
    }
%>
<%
    try (Connection conn = openDbConnection()) {
    request.setCharacterEncoding("UTF-8");

    DataRetentionRequest req = buildDataRetentionRequest(request);
    List<String> candidateTables = Arrays.asList(
        "dbo.measurements",
        "dbo.harmonic_measurements",
        "dbo.flicker_measurements",
        "dbo.voltage_events",
        "dbo.device_events",
        "dbo.voltage_event_log",
        "dbo.alarm_log",
        "dbo.plc_ai_samples",
        "dbo.plc_di_samples"
    );
    List<String> timeCols = Arrays.asList("measured_at", "triggered_at", "event_time", "event_at", "occurred_at", "created_at", "reg_time");
    DataRetentionResult result = new DataRetentionResult();

    try {
        if (req.doBackup) {
            result.backupPathUsed = req.backupPath;
            String backupErr = executeBackup(conn, req.backupPath);
            if (backupErr != null) {
                result.errorMsg = backupErr;
            } else {
                result.successMsg = "DB 백업 완료: " + result.backupPathUsed;
            }
        }

        result.activeTargets = findActiveTargets(conn, candidateTables, timeCols);
        refreshPreviewCounts(conn, req, result);

        if (req.doDelete) {
            if (!req.confirmedDelete) {
                result.errorMsg = "삭제를 확인했습니다 체크박스를 선택해 주세요.";
            } else if (result.activeTargets.isEmpty()) {
                result.errorMsg = "삭제 가능한 대상 테이블을 찾지 못했습니다.";
            } else if (result.previewTotalCount <= 0) {
                result.successMsg = "삭제 대상 데이터가 없습니다.";
            } else {
                String deleteErr = executeDelete(conn, req, result);
                if (deleteErr != null) {
                    result.errorMsg = deleteErr;
                } else {
                    result.successMsg = "삭제 완료: 총 " + result.deletedTotalCount + "건";
                    refreshPreviewCounts(conn, req, result);
                }
            }
        }
    } catch (Exception e) {
        if (req.doBackup && result.backupPathUsed != null) {
            result.errorMsg = "[백업 경로: " + result.backupPathUsed + "] " + e.getMessage();
        } else {
            result.errorMsg = e.getMessage();
        }
    }
%>
<!doctype html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Data 관리 - 이력 데이터 삭제</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-meter-status.page-alarm { height: auto; min-height: 100vh; overflow: auto; }
        .page-meter-status.page-alarm .dash { height: auto; min-height: 100vh; }
        .page-meter-status.page-alarm .dash-main { overflow: auto; }
        .warn-box { margin: 0; padding: 10px 12px; border-radius: 8px; background: #fff3cd; border: 1px solid #ffe08a; color: #7a5800; font-size: 13px; font-weight: 700; }
        .ok-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #ebfff1; border: 1px solid #b7ebc6; color: #0f7a2a; font-size: 13px; font-weight: 700; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .panel_s form { margin: 0; padding: 0; background: transparent; box-shadow: none; }
        .row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
        .btn-danger { background: #b42318; color: #fff; border: 1px solid #9c1d14; border-radius: 6px; padding: 8px 12px; cursor: pointer; }
        .btn-danger:hover { background: #8f1b13; }
        .btn-danger:disabled { background: #c9c9c9; border-color: #bdbdbd; cursor: not-allowed; }
        .btn-backup { background: #0b7285; color: #fff; border: 1px solid #0a6070; border-radius: 6px; padding: 8px 12px; cursor: pointer; }
        .btn-backup:hover { background: #095b69; }
        .preview-box { margin-top: 0; }
        .preview-box table { margin-bottom: 0; }
        .label { min-width: 110px; text-align: left; font-weight: 700; }
        .path-input { min-width: 460px; max-width: 100%; }
        .sub-title { font-weight: 700; margin-bottom: 8px; }
        .top-actions { display:flex; gap:8px; align-items:center; }
        .content-stack { display:flex; flex-direction:column; gap:12px; min-height:0; }
        .row-tight { margin-bottom: 6px; }
        .row-danger { margin-top: 10px; }
        @media (max-width: 960px) { .path-input { min-width: 260px; } }
    </style>
</head>
<body class="page-meter-status page-alarm">
<div class="dash">
    <div class="dash-top">
        <div class="title-bar">
            <h2>🧹 Data 관리 - 이력 데이터 삭제</h2>
            <div class="inline-actions">
                <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
            </div>
        </div>
    </div>

    <div class="dash-main content-stack">
        <section class="panel_s">
            <div class="warn-box">
                주의: 삭제는 되돌릴 수 없습니다. 삭제 전 DB 백업을 먼저 실행하세요.
            </div>
            <% if (result.successMsg != null) { %>
            <div class="ok-box"><%= h(result.successMsg) %></div>
            <% } %>
            <% if (result.errorMsg != null) { %>
            <div class="err-box"><%= h(result.errorMsg) %></div>
            <% } %>
            <% if (result.backupPathUsed != null) { %>
            <div class="warn-box">이번 백업 요청 경로: <span class="mono"><%= h(result.backupPathUsed) %></span></div>
            <% } %>
        </section>

        <section class="panel_s">
            <form method="post" action="">
                <div class="row">
                    <div class="label">DB 서버 백업 경로</div>
                    <input class="path-input mono" type="text" name="backup_path" value="<%= h(req.backupPath) %>" placeholder="예: F:\backup\epms_2026-02-13.bak" />
                    <input type="hidden" name="retention_years" value="<%= req.retentionYears %>" />
                    <input type="hidden" name="action" value="backup" />
                    <button type="submit" class="btn-backup" onclick="return confirm('입력한 서버 경로로 DB 백업을 실행하시겠습니까?');">DB 백업 실행</button>
                </div>
            </form>
        </section>

        <section class="panel_s">
            <form method="post" action="">
                <input type="hidden" name="backup_path" value="<%= h(req.backupPath) %>" />

                <div class="row row-tight">
                    <div class="label">보관기간</div>
                    <select name="retention_years" required>
                        <option value="5" <%= req.retentionYears == 5 ? "selected" : "" %>>5년</option>
                        <option value="7" <%= req.retentionYears == 7 ? "selected" : "" %>>7년</option>
                        <option value="10" <%= req.retentionYears == 10 ? "selected" : "" %>>10년</option>
                    </select>
                    <button type="button" class="back-btn" onclick="location.href='data_retention_manage.jsp?retention_years='+document.querySelector('select[name=retention_years]').value+'&backup_path='+encodeURIComponent(document.querySelector('input[name=backup_path]').value);">건수 다시 조회</button>
                </div>

                <div class="preview-box">
                    <table>
                        <tbody>
                        <tr>
                            <th>기준일</th>
                            <td class="mono"><%= req.cutoffDate %> 00:00:00</td>
                        </tr>
                        <tr>
                            <th>삭제 범위</th>
                            <td>기준일 이전 데이터 삭제</td>
                        </tr>
                        <% for (Map.Entry<String, Long> e : result.previewCounts.entrySet()) { %>
                        <tr>
                            <th>삭제 대상 (<%= h(e.getKey()) %>)</th>
                            <td><b><%= String.format("%,d", e.getValue()) %></b> 건</td>
                        </tr>
                        <% } %>
                        <tr>
                            <th>삭제 대상 건수 (합계)</th>
                            <td><b><%= String.format("%,d", result.previewTotalCount) %></b> 건</td>
                        </tr>
                        </tbody>
                    </table>
                </div>

                <div class="row row-danger">
                    <label>
                        <input type="checkbox" id="confirmDelete" name="confirm_delete" value="Y" />
                        삭제를 확인했습니다.
                    </label>
                    <input type="hidden" name="action" value="delete" />
                    <button type="submit" id="deleteBtn" class="btn-danger" disabled onclick="return confirm('선택한 기준일로 과거 데이터를 삭제합니다. 계속하시겠습니까?');">삭제 실행</button>
                </div>
            </form>
        </section>
    </div>
    <footer>© EPMS Dashboard | SNUT CNT</footer>
</div>
<script>
(function () {
    const confirmEl = document.getElementById('confirmDelete');
    const deleteBtn = document.getElementById('deleteBtn');
    if (!confirmEl || !deleteBtn) return;
    function syncDeleteButton() { deleteBtn.disabled = !confirmEl.checked; }
    confirmEl.addEventListener('change', syncDeleteButton);
    syncDeleteButton();
})();
</script>
</body>
</html>
<%
    } // end try-with-resources
%>
