package epms.alarm;

import java.sql.Timestamp;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public final class AlarmApiModels {
    private AlarmApiModels() {
    }

    public static final class AiRow {
        public int meterId;
        public String token;
        public double value;
    }

    public static final class DiRequestPayload {
        public int plcId;
        public Timestamp measuredAt;
        public List<Map<String, Object>> rows = Collections.emptyList();
    }

    public static final class AiRequestPayload {
        public int plcId;
        public Timestamp measuredAt;
        public List<AiRow> rows = Collections.emptyList();
    }

    public static final class OpenCloseCount {
        public int opened;
        public int closed;
    }

    public static final class CacheEntry<T> {
        public final T data;
        public final long loadedAtMs;

        public CacheEntry(T data) {
            this.data = data;
            this.loadedAtMs = System.currentTimeMillis();
        }
    }

    public static final class DiRuleMeta {
        public int ruleId;
        public String ruleCode;
        public String ruleName;
        public String metricKey;
        public String messageTemplate;
    }

    public static final class AiPreparedMetrics {
        public Map<Integer, Map<String, Double>> valueByMeterMetric = Collections.emptyMap();
        public Map<String, Map<String, Double>> previousByMeter = Collections.emptyMap();
    }

    public static final class DiRuntimeContext {
        public Map<String, Integer> meterIdByName = Collections.emptyMap();
        public Map<String, DiRuleMeta> diRuleMetaMap = Collections.emptyMap();
    }
}
