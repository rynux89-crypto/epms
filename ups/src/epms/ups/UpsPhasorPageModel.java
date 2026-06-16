package epms.ups;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class UpsPhasorPageModel {
    public String err;
    public String selectedId;
    public final List<Map<String, Object>> devices = new ArrayList<Map<String, Object>>();
    public Map<String, Object> selected;
    public Map<String, Object> measurement = new HashMap<String, Object>();
    public boolean simulatorLive;
    public boolean hideData;

    public boolean hasData() {
        return !hideData && measurement.get("measured_at") != null;
    }
}
