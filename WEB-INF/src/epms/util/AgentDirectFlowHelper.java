package epms.util;

public final class AgentDirectFlowHelper {
    private AgentDirectFlowHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult tryBuildPowerPhaseAnswer(
        AgentRuntimeModels.DirectAnswerRequest req,
        boolean wantsVoltageAverage,
        boolean wantsMonthlyFrequency,
        boolean wantsMonthlyPeakPower,
        boolean wantsMonthlyPowerStats,
        boolean wantsBuildingPowerTop,
        boolean wantsReactiveEnergyValue,
        boolean wantsEnergyValue,
        boolean wantsActivePowerValue,
        boolean wantsReactivePowerValue,
        boolean wantsVoltagePhaseAngle,
        boolean wantsCurrentPhaseAngle,
        boolean wantsPhaseCurrentValue,
        boolean wantsPhaseVoltageValue,
        boolean wantsLineVoltageValue
    ) {
        if (req == null) {
            return null;
        }

        if (wantsVoltageAverage) {
            Integer daysFallback = (req.directFromTs == null ? req.directExplicitDays : null);
            return AgentDirectPowerHelper.voltageAverage(
                AgentDbTools.getVoltageAverageContext(
                    req.directMeterId,
                    joinCsv(req.directPanelTokens),
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel,
                    daysFallback
                ),
                req.directMeterId
            );
        }

        if (wantsMonthlyFrequency) {
            return AgentDirectPowerHelper.frequency(
                AgentDbTools.getMonthlyAvgFrequencyContext(req.directMeterId, req.directMonth),
                req.directMeterId,
                req.directMonth
            );
        }

        if (wantsMonthlyPeakPower) {
            return AgentDirectPowerHelper.monthlyPeak(
                AgentDbTools.getMonthlyPeakPowerContext(req.directMeterId, req.directMonth)
            );
        }

        if (wantsMonthlyPowerStats) {
            return AgentDirectPowerHelper.monthlyPowerStats(
                AgentDbTools.getMonthlyPowerStatsContext(req.directMeterId, req.directMonth)
            );
        }

        if (wantsBuildingPowerTop) {
            return AgentDirectPowerHelper.buildingPowerTop(
                AgentDbTools.getBuildingPowerTopNContext(req.directMonth, req.directTopN)
            );
        }

        if (wantsReactiveEnergyValue || wantsEnergyValue) {
            boolean reactive = wantsReactiveEnergyValue;
            if (req.directFromTs != null) {
                return AgentDirectPowerHelper.energyDelta(
                    AgentDbTools.getEnergyDeltaContext(
                        req.directMeterId,
                        req.directFromTs,
                        req.directToTs,
                        req.directPeriodLabel,
                        reactive
                    ),
                    reactive
                );
            }
            return AgentDirectPowerHelper.energyValue(
                AgentDbTools.getLatestEnergyContext(req.directMeterId, joinCsv(req.directPanelTokens)),
                reactive
            );
        }

        if (wantsActivePowerValue || wantsReactivePowerValue) {
            return AgentDirectPowerHelper.powerValue(
                AgentDbTools.getRecentMeterContext(req.directMeterId, joinCsv(req.directPanelTokens)),
                wantsReactivePowerValue
            );
        }

        if (wantsVoltagePhaseAngle || wantsCurrentPhaseAngle || wantsPhaseCurrentValue || wantsPhaseVoltageValue || wantsLineVoltageValue) {
            String ctx;
            String message;
            if (wantsVoltagePhaseAngle) {
                ctx = AgentDbTools.getVoltagePhaseAngleContext(req.directMeterId);
                message = "전압 위상각을 조회했습니다.";
            } else if (wantsCurrentPhaseAngle) {
                ctx = AgentDbTools.getCurrentPhaseAngleContext(req.directMeterId);
                message = "전류 위상각을 조회했습니다.";
            } else if (wantsPhaseCurrentValue) {
                ctx = AgentDbTools.getPhaseCurrentContext(req.directMeterId, req.directPhaseLabel);
                message = "상전류를 조회했습니다.";
            } else if (wantsPhaseVoltageValue) {
                ctx = AgentDbTools.getPhaseVoltageContext(req.directMeterId, req.directPhaseLabel);
                message = "상전압을 조회했습니다.";
            } else {
                ctx = AgentDbTools.getLineVoltageContext(req.directMeterId, req.directLinePairLabel);
                message = "선간전압을 조회했습니다.";
            }
            return AgentDirectResultHelper.simple(ctx, buildUserDbContext(ctx), message);
        }

        return null;
    }

