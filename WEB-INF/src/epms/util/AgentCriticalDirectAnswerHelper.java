package epms.util;

import java.time.LocalDate;
import java.util.Locale;

public final class AgentCriticalDirectAnswerHelper {
    private AgentCriticalDirectAnswerHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult tryBuildStaticCriticalAnswer(
        String userMessage,
        Integer month,
        boolean wantsHarmonicExceedStandard,
        boolean wantsFrequencyOpsGuide,
        boolean wantsHarmonicOpsGuide,
        boolean wantsUnbalanceOpsGuide,
        boolean wantsVoltageOpsGuide,
        boolean wantsCurrentOpsGuide,
        boolean wantsCommunicationOpsGuide,
        boolean wantsAlarmTrendGuide,
        boolean wantsPeakCauseGuide,
        boolean wantsPowerFactorOpsGuide,
        boolean wantsPowerFactorThreshold,
        boolean wantsEpmsKnowledge,
        boolean wantsFrequencyOutlierStandard,
        boolean wantsMonthlyEnergyUsagePrompt,
        boolean wantsDisplayedVoltageMeaning,
        boolean wantsDisplayedMetricMeaning,
        boolean wantsPowerFactorStandard
    ) {
        if (wantsHarmonicExceedStandard) {
            return result("[Harmonic exceed standard] thdV>3.0, thdI>20.0", buildHarmonicExceedStandardDirectAnswer());
        }
        if (wantsFrequencyOpsGuide) {
            return result("[Frequency ops guide]", buildFrequencyOpsGuideDirectAnswer());
        }
        if (wantsHarmonicOpsGuide) {
            return result("[Harmonic ops guide]", buildHarmonicOpsGuideDirectAnswer());
        }
        if (wantsUnbalanceOpsGuide) {
            return result("[Unbalance ops guide]", buildUnbalanceOpsGuideDirectAnswer());
        }
        if (wantsVoltageOpsGuide) {
            return result("[Voltage ops guide]", buildVoltageOpsGuideDirectAnswer());
        }
        if (wantsCurrentOpsGuide) {
            return result("[Current ops guide]", buildCurrentOpsGuideDirectAnswer());
        }
        if (wantsCommunicationOpsGuide) {
            return result("[Communication ops guide]", buildCommunicationOpsGuideDirectAnswer());
        }
        if (wantsAlarmTrendGuide) {
            return result("[Alarm trend guide]", buildAlarmTrendGuideDirectAnswer(month));
        }
        if (wantsPeakCauseGuide) {
            return result("[Peak cause guide]", buildPeakCauseGuideDirectAnswer(month));
        }
        if (wantsPowerFactorOpsGuide) {
            return result("[PF ops guide]", buildPowerFactorOpsGuideDirectAnswer());
        }
        if (wantsPowerFactorThreshold) {
            return result("[PF threshold] 0.9/0.95", buildPowerFactorThresholdDirectAnswer());
        }
        if (wantsEpmsKnowledge) {
            return result("[EPMS knowledge]", buildEpmsKnowledgeDirectAnswer());
        }
        if (wantsFrequencyOutlierStandard) {
            return result("[Frequency outlier standard] threshold<59.5 or >60.5", buildFrequencyOutlierStandardDirectAnswer());
        }
        if (wantsMonthlyEnergyUsagePrompt) {
            return result("", "이번 달 전력 사용량은 계측기를 지정해야 조회할 수 있습니다. 예: 77번 계측기 이번 달 전력 사용량은?");
        }
        if (wantsDisplayedVoltageMeaning) {
            return result("[Displayed voltage meaning] source=average_voltage>line_voltage_avg>phase_voltage_avg>voltage_ab", buildDisplayedVoltageMeaningAnswer());
        }
        if (wantsDisplayedMetricMeaning) {
            String answer = buildDisplayedMetricMeaningAnswer(userMessage);
            if (answer != null) {
                return result("[Displayed metric meaning]", answer);
            }
        }
        if (wantsPowerFactorStandard) {
            return result("[PF standard] IEEE", buildPowerFactorStandardDirectAnswer(userMessage));
        }
        return null;
    }

