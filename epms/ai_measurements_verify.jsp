<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" language="java" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconfig.jspf" %>
<%@ include file="../includes/epms_html.jspf" %>
<%@ include file="../includes/ai_measurements_match_support.jspf" %>
<%!
    private static String fmtNum2(Object value) {
        if (value == null) return "-";
        if (value instanceof Number) return String.format(Locale.US, "%.2f", ((Number)value).doubleValue());
        return String.valueOf(value);
    }

    private static Timestamp asTimestamp(Object value) {
        return (value instanceof Timestamp) ? (Timestamp)value : null;
    }

    private static List<String> parseMetricOrder(String metricOrder) {
        List<String> tokens = new ArrayList<String>();
        if (metricOrder == null) return tokens;
        String[] parts = metricOrder.split(",");
        for (String part : parts) {
            if (part == null) continue;
            String token = part.trim().toUpperCase(Locale.ROOT);
            if (token.isEmpty()) continue;
            tokens.add(token);
        }
        return tokens;
    }

    private static String classifySelectionState(Integer plcId, Integer meterId, boolean hasMappingRows, boolean hasTokenRows) {
        if (plcId == null || meterId == null) return "PLC와 Meter를 선택한 뒤 검증 데이터를 조회하세요.";
        if (!hasMappingRows) return "선택한 PLC/Meter에 활성 plc_meter_map 매핑이 없습니다.";
        if (!hasTokenRows) return "활성 지원 토큰에 대한 PLC 샘플 데이터가 없습니다.";
        return null;
    }

    private static String classifyTokenGroup(String token, Integer floatIndex) {
        if (token == null) return "기타";
        String t = token.trim().toUpperCase(Locale.ROOT);
        if (t.startsWith("H_V")) return "전압 고조파";
        if (t.startsWith("H_I")) return "전류 고조파";
        if (t.startsWith("PV") || t.startsWith("PI")) return "위상각";
        if ("VA".equals(t) && floatIndex != null && floatIndex.intValue() == 8) return "전압";
        if ("VA".equals(t) || "VAH".equals(t) || "VAR".equals(t) || "VARH".equals(t)) return "전력/에너지";
        if ("PF".equals(t) || "HZ".equals(t) || "KW".equals(t) || "KWH".equals(t) || "KVAR".equals(t) || "KVARH".equals(t) || "PEAK".equals(t) || "IR".equals(t)) return "전력/에너지";
        if (t.startsWith("A")) return "전류";
        if (t.startsWith("V")) return "전압";
        return "기타";
    }

    private static String describeTokenMeaning(String token, Integer floatIndex) {
        if (token == null) return "";
        String t = token.trim().toUpperCase(Locale.ROOT);
        if ("VA".equals(t) && floatIndex != null && floatIndex.intValue() == 8) return "상평균 전압";
        if ("VA".equals(t) && floatIndex != null && floatIndex.intValue() == 18) return "무효전력";
        if ("VAH".equals(t) && floatIndex != null && floatIndex.intValue() == 19) return "무효전력량";
        if ("VAR".equals(t)) return "무효전력";
        if ("VARH".equals(t)) return "무효전력량";
        if ("PV1".equals(t)) return "A상 전압 위상각";
        if ("PV2".equals(t)) return "B상 전압 위상각";
        if ("PV3".equals(t)) return "C상 전압 위상각";
        if ("PI1".equals(t)) return "A상 전류 위상각";
        if ("PI2".equals(t)) return "B상 전류 위상각";
        if ("PI3".equals(t)) return "C상 전류 위상각";
        if ("PF".equals(t)) return "역률";
        if ("HZ".equals(t)) return "주파수";
        if ("KW".equals(t)) return "유효전력";
        if ("KWH".equals(t)) return "유효전력량";
        if ("KVARH".equals(t)) return "무효전력량";
        if ("IR".equals(t)) return "전류 불평형률";
        if ("KVAR".equals(t)) return "무효전력";
        if ("PEAK".equals(t)) return "전력 피크";
        return "";
    }

    private static String humanizeMeasurementColumn(String column) {
        if (column == null) return "";
        String c = column.trim();
        if (c.isEmpty()) return "";
        return c.replace('_', ' ');
    }

    private static boolean isSafeSqlIdentifier(String identifier) {
        return identifier != null && identifier.matches("[A-Za-z_][A-Za-z0-9_]*");
    }

    private static String buildSelectColumns(List<Map<String, Object>> tokenDefinitions, String targetTable) {
        LinkedHashSet<String> columns = new LinkedHashSet<String>();
        columns.add("measured_at");
        if (tokenDefinitions != null) {
            for (Map<String, Object> row : tokenDefinitions) {
                if (row == null) continue;
                String configuredTargetTable = (String) row.get("target_table");
                String resolvedTargetTable = resolveAiMatchTargetTable(configuredTargetTable);
                if (resolvedTargetTable == null || !resolvedTargetTable.equalsIgnoreCase(targetTable)) continue;
                String column = (String) row.get("measurement_column");
                if (isSafeSqlIdentifier(column)) {
                    columns.add(column);
                }
            }
        }
        StringBuilder sql = new StringBuilder();
        boolean first = true;
        for (String column : columns) {
            if (!first) sql.append(", ");
            first = false;
            sql.append(column);
        }
        return sql.toString();
    }

    private static void copyRow(ResultSet rs, Map<String, Object> out, List<String> columns) throws SQLException {
        if (rs == null || out == null || columns == null) return;
        for (String column : columns) {
            if (column == null || column.trim().isEmpty()) continue;
            out.put(column, rs.getObject(column));
        }
    }

    private static List<String> parseSelectedColumns(String selectColumns) {
        List<String> columns = new ArrayList<String>();
        if (selectColumns == null) return columns;
        String[] parts = selectColumns.split(",");
        for (String part : parts) {
            if (part == null) continue;
            String column = part.trim();
            if (!column.isEmpty()) columns.add(column);
        }
        return columns;
    }
