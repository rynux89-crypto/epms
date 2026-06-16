package epms.ups;

import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class UpsAlarmRow {
    public final Object alarmId;
    public final String upsName;
    public final String severity;
    public final String metricKey;
    public final String alarmMessage;
    public final Object occurredAt;
    public final Object clearedAt;
    public final String status;
    private final Map<String, Object> values;

    private UpsAlarmRow(Map<String, Object> values) {
        this.values = values;
        this.alarmId = values.get("alarm_id");
        this.upsName = stringValue(values.get("ups_name"));
        this.severity = stringValue(values.get("severity"));
        this.metricKey = stringValue(values.get("metric_key"));
        this.alarmMessage = stringValue(values.get("alarm_message"));
        this.occurredAt = values.get("occurred_at");
        this.clearedAt = values.get("cleared_at");
        this.status = stringValue(values.get("status"));
    }

    public static UpsAlarmRow from(ResultSet rs) throws Exception {
        Map<String, Object> row = new HashMap<String, Object>();
        ResultSetMetaData md = rs.getMetaData();
        for (int i = 1; i <= md.getColumnCount(); i++) {
            row.put(md.getColumnLabel(i), rs.getObject(i));
        }
        return new UpsAlarmRow(row);
    }

    public Map<String, Object> toMap() {
        return new HashMap<String, Object>(values);
    }

    public static List<Map<String, Object>> toMaps(List<UpsAlarmRow> rows) {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        for (UpsAlarmRow row : rows) {
            out.add(row.toMap());
        }
        return out;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
