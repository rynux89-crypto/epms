package epms.remote;

import java.util.Collections;
import java.util.List;

public final class MeterStoreTilesPageData {
    private final List<String> floorOptions;
    private final List<String> zoneOptions;
    private final List<String> categoryOptions;
    private final List<MeterStoreTileRow> tiles;

    public MeterStoreTilesPageData(List<String> floorOptions, List<String> zoneOptions, List<String> categoryOptions,
            List<MeterStoreTileRow> tiles) {
        this.floorOptions = floorOptions == null ? Collections.<String>emptyList() : floorOptions;
        this.zoneOptions = zoneOptions == null ? Collections.<String>emptyList() : zoneOptions;
        this.categoryOptions = categoryOptions == null ? Collections.<String>emptyList() : categoryOptions;
        this.tiles = tiles == null ? Collections.<MeterStoreTileRow>emptyList() : tiles;
    }

    public List<String> getFloorOptions() { return floorOptions; }
    public List<String> getZoneOptions() { return zoneOptions; }
    public List<String> getCategoryOptions() { return categoryOptions; }
    public List<MeterStoreTileRow> getTiles() { return tiles; }
}
