package epms.util;

import java.util.Locale;

public final class AgentQueryRouter {
    private AgentQueryRouter() {
    }

    public enum Mode {
        DEFAULT,
        LLM_ONLY,
        RULE_ONLY
    }

    public static final class ParsedQuery {
        public final Mode mode;
        public final String userMessage;
        public final boolean prefersNarrativeLlm;

        public ParsedQuery(Mode mode, String userMessage, boolean prefersNarrativeLlm) {
            this.mode = mode;
            this.userMessage = userMessage;
            this.prefersNarrativeLlm = prefersNarrativeLlm;
        }
    }

    public static ParsedQuery parse(String rawMessage) {
        String message = EpmsWebUtil.trimToNull(rawMessage);
        if (message == null) {
            return new ParsedQuery(Mode.DEFAULT, "", false);
        }

        Mode mode = Mode.DEFAULT;
        String normalized = message.trim();
        String lower = normalized.toLowerCase(Locale.ROOT);
        if (lower.startsWith("/llm ")) {
            mode = Mode.LLM_ONLY;
            normalized = normalized.substring(5).trim();
        } else if (lower.startsWith("/rule ")) {
            mode = Mode.RULE_ONLY;
            normalized = normalized.substring(6).trim();
        }

        return new ParsedQuery(mode, normalized, prefersNarrativeLlm(normalized));
    }

    public static boolean prefersNarrativeLlm(String userMessage) {
        String m = normalize(userMessage);
        boolean hasNarrativeIntent =
            m.contains("\uD574\uC11D") || m.contains("\uC124\uBA85") || m.contains("\uC694\uC57D")
            || m.contains("\uBCF4\uACE0\uC11C") || m.contains("\uBD84\uC11D") || m.contains("\uD3C9\uAC00")
            || m.contains("\uCD94\uB860") || m.contains("\uC9C4\uB2E8") || m.contains("\uBE0C\uB9AC\uD551")
            || m.contains("\uC54C\uB824") || m.contains("\uC548\uB0B4") || m.contains("\uCCB4\uD06C\uB9AC\uC2A4\uD2B8")
            || m.contains("\uD56D\uBAA9") || m.contains("\uC21C\uC11C") || m.contains("\uC808\uCC28")
            || m.contains("\uC6D0\uC778") || m.contains("\uC810\uAC80");
        boolean hasCombinedIntent =
            (m.contains("\uACC4\uCE21") || m.contains("\uC0C1\uD0DC") || m.contains("\uCE21\uC815"))
            && (m.contains("\uC54C\uB78C") || m.contains("\uACBD\uBCF4"));
        boolean hasQualityOpsIntent =
            (m.contains("\uC5ED\uB960") || m.contains("powerfactor") || m.contains("pf")
                || m.contains("\uC8FC\uD30C\uC218") || m.contains("frequency")
                || m.contains("\uACE0\uC870\uD30C") || m.contains("harmonic")
                || m.contains("\uBD88\uD3C9\uD615") || m.contains("unbalance"))
            && (m.contains("\uC6B4\uC601\uC790") || m.contains("\uB2F4\uB2F9\uC790")
                || m.contains("\uBB50\uBD80\uD130") || m.contains("\uBA3C\uC800")
                || m.contains("\uD56D\uBAA9") || m.contains("\uC21C\uC11C")
                || m.contains("\uC808\uCC28") || m.contains("\uC810\uAC80")
                || m.contains("\uC6D0\uC778") || m.contains("\uB300\uC751"));
        return (hasNarrativeIntent && hasCombinedIntent) || (hasNarrativeIntent && hasQualityOpsIntent);
    }