    public static String buildDisplayedVoltageMeaningAnswer() {
        return "현재 상태 카드의 전압(V)은 보통 average_voltage(평균전압)입니다. 다만 average_voltage가 없거나 0이면 line_voltage_avg, phase_voltage_avg, 마지막으로 voltage_ab 순서로 대체해서 보여줍니다.";
    }

    public static String buildDisplayedMetricMeaningAnswer(String userMessage) {
        String m = normalizeForIntent(userMessage);
        if (m.contains("전류") || m.contains("current")) {
            return "현재 상태 카드의 전류(I)는 average_current 값입니다.";
        }
        if (m.contains("역률") || m.contains("powerfactor") || m.contains("pf")) {
            return "현재 상태 카드의 역률(PF)은 COALESCE(power_factor, power_factor_avg, (power_factor_a + power_factor_b + power_factor_c) / 3.0) 기준입니다.";
        }
        if (m.contains("유효전력") || m.contains("activepower")) {
            return "현재 상태 카드의 유효전력(kW)은 active_power_total 값입니다.";
        }
        if (m.contains("무효전력") || m.contains("reactivepower")) {
            return "현재 상태 카드의 무효전력(kVAr)은 reactive_power_total 값입니다.";
        }
        if (m.contains("주파수") || m.contains("frequency")) {
            return "현재 상태 카드의 주파수(Hz)는 frequency 값입니다.";
        }
        return null;
    }

    public static String buildPowerFactorStandardDirectAnswer(String userMessage) {
        String m = normalizeForIntent(userMessage);
        if (m.contains("ieee")) {
            return "IEEE에는 모든 설비에 공통으로 적용되는 단일 역률 최소 기준치가 명시돼 있다고 보기 어렵습니다. 실무에서는 보통 0.9 이상을 최소 관리 기준으로 보고, 운영 목표는 0.95 이상으로 두는 경우가 많습니다.";
        }
        return "역률 기준은 적용 규정과 계약 조건에 따라 달라질 수 있지만, 실무에서는 보통 0.9 이상을 최소 관리 기준으로 보고 0.95 이상을 목표로 관리하는 경우가 많습니다.";
    }

    public static String buildPowerFactorOpsGuideDirectAnswer() {
        return "역률이 낮을 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 콘덴서 뱅크와 역률보상반 투입 상태 확인\n"
            + "2. 무효전력(kVAr) 급증 여부와 시간대별 편차 확인\n"
            + "3. 대형 유도성 부하(모터, 펌프, 팬, 냉동기) 운전 상태 확인\n"
            + "4. 고조파 과다로 보상 설비가 정상 동작하지 않는지 점검\n"
            + "5. 계측기 무신호 또는 데이터 이상 여부 확인\n\n"
            + "점검 순서:\n"
            + "- 보상설비 투입/차단 상태\n"
            + "- 최근 kW, kVAr, PF 추이\n"
            + "- 저역률 발생 시간대와 운전 설비 매칭\n"
            + "- 고조파/알람 동시 발생 여부\n"
            + "- 계측기 통신 상태";
    }

    public static String buildPeakCauseGuideDirectAnswer(Integer month) {
        String periodLabel = month == null ? "최대 피크" : (LocalDate.now().getYear() + "-" + String.format(Locale.US, "%02d", month.intValue()) + " 최대 피크");
        return periodLabel + "가 높게 나온 가능한 원인입니다.\n\n"
            + "1. 대형 부하 동시 투입\n"
            + "2. 모터, 펌프, 냉동기 등의 기동전류/돌입전류 영향\n"
            + "3. 특정 패널 또는 계측기에 부하가 집중된 경우\n"
            + "4. 냉난방, 압축기, 생산설비 등 시간대성 고부하 운전\n"
            + "5. 역률 저하나 무효전력 증가로 설비 부담이 커진 경우\n"
            + "6. 고조파, 불평형, 계측 이상치 등 전력품질 문제\n\n"
            + "확인 순서:\n"
            + "- 피크 발생 시각의 운전 설비 목록 확인\n"
            + "- 같은 시각의 kW, kVAr, PF, 알람 이력 확인\n"
            + "- 상위 부하 패널/계측기 집중 여부 확인\n"
            + "- 반복 피크인지 일시적 이벤트인지 구분\n"
            + "- 계측값 이상치나 초기 적재값 여부 점검";
    }

