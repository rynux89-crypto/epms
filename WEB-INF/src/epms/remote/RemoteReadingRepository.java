package epms.remote;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public final class RemoteReadingRepository {
    public Connection openConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public List<String> listFloorOptions(Connection conn) throws Exception {
        List<String> rows = new ArrayList<String>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT x.floor_name " +
                "FROM ( " +
                "    SELECT floor_name, TRY_CONVERT(int, floor_name) AS floor_no " +
                "    FROM dbo.tenant_store " +
                "    WHERE floor_name IS NOT NULL AND LTRIM(RTRIM(floor_name)) <> '' " +
                "    GROUP BY floor_name " +
                ") x " +
                "ORDER BY CASE WHEN x.floor_no IS NULL THEN 1 ELSE 0 END, x.floor_no, x.floor_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) rows.add(rs.getString(1));
        }
        return rows;
    }

    public List<String> listZoneOptions(Connection conn) throws Exception {
        List<String> rows = new ArrayList<String>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT x.zone_name " +
                "FROM ( " +
                "    SELECT zone_name " +
                "    FROM dbo.tenant_store " +
                "    WHERE zone_name IS NOT NULL AND LTRIM(RTRIM(zone_name)) <> '' " +
                "    GROUP BY zone_name " +
                ") x " +
                "ORDER BY x.zone_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) rows.add(rs.getString(1));
        }
        return rows;
    }

    public List<String> listCategoryOptions(Connection conn) throws Exception {
        List<String> rows = new ArrayList<String>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT x.category_name " +
                "FROM ( " +
                "    SELECT category_name " +
                "    FROM dbo.tenant_store " +
                "    WHERE category_name IS NOT NULL AND LTRIM(RTRIM(category_name)) <> '' " +
                "    GROUP BY category_name " +
                ") x " +
                "ORDER BY x.category_name");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) rows.add(rs.getString(1));
        }
        return rows;
    }

    private static Double getNullableDouble(ResultSet rs, String columnName) throws Exception {
        Object value = rs.getObject(columnName);
        if (value == null) return null;
        return Double.valueOf(((Number) value).doubleValue());
    }

    public List<MeterStoreTileRow> listMeterStoreTiles(Connection conn, String q, String floor, String zone,
            String category, String openedOn, String contact, LocalDate prevMonthStart, LocalDate prevMonthEnd) throws Exception {
        List<MeterStoreTileRow> rows = new ArrayList<MeterStoreTileRow>();
        String sql =
            "WITH active_map AS ( " +
            "    SELECT tm.map_id, tm.store_id, tm.meter_id, tm.is_primary, tm.valid_from, tm.valid_to, " +
            "           ts.store_code, ts.store_name, ts.floor_name, ts.room_name, ts.zone_name, ts.category_name, ts.opened_on, ts.contact_name, " +
            "           ROW_NUMBER() OVER (PARTITION BY tm.meter_id ORDER BY tm.is_primary DESC, ts.store_code ASC, tm.map_id ASC) AS display_rn " +
            "    FROM dbo.tenant_meter_map tm " +
            "    INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id " +
            "    WHERE tm.valid_from <= CAST(GETDATE() AS date) " +
            "      AND (tm.valid_to IS NULL OR tm.valid_to >= CAST(GETDATE() AS date)) " +
            "), meter_scope AS ( " +
            "    SELECT m.meter_id, m.name AS meter_name, m.building_name, m.panel_name, m.usage_type, " +
            "           COUNT(am.map_id) AS store_count, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN am.store_id END) AS display_store_id, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN am.store_name END) AS display_store_name, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN am.store_code END) AS display_store_code, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN am.floor_name END) AS display_floor_name, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN am.room_name END) AS display_room_name, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN am.zone_name END) AS display_zone_name, " +
            "           MAX(CASE WHEN am.display_rn = 1 THEN CASE " +
            "                 WHEN am.opened_on IS NULL THEN am.valid_from " +
            "                 WHEN am.valid_from IS NULL THEN am.opened_on " +
            "                 WHEN am.opened_on <= am.valid_from THEN am.opened_on " +
            "                 ELSE am.valid_from END END) AS effective_start_date, " +
            "           STRING_AGG(CONCAT(am.store_code, ' | ', am.store_name), ' || ') WITHIN GROUP (ORDER BY am.store_code) AS store_list " +
            "    FROM dbo.meters m " +
            "    INNER JOIN active_map am ON am.meter_id = m.meter_id " +
            "    WHERE (? = '' OR ISNULL(am.floor_name, '') LIKE ?) " +
            "      AND (? = '' OR ISNULL(am.zone_name, '') LIKE ?) " +
            "      AND (? = '' OR ISNULL(am.category_name, '') LIKE ?) " +
            "      AND (? = '' OR CONVERT(varchar(10), am.opened_on, 23) = ?) " +
            "      AND (? = '' OR ISNULL(am.contact_name, '') LIKE ?) " +
            "      AND (? = '' OR m.name LIKE ? OR ISNULL(m.panel_name, '') LIKE ? OR ISNULL(am.store_name, '') LIKE ? OR ISNULL(am.store_code, '') LIKE ?) " +
            "    GROUP BY m.meter_id, m.name, m.building_name, m.panel_name, m.usage_type " +
            "), latest_power AS ( " +
            "    SELECT x.meter_id, x.measured_at, x.active_power_total " +
            "    FROM ( " +
            "        SELECT ms.meter_id, ms.measured_at, CAST(ms.active_power_total AS float) AS active_power_total, " +
            "               ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
            "        FROM dbo.measurements ms " +
            "        INNER JOIN meter_scope s ON s.meter_id = ms.meter_id " +
            "        WHERE ms.active_power_total IS NOT NULL " +
            "    ) x WHERE x.rn = 1 " +
            "), latest_valid_power AS ( " +
            "    SELECT x.meter_id, x.measured_at, x.active_power_total " +
            "    FROM ( " +
            "        SELECT ms.meter_id, ms.measured_at, CAST(ms.active_power_total AS float) AS active_power_total, " +
            "               ROW_NUMBER() OVER (PARTITION BY ms.meter_id ORDER BY ms.measured_at DESC) AS rn " +
            "        FROM dbo.measurements ms " +
            "        INNER JOIN meter_scope s ON s.meter_id = ms.meter_id " +
            "        WHERE ms.active_power_total IS NOT NULL AND ABS(CAST(ms.active_power_total AS float)) > 0.0001 " +
            "    ) x WHERE x.rn = 1 " +
            "), day_last AS ( " +
            "    SELECT ms.meter_id, CAST(ms.measured_at AS date) AS d, CAST(ms.energy_consumed_total AS float) AS energy_total, " +
            "           ROW_NUMBER() OVER (PARTITION BY ms.meter_id, CAST(ms.measured_at AS date) ORDER BY ms.measured_at DESC) AS rn " +
            "    FROM dbo.measurements ms " +
            "    INNER JOIN meter_scope s ON s.meter_id = ms.meter_id " +
            "    WHERE ms.energy_consumed_total IS NOT NULL " +
            "      AND ms.measured_at >= DATEADD(day, -1, ?) " +
            "      AND ms.measured_at < DATEADD(day, 1, ?) " +
            "), day_meter AS ( " +
            "    SELECT meter_id, d, energy_total AS end_total FROM day_last WHERE rn = 1 " +
            "), day_diff AS ( " +
            "    SELECT meter_id, d, end_total - LAG(end_total) OVER (PARTITION BY meter_id ORDER BY d) AS day_kwh " +
            "    FROM day_meter " +
            "), prev_month_usage AS ( " +
            "    SELECT d.meter_id, SUM(CASE WHEN d.day_kwh >= 0 THEN d.day_kwh ELSE 0 END) AS last_month_kwh " +
            "    FROM day_diff d " +
            "    INNER JOIN meter_scope s ON s.meter_id = d.meter_id " +
            "    WHERE d.d BETWEEN ? AND ? " +
            "      AND d.d >= CASE " +
            "            WHEN s.effective_start_date IS NULL THEN ? " +
            "            WHEN s.effective_start_date < ? THEN ? " +
            "            ELSE s.effective_start_date END " +
            "    GROUP BY d.meter_id " +
            ") " +
            "SELECT s.meter_id, s.meter_name, s.building_name, s.panel_name, s.usage_type, s.store_count, " +
            "       s.display_store_id, s.display_store_name, s.display_store_code, s.display_floor_name, s.display_room_name, s.display_zone_name, s.effective_start_date, s.store_list, " +
            "       lp.active_power_total AS current_kw, lvp.active_power_total AS current_valid_kw, pmu.last_month_kwh " +
            "FROM meter_scope s " +
            "LEFT JOIN latest_power lp ON lp.meter_id = s.meter_id " +
            "LEFT JOIN latest_valid_power lvp ON lvp.meter_id = s.meter_id " +
            "LEFT JOIN prev_month_usage pmu ON pmu.meter_id = s.meter_id " +
            "ORDER BY TRY_CONVERT(int, NULLIF(s.display_floor_name, '')) ASC, s.display_floor_name ASC, " +
            "         TRY_CONVERT(int, NULLIF(s.display_room_name, '')) ASC, s.display_room_name ASC, " +
            "         s.display_store_name ASC, s.meter_id ASC";

        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, floor);
            ps.setString(2, "%" + floor + "%");
            ps.setString(3, zone);
            ps.setString(4, "%" + zone + "%");
            ps.setString(5, category);
            ps.setString(6, "%" + category + "%");
            ps.setString(7, openedOn);
            ps.setString(8, openedOn);
            ps.setString(9, contact);
            ps.setString(10, "%" + contact + "%");
            ps.setString(11, q);
            ps.setString(12, "%" + q + "%");
            ps.setString(13, "%" + q + "%");
            ps.setString(14, "%" + q + "%");
            ps.setString(15, "%" + q + "%");
            ps.setDate(16, Date.valueOf(prevMonthStart));
            ps.setDate(17, Date.valueOf(prevMonthEnd));
            ps.setDate(18, Date.valueOf(prevMonthStart));
            ps.setDate(19, Date.valueOf(prevMonthEnd));
            ps.setDate(20, Date.valueOf(prevMonthStart));
            ps.setDate(21, Date.valueOf(prevMonthStart));
            ps.setDate(22, Date.valueOf(prevMonthStart));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Integer displayStoreId = rs.getObject("display_store_id") == null ? null : Integer.valueOf(rs.getInt("display_store_id"));
                    rows.add(new MeterStoreTileRow(
                            rs.getInt("meter_id"),
                            rs.getString("meter_name"),
                            rs.getString("building_name"),
                            rs.getString("panel_name"),
                            rs.getString("usage_type"),
                            rs.getInt("store_count"),
                            displayStoreId,
                            rs.getString("display_store_name"),
                            rs.getString("display_store_code"),
                            rs.getString("display_floor_name"),
                            rs.getString("display_room_name"),
                            rs.getString("display_zone_name"),
                            rs.getDate("effective_start_date"),
                            rs.getString("store_list"),
                            getNullableDouble(rs, "last_month_kwh"),
                            getNullableDouble(rs, "current_kw"),
                            getNullableDouble(rs, "current_valid_kw")));
                }
            }
        }
        return rows;
    }

    public EnergyDetailSnapshot loadEnergyDetailSnapshot(Connection conn, int storeId, int meterId,
            LocalDate monthSeriesStart, LocalDate today) throws Exception {
        EnergyDetailSnapshot snapshot = new EnergyDetailSnapshot();
        snapshot.setStoreId(storeId);
        snapshot.setMeterId(meterId);

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT store_code, store_name, floor_name, room_name, zone_name, category_name, contact_name, contact_phone, opened_on, closed_on " +
                "FROM dbo.tenant_store WHERE store_id = ?")) {
            ps.setInt(1, storeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    snapshot.setStoreCode(rs.getString("store_code"));
                    snapshot.setStoreName(rs.getString("store_name"));
                    snapshot.setFloorName(rs.getString("floor_name"));
                    snapshot.setRoomName(rs.getString("room_name"));
                    snapshot.setZoneName(rs.getString("zone_name"));
                    snapshot.setCategoryName(rs.getString("category_name"));
                    snapshot.setContactName(rs.getString("contact_name"));
                    snapshot.setContactPhone(rs.getString("contact_phone"));
                    snapshot.setOpenedOn(rs.getDate("opened_on"));
                    snapshot.setClosedOn(rs.getDate("closed_on"));
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT name, building_name, panel_name, usage_type FROM dbo.meters WHERE meter_id = ?")) {
            ps.setInt(1, meterId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    snapshot.setMeterName(rs.getString("name"));
                    snapshot.setBuildingName(rs.getString("building_name"));
                    snapshot.setPanelName(rs.getString("panel_name"));
                    snapshot.setUsageType(rs.getString("usage_type"));
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 valid_from, valid_to, allocation_ratio, billing_scope, is_primary " +
                "FROM dbo.tenant_meter_map WHERE store_id = ? AND meter_id = ? " +
                "ORDER BY is_primary DESC, valid_from DESC, map_id DESC")) {
            ps.setInt(1, storeId);
            ps.setInt(2, meterId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    snapshot.setValidFrom(rs.getDate("valid_from"));
                    snapshot.setValidTo(rs.getDate("valid_to"));
                    snapshot.setAllocationRatio(getNullableDouble(rs, "allocation_ratio"));
                    snapshot.setBillingScope(rs.getString("billing_scope"));
                    snapshot.setIsPrimary(rs.getObject("is_primary") == null ? null : Boolean.valueOf(rs.getBoolean("is_primary")));
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 measured_at, CAST(active_power_total AS float) AS active_kw " +
                "FROM dbo.measurements WHERE meter_id = ? ORDER BY measured_at DESC")) {
            ps.setInt(1, meterId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    snapshot.setCurrentMeasuredAt(rs.getTimestamp("measured_at"));
                    snapshot.setCurrentKw(getNullableDouble(rs, "active_kw"));
                }
            }
        }

        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT TOP 1 measured_at, CAST(active_power_total AS float) AS active_kw " +
                "FROM dbo.measurements WHERE meter_id = ? " +
                "AND active_power_total IS NOT NULL AND ABS(CAST(active_power_total AS float)) > 0.0001 " +
                "ORDER BY measured_at DESC")) {
            ps.setInt(1, meterId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    snapshot.setCurrentValidMeasuredAt(rs.getTimestamp("measured_at"));
                    snapshot.setCurrentValidKw(getNullableDouble(rs, "active_kw"));
                }
            }
        }

        String diffSql =
            "WITH day_last AS ( " +
            "    SELECT CAST(measured_at AS date) AS d, CAST(energy_consumed_total AS float) AS energy_total, " +
            "           ROW_NUMBER() OVER (PARTITION BY CAST(measured_at AS date) ORDER BY measured_at DESC) AS rn " +
            "    FROM dbo.measurements " +
            "    WHERE meter_id = ? " +
            "      AND energy_consumed_total IS NOT NULL " +
            "      AND measured_at >= DATEADD(day, -1, ?) " +
            "      AND measured_at < DATEADD(day, 1, ?) " +
            "), day_meter AS ( " +
            "    SELECT d, energy_total AS end_total FROM day_last WHERE rn = 1 " +
            "), day_diff AS ( " +
            "    SELECT d, end_total - LAG(end_total) OVER (ORDER BY d) AS day_kwh FROM day_meter " +
            ") " +
            "SELECT d, day_kwh FROM day_diff WHERE d BETWEEN ? AND ? ORDER BY d";

        try (PreparedStatement ps = conn.prepareStatement(diffSql)) {
            ps.setInt(1, meterId);
            ps.setDate(2, Date.valueOf(monthSeriesStart.minusDays(1)));
            ps.setDate(3, Date.valueOf(today));
            ps.setDate(4, Date.valueOf(monthSeriesStart));
            ps.setDate(5, Date.valueOf(today));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Date dObj = rs.getDate("d");
                    if (dObj == null) continue;
                    snapshot.putDailyUsage(dObj.toLocalDate(), getNullableDouble(rs, "day_kwh"));
                }
            }
        }

        return snapshot;
    }
}