%>
<%
    try (Connection conn = openDbConnection()) {
    response.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0L);
    String plcParam = request.getParameter("plc_id");
    String meterParam = request.getParameter("meter_id");
    boolean showMapping = "1".equals(request.getParameter("show_mapping"));
    boolean autoRefresh = "1".equals(request.getParameter("auto_refresh"));
    Integer plcId = null;
    Integer meterId = null;
    try { if (plcParam != null && !plcParam.trim().isEmpty()) plcId = Integer.parseInt(plcParam.trim()); } catch (Exception ignore) {}
    try { if (meterParam != null && !meterParam.trim().isEmpty()) meterId = Integer.parseInt(meterParam.trim()); } catch (Exception ignore) {}

    List<Map<String, Object>> plcList = new ArrayList<>();
    List<Map<String, Object>> meterList = new ArrayList<>();
    Map<Integer, List<Integer>> meterIdsByPlc = new LinkedHashMap<Integer, List<Integer>>();
    List<Map<String, Object>> mappingRows = new ArrayList<>();
    List<Map<String, Object>> latestTokenRows = new ArrayList<>();
    Map<String, Object> latestMeasurement = new HashMap<>();
    Map<String, Object> latestHarmonicMeasurement = new HashMap<>();
    Timestamp latestHarmonicRecentAt = null;
    Map<String, List<Map<String, Object>>> latestTokenGroups = new LinkedHashMap<>();
    Map<String, Map<String, Object>> mappingByTokenIndex = new HashMap<>();
    Timestamp latestPlcSampleAt = null;
    Timestamp latestRawPlcSampleAt = null;
    boolean hasHarmonicTargets = false;
    String emptyStateMessage = null;
    String timingNotice = null;
    String perfNotice = null;
    String error = null;
    boolean hasActivePlcMeterMap = false;
    boolean hasAiMaster = false;
    long requestStartMs = System.currentTimeMillis();
    long configLoadMs = 0L;
    long mappingLoadMs = 0L;
    long tokenResolveMs = 0L;
    long latestFetchMs = 0L;

    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT CASE WHEN OBJECT_ID('dbo.plc_ai_mapping_master', 'U') IS NULL THEN 0 ELSE 1 END AS has_ai_master");
         ResultSet rs = ps.executeQuery()) {
        if (rs.next()) {
            hasAiMaster = rs.getInt("has_ai_master") == 1;
        }
    }

    try {
        long sectionStartMs = System.currentTimeMillis();
        try (PreparedStatement ps = conn.prepareStatement("SELECT plc_id, plc_ip, plc_port, unit_id, polling_ms, enabled FROM dbo.plc_config ORDER BY plc_id");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("plc_id", rs.getInt("plc_id"));
                r.put("plc_ip", rs.getString("plc_ip"));
                r.put("plc_port", rs.getInt("plc_port"));
                r.put("unit_id", rs.getInt("unit_id"));
                r.put("polling_ms", rs.getInt("polling_ms"));
                r.put("enabled", rs.getBoolean("enabled"));
                plcList.add(r);
            }
        }

        String meterSql = "SELECT meter_id, name, panel_name FROM dbo.meters ORDER BY meter_id";
        try (PreparedStatement ps = conn.prepareStatement(meterSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, Object> r = new HashMap<>();
                r.put("meter_id", rs.getInt("meter_id"));
                r.put("name", rs.getString("name"));
                r.put("panel_name", rs.getString("panel_name"));
                meterList.add(r);
            }
        }

        String plcMeterSql = hasAiMaster
            ? "SELECT DISTINCT plc_id, meter_id FROM dbo.plc_ai_mapping_master WHERE enabled = 1 ORDER BY plc_id, meter_id"
            : "SELECT DISTINCT plc_id, meter_id FROM dbo.plc_meter_map WHERE enabled = 1 ORDER BY plc_id, meter_id";
        try (PreparedStatement ps = conn.prepareStatement(plcMeterSql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Integer key = Integer.valueOf(rs.getInt("plc_id"));
                List<Integer> meterIds = meterIdsByPlc.get(key);
                if (meterIds == null) {
                    meterIds = new ArrayList<Integer>();
                    meterIdsByPlc.put(key, meterIds);
                }
                meterIds.add(Integer.valueOf(rs.getInt("meter_id")));
            }
        }
        configLoadMs = Math.max(0L, System.currentTimeMillis() - sectionStartMs);

        sectionStartMs = System.currentTimeMillis();
        if (hasAiMaster && showMapping) {
            String mapSql =
                "SELECT token, float_index, " +
                "       CAST(2 AS INT) AS float_registers, " +
                "       MIN(reg_address) AS reg_address, " +
                "       MAX(measurement_column) AS measurement_column, " +
                "       MAX(target_table) AS target_table, " +
                "       MAX(CASE WHEN db_insert_yn = 1 THEN 1 ELSE 0 END) AS is_supported, " +
                "       MAX(note) AS note " +
                "FROM dbo.plc_ai_mapping_master " +
                "WHERE enabled = 1 " +
                (plcId != null && meterId != null ? "AND plc_id = ? AND meter_id = ? " : "") +
                "GROUP BY token, float_index " +
                "ORDER BY float_index, token";
            try (PreparedStatement ps = conn.prepareStatement(mapSql)) {
                if (plcId != null && meterId != null) {
                    ps.setInt(1, plcId.intValue());
                    ps.setInt(2, meterId.intValue());
                }
                try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("token", rs.getString("token"));
                    r.put("float_index", rs.getInt("float_index"));
                    r.put("float_registers", rs.getInt("float_registers"));
                    r.put("reg_address", rs.getInt("reg_address"));
                    r.put("measurement_column", rs.getString("measurement_column"));
                    r.put("target_table", rs.getString("target_table"));
                    r.put("is_supported", rs.getInt("is_supported") == 1);
                    r.put("note", rs.getString("note"));
                    mappingRows.add(r);
                    mappingByTokenIndex.put(String.valueOf(r.get("token")).toUpperCase(Locale.ROOT) + "|" + rs.getInt("float_index"), r);
                }
                }
            }
        } else if (!hasAiMaster) {
            String mapSql =
                "SELECT token, float_index, float_registers, CAST(NULL AS INT) AS reg_address, measurement_column, target_table, is_supported, note " +
                "FROM dbo.plc_ai_measurements_match ORDER BY float_index";
            try (PreparedStatement ps = conn.prepareStatement(mapSql);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> r = new HashMap<>();
                    r.put("token", rs.getString("token"));
                    r.put("float_index", rs.getInt("float_index"));
                    r.put("float_registers", rs.getInt("float_registers"));
                    r.put("reg_address", rs.getObject("reg_address"));
                    r.put("measurement_column", rs.getString("measurement_column"));
                    r.put("target_table", rs.getString("target_table"));
                    r.put("is_supported", rs.getBoolean("is_supported"));
                    r.put("note", rs.getString("note"));
                    mappingRows.add(r);
                    mappingByTokenIndex.put(String.valueOf(r.get("token")).toUpperCase(Locale.ROOT) + "|" + rs.getInt("float_index"), r);
                }
            }
        }
        mappingLoadMs = Math.max(0L, System.currentTimeMillis() - sectionStartMs);

        if (plcId != null && meterId != null) {
            sectionStartMs = System.currentTimeMillis();
            Integer startAddress = null;
            String metricOrder = null;
            List<Map<String, Object>> tokenDefinitions = new ArrayList<Map<String, Object>>();
            List<Integer> regAddresses = new ArrayList<Integer>();
            boolean loadedFromMaster = false;

            if (hasAiMaster) {
                String masterSql =
                    "SELECT float_index, token, reg_address, measurement_column, target_table, db_insert_yn, note " +
                    "FROM dbo.plc_ai_mapping_master " +
                    "WHERE plc_id = ? AND meter_id = ? AND enabled = 1 " +
                    "ORDER BY float_index";
                try (PreparedStatement ps = conn.prepareStatement(masterSql)) {
                    ps.setInt(1, plcId);
                    ps.setInt(2, meterId);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            hasActivePlcMeterMap = true;
                            loadedFromMaster = true;
                            Map<String, Object> r = new HashMap<>();
                            String token = rs.getString("token");
                            int floatIndex = rs.getInt("float_index");
                            int regAddress = rs.getInt("reg_address");
                            r.put("token", token);
                            r.put("float_index", Integer.valueOf(floatIndex));
                            r.put("float_registers", Integer.valueOf(2));
                            r.put("measurement_column", rs.getString("measurement_column"));
                            r.put("target_table", rs.getString("target_table"));
                            r.put("note", rs.getString("note"));
                            r.put("reg_address", Integer.valueOf(regAddress));
                            r.put("is_supported", Boolean.valueOf(rs.getBoolean("db_insert_yn")));
                            if ("harmonic_measurements".equalsIgnoreCase(rs.getString("target_table"))) {
                                hasHarmonicTargets = true;
                            }
                            tokenDefinitions.add(r);
                            regAddresses.add(Integer.valueOf(regAddress));
                            if (startAddress == null || regAddress < startAddress.intValue()) {
                                startAddress = Integer.valueOf(regAddress);
                            }
                        }
                    }
                }
            }

            if (!loadedFromMaster) {
                String mapExistsSql =
                    "SELECT TOP 1 start_address, metric_order FROM dbo.plc_meter_map WHERE plc_id = ? AND meter_id = ? AND enabled = 1 ORDER BY map_id";
                try (PreparedStatement ps = conn.prepareStatement(mapExistsSql)) {
                    ps.setInt(1, plcId);
                    ps.setInt(2, meterId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            hasActivePlcMeterMap = true;
                            startAddress = rs.getInt("start_address");
                            metricOrder = rs.getString("metric_order");
                        }
                    }
                }

                List<String> metricTokens = parseMetricOrder(metricOrder);
                if (hasActivePlcMeterMap && startAddress != null && !metricTokens.isEmpty()) {
                    int currentRegAddress = startAddress.intValue();
                    for (int i = 0; i < metricTokens.size(); i++) {
                        String token = metricTokens.get(i);
                        Map<String, Object> mapping = mappingByTokenIndex.get(token + "|" + (i + 1));
                        int floatRegisters = 2;
                        String measurementColumn = null;
                        String targetTable = null;
                        String note = null;
                        boolean supported = isAiMatchPlcOnlyToken(token);
                        if (mapping != null) {
                            Object regsObj = mapping.get("float_registers");
                            if (regsObj instanceof Number) floatRegisters = ((Number)regsObj).intValue();
                            measurementColumn = (String)mapping.get("measurement_column");
                            targetTable = (String)mapping.get("target_table");
                            note = (String)mapping.get("note");
                            Object supportedObj = mapping.get("is_supported");
                            if (supportedObj instanceof Boolean) supported = ((Boolean)supportedObj).booleanValue();
                        }
                        if (floatRegisters <= 0) floatRegisters = 2;
                        Map<String, Object> r = new HashMap<>();
                        r.put("token", token);
                        r.put("float_index", Integer.valueOf(i + 1));
                        r.put("float_registers", Integer.valueOf(floatRegisters));
                        r.put("measurement_column", measurementColumn);
                        r.put("target_table", targetTable);
                        r.put("note", note);
                        r.put("reg_address", Integer.valueOf(currentRegAddress));
                        r.put("is_supported", Boolean.valueOf(supported));
                        if ("harmonic_measurements".equalsIgnoreCase(targetTable)) {
                            hasHarmonicTargets = true;
                        }
                        tokenDefinitions.add(r);
                        regAddresses.add(Integer.valueOf(currentRegAddress));
                        currentRegAddress += floatRegisters;
                    }
                }
            }

            if (!tokenDefinitions.isEmpty()) {
                String latestSampleAtSql =
                    "SELECT TOP 1 measured_at FROM dbo.plc_ai_samples " +
                    "WHERE plc_id = ? AND meter_id = ? ORDER BY measured_at DESC";
                try (PreparedStatement ps = conn.prepareStatement(latestSampleAtSql)) {
                    ps.setInt(1, plcId);
                    ps.setInt(2, meterId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            latestRawPlcSampleAt = rs.getTimestamp("measured_at");
                        }
                    }
                }

                String comparableSampleSql =
                    "SELECT TOP 1 s.measured_at " +
                    "FROM (SELECT DISTINCT TOP 12 measured_at FROM dbo.plc_ai_samples WHERE plc_id = ? AND meter_id = ? ORDER BY measured_at DESC) s " +
                    "WHERE EXISTS ( " +
                    "    SELECT 1 FROM dbo.measurements m " +
                    "    WHERE m.meter_id = ? " +
                    "      AND m.measured_at BETWEEN DATEADD(SECOND, -2, s.measured_at) AND DATEADD(SECOND, 2, s.measured_at) " +
                    ") " +
                    (hasHarmonicTargets
                        ? "AND EXISTS ( " +
                          "    SELECT 1 FROM dbo.harmonic_measurements h " +
                          "    WHERE h.meter_id = ? " +
                          "      AND h.measured_at BETWEEN DATEADD(SECOND, -2, s.measured_at) AND DATEADD(SECOND, 2, s.measured_at) " +
                          ") "
                        : "") +
                    "ORDER BY s.measured_at DESC";
                try (PreparedStatement ps = conn.prepareStatement(comparableSampleSql)) {
                    int idx = 1;
                    ps.setInt(idx++, plcId);
                    ps.setInt(idx++, meterId);
                    ps.setInt(idx++, meterId);
                    if (hasHarmonicTargets) {
                        ps.setInt(idx++, meterId);
                    }
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            latestPlcSampleAt = rs.getTimestamp("measured_at");
                        }
                    }
                }
                if (latestPlcSampleAt == null) {
                    latestPlcSampleAt = latestRawPlcSampleAt;
                }

                if (!regAddresses.isEmpty() && latestPlcSampleAt != null) {
                    StringBuilder sampleSql = new StringBuilder();
                    sampleSql.append("SELECT reg_address, value_float, measured_at ");
                    sampleSql.append("FROM dbo.plc_ai_samples WHERE plc_id = ? AND meter_id = ? AND measured_at = ? AND reg_address IN (");
                    for (int i = 0; i < regAddresses.size(); i++) {
                        if (i > 0) sampleSql.append(",");
                        sampleSql.append("?");
                    }
                    sampleSql.append(")");

                    Map<Integer, Map<String, Object>> latestSamplesByReg = new HashMap<Integer, Map<String, Object>>();
                    try (PreparedStatement ps = conn.prepareStatement(sampleSql.toString())) {
                        ps.setInt(1, plcId);
                        ps.setInt(2, meterId);
                        ps.setTimestamp(3, latestPlcSampleAt);
                        for (int i = 0; i < regAddresses.size(); i++) {
                            ps.setInt(i + 4, regAddresses.get(i).intValue());
                        }
                        try (ResultSet rs = ps.executeQuery()) {
                            while (rs.next()) {
                                Map<String, Object> sample = new HashMap<>();
                                sample.put("value_float", rs.getObject("value_float"));
                                sample.put("measured_at", rs.getTimestamp("measured_at"));
                                latestSamplesByReg.put(Integer.valueOf(rs.getInt("reg_address")), sample);
                            }
                        }
                    }

                    for (Map<String, Object> r : tokenDefinitions) {
                        Integer regAddress = (Integer)r.get("reg_address");
                        Map<String, Object> sample = latestSamplesByReg.get(regAddress);
                        r.put("value_float", sample == null ? null : sample.get("value_float"));
                        r.put("measured_at", sample == null ? null : sample.get("measured_at"));
                        latestTokenRows.add(r);
                    }
                }
            }
            tokenResolveMs = Math.max(0L, System.currentTimeMillis() - sectionStartMs);

            sectionStartMs = System.currentTimeMillis();
            String measurementSelectColumns = buildSelectColumns(tokenDefinitions, "measurements");
            List<String> measurementColumnList = parseSelectedColumns(measurementSelectColumns);
            String latestSql =
                "SELECT TOP 1 " + measurementSelectColumns + " FROM dbo.measurements WHERE meter_id = ? " +
                (latestPlcSampleAt != null
                    ? "AND measured_at BETWEEN DATEADD(SECOND, -2, ?) AND DATEADD(SECOND, 2, ?) " +
                      "ORDER BY ABS(DATEDIFF(MILLISECOND, measured_at, ?)), measured_at DESC"
                    : "ORDER BY measured_at DESC");
            try (PreparedStatement ps = conn.prepareStatement(latestSql)) {
                ps.setInt(1, meterId);
                if (latestPlcSampleAt != null) {
                    ps.setTimestamp(2, latestPlcSampleAt);
                    ps.setTimestamp(3, latestPlcSampleAt);
                    ps.setTimestamp(4, latestPlcSampleAt);
                }
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        copyRow(rs, latestMeasurement, measurementColumnList);
                    }
                }
            }

            if (hasHarmonicTargets) {
                String harmonicSelectColumns = buildSelectColumns(tokenDefinitions, "harmonic_measurements");
                List<String> harmonicColumnList = parseSelectedColumns(harmonicSelectColumns);
                String latestHarmonicSql =
                    "SELECT TOP 1 " + harmonicSelectColumns + " FROM dbo.harmonic_measurements WHERE meter_id = ? " +
                    (latestPlcSampleAt != null
                        ? "AND measured_at BETWEEN DATEADD(SECOND, -2, ?) " +
                          "AND DATEADD(SECOND, 2, ?) " +
                          "ORDER BY ABS(DATEDIFF(MILLISECOND, measured_at, ?)), measured_at DESC"
                        : "ORDER BY measured_at DESC");
                try (PreparedStatement ps = conn.prepareStatement(latestHarmonicSql)) {
                    ps.setInt(1, meterId);
                    if (latestPlcSampleAt != null) {
                        ps.setTimestamp(2, latestPlcSampleAt);
                        ps.setTimestamp(3, latestPlcSampleAt);
                        ps.setTimestamp(4, latestPlcSampleAt);
                    }
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            copyRow(rs, latestHarmonicMeasurement, harmonicColumnList);
                        }
                    }
                }

                String latestHarmonicRecentSql =
                    "SELECT TOP 1 measured_at FROM dbo.harmonic_measurements WHERE meter_id = ? ORDER BY measured_at DESC";
                try (PreparedStatement ps = conn.prepareStatement(latestHarmonicRecentSql)) {
                    ps.setInt(1, meterId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            latestHarmonicRecentAt = rs.getTimestamp("measured_at");
                        }
                    }
                }
            }
            latestFetchMs = Math.max(0L, System.currentTimeMillis() - sectionStartMs);
        }
    } catch (Exception e) {
        error = e.getMessage();
    }
    String[] groupOrder = new String[]{"전압", "전류", "전력/에너지", "전압 고조파", "전류 고조파", "위상각", "기타"};
    for (String groupName : groupOrder) latestTokenGroups.put(groupName, new ArrayList<Map<String, Object>>());
    for (Map<String, Object> r : latestTokenRows) {
        String groupName = classifyTokenGroup((String)r.get("token"), (Integer)r.get("float_index"));
        List<Map<String, Object>> bucket = latestTokenGroups.get(groupName);
        if (bucket == null) {
            bucket = new ArrayList<Map<String, Object>>();
            latestTokenGroups.put(groupName, bucket);
        }
        bucket.add(r);
    }
    emptyStateMessage = classifySelectionState(plcId, meterId, hasActivePlcMeterMap, !latestTokenRows.isEmpty());
    if (latestPlcSampleAt != null) {
        Timestamp measurementAt = asTimestamp(latestMeasurement.get("measured_at"));
        Timestamp harmonicAt = asTimestamp(latestHarmonicMeasurement.get("measured_at"));
        List<String> timingParts = new ArrayList<String>();
        timingParts.add("검증 기준 PLC 샘플 시각: " + latestPlcSampleAt);
        if (latestRawPlcSampleAt != null && !latestRawPlcSampleAt.equals(latestPlcSampleAt)) {
            timingParts.add("최신 PLC 샘플 시각: " + latestRawPlcSampleAt);
        }
        timingParts.add("measurements 비교 행: " + (measurementAt == null ? "없음" : String.valueOf(measurementAt)));
        timingParts.add("harmonic_measurements 비교 행: " + (harmonicAt == null ? "없음" : String.valueOf(harmonicAt)));
        if (latestHarmonicRecentAt != null) {
            timingParts.add("harmonic_measurements 최근 행: " + latestHarmonicRecentAt);
        }
        timingNotice = String.join(" | ", timingParts);
    }
    perfNotice = "server_ms total=" + Math.max(0L, System.currentTimeMillis() - requestStartMs)
            + " config=" + configLoadMs
            + " mapping=" + mappingLoadMs
            + " token_resolve=" + tokenResolveMs
            + " latest_fetch=" + latestFetchMs;