    public static String buildAlarmTrendGuideDirectAnswer(Integer month) {
        String periodLabel = month == null ? "최근 알람 추이" : (LocalDate.now().getYear() + "-" + String.format(Locale.US, "%02d", month.intValue()) + " 알람 추이");
        return periodLabel + "를 원인과 점검 순서 기준으로 정리하면 다음과 같습니다.\n\n"
            + "1. 추이 확인\n"
            + "- 알람 건수가 특정 날짜나 시간대에 집중되는지 확인\n"
            + "- 반복 발생 유형(TRIP, 통신이상, 과전류, 고조파 등) 구분\n\n"
            + "2. 가능한 원인\n"
            + "- 특정 설비의 반복 기동 또는 정지\n"
            + "- 전력품질 문제(역률, 고조파, 불평형, 주파수 이상)\n"
            + "- 통신 불안정이나 계측기 무신호\n"
            + "- 특정 패널/구간 부하 집중 또는 보호장치 민감도 문제\n\n"
            + "3. 점검 순서\n"
            + "- 알람 상위 유형과 건수 확인\n"
            + "- 반복 발생 계측기와 패널 확인\n"
            + "- 발생 시각과 설비 운전 이력 비교\n"
            + "- 미해결 알람 여부 확인\n"
            + "- 통신 상태와 계측기 전원/신호 상태 점검";
    }

    public static String buildFrequencyOpsGuideDirectAnswer() {
        return "주파수가 흔들릴 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 계통 이상 또는 상위 전원 변동 여부 확인\n"
            + "2. 발전기, UPS, 인버터, 대형 회전기 운전 상태 확인\n"
            + "3. 같은 시각의 알람과 전압 변동 동시 발생 여부 확인\n"
            + "4. 특정 계측기만 흔들리는지 전체 계통인지 구분\n"
            + "5. 계측기 통신 지연이나 측정 이상 여부 점검\n\n"
            + "점검 순서:\n"
            + "- 주파수 이상 발생 시각 확인\n"
            + "- 전원계통, 발전기, UPS 이벤트 확인\n"
            + "- 같은 시각 전압, 전류, 알람 비교\n"
            + "- 단일 계측기 문제인지 전체 계통 문제인지 구분\n"
            + "- 통신 상태와 계측값 이상 여부 점검";
    }

    public static String buildHarmonicOpsGuideDirectAnswer() {
        return "고조파가 높을 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 인버터, UPS, 정류기, VFD 같은 비선형 부하 운전 상태 확인\n"
            + "2. 특정 시간대나 특정 패널에 집중되는지 확인\n"
            + "3. 필터나 리액터 설치와 동작 상태 확인\n"
            + "4. 콘덴서 뱅크와 함께 문제 발생 여부 확인\n"
            + "5. 계측기 이상치인지 실제 전력품질 문제인지 구분\n\n"
            + "점검 순서:\n"
            + "- THD 전압/전류 증가 시각 확인\n"
            + "- 비선형 부하 운전 이력 확인\n"
            + "- 관련 패널, 계측기, 상별 편차 확인\n"
            + "- 역률보상설비와 필터 동작 여부 점검\n"
            + "- 반복 패턴인지 일시적 이벤트인지 구분";
    }

    public static String buildUnbalanceOpsGuideDirectAnswer() {
        return "불평형이 심할 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 상별 전류와 전압 편차 확인\n"
            + "2. 단상 부하 편중 여부 확인\n"
            + "3. 특정 패널 또는 분기 회로에 부하가 몰렸는지 점검\n"
            + "4. 결선 이상, 접촉 불량, 상 손실 가능성 확인\n"
            + "5. 반복 발생 시간대와 설비 운전 조건 확인\n\n"
            + "점검 순서:\n"
            + "- 상별 값(A/B/C 또는 R/S/T) 비교\n"
            + "- 단상 부하 분산 상태 확인\n"
            + "- 패널, 분기 회로 집중 여부 점검\n"
            + "- 보호장치, 단자, 결선 상태 확인\n"
            + "- 전압 불평형과 전류 불평형 동시 여부 확인";
    }

