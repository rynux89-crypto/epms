package epms.util;

import epms.plc.PlcAiMapEntry;
import epms.plc.PlcAiReadRow;
import epms.plc.PlcDiTagEntry;
import epms.plc.PlcDiReadRow;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class ModbusReadSupport {
    public static final class DiReadResult {
        public final List<PlcDiReadRow> rows;
        public final long durationMs;

        public DiReadResult(List<PlcDiReadRow> rows, long durationMs) {
            this.rows = rows;
            this.durationMs = durationMs;
        }
    }

    public static final class AiReadResult {
        public final List<PlcAiReadRow> rows;
        public final int meterRead;
        public final int totalFloat;
        public final long durationMs;

        public AiReadResult(List<PlcAiReadRow> rows, int meterRead, int totalFloat, long durationMs) {
            this.rows = rows;
            this.meterRead = meterRead;
            this.totalFloat = totalFloat;
            this.durationMs = durationMs;
        }
    }

    private static final class AiRange {
        final int startReg;
        int endReg;
        byte[] regs;

        AiRange(int startReg, int endReg) {
            this.startReg = startReg;
            this.endReg = endReg;
        }
    }

    private ModbusReadSupport() {
    }

    public static int toPlcBitIndex(int configuredBitNo) {
        if (configuredBitNo >= 1 && configuredBitNo <= 16) {
            return configuredBitNo - 1;
        }
        if (configuredBitNo >= 0 && configuredBitNo <= 15) {
            return configuredBitNo;
        }
        return configuredBitNo;
    }

    public static float decodeFloatFrom2Regs(byte a, byte b, byte c, byte d, String byteOrder) {
        byte[] x = new byte[4];
        String bo = (byteOrder == null) ? "ABCD" : byteOrder.trim().toUpperCase(Locale.ROOT);
        if ("BADC".equals(bo)) {
            x[0] = b;
            x[1] = a;
            x[2] = d;
            x[3] = c;
        } else if ("CDAB".equals(bo)) {
            x[0] = c;
            x[1] = d;
            x[2] = a;
            x[3] = b;
        } else if ("DCBA".equals(bo)) {
            x[0] = d;
            x[1] = c;
            x[2] = b;
            x[3] = a;
        } else {
            x[0] = a;
            x[1] = b;
            x[2] = c;
            x[3] = d;
        }
        int bits = ((x[0] & 0xFF) << 24) | ((x[1] & 0xFF) << 16) | ((x[2] & 0xFF) << 8) | (x[3] & 0xFF);
        return Float.intBitsToFloat(bits);
    }

    public static DiReadResult readDiRows(ModbusSupport.ModbusTcpClient client, int unitId, List<PlcDiTagEntry> diTagList) throws Exception {
        long t0 = System.currentTimeMillis();
        List<PlcDiReadRow> out = new ArrayList<>();
        if (diTagList == null || diTagList.isEmpty()) {
            return new DiReadResult(out, Math.max(0L, System.currentTimeMillis() - t0));
        }

        int minAddr = Integer.MAX_VALUE;
        int maxAddr = Integer.MIN_VALUE;
        for (PlcDiTagEntry t : diTagList) {
            int diAddress = t.diAddress;
            if (diAddress < minAddr) minAddr = diAddress;
            if (diAddress > maxAddr) maxAddr = diAddress;
        }

        int regCount = maxAddr - minAddr + 1;
        if (regCount <= 0) {
            return new DiReadResult(out, Math.max(0L, System.currentTimeMillis() - t0));
        }

        byte[] regs = ModbusSupport.readHoldingRegisters(client, unitId, ModbusSupport.toModbusOffset(minAddr), regCount);

        int diSeq = 1;
        for (PlcDiTagEntry t : diTagList) {
            int pointId = t.pointId;
            int diAddress = t.diAddress;
            int bitNo = t.bitNo;
            int plcBitNo = toPlcBitIndex(bitNo);
            String tagName = t.tagName;
            String itemName = t.itemName;
            String panelName = t.panelName;
            int word = 0;
            int wordIdx = diAddress - minAddr;
            int byteIdx = wordIdx * 2;
            if (byteIdx >= 0 && (byteIdx + 1) < regs.length) {
                word = ModbusSupport.toU16(regs[byteIdx], regs[byteIdx + 1]);
            }
            int bitVal = ((plcBitNo >= 0 && plcBitNo <= 15) && (((word >> plcBitNo) & 0x1) == 1)) ? 1 : 0;

            out.add(new PlcDiReadRow(diSeq++, pointId, diAddress, bitNo, tagName, itemName, panelName, bitVal));
        }
        return new DiReadResult(out, Math.max(0L, System.currentTimeMillis() - t0));
    }

    public static AiReadResult readAiRows(ModbusSupport.ModbusTcpClient client, int unitId, List<PlcAiMapEntry> mapList) throws Exception {
        long t0 = System.currentTimeMillis();
        if (mapList == null || mapList.isEmpty()) {
            throw new Exception("No enabled AI mapping found for this PLC.");
        }

        List<PlcAiReadRow> out = new ArrayList<>();
        final int aiMergeGapRegs = 8;
        final int aiMergeMaxRegs = 480;
        Map<Integer, List<AiRange>> aiRangesByMeter = new HashMap<>();
        for (PlcAiMapEntry m : mapList) {
            int meterId = m.meterId;
            int startAddress = m.startAddress;
            int floatCount = m.floatCount;
            if (floatCount <= 0) continue;
            int rowStart = startAddress;
            int rowEnd = startAddress + (floatCount * 2) - 1;

            List<AiRange> ranges = aiRangesByMeter.computeIfAbsent(meterId, k -> new ArrayList<>());
            if (ranges.isEmpty()) {
                ranges.add(new AiRange(rowStart, rowEnd));
                continue;
            }
            AiRange last = ranges.get(ranges.size() - 1);
            int mergedEnd = Math.max(last.endReg, rowEnd);
            int mergedLen = mergedEnd - last.startReg + 1;
            if (rowStart <= (last.endReg + 1 + aiMergeGapRegs) && mergedLen <= aiMergeMaxRegs) {
                last.endReg = mergedEnd;
            } else {
                ranges.add(new AiRange(rowStart, rowEnd));
            }
        }

        for (List<AiRange> ranges : aiRangesByMeter.values()) {
            for (AiRange r : ranges) {
                int startOffset = ModbusSupport.toModbusOffset(r.startReg);
                int registerCount = r.endReg - r.startReg + 1;
                r.regs = ModbusSupport.readHoldingRegisters(client, unitId, startOffset, registerCount);
            }
        }

        int totalFloat = 0;
        int seq = 1;
        Set<Integer> metersRead = new HashSet<>();
        for (PlcAiMapEntry m : mapList) {
            int meterId = m.meterId;
            int startAddress = m.startAddress;
            int floatCount = m.floatCount;
            String byteOrder = m.byteOrder;
            if (floatCount <= 0) continue;

            metersRead.add(meterId);
            byte[] srcRegs = null;
            int baseByteOff = 0;
            List<AiRange> ranges = aiRangesByMeter.get(meterId);
            if (ranges != null) {
                for (AiRange r : ranges) {
                    int rowEnd = startAddress + (floatCount * 2) - 1;
                    if (startAddress >= r.startReg && rowEnd <= r.endReg) {
                        baseByteOff = (startAddress - r.startReg) * 2;
                        srcRegs = r.regs;
                        break;
                    }
                }
            }
            if (srcRegs == null) {
                int startOffset = ModbusSupport.toModbusOffset(startAddress);
                srcRegs = ModbusSupport.readHoldingRegisters(client, unitId, startOffset, floatCount * 2);
                baseByteOff = 0;
            }
            String[] tokens = m.tokens;
            if (tokens == null) tokens = new String[0];
            for (int i = 0; i < floatCount; i++) {
                int b = baseByteOff + (i * 4);
                float v = decodeFloatFrom2Regs(srcRegs[b], srcRegs[b + 1], srcRegs[b + 2], srcRegs[b + 3], byteOrder);
                out.add(new PlcAiReadRow(
                        seq++,
                        meterId,
                        i + 1,
                        i < tokens.length ? tokens[i] : ("F" + (i + 1)),
                        startAddress + (i * 2),
                        startAddress + (i * 2) + 1,
                        byteOrder,
                        v
                ));
            }
            totalFloat += floatCount;
        }
        return new AiReadResult(out, metersRead.size(), totalFloat, Math.max(0L, System.currentTimeMillis() - t0));
    }
}
