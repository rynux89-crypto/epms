package epms.plc;

import epms.util.ModbusSupport;
import java.sql.Timestamp;
public final class ModbusReadService {
    private ModbusReadService() {
    }

    public static PlcReadResult readPlcData(int plcId, String alarmApiUrl) {
        PlcReadResult result = new PlcReadResult();
        try {
            long tAllStart = System.currentTimeMillis();
            Timestamp measuredAt = new Timestamp(tAllStart);
            ModbusCycleSupport.LoadedResources resources = ModbusCycleSupport.loadResources(plcId);
            PlcConfig cfg = resources.cfg;
            if (!cfg.exists || cfg.ip == null) {
                result.error = "Selected PLC config not found.";
                return result;
            }
            if (!cfg.enabled) {
                result.error = "Selected PLC is inactive.";
                return result;
            }
            ModbusCycleSupport.DiCycleResult diResult;
            ModbusCycleSupport.AiCycleResult aiResult;
            try (epms.util.ModbusSupport.ModbusTcpClient client = new epms.util.ModbusSupport.ModbusTcpClient(cfg.ip, cfg.port)) {
                diResult = ModbusCycleSupport.runDiCycle(plcId, cfg, resources.diTagList, client, measuredAt);
                aiResult = ModbusCycleSupport.runAiCycle(
                        plcId,
                        cfg,
                        resources.aiMapList,
                        resources.aiMatchMap,
                        client,
                        measuredAt,
                        resolveAlarmApiUrl(alarmApiUrl)
                );
            }

            result.diRows = diResult.diData.rows;
            result.rows = aiResult.aiData.rows;
            result.measurementsInserted = aiResult.aiPersist[0];
            result.harmonicInserted = aiResult.aiPersist[1];
            result.flickerInserted = aiResult.aiPersist[2];
            result.deviceEventsOpened = diResult.diPersist[0];
            result.deviceEventsClosed = diResult.diPersist[1];
            result.aiAlarmOpened = aiResult.aiAlarmPersist[0];
            result.aiAlarmClosed = aiResult.aiAlarmPersist[1];
            result.ok = true;
            result.info = "Read success. PLC " + plcId + " (" + cfg.ip + ":" + cfg.port + ", unit " + cfg.unitId +
                    "), meters=" + aiResult.aiData.meterRead + ", total_floats=" + aiResult.aiData.totalFloat + ", di_tags=" + result.diRows.size() +
                    ", measurements_ins=" + result.measurementsInserted + ", harmonic_ins=" + result.harmonicInserted +
                    ", flicker_ins=" + result.flickerInserted +
                    ", events_opened=" + result.deviceEventsOpened + ", events_closed=" + result.deviceEventsClosed +
                    ", ai_alarm_opened=" + result.aiAlarmOpened + ", ai_alarm_closed=" + result.aiAlarmClosed;
            long tEnd = System.currentTimeMillis();
            result.diMs = diResult.diData.durationMs;
            result.aiMs = aiResult.aiData.durationMs;
            result.procMs = Math.max(0L, tEnd - tAllStart - result.diMs - result.aiMs);
            result.totalMs = Math.max(0L, tEnd - tAllStart);
            return result;
        } catch (Exception e) {
            result.error = e.getMessage();
            return result;
        }
    }

    private static String resolveAlarmApiUrl(String alarmApiUrl) {
        if (alarmApiUrl != null && !alarmApiUrl.trim().isEmpty()) {
            return alarmApiUrl;
        }
        return ModbusSupport.resolveAlarmApiUrl(null);
    }
}
