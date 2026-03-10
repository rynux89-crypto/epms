<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ include file="../includes/dbconn.jsp" %>
<%@ include file="../includes/epms_html.jspf" %>
<%!
    private static String jsq(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }
%>
<%
    TreeSet<String> aiTokenSet = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
    TreeSet<String> aiMetricSet = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
    String loadErr = null;
    try {
        String ensureCatalogSql =
            "IF OBJECT_ID('dbo.metric_catalog','U') IS NULL " +
            "BEGIN " +
            "  CREATE TABLE dbo.metric_catalog ( " +
            "    metric_key VARCHAR(100) NOT NULL PRIMARY KEY, " +
            "    display_name NVARCHAR(150) NULL, " +
            "    source_type VARCHAR(20) NOT NULL DEFAULT 'AI', " +
            "    enabled BIT NOT NULL DEFAULT 1, " +
            "    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), " +
            "    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME() " +
            "  ); " +
            "END";
        try (Statement st = conn.createStatement()) {
            st.execute(ensureCatalogSql);
        }

        try (PreparedStatement ps = conn.prepareStatement("SELECT token, measurement_column FROM dbo.plc_ai_measurements_match");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String token = rs.getString("token");
                String col = rs.getString("measurement_column");
                if (token != null && !token.trim().isEmpty()) aiTokenSet.add(token.trim().toUpperCase(Locale.ROOT));
                if (col != null && !col.trim().isEmpty()) aiMetricSet.add(col.trim().toUpperCase(Locale.ROOT));
            }
        } catch (Exception ignore) {}

        try (PreparedStatement ps = conn.prepareStatement("SELECT metric_order FROM dbo.plc_meter_map WHERE enabled = 1");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String metricOrder = rs.getString(1);
                if (metricOrder == null || metricOrder.trim().isEmpty()) continue;
                String[] toks = metricOrder.split("\\s*,\\s*");
                for (String t : toks) {
                    if (t != null && !t.trim().isEmpty()) aiTokenSet.add(t.trim().toUpperCase(Locale.ROOT));
                }
            }
        } catch (Exception ignore) {}

        aiMetricSet.add("VOLTAGE");
        aiMetricSet.add("CURRENT");
        aiMetricSet.add("THD");
        aiMetricSet.add("THD_VOLTAGE");
        aiMetricSet.add("THD_CURRENT");
        aiMetricSet.add("UNBALANCE");
        aiMetricSet.add("VARIATION");
        aiMetricSet.add("POWER_FACTOR");
        aiMetricSet.add("FREQUENCY_GROUP");
        aiMetricSet.add("PEAK");
        aiMetricSet.add("MAX_POWER");

        // Keep existing alarm metric keys selectable as catalog entries.
        try (PreparedStatement ps = conn.prepareStatement("SELECT DISTINCT metric_key FROM dbo.alarm_rule");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String mk = rs.getString(1);
                if (mk != null && !mk.trim().isEmpty()) aiMetricSet.add(mk.trim().toUpperCase(Locale.ROOT));
            }
        } catch (Exception ignore) {}

        String mergeCatalogSql =
            "MERGE dbo.metric_catalog AS t " +
            "USING (SELECT ? AS metric_key, ? AS source_type) s " +
            "ON (t.metric_key = s.metric_key) " +
            "WHEN MATCHED THEN " +
            "  UPDATE SET display_name = COALESCE(NULLIF(t.display_name,''), s.metric_key), " +
            "             source_type = CASE WHEN UPPER(t.source_type)='DI' THEN t.source_type ELSE s.source_type END, " +
            "             enabled = 1, updated_at = SYSUTCDATETIME() " +
            "WHEN NOT MATCHED THEN " +
            "  INSERT (metric_key, display_name, source_type, enabled, created_at, updated_at) " +
            "  VALUES (s.metric_key, s.metric_key, s.source_type, 1, SYSUTCDATETIME(), SYSUTCDATETIME());";
        try (PreparedStatement ps = conn.prepareStatement(mergeCatalogSql)) {
            for (String mk : aiMetricSet) {
                ps.setString(1, mk);
                ps.setString(2, "AI");
                ps.executeUpdate();
            }
        }

        // Read metric keys from catalog (all enabled keys).
        aiMetricSet.clear();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT metric_key FROM dbo.metric_catalog WHERE enabled = 1 ORDER BY metric_key");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String mk = rs.getString(1);
                if (mk != null && !mk.trim().isEmpty()) aiMetricSet.add(mk.trim().toUpperCase(Locale.ROOT));
            }
        }
        // Safety net: always include keys already used by alarm rules.
        try (PreparedStatement ps = conn.prepareStatement("SELECT DISTINCT metric_key FROM dbo.alarm_rule");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String mk = rs.getString(1);
                if (mk != null && !mk.trim().isEmpty()) aiMetricSet.add(mk.trim().toUpperCase(Locale.ROOT));
            }
        } catch (Exception ignore) {}
    } catch (Exception e) {
        loadErr = e.getMessage();
    } finally {
        try { if (conn != null && !conn.isClosed()) conn.close(); } catch (Exception ignore) {}
    }
