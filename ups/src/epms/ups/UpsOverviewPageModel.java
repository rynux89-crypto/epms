package epms.ups;

import java.util.ArrayList;
import java.util.List;

public final class UpsOverviewPageModel {
    public String err;
    public boolean includeInactive;
    public final List<UpsOverviewItem> items = new ArrayList<UpsOverviewItem>();
    public int normalCount;
    public int alarmCount;
    public int commCount;
    public int unknownCount;
    public int disabledCount;

    public int inactiveOrUnknownCount() {
        return includeInactive ? disabledCount + unknownCount : unknownCount;
    }
}
