package epms.plc;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

public final class ModbusCycleSupport {
    public static final class LoadedResources {
        public final PlcConfig cfg;
        public final List<PlcDiTagEntry> diTagList;
        public final List<PlcAiMapEntry> aiMapList;
        public final Map<String, PlcAiMeasurementMatchEntry> aiMatchMap;

        public LoadedResources(
                PlcConfig cfg,
                List<PlcDiTagEntry> diTagList,
                List<PlcAiMapEntry> aiMapList,
                Map<String, PlcAiMeasurementMatchEntry> aiMatchMap) {
            this.cfg = cfg;
            this.diTagList = diTagList;
            this.aiMapList = aiMapList;
            this.aiMatchMap = aiMatchMap;
        }
    }

    public static final class DiCycleResult {
        public final PlcDiReadData diData;
        public final int[] diPersist;
        public final long elapsedMs;

        public DiCycleResult(PlcDiReadData diData, int[] diPersist, long elapsedMs) {
            this.diData = diData;
            this.diPersist = diPersist;
            this.elapsedMs = elapsedMs;
        }
    }

    public static final class AiCycleResult {
        public final PlcAiReadData aiData;
        public final int[] aiPersist;
        public final int[] aiAlarmPersist;
        public final long elapsedMs;

        public AiCycleResult(PlcAiReadData aiData, int[] aiPersist, int[] aiAlarmPersist, long elapsedMs) {
            this.aiData = aiData;
            this.aiPersist = aiPersist;
            this.aiAlarmPersist = aiAlarmPersist;
            this.elapsedMs = elapsedMs;
        }
    }

    private ModbusCycleSupport() {
    }

    public static LoadedResources loadResources(int plcId) throws Exception {
        PlcConfig cfg = ModbusConfigRepository.loadPlcConfig(plcId);
        List<PlcDiTagEntry> diTagList = ModbusConfigRepository.loadDiTagMap(plcId);
        List<PlcAiMapEntry> aiMapList = ModbusConfigRepository.loadAiMap(plcId);
        Map<String, PlcAiMeasurementMatchEntry> aiMatchMap = ModbusConfigRepository.loadAiMeasurementsMatch();
        return new LoadedResources(cfg, diTagList, aiMapList, aiMatchMap);
    }

    public static DiCycleResult runDiCycle(
            int plcId,
            PlcConfig cfg,
            List<PlcDiTagEntry> diTagList,
            epms.util.ModbusSupport.ModbusTcpClient client,
            Timestamp measuredAt) throws Exception {
        long diStart = System.currentTimeMillis();
        PlcDiReadData diData = ModbusRawReadService.readDiRows(client, cfg, diTagList);
        int[] diPersist = ModbusDiPersistService.persistDiRowsToDeviceEvents(plcId, diData.rows, measuredAt);
        long diElapsed = diData.durationMs > 0L ? diData.durationMs : Math.max(0L, System.currentTimeMillis() - diStart);
        return new DiCycleResult(diData, diPersist, diElapsed);
    }

    public static AiCycleResult runAiCycle(
            int plcId,
            PlcConfig cfg,
            List<PlcAiMapEntry> aiMapList,
            Map<String, PlcAiMeasurementMatchEntry> aiMatchMap,
            epms.util.ModbusSupport.ModbusTcpClient client,
            Timestamp measuredAt,
            String alarmApiUrl) throws Exception {
        long aiStart = System.currentTimeMillis();
        PlcAiReadData aiData = ModbusRawReadService.readAiRows(client, cfg, aiMapList);
        ModbusAiPersistService.persistAiRowsToSamples(plcId, cfg, aiData.rows, measuredAt);
        int[] aiPersist = ModbusAiPersistService.persistAiRowsToTargetTables(aiMatchMap, aiData.rows, measuredAt);
        int[] aiAlarmPersist = new int[]{0, 0};
        try {
            aiAlarmPersist = ModbusAlarmBridgeService.persistAiRowsViaAlarmApi(alarmApiUrl, plcId, aiData.rows, measuredAt);
        } catch (Exception ignore) {
        }
        long aiElapsed = aiData.durationMs > 0L ? aiData.durationMs : Math.max(0L, System.currentTimeMillis() - aiStart);
        return new AiCycleResult(aiData, aiPersist, aiAlarmPersist, aiElapsed);
    }
}
