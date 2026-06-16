package epms.ups;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;
import javax.servlet.ServletContext;

public final class UpsQueryService {
    private UpsQueryService() {
    }

    public static List<Map<String, Object>> listDevicesBasic() throws Exception {
        return UpsDeviceLookupService.listDevicesBasic();
    }

    public static List<Map<String, Object>> listDevicesWithProfile() throws Exception {
        return UpsDeviceLookupService.listDevicesWithProfile();
    }

    public static List<Map<String, Object>> measurementHistory(String selectedId, String searchText, Timestamp fromTs, Timestamp toTs, int limit) throws Exception {
        return UpsMeasurementHistoryService.measurementHistory(selectedId, searchText, fromTs, toTs, limit);
    }

    public static List<Map<String, Object>> alarmRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        return UpsAlarmEventService.alarmRows(searchText, fromTs, toTs);
    }

    public static List<Map<String, Object>> eventRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        return UpsAlarmEventService.eventRows(searchText, fromTs, toTs);
    }

    public static Map<String, Object> latestPhasorMeasurement(String selectedId) throws Exception {
        return UpsRealtimeService.latestPhasorMeasurement(selectedId);
    }

    public static Map<String, Object> realtimeStatus(String selectedId, ServletContext app) throws Exception {
        return UpsRealtimeService.realtimeStatus(selectedId, app);
    }

    public static List<Map<String, Object>> reportRows(String searchText, Timestamp fromTs, Timestamp toTs) throws Exception {
        return UpsReportService.reportRows(searchText, fromTs, toTs);
    }

    public static Map<String, Object> latestStatusMeasurement(String selectedId) throws Exception {
        return UpsRealtimeService.latestStatusMeasurement(selectedId);
    }

    public static void syncSimulatorScenarioEvent(ServletContext app) {
        UpsAlarmEventService.syncSimulatorScenarioEvent(app);
    }

}
