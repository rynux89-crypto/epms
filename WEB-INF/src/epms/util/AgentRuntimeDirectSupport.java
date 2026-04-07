package epms.util;

import java.util.List;
import java.util.Locale;

import epms.util.AgentRuntimeModels.CriticalDirectAnswerRequest;
import epms.util.AgentRuntimeModels.DirectAnswerRequest;
import epms.util.AgentRuntimeModels.DirectAnswerResult;

public final class AgentRuntimeDirectSupport {
    private AgentRuntimeDirectSupport() {
    }

    public static boolean isBareEnergyValueQuestion(String userMessage) {
        if (userMessage == null) return false;
        String normalized = userMessage.toLowerCase(Locale.ROOT).replaceAll("\\s+", "");
        boolean asksEnergy =
            normalized.contains("전력량") || normalized.contains("사용량") || normalized.contains("energy") || normalized.contains("kwh");
        boolean asksCurrent =
            normalized.contains("현재") || normalized.contains("지금") || normalized.contains("latest") || normalized.contains("now");
        boolean hasTarget =
            AgentQueryExtractSupport.extractMeterId(userMessage) != null
            || AgentSupport.trimToNull(AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null
            || (AgentQueryExtractSupport.extractPanelTokens(userMessage) != null && !AgentQueryExtractSupport.extractPanelTokens(userMessage).isEmpty())
            || normalized.contains("계측기")
            || normalized.contains("미터")
            || normalized.contains("meter")
            || normalized.contains("패널")
            || normalized.contains("panel")
            || normalized.contains("구역")
            || normalized.contains("동")
            || normalized.contains("라인")
            || normalized.contains("vcb")
            || normalized.contains("acb")
            || normalized.contains("mdb");
        boolean hasPeriod =
            AgentQueryExtractSupport.extractTimeWindow(userMessage) != null
            || AgentQueryExtractSupport.extractMonth(userMessage) != null;
        return asksEnergy && asksCurrent && !hasTarget && !hasPeriod;
    }

    public static DirectAnswerResult tryBuildDirectAnswer(String userMessage, boolean forceLlmOnly) throws Exception {
        if (forceLlmOnly) return null;
        String rawLower = userMessage == null ? "" : userMessage.toLowerCase(Locale.ROOT);

        String directIntentText = AgentTextUtil.normalizeForIntent(userMessage);
        Integer directMeterId = AgentQueryExtractSupport.extractMeterId(userMessage);
        if (directMeterId == null) {
            directMeterId = AgentDbTools.resolveMeterIdByName(AgentQueryExtractSupport.extractMeterNameToken(userMessage));
        }
        AgentQueryExtractSupport.TimeWindow directWindow = AgentQueryExtractSupport.extractTimeWindow(userMessage);
        List<String> scopeHints = AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4);
        List<String> directPanelTokens = AgentQueryExtractSupport.extractPanelTokens(userMessage);
        if (AgentQueryRouterCompat.wantsPanelLatestStatus(userMessage) && (directPanelTokens == null || directPanelTokens.isEmpty())) {
            directPanelTokens = AgentQueryExtractSupport.extractPanelTokensLoose(userMessage);
        }
        DirectAnswerRequest directReq = AgentRequestSupport.buildDirectAnswerRequest(
            directIntentText,
            AgentQueryRouterCompat.wantsTripAlarmOnly(userMessage) || AgentLocalIntentSupport.wantsTripAlarmOnly(userMessage),
            AgentQueryIntentSupport.wantsAlarmCountSummary(userMessage),
            AgentLocalIntentSupport.wantsAlarmCountSummary(userMessage),
            AgentQueryIntentSupport.wantsOpenAlarms(userMessage),
            AgentLocalIntentSupport.wantsOpenAlarms(userMessage),
            AgentQueryIntentSupport.wantsOpenAlarmCountSummary(userMessage),
            AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage),
            AgentScopedIntentSupport.wantsScopedMonthlyEnergySummary(
                userMessage,
                AgentQueryExtractSupport.extractMeterId(userMessage) != null || AgentSupport.trimToNull(AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null,
                ((AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 1) != null && !AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 1).isEmpty())
                    || AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage) != null)
            ),
            directMeterId,
            AgentQueryExtractSupport.extractMonth(userMessage),
            AgentQueryExtractSupport.extractTopN(userMessage, 10, 50),
            AgentQueryExtractSupport.extractDays(userMessage, 7, 90),
            AgentQueryExtractSupport.extractExplicitDays(userMessage, 90),
            directWindow != null ? directWindow.fromTs : null,
            directWindow != null ? directWindow.toTs : null,
            directWindow != null ? directWindow.label : null,
            AgentQueryExtractSupport.extractHzThreshold(userMessage),
            AgentQueryExtractSupport.extractPfThreshold(userMessage),
            AgentQueryExtractSupport.extractAlarmTypeToken(userMessage),
            AgentQueryExtractSupport.extractAlarmAreaToken(userMessage),
            AgentQueryExtractSupport.extractMeterScopeToken(userMessage),
            AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage),
            scopeHints,
            directPanelTokens,
            AgentQueryExtractSupport.extractPhaseLabel(userMessage),
            AgentQueryExtractSupport.extractLinePairLabel(userMessage),
            AgentQueryRouterCompat.wantsPanelLatestStatus(userMessage)
        );
        boolean rawEnergyNow = (rawLower.contains("현재") || rawLower.contains("지금") || rawLower.contains("latest") || rawLower.contains("now"))
            && (rawLower.contains("전력량") || rawLower.contains("사용량") || rawLower.contains("energy") || rawLower.contains("kwh"));
        if (rawEnergyNow && (directReq.directMeterId != null || (directReq.directPanelTokens != null && !directReq.directPanelTokens.isEmpty()))) {
            return AgentDirectPowerHelper.energyValue(
                AgentDbTools.getLatestEnergyContext(directReq.directMeterId, joinCsv(directReq.directPanelTokens)),
                false
            );
        }
        if ((rawLower.contains("역률") || rawLower.contains("power factor") || rawLower.contains("pf"))
            && (rawLower.contains("기준") || rawLower.contains("표준") || rawLower.contains("standard"))) {
            DirectAnswerResult result = new DirectAnswerResult();
            result.dbContext = "[PF standard] IEEE";
            String delegated = AgentAnswerFormatter.buildPowerFactorStandardDirectAnswer(userMessage);
            result.answer = delegated != null ? delegated : AgentCriticalDirectAnswerHelper.buildPowerFactorStandardDirectAnswer(userMessage);
            return result;
        }
        boolean wantsReactiveEnergyValue = AgentQueryRouterCompat.wantsReactiveEnergyValue(userMessage);
        boolean wantsEnergyValue = AgentQueryRouterCompat.wantsEnergyValue(userMessage);
        boolean wantsActivePowerValue = AgentQueryRouterCompat.wantsActivePowerValue(userMessage);
        boolean wantsReactivePowerValue = AgentQueryRouterCompat.wantsReactivePowerValue(userMessage);
        boolean wantsVoltagePhaseAngle = AgentQueryRouterCompat.wantsVoltagePhaseAngle(userMessage);
        boolean wantsCurrentPhaseAngle = AgentQueryRouterCompat.wantsCurrentPhaseAngle(userMessage);
        boolean wantsPhaseCurrentValue = AgentQueryRouterCompat.wantsPhaseCurrentValue(userMessage);
        boolean wantsPhaseVoltageValue = AgentQueryRouterCompat.wantsPhaseVoltageValue(userMessage);
        boolean wantsLineVoltageValue = AgentQueryRouterCompat.wantsLineVoltageValue(userMessage);
        boolean wantsVoltageAverage = AgentQueryRouterCompat.wantsVoltageAverageSummary(userMessage);
        boolean wantsMonthlyFrequency = AgentQueryRouterCompat.wantsMonthlyFrequencySummary(userMessage);
        boolean wantsMonthlyPeakPower = AgentQueryIntentSupport.wantsMonthlyPeakPower(userMessage);
        boolean wantsMonthlyPowerStats = AgentQueryIntentSupport.wantsMonthlyPowerStats(userMessage);
        boolean wantsBuildingPowerTop = AgentQueryRouterCompat.wantsBuildingPowerTopN(userMessage);
        String usageCountToken = AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage);
        boolean wantsUsageMeterCount = AgentScopedIntentSupport.wantsUsageMeterCountSummary(userMessage, usageCountToken);
        if (wantsUsageMeterCount && usageCountToken == null && AgentTextUtil.normalizeForIntent(userMessage).contains("비상")) {
            usageCountToken = "비상";
        }
        boolean wantsMeterCount = AgentQueryIntentSupport.wantsMeterCountSummary(userMessage);
        String meterCountIntent = AgentTextUtil.normalizeForIntent(userMessage);
        String meterCountScopeToken = AgentScopeFallbackSupport.shouldTreatAsGlobalMeterCount(userMessage, directReq.directMeterScopeToken) ? null : directReq.directMeterScopeToken;
        if (wantsMeterCount && (meterCountIntent.contains("시스템의계측기수") || meterCountIntent.contains("이시스템의계측기수"))) {
            meterCountScopeToken = null;
        }
        boolean wantsUsageMeterTop = AgentLocalIntentSupport.wantsUsageMeterTopSummary(userMessage);
        boolean wantsUsageTypeList = AgentQueryIntentSupport.wantsUsageTypeListSummary(userMessage) || AgentLocalIntentSupport.wantsUsageTypeListSummary(userMessage);
        boolean wantsMeterList = AgentQueryIntentSupport.wantsMeterListSummary(userMessage);
        boolean wantsBuildingCount = AgentQueryRouterCompat.wantsBuildingCountSummary(userMessage);
        boolean wantsUsageTypeCount = AgentQueryIntentSupport.wantsUsageTypeCountSummary(userMessage);
        boolean wantsPanelCount = AgentQueryRouterCompat.wantsPanelCountSummary(userMessage);
        String panelCountScopeToken = AgentScopeFallbackSupport.shouldTreatAsGlobalPanelCount(userMessage, directReq.directMeterScopeToken) ? null : directReq.directMeterScopeToken;
        boolean wantsPanelLatestStatus = AgentQueryRouterCompat.wantsPanelLatestStatus(userMessage);
        boolean wantsAlarmMeterTop = AgentQueryIntentSupport.wantsAlarmMeterTopN(userMessage);
        boolean wantsUsageAlarmTop = AgentLocalIntentSupport.wantsUsageAlarmTopSummary(userMessage);
        boolean wantsAlarmType = AgentQueryRouterCompat.wantsAlarmTypeSummary(userMessage);
        boolean wantsOpenAlarmCount = directReq.directOpenAlarmCountIntent;
        boolean wantsAlarmSeverity = AgentQueryRouterCompat.wantsAlarmSeveritySummary(userMessage);
        String usageAlarmToken = directReq.directAlarmCountIntent ? AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage) : null;
        boolean wantsAlarmCount = directReq.directAlarmCountIntent;
        boolean wantsOpenAlarms = directReq.directOpenAlarmsIntent;
        boolean wantsHarmonicExceed = AgentQueryIntentSupport.wantsHarmonicExceed(userMessage);
        boolean wantsFrequencyOutlier = AgentQueryIntentSupport.wantsFrequencyOutlier(userMessage);
        boolean wantsVoltageUnbalanceTop = AgentQueryIntentSupport.wantsVoltageUnbalanceTopN(userMessage);
        boolean wantsPowerFactorOutlier = AgentQueryIntentSupport.wantsPowerFactorOutlier(userMessage);
        boolean wantsHarmonicSummary = AgentQueryRouterCompat.wantsHarmonicSummary(userMessage) && !wantsHarmonicExceed;
        boolean wantsMeterSummary = AgentQueryRouterCompat.wantsMeterSummary(userMessage);
        boolean wantsAlarmSummary = AgentQueryIntentSupport.wantsAlarmSummary(userMessage);

        DirectAnswerResult result = new DirectAnswerResult();
        if (directReq.directPfStandard) {
            result.dbContext = "[PF standard] IEEE";
            String delegated = AgentAnswerFormatter.buildPowerFactorStandardDirectAnswer(userMessage);
            result.answer = delegated != null
                ? delegated
                : AgentCriticalDirectAnswerHelper.buildPowerFactorStandardDirectAnswer(userMessage);
        } else if (isBareEnergyValueQuestion(userMessage)) {
            result.dbContext = "[Energy value] target required";
            result.answer = "전력량을 조회할 대상이 필요합니다. 예: 1번 계측기의 현재 전력량은?, EAST_VCB_MAIN의 현재 전력량은?";
        } else if (directReq.directScopedMonthlyEnergyIntent) {
            return AgentCriticalResultHelper.scopedMonthlyEnergy(
                AgentDbTools.getScopedMonthlyEnergyContext(directReq.directMeterScopeToken, directReq.directMonth)
            );
        } else {
            DirectAnswerResult powerDelegated = AgentDirectFlowHelper.tryBuildPowerPhaseAnswer(
                directReq,
                wantsVoltageAverage,
                wantsMonthlyFrequency,
                wantsMonthlyPeakPower,
                wantsMonthlyPowerStats,
                wantsBuildingPowerTop,
                wantsReactiveEnergyValue,
                wantsEnergyValue,
                wantsActivePowerValue,
                wantsReactivePowerValue,
                wantsVoltagePhaseAngle,
                wantsCurrentPhaseAngle,
                wantsPhaseCurrentValue,
                wantsPhaseVoltageValue,
                wantsLineVoltageValue
            );
            if (powerDelegated != null) {
                return powerDelegated;
            }
            DirectAnswerResult delegated = AgentDirectFlowHelper.tryBuildCatalogAlarmOutlierAnswer(
                directReq,
                wantsUsageMeterCount,
                usageCountToken,
                wantsMeterCount,
                meterCountScopeToken,
                wantsUsageMeterTop,
                wantsUsageTypeList,
                wantsMeterList,
                wantsBuildingCount,
                wantsUsageTypeCount,
                wantsPanelCount,
                panelCountScopeToken,
                wantsPanelLatestStatus,
                wantsAlarmMeterTop,
                wantsUsageAlarmTop,
                wantsAlarmType,
                wantsOpenAlarmCount,
                wantsAlarmSeverity,
                wantsAlarmCount && usageAlarmToken != null,
                usageAlarmToken,
                wantsAlarmCount,
                wantsOpenAlarms,
                wantsHarmonicExceed,
                wantsFrequencyOutlier,
                wantsVoltageUnbalanceTop,
                wantsPowerFactorOutlier,
                wantsHarmonicSummary,
                wantsMeterSummary,
                wantsAlarmSummary
            );
            if (delegated != null) {
                return delegated;
            }
        }

        if (result.answer == null || result.dbContext == null) {
            return null;
        }
        return result;
    }

    public static DirectAnswerResult tryBuildCriticalDirectAnswer(String userMessage, boolean forceLlmOnly) throws Exception {
        if (forceLlmOnly) return null;
        String rawLower = userMessage == null ? "" : userMessage.toLowerCase(Locale.ROOT);

        boolean criticalHasMeterHint =
            AgentQueryExtractSupport.extractMeterId(userMessage) != null
            || AgentSupport.trimToNull(AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null;
        AgentQueryExtractSupport.TimeWindow criticalWindow = AgentQueryExtractSupport.extractTimeWindow(userMessage);
        List<String> criticalPanelTokens = AgentQueryExtractSupport.extractPanelTokens(userMessage);
        if (criticalPanelTokens == null || criticalPanelTokens.isEmpty()) {
            criticalPanelTokens = AgentQueryExtractSupport.extractPanelTokensLoose(userMessage);
        }
        Integer criticalMeterId = AgentQueryExtractSupport.extractMeterId(userMessage);
        if (criticalMeterId == null) {
            criticalMeterId = AgentDbTools.resolveMeterIdByName(AgentQueryExtractSupport.extractMeterNameToken(userMessage));
        }
        DirectAnswerRequest criticalAlarmSeed = AgentRequestSupport.buildDirectAnswerRequest(
            AgentTextUtil.normalizeForIntent(userMessage),
            AgentLocalIntentSupport.wantsTripAlarmOnly(userMessage),
            false,
            false,
            false,
            false,
            false,
            AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage),
            false,
            criticalMeterId,
            AgentQueryExtractSupport.extractMonth(userMessage),
            AgentQueryExtractSupport.extractTopN(userMessage, 5, 20),
            AgentQueryExtractSupport.extractDays(userMessage, 7, 90),
            AgentQueryExtractSupport.extractExplicitDays(userMessage, 90),
            criticalWindow != null ? criticalWindow.fromTs : null,
            criticalWindow != null ? criticalWindow.toTs : null,
            criticalWindow != null ? criticalWindow.label : null,
            null,
            null,
            AgentQueryExtractSupport.extractAlarmTypeToken(userMessage),
            AgentQueryExtractSupport.extractAlarmAreaToken(userMessage),
            null,
            AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage),
            AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 4),
            criticalPanelTokens,
            null,
            null,
            false
        );
        CriticalDirectAnswerRequest criticalReq = AgentRequestSupport.buildCriticalDirectAnswerRequest(
            criticalAlarmSeed.directIntentText,
            criticalHasMeterHint,
            criticalAlarmSeed.directMonth,
            criticalAlarmSeed.directMeterId,
            criticalAlarmSeed.directTopN,
            criticalAlarmSeed.directMeterScopeToken,
            AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage),
            criticalAlarmSeed.directAlarmTypeToken,
            criticalAlarmSeed.directAlarmAreaToken,
            criticalAlarmSeed.directFromTs,
            criticalAlarmSeed.directToTs,
            criticalAlarmSeed.directPeriodLabel,
            criticalPanelTokens
        );
        boolean rawPanelMonthly = criticalPanelTokens != null && !criticalPanelTokens.isEmpty()
            && (rawLower.contains("패널") || rawLower.contains("panel"))
            && (rawLower.contains("전체") || rawLower.contains("총") || rawLower.contains("합계"))
            && (rawLower.contains("전력량") || rawLower.contains("사용량") || rawLower.contains("energy") || rawLower.contains("kwh"));
        if (rawPanelMonthly) {
            return AgentCriticalResultHelper.panelMonthlyEnergy(
                AgentDbTools.getPanelMonthlyEnergyContext(joinCsv(criticalPanelTokens), criticalReq.criticalMonth)
            );
        }
        boolean rawCurrentUnbalanceCount = (rawLower.contains("전류") || rawLower.contains("current"))
            && (rawLower.contains("불평형") || rawLower.contains("불균형") || rawLower.contains("unbalance") || rawLower.contains("imbalance"))
            && (rawLower.contains("수는") || rawLower.contains("개수") || rawLower.contains("갯수")
                || rawLower.contains("건수") || rawLower.contains("몇개") || rawLower.contains("몇 개")
                || rawLower.contains("count") || rawLower.contains("총 "));
        if (rawCurrentUnbalanceCount) {
            String countCtx = criticalReq.criticalFromTs != null
                ? AgentDbTools.getCurrentUnbalanceCountContext(10.0d, criticalReq.criticalFromTs, criticalReq.criticalToTs, criticalReq.criticalPeriodLabel)
                : AgentDbTools.getCurrentUnbalanceCountContext(10.0d, null, null, null);
            return AgentDirectOutlierHelper.currentUnbalanceCount(countCtx);
        }
        Integer harmonicCountTopN = AgentQueryExtractSupport.extractTopN(userMessage, 200, 500);
        return AgentCriticalFlowHelper.tryBuildCriticalAnswer(
            userMessage,
            criticalReq,
            harmonicCountTopN,
            AgentScopedIntentSupport.wantsPanelMonthlyEnergySummary(
                userMessage,
                ((AgentQueryExtractSupport.extractPanelTokens(userMessage) != null && !AgentQueryExtractSupport.extractPanelTokens(userMessage).isEmpty())
                    || (AgentQueryExtractSupport.extractPanelTokensLoose(userMessage) != null && !AgentQueryExtractSupport.extractPanelTokensLoose(userMessage).isEmpty()))
            ),
            AgentScopedIntentSupport.wantsUsageMonthlyEnergySummary(
                userMessage,
                AgentScopeFallbackSupport.extractUsageTokenFallback(userMessage) != null
            ),
            AgentLocalIntentSupport.wantsUsagePowerTopSummary(userMessage),
            AgentLocalIntentSupport.wantsHarmonicExceedStandard(userMessage),
            AgentLocalIntentSupport.wantsFrequencyOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsHarmonicOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsUnbalanceOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsVoltageOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsCurrentOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsCommunicationOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsAlarmTrendGuide(userMessage),
            AgentLocalIntentSupport.wantsPeakCauseGuide(userMessage),
            AgentLocalIntentSupport.wantsPowerFactorOpsGuide(userMessage),
            AgentLocalIntentSupport.wantsPowerFactorThreshold(userMessage),
            AgentLocalIntentSupport.wantsEpmsKnowledge(userMessage),
            AgentLocalIntentSupport.wantsFrequencyOutlierStandard(userMessage),
            AgentScopedIntentSupport.wantsMonthlyEnergyUsagePrompt(
                userMessage,
                AgentQueryExtractSupport.extractMeterId(userMessage) != null
                    || AgentSupport.trimToNull(AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null
                    || !AgentQueryExtractSupport.extractPanelTokens(userMessage).isEmpty()
                    || !AgentQueryExtractSupport.extractPanelTokensLoose(userMessage).isEmpty()
            ),
            AgentLocalIntentSupport.wantsDisplayedVoltageMeaning(userMessage),
            AgentLocalIntentSupport.wantsDisplayedMetricMeaning(userMessage),
            AgentLocalIntentSupport.wantsPowerFactorStandard(userMessage),
            AgentLocalIntentSupport.wantsCurrentUnbalanceCount(userMessage),
            AgentLocalIntentSupport.wantsHarmonicExceedCount(userMessage),
            AgentScopedIntentSupport.wantsScopedMonthlyEnergySummary(
                userMessage,
                AgentQueryExtractSupport.extractMeterId(userMessage) != null || AgentSupport.trimToNull(AgentQueryExtractSupport.extractMeterNameToken(userMessage)) != null,
                ((AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 1) != null && !AgentMetadataLookupSupport.findScopeTokensFromMeterMaster(userMessage, 1).isEmpty())
                    || AgentScopeFallbackSupport.extractScopedAreaTokenFallback(userMessage) != null)
            ),
            AgentLocalIntentSupport.wantsOpenAlarmCountSummary(userMessage)
        );
    }

    private static String joinCsv(java.util.List<String> items) {
        if (items == null || items.isEmpty()) {
            return null;
        }
        return String.join(",", items);
    }
}
