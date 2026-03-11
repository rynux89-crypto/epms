package epms.util;

import java.util.Locale;

public final class AgentQueryRouterCompat {
    private AgentQueryRouterCompat() {
    }

    public static boolean wantsMeterSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean meterWord = m.contains("meter") || m.contains("미터") || m.contains("계측기");
        boolean meterIntentWord =
            m.contains("최근계측") || m.contains("최신계측")
            || m.contains("최근측정") || m.contains("최신측정")
            || m.contains("계측값") || m.contains("measurement") || m.contains("실시간상태")
            || m.contains("현재상태")
            || m.contains("전압값") || m.contains("전류값")
            || m.contains("역률") || m.contains("전력값") || m.contains("kw");
        boolean electricalWord =
            m.contains("전압") || m.contains("voltage")
            || m.contains("전류") || m.contains("current")
            || m.contains("전력") || m.contains("power")
            || m.contains("역률") || m.contains("pf");
        boolean recentWord =
            m.contains("최근") || m.contains("최신") || m.contains("실시간")
            || m.contains("current") || m.contains("latest");
        boolean statusWord = m.contains("상태") || m.contains("status");
        boolean hasMeterCode = m.matches(".*[a-z]{2,}_[a-z0-9_\\-]{2,}.*");
        boolean askForm = m.endsWith("?") || m.endsWith("는?") || m.endsWith("은?");
        boolean sqlLike = m.contains("select") || m.contains("where") || m.contains("join")
            || m.contains("query") || m.contains("sql") || m.contains("테이블") || m.contains("컬럼");
        if (sqlLike) return false;
        if (hasMeterCode && (statusWord || askForm)) return true;
        if (meterWord && statusWord) return true;
        if (meterWord && electricalWord) return true;
        if (electricalWord && recentWord && (m.contains("계측기") || meterWord)) return true;
        return meterIntentWord || (meterWord && (m.contains("값") || m.contains("value") || m.contains("status") || m.contains("상태")));
    }

    public static boolean wantsAlarmSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarmWord = m.contains("알람") || m.contains("경보") || m.contains("alarm") || m.contains("alert");
        boolean hasSummaryIntent = m.contains("최근") || m.contains("최신") || m.contains("요약")
            || m.contains("보여") || m.contains("알려") || m.contains("목록") || m.contains("같이");
        return m.contains("최근알람") || m.contains("최신알람")
            || m.contains("알람요약") || m.contains("경보요약")
            || m.contains("alarm") || m.contains("alert")
            || m.contains("이상내역")
            || (hasAlarmWord && hasSummaryIntent);
    }

    public static boolean wantsMonthlyFrequencySummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
        boolean hasAverage = m.contains("평균") || m.contains("avg") || m.contains("mean");
        boolean hasPeriod = m.contains("월") || m.contains("month");
        return hasFrequency && (hasAverage || hasPeriod);
    }

    public static boolean wantsPerMeterPowerSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean meterScope = m.contains("각계측기") || m.contains("모든계측기") || m.contains("계측기별")
            || (m.contains("각") && m.contains("계측기")) || (m.contains("all") && m.contains("meter"));
        boolean powerWord = m.contains("전력량") || m.contains("전력") || m.contains("사용전력")
            || m.contains("kw") || m.contains("kwh") || m.contains("power");
        return meterScope && powerWord;
    }

    public static boolean wantsHarmonicSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
        boolean hasSummaryIntent =
            m.contains("상태") || m.contains("요약") || m.contains("현재")
            || m.contains("최신") || m.contains("값") || m.contains("보여")
            || m.contains("알려") || m.contains("status") || m.contains("summary")
            || m.contains("current") || m.contains("latest");
        boolean hasOutlierIntent =
            m.contains("초과") || m.contains("기준") || m.contains("threshold")
            || m.contains("over") || m.contains("이상") || m.contains("비정상")
            || m.contains("문제");
        return hasHarmonic && (hasSummaryIntent || !hasOutlierIntent);
    }

    public static boolean wantsMeterListSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasList = m.contains("리스트") || m.contains("목록") || m.contains("list");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter") || m.contains("게츠기");
        boolean hasScoped = m.contains("관련된") || m.contains("의");
        boolean hasStatusIntent =
            m.contains("상태") || m.contains("현재상태") || m.contains("실시간상태")
            || m.contains("계측값") || m.contains("전압") || m.contains("전류")
            || m.contains("역률") || m.contains("전력") || m.contains("주파수")
            || m.contains("값") || m.contains("status") || m.contains("current")
            || m.contains("latest") || m.contains("measurement");
        boolean askMeter =
            (hasMeter && (m.endsWith("는?") || m.endsWith("은?") || m.endsWith("?")))
            || m.contains("계측기는") || m.contains("계측기?")
            || m.contains("미터는") || m.contains("meter?");
        if (hasStatusIntent) return false;
        return (hasList && (hasMeter || hasScoped)) || (hasMeter && hasScoped && askMeter);
    }

    public static boolean wantsMeterCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter") || m.contains("게츠기");
        boolean hasCount =
            m.contains("몇개") || m.contains("몇개야") || m.contains("개수")
            || m.contains("갯수") || m.contains("수는") || m.contains("수알려")
            || m.contains("수를알려") || m.contains("수를보여") || m.contains("총개수")
            || m.contains("count") || m.contains("몇대") || m.contains("총몇")
            || m.matches(".*계측기.*수.*알려.*") || m.matches(".*meter.*count.*");
        boolean hasList = m.contains("리스트") || m.contains("목록") || m.contains("list");
        return hasMeter && hasCount && !hasList;
    }

    public static boolean wantsPanelCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPanel = m.contains("패널") || m.contains("판넬") || m.contains("panel");
        boolean hasCount =
            m.contains("몇개") || m.contains("몇개야") || m.contains("개수")
            || m.contains("갯수") || m.contains("수는") || m.contains("수알려")
            || m.contains("수를알려") || m.contains("수를보여") || m.contains("총개수")
            || m.contains("count") || m.contains("몇개패널") || m.matches(".*패널.*수.*알려.*");
        boolean hasStatus = m.contains("상태") || m.contains("status");
        return hasPanel && hasCount && !hasStatus;
    }

    public static boolean wantsBuildingCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasBuilding = m.contains("건물") || m.contains("building");
        boolean hasCount =
            m.contains("몇개") || m.contains("몇개야") || m.contains("개수")
            || m.contains("갯수") || m.contains("수는") || m.contains("수알려")
            || m.contains("수를알려") || m.contains("수를보여") || m.contains("총개수")
            || m.contains("count") || m.matches(".*건물.*수.*알려.*");
        return hasBuilding && hasCount;
    }

    public static boolean wantsUsageTypeCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
        boolean hasCount =
            m.contains("몇개") || m.contains("몇개야") || m.contains("개수")
            || m.contains("갯수") || m.contains("수는") || m.contains("수알려")
            || m.contains("수를알려") || m.contains("수를보여") || m.contains("총개수")
            || m.contains("count") || m.matches(".*용도.*수.*알려.*") || m.matches(".*사용처.*수.*알려.*");
        return hasUsage && hasCount;
    }

    public static boolean wantsAlarmSeveritySummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("alarm") || m.contains("경보");
        boolean hasSeverity = m.contains("심각도") || m.contains("severity");
        return hasAlarm && hasSeverity;
    }

    public static boolean wantsAlarmTypeSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("alarm") || m.contains("경보");
        boolean hasType = m.contains("종류") || m.contains("유형") || m.contains("타입")
            || m.contains("type") || m.contains("무슨알람") || m.contains("어떤알람");
        boolean hasSeverity = m.contains("심각도") || m.contains("severity");
        return hasAlarm && hasType && !hasSeverity;
    }

    public static boolean wantsAlarmCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("alarm") || m.contains("경보");
        boolean hasCount = m.contains("건수") || m.contains("개수") || m.contains("갯수") || m.contains("count")
            || m.contains("몇건") || m.contains("몇개")
            || m.contains("알람의수") || m.contains("수는") || m.contains("수알려")
            || m.contains("수를알려") || m.contains("수를보여")
            || m.matches(".*알람.*수.*알려.*") || m.endsWith("수");
        boolean hasOccurred = m.contains("발생") || m.contains("trigger");
        return hasAlarm && (hasCount || hasOccurred || m.endsWith("수는?") || m.endsWith("수?"));
    }

    public static boolean wantsOpenAlarms(String userMessage) {
        String m = normalize(userMessage);
        return (m.contains("미해결") || m.contains("열린") || m.contains("open"))
            && (m.contains("알람") || m.contains("alarm"));
    }

    public static boolean wantsOpenAlarmCountSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasOpen = m.contains("미해결") || m.contains("열린") || m.contains("open");
        boolean hasAlarm = m.contains("알람") || m.contains("alarm") || m.contains("경보");
        boolean hasCount = m.contains("건수") || m.contains("개수") || m.contains("갯수") || m.contains("count")
            || m.contains("몇건") || m.contains("몇개")
            || m.contains("수는") || m.contains("수알려") || m.contains("수를알려") || m.contains("수를보여");
        return hasOpen && hasAlarm && hasCount;
    }

    public static boolean wantsBuildingPowerTopN(String userMessage) {
        String m = normalize(userMessage);
        boolean hasBuilding = m.contains("건물") || m.contains("building");
        boolean hasPower = m.contains("전력") || m.contains("전력량") || m.contains("사용전력")
            || m.contains("kw") || m.contains("kwh") || m.contains("power");
        boolean hasTop = m.contains("top") || m.contains("상위") || m.matches(".*[0-9]+개.*");
        boolean hasListIntent = m.contains("별") || m.contains("비교") || m.contains("목록") || m.contains("보여");
        return hasBuilding && hasPower && (hasTop || hasListIntent || m.endsWith("은?") || m.endsWith("?"));
    }

    public static boolean wantsPanelLatestStatus(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPanel = m.contains("패널") || m.contains("panel") || m.contains("판넬") || m.contains("계열");
        boolean hasStatus = m.contains("상태") || m.contains("status");
        boolean hasPanelCode = m.matches(".*(mdb|vcb|acb)[a-z0-9_\\-]*.*");
        boolean hasMeterScope = m.contains("계측기") || m.contains("meter");
        if (hasMeterScope && !hasPanel) return false;
        return (hasPanel || hasPanelCode) && hasStatus;
    }

    public static boolean wantsHarmonicExceed(String userMessage) {
        String m = normalize(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
        boolean hasOutlier = m.contains("초과") || m.contains("기준") || m.contains("threshold") || m.contains("over")
            || m.contains("이상") || m.contains("비정상") || m.contains("문제");
        return hasHarmonic && hasOutlier;
    }

    public static boolean wantsFrequencyOutlier(String userMessage) {
        String m = normalize(userMessage);
        return (m.contains("주파수") || m.contains("frequency") || m.contains("hz"))
            && (m.contains("이상") || m.contains("미만") || m.contains("초과") || m.contains("outlier"));
    }

    public static boolean wantsVoltageUnbalanceTopN(String userMessage) {
        String m = normalize(userMessage);
        boolean hasUnbalance =
            m.contains("불평형") || m.contains("불균형")
            || m.contains("전압불평형") || m.contains("전압불균형")
            || m.contains("unbalance");
        boolean hasListIntent =
            m.contains("top") || m.contains("상위")
            || m.contains("보여줘") || m.contains("목록") || m.contains("리스트")
            || m.matches(".*[0-9]+개.*");
        return hasUnbalance && (hasListIntent || m.contains("계측기"));
    }

    public static boolean wantsPowerFactorOutlier(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
        boolean hasOutlier = m.contains("이상") || m.contains("비정상") || m.contains("문제")
            || m.contains("낮") || m.contains("high") || m.contains("low");
        boolean hasMeterScope = m.contains("계측기") || m.contains("meter") || m.contains("목록") || m.contains("보여");
        return hasPf && (hasOutlier || hasMeterScope);
    }

    public static boolean wantsVoltageAverageSummary(String userMessage) {
        String m = normalize(userMessage);
        boolean hasVoltage = m.contains("전압") || m.contains("voltage");
        boolean hasAvg = m.contains("평균") || m.contains("avg") || m.contains("mean");
        boolean hasDate = m.matches(".*[0-9]{4}[-./][0-9]{1,2}[-./][0-9]{1,2}.*");
        boolean hasPeriod = m.contains("오늘") || m.contains("어제") || m.contains("이번주") || m.contains("금주")
            || m.contains("이번달") || m.contains("금월") || m.contains("올해") || m.contains("금년")
            || m.contains("일주일") || m.contains("1주") || m.contains("최근7일")
            || m.contains("월") || m.contains("year") || m.contains("week") || m.contains("month")
            || m.matches(".*[0-9]+일.*") || hasDate;
        return hasVoltage && hasAvg && hasPeriod;
    }

    public static boolean wantsVoltagePhaseAngle(String userMessage) {
        String m = normalize(userMessage);
        return (m.contains("전압") || m.contains("voltage"))
            && (m.contains("위상각") || m.contains("phaseangle") || m.contains("phase"));
    }

    public static boolean wantsCurrentPhaseAngle(String userMessage) {
        String m = normalize(userMessage);
        return (m.contains("전류") || m.contains("current"))
            && (m.contains("위상각") || m.contains("phaseangle") || m.contains("phase"));
    }

    public static boolean wantsPhaseCurrentValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPhase = m.contains("a상") || m.contains("b상") || m.contains("c상")
            || m.contains("r상") || m.contains("s상") || m.contains("t상");
        return (m.contains("전류") || m.contains("current")) && hasPhase;
    }

    public static boolean wantsActivePowerValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPower = m.contains("유효전력") || m.contains("activepower") || m.contains("active_power") || m.contains("kw");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
        boolean isReactive = m.contains("무효전력") || m.contains("reactive") || m.contains("kvar");
        boolean isEnergy = m.contains("전력량") || m.contains("사용량") || m.contains("누적") || m.contains("kwh");
        return hasPower && !isReactive && !isEnergy && (hasMeter || extractMeterId(userMessage) != null);
    }

    public static boolean wantsReactivePowerValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPower = m.contains("무효전력") || m.contains("reactivepower") || m.contains("reactive_power") || m.contains("kvar");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
        boolean isEnergy = m.contains("무효전력량") || m.contains("reactiveenergy") || m.contains("reactive_energy") || m.contains("kvarh");
        return hasPower && !isEnergy && (hasMeter || extractMeterId(userMessage) != null);
    }

    public static boolean wantsEnergyValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasEnergy = m.contains("전력량") || m.contains("사용량") || m.contains("누적") || m.contains("kwh") || m.contains("energy");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
        boolean isReactive = m.contains("무효전력량") || m.contains("reactiveenergy") || m.contains("reactive_energy") || m.contains("kvarh");
        return hasEnergy && !isReactive && (hasMeter || extractMeterId(userMessage) != null);
    }

    public static boolean wantsReactiveEnergyValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasEnergy = m.contains("무효전력량") || m.contains("reactiveenergy") || m.contains("reactive_energy") || m.contains("kvarh");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
        return hasEnergy && (hasMeter || extractMeterId(userMessage) != null);
    }

    public static boolean wantsPhaseVoltageValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPhase = m.contains("a상") || m.contains("b상") || m.contains("c상")
            || m.contains("r상") || m.contains("s상") || m.contains("t상");
        return (m.contains("전압") || m.contains("voltage")) && hasPhase;
    }

    public static boolean wantsLineVoltageValue(String userMessage) {
        String m = normalize(userMessage);
        boolean hasLine = m.contains("선간") || m.contains("linevoltage")
            || m.contains("vab") || m.contains("vbc") || m.contains("vca")
            || m.contains("ab상") || m.contains("bc상") || m.contains("ca상");
        return (m.contains("전압") || m.contains("voltage")) && hasLine;
    }

    public static boolean wantsMonthlyPowerStats(String userMessage) {
        String m = normalize(userMessage);
        boolean hasMonth = m.contains("월") || m.contains("달") || m.contains("month") || m.contains("thismonth");
        boolean hasPower = m.contains("전력") || m.contains("kw") || m.contains("power");
        boolean hasStat = m.contains("평균") || m.contains("최대") || m.contains("max") || m.contains("avg");
        return hasMonth && hasPower && hasStat;
    }

    public static boolean wantsTripAlarmOnly(String userMessage) {
        String m = normalize(userMessage);
        return m.contains("트립") || m.contains("trip") || m.contains("트림");
    }

    public static boolean wantsPowerFactorStandard(String userMessage) {
        String m = normalize(userMessage);
        boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
        boolean hasStandard = m.contains("기준") || m.contains("기준치") || m.contains("표준") || m.contains("standard");
        boolean hasIeee = m.contains("ieee");
        return hasPf && hasStandard && hasIeee;
    }

    private static String normalize(String s) {
        if (s == null) return "";
        return s.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }

    private static Integer extractMeterId(String userMessage) {
        if (userMessage == null) return null;
        java.util.regex.Matcher m1 = java.util.regex.Pattern
            .compile("\\b([0-9]{1,6})\\s*(?:번)?\\s*(?:계측기|미터|meter)\\b", java.util.regex.Pattern.CASE_INSENSITIVE)
            .matcher(userMessage);
        if (m1.find()) {
            try { return Integer.valueOf(Integer.parseInt(m1.group(1))); } catch (Exception ignore) {}
        }
        java.util.regex.Matcher m2 = java.util.regex.Pattern
            .compile("\\b(?:meter|미터|계측기)\\s*#?\\s*([0-9]{1,6})\\b", java.util.regex.Pattern.CASE_INSENSITIVE)
            .matcher(userMessage);
        if (m2.find()) {
            try { return Integer.valueOf(Integer.parseInt(m2.group(1))); } catch (Exception ignore) {}
        }
        return null;
    }
}
