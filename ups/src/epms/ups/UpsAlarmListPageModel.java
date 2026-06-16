package epms.ups;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class UpsAlarmListPageModel {
    public String err;
    public String searchText;
    public String fromRaw;
    public String toRaw;
    public boolean explicitTo;
    public boolean activeOnly;
    public final List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
}