%>
<html>
<head>
    <title>AI Measurement Verification</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1500px; margin: 0 auto; }
        .info-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .warn-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff8e8; border: 1px solid #f5d48f; color: #9a6700; font-size: 13px; }
        .err-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #fff1f1; border: 1px solid #ffc9c9; color: #b42318; font-size: 13px; font-weight: 700; }
        .refresh-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #f5f9ff; border: 1px solid #d7e6ff; color: #35557a; font-size: 13px; }
        .section-title { margin: 14px 0 6px; font-size: 15px; font-weight: 700; color: #1f3347; }
        .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
        .toolbar label { font-size: 13px; color: #31506f; font-weight: 600; }
        .toolbar select { min-height: 36px; padding: 6px 10px; border-radius: 10px; border: 1px solid #c9d8e8; background: #fff; color: #1f3347; }
        .toolbar button[type="submit"] { min-height: 38px; padding: 0 18px; border: 0; border-radius: 999px; background: linear-gradient(135deg, #2f6fe4, #1956c8); color: #fff; font-weight: 700; letter-spacing: -0.01em; box-shadow: 0 10px 22px rgba(31, 86, 200, 0.22); }
        .toolbar button[type="submit"]:disabled { opacity: 0.7; box-shadow: none; }
        .auto-refresh-toggle { display: inline-flex; align-items: center; gap: 8px; padding: 7px 12px; border-radius: 999px; border: 1px solid #cfe0fb; background: linear-gradient(180deg, #f7fbff, #edf4ff); color: #1f5cc4; font-size: 13px; font-weight: 700; box-shadow: inset 0 1px 0 rgba(255,255,255,0.8); }
        .auto-refresh-toggle input[type="checkbox"] { width: 15px; height: 15px; margin: 0; accent-color: #1f6ae0; }
        .auto-refresh-status { display: inline-flex; align-items: center; min-height: 34px; padding: 0 12px; border-radius: 999px; background: #eef4ff; border: 1px solid #d3e2ff; color: #3c5f8d; font-size: 12px; font-weight: 700; letter-spacing: -0.01em; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
        .b-ok { background: #e8f7ec; color: #1b7f3b; border: 1px solid #b9e6c6; }
        .b-no { background: #fff3e0; color: #b45309; border: 1px solid #ffd8a8; }
        .b-plc { background: #eef2ff; color: #3347a8; border: 1px solid #cdd6ff; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        td { font-size: 12px; }
        .match-groups { display: flex; flex-direction: column; gap: 16px; margin-top: 8px; }
        .match-group { border: 1px solid #d8e2ee; border-radius: 14px; background: #f9fbfd; overflow: hidden; }
        .match-group-head { display: flex; justify-content: space-between; align-items: center; padding: 10px 14px; background: #eef4fa; border-bottom: 1px solid #d8e2ee; }
        .match-group-title { font-size: 15px; font-weight: 700; color: #1f3347; }
        .match-group-count { font-size: 12px; color: #54708b; }
        .match-card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; padding: 12px; }
        .match-card { border: 1px solid #dbe6f0; border-radius: 12px; background: #fff; padding: 12px; box-shadow: 0 1px 2px rgba(20, 48, 76, 0.06); }
        .match-card-top { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin-bottom: 8px; }
        .match-card-token { font-size: 15px; font-weight: 700; color: #15324b; }
        .match-card-index { font-size: 11px; color: #6b7f93; }
        .match-card-meta { display: grid; grid-template-columns: 96px 1fr; gap: 4px 8px; font-size: 12px; margin-top: 8px; }
        .match-card-meta dt { margin: 0; color: #70859a; font-weight: 700; }
        .match-card-meta dd { margin: 0; color: #1f3347; }
        .match-values { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
        .match-value-box { border-radius: 10px; padding: 10px; }
        .match-value-box.plc { background: #edf7ff; border: 1px solid #cfe7fb; }
        .match-value-box.target { background: #eef9f0; border: 1px solid #d7efd8; }
        .match-value-label { font-size: 11px; color: #587086; margin-bottom: 4px; }
        .match-value-num { font-size: 20px; font-weight: 700; color: #14324a; line-height: 1.1; }
        .match-empty { padding: 16px; border: 1px dashed #c7d4e2; border-radius: 12px; background: #f8fbfe; color: #60768a; font-size: 13px; }
        @media (max-width: 768px) {
            .match-card-grid { grid-template-columns: 1fr; }
            .match-values { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>🔎 AI 측정값 적재 검증</h2>
        <div class="inline-actions">
            <button class="back-btn" onclick="location.href='/epms/ai_mapping.jsp'">AI 매핑</button>
            <button class="back-btn" onclick="location.href='/epms/ai_measurements_mapping_manage.jsp'">매핑 정의 관리</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 홈</button>
        </div>
    </div>

    <div class="info-box">
        기준: <span class="mono">dbo.plc_ai_mapping_master</span> 우선 기준으로 PLC 샘플값과 DB 적재값을 비교하는 검증 화면입니다. 마스터가 없을 때만 기존 <span class="mono">plc_ai_measurements_match</span> / <span class="mono">plc_meter_map</span> 으로 fallback 합니다.<br/>
        참고: <span class="mono">PV1/PV2/PV3</span>, <span class="mono">PI1/PI2/PI3</span>는 현재 화면에서 위상각 의미로 표시되며, 적재값은 PLC 최신 샘플 시각 이하의 최근 행을 기준으로 비교합니다.
    </div>

    <% if (error != null) { %>
    <div class="err-box">DB 오류: <%= h(error) %></div>
    <% } %>
    <% if (timingNotice != null) { %>
    <div class="warn-box"><%= h(timingNotice) %></div>
    <% } %>
    <% if (perfNotice != null) { %>
    <div class="info-box mono"><%= h(perfNotice) %></div>
    <% } %>
    <div class="refresh-box" id="refreshNotice">
        자동 갱신은 선택한 PLC의 polling 주기(ms)를 기준으로 동작합니다. 자동 갱신을 켜면 해당 주기마다 현재 조건으로 다시 조회합니다.
    </div>

    <form method="GET" action="<%= request.getRequestURI() %>" class="toolbar" id="verifyForm" autocomplete="off">
        <label for="plc_id">PLC:</label>
        <select id="plc_id" name="plc_id">
            <option value="">선택</option>
            <% for (Map<String, Object> p : plcList) { %>
            <% String v = String.valueOf(p.get("plc_id")); %>
            <option value="<%= v %>" data-polling-ms="<%= p.get("polling_ms") %>" <%= (plcId != null && plcId.toString().equals(v)) ? "selected" : "" %>>
                PLC <%= p.get("plc_id") %> - <%= h(p.get("plc_ip")) %>:<%= p.get("plc_port") %>
            </option>
            <% } %>
        </select>

        <label for="meter_id">Meter:</label>
        <select id="meter_id" name="meter_id">
            <option value="">선택</option>
            <% for (Map<String, Object> m : meterList) { %>
            <% String v = String.valueOf(m.get("meter_id")); %>
            <option value="<%= v %>" data-panel-name="<%= h(m.get("panel_name")) %>" data-meter-name="<%= h(m.get("name")) %>" <%= (meterId != null && meterId.toString().equals(v)) ? "selected" : "" %>>
                #<%= m.get("meter_id") %> - <%= h(m.get("name")) %> (<%= h(m.get("panel_name")) %>)
            </option>
            <% } %>
        </select>
        <label class="auto-refresh-toggle">
            <input type="checkbox" id="auto_refresh" name="auto_refresh" value="1" <%= autoRefresh ? "checked" : "" %>>
            자동 갱신
        </label>
        <% if (showMapping) { %><input type="hidden" name="show_mapping" value="1"><% } %>
        <span id="autoRefreshStatus" class="auto-refresh-status mono"></span>
        <button type="submit" id="verifySubmitBtn">검증 조회</button>
    </form>

    <div class="section-title">1) 실측 비교 결과</div>
    <% if (latestTokenRows.isEmpty()) { %>
    <div class="match-empty"><%= h(emptyStateMessage) %></div>
    <% } else { %>
    <div class="match-groups">
        <% for (Map.Entry<String, List<Map<String, Object>>> entry : latestTokenGroups.entrySet()) { %>
            <% if (entry.getValue().isEmpty()) continue; %>
            <div class="match-group">
                <div class="match-group-head">
                    <div class="match-group-title"><%= h(entry.getKey()) %></div>
                    <div class="match-group-count"><%= entry.getValue().size() %>개 항목</div>
                </div>
                <div class="match-card-grid">
                    <% for (Map<String, Object> r : entry.getValue()) { %>
                        <%
                            String col = (String)r.get("measurement_column");
                            Integer floatIndex = (Integer)r.get("float_index");
                            Object noteObj = r.get("note");
                            String note = noteObj == null ? "" : String.valueOf(noteObj).trim();
                            String tokenMeaning = note;
                            if (tokenMeaning == null || tokenMeaning.trim().isEmpty()) {
                                tokenMeaning = describeTokenMeaning((String)r.get("token"), floatIndex);
                            }
                            if (tokenMeaning == null || tokenMeaning.trim().isEmpty()) {
                                tokenMeaning = humanizeMeasurementColumn(col);
                            }
                            boolean plcOnly = isAiMatchPlcOnlyToken((String)r.get("token"));
                            String configuredTargetTable = (String)r.get("target_table");
                            String resolvedTargetTable = resolveAiMatchTargetTable(configuredTargetTable);
                            Object mv = null;
                            if (!plcOnly && col != null) {
                                if ("harmonic_measurements".equalsIgnoreCase(resolvedTargetTable)) mv = latestHarmonicMeasurement.get(col);
                                else if ("measurements".equalsIgnoreCase(resolvedTargetTable)) mv = latestMeasurement.get(col);
                            }
                            String targetTableLabel = plcOnly
                                ? "DB 미적재 PLC 전용"
                                : (resolvedTargetTable == null ? "미지원 target_table: " + configuredTargetTable : resolvedTargetTable);
                            Object targetMeasuredAt = null;
                            if (!plcOnly && "harmonic_measurements".equalsIgnoreCase(resolvedTargetTable)) {
                                targetMeasuredAt = latestHarmonicMeasurement.get("measured_at");
                            } else if (!plcOnly && "measurements".equalsIgnoreCase(resolvedTargetTable)) {
                                targetMeasuredAt = latestMeasurement.get("measured_at");
                            }
                            String targetMeasuredAtLabel = plcOnly
                                ? "-"
                                : (targetMeasuredAt == null ? "동일 cycle 비교 행 없음" : String.valueOf(targetMeasuredAt));
                            String targetValueLabel = plcOnly
                                ? "DB 적재 대상 아님"
                                : (targetMeasuredAt == null ? "동일 cycle DB값 없음" : "DB 비교값");
                        %>
                        <div class="match-card">
                            <div class="match-card-top">
                                <div class="match-card-token mono"><%= h(r.get("token")) %></div>
                                <div class="match-card-index mono">
                                    #<%= r.get("float_index") %>
                                    <% if (plcOnly) { %><span class="badge b-plc">PLC Only</span><% } %>
                                </div>
                            </div>
                            <div class="match-values">
                                <div class="match-value-box plc">
                                    <div class="match-value-label">PLC 샘플값</div>
                                    <div class="match-value-num mono"><%= h(fmtNum2(r.get("value_float"))) %></div>
                                </div>
                                <div class="match-value-box target">
                                    <div class="match-value-label"><%= h(targetValueLabel) %></div>
                                    <div class="match-value-num mono"><%= plcOnly ? "-" : h(fmtNum2(mv)) %></div>
                                </div>
                            </div>
                            <dl class="match-card-meta">
                                <dt>실제 의미</dt><dd><%= tokenMeaning == null || tokenMeaning.isEmpty() ? "-" : h(tokenMeaning) %></dd>
                                <dt>컬럼</dt><dd class="mono"><%= plcOnly ? "-" : h(col) %></dd>
                                <dt>대상 테이블</dt><dd class="mono"><%= h(targetTableLabel) %></dd>
                                <dt>float_regs</dt><dd class="mono"><%= r.get("float_registers") %></dd>
                                <dt>레지스터</dt><dd class="mono"><%= r.get("reg_address") %></dd>
                                <dt>PLC 샘플시각</dt><dd><%= r.get("measured_at") == null ? "-" : h(r.get("measured_at")) %></dd>
                                <dt>DB 비교 시각</dt><dd><%= h(targetMeasuredAtLabel) %></dd>
                            </dl>
                        </div>
                    <% } %>
                </div>
            </div>
        <% } %>
    </div>
    <% } %>

    <div class="section-title">2) 매핑 정의</div>
    <% if (!showMapping) { %>
    <div class="info-box">
        이 구간은 초기 로딩 속도를 위해 기본 숨김입니다.
        <a href="?plc_id=<%= plcId == null ? "" : plcId %>&meter_id=<%= meterId == null ? "" : meterId %>&show_mapping=1<%= autoRefresh ? "&auto_refresh=1" : "" %>">매핑 정의 펼치기</a>
    </div>
    <% } else { %>
    <div class="info-box">
        <a href="?plc_id=<%= plcId == null ? "" : plcId %>&meter_id=<%= meterId == null ? "" : meterId %><%= autoRefresh ? "&auto_refresh=1" : "" %>">매핑 정의 숨기기</a>
    </div>
    <table>
        <thead>
        <tr>
            <th>float_index</th>
            <th>tag token</th>
            <th>float_regs</th>
            <th>reg_address</th>
            <th>measurement_column</th>
            <th>supported</th>
            <th>target_table</th>
            <th>note</th>
        </tr>
        </thead>
        <tbody>
        <% for (Map<String, Object> r : mappingRows) { %>
        <tr>
            <td class="mono"><%= r.get("float_index") %></td>
            <td class="mono"><%= h(r.get("token")) %></td>
            <td class="mono"><%= r.get("float_registers") %></td>
            <td class="mono"><%= r.get("reg_address") == null ? "-" : h(r.get("reg_address")) %></td>
            <td class="mono"><%= r.get("measurement_column") == null ? "-" : h(r.get("measurement_column")) %></td>
            <td>
                <% if ((Boolean)r.get("is_supported")) { %><span class="badge b-ok">YES</span><% } else { %><span class="badge b-no">NO</span><% } %>
            </td>
            <td class="mono"><%= h(r.get("target_table")) %></td>
            <td><%= r.get("note") == null ? "-" : h(r.get("note")) %></td>
        </tr>
        <% } %>
        </tbody>
    </table>
    <% } %>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
<script>
(function() {
  var verifyForm = document.getElementById('verifyForm');
  var verifySubmitBtn = document.getElementById('verifySubmitBtn');
  var plcSelect = document.getElementById('plc_id');
  var meterSelect = document.getElementById('meter_id');
  var autoRefreshCheckbox = document.getElementById('auto_refresh');
  var autoRefreshStatus = document.getElementById('autoRefreshStatus');
  var refreshNotice = document.getElementById('refreshNotice');
  var autoRefreshTimer = null;
  var allMeterOptions = meterSelect ? Array.prototype.slice.call(meterSelect.querySelectorAll('option')).map(function(option) {
    return {
      value: option.value,
      text: option.textContent,
      selected: option.selected,
      meterName: option.getAttribute('data-meter-name') || '',
      panelName: option.getAttribute('data-panel-name') || ''
    };
  }) : [];
  var meterIdsByPlc = {
    <% boolean firstPlcMeterMap = true; for (Map.Entry<Integer, List<Integer>> entry : meterIdsByPlc.entrySet()) { %>
    <% if (!firstPlcMeterMap) { %>,<% } %>
    "<%= entry.getKey() %>":[<% for (int i = 0; i < entry.getValue().size(); i++) { %><%= i > 0 ? "," : "" %>"<%= entry.getValue().get(i) %>"<% } %>]
    <% firstPlcMeterMap = false; } %>
  };

  function resetSubmitButton() {
    if (verifySubmitBtn) {
      verifySubmitBtn.disabled = false;
      verifySubmitBtn.textContent = '검증 조회';
    }
  }

  function selectedPollingMs() {
    if (!plcSelect) return 0;
    var option = plcSelect.options[plcSelect.selectedIndex];
    if (!option) return 0;
    var pollingMs = parseInt(option.getAttribute('data-polling-ms') || '0', 10);
    return Number.isFinite(pollingMs) && pollingMs > 0 ? pollingMs : 0;
  }

  function stopAutoRefresh() {
    if (autoRefreshTimer) {
      clearTimeout(autoRefreshTimer);
      autoRefreshTimer = null;
    }
  }

  function rebuildMeterOptions() {
    if (!meterSelect) return;
    var selectedPlcId = plcSelect ? plcSelect.value : '';
    var allowedMeters = selectedPlcId ? (meterIdsByPlc[selectedPlcId] || []) : null;
    var currentMeterValue = meterSelect.value;
    meterSelect.innerHTML = '';

    function appendOption(data) {
      var option = document.createElement('option');
      option.value = data.value;
      option.textContent = data.text;
      if (data.meterName) option.setAttribute('data-meter-name', data.meterName);
      if (data.panelName) option.setAttribute('data-panel-name', data.panelName);
      meterSelect.appendChild(option);
    }

    allMeterOptions.forEach(function(data) {
      if (!selectedPlcId || data.value === '') {
        appendOption(data);
        return;
      }
      if (allowedMeters.indexOf(data.value) >= 0) {
        appendOption(data);
      }
    });

    if (currentMeterValue) {
      var hasCurrent = Array.prototype.some.call(meterSelect.options, function(option) {
        return option.value === currentMeterValue;
      });
      meterSelect.value = hasCurrent ? currentMeterValue : '';
    }
  }

  function submitForAutoRefresh() {
    if (!verifyForm) return;
    if (!autoRefreshCheckbox || !autoRefreshCheckbox.checked) return;
    if (!plcSelect || !plcSelect.value || !meterSelect || !meterSelect.value) return;
    verifyForm.requestSubmit ? verifyForm.requestSubmit() : verifyForm.submit();
  }

  function scheduleAutoRefresh() {
    stopAutoRefresh();
    var pollingMs = selectedPollingMs();
    var enabled = !!(autoRefreshCheckbox && autoRefreshCheckbox.checked);
    var ready = !!(plcSelect && plcSelect.value && meterSelect && meterSelect.value);
    if (autoRefreshStatus) {
      if (!enabled) autoRefreshStatus.textContent = '자동 갱신 꺼짐';
      else if (!ready) autoRefreshStatus.textContent = 'PLC와 Meter를 선택하면 자동 갱신됩니다.';
      else if (pollingMs > 0) autoRefreshStatus.textContent = '자동 갱신 주기: ' + pollingMs + 'ms';
      else autoRefreshStatus.textContent = '선택한 PLC의 polling 주기를 확인할 수 없습니다.';
    }
    if (refreshNotice) {
      if (enabled && ready && pollingMs > 0) {
        refreshNotice.innerHTML = '자동 갱신이 켜져 있습니다. 선택한 PLC의 polling 주기 <strong>' + pollingMs + 'ms</strong>마다 현재 조건으로 다시 조회합니다.';
      } else {
        refreshNotice.innerHTML = '자동 갱신은 선택한 PLC의 polling 주기(ms)를 기준으로 동작합니다. 자동 갱신을 켜면 해당 주기마다 현재 조건으로 다시 조회합니다.';
      }
    }
    if (!enabled || !ready || pollingMs <= 0) return;
    autoRefreshTimer = setTimeout(submitForAutoRefresh, pollingMs);
  }

  resetSubmitButton();
  window.addEventListener('pageshow', resetSubmitButton);
  window.addEventListener('pageshow', scheduleAutoRefresh);
  if (!verifyForm) return;
  if (plcSelect) plcSelect.addEventListener('change', function() {
    rebuildMeterOptions();
    scheduleAutoRefresh();
  });
  if (meterSelect) meterSelect.addEventListener('change', scheduleAutoRefresh);
  if (autoRefreshCheckbox) autoRefreshCheckbox.addEventListener('change', scheduleAutoRefresh);
  verifyForm.addEventListener('submit', function() {
    stopAutoRefresh();
    if (verifySubmitBtn) {
      verifySubmitBtn.disabled = true;
      verifySubmitBtn.textContent = '조회 중...';
    }
  });
  rebuildMeterOptions();
  scheduleAutoRefresh();
})();
</script>
</body>
</html>
<%
    } // end try-with-resources
%>