    public static String buildVoltageOpsGuideDirectAnswer() {
        return "전압이 떨어질 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 특정 계측기만 문제인지 전체 계통 문제인지 구분\n"
            + "2. 같은 시각의 전류 증가, 피크 상승, 알람 발생 여부 확인\n"
            + "3. 변압기, 차단기, 접속부, 케이블 과부하 가능성 점검\n"
            + "4. 대형 부하 기동 시점과 전압 강하 연관성 확인\n"
            + "5. 계측기 설정 오류나 측정 이상 여부 확인\n\n"
            + "점검 순서:\n"
            + "- 전압 저하 시각과 지속 시간 확인\n"
            + "- 상별 전압 편차 확인\n"
            + "- 같은 시각 전류, kW, 알람 비교\n"
            + "- 상위 전원과 하위 패널 구간별로 원인 범위 축소\n"
            + "- 결선, 접속 상태, 계측 이상 여부 점검";
    }

    public static String buildCurrentOpsGuideDirectAnswer() {
        return "전류가 튈 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 특정 설비 기동이나 부하 급변 여부 확인\n"
            + "2. 상별 전류 편차와 반복 패턴 확인\n"
            + "3. 같은 시각 전압 강하, 알람, 피크 상승 여부 확인\n"
            + "4. CT 설정, 결선, 계측 이상 가능성 점검\n"
            + "5. 과전류 보호장치 민감도와 차단 이력 확인\n\n"
            + "점검 순서:\n"
            + "- 전류 급변 발생 시각 확인\n"
            + "- 설비 운전 이력과 매칭\n"
            + "- 상별 전류와 전압 동시 확인\n"
            + "- 과전류 알람 또는 트립 이력 비교\n"
            + "- 계측기와 CT 결선 상태 점검";
    }

    public static String buildCommunicationOpsGuideDirectAnswer() {
        return "통신이 끊길 때 운영자가 먼저 볼 항목입니다.\n\n"
            + "1. 특정 계측기만 문제인지 구간 전체 문제인지 구분\n"
            + "2. 전원 상태와 네트워크 링크 상태 확인\n"
            + "3. RS-485, 게이트웨이, 스위치, PLC 중 어느 구간에서 끊기는지 점검\n"
            + "4. 같은 시각 무신호 알람이나 데이터 공백 발생 여부 확인\n"
            + "5. 주소 충돌, 포트 설정, polling 지연 여부 확인\n\n"
            + "점검 순서:\n"
            + "- 무신호 발생 계측기 범위 확인\n"
            + "- 전원과 통신선 상태 확인\n"
            + "- 게이트웨이, 스위치, PLC 로그 확인\n"
            + "- 최근 설정 변경 여부 확인\n"
            + "- polling 주기, 주소, 포트 설정 점검";
    }

    public static String buildHarmonicExceedStandardDirectAnswer() {
        return "현재 고조파 이상 기준은 THD_V 3.0% 초과 또는 THD_I 20.0% 초과입니다.";
    }

    public static String buildPowerFactorThresholdDirectAnswer() {
        return "운영 기준으로는 보통 역률 0.90 미만을 이상으로 보고, 관리 목표는 0.95 이상으로 둡니다.";
    }

    public static String buildEpmsKnowledgeDirectAnswer() {
        return "네. 이 EPMS에서는 계측기 상태(전압/전루/역률/주파수), 알람, 전력량, 주파수, 역률, 고조파, 불평형 같은 전력 품질 정보를 조회하고 요약해서 답하도록 구성돼 있습니다.";
    }

    public static String buildFrequencyOutlierStandardDirectAnswer() {
        return "현재 주파수 이상치는 59.5Hz 미만이거나 60.5Hz 초과인 경우로 판단합니다.";
    }

    private static AgentRuntimeModels.DirectAnswerResult result(String dbContext, String answer) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = answer;
        return result;
    }

    private static String normalizeForIntent(String text) {
        if (text == null) {
            return "";
        }
        return text.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
    }
}
