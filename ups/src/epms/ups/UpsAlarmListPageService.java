package epms.ups;

import epms.util.UpsDateRangeSupport;

public final class UpsAlarmListPageService {
    private UpsAlarmListPageService() {
    }

    public static UpsAlarmListPageModel build(String rawSearchText, UpsDateRangeSupport.DateRange range, boolean activeOnly) {
        UpsAlarmListPageModel model = new UpsAlarmListPageModel();
        model.searchText = rawSearchText == null ? "" : rawSearchText.trim();
        model.fromRaw = range == null ? "" : range.fromRaw;
        model.toRaw = range == null ? "" : range.toRaw;
        model.explicitTo = range != null && range.explicitTo;
        model.activeOnly = activeOnly;
        try {
            if (activeOnly) {
                model.rows.addAll(UpsActiveAlarmQueryService.rows(model.searchText));
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
}
