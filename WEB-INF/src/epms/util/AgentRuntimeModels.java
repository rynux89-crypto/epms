package epms.util;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;

public final class AgentRuntimeModels {
    private AgentRuntimeModels() {
    }

    public static final class AgentRequestContext {
        public Integer requestedMeterId;
        public String requestedMeterScope;
        public Integer requestedMonth;
        public boolean needsPerMeterPower;
        public boolean needsMeterList;
        public boolean needsPhaseCurrent;
        public boolean needsPhaseVoltage;
        public boolean needsLineVoltage;
        public boolean needsHarmonic;
        public List<String> panelTokens = new ArrayList<String>();
        public String requestedPhase;
        public String requestedLinePair;
    }

    public static final class DirectAnswerResult {
        public String answer;
        public String dbContext;
    }

    public static final class DirectAnswerRequest {
        public String directIntentText;
        public boolean directPfStandard;
        public boolean directTripOnly;
        public boolean directAlarmCountIntent;
        public boolean directOpenAlarmsIntent;
        public boolean directOpenAlarmCountIntent;
        public boolean directScopedMonthlyEnergyIntent;
        public Integer directMeterId;
        public Integer directMonth;
        public Integer directTopN;
        public Integer directDays;
        public Integer directExplicitDays;
        public Timestamp directFromTs;
        public Timestamp directToTs;
        public String directPeriodLabel;
        public Double directHz;
        public Double directPf;
        public String directAlarmTypeToken;
        public String directAlarmAreaToken;
        public String directMeterScopeToken;
        public List<String> directPanelTokens = new ArrayList<String>();
        public String directPhaseLabel;
        public String directLinePairLabel;
    }

    public static final class AgentExecutionContext {
        public Integer requestedMeterId;
        public String requestedMeterScope;
        public Integer requestedMonth;
        public Integer requestedTopN;
        public String requestedPhase;
        public String requestedLinePair;
        public List<String> panelTokens = new ArrayList<String>();
        public boolean needsMeter;
        public boolean needsAlarm;
        public boolean needsFrequency;
        public boolean needsPerMeterPower;
        public boolean needsMeterList;
        public boolean needsPhaseCurrent;
        public boolean needsPhaseVoltage;
        public boolean needsLineVoltage;
        public boolean needsHarmonic;
        public boolean needsDb;
        public boolean forceCoderFlow;
    }

    public static final class PlannerExecutionResult {
        public String meterCtx = "";
        public String alarmCtx = "";
        public String frequencyCtx = "";
        public String powerCtx = "";
        public String meterListCtx = "";
        public String phaseCurrentCtx = "";
        public String phaseVoltageCtx = "";
        public String lineVoltageCtx = "";
        public String harmonicCtx = "";
        public String coderDraft = "";
    }

    public static final class SpecializedAnswerResult {
        public String answer;
    }
}
