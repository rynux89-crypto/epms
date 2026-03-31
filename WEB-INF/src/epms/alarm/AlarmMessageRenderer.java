package epms.alarm;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

public final class AlarmMessageRenderer {
    private AlarmMessageRenderer() {
    }

    public static String formatDecimal2(Double value) {
        if (value == null) {
            return "";
        }
        return String.format(Locale.US, "%.2f", value.doubleValue());
    }

    public static String formatDecimal2(double value) {
        return String.format(Locale.US, "%.2f", value);
    }

    public static String render(String template, Map<String, String> vars, String fallback) {
        if (template == null || template.trim().isEmpty()) {
            return fallback;
        }
        String out = template;
        for (Map.Entry<String, String> entry : vars.entrySet()) {
            String key = entry.getKey();
            String value = entry.getValue() == null ? "" : entry.getValue();
            out = out.replace("${" + key + "}", value);
            out = out.replace("{" + key + "}", value);
        }
        return out.trim().isEmpty() ? fallback : out;
    }

    public static Map<String, String> aiVars(
            AlarmRuleDef rule,
            int meterId,
            String stage,
            String source,
            double value) {
        Map<String, String> vars = new LinkedHashMap<>();
        vars.put("meter_id", String.valueOf(meterId));
        vars.put("rule_code", safe(rule == null ? null : rule.getRuleCode()));
        vars.put("stage", safe(stage));
        vars.put("metric", safe(rule == null ? null : rule.getMetricKey()));
        vars.put("metric_key", safe(rule == null ? null : rule.getMetricKey()));
        vars.put("source", safe(source));
        vars.put("source_token", safe(source));
        vars.put("value", formatDecimal2(value));
        vars.put("operator", safe(rule == null ? null : rule.getOperator()));
        vars.put("t1", formatDecimal2(rule == null ? null : rule.getThreshold1()));
        vars.put("t2", formatDecimal2(rule == null ? null : rule.getThreshold2()));
        return vars;
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