%><!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>EPMS 알람 규칙 등록</title>
    <link rel="stylesheet" type="text/css" href="<%= request.getContextPath() %>/css/main.css">
    <style>
        .page-wrap { max-width: 1300px; margin: 0 auto; }
        .note-box { margin: 10px 0; padding: 10px 12px; border-radius: 8px; background: #eef6ff; border: 1px solid #cfe2ff; color: #1d4f91; font-size: 13px; }
        .card {
            margin-top: 12px;
            background: #fff;
            border: 1px solid #dbe4ee;
            border-radius: 10px;
            box-shadow: 0 1px 4px rgba(0, 0, 0, 0.04);
            overflow: hidden;
        }
        .card-title {
            margin: 0;
            padding: 12px 14px;
            font-size: 16px;
            border-bottom: 1px solid #e6edf5;
            background: #f8fbff;
        }
        .card-body { padding: 14px; }
        .grid {
            display: grid;
            grid-template-columns: 150px 1fr 150px 1fr;
            gap: 10px 12px;
            align-items: center;
        }
        .full { grid-column: 1 / -1; }
        .required::after { content: " *"; color: #d93025; }
        .hint { font-size: 12px; color: #64748b; margin-top: 4px; }
        .di-only { display: none; }
        .mono { font-family: Consolas, "Courier New", monospace; }
        .radio-group { display: flex; align-items: center; gap: 14px; }
        .badge {
            display: inline-block;
            border-radius: 999px;
            padding: 3px 8px;
            font-size: 11px;
            font-weight: 700;
            border: 1px solid #cfd9e8;
            background: #eef3fb;
            color: #1f3b5f;
        }
        .type-guide {
            margin-top: 8px;
            padding: 8px 10px;
            border: 1px dashed #cfd9e8;
            border-radius: 8px;
            background: #fafcff;
            font-size: 12px;
            color: #4a5d78;
        }
        input[type="text"],
        input[type="number"],
        select,
        textarea {
            width: 100%;
            margin: 0;
            padding: 7px 9px;
            border: 1px solid #cfd9e8;
            border-radius: 6px;
            font-size: 13px;
            background: #fff;
        }
        textarea { min-height: 96px; resize: vertical; }
        .inline-group { display: flex; gap: 8px; align-items: center; }
        .inline-group input,
        .inline-group select { flex: 1; }
        .preview-box {
            margin-top: 8px;
            padding: 10px 12px;
            background: #f8fbff;
            border: 1px solid #dbe4ee;
            border-radius: 8px;
            font-size: 13px;
            line-height: 1.6;
        }
        .form-actions { display: flex; justify-content: flex-end; gap: 6px; margin-top: 12px; }
        @media (max-width: 980px) {
            .grid { grid-template-columns: 1fr; }
        }
    </style>
    <script>
        const DI_SIGNAL_PRESETS = [
            { code: 'DI_TRIP', label: '보호계전/차단 - TRIP', metricKey: 'DI_TRIP', category: 'SAFETY', severity: 'CRITICAL' },
            { code: 'DI_TR_ALARM', label: '보호계전/차단 - TR ALARM', metricKey: 'DI_TR_ALARM', category: 'SAFETY', severity: 'CRITICAL' },
            { code: 'DI_OCR_ALL_ON', label: '보호계전/차단 - OCR ALL ON', metricKey: 'DI_OCR_ALL_ON', category: 'SAFETY', severity: 'CRITICAL' },
            { code: 'DI_OCGR_ALL_ON', label: '보호계전/차단 - OCGR ALL ON', metricKey: 'DI_OCGR_ALL_ON', category: 'SAFETY', severity: 'CRITICAL' },
            { code: 'DI_OVR_ALL_ON', label: '보호계전/차단 - OVR ALL ON', metricKey: 'DI_OVR_ALL_ON', category: 'SAFETY', severity: 'CRITICAL' },
            { code: 'DI_ELD_ON', label: '안전/환경 - ELD 누전', metricKey: 'DI_ELD_ON', category: 'SAFETY', severity: 'CRITICAL' },
            { code: 'DI_TM_ON', label: '안전/환경 - TM 온도접점', metricKey: 'DI_TM_ON', category: 'SAFETY', severity: 'ALARM' },
            { code: 'DI_LIGHT_ON', label: '고장/경고 - 경고등', metricKey: 'DI_LIGHT_ON', category: 'FACILITY', severity: 'WARN' }
        ];
        const AI_TOKEN_OPTIONS = [
            <% int tokIdx = 0; for (String t : aiTokenSet) { if (tokIdx++ > 0) { %>,<% } %>"<%= jsq(t) %>"<% } %>
        ];
        const AI_METRIC_OPTIONS = [
            <% int metIdx = 0; for (String m : aiMetricSet) { if (metIdx++ > 0) { %>,<% } %>"<%= jsq(m) %>"<% } %>
        ];

        function getDiPresetByCode(code) {
            if (!code) return null;
            for (let i = 0; i < DI_SIGNAL_PRESETS.length; i++) {
                if (DI_SIGNAL_PRESETS[i].code === code) return DI_SIGNAL_PRESETS[i];
            }
            return null;
        }

        function buildSelectOptions(selectEl, values) {
            if (!selectEl) return;
            selectEl.innerHTML = '';
            const first = document.createElement('option');
            first.value = '';
            first.text = '선택';
            selectEl.appendChild(first);
            (values || []).forEach(function(v) {
                const opt = document.createElement('option');
                opt.value = v;
                opt.text = v;
                selectEl.appendChild(opt);
            });
        }

        function syncKeyFields() {
            const mkSel = document.getElementById('metricKeySelect');
            const stSel = document.getElementById('sourceTokenSelect');
            const mk = document.getElementById('metricKey');
            const st = document.getElementById('sourceToken');
            const sourceLocked = stSel && stSel.dataset.locked === '1';
            if (mk && mkSel) mk.value = mkSel.value || '';
            if (sourceLocked && stSel && mkSel) stSel.value = mkSel.value || '';
            if (st && stSel) st.value = stSel.value || '';
        }

        function setSourceLocked(locked) {
            const stSel = document.getElementById('sourceTokenSelect');
            const hint = document.getElementById('sourceTokenHint');
            if (!stSel) return;
            stSel.disabled = !!locked;
            stSel.dataset.locked = locked ? '1' : '0';
            if (hint) {
                hint.textContent = locked
                    ? 'DI 규칙은 지표키와 동일한 토큰으로 자동 연동됩니다.'
                    : '수집/매핑된 토큰 중에서 선택합니다.';
            }
        }

        function toggleDiFields(show) {
            document.querySelectorAll('.di-only').forEach(function(el) {
                el.style.display = show ? '' : 'none';
            });
        }

        function buildDiSignalOptions() {
            const sel = document.getElementById('diSignalType');
            if (!sel) return;
            sel.innerHTML = '';
            const first = document.createElement('option');
            first.value = '';
            first.text = '선택';
            sel.appendChild(first);
            DI_SIGNAL_PRESETS.forEach(function(p) {
                const opt = document.createElement('option');
                opt.value = p.code;
                opt.text = p.label;
                sel.appendChild(opt);
            });
        }

        function buildAiOptions() {
            const mkSel = document.getElementById('metricKeySelect');
            const stSel = document.getElementById('sourceTokenSelect');
            buildSelectOptions(mkSel, AI_METRIC_OPTIONS);
            buildSelectOptions(stSel, AI_TOKEN_OPTIONS);
            syncKeyFields();
        }

        function applyDiPreset() {
            const ruleType = document.querySelector('input[name="ruleType"]:checked')?.value;
            if (ruleType !== 'DI') return;

            const diType = document.getElementById('diSignalType');
            const metricKeySelect = document.getElementById('metricKeySelect');
            const sourceTokenSelect = document.getElementById('sourceTokenSelect');
            const operator = document.getElementById('operator');
            const threshold = document.getElementById('thresholdValue');
            const durationValue = document.getElementById('durationValue');
            const durationUnit = document.getElementById('durationUnit');
            const severity = document.getElementById('severity');
            const category = document.getElementById('category');
            const diPresetInfo = document.getElementById('diPresetInfo');
            const preset = getDiPresetByCode(diType ? diType.value : '');

            if (!preset) {
                if (diPresetInfo) diPresetInfo.value = '';
                updatePreview();
                return;
            }

            if (metricKeySelect) metricKeySelect.value = preset.metricKey;
            if (sourceTokenSelect) sourceTokenSelect.value = preset.metricKey;
            syncKeyFields();
            operator.value = '=';
            threshold.value = '1';
            durationValue.value = '0';
            durationUnit.value = 'sec';
            severity.value = preset.severity;
            if (category && preset.category) category.value = preset.category;
            if (diPresetInfo) {
                diPresetInfo.value = '권장: ' + preset.metricKey + ' = 1, 0 sec, ' + preset.severity;
            }
            updatePreview();
        }

        function updateRuleType() {
            const ruleType = document.querySelector('input[name="ruleType"]:checked').value;
            const categoryInput = document.getElementById('category');
            const targetScope = document.getElementById('targetScope');
            const threshold = document.getElementById('thresholdValue');
            const metricKeySelect = document.getElementById('metricKeySelect');
            const sourceTokenSelect = document.getElementById('sourceTokenSelect');
            const typeBadge = document.getElementById('typeBadge');
            const typeGuide = document.getElementById('typeGuide');

            if (ruleType === 'DI') {
                threshold.placeholder = '예: 1';
                typeBadge.innerText = 'DI 규칙';
                typeGuide.innerText = '센서/수집 데이터의 임계값 조건(연산자 + 임계값 + 지속시간)으로 알람을 판정합니다.';
                if (categoryInput) categoryInput.value = 'SAFETY';
                if (targetScope) targetScope.value = 'PLC';
                buildSelectOptions(metricKeySelect, DI_SIGNAL_PRESETS.map(p => p.metricKey));
                buildSelectOptions(sourceTokenSelect, DI_SIGNAL_PRESETS.map(p => p.metricKey));
                setSourceLocked(true);
                toggleDiFields(true);
            } else {
                threshold.placeholder = '예: 0.85, 0.90';
                typeBadge.innerText = 'AI 규칙';
                typeGuide.innerText = 'AI 분석 점수(이상도/위험도/예측치)를 기준으로 운영 알람을 판정합니다.';
                if (categoryInput) categoryInput.value = 'ANOMALY';
                if (targetScope) targetScope.value = 'AI';
                buildAiOptions();
                setSourceLocked(false);
                toggleDiFields(false);
                const diType = document.getElementById('diSignalType');
                const diPresetInfo = document.getElementById('diPresetInfo');
                if (diType) diType.value = '';
                if (diPresetInfo) diPresetInfo.value = '';
                syncKeyFields();
            }

            if (ruleType === 'DI') applyDiPreset();
            else syncKeyFields();
            updatePreview();
        }

        function resetFormData() {
            document.getElementById('alarmRuleForm').reset();
            document.getElementById('ruleTypeDI').checked = true;
            updateRuleType();
        }

        function updatePreview() {
            const ruleType = document.querySelector('input[name="ruleType"]:checked')?.value || '-';
            const diSignalType = document.getElementById('diSignalType');
            const diPreset = getDiPresetByCode(diSignalType ? diSignalType.value : '');
            const ruleCode = document.getElementById('ruleCode').value || '-';
            const ruleName = document.getElementById('ruleName').value || '-';
            const targetScope = document.getElementById('targetScope').value || '-';
            const metricKey = document.getElementById('metricKey').value || '-';
            const sourceToken = document.getElementById('sourceToken').value || '-';
            const operator = document.getElementById('operator').value || '-';
            const thresholdValue = document.getElementById('thresholdValue').value || '-';
            const durationValue = document.getElementById('durationValue').value || '-';
            const durationUnit = document.getElementById('durationUnit').value || '';
            const severity = document.getElementById('severity').value || '-';
            const messageTemplate = document.getElementById('messageTemplate').value || '-';
            const description = document.getElementById('descriptionRaw').value || '-';

            document.getElementById('preview').innerHTML =
                '<b>규칙유형</b> : ' + ruleType + '<br>' +
                '<b>알람 규칙코드</b> : ' + ruleCode + '<br>' +
                '<b>규칙명</b> : ' + ruleName + '<br>' +
                '<b>적용대상</b> : ' + targetScope + '<br>' +
                (ruleType === 'DI' ? ('<b>DI 신호종류</b> : ' + (diPreset ? diPreset.label : '-') + '<br>') : '') +
                '<b>지표키</b> : ' + metricKey + '<br>' +
                '<b>연결 Token/Tag</b> : ' + sourceToken + '<br>' +
                '<b>조건</b> : ' + metricKey + ' ' + operator + ' ' + thresholdValue + '<br>' +
                '<b>지속시간</b> : ' + durationValue + ' ' + durationUnit + '<br>' +
                '<b>심각도</b> : ' + severity + '<br>' +
                '<b>알람 메시지 템플릿</b> : ' + messageTemplate + '<br>' +
                '<b>설명</b> : ' + description;
        }

        function toDurationSec() {
            const v = parseInt(document.getElementById('durationValue').value || '0', 10);
            const unit = document.getElementById('durationUnit').value || 'sec';
            const base = Number.isFinite(v) && v > 0 ? v : 0;
            if (unit === 'hour') return base * 3600;
            if (unit === 'min') return base * 60;
            return base;
        }

        function buildDescriptionPayload() {
            const descRaw = document.getElementById('descriptionRaw').value || '';
            const sourceToken = document.getElementById('sourceToken').value || '';
            const msgTpl = document.getElementById('messageTemplate').value || '';
            const meta = [];
            if (sourceToken.trim()) meta.push('source_token=' + sourceToken.trim());
            if (msgTpl.trim()) meta.push('msg_template=' + msgTpl.trim());
            if (meta.length === 0) return descRaw.trim();
            if (!descRaw.trim()) return meta.join(' | ');
            return descRaw.trim() + '\n' + meta.join(' | ');
        }

        function validateForm() {
            const requiredIds = ['ruleCode', 'ruleName', 'targetScope', 'metricKey', 'sourceToken', 'operator', 'thresholdValue', 'durationUnit', 'severity'];
            for (let i = 0; i < requiredIds.length; i++) {
                const el = document.getElementById(requiredIds[i]);
                if (!el.value || el.value.trim() === '') {
                    alert('필수 항목을 입력해 주세요.');
                    el.focus();
                    return false;
                }
            }
            const ruleType = document.querySelector('input[name="ruleType"]:checked')?.value;
            if (ruleType === 'DI') {
                const diType = document.getElementById('diSignalType');
                if (!diType || !diType.value) {
                    alert('DI 신호종류를 선택해 주세요.');
                    if (diType) diType.focus();
                    return false;
                }
            }
            document.getElementById('durationSec').value = String(toDurationSec());
            document.getElementById('description').value = buildDescriptionPayload();
            return true;
        }

        window.onload = function() {
            buildDiSignalOptions();
            buildAiOptions();
            updateRuleType();
            const inputs = document.querySelectorAll('input, select, textarea');
            inputs.forEach(function(el) {
                el.addEventListener('input', updatePreview);
                el.addEventListener('change', updatePreview);
            });
            const diType = document.getElementById('diSignalType');
            if (diType) diType.addEventListener('change', applyDiPreset);
            const mkSel = document.getElementById('metricKeySelect');
            const stSel = document.getElementById('sourceTokenSelect');
            if (mkSel) mkSel.addEventListener('change', function(){ syncKeyFields(); updatePreview(); });
            if (stSel) stSel.addEventListener('change', function(){ syncKeyFields(); updatePreview(); });
        };
    </script>
</head>
<body>
<div class="page-wrap">
    <div class="title-bar">
        <h2>알람 규칙 등록</h2>
        <div style="display:flex; gap:8px;">
            <button class="back-btn" onclick="location.href='/epms/alarm_rule_manage.jsp'">알람 규칙 관리</button>
            <button class="back-btn" onclick="location.href='/epms/epms_main.jsp'">EPMS 메인</button>
        </div>
    </div>

    <div class="note-box">
        EPMS 운영 기준으로 DI/AI 알람 규칙을 등록합니다. 규칙은 metric_key + token/tag를 기준으로 어떤 데이터와 연결되는지 추적 가능해야 합니다.
    </div>
    <% if (loadErr != null && !loadErr.trim().isEmpty()) { %>
    <div class="note-box" style="background:#fff6f6; border-color:#f4caca; color:#9f2d2d;">
        토큰 목록을 불러오지 못했습니다: <%= h(loadErr) %>
    </div>
    <% } %>

    <form id="alarmRuleForm" method="post" action="<%=request.getContextPath()%>/epms/alarm_rule_manage.jsp" onsubmit="return validateForm();">
        <input type="hidden" name="action" value="add">
        <input type="hidden" id="category" name="category" value="SAFETY">
        <input type="hidden" id="durationSec" name="duration_sec" value="0">
        <input type="hidden" id="metricKey" name="metric_key" value="">
        <input type="hidden" id="sourceToken" name="source_token" value="">
        <input type="hidden" name="threshold2" value="">
        <input type="hidden" name="hysteresis" value="">
        <input type="hidden" id="description" name="description" value="">
        <div class="card">
            <h3 class="card-title">기본 정보</h3>
            <div class="card-body">
                <div class="grid">
                    <label class="required">규칙유형</label>
                    <div>
                        <div class="radio-group">
                            <label><input type="radio" id="ruleTypeDI" name="ruleType" value="DI" checked onclick="updateRuleType()"> DI</label>
                            <label><input type="radio" name="ruleType" value="AI" onclick="updateRuleType()"> AI</label>
                            <span id="typeBadge" class="badge">DI 규칙</span>
                        </div>
                        <div id="typeGuide" class="type-guide"></div>
                    </div>

                    <label class="required">알람 규칙코드</label>
                    <div>
                        <input type="text" id="ruleCode" name="rule_code" maxlength="50" placeholder="예: ALM_DI_TEMP_001" class="mono">
                        <div class="hint">영문/숫자/언더스코어 권장, 중복 불가</div>
                    </div>

                    <label class="required">규칙명</label>
                    <div>
                        <input type="text" id="ruleName" name="rule_name" maxlength="100" placeholder="예: Chiller High Temperature">
                    </div>

                    <label class="required">적용대상</label>
                    <div>
                        <select id="targetScope" name="target_scope" class="mono">
                            <option value="PLC">PLC (DI)</option>
                            <option value="AI">AI</option>
                            <option value="METER">METER</option>
                        </select>
                    </div>

                    <label>설명</label>
                    <div class="full">
                        <textarea id="descriptionRaw" placeholder="규칙 목적, 대상 설비, 운영 기준을 입력하세요."></textarea>
                    </div>
                </div>
            </div>
        </div>

        <div class="card">
            <h3 class="card-title">조건 설정</h3>
            <div class="card-body">
                <div class="grid">
                    <label class="required di-only">DI 신호종류</label>
                    <div class="di-only">
                        <select id="diSignalType" name="diSignalType"></select>
                        <div class="hint">보호계전/경고 DI 의미별로 분류해서 규칙을 설정합니다.</div>
                    </div>

                    <label class="di-only">권장값</label>
                    <div class="di-only">
                        <input type="text" id="diPresetInfo" readonly placeholder="DI 신호종류 선택 시 자동 표시">
                    </div>

                    <label class="required">지표키</label>
                    <div>
                        <select id="metricKeySelect" class="mono"></select>
                        <div class="hint">자유 입력 대신 등록된 metric_key만 선택합니다.</div>
                    </div>

                    <label class="required">연결 Token/Tag</label>
                    <div>
                        <select id="sourceTokenSelect" class="mono"></select>
                        <div class="hint" id="sourceTokenHint">자유 입력 대신 수집/매핑된 토큰만 선택합니다.</div>
                    </div>

                    <label class="required">연산자</label>
                    <div>
                        <select id="operator" name="operator">
                            <option value="">선택</option>
                            <option value=">">&gt;</option>
                            <option value=">=">&gt;=</option>
                            <option value="<">&lt;</option>
                            <option value="<=">&lt;=</option>
                            <option value="=">=</option>
                            <option value="!=">!=</option>
                        </select>
                    </div>

                    <label class="required">임계값</label>
                    <div>
                        <input type="number" step="0.0001" id="thresholdValue" name="threshold1" placeholder="예: 75">
                    </div>

                    <label class="required">지속시간</label>
                    <div class="inline-group">
                        <input type="number" min="0" id="durationValue" placeholder="예: 5">
                        <select id="durationUnit">
                            <option value="">단위</option>
                            <option value="sec">sec</option>
                            <option value="min">min</option>
                            <option value="hour">hour</option>
                        </select>
                    </div>
                </div>
            </div>
        </div>

        <div class="card">
            <h3 class="card-title">알람 설정</h3>
            <div class="card-body">
                <div class="grid">
                    <label class="required">심각도</label>
                    <div>
                        <select id="severity" name="severity" class="mono">
                            <option value="">선택</option>
                            <option value="WARN">WARN</option>
                            <option value="ALARM">ALARM</option>
                            <option value="CRITICAL">CRITICAL</option>
                        </select>
                    </div>

                    <label>알람 메시지 템플릿</label>
                    <div class="full">
                        <input type="text" id="messageTemplate" name="message_template" placeholder="예: {metric_key}={value} 임계치 초과">
                    </div>
                </div>
            </div>
        </div>

        <div class="card">
            <h3 class="card-title">규칙 미리보기</h3>
            <div class="card-body">
                <div id="preview" class="preview-box">입력값을 바탕으로 규칙 요약이 표시됩니다.</div>
            </div>
        </div>

        <div class="form-actions">
            <button type="button" onclick="resetFormData();">초기화</button>
            <button type="submit">규칙 저장</button>
        </div>
    </form>
</div>
<footer>© EPMS Dashboard | SNUT CNT</footer>
</body>
</html>


