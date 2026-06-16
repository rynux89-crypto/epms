package epms.ups;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class UpsReportPageModel {
    public String err;
    public String searchText;
    public String fromRaw;
    public String toRaw;
    public boolean explicitTo;
    public final List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
    public int totalUps;
    public int totalMeasurements;
    public int totalAlarms;
    public int totalEvents;
    public int totalCritical;
    public Double fleetAvgLoad;
}
