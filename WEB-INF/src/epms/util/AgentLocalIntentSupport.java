package epms.util;

public final class AgentLocalIntentSupport {
    private AgentLocalIntentSupport() {
    }

    public static boolean wantsAlarmCountSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
        boolean hasCount = m.contains("건수") || m.contains("개수") || m.contains("갯수")
            || m.contains("count") || m.contains("몇건") || m.contains("몇개")
            || m.contains("수를알려") || m.contains("수를보여");
        boolean hasOccurred = m.contains("발생");
        return hasAlarm && (hasCount || hasOccurred || m.endsWith("알람은?") || m.endsWith("알람?"));
    }

    public static boolean wantsAlarmTrendGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
        boolean hasTrend = m.contains("추세") || m.contains("트렌드") || m.contains("trend");
        boolean hasGuide = m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("분석");
        return hasAlarm && hasTrend && hasGuide;
    }

    public static boolean wantsFrequencyOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
        boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("threshold");
        return hasFrequency && hasGuideIntent && !asksThreshold;
    }

    public static boolean wantsHarmonicOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
        boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("threshold");
        return hasHarmonic && hasGuideIntent && !asksThreshold;
    }

    public static boolean wantsUnbalanceOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUnbalance = m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
        return hasUnbalance && hasGuideIntent;
    }

    public static boolean wantsVoltageOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasVoltage = m.contains("전압") || m.contains("voltage");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저")
            || m.contains("떨어") || m.contains("낮");
        boolean hasSimpleValueIntent = m.contains("값") || m.contains("조회") || m.contains("평균");
        return hasVoltage && hasGuideIntent && !hasSimpleValueIntent;
    }

    public static boolean wantsCurrentOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasCurrent = m.contains("전류") || m.contains("current");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저")
            || m.contains("튀") || m.contains("급변");
        boolean hasSimpleValueIntent = m.contains("값") || m.contains("조회") || m.contains("상전류");
        return hasCurrent && hasGuideIntent && !hasSimpleValueIntent;
    }

    public static boolean wantsCommunicationOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasComm = m.contains("통신") || m.contains("communication") || m.contains("comm")
            || m.contains("무신호") || m.contains("신호없음") || m.contains("데이터안들어옴");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저")
            || m.contains("끊") || m.contains("안됨");
        return hasComm && hasGuideIntent;
    }

    public static boolean wantsOpenAlarms(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasOpen = m.contains("미해결") || m.contains("열린") || m.contains("open");
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
        return hasOpen && hasAlarm;
    }

    public static boolean wantsOpenAlarmCountSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasOpen = m.contains("미해결") || m.contains("열린") || m.contains("open");
        return hasOpen && wantsAlarmCountSummary(userMessage);
    }

    public static boolean wantsAlarmMeterTopN(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
        boolean hasRanking = m.contains("top") || m.contains("상위") || m.contains("많은") || m.contains("가장많은")
            || m.contains("많이발생") || m.contains("자주") || m.contains("목록") || m.contains("보여") || m.contains("알려");
        boolean hasCountHint = m.contains("건수") || m.contains("개수") || m.contains("수") || m.contains("발생")
            || m.contains("있는계측기") || m.contains("계측기는") || m.endsWith("계측기") || m.endsWith("계측기는");
        return hasAlarm && hasMeter && hasRanking && hasCountHint;
    }

    public static boolean wantsMonthlyPeakPower(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasPeak = m.contains("피크") || m.contains("peak") || m.contains("최대피크");
        boolean hasPower = m.contains("전력") || m.contains("power") || m.contains("kw");
        boolean hasPeriod = m.contains("월") || m.contains("달") || m.contains("month") || m.contains("이번달") || m.contains("금월");
        return hasPeak && (hasPower || !m.contains("전압")) && hasPeriod;
    }

    public static boolean wantsMonthlyPowerStats(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasPeriod = m.contains("월") || m.contains("달") || m.contains("month") || m.contains("이번달") || m.contains("금월");
        boolean hasPower = m.contains("전력") || m.contains("power") || m.contains("kw");
        boolean hasStats = m.contains("통계") || m.contains("요약") || m.contains("평균") || m.contains("최대전력") || m.contains("avg") || m.contains("max");
        boolean excludes = m.contains("피크") || m.contains("peak") || m.contains("전압") || m.contains("주파수");
        return hasPeriod && hasPower && hasStats && !excludes;
    }

    public static boolean wantsPeakCauseGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasPeak = m.contains("피크") || m.contains("peak") || m.contains("최대피크");
        boolean hasCauseIntent = m.contains("이유") || m.contains("원인") || m.contains("정리") || m.contains("설명") || m.contains("해석") || m.contains("분석");
        return hasPeak && hasCauseIntent;
    }

    public static boolean wantsPowerFactorStandard(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        String raw = userMessage == null ? "" : userMessage.toLowerCase(java.util.Locale.ROOT);
        boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
        boolean hasStandard = m.contains("기준") || m.contains("기준치") || m.contains("표준") || m.contains("standard");
        boolean hasIeee = m.contains("ieee");
        if (!hasPf) hasPf = raw.contains("역률") || raw.contains("power factor");
        if (!hasStandard) hasStandard = raw.contains("기준") || raw.contains("표준");
        if (!hasIeee) hasIeee = raw.contains("ieee");
        return hasPf && hasStandard && hasIeee;
    }

    public static boolean wantsPowerFactorThreshold(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
        boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("기준치") || m.contains("threshold");
        boolean hasIeee = m.contains("ieee");
        return hasPf && asksThreshold && !hasIeee;
    }

    public static boolean wantsPowerFactorOpsGuide(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasPf = m.contains("역률") || m.contains("powerfactor") || m.contains("pf");
        boolean hasGuideIntent = m.contains("운영자") || m.contains("담당자") || m.contains("알려")
            || m.contains("설명") || m.contains("원인") || m.contains("점검") || m.contains("항목")
            || m.contains("순서") || m.contains("절차") || m.contains("체크리스트") || m.contains("뭐부터") || m.contains("먼저");
        boolean asksThreshold = m.contains("임계치") || m.contains("기준") || m.contains("기준치") || m.contains("threshold");
        return hasPf && hasGuideIntent && !asksThreshold;
    }

    public static boolean wantsEpmsKnowledge(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean asksEpms = m.contains("epms") || m.contains("이에프엠에스") || m.contains("전력감시") || m.contains("에너지관리");
        boolean asksKnowledge = m.contains("잘알아") || m.contains("알아") || m.contains("무슨시스템") || m.contains("뭐하는시스템") || m.contains("설명해");
        return asksEpms && asksKnowledge;
    }

    public static boolean wantsFrequencyOutlierStandard(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
        boolean asksStandard = m.contains("기준") || m.contains("임계치") || m.contains("어떻게판단") || m.contains("판단")
            || m.contains("threshold") || m.contains("조건");
        return hasFrequency && asksStandard;
    }

    public static boolean wantsUsageTypeListSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
        boolean hasList = m.contains("리스트") || m.contains("목록") || m.contains("list")
            || m.contains("종류") || m.contains("항목") || m.contains("보여") || m.contains("알려");
        boolean hasTopIntent = m.contains("top") || m.contains("상위") || m.contains("가장많은")
            || m.contains("제일많은") || m.contains("많은");
        boolean hasCount = m.contains("몇개") || m.contains("개수") || m.contains("갯수")
            || m.contains("수는") || m.contains("총개수") || m.contains("count");
        boolean hasPowerIntent = m.contains("전력") || m.contains("전력량") || m.contains("사용량")
            || m.contains("kwh") || m.contains("kw") || m.contains("power");
        return hasUsage && hasList && !hasAlarm && !hasTopIntent && !hasCount && !hasPowerIntent;
    }

    public static boolean wantsUsagePowerTopSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUsage = m.contains("용도별") || m.contains("사용처별") || (m.contains("용도") && m.contains("별")) || m.contains("usage");
        boolean hasPower = m.contains("전력") || m.contains("전력량") || m.contains("사용량") || m.contains("kwh") || m.contains("power");
        boolean hasTop = m.contains("top") || m.contains("상위") || m.contains("비교") || m.contains("목록") || m.contains("보여");
        return hasUsage && hasPower && hasTop;
    }

    public static boolean wantsUsageMeterTopSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
        boolean hasMeter = m.contains("계측기") || m.contains("미터") || m.contains("meter");
        boolean hasTop = m.contains("가장많은") || m.contains("제일많은") || m.contains("가장많이")
            || m.contains("top") || m.contains("상위") || m.contains("많은");
        boolean hasCountIntent = m.contains("가진") || m.contains("보유") || m.contains("몇개") || m.contains("개수")
            || m.contains("갯수") || m.contains("수");
        boolean hasExcludedIntent = m.contains("전력") || m.contains("전력량") || m.contains("사용량")
            || m.contains("kwh") || m.contains("kw") || m.contains("power");
        return hasUsage && hasMeter && hasTop && hasCountIntent && !hasExcludedIntent;
    }

    public static boolean wantsUsageAlarmTopSummary(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasUsage = m.contains("용도") || m.contains("사용처") || m.contains("usage");
        boolean hasAlarm = m.contains("알람") || m.contains("경보") || m.contains("alarm");
        boolean hasTop = m.contains("가장많은") || m.contains("제일많은") || m.contains("가장많이")
            || m.contains("top") || m.contains("상위") || m.contains("많은")
            || m.contains("목록") || m.contains("보여") || m.contains("알려");
        boolean hasCountIntent = m.contains("가진") || m.contains("보유") || m.contains("건수")
            || m.contains("개수") || m.contains("갯수") || m.contains("수")
            || m.endsWith("용도는") || m.endsWith("용도는?") || m.endsWith("용도?");
        return hasUsage && hasAlarm && hasTop && (hasCountIntent || m.contains("상위") || m.contains("top"));
    }

    public static boolean wantsHarmonicExceedCount(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd")
            || m.contains("왜형률") || m.contains("허형율");
        boolean hasOutlier = m.contains("이상") || m.contains("초과") || m.contains("문제") || m.contains("비정상");
        boolean hasCount = m.contains("총몇개") || m.contains("몇개") || m.contains("몇건") || m.contains("건수")
            || m.contains("개수") || m.contains("갯수") || m.contains("count") || m.contains("총몇")
            || m.contains("수는") || m.endsWith("수") || m.endsWith("수는?") || m.endsWith("개야") || m.contains("몇대");
        return hasHarmonic && hasOutlier && hasCount;
    }

    public static boolean wantsHarmonicExceed(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd")
            || m.contains("왜형률") || m.contains("허형율");
        boolean hasOutlier = m.contains("이상") || m.contains("초과") || m.contains("문제") || m.contains("비정상");
        boolean hasListIntent = m.contains("보여") || m.contains("목록") || m.contains("리스트") || m.contains("상위") || m.contains("top") || m.contains("어디");
        return hasHarmonic && hasOutlier && hasListIntent && !wantsHarmonicExceedCount(userMessage);
    }

    public static boolean wantsHarmonicExceedStandard(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasHarmonic = m.contains("고조파") || m.contains("harmonic") || m.contains("thd")
            || m.contains("왜형률") || m.contains("허형율");
        boolean asksStandard = m.contains("기준") || m.contains("기준값") || m.contains("임계치")
            || m.contains("threshold") || m.contains("조건");
        return hasHarmonic && asksStandard;
    }

    public static boolean wantsCurrentUnbalanceCount(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        String raw = userMessage == null ? "" : userMessage.toLowerCase(java.util.Locale.ROOT);
        boolean hasCurrent = m.contains("전류") || m.contains("current");
        boolean hasUnbalance = m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance");
        boolean hasCount = m.contains("수는") || m.contains("몇개") || m.contains("몇건") || m.contains("개수")
            || m.contains("갯수") || m.contains("건수") || m.contains("count") || m.contains("총몇");
        if (!hasCurrent) hasCurrent = raw.contains("전류");
        if (!hasUnbalance) hasUnbalance = raw.contains("불평형") || raw.contains("불균형");
        if (!hasCount) hasCount = raw.contains("수는") || raw.contains("개수") || raw.contains("갯수")
            || raw.contains("건수") || raw.contains("몇 개") || raw.contains("몇개") || raw.contains("총 ");
        return hasCurrent && hasUnbalance && hasCount;
    }

    public static boolean wantsFrequencyOutlier(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasFrequency = m.contains("주파수") || m.contains("frequency") || m.contains("hz");
        boolean hasOutlier = m.contains("이상") || m.contains("이상치") || m.contains("초과") || m.contains("문제") || m.contains("비정상");
        boolean hasListIntent = m.contains("보여") || m.contains("목록") || m.contains("리스트") || m.contains("어디") || m.contains("상위");
        return hasFrequency && hasOutlier && hasListIntent;
    }

    public static boolean wantsVoltageUnbalanceTopN(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasVoltage = m.contains("전압") || m.contains("voltage");
        boolean hasUnbalance = m.contains("불평형") || m.contains("불균형") || m.contains("unbalance") || m.contains("imbalance");
        boolean hasListIntent = m.contains("보여") || m.contains("목록") || m.contains("리스트") || m.contains("상위") || m.contains("top") || m.contains("어디");
        return hasVoltage && hasUnbalance && hasListIntent;
    }

    public static boolean wantsPowerFactorOutlier(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean hasPowerFactor = m.contains("역률") || m.contains("pf") || m.contains("powerfactor");
        boolean hasOutlier = m.contains("이상") || m.contains("미만") || m.contains("낮") || m.contains("문제") || m.contains("비정상");
        boolean hasListIntent = m.contains("보여") || m.contains("목록") || m.contains("리스트") || m.contains("어디") || m.contains("상위");
        return hasPowerFactor && hasOutlier && hasListIntent;
    }

    public static boolean wantsDisplayedVoltageMeaning(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean asksVoltageMeaning = (m.contains("보여주는전압") || m.contains("보여준전압") || m.contains("전압값") || m.contains("전압은") || m.contains("전압이"))
            && (m.contains("평균") || m.contains("무슨값") || m.contains("어떤값") || m.contains("기준"));
        boolean asksDisplayedValue = (m.contains("지금") || m.contains("방금") || m.contains("니가") || m.contains("네가") || m.contains("보여준") || m.contains("보여주는"))
            && (m.contains("값") || m.contains("전압"));
        return asksVoltageMeaning || asksDisplayedValue;
    }

    public static boolean wantsDisplayedMetricMeaning(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        boolean asksContext = m.contains("지금") || m.contains("방금") || m.contains("니가") || m.contains("네가")
            || m.contains("보여준") || m.contains("보여주는");
        boolean asksMeaning = m.contains("무슨값") || m.contains("어떤값") || m.contains("기준")
            || m.contains("의미") || m.contains("평균") || m.contains("계산");
        boolean asksMetric = m.contains("전류") || m.contains("역률") || m.contains("유효전력")
            || m.contains("무효전력") || m.contains("주파수")
            || m.contains("current") || m.contains("pf") || m.contains("powerfactor")
            || m.contains("activepower") || m.contains("reactivepower") || m.contains("frequency");
        return asksMetric && (asksMeaning || asksContext);
    }

    public static boolean wantsTripAlarmOnly(String userMessage) {
        String m = AgentTextUtil.normalizeForIntent(userMessage);
        return m.contains("트립") || m.contains("trip") || m.contains("트림");
    }
}
