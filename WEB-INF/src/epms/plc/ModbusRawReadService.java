package epms.plc;

import epms.util.ModbusReadSupport;
import epms.util.ModbusSupport;
import java.util.List;

public final class ModbusRawReadService {
    private ModbusRawReadService() {
    }

    public static PlcDiReadData readDiData(PlcConfig cfg, List<PlcDiTagEntry> diTagList) throws Exception {
        try (ModbusSupport.ModbusTcpClient client = new ModbusSupport.ModbusTcpClient(cfg.ip, cfg.port)) {
            return readDiRows(client, cfg, diTagList);
        }
    }

    public static PlcAiReadData readAiData(PlcConfig cfg, List<PlcAiMapEntry> mapList) throws Exception {
        try (ModbusSupport.ModbusTcpClient client = new ModbusSupport.ModbusTcpClient(cfg.ip, cfg.port)) {
            return readAiRows(client, cfg, mapList);
        }
    }

    public static PlcDiReadData readDiRows(ModbusSupport.ModbusTcpClient client, PlcConfig cfg, List<PlcDiTagEntry> diTagList) throws Exception {
        ModbusReadSupport.DiReadResult result = ModbusReadSupport.readDiRows(client, cfg.unitId, diTagList);
        return new PlcDiReadData(result.rows, result.durationMs);
    }

    public static PlcAiReadData readAiRows(ModbusSupport.ModbusTcpClient client, PlcConfig cfg, List<PlcAiMapEntry> mapList) throws Exception {
        ModbusReadSupport.AiReadResult result = ModbusReadSupport.readAiRows(client, cfg.unitId, mapList);
        return new PlcAiReadData(result.rows, result.meterRead, result.totalFloat, result.durationMs);
    }
}
