package epms.ups;

import epms.util.UpsDateRangeSupport;
import java.util.List;
import java.util.Map;

public final class UpsReportPageService {
    private UpsReportPageService() {
    }

    public static UpsReportPageModel build(String rawSearchText, UpsDateRangeSupport.DateRange range) {
        UpsReportPageModel model = new UpsReportPageModel();
        model.searchText = rawSearchText == null ? "" : rawSearchText.trim();
        model.fromRaw = range == null ? "" : range.fromRaw;
        model.toRaw = range == null ? "" : range.toRaw;
        model.explicitTo = range != null && range.explicitTo;
        try {
            List<Map<String, Object>> rows = UpsReportService.reportRows(
                model.searchText,
                range == null ? null : range.fromTs,
                range == null ? null : range.toTs);
            model.rows.addAll(rows);
            summarize(model);
        } catch (Exception e) {
            model.err = e.getMessage();
        }
        return model;
    }

    private static void summarize(UpsReportPageModel model) {
        model.totalUps = model.rows.size();
        double avgLoadSum = 0d;
        int avgLoadCount = 0;
        for (Map<String, Object> row : model.rows) {
            model.totalMeasurements += intValue(row.get("measurement_count"));
            model.totalAlarms += intValue(row.get("alarm_count"));
            model.totalEvents += intValue(row.get("event_count"));
            model.totalCritical += intValue(row.get("critical_count"));
            Object avg = row.get("avg_load_percent");
            if (avg instanceof Number) {
                avgLoadSum += ((Number)avg).doubleValue();
                avgLoadCount++;
            }
        }
        model.fleetAvgLoad = avgLoadCount == 0 ? null : Double.valueOf(avgLoadSum / avgLoadCount);
    }

    private static int intValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Number) return ((Number)value).intValue();
        try {
            return Integer.parseInt(String.valueOf(value));
        } catch (Exception ignore) {
            return 0;
        }
    }
}
