package epms.util;

import java.util.ArrayList;
import java.util.List;

public final class AgentRequestSupport {
    private AgentRequestSupport() {
    }

    public static AgentRuntimeModels.AgentRequestContext buildRequestContext(
            Integer requestedMeterId,
            String meterScopeToken,
            String alarmAreaToken,
            List<String> scopeHints,
            Integer requestedMonth,
            boolean needsPerMeterPower,
            boolean needsMeterList,
            boolean needsPhaseCurrent,
            boolean needsPhaseVoltage,
            boolean needsLineVoltage,
            boolean needsHarmonic,
            List<String> panelTokens,
            String requestedPhase,
            String requestedLinePair) {
        AgentRuntimeModels.AgentRequestContext ctx = new AgentRuntimeModels.AgentRequestContext();
        ctx.requestedMeterId = requestedMeterId;
        ctx.requestedMeterScope = resolveScopeToken(meterScopeToken, alarmAreaToken, scopeHints);
        ctx.requestedMonth = requestedMonth;
        ctx.needsPerMeterPower = needsPerMeterPower;
        ctx.needsMeterList = needsMeterList;
        ctx.needsPhaseCurrent = needsPhaseCurrent;
        ctx.needsPhaseVoltage = needsPhaseVoltage;
        ctx.needsLineVoltage = needsLineVoltage;
        ctx.needsHarmonic = needsHarmonic;
        ctx.panelTokens = needsPerMeterPower ? new ArrayList<String>() : copyList(panelTokens);
        ctx.requestedPhase = requestedPhase;
        ctx.requestedLinePair = requestedLinePair;
        return ctx;
    }

    public static AgentRuntimeModels.DirectAnswerRequest buildDirectAnswerRequest(
            String directIntentText,
            boolean routedWantsTripAlarmOnly,
            boolean routedWantsAlarmCountSummary,
            boolean localWantsAlarmCountSummary,
            boolean routedWantsOpenAlarms,
            boolean localWantsOpenAlarms,
            boolean routedWantsOpenAlarmCountSummary,
            boolean localWantsOpenAlarmCountSummary,
            boolean localWantsScopedMonthlyEnergySummary,
            Integer directMeterId,
            Integer directMonth,
            Integer directTopN,
            Integer directDays,
            Integer directExplicitDays,
            java.sql.Timestamp directFromTs,
            java.sql.Timestamp directToTs,
            String directPeriodLabel,
            Double directHz,
            Double directPf,
            String directAlarmTypeToken,
            String directAlarmAreaToken,
            String directMeterScopeToken,
            String scopedAreaFallbackToken,
            List<String> scopeHints,
            List<String> directPanelTokens,
            String directPhaseLabel,
            String directLinePairLabel,
            boolean routedWantsPanelLatestStatus) {
        AgentRuntimeModels.DirectAnswerRequest req = new AgentRuntimeModels.DirectAnswerRequest();
        req.directIntentText = trimToNull(directIntentText);
        String intentText = req.directIntentText == null ? "" : req.directIntentText;
        req.directPfStandard =
                (intentText.contains("역률") || intentText.contains("powerfactor") || intentText.contains("pf"))
                && (intentText.contains("기준") || intentText.contains("기준치") || intentText.contains("표준") || intentText.contains("standard"))
                && intentText.contains("ieee");
        req.directTripOnly =
                routedWantsTripAlarmOnly
                || intentText.contains("트립")
                || intentText.contains("trip")
                || intentText.contains("트림");
        req.directAlarmCountIntent = routedWantsAlarmCountSummary || localWantsAlarmCountSummary;
        req.directOpenAlarmsIntent = routedWantsOpenAlarms || localWantsOpenAlarms;
        req.directOpenAlarmCountIntent =
                routedWantsOpenAlarmCountSummary
                || localWantsOpenAlarmCountSummary
                || (req.directOpenAlarmsIntent && req.directAlarmCountIntent);
        req.directScopedMonthlyEnergyIntent = localWantsScopedMonthlyEnergySummary;

        req.directMeterId = directMeterId;
        req.directMonth = directMonth;
        req.directTopN = directTopN;
        req.directDays = directDays;
        req.directExplicitDays = directExplicitDays;
        req.directFromTs = directFromTs;
        req.directToTs = directToTs;
        req.directPeriodLabel = trimToNull(directPeriodLabel);
        req.directHz = directHz;
        req.directPf = directPf;
        req.directAlarmTypeToken = trimToNull(directAlarmTypeToken);
        if (req.directTripOnly && req.directAlarmTypeToken == null) {
            req.directAlarmTypeToken = "TRIP";
        }

        req.directAlarmAreaToken = trimToNull(directAlarmAreaToken);
        if (req.directAlarmAreaToken == null && scopeHints != null && !scopeHints.isEmpty()) {
            req.directAlarmAreaToken = String.join(",", scopeHints);
        }

        req.directMeterScopeToken = trimToNull(directMeterScopeToken);
        if (req.directMeterScopeToken == null && req.directAlarmAreaToken != null) {
            req.directMeterScopeToken = req.directAlarmAreaToken;
        }
        if (req.directMeterScopeToken == null && req.directScopedMonthlyEnergyIntent) {
            if (scopeHints != null && !scopeHints.isEmpty()) {
                req.directMeterScopeToken = String.join(",", scopeHints);
            } else {
                req.directMeterScopeToken = trimToNull(scopedAreaFallbackToken);
            }
        }

        req.directPanelTokens = copyList(directPanelTokens);
        if (intentText.contains("전체") || intentText.contains("전부") || intentText.contains("모두") || intentText.contains("all")) {
            req.directTopN = Integer.valueOf(50);
        }
        if (routedWantsPanelLatestStatus && req.directPanelTokens.isEmpty()) {
            req.directPanelTokens = new ArrayList<String>();
        }

        req.directPhaseLabel = trimToNull(directPhaseLabel);
        req.directLinePairLabel = trimToNull(directLinePairLabel);
        return req;
    }

