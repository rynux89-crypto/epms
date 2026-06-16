package epms.ups;

import epms.util.UpsSimulatorSupport;
import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

public final class UpsPhasorPageService {
    private static final int COMM_FAIL_OFFLINE_THRESHOLD = 3;

    private UpsPhasorPageService() {
    }

    public static UpsPhasorPageModel build(String selectedId) {
        UpsPhasorPageModel model = new UpsPhasorPageModel();
        model.selectedId = selectedId;
        try {
            List<Map<String, Object>> devices = UpsDeviceLookupService.listActiveDevicesWithProfile();
            model.devices.addAll(devices);
            selectDevice(model);
            if (model.selectedId != null && model.selectedId.trim().length() > 0) {
                model.measurement = UpsRealtimeService.latestPhasorMeasurement(model.selectedId);
            }
            mergeSimulator(model);
            model.hideData = isCommBad(model.selected) && !model.simulatorLive;
        } catch (Exception e) {
            model.err = e.getMessage();
        }
        return model;
    }

    private static void selectDevice(UpsPhasorPageModel model) {
        if ((model.selectedId == null || model.selectedId.trim().length() == 0) && !model.devices.isEmpty()) {
            model.selectedId = String.valueOf(model.devices.get(0).get("ups_id"));
        }
        if (model.selectedId == null || model.selectedId.trim().length() == 0) return;
        for (Map<String, Object> device : model.devices) {
            if (model.selectedId.equals(String.valueOf(device.get("ups_id")))) {
                model.selected = device;
                return;
            }
        }
    }

    private static void mergeSimulator(UpsPhasorPageModel model) {
        if (!UpsSimulatorSupport.isSimulatorDevice(model.selected)) return;
        String simStatus = UpsSimulatorSupport.readStatus(250);
        if (simStatus == null || simStatus.trim().isEmpty()) return;
        model.simulatorLive = true;
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_voltage_l12", "output_voltage_l12");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_voltage_l23", "output_voltage_l23");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_voltage_l31", "output_voltage_l31");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_current_l1", "output_current_l1");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_current_l2", "output_current_l2");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_current_l3", "output_current_l3");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_pf_l1", "output_pf_l1");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_pf_l2", "output_pf_l2");
        UpsSimulatorSupport.putJsonDecimal(model.measurement, simStatus, "output_pf_l3", "output_pf_l3");
        model.measurement.put("measured_at", new Timestamp(System.currentTimeMillis()));
    }

    private static boolean isCommBad(Map<String, Object> selected) {
        if (selected == null || selected.get("last_comm_status") == null) return false;
        int failCount = intValue(selected.get("consecutive_fail_count"), 0);
        if (failCount > 0 && failCount < COMM_FAIL_OFFLINE_THRESHOLD) return false;
        String comm = String.valueOf(selected.get("last_comm_status"));
        return !("OK".equalsIgnoreCase(comm) || "NORMAL".equalsIgnoreCase(comm) || "ONLINE".equalsIgnoreCase(comm));
    }

    private static int intValue(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            return value instanceof Number ? ((Number)value).intValue() : Integer.parseInt(String.valueOf(value).trim());
        } catch (Exception ignore) {
            return fallback;
        }
    }
}
