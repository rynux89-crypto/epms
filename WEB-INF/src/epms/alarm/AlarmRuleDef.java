package epms.alarm;

public final class AlarmRuleDef {
    private final int ruleId;
    private final String ruleCode;
    private final String targetScope;
    private final String metricKey;
    private final String sourceToken;
    private final String messageTemplate;
    private final String operator;
    private final Double threshold1;
    private final Double threshold2;
    private final int durationSec;
    private final Double hysteresis;
    private final String severity;

    public AlarmRuleDef(
            int ruleId,
            String ruleCode,
            String targetScope,
            String metricKey,
            String sourceToken,
            String messageTemplate,
            String operator,
            Double threshold1,
            Double threshold2,
            int durationSec,
            Double hysteresis,
            String severity) {
        this.ruleId = ruleId;
        this.ruleCode = ruleCode;
        this.targetScope = targetScope;
        this.metricKey = metricKey;
        this.sourceToken = sourceToken;
        this.messageTemplate = messageTemplate;
        this.operator = operator;
        this.threshold1 = threshold1;
        this.threshold2 = threshold2;
        this.durationSec = durationSec;
        this.hysteresis = hysteresis;
        this.severity = severity;
    }

    public int getRuleId() { return ruleId; }
    public String getRuleCode() { return ruleCode; }
    public String getTargetScope() { return targetScope; }
    public String getMetricKey() { return metricKey; }
    public String getSourceToken() { return sourceToken; }
    public String getMessageTemplate() { return messageTemplate; }
    public String getOperator() { return operator; }
    public Double getThreshold1() { return threshold1; }
    public Double getThreshold2() { return threshold2; }
    public int getDurationSec() { return durationSec; }
    public Double getHysteresis() { return hysteresis; }
    public String getSeverity() { return severity; }
}
