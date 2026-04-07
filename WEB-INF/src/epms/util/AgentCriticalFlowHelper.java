package epms.util;

public final class AgentCriticalFlowHelper {
    private AgentCriticalFlowHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult tryBuildCriticalAnswer(
        String userMessage,
        AgentRuntimeModels.CriticalDirectAnswerRequest req,
        Integer harmonicCountTopN,
        boolean wantsPanelMonthlyEnergy,
        boolean wantsUsageMonthlyEnergy,
        boolean wantsUsagePowerTop,
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
        boolean wantsPowerFactorStandard,
        boolean wantsCurrentUnbalanceCount,
        boolean wantsHarmonicExceedCount,
        boolean wantsScopedMonthlyEnergy,
        boolean wantsOpenAlarmCountSummary
    ) {
        if (req == null) {
            return null;
        }

        if (!req.criticalHasMeterHint
            && req.criticalIntentText != null
            && req.criticalIntentText.contains("전체사용량")
            && userMessage != null
            && userMessage.contains("의")) {
            return AgentCriticalResultHelper.scopedMonthlyEnergy(
                AgentDbTools.getScopedMonthlyEnergyContext(req.criticalScopedAreaToken, req.criticalMonth)
            );
        }

        if (wantsPanelMonthlyEnergy) {
            return AgentCriticalResultHelper.panelMonthlyEnergy(
                AgentDbTools.getPanelMonthlyEnergyContext(joinCsv(req.criticalPanelTokens), req.criticalMonth)
            );
        }

        if (wantsUsageMonthlyEnergy) {
            return AgentCriticalResultHelper.usageMonthlyEnergy(
                AgentDbTools.getUsageMonthlyEnergyContext(req.criticalUsageToken, req.criticalMonth)
            );
        }

        if (wantsUsagePowerTop) {
            return AgentDirectPowerHelper.usagePowerTop(
                AgentDbTools.getUsagePowerTopNContext(req.criticalMonth, req.criticalTopN)
            );
        }

        AgentRuntimeModels.DirectAnswerResult staticResult = AgentCriticalDirectAnswerHelper.tryBuildStaticCriticalAnswer(
            userMessage,
            req.criticalMonth,
            wantsHarmonicExceedStandard,
            wantsFrequencyOpsGuide,
            wantsHarmonicOpsGuide,
            wantsUnbalanceOpsGuide,
            wantsVoltageOpsGuide,
            wantsCurrentOpsGuide,
            wantsCommunicationOpsGuide,
            wantsAlarmTrendGuide,
            wantsPeakCauseGuide,
            wantsPowerFactorOpsGuide,
            wantsPowerFactorThreshold,
            wantsEpmsKnowledge,
            wantsFrequencyOutlierStandard,
            wantsMonthlyEnergyUsagePrompt,
            wantsDisplayedVoltageMeaning,
            wantsDisplayedMetricMeaning,
            wantsPowerFactorStandard
        );
        if (staticResult != null) {
            return staticResult;
        }

        if (wantsCurrentUnbalanceCount) {
            String countCtx = req.criticalFromTs != null
                ? AgentDbTools.getCurrentUnbalanceCountContext(10.0d, req.criticalFromTs, req.criticalToTs, req.criticalPeriodLabel)
                : AgentDbTools.getCurrentUnbalanceCountContext(10.0d, null, null, null);
            return AgentDirectOutlierHelper.currentUnbalanceCount(countCtx);
        }

        if (wantsHarmonicExceedCount) {
            Integer harmonicTopN = harmonicCountTopN == null ? Integer.valueOf(200) : harmonicCountTopN;
            String countCtx = req.criticalFromTs != null
                ? AgentDbTools.getHarmonicExceedListContext(null, null, harmonicTopN, req.criticalFromTs, req.criticalToTs, req.criticalPeriodLabel)
                : AgentDbTools.getHarmonicExceedListContext(null, null, harmonicTopN, null, null, null);
            return AgentDirectOutlierHelper.harmonicExceedCount(countCtx);
        }

        if (wantsScopedMonthlyEnergy) {
            return AgentCriticalResultHelper.scopedMonthlyEnergy(
                AgentDbTools.getScopedMonthlyEnergyContext(req.criticalScopedAreaToken, req.criticalMonth)
            );
        }

        if (wantsOpenAlarmCountSummary) {
            return AgentCriticalResultHelper.openAlarmCount(
                AgentDbTools.getOpenAlarmCountContext(
                    req.criticalFromTs,
                    req.criticalToTs,
                    req.criticalPeriodLabel,
                    req.criticalMeterId,
                    req.criticalAlarmTypeToken,
                    req.criticalAlarmAreaToken
                )
            );
        }

        return null;
    }

    private static String joinCsv(java.util.List<String> items) {
        if (items == null || items.isEmpty()) {
            return null;
        }
        return String.join(",", items);
    }
}