    public static boolean wantsMeterSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean meterWord = m.contains("meter") || m.contains("\uBBF8\uD130") || m.contains("\uACC4\uCE21\uAE30");
        boolean meterIntentWord =
            m.contains("\uCD5C\uADFC\uACC4\uCE21") || m.contains("\uCD5C\uC2E0\uACC4\uCE21")
            || m.contains("\uCD5C\uADFC\uCE21\uC815") || m.contains("\uCD5C\uC2E0\uCE21\uC815")
            || m.contains("\uACC4\uCE21\uAC12") || m.contains("measurement") || m.contains("\uC2E4\uC2DC\uAC04\uC0C1\uD0DC")
            || m.contains("\uD604\uC7AC\uC0C1\uD0DC")
            || m.contains("\uC804\uC555\uAC12") || m.contains("\uC804\uB958\uAC12")
            || m.contains("\uC5ED\uB960") || m.contains("\uC804\uB825\uAC12") || m.contains("kw");
        boolean electricalWord =
            m.contains("\uC804\uC555") || m.contains("voltage")
            || m.contains("\uC804\uB958") || m.contains("current")
            || m.contains("\uC804\uB825") || m.contains("power")
            || m.contains("\uC5ED\uB960") || m.contains("pf");
        boolean recentWord =
            m.contains("\uCD5C\uADFC") || m.contains("\uCD5C\uC2E0") || m.contains("\uC2E4\uC2DC\uAC04")
            || m.contains("current") || m.contains("latest");
        boolean statusWord = m.contains("\uC0C1\uD0DC") || m.contains("status");
        boolean hasMeterCode = m.matches(".*[a-z]{2,}_[a-z0-9_\\-]{2,}.*");
        boolean askForm = m.endsWith("?") || m.endsWith("\uB294?") || m.endsWith("\uC740?");
        boolean sqlLike = m.contains("select") || m.contains("where") || m.contains("join")
            || m.contains("query") || m.contains("sql") || m.contains("\uD14C\uC774\uBE14") || m.contains("\uCEEC\uB7FC");
        if (sqlLike) return false;
        if (hasMeterCode && (statusWord || askForm)) return true;
        if (meterWord && statusWord) return true;
        if (meterWord && electricalWord) return true;
        if (electricalWord && recentWord && (m.contains("\uACC4\uCE21\uAE30") || meterWord)) return true;
        return meterIntentWord || (meterWord && (m.contains("\uAC12") || m.contains("value") || m.contains("status") || m.contains("\uC0C1\uD0DC")));
    }

    public static boolean wantsAlarmSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarmWord = m.contains("\uC54C\uB78C") || m.contains("\uACBD\uBCF4") || m.contains("alarm") || m.contains("alert");
        boolean hasSummaryIntent = m.contains("\uCD5C\uADFC") || m.contains("\uCD5C\uC2E0") || m.contains("\uC694\uC57D")
            || m.contains("\uBCF4\uC5EC") || m.contains("\uC54C\uB824") || m.contains("\uBAA9\uB85D") || m.contains("\uAC19\uC774");
        return m.contains("\uCD5C\uADFC\uC54C\uB78C") || m.contains("\uCD5C\uC2E0\uC54C\uB78C")
            || m.contains("\uC54C\uB78C\uC694\uC57D") || m.contains("\uACBD\uBCF4\uC694\uC57D")
            || m.contains("alarm") || m.contains("alert")
            || m.contains("\uC774\uC0C1\uB0B4\uC5ED")
            || (hasAlarmWord && hasSummaryIntent);
    }

    public static boolean wantsMonthlyFrequencySummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasFrequency = m.contains("\uC8FC\uD30C\uC218") || m.contains("frequency") || m.contains("hz");
        boolean hasAverage = m.contains("\uD3C9\uADE0") || m.contains("avg") || m.contains("mean");
        boolean hasPeriod = m.contains("\uC6D4") || m.contains("month");
        return hasFrequency && (hasAverage || hasPeriod);
    }

    public static boolean wantsPerMeterPowerSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean meterScope = m.contains("\uAC01\uACC4\uCE21\uAE30") || m.contains("\uBAA8\uB4E0\uACC4\uCE21\uAE30") || m.contains("\uACC4\uCE21\uAE30\uBCC4")
            || (m.contains("\uAC01") && m.contains("\uACC4\uCE21\uAE30")) || (m.contains("all") && m.contains("meter"));
        boolean powerWord = m.contains("\uC804\uB825\uB7C9") || m.contains("\uC804\uB825") || m.contains("\uC0AC\uC6A9\uC804\uB825")
            || m.contains("kw") || m.contains("kwh") || m.contains("power");
        return meterScope && powerWord;
    }

    public static boolean wantsHarmonicSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasHarmonic = m.contains("\uACE0\uC870\uD30C") || m.contains("harmonic") || m.contains("thd");
        boolean hasSummaryIntent =
            m.contains("\uC0C1\uD0DC") || m.contains("\uC694\uC57D") || m.contains("\uD604\uC7AC")
            || m.contains("\uCD5C\uC2E0") || m.contains("\uAC12") || m.contains("\uBCF4\uC5EC")
            || m.contains("\uC54C\uB824") || m.contains("status") || m.contains("summary")
            || m.contains("current") || m.contains("latest");
        boolean hasOutlierIntent =
            m.contains("\uCD08\uACFC") || m.contains("\uAE30\uC900") || m.contains("threshold")
            || m.contains("over") || m.contains("\uC774\uC0C1") || m.contains("\uBE44\uC815\uC0C1")
            || m.contains("\uBB38\uC81C");
        return hasHarmonic && (hasSummaryIntent || !hasOutlierIntent);
    }

    public static boolean wantsMeterListSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasList = m.contains("\uB9AC\uC2A4\uD2B8") || m.contains("\uBAA9\uB85D") || m.contains("list");
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter") || m.contains("\uAC8C\uCE20\uAE30");
        boolean hasScoped = m.contains("\uAD00\uB828\uB41C") || m.contains("\uC758");
        boolean hasStatusIntent =
            m.contains("\uC0C1\uD0DC") || m.contains("\uD604\uC7AC\uC0C1\uD0DC") || m.contains("\uC2E4\uC2DC\uAC04\uC0C1\uD0DC")
            || m.contains("\uACC4\uCE21\uAC12") || m.contains("\uC804\uC555") || m.contains("\uC804\uB958")
            || m.contains("\uC5ED\uB960") || m.contains("\uC804\uB825") || m.contains("\uC8FC\uD30C\uC218")
            || m.contains("\uAC12") || m.contains("status") || m.contains("current")
            || m.contains("latest") || m.contains("measurement");
        boolean hasHarmonicIntent =
            m.contains("\uACE0\uC870\uD30C") || m.contains("harmonic") || m.contains("thd")
            || m.contains("\uC65C\uD615\uB960") || m.contains("\uD5C8\uD615\uC728");
        boolean askMeter =
            (hasMeter && (m.endsWith("\uB294?") || m.endsWith("\uC740?") || m.endsWith("?")))
            || m.contains("\uACC4\uCE21\uAE30\uB294") || m.contains("\uACC4\uCE21\uAE30?")
            || m.contains("\uBBF8\uD130\uB294") || m.contains("meter?");
        if (hasStatusIntent || hasHarmonicIntent) return false;
        return (hasList && (hasMeter || hasScoped)) || (hasMeter && hasScoped && askMeter);
    }

    public static boolean wantsMeterCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter") || m.contains("\uAC8C\uCE20\uAE30");
        boolean hasCount =
            m.contains("\uBA87\uAC1C") || m.contains("\uBA87\uAC1C\uC57C") || m.contains("\uAC1C\uC218")
            || m.contains("\uAC2F\uC218") || m.contains("\uC218\uB294") || m.contains("\uC218\uC54C\uB824")
            || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC") || m.contains("\uCD1D\uAC1C\uC218")
            || m.contains("count") || m.contains("\uBA87\uB300") || m.contains("\uCD1D\uBA87")
            || m.matches(".*\uACC4\uCE21\uAE30.*\uC218.*\uC54C\uB824.*") || m.matches(".*meter.*count.*");
        boolean hasList = m.contains("\uB9AC\uC2A4\uD2B8") || m.contains("\uBAA9\uB85D") || m.contains("list");
        return hasMeter && hasCount && !hasList;
    }

    public static boolean wantsPanelCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPanel = m.contains("\uD328\uB110") || m.contains("\uD310\uB12C") || m.contains("panel");
        boolean hasCount =
            m.contains("\uBA87\uAC1C") || m.contains("\uBA87\uAC1C\uC57C") || m.contains("\uAC1C\uC218")
            || m.contains("\uAC2F\uC218") || m.contains("\uC218\uB294") || m.contains("\uC218\uC54C\uB824")
            || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC") || m.contains("\uCD1D\uAC1C\uC218")
            || m.contains("count") || m.contains("\uBA87\uAC1C\uD328\uB110") || m.matches(".*\uD328\uB110.*\uC218.*\uC54C\uB824.*");
        boolean hasStatus = m.contains("\uC0C1\uD0DC") || m.contains("status");
        return hasPanel && hasCount && !hasStatus;
    }

    public static boolean wantsBuildingCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasBuilding = m.contains("\uAC74\uBB3C") || m.contains("building");
        boolean hasCount =
            m.contains("\uBA87\uAC1C") || m.contains("\uBA87\uAC1C\uC57C") || m.contains("\uAC1C\uC218")
            || m.contains("\uAC2F\uC218") || m.contains("\uC218\uB294") || m.contains("\uC218\uC54C\uB824")
            || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC") || m.contains("\uCD1D\uAC1C\uC218")
            || m.contains("count") || m.matches(".*\uAC74\uBB3C.*\uC218.*\uC54C\uB824.*");
        return hasBuilding && hasCount;
    }

    public static boolean wantsUsageTypeCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasUsage = m.contains("\uC6A9\uB3C4") || m.contains("\uC0AC\uC6A9\uCC98") || m.contains("usage");
        boolean hasCount =
            m.contains("\uBA87\uAC1C") || m.contains("\uBA87\uAC1C\uC57C") || m.contains("\uAC1C\uC218")
            || m.contains("\uAC2F\uC218") || m.contains("\uC218\uB294") || m.contains("\uC218\uC54C\uB824")
            || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC") || m.contains("\uCD1D\uAC1C\uC218")
            || m.contains("count") || m.matches(".*\uC6A9\uB3C4.*\uC218.*\uC54C\uB824.*") || m.matches(".*\uC0AC\uC6A9\uCC98.*\uC218.*\uC54C\uB824.*");
        return hasUsage && hasCount;
    }

    public static boolean wantsUsageTypeListSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasUsage = m.contains("\uC6A9\uB3C4") || m.contains("\uC0AC\uC6A9\uCC98") || m.contains("usage");
        boolean hasList =
            m.contains("\uB9AC\uC2A4\uD2B8") || m.contains("\uBAA9\uB85D") || m.contains("list")
            || m.contains("\uC885\uB958") || m.contains("\uD56D\uBAA9") || m.contains("\uBCF4\uC5EC")
            || m.contains("\uC54C\uB824");
        boolean hasCount =
            m.contains("\uBA87\uAC1C") || m.contains("\uBA87\uAC1C\uC57C") || m.contains("\uAC1C\uC218")
            || m.contains("\uAC2F\uC218") || m.contains("\uC218\uB294") || m.contains("\uCD1D\uAC1C\uC218")
            || m.contains("count");
        boolean hasPowerIntent =
            m.contains("\uC804\uB825") || m.contains("\uC804\uB825\uB7C9") || m.contains("\uC0AC\uC6A9\uB7C9")
            || m.contains("power") || m.contains("kwh") || m.contains("kw");
        return hasUsage && hasList && !hasCount && !hasPowerIntent;
    }

    public static boolean wantsAlarmSeveritySummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("alarm") || m.contains("\uACBD\uBCF4");
        boolean hasSeverity = m.contains("\uC2EC\uAC01\uB3C4") || m.contains("severity");
        return hasAlarm && hasSeverity;
    }

    public static boolean wantsAlarmTypeSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("alarm") || m.contains("\uACBD\uBCF4");
        boolean hasType = m.contains("\uC885\uB958") || m.contains("\uC720\uD615") || m.contains("\uD0C0\uC785")
            || m.contains("type") || m.contains("\uBB34\uC2A8\uC54C\uB78C") || m.contains("\uC5B4\uB5A4\uC54C\uB78C");
        boolean hasSeverity = m.contains("\uC2EC\uAC01\uB3C4") || m.contains("severity");
        return hasAlarm && hasType && !hasSeverity;
    }

    public static boolean wantsAlarmCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("alarm") || m.contains("\uACBD\uBCF4");
        boolean hasCount = m.contains("\uAC74\uC218") || m.contains("\uAC1C\uC218") || m.contains("\uAC2F\uC218") || m.contains("count")
            || m.contains("\uBA87\uAC74") || m.contains("\uBA87\uAC1C")
            || m.contains("\uC54C\uB78C\uC758\uC218") || m.contains("\uC218\uB294") || m.contains("\uC218\uC54C\uB824")
            || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC")
            || m.matches(".*\uC54C\uB78C.*\uC218.*\uC54C\uB824.*") || m.endsWith("\uC218");
        boolean hasOccurred = m.contains("\uBC1C\uC0DD") || m.contains("trigger");
        return hasAlarm && (hasCount || hasOccurred || m.endsWith("\uC218\uB294?") || m.endsWith("\uC218?"));
    }

    public static boolean wantsOpenAlarms(String userMessage) {
        String m = normalize(userMessage);
        return (m.contains("\uBBF8\uD574\uACB0") || m.contains("\uC5F4\uB9B0") || m.contains("open"))
            && (m.contains("\uC54C\uB78C") || m.contains("alarm"));
    }

    public static boolean wantsOpenAlarmCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasOpen = m.contains("\uBBF8\uD574\uACB0") || m.contains("\uC5F4\uB9B0") || m.contains("open");
        boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("alarm") || m.contains("\uACBD\uBCF4");
        boolean hasCount = m.contains("\uAC74\uC218") || m.contains("\uAC1C\uC218") || m.contains("\uAC2F\uC218") || m.contains("count")
            || m.contains("\uBA87\uAC74") || m.contains("\uBA87\uAC1C")
            || m.contains("\uC218\uB294") || m.contains("\uC218\uC54C\uB824") || m.contains("\uC218\uB97C\uC54C\uB824") || m.contains("\uC218\uB97C\uBCF4\uC5EC");
        return hasOpen && hasAlarm && hasCount;
    }

    public static boolean wantsAlarmMeterTopN(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("\uC54C\uB78C") || m.contains("alarm") || m.contains("\uACBD\uBCF4");
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter");
        boolean hasRanking =
            m.contains("top") || m.contains("\uC0C1\uC704") || m.contains("\uB9CE\uC740")
            || m.contains("\uB9CE\uC774\uBC1C\uC0DD") || m.contains("\uC790\uC8FC")
            || m.contains("\uBAA9\uB85D") || m.contains("\uBCF4\uC5EC") || m.contains("\uC54C\uB824");
        boolean hasCountHint =
            m.contains("\uAC74\uC218") || m.contains("\uAC1C\uC218") || m.contains("\uC218")
            || m.contains("\uBC1C\uC0DD");
        return hasAlarm && hasMeter && hasRanking && hasCountHint;
    }

    public static boolean wantsBuildingPowerTopN(String userMessage) {
        String m = normalize(userMessage);
        boolean hasBuilding = m.contains("\uAC74\uBB3C") || m.contains("building");
        boolean hasPower = m.contains("\uC804\uB825") || m.contains("\uC804\uB825\uB7C9") || m.contains("\uC0AC\uC6A9\uC804\uB825")
            || m.contains("kw") || m.contains("kwh") || m.contains("power");
        boolean hasTop = m.contains("top") || m.contains("\uC0C1\uC704") || m.matches(".*[0-9]+\uAC1C.*");
        boolean hasListIntent = m.contains("\uBCC4") || m.contains("\uBE44\uAD50") || m.contains("\uBAA9\uB85D") || m.contains("\uBCF4\uC5EC");
        return hasBuilding && hasPower && (hasTop || hasListIntent || m.endsWith("\uC740?") || m.endsWith("?"));
    }

    public static boolean wantsPanelLatestStatus(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPanel = m.contains("\uD328\uB110") || m.contains("panel") || m.contains("\uD310\uB12C") || m.contains("\uACC4\uC5F4");
        boolean hasStatus = m.contains("\uC0C1\uD0DC") || m.contains("status");
        boolean hasPanelCode = m.matches(".*(mdb|vcb|acb)[a-z0-9_\\-]*.*");
        boolean hasMeterScope = m.contains("\uACC4\uCE21\uAE30") || m.contains("meter");
        if (hasMeterScope && !hasPanel) return false;
        return (hasPanel || hasPanelCode) && hasStatus;
    }

    public static boolean wantsHarmonicExceed(String userMessage) {
        String m = normalize(userMessage);
        boolean hasHarmonic = m.contains("\uACE0\uC870\uD30C") || m.contains("harmonic") || m.contains("thd");
        boolean hasOutlier = m.contains("\uCD08\uACFC") || m.contains("\uAE30\uC900") || m.contains("threshold") || m.contains("over")
            || m.contains("\uC774\uC0C1") || m.contains("\uBE44\uC815\uC0C1") || m.contains("\uBB38\uC81C");
        return hasHarmonic && hasOutlier;
    }

    public static boolean wantsFrequencyOutlier(String userMessage) {
        String m = normalize(userMessage);
        return (m.contains("\uC8FC\uD30C\uC218") || m.contains("frequency") || m.contains("hz"))
            && (m.contains("\uC774\uC0C1") || m.contains("\uBBF8\uB9CC") || m.contains("\uCD08\uACFC") || m.contains("outlier"));
    }

    public static boolean wantsVoltageUnbalanceTopN(String userMessage) {
        String m = normalize(userMessage);
        boolean hasUnbalance =
            m.contains("\uBD88\uD3C9\uD615") || m.contains("\uBD88\uADE0\uD615")
            || m.contains("\uC804\uC555\uBD88\uD3C9\uD615") || m.contains("\uC804\uC555\uBD88\uADE0\uD615")
            || m.contains("unbalance");
        boolean hasListIntent =
            m.contains("top") || m.contains("\uC0C1\uC704")
            || m.contains("\uBCF4\uC5EC\uC918") || m.contains("\uBAA9\uB85D") || m.contains("\uB9AC\uC2A4\uD2B8")
            || m.matches(".*[0-9]+\uAC1C.*");
        return hasUnbalance && (hasListIntent || m.contains("\uACC4\uCE21\uAE30"));
    }

    public static boolean wantsPowerFactorOutlier(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPf = m.contains("\uC5ED\uB960") || m.contains("powerfactor") || m.contains("pf");
        boolean hasOutlier = m.contains("\uC774\uC0C1") || m.contains("\uBE44\uC815\uC0C1") || m.contains("\uBB38\uC81C")
            || m.contains("\uB0AE") || m.contains("high") || m.contains("low");
        boolean hasMeterScope = m.contains("\uACC4\uCE21\uAE30") || m.contains("meter") || m.contains("\uBAA9\uB85D") || m.contains("\uBCF4\uC5EC");
        boolean hasGuidanceIntent =
            m.contains("\uC6B4\uC601\uC790") || m.contains("\uB2F4\uB2F9\uC790")
            || m.contains("\uC54C\uB824") || m.contains("\uC124\uBA85") || m.contains("\uD574\uC11D")
            || m.contains("\uC6D0\uC778") || m.contains("\uC810\uAC80") || m.contains("\uC21C\uC11C")
            || m.contains("\uC808\uCC28") || m.contains("\uD56D\uBAA9") || m.contains("\uCCB4\uD06C\uB9AC\uC2A4\uD2B8")
            || m.contains("\uBB50\uBD80\uD130") || m.contains("\uBA3C\uC800");
        return hasPf && (hasOutlier || hasMeterScope) && !hasGuidanceIntent;
    }

    public static boolean wantsVoltageAverageSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasVoltage = m.contains("\uC804\uC555") || m.contains("voltage");
        boolean hasAvg = m.contains("\uD3C9\uADE0") || m.contains("avg") || m.contains("mean");
        boolean hasDate = m.matches(".*[0-9]{4}[-./][0-9]{1,2}[-./][0-9]{1,2}.*");
        boolean hasPeriod = m.contains("\uC624\uB298") || m.contains("\uC5B4\uC81C") || m.contains("\uC774\uBC88\uC8FC") || m.contains("\uAE08\uC8FC")
            || m.contains("\uC774\uBC88\uB2EC") || m.contains("\uAE08\uC6D4") || m.contains("\uC62C\uD574") || m.contains("\uAE08\uB144")
            || m.contains("\uC77C\uC8FC\uC77C") || m.contains("1\uC8FC") || m.contains("\uCD5C\uADFC7\uC77C")
            || m.contains("\uC6D4") || m.contains("year") || m.contains("week") || m.contains("month")
            || m.matches(".*[0-9]+\uC77C.*") || hasDate;
        return hasVoltage && hasAvg && hasPeriod;
    }

    public static boolean wantsMonthlyPeakPower(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPeak = m.contains("\uD53C\uD06C") || m.contains("peak") || m.contains("\uCD5C\uB300\uD53C\uD06C");
        boolean hasPower = m.contains("\uC804\uB825") || m.contains("power") || m.contains("kw");
        boolean hasPeriod = m.contains("\uC6D4") || m.contains("\uB2EC") || m.contains("month") || m.contains("\uC774\uBC88\uB2EC") || m.contains("\uAE08\uC6D4");
        return hasPeak && (hasPower || !m.contains("\uC804\uC555")) && hasPeriod;
    }

    public static boolean wantsVoltagePhaseAngle(String userMessage) {
        String m = normalize(userMessage);
        boolean hasVoltage = m.contains("\uC804\uC555") || m.contains("voltage");
        boolean hasPhase = m.contains("\uC704\uC0C1\uAC01") || m.contains("phaseangle") || m.contains("phase");
        return hasVoltage && hasPhase;
    }

    public static boolean wantsCurrentPhaseAngle(String userMessage) {
        String m = normalize(userMessage);
        boolean hasCurrent = m.contains("\uC804\uB958") || m.contains("current");
        boolean hasPhase = m.contains("\uC704\uC0C1\uAC01") || m.contains("phaseangle") || m.contains("phase");
        return hasCurrent && hasPhase;
    }

    public static boolean wantsPhaseCurrentValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasCurrent = m.contains("\uC804\uB958") || m.contains("current");
        boolean hasPhase = m.contains("a\uC0C1") || m.contains("b\uC0C1") || m.contains("c\uC0C1")
            || m.contains("r\uC0C1") || m.contains("s\uC0C1") || m.contains("t\uC0C1");
        return hasCurrent && hasPhase;
    }

    public static boolean wantsActivePowerValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPower = m.contains("\uC720\uD6A8\uC804\uB825") || m.contains("activepower") || m.contains("active_power")
            || m.contains("kw");
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter");
        boolean isReactive = m.contains("\uBB34\uD6A8\uC804\uB825") || m.contains("reactive") || m.contains("kvar");
        boolean isEnergy = m.contains("\uC804\uB825\uB7C9") || m.contains("\uC0AC\uC6A9\uB7C9") || m.contains("\uB204\uC801") || m.contains("kwh");
        return hasPower && !isReactive && !isEnergy && (hasMeter || extractMeterId(normalizeRaw(userMessage)) != null);
    }

    public static boolean wantsReactivePowerValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPower = m.contains("\uBB34\uD6A8\uC804\uB825") || m.contains("reactivepower") || m.contains("reactive_power") || m.contains("kvar");
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter");
        boolean isEnergy = m.contains("\uBB34\uD6A8\uC804\uB825\uB7C9") || m.contains("reactiveenergy") || m.contains("reactive_energy") || m.contains("kvarh");
        return hasPower && !isEnergy && (hasMeter || extractMeterId(normalizeRaw(userMessage)) != null);
    }

    public static boolean wantsEnergyValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasEnergy = m.contains("\uC804\uB825\uB7C9") || m.contains("\uC0AC\uC6A9\uB7C9") || m.contains("\uB204\uC801") || m.contains("kwh")
            || m.contains("energy");
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter");
        boolean isReactive = m.contains("\uBB34\uD6A8\uC804\uB825\uB7C9") || m.contains("reactiveenergy") || m.contains("reactive_energy") || m.contains("kvarh");
        return hasEnergy && !isReactive && (hasMeter || extractMeterId(normalizeRaw(userMessage)) != null);
    }

    public static boolean wantsReactiveEnergyValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasEnergy = m.contains("\uBB34\uD6A8\uC804\uB825\uB7C9") || m.contains("reactiveenergy") || m.contains("reactive_energy") || m.contains("kvarh");
        boolean hasMeter = m.contains("\uACC4\uCE21\uAE30") || m.contains("\uBBF8\uD130") || m.contains("meter");
        return hasEnergy && (hasMeter || extractMeterId(normalizeRaw(userMessage)) != null);
    }

    public static boolean wantsPhaseVoltageValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasVoltage = m.contains("\uC804\uC555") || m.contains("voltage");
        boolean hasPhase = m.contains("a\uC0C1") || m.contains("b\uC0C1") || m.contains("c\uC0C1")
            || m.contains("r\uC0C1") || m.contains("s\uC0C1") || m.contains("t\uC0C1");
        return hasVoltage && hasPhase;
    }

    public static boolean wantsLineVoltageValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasVoltage = m.contains("\uC804\uC555") || m.contains("voltage");
        boolean hasLine = m.contains("\uC120\uAC04") || m.contains("linevoltage")
            || m.contains("vab") || m.contains("vbc") || m.contains("vca")
            || m.contains("ab\uC0C1") || m.contains("bc\uC0C1") || m.contains("ca\uC0C1");
        return hasVoltage && hasLine;
    }

    public static boolean wantsMonthlyPowerStats(String userMessage) {
        String m = normalize(userMessage);
        boolean hasMonth = m.contains("\uC6D4") || m.contains("\uB2EC") || m.contains("month") || m.contains("thismonth");
        boolean hasPower = m.contains("\uC804\uB825") || m.contains("kw") || m.contains("power");
        boolean hasStat = m.contains("\uD3C9\uADE0") || m.contains("\uCD5C\uB300") || m.contains("max") || m.contains("avg");
        return hasMonth && hasPower && hasStat;
    }

    public static boolean wantsTripAlarmOnly(String userMessage) {
        String m = normalize(userMessage);
        return m.contains("\uD2B8\uB9BD") || m.contains("trip") || m.contains("\uD2B8\uB9BC");
    }

    public static boolean wantsPowerFactorStandard(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPf = m.contains("\uC5ED\uB960") || m.contains("powerfactor") || m.contains("pf");
        boolean hasStandard = m.contains("\uAE30\uC900") || m.contains("\uAE30\uC900\uCE58") || m.contains("\uD45C\uC900") || m.contains("standard");
        boolean hasIeee = m.contains("ieee");
        return hasPf && hasStandard && hasIeee;
    }

    private static String normalize(String s) {
        if (s == null) {
            return "";
        }
        return s.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }

    private static String normalizeRaw(String s) {
        return s == null ? "" : s;
    }

    private static Integer extractMeterId(String userMessage) {
        if (userMessage == null) return null;
        java.util.regex.Matcher m1 = java.util.regex.Pattern.compile("\\b([0-9]{1,6})\\s*(?:번)?\\s*(?:계측기|미터|meter)\\b", java.util.regex.Pattern.CASE_INSENSITIVE).matcher(userMessage);
        if (m1.find()) {
            try { return Integer.valueOf(Integer.parseInt(m1.group(1))); } catch (Exception ignore) {}
        }
        java.util.regex.Matcher m2 = java.util.regex.Pattern.compile("\\b(?:meter|미터|계측기)\\s*#?\\s*([0-9]{1,6})\\b", java.util.regex.Pattern.CASE_INSENSITIVE).matcher(userMessage);
        if (m2.find()) {
            try { return Integer.valueOf(Integer.parseInt(m2.group(1))); } catch (Exception ignore) {}
        }
        return null;
    }
}
