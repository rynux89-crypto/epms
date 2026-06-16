package epms.ups;

import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.util.HashMap;
import java.util.Map;

public final class UpsMeasurementRow {
    private final Map<String, Object> values;

    private UpsMeasurementRow(Map<String, Object> values) {
        this.values = values;
    }

    public static UpsMeasurementRow empty() {
        return new UpsMeasurementRow(new HashMap<String, Object>());
    }

    public static UpsMeasurementRow from(ResultSet rs) throws Exception {
        Map<String, Object> row = new HashMap<String, Object>();
        ResultSetMetaData md = rs.getMetaData();
        for (int i = 1; i <= md.getColumnCount(); i++) {
            row.put(md.getColumnLabel(i), rs.getObject(i));
        }
        return new UpsMeasurementRow(row);
    }

    public Object get(String key) {
        return values.get(key);
    }

    public void put(String key, Object value) {
        values.put(key, value);
    }

    public boolean hasMeasuredAt() {
        return values.get("measured_at") != null;
    }

    public Map<String, Object> toMap() {
        return new HashMap<String, Object>(values);
    }
}
