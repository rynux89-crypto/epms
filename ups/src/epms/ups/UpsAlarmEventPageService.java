package epms.ups;

import epms.util.UpsDateRangeSupport;
import javax.servlet.ServletContext;

public final class UpsAlarmEventPageService {
    private UpsAlarmEventPageService() {
    }

    public static UpsAlarmEventPageModel alarms(String rawSearchText, UpsDateRangeSupport.DateRange range) {
        return alarms(rawSearchText, range, false);
    }

    public static UpsAlarmEventPageModel alarms(String rawSearchText, UpsDateRangeSupport.DateRange range, boolean activeOnly) {
        UpsAlarmEventPageModel model = baseModel(rawSearchText, range);
        model.activeOnly = activeOnly;
        try {
            if (activeOnly) {
                model.rows.addAll(UpsAlarmEventService.activeAlarmRows(model.searchText));
            } else {
                model.rows.addAll(UpsAlarmEventService.alarmRows(
                    model.searchText,
                    range == null ? null : range.fromTs,
                    range == null ? null : range.toTs));
            }
        } catch (Exception e) {
            model.err = e.getMessage();
        }
        return model;
    }

    public static UpsAlarmEventPageModel events(String rawSearchText, UpsDateRangeSupport.DateRange range, ServletContext app) {
        UpsAlarmEventPageModel model = baseModel(rawSearchText, range);
        try {
            UpsAlarmEventService.syncSimulatorScenarioEvent(app);
            model.rows.addAll(UpsAlarmEventService.eventRows(
                model.searchText,
                range == null ? null : range.fromTs,
                range == null ? null : range.toTs));
        } catch (Exception e) {
            model.err = e.getMessage();
        }
        return model;
    }

    private static UpsAlarmEventPageModel baseModel(String rawSearchText, UpsDateRangeSupport.DateRange range) {
        UpsAlarmEventPageModel model = new UpsAlarmEventPageModel();
        model.searchText = rawSearchText == null ? "" : rawSearchText.trim();
        model.fromRaw = range == null ? "" : range.fromRaw;
        model.toRaw = range == null ? "" : range.toRaw;
        model.explicitTo = range != null && range.explicitTo;
        return model;
    }
}
