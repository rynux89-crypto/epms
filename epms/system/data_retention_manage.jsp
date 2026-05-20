<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.time.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../../includes/dbconfig.jspf" %>
<%@ include file="../../includes/epms_html.jspf" %>
<%@ include file="../../includes/epms_admin_guard.jspf" %>
<%!
    private static class RetentionTargetDef {
        String fqtn;
        String timeCol;
        String label;
        boolean defaultSelected;

        RetentionTargetDef(String fqtn, String timeCol, String label, boolean defaultSelected) {
            this.fqtn = fqtn;
            this.timeCol = timeCol;
            this.label = label;
            this.defaultSelected = defaultSelected;
        }
    }

    private static class DataRetentionRequest {
        int retentionYears;
        String action;
        boolean isPost;
        boolean doBackup;
        boolean doDelete;
        boolean doInitializeOperational;
        boolean doInitializeDb;
        boolean confirmedDelete;
        boolean confirmedInitializeOperational;
        boolean confirmedInitialize;
        String backupPath;
        String cutoffDateInput;
        String initializeOperationalPhrase;
        String initializePhrase;
        boolean acknowledgedMasterDelete;
        boolean usesCustomCutoffDate;
        Set<String> selectedTargets = new LinkedHashSet<>();
        LocalDate today;
        LocalDate cutoffDate;
        Timestamp cutoffTimestamp;
    }

    private static class DataRetentionResult {
        List<Map<String, Object>> activeTargets = new ArrayList<>();
        List<Map<String, Object>> selectedActiveTargets = new ArrayList<>();
        LinkedHashMap<String, Long> previewCounts = new LinkedHashMap<>();
        long previewTotalCount = 0L;
        long deletedTotalCount = 0L;
        long initializedOperationalTableCount = 0L;
        long initializedTableCount = 0L;
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

    private static int parseRetentionYears(String value) {
        try {
            int y = Integer.parseInt(value);
            if (y == 5 || y == 7 || y == 10) return y;
        } catch (Exception ignore) {}
        return 5;
    }

    private static LocalDate parseCutoffDate(String value) {
        try {
            if (value == null || value.trim().isEmpty()) return null;
            return LocalDate.parse(value.trim());
        } catch (Exception ignore) {}
        return null;
    }

    private static String defaultBackupPath(LocalDate today) {
        return "F:\\backup\\epms_" + today + ".bak";
    }

    private static List<String> buildOperationalInitTables() {
        return Arrays.asList(
            "dbo.measurements",
            "dbo.harmonic_measurements",
            "dbo.flicker_measurements",
            "dbo.device_events",
            "dbo.alarm_log",
            "dbo.plc_ai_samples",
            "dbo.plc_di_samples",
            "dbo.daily_measurements",
            "dbo.hourly_measurements",
            "dbo.monthly_measurements",
            "dbo.yearly_measurements",
            "dbo.peak_15min_summary",
            "dbo.epms_building_carbon_daily",
            "dbo.billing_meter_snapshot",
            "dbo.billing_statement",
            "dbo.billing_statement_line"
        );
    }

    private static List<RetentionTargetDef> buildRetentionTargetDefs() {
        return Arrays.asList(
            new RetentionTargetDef("dbo.measurements", "measured_at", "원시 계측값", true),
            new RetentionTargetDef("dbo.harmonic_measurements", "measured_at", "고조파 계측값", true),
            new RetentionTargetDef("dbo.flicker_measurements", "measured_at", "플리커 계측값", true),
            new RetentionTargetDef("dbo.device_events", "event_time", "장비 이벤트", true),
            new RetentionTargetDef("dbo.alarm_log", "triggered_at", "알람 이력", true),
            new RetentionTargetDef("dbo.plc_ai_samples", "measured_at", "PLC AI 샘플", true),
            new RetentionTargetDef("dbo.plc_di_samples", "measured_at", "PLC DI 샘플", true),
            new RetentionTargetDef("dbo.daily_measurements", "measured_date", "일 집계 계측값", false),
            new RetentionTargetDef("dbo.hourly_measurements", "measured_hour", "시간 집계 계측값", false),
            new RetentionTargetDef("dbo.monthly_measurements", "measured_month", "월 집계 계측값", false),
            new RetentionTargetDef("dbo.yearly_measurements", "measured_year", "연 집계 계측값", false),
            new RetentionTargetDef("dbo.peak_15min_summary", "bucket_at", "15분 피크 집계", false)
        );
    }

    private static DataRetentionRequest buildDataRetentionRequest(javax.servlet.http.HttpServletRequest request, List<RetentionTargetDef> defs) {
        DataRetentionRequest req = new DataRetentionRequest();
        req.retentionYears = parseRetentionYears(request.getParameter("retention_years"));
        req.action = request.getParameter("action");
        req.isPost = "POST".equalsIgnoreCase(request.getMethod());
        req.doBackup = req.isPost && "backup".equalsIgnoreCase(req.action);
        req.doDelete = req.isPost && "delete".equalsIgnoreCase(req.action);
        req.doInitializeOperational = req.isPost && "initialize_operational".equalsIgnoreCase(req.action);
        req.doInitializeDb = req.isPost && "initialize_db".equalsIgnoreCase(req.action);
        req.confirmedDelete = "Y".equalsIgnoreCase(request.getParameter("confirm_delete"));
        req.initializeOperationalPhrase = request.getParameter("initialize_operational_phrase");
        req.confirmedInitializeOperational = "운영초기화".equals(req.initializeOperationalPhrase == null ? "" : req.initializeOperationalPhrase.trim());
        req.initializePhrase = request.getParameter("initialize_phrase");
        req.acknowledgedMasterDelete = "Y".equalsIgnoreCase(request.getParameter("ack_master_delete"));
        req.confirmedInitialize = "DB초기화".equals(req.initializePhrase == null ? "" : req.initializePhrase.trim());
        req.today = LocalDate.now();
        req.cutoffDateInput = request.getParameter("cutoff_date");
        LocalDate customCutoffDate = parseCutoffDate(req.cutoffDateInput);
        req.usesCustomCutoffDate = customCutoffDate != null;
        req.cutoffDate = req.usesCustomCutoffDate ? customCutoffDate : req.today.minusYears(req.retentionYears);
        req.cutoffTimestamp = Timestamp.valueOf(req.cutoffDate.atStartOfDay());
        String[] selected = request.getParameterValues("selected_targets");
        if (selected != null) {
            for (String value : selected) {
                if (value != null && !value.trim().isEmpty()) req.selectedTargets.add(value.trim());
            }
        }
        if (req.selectedTargets.isEmpty()) {
            for (RetentionTargetDef def : defs) {
                if (def.defaultSelected) req.selectedTargets.add(def.fqtn);
            }
        }

        String backupPath = request.getParameter("backup_path");
        if (backupPath == null || backupPath.trim().isEmpty()) {
            req.backupPath = defaultBackupPath(req.today);
        } else {
            req.backupPath = backupPath.trim();
        }
        return req;
    }

    private static List<Map<String, Object>> findActiveTargets(Connection conn, List<RetentionTargetDef> defs, Set<String> selectedTargets) throws SQLException {
        List<Map<String, Object>> activeTargets = new ArrayList<>();
        for (RetentionTargetDef def : defs) {
            String[] p = def.fqtn.split("\\.");
            if (p.length != 2) continue;
            String schema = p[0];
            String table = p[1];

            if (!tableExists(conn, schema, table)) continue;

            Map<String, Object> target = new HashMap<>();
            target.put("fqtn", def.fqtn);
            target.put("timeCol", def.timeCol);
            target.put("label", def.label);
            target.put("selected", Boolean.valueOf(selectedTargets.contains(def.fqtn)));
            activeTargets.add(target);
        }
        return activeTargets;
    }

    private static List<Map<String, Object>> filterSelectedTargets(List<Map<String, Object>> activeTargets) {
        List<Map<String, Object>> selected = new ArrayList<>();
        for (Map<String, Object> target : activeTargets) {
            if (Boolean.TRUE.equals(target.get("selected"))) selected.add(target);
        }
        return selected;
    }

    private static void refreshPreviewCounts(Connection conn, DataRetentionRequest req, DataRetentionResult result) throws SQLException {
        result.previewCounts.clear();
        result.previewTotalCount = 0L;
        for (Map<String, Object> t : result.selectedActiveTargets) {
            String fqtn = String.valueOf(t.get("fqtn"));
            String timeCol = String.valueOf(t.get("timeCol"));
            String cntSql;
            if ("measured_year".equalsIgnoreCase(timeCol)) {
                cntSql = "SELECT COUNT(*) AS cnt FROM " + fqtn + " WHERE " + timeCol + " < ?";
            } else {
                cntSql = "SELECT COUNT(*) AS cnt FROM " + fqtn + " WHERE " + timeCol + " < ?";
            }
            try (PreparedStatement ps = conn.prepareStatement(cntSql)) {
                if ("measured_year".equalsIgnoreCase(timeCol)) {
                    ps.setInt(1, req.cutoffDate.getYear());
                } else if ("measured_date".equalsIgnoreCase(timeCol) || "measured_month".equalsIgnoreCase(timeCol)) {
                    ps.setDate(1, java.sql.Date.valueOf(req.cutoffDate));
                } else {
                    ps.setTimestamp(1, req.cutoffTimestamp);
                }
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
            for (Map<String, Object> t : result.selectedActiveTargets) {
                String fqtn = String.valueOf(t.get("fqtn"));
                String timeCol = String.valueOf(t.get("timeCol"));
                String delSql = "DELETE FROM " + fqtn + " WHERE " + timeCol + " < ?";
                try (PreparedStatement ps = conn.prepareStatement(delSql)) {
                    if ("measured_year".equalsIgnoreCase(timeCol)) {
                        ps.setInt(1, req.cutoffDate.getYear());
                    } else if ("measured_date".equalsIgnoreCase(timeCol) || "measured_month".equalsIgnoreCase(timeCol)) {
                        ps.setDate(1, java.sql.Date.valueOf(req.cutoffDate));
                    } else {
                        ps.setTimestamp(1, req.cutoffTimestamp);
                    }
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

    private static String executeInitializeDb(Connection conn, DataRetentionResult result) {
        boolean oldAutoCommit = true;
        try {
            oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);

            List<String> fqtns = new ArrayList<>();
            String listSql =
                "SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS fqtn " +
                "FROM sys.tables t " +
                "INNER JOIN sys.schemas s ON s.schema_id = t.schema_id " +
                "WHERE s.name = 'dbo' AND t.is_ms_shipped = 0 AND t.name <> 'sysdiagrams' " +
                "ORDER BY t.name";
            try (PreparedStatement ps = conn.prepareStatement(listSql);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) fqtns.add(rs.getString("fqtn"));
            }

            for (String fqtn : fqtns) {
                try (Statement st = conn.createStatement()) {
                    st.execute("ALTER TABLE " + fqtn + " NOCHECK CONSTRAINT ALL");
                }
            }

            for (String fqtn : fqtns) {
                try (Statement st = conn.createStatement()) {
                    st.executeUpdate("DELETE FROM " + fqtn);
                    result.initializedTableCount++;
                }
            }

            String identitySql =
                "SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS fqtn " +
                "FROM sys.tables t " +
                "INNER JOIN sys.schemas s ON s.schema_id = t.schema_id " +
                "WHERE s.name = 'dbo' AND t.is_ms_shipped = 0 AND t.name <> 'sysdiagrams' " +
                "AND OBJECTPROPERTY(t.object_id, 'TableHasIdentity') = 1";
            try (PreparedStatement ps = conn.prepareStatement(identitySql);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String fqtn = rs.getString("fqtn");
                    try (Statement st = conn.createStatement()) {
                        st.execute("DBCC CHECKIDENT ('" + fqtn.replace("[", "").replace("]", "") + "', RESEED, 0)");
                    }
                }
            }

            for (String fqtn : fqtns) {
                try (Statement st = conn.createStatement()) {
                    st.execute("ALTER TABLE " + fqtn + " WITH CHECK CHECK CONSTRAINT ALL");
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

    private static String executeInitializeOperational(Connection conn, DataRetentionResult result) {
        boolean oldAutoCommit = true;
        try {
            oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);

            List<String> operationalTables = buildOperationalInitTables();

            List<String> existingTables = new ArrayList<>();
            for (String fqtn : operationalTables) {
                String[] p = fqtn.split("\\.");
                if (p.length == 2 && tableExists(conn, p[0], p[1])) existingTables.add(fqtn);
            }

            for (String fqtn : existingTables) {
                try (Statement st = conn.createStatement()) {
                    st.execute("ALTER TABLE " + fqtn + " NOCHECK CONSTRAINT ALL");
                }
            }

            for (String fqtn : existingTables) {
                try (Statement st = conn.createStatement()) {
                    st.executeUpdate("DELETE FROM " + fqtn);
                    result.initializedOperationalTableCount++;
                }
            }

            for (String fqtn : existingTables) {
                String normalized = fqtn;
                try (PreparedStatement ps = conn.prepareStatement(
                        "SELECT OBJECTPROPERTY(OBJECT_ID(?), 'TableHasIdentity') AS has_identity")) {
                    ps.setString(1, normalized);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next() && rs.getInt("has_identity") == 1) {
                            try (Statement st = conn.createStatement()) {
                                st.execute("DBCC CHECKIDENT ('" + normalized + "', RESEED, 0)");
                            }
                        }
                    }
                }
            }

            for (String fqtn : existingTables) {
                try (Statement st = conn.createStatement()) {
                    st.execute("ALTER TABLE " + fqtn + " WITH CHECK CHECK CONSTRAINT ALL");
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

    List<RetentionTargetDef> targetDefs = buildRetentionTargetDefs();
    DataRetentionRequest req = buildDataRetentionRequest(request, targetDefs);
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

        result.activeTargets = findActiveTargets(conn, targetDefs, req.selectedTargets);
        result.selectedActiveTargets = filterSelectedTargets(result.activeTargets);
        refreshPreviewCounts(conn, req, result);

        if (req.doDelete) {
            if (!req.confirmedDelete) {
                result.errorMsg = "삭제를 확인했습니다 체크박스를 선택해 주세요.";
            } else if (result.activeTargets.isEmpty()) {
                result.errorMsg = "삭제 가능한 대상 테이블을 찾지 못했습니다.";
            } else if (result.selectedActiveTargets.isEmpty()) {
                result.errorMsg = "삭제할 테이블을 하나 이상 선택해 주세요.";
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
        } else if (req.doInitializeOperational) {
            if (!req.confirmedInitializeOperational) {
                result.errorMsg = "운영 데이터 초기화 확인 문구를 정확히 입력해 주세요.";
            } else {
                String initErr = executeInitializeOperational(conn, result);
                if (initErr != null) {
                    result.errorMsg = initErr;
                } else {
                    result.successMsg = "운영 데이터 초기화 완료: 총 " + result.initializedOperationalTableCount + "개 테이블 데이터를 비웠습니다.";
                    result.activeTargets = findActiveTargets(conn, targetDefs, req.selectedTargets);
                    result.selectedActiveTargets = filterSelectedTargets(result.activeTargets);
                    refreshPreviewCounts(conn, req, result);
                }
            }
        } else if (req.doInitializeDb) {
            if (!req.acknowledgedMasterDelete) {
                result.errorMsg = "마스터/설정 데이터 삭제 확인 체크를 선택해 주세요.";
            } else if (!req.confirmedInitialize) {
                result.errorMsg = "전체 데이터 초기화 확인 문구를 정확히 입력해 주세요.";
            } else {
                String initErr = executeInitializeDb(conn, result);
                if (initErr != null) {
                    result.errorMsg = initErr;
                } else {
                    result.successMsg = "전체 데이터 초기화 완료: 총 " + result.initializedTableCount + "개 테이블 데이터를 비웠습니다.";
                    result.activeTargets = findActiveTargets(conn, targetDefs, req.selectedTargets);
                    result.selectedActiveTargets = filterSelectedTargets(result.activeTargets);
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
        .page-meter-status.page-alarm .dash { height: auto; min-height: 100vh; max-width: 1520px; margin: 0 auto; padding: 0 14px 18px; box-sizing: border-box; }
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
        .date-input { min-width: 180px; }
        .sub-title { font-weight: 700; margin-bottom: 8px; }
        .top-actions { display:flex; gap:8px; align-items:center; }
        .content-stack { display:flex; flex-direction:column; gap:12px; min-height:0; }
        .row-tight { margin-bottom: 6px; }
        .row-danger { margin-top: 10px; }
        .summary-grid { display:grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap:10px; }
        .summary-card { padding:12px 14px; border-radius:10px; border:1px solid #d8e1ea; background:linear-gradient(180deg, #ffffff 0%, #f8fbfd 100%); }
        .summary-label { font-size:11px; font-weight:800; color:#6b7c8d; text-transform:uppercase; letter-spacing:.04em; }
        .summary-value { margin-top:5px; font-size:20px; font-weight:900; color:#18344d; }
        .summary-sub { margin-top:4px; font-size:12px; color:#5b6b7c; }
        .mini-summary-grid { display:grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap:8px; margin-bottom:12px; }
        .mini-summary-card { padding:10px 12px; border:1px solid #dbe5ee; border-radius:10px; background:#fff; }
        .mini-summary-card .mini-label { font-size:11px; font-weight:800; color:#728395; }
        .mini-summary-card .mini-value { margin-top:4px; font-size:18px; font-weight:900; color:#18344d; }
        .section-grid { display:grid; grid-template-columns: 1fr; gap:12px; align-items:start; }
        .action-stack { display:grid; gap:12px; }
        .init-grid { display:grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap:12px; align-items:start; }
        .section-card { border:1px solid #d9e2ec; border-radius:12px; background:#fff; box-shadow:0 1px 2px rgba(15,23,42,.03); overflow:hidden; }
        .section-head { padding:12px 14px; border-bottom:1px solid #e7edf3; background:linear-gradient(180deg, #fbfdff 0%, #f4f8fb 100%); display:flex; justify-content:space-between; align-items:flex-start; gap:10px; }
        .section-head h3 { margin:0; font-size:16px; color:#18344d; }
        .section-head p { margin:4px 0 0; font-size:12px; color:#5f7183; line-height:1.45; }
        .section-body { padding:14px; }
        .split-block { display:grid; grid-template-columns: 1fr; gap:14px; align-items:start; }
        .sub-panel { padding:12px; border:1px solid #e4ebf2; border-radius:10px; background:#fbfdff; }
        .sub-panel h4 { margin:0 0 8px; font-size:14px; color:#18344d; }
        .final-summary { margin-top:12px; padding:12px 14px; border:1px solid #ffd37a; border-radius:10px; background:linear-gradient(180deg,#fff8e6 0%,#fff2cc 100%); color:#7b5600; font-size:13px; font-weight:800; line-height:1.5; }
        .section-tag { display:inline-flex; align-items:center; justify-content:center; min-width:72px; padding:5px 10px; border-radius:999px; font-size:11px; font-weight:800; }
        .tag-safe { background:#e9f7ef; color:#136c3d; border:1px solid #b8e0c8; }
        .tag-warn { background:#fff6df; color:#8c6400; border:1px solid #f4d27c; }
        .tag-danger { background:#fdecec; color:#b42318; border:1px solid #f5b8b3; }
        .section-body .warn-box { margin-bottom:10px; }
        .inline-actions-bar { display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
        .target-grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap:8px 14px; margin:10px 0 12px; }
        .target-item { display:flex; align-items:flex-start; gap:8px; padding:8px 10px; border:1px solid #d6dde6; border-radius:8px; background:#f9fbfd; }
        .target-item small { display:block; color:#66788a; margin-top:2px; }
        .helper-text { font-size:12px; color:#5b6b7c; margin-top:6px; }
        .preview-box table { table-layout: fixed; width:100%; }
        .preview-box table th { width:220px; word-break: keep-all; }
        .preview-box table td { word-break: break-word; }
        .count-tile-grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap:10px; }
        .count-tile { padding:12px; border:1px solid #dce6f0; border-radius:12px; background:linear-gradient(180deg, #ffffff 0%, #f7fbff 100%); box-shadow:0 1px 2px rgba(15,23,42,.03); }
        .count-tile-name { font-weight:800; color:#18344d; line-height:1.35; word-break:break-word; }
        .count-tile-meta { margin-top:6px; font-size:12px; color:#6b7c8d; line-height:1.4; word-break:break-all; }
        .count-tile-value { margin-top:10px; font-size:20px; font-weight:900; color:#0f3f75; }
        .count-tile-sub { margin-top:3px; font-size:11px; color:#7a8b9d; }
        .simple-list { margin:0; padding-left:18px; color:#4c5d70; }
        .simple-list li { margin:4px 0; }
        @media (max-width: 1280px) { .section-grid { grid-template-columns:1fr; } .init-grid { grid-template-columns:1fr; } }
        @media (max-width: 1180px) { .summary-grid, .mini-summary-grid { grid-template-columns:1fr; } }
        @media (max-width: 960px) { .path-input { min-width: 260px; } .section-head { flex-direction:column; } .preview-box table th { width:auto; } }
    </style>
</head>
<body class="page-meter-status page-alarm">
<div class="dash">
    <div class="dash-top">
        <div class="title-bar">
            <h2>Data 관리 - 백업 / 삭제 / 운영 초기화 / 전체 초기화</h2>
            <div class="inline-actions">
                <button class="back-btn" onclick="location.href='../epms_main.jsp'">EPMS 홈</button>
            </div>
        </div>
    </div>

    <div class="dash-main content-stack">
        <section class="panel_s">
            <div class="warn-box">
                주의: 삭제, 운영 데이터 초기화, 전체 데이터 초기화는 되돌릴 수 없습니다. 실행 전 DB 백업을 먼저 수행하세요.
            </div>
            <div class="summary-grid" style="margin-top:12px;">
                <div class="summary-card">
                    <div class="summary-label">백업 경로</div>
                    <div class="summary-value mono" style="font-size:16px;"><%= h(req.backupPath) %></div>
                    <div class="summary-sub">실행 전 DB 서버 경로를 확인하세요.</div>
                </div>
                <div class="summary-card">
                    <div class="summary-label">삭제 기준일</div>
                    <div class="summary-value"><%= h(String.valueOf(req.cutoffDate)) %></div>
                    <div class="summary-sub"><%= req.usesCustomCutoffDate ? "특정 날짜 직접 입력" : ("보관기간 " + req.retentionYears + "년 기준") %></div>
                </div>
                <div class="summary-card">
                    <div class="summary-label">선택 테이블</div>
                    <div class="summary-value"><%= result.selectedActiveTargets.size() %>개</div>
                    <div class="summary-sub">이력 삭제 대상 테이블 수</div>
                </div>
                <div class="summary-card">
                    <div class="summary-label">예상 삭제 건수</div>
                    <div class="summary-value"><%= String.format("%,d", result.previewTotalCount) %></div>
                    <div class="summary-sub">현재 선택 기준 미리보기</div>
                </div>
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

        <div class="section-grid">
            <div class="action-stack">
                <section class="section-card">
                    <div class="section-head">
                        <div>
                            <h3>DB 백업</h3>
                            <p>삭제나 초기화 전에 먼저 서버 경로로 전체 데이터베이스 백업을 실행합니다.</p>
                        </div>
                        <span class="section-tag tag-safe">안전</span>
                    </div>
                    <div class="section-body">
                        <form method="post" action="">
                            <div class="row">
                                <div class="label">DB 서버 백업 경로</div>
                                <input class="path-input mono" type="text" name="backup_path" value="<%= h(req.backupPath) %>" placeholder="예: F:\backup\epms_2026-02-13.bak" />
                                <input type="hidden" name="retention_years" value="<%= req.retentionYears %>" />
                                <input type="hidden" name="cutoff_date" value="<%= h(req.cutoffDateInput == null ? "" : req.cutoffDateInput) %>" />
                                <% for (String selectedTarget : req.selectedTargets) { %>
                                <input type="hidden" name="selected_targets" value="<%= h(selectedTarget) %>" />
                                <% } %>
                                <input type="hidden" name="action" value="backup" />
                                <button type="submit" class="btn-backup" onclick="return confirm('입력한 서버 경로로 DB 백업을 실행하시겠습니까?');">DB 백업 실행</button>
                            </div>
                        </form>
                    </div>
                </section>

                <section class="section-card">
                    <div class="section-head">
                        <div>
                            <h3>이력 데이터 삭제</h3>
                            <p>특정 날짜 또는 보관기간 기준으로 선택한 이력성 테이블의 과거 데이터를 삭제합니다.</p>
                        </div>
                        <span class="section-tag tag-warn">주의</span>
                    </div>
                    <div class="section-body">
                        <form method="post" action="">
                            <input type="hidden" name="backup_path" value="<%= h(req.backupPath) %>" />

                            <div class="row row-tight">
                                <div class="label">보관기간</div>
                                <select id="retentionYears" name="retention_years" required>
                                    <option value="5" <%= req.retentionYears == 5 ? "selected" : "" %>>5년</option>
                                    <option value="7" <%= req.retentionYears == 7 ? "selected" : "" %>>7년</option>
                                    <option value="10" <%= req.retentionYears == 10 ? "selected" : "" %>>10년</option>
                                </select>
                                <span>또는</span>
                                <div class="label" style="min-width:auto;">특정 날짜</div>
                                <input id="cutoffDateInput" class="date-input" type="date" name="cutoff_date" value="<%= h(req.cutoffDateInput == null ? "" : req.cutoffDateInput) %>" />
                                <button type="button" class="back-btn" onclick="reloadPreview();">건수 다시 조회</button>
                                <button type="button" class="back-btn" onclick="resetCutoffDate();">특정 날짜 초기화</button>
                            </div>

                            <div class="sub-title">삭제 대상 테이블 선택</div>
                            <div class="target-grid">
                                <% for (Map<String, Object> target : result.activeTargets) { %>
                                <label class="target-item">
                                    <input type="checkbox" name="selected_targets" value="<%= h(String.valueOf(target.get("fqtn"))) %>" <%= Boolean.TRUE.equals(target.get("selected")) ? "checked" : "" %> />
                                    <span>
                                        <b><%= h(String.valueOf(target.get("label"))) %></b>
                                        <small class="mono"><%= h(String.valueOf(target.get("fqtn"))) %> / 기준 컬럼: <%= h(String.valueOf(target.get("timeCol"))) %></small>
                                    </span>
                                </label>
                                <% } %>
                            </div>
                            <div class="helper-text">기본값은 원시 이력 테이블만 선택되어 있으며, 일/월/연 집계 및 피크 집계 테이블은 필요할 때만 추가 선택하세요.</div>

                            <div class="sub-panel" style="margin-top:12px;">
                                <h4>삭제 미리보기</h4>
                                <div class="mini-summary-grid">
                                    <div class="mini-summary-card">
                                        <div class="mini-label">기준일</div>
                                        <div class="mini-value mono" style="font-size:15px;"><%= req.cutoffDate %> 00:00</div>
                                    </div>
                                    <div class="mini-summary-card">
                                        <div class="mini-label">기준 방식</div>
                                        <div class="mini-value" style="font-size:15px;"><%= req.usesCustomCutoffDate ? "특정 날짜" : ("보관기간 " + req.retentionYears + "년") %></div>
                                    </div>
                                    <div class="mini-summary-card">
                                        <div class="mini-label">선택 테이블</div>
                                        <div class="mini-value"><%= result.selectedActiveTargets.size() %>개</div>
                                    </div>
                                    <div class="mini-summary-card">
                                        <div class="mini-label">삭제 합계</div>
                                        <div class="mini-value"><%= String.format("%,d", result.previewTotalCount) %></div>
                                    </div>
                                </div>

                                <div class="preview-box" style="margin-bottom:12px;">
                                    <table>
                                        <tbody>
                                        <tr>
                                            <th>삭제 범위</th>
                                            <td>기준일 이전 데이터 삭제</td>
                                        </tr>
                                        </tbody>
                                    </table>
                                </div>

                                <div class="count-tile-grid">
                                    <% for (Map.Entry<String, Long> e : result.previewCounts.entrySet()) { %>
                                    <div class="count-tile">
                                        <div class="count-tile-name"><%= h(e.getKey()) %></div>
                                        <div class="count-tile-meta">삭제 예정 데이터</div>
                                        <div class="count-tile-value"><%= String.format("%,d", e.getValue()) %> 건</div>
                                        <div class="count-tile-sub">기준일 이전 레코드</div>
                                    </div>
                                    <% } %>
                                </div>
                            </div>

                            <div class="final-summary">
                                최종 확인: 현재 기준은 <span class="mono"><%= h(String.valueOf(req.cutoffDate)) %> 00:00:00</span> 이고,
                                선택한 테이블은 <b><%= result.selectedActiveTargets.size() %>개</b>,
                                삭제 예정 건수는 <b><%= String.format("%,d", result.previewTotalCount) %>건</b>입니다.
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
                    </div>
                </section>

                <div class="init-grid">
                    <section class="section-card">
                    <div class="section-head">
                        <div>
                            <h3>운영 데이터 초기화</h3>
                            <p>측정, 이벤트, 알람, 집계, 정산 결과 같은 운영 데이터만 비우고 마스터/설정은 유지합니다.</p>
                        </div>
                        <span class="section-tag tag-warn">주의</span>
                    </div>
                    <div class="section-body">
                        <form method="post" action="">
                            <input type="hidden" name="backup_path" value="<%= h(req.backupPath) %>" />
                            <input type="hidden" name="retention_years" value="<%= req.retentionYears %>" />
                            <input type="hidden" name="cutoff_date" value="<%= h(req.cutoffDateInput == null ? "" : req.cutoffDateInput) %>" />
                            <% for (String selectedTarget : req.selectedTargets) { %>
                            <input type="hidden" name="selected_targets" value="<%= h(selectedTarget) %>" />
                            <% } %>
                            <div class="warn-box" style="margin-bottom:10px;">
                                측정값, 이벤트, 알람, PLC 샘플, 집계, 정산 결과 같은 <b>운영 데이터만 삭제</b>합니다. 마스터/설정 데이터는 유지합니다. 가능하면 자동증가 번호도 다시 맞춰 다음 INSERT 시 1부터 시작하도록 초기화합니다.
                            </div>
                            <details style="margin-bottom:10px;">
                                <summary><b>운영 데이터 초기화 대상 테이블 보기</b></summary>
                                <ul class="simple-list">
                                    <% for (String fqtn : buildOperationalInitTables()) { %>
                                    <li class="mono"><%= h(fqtn) %></li>
                                    <% } %>
                                </ul>
                            </details>
                            <div class="row">
                                <div class="label">확인 문구</div>
                                <input class="mono" type="text" name="initialize_operational_phrase" value="" placeholder="운영초기화" />
                            </div>
                            <div class="helper-text">실행하려면 <span class="mono">운영초기화</span> 를 정확히 입력하세요.</div>
                            <div class="row row-danger">
                                <input type="hidden" name="action" value="initialize_operational" />
                                <button type="submit" class="btn-danger" onclick="return confirm('운영 데이터 초기화를 실행하면 측정/이벤트/알람/집계/정산 데이터가 삭제됩니다. 계속하시겠습니까?');">운영 데이터 초기화 실행</button>
                            </div>
                        </form>
                    </div>
                    </section>

                    <section class="section-card">
                    <div class="section-head">
                        <div>
                            <h3>전체 데이터 초기화</h3>
                            <p>마스터와 설정까지 포함해 dbo 사용자 테이블의 데이터를 모두 비우는 강한 초기화입니다.</p>
                        </div>
                        <span class="section-tag tag-danger">위험</span>
                    </div>
                    <div class="section-body">
                        <form method="post" action="">
                            <input type="hidden" name="backup_path" value="<%= h(req.backupPath) %>" />
                            <input type="hidden" name="retention_years" value="<%= req.retentionYears %>" />
                            <input type="hidden" name="cutoff_date" value="<%= h(req.cutoffDateInput == null ? "" : req.cutoffDateInput) %>" />
                            <% for (String selectedTarget : req.selectedTargets) { %>
                            <input type="hidden" name="selected_targets" value="<%= h(selectedTarget) %>" />
                            <% } %>
                            <div class="warn-box" style="margin-bottom:10px; background:#fff1f1; border-color:#ffc9c9; color:#a11d14;">
                                스키마는 유지하고 <b>dbo 사용자 테이블의 모든 데이터</b>를 삭제합니다. <b>마스터/설정 데이터도 함께 삭제</b>되며, 가능하면 자동증가 번호(IDENTITY)도 다시 맞춰서 다음 INSERT 시 1부터 시작하도록 초기화합니다.
                            </div>
                            <details style="margin-bottom:10px;">
                                <summary><b>전체 데이터 초기화 대상 범위 보기</b></summary>
                                <ul class="simple-list">
                                    <li>대상: <span class="mono">dbo</span> 스키마의 사용자 테이블 전체</li>
                                    <li>포함: 마스터, 설정, 정책, 매핑, 측정, 알람, 이벤트, 집계, 정산 결과</li>
                                    <li>유지: 테이블 구조, 컬럼, 인덱스, 제약조건, 프로시저, 뷰</li>
                                </ul>
                            </details>
                            <div class="row">
                                <label>
                                    <input type="checkbox" name="ack_master_delete" value="Y" />
                                    마스터/설정 데이터도 함께 삭제되는 것을 확인했습니다.
                                </label>
                            </div>
                            <div class="row">
                                <div class="label">확인 문구</div>
                                <input class="mono" type="text" name="initialize_phrase" value="" placeholder="DB초기화" />
                            </div>
                            <div class="helper-text">실행하려면 <span class="mono">DB초기화</span> 를 정확히 입력하세요. 마스터 포함 모든 데이터가 삭제되고 자동증가 번호가 초기 상태로 재설정됩니다.</div>
                            <div class="row row-danger">
                                <input type="hidden" name="action" value="initialize_db" />
                                <button type="submit" class="btn-danger" onclick="return confirm('전체 데이터 초기화를 실행하면 마스터 포함 dbo 사용자 테이블의 데이터가 모두 삭제되고 자동증가 번호가 다시 시작됩니다. 계속하시겠습니까?');">전체 데이터 초기화 실행</button>
                            </div>
                        </form>
                    </div>
                    </section>
                </div>
            </div>
        </div>
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

function reloadPreview() {
    const retentionYears = document.getElementById('retentionYears');
    const cutoffDateInput = document.getElementById('cutoffDateInput');
    const backupPathInput = document.querySelector('input[name=backup_path]');
    const params = new URLSearchParams();
    if (retentionYears) params.set('retention_years', retentionYears.value || '5');
    if (cutoffDateInput && cutoffDateInput.value) params.set('cutoff_date', cutoffDateInput.value);
    if (backupPathInput && backupPathInput.value) params.set('backup_path', backupPathInput.value);
    document.querySelectorAll('input[name=\"selected_targets\"]:checked').forEach(function (el) {
        params.append('selected_targets', el.value);
    });
    location.href = 'data_retention_manage.jsp?' + params.toString();
}

function resetCutoffDate() {
    const cutoffDateInput = document.getElementById('cutoffDateInput');
    if (cutoffDateInput) cutoffDateInput.value = '';
    reloadPreview();
}
</script>
</body>
</html>
<%
    } // end try-with-resources
%>