    public static AgentRuntimeModels.DirectAnswerResult tryBuildCatalogAlarmOutlierAnswer(
        AgentRuntimeModels.DirectAnswerRequest req,
        boolean wantsUsageMeterCount,
        String usageCountToken,
        boolean wantsMeterCount,
        String meterCountScopeToken,
        boolean wantsUsageMeterTop,
        boolean wantsUsageTypeList,
        boolean wantsMeterList,
        boolean wantsBuildingCount,
        boolean wantsUsageTypeCount,
        boolean wantsPanelCount,
        String panelCountScopeToken,
        boolean wantsPanelLatestStatus,
        boolean wantsAlarmMeterTop,
        boolean wantsUsageAlarmTop,
        boolean wantsAlarmType,
        boolean wantsOpenAlarmCount,
        boolean wantsAlarmSeverity,
        boolean wantsUsageAlarmCount,
        String usageAlarmToken,
        boolean wantsAlarmCount,
        boolean wantsOpenAlarms,
        boolean wantsHarmonicExceed,
        boolean wantsFrequencyOutlier,
        boolean wantsVoltageUnbalanceTop,
        boolean wantsPowerFactorOutlier,
        boolean wantsHarmonicSummary,
        boolean wantsMeterSummary,
        boolean wantsAlarmSummary
    ) {
        if (req == null) {
            return null;
        }

        if (wantsUsageMeterCount) {
            return AgentDirectCatalogHelper.usageMeterCount(
                AgentDbTools.getMeterCountContext(usageCountToken),
                usageCountToken
            );
        }

        if (wantsMeterCount && !req.directAlarmCountIntent && !req.directOpenAlarmCountIntent) {
            return AgentDirectCatalogHelper.meterCount(
                AgentDbTools.getMeterCountContext(meterCountScopeToken)
            );
        }

        if (wantsUsageMeterTop) {
            return AgentDirectCatalogHelper.usageMeterTop(
                AgentDbTools.getUsageMeterTopNContext(req.directTopN)
            );
        }

        if (wantsUsageTypeList) {
            return AgentDirectCatalogHelper.usageTypeList(
                AgentDbTools.getUsageTypeListContext(req.directTopN)
            );
        }

        if (wantsMeterList && !req.directAlarmCountIntent && !req.directOpenAlarmCountIntent) {
            return AgentDirectCatalogHelper.meterList(
                AgentDbTools.getMeterListContext(req.directMeterScopeToken, req.directTopN)
            );
        }

        if (wantsBuildingCount) {
            return AgentDirectCatalogHelper.buildingCount(AgentDbTools.getBuildingCountContext());
        }

        if (wantsUsageTypeCount) {
            return AgentDirectCatalogHelper.usageTypeCount(AgentDbTools.getUsageTypeCountContext());
        }

        if (wantsPanelCount) {
            return AgentDirectCatalogHelper.panelCount(
                AgentDbTools.getPanelCountContext(panelCountScopeToken)
            );
        }

        if (wantsPanelLatestStatus) {
            return AgentDirectCatalogHelper.panelLatest(
                AgentDbTools.getPanelLatestStatusContext(joinCsv(req.directPanelTokens), req.directTopN)
            );
        }

        if (wantsAlarmMeterTop) {
            return AgentDirectAlarmHelper.alarmMeterTop(
                AgentDbTools.getAlarmMeterTopNContext(
                    req.directDays,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel,
                    req.directTopN
                )
            );
        }

        if (wantsUsageAlarmTop) {
            return AgentDirectAlarmHelper.usageAlarmTop(
                AgentDbTools.getUsageAlarmTopNContext(
                    req.directDays,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel,
                    req.directTopN
                )
            );
        }

        if (wantsAlarmType) {
            return AgentDirectAlarmHelper.alarmType(
                AgentDbTools.getAlarmTypeSummaryContext(
                    req.directDays,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel,
                    req.directMeterId,
                    req.directTripOnly,
                    req.directTopN
                )
            );
        }

        if (wantsOpenAlarmCount) {
            AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
            result.dbContext = AgentDbTools.getOpenAlarmCountContext(
                req.directFromTs,
                req.directToTs,
                req.directPeriodLabel,
                req.directMeterId,
                req.directAlarmTypeToken,
                req.directAlarmAreaToken
            );
            result.answer = AgentDirectAnswerHelper.buildOpenAlarmCountAnswer(result.dbContext);
            return result;
        }

        if (wantsAlarmSeverity) {
            return AgentDirectAlarmHelper.alarmSeverity(
                AgentDbTools.getAlarmSeveritySummaryContext(
                    req.directDays,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                )
            );
        }

        if (wantsUsageAlarmCount && usageAlarmToken != null) {
            return AgentDirectAlarmHelper.usageAlarmCount(
                AgentDbTools.getUsageAlarmCountContext(
                    usageAlarmToken,
                    req.directDays,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                )
            );
        }

        if (wantsAlarmCount) {
            AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
            result.dbContext = AgentDbTools.getAlarmCountContext(
                req.directDays,
                req.directFromTs,
                req.directToTs,
                req.directPeriodLabel,
                req.directMeterId,
                req.directAlarmTypeToken,
                req.directAlarmAreaToken
            );
            String userCtx = buildUserDbContext(result.dbContext);
            result.answer = (userCtx == null || userCtx.trim().isEmpty()) ? "알람 건수를 조회했습니다." : userCtx;
            return result;
        }

        if (wantsOpenAlarms) {
            return AgentDirectAlarmHelper.openAlarms(
                AgentDbTools.getOpenAlarmsContext(
                    req.directTopN,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                )
            );
        }

        if (wantsHarmonicExceed) {
            return AgentDirectOutlierHelper.harmonicExceed(
                AgentDbTools.getHarmonicExceedListContext(
                    null,
                    null,
                    req.directTopN,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                )
            );
        }

        if (wantsFrequencyOutlier) {
            return AgentDirectOutlierHelper.frequencyOutlier(
                AgentDbTools.getFrequencyOutlierListContext(
                    req.directHz,
                    req.directTopN,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                )
            );
        }

        if (wantsVoltageUnbalanceTop) {
            return AgentDirectOutlierHelper.voltageUnbalanceTop(
                AgentDbTools.getVoltageUnbalanceTopNContext(
                    req.directTopN,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                )
            );
        }

        if (wantsPowerFactorOutlier) {
            String pfCtx = AgentDbTools.getPowerFactorOutlierListContext(
                req.directPf,
                req.directTopN,
                req.directFromTs,
                req.directToTs,
                req.directPeriodLabel
            );
            int noSignalCount = AgentDbTools.getPowerFactorNoSignalCount(req.directFromTs, req.directToTs);
            AgentRuntimeModels.DirectAnswerResult result = AgentDirectOutlierHelper.powerFactorOutlier(pfCtx, noSignalCount);
            if ((pfCtx.contains("none") || pfCtx.contains("no data")) && noSignalCount > 0) {
                int noSignalTopN = (req.directIntentText != null
                    && (req.directIntentText.contains("전체")
                        || req.directIntentText.contains("전부")
                        || req.directIntentText.contains("모두")
                        || req.directIntentText.contains("all"))) ? 50 : 10;
                String noSignalCtx = AgentDbTools.getPowerFactorNoSignalListContext(
                    noSignalTopN,
                    req.directFromTs,
                    req.directToTs,
                    req.directPeriodLabel
                );
                String snippet = AgentDirectResultHelper.buildPowerFactorNoSignalListSnippet(noSignalCtx);
                if (snippet != null && !snippet.trim().isEmpty()) {
                    result.answer = result.answer + "\n\n" + snippet.trim();
                }
            }
            return result;
        }

        if (wantsHarmonicSummary) {
            return AgentDirectPowerHelper.harmonic(
                AgentDbTools.getHarmonicContext(req.directMeterId, joinCsv(req.directPanelTokens)),
                req.directMeterId
            );
        }

        if (wantsMeterSummary || wantsAlarmSummary) {
            String meterCtx = wantsMeterSummary
                ? AgentDbTools.getRecentMeterContext(req.directMeterId, joinCsv(req.directPanelTokens))
                : "";
            String alarmCtx = wantsAlarmSummary ? AgentDbTools.getRecentAlarmContext() : "";
            StringBuilder dbSb = new StringBuilder();
            if (meterCtx != null && !meterCtx.trim().isEmpty()) dbSb.append("Meter: ").append(meterCtx);
            if (alarmCtx != null && !alarmCtx.trim().isEmpty()) {
                if (dbSb.length() > 0) dbSb.append("\n");
                dbSb.append("Alarm: ").append(alarmCtx);
            }
            AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
            result.dbContext = dbSb.toString();
            if (result.dbContext == null || result.dbContext.trim().isEmpty()) {
                result.answer = "요청한 조회 결과를 찾지 못했습니다.";
            } else if (result.dbContext.contains("unavailable")) {
                result.answer = "현재 계측/알람 조회를 수행할 수 없습니다.";
            } else if (wantsMeterSummary && !wantsAlarmSummary) {
                if (result.dbContext.contains("no data")) {
                    result.answer = "요청한 계측 데이터가 없습니다.";
                } else {
                    String userCtx = buildUserDbContext(result.dbContext);
                    result.answer = (userCtx == null || userCtx.trim().isEmpty())
                        ? "최근 계측값을 조회했습니다."
                        : userCtx;
                }
            } else if (!wantsMeterSummary && wantsAlarmSummary) {
                result.answer = AgentDirectAlarmHelper.latestAlarms(alarmCtx).answer;
            } else {
                String meterText = wantsMeterSummary ? buildUserDbContext(meterCtx) : null;
                String alarmText = wantsAlarmSummary ? AgentDirectAlarmHelper.latestAlarms(alarmCtx).answer : null;
                result.answer = AgentDirectAlarmHelper.directDbSummary(wantsMeterSummary, wantsAlarmSummary, meterText, alarmText);
                if (result.answer == null || result.answer.trim().isEmpty()) {
                    result.answer = "최근 계측값과 알람을 조회했습니다.";
                }
            }
            return result;
        }

        return null;
    }

    private static String joinCsv(java.util.List<String> items) {
        if (items == null || items.isEmpty()) {
            return null;
        }
        return String.join(",", items);
    }

    private static String buildUserDbContext(String dbContext) {
        String ctx = dbContext == null ? "" : dbContext.trim();
        if (ctx.isEmpty()) {
            return "";
        }
        String delegated = AgentAnswerFormatter.buildUserDbContext(ctx);
        int noSignalCount = ctx.contains("[Power factor outlier]") ? AgentDbTools.getPowerFactorNoSignalCount(null, null) : 0;
        String delegatedPf = null;
        String noSignalCtx = null;
        if (ctx.contains("[Power factor outlier]")) {
            delegatedPf = AgentAnswerFormatter.buildPowerFactorOutlierDirectAnswer(ctx, noSignalCount);
            if ((ctx.contains("none") || ctx.contains("no data")) && noSignalCount > 0) {
                noSignalCtx = AgentDbTools.getPowerFactorNoSignalListContext(10, null, null, null);
            }
        }
        return AgentUserContextHelper.buildUserContextWithPowerFactorHandling(
            ctx,
            delegated,
            noSignalCount,
            delegatedPf,
            noSignalCtx
        );
    }
}