    public static AgentRuntimeModels.CriticalDirectAnswerRequest buildCriticalDirectAnswerRequest(
            String criticalIntentText,
            boolean criticalHasMeterHint,
            Integer criticalMonth,
            Integer criticalMeterId,
            Integer criticalTopN,
            String criticalScopedAreaToken,
            String criticalUsageToken,
            String criticalAlarmTypeToken,
            String criticalAlarmAreaToken,
            java.sql.Timestamp criticalFromTs,
            java.sql.Timestamp criticalToTs,
            String criticalPeriodLabel,
            List<String> criticalPanelTokens) {
        AgentRuntimeModels.CriticalDirectAnswerRequest req = new AgentRuntimeModels.CriticalDirectAnswerRequest();
        req.criticalIntentText = trimToNull(criticalIntentText);
        req.criticalHasMeterHint = criticalHasMeterHint;
        req.criticalMonth = criticalMonth;
        req.criticalMeterId = criticalMeterId;
        req.criticalTopN = criticalTopN;
        req.criticalScopedAreaToken = trimToNull(criticalScopedAreaToken);
        req.criticalUsageToken = trimToNull(criticalUsageToken);
        req.criticalAlarmTypeToken = trimToNull(criticalAlarmTypeToken);
        req.criticalAlarmAreaToken = trimToNull(criticalAlarmAreaToken);
        req.criticalFromTs = criticalFromTs;
        req.criticalToTs = criticalToTs;
        req.criticalPeriodLabel = trimToNull(criticalPeriodLabel);
        req.criticalPanelTokens = copyList(criticalPanelTokens);
        return req;
    }

    private static String resolveScopeToken(String meterScopeToken, String alarmAreaToken, List<String> scopeHints) {
        String resolved = trimToNull(meterScopeToken);
        if (resolved == null) resolved = trimToNull(alarmAreaToken);
        if (resolved == null && scopeHints != null && !scopeHints.isEmpty()) resolved = String.join(",", scopeHints);
        return resolved;
    }

    private static List<String> copyList(List<String> src) {
        if (src == null || src.isEmpty()) return new ArrayList<String>();
        return new ArrayList<String>(src);
    }

    private static String trimToNull(String s) {
        if (s == null) return null;
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }
}
