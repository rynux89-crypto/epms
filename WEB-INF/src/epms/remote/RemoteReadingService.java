package epms.remote;

import java.sql.Connection;
import java.sql.Date;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class RemoteReadingService {
    private final RemoteReadingRepository repository = new RemoteReadingRepository();

    public MeterStoreTilesPageData loadMeterStoreTilesPage(String q, String floor, String zone, String category,
            String openedOn, String contact) throws Exception {
        String safeQ = trimToEmpty(q);
        String safeFloor = trimToEmpty(floor);
        String safeZone = trimToEmpty(zone);
        String safeCategory = trimToEmpty(category);
        String safeOpenedOn = trimToEmpty(openedOn);
        String safeContact = trimToEmpty(contact);

        LocalDate today = LocalDate.now();
        LocalDate prevMonthStart = today.minusMonths(1).withDayOfMonth(1);
        LocalDate prevMonthEnd = prevMonthStart.withDayOfMonth(prevMonthStart.lengthOfMonth());

        try (Connection conn = repository.openConnection()) {
            return new MeterStoreTilesPageData(
                    repository.listFloorOptions(conn),
                    repository.listZoneOptions(conn),
                    repository.listCategoryOptions(conn),
                    repository.listMeterStoreTiles(conn, safeQ, safeFloor, safeZone, safeCategory, safeOpenedOn, safeContact, prevMonthStart, prevMonthEnd));
        }
    }

    public EnergyDetailPageData loadEnergyDetailPage(int storeId, int meterId) throws Exception {
        LocalDate today = LocalDate.now();
        LocalDate currentMonthStart = today.withDayOfMonth(1);
        LocalDate prevMonthStart = currentMonthStart.minusMonths(1);
        LocalDate dailyStart = today.minusDays(30);
        LocalDate monthSeriesStart = currentMonthStart.minusMonths(11).withDayOfMonth(1);

        try (Connection conn = repository.openConnection()) {
            EnergyDetailSnapshot snapshot = repository.loadEnergyDetailSnapshot(conn, storeId, meterId, monthSeriesStart, today);
            return buildEnergyDetailPageData(snapshot, today, currentMonthStart, prevMonthStart,
                    currentMonthStart.minusDays(1), dailyStart, monthSeriesStart, null);
        } catch (Exception e) {
            EnergyDetailSnapshot snapshot = new EnergyDetailSnapshot();
            snapshot.setStoreId(storeId);
            snapshot.setMeterId(meterId);
            return buildEnergyDetailPageData(snapshot, today, currentMonthStart, prevMonthStart,
                    currentMonthStart.minusDays(1), dailyStart, monthSeriesStart, e.getMessage());
        }
    }

    private EnergyDetailPageData buildEnergyDetailPageData(EnergyDetailSnapshot snapshot, LocalDate today,
            LocalDate currentMonthStart, LocalDate prevMonthStart, LocalDate prevMonthEnd, LocalDate dailyStart,
            LocalDate monthSeriesStart, String queryError) {
        LocalDate openedLocal = snapshot.getOpenedOn() == null ? null : snapshot.getOpenedOn().toLocalDate();
        LocalDate closedLocal = snapshot.getClosedOn() == null ? null : snapshot.getClosedOn().toLocalDate();
        LocalDate validFromLocal = snapshot.getValidFrom() == null ? null : snapshot.getValidFrom().toLocalDate();
        LocalDate validToLocal = snapshot.getValidTo() == null ? null : snapshot.getValidTo().toLocalDate();

        LocalDate startLocal = null;
        if (openedLocal == null) startLocal = validFromLocal;
        else if (validFromLocal == null) startLocal = openedLocal;
        else startLocal = openedLocal.isBefore(validFromLocal) ? openedLocal : validFromLocal;

        LocalDate endLocal = null;
        if (closedLocal == null) endLocal = validToLocal;
        else if (validToLocal == null) endLocal = closedLocal;
        else endLocal = closedLocal.isBefore(validToLocal) ? closedLocal : validToLocal;

        LinkedHashMap<String, Double> dailyUsage = new LinkedHashMap<String, Double>();
        LinkedHashMap<String, Double> monthlyUsage = new LinkedHashMap<String, Double>();
        for (LocalDate d = dailyStart; !d.isAfter(today); d = d.plusDays(1)) dailyUsage.put(d.toString(), Double.valueOf(0.0d));
        for (YearMonth ym = YearMonth.from(monthSeriesStart); !ym.isAfter(YearMonth.from(today)); ym = ym.plusMonths(1)) {
            monthlyUsage.put(ym.toString(), Double.valueOf(0.0d));
        }

        double todayKwh = 0.0d;
        double currentMonthKwh = 0.0d;
        double prevMonthKwh = 0.0d;
        for (Map.Entry<java.time.LocalDate, Double> entry : snapshot.getDailyUsage().entrySet()) {
            LocalDate day = entry.getKey();
            double safe = entry.getValue() != null && entry.getValue().doubleValue() >= 0.0d ? entry.getValue().doubleValue() : 0.0d;
            boolean inRange = true;
            if (startLocal != null && day.isBefore(startLocal)) inRange = false;
            if (endLocal != null && day.isAfter(endLocal)) inRange = false;
            if (!inRange) safe = 0.0d;
            String dayKey = day.toString();
            if (dailyUsage.containsKey(dayKey)) dailyUsage.put(dayKey, Double.valueOf(safe));
            String ymKey = String.format(java.util.Locale.ROOT, "%04d-%02d", day.getYear(), day.getMonthValue());
            if (monthlyUsage.containsKey(ymKey)) monthlyUsage.put(ymKey, Double.valueOf(monthlyUsage.get(ymKey).doubleValue() + safe));
            if (day.equals(today)) todayKwh += safe;
            if (!day.isBefore(currentMonthStart)) currentMonthKwh += safe;
            if (!day.isBefore(prevMonthStart) && !day.isAfter(prevMonthEnd)) prevMonthKwh += safe;
        }

        double shownCurrentKw = 0.0d;
        boolean usingFallbackCurrent = false;
        if (snapshot.getCurrentKw() != null && Math.abs(snapshot.getCurrentKw().doubleValue()) > 0.0001d) {
            shownCurrentKw = snapshot.getCurrentKw().doubleValue();
        } else if (snapshot.getCurrentValidKw() != null) {
            shownCurrentKw = snapshot.getCurrentValidKw().doubleValue();
            usingFallbackCurrent = true;
        }

        List<String> locationParts = new ArrayList<String>();
        if (snapshot.getFloorName() != null && !snapshot.getFloorName().trim().isEmpty()) locationParts.add(snapshot.getFloorName().trim());
        if (snapshot.getRoomName() != null && !snapshot.getRoomName().trim().isEmpty()) locationParts.add(snapshot.getRoomName().trim());
        if (snapshot.getZoneName() != null && !snapshot.getZoneName().trim().isEmpty()) locationParts.add(snapshot.getZoneName().trim());
        String locationText = locationParts.isEmpty() ? "-" : String.join(" / ", locationParts);

        String storeName = snapshot.getStoreName();
        if (storeName == null || storeName.trim().isEmpty()) storeName = "Store " + snapshot.getStoreId();
        String meterName = snapshot.getMeterName();
        if (meterName == null || meterName.trim().isEmpty()) meterName = "Meter " + snapshot.getMeterId();
        String storeCode = snapshot.getStoreCode();
        if (storeCode == null || storeCode.trim().isEmpty()) storeCode = "STORE-" + snapshot.getStoreId();

        return new EnergyDetailPageData(
                snapshot.getStoreId(),
                snapshot.getMeterId(),
                storeCode,
                storeName,
                snapshot.getCategoryName(),
                snapshot.getContactName(),
                snapshot.getContactPhone(),
                meterName,
                snapshot.getBuildingName(),
                snapshot.getPanelName(),
                snapshot.getUsageType(),
                locationText,
                snapshot.getOpenedOn(),
                snapshot.getClosedOn(),
                snapshot.getValidFrom(),
                snapshot.getValidTo(),
                startLocal == null ? null : Date.valueOf(startLocal),
                endLocal == null ? null : Date.valueOf(endLocal),
                snapshot.getAllocationRatio(),
                snapshot.getBillingScope(),
                snapshot.getIsPrimary(),
                snapshot.getCurrentMeasuredAt(),
                snapshot.getCurrentValidMeasuredAt(),
                shownCurrentKw,
                usingFallbackCurrent,
                todayKwh,
                currentMonthKwh,
                prevMonthKwh,
                today.toString(),
                currentMonthStart.toString().substring(0, 7),
                prevMonthStart.toString().substring(0, 7),
                dailyUsage,
                monthlyUsage,
                queryError);
    }

    private static String trimToEmpty(String value) {
        return value == null ? "" : value.trim();
    }
}
