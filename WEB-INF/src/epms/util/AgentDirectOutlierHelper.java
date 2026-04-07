package epms.util;

import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentDirectOutlierHelper {
    private AgentDirectOutlierHelper() {
    }

    public static AgentRuntimeModels.DirectAnswerResult powerFactorOutlier(String dbContext, int noSignalCount) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = buildPowerFactorOutlierAnswer(dbContext, noSignalCount);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult frequencyOutlier(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = buildFrequencyOutlierAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult voltageUnbalanceTop(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = buildVoltageUnbalanceTopAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult harmonicExceed(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = dbContext;
        result.answer = buildHarmonicExceedAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult currentUnbalanceCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = "";
        result.answer = buildCurrentUnbalanceCountAnswer(dbContext);
        return result;
    }

    public static AgentRuntimeModels.DirectAnswerResult harmonicExceedCount(String dbContext) {
        AgentRuntimeModels.DirectAnswerResult result = new AgentRuntimeModels.DirectAnswerResult();
        result.dbContext = "";
        result.answer = buildHarmonicExceedCountAnswer(dbContext);
        return result;
    }

    private static String buildPowerFactorOutlierAnswer(String ctx, int noSignalCount) {
        if (ctx == null || ctx.trim().isEmpty()) return "역률 이상 데이터를 찾지 못했습니다.";
        if (ctx.contains("unavailable")) return "역률 이상 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("none") || ctx.contains("no data")) {
            if (noSignalCount >= 0) return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다. (신호없음 " + noSignalCount + "개 별도)";
            return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다.";
        }

        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*pf=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        ArrayList<String> items = new ArrayList<String>();
        while (row.find()) {
            String meterId = EpmsWebUtil.trimToNull(row.group(1));
            String meterName = EpmsWebUtil.trimToNull(row.group(2));
            String panel = EpmsWebUtil.trimToNull(row.group(3));
            String pf = EpmsWebUtil.trimToNull(row.group(4));
            String ts = EpmsWebUtil.trimToNull(row.group(5));
            if (meterId == null || meterName == null || pf == null) continue;
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
            item += " / PF " + pf;
            if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) {
            if (noSignalCount >= 0) return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다. (신호없음 " + noSignalCount + "개 별도)";
            return "역률 이상(유효신호 기준, 임계 미만) 계측기가 없습니다.";
        }
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("역률 이상 계측기 목록입니다.\n");
        else out.append(period).append(" 역률 이상 계측기 목록입니다.\n");
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) out.append("\n");
        }
        if (noSignalCount >= 0) {
            out.append("\n\n메타 정보:\n- 신호없음 별도 계측기: ").append(noSignalCount).append("개");
        }
        return out.toString();
    }

    private static String buildFrequencyOutlierAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "주파수 이상치 데이터를 찾지 못했습니다.";
        if (ctx.contains("unavailable")) return "주파수 이상치 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("none") || ctx.contains("no data")) return "주파수 이상치가 없습니다.";

        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*Hz=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        ArrayList<String> items = new ArrayList<String>();
        while (row.find()) {
            String meterId = EpmsWebUtil.trimToNull(row.group(1));
            String meterName = EpmsWebUtil.trimToNull(row.group(2));
            String panel = EpmsWebUtil.trimToNull(row.group(3));
            String hz = EpmsWebUtil.trimToNull(row.group(4));
            String ts = EpmsWebUtil.trimToNull(row.group(5));
            if (meterId == null || meterName == null || hz == null) continue;
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
            item += " / " + hz + "Hz";
            if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) return "주파수 이상치가 없습니다.";
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("주파수 이상치 목록입니다.\n");
        else out.append(period).append(" 주파수 이상치 목록입니다.\n");
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) out.append("\n");
        }
        return out.toString();
    }

    private static String buildVoltageUnbalanceTopAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "전압 불평형 상위 데이터를 찾지 못했습니다.";
        if (ctx.contains("unavailable")) return "전압 불평형 상위를 현재 조회할 수 없습니다.";
        if (ctx.contains("no data")) return "전압 불평형 데이터가 없습니다.";

        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*unb=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String meterId = EpmsWebUtil.trimToNull(row.group(1));
            String meterName = EpmsWebUtil.trimToNull(row.group(2));
            String unb = EpmsWebUtil.trimToNull(row.group(3));
            String ts = EpmsWebUtil.trimToNull(row.group(4));
            if (meterId == null || meterName == null || unb == null) continue;
            String item = meterName + "(" + meterId + ") " + unb + "%";
            if (ts != null && !ts.isEmpty()) item += " @ " + clip(ts, 19);
            parts.add(item);
        }
        if (parts.isEmpty()) return "전압 불평형 데이터가 없습니다.";
        String prefix = (period == null || period.isEmpty()) ? "전압 불평형 상위는 " : (period + " 전압 불평형 상위는 ");
        return prefix + String.join(" / ", parts) + "입니다.";
    }

    private static String buildHarmonicExceedAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "고조파 이상 데이터를 찾지 못했습니다.";
        if (ctx.contains("unavailable")) return "고조파 이상 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("none") || ctx.contains("no data")) return "고조파 이상 계측기가 없습니다.";

        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),(?:\\s*panel=([^,;]*),)?\\s*t=([^,;]+),\\s*TV=([0-9./\\-]+),\\s*TI=([0-9./\\-]+);").matcher(ctx);
        ArrayList<String> items = new ArrayList<String>();
        while (row.find()) {
            String meterId = EpmsWebUtil.trimToNull(row.group(1));
            String meterName = EpmsWebUtil.trimToNull(row.group(2));
            String panel = EpmsWebUtil.trimToNull(row.group(3));
            String ts = EpmsWebUtil.trimToNull(row.group(4));
            String thdV = EpmsWebUtil.trimToNull(row.group(5));
            String thdI = EpmsWebUtil.trimToNull(row.group(6));
            if (meterId == null || meterName == null) continue;
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
            item += " / THD_V " + thdV + " / THD_I " + thdI;
            if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) return "고조파 이상 계측기가 없습니다.";
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("고조파 이상 계측기 목록입니다.\n");
        else out.append(period).append(" 고조파 이상 계측기 목록입니다.\n");
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) out.append("\n");
        }
        return out.toString();
    }

    private static String buildCurrentUnbalanceCountAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "전류 불평형 계측기 수를 찾지 못했습니다.";
        if (ctx.contains("unavailable")) return "전류 불평형 계측기 수를 현재 조회할 수 없습니다.";
        Matcher thresholdMatcher = Pattern.compile("threshold=([0-9.\\-]+)").matcher(ctx);
        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        Matcher countMatcher = Pattern.compile("count=([0-9]+)").matcher(ctx);
        String threshold = thresholdMatcher.find() ? EpmsWebUtil.trimToNull(thresholdMatcher.group(1)) : "10.00";
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        String count = countMatcher.find() ? EpmsWebUtil.trimToNull(countMatcher.group(1)) : "0";
        if (period == null || period.isEmpty()) {
            return "전류 불평형 " + threshold + "% 초과 계측기는 총 " + count + "개입니다.";
        }
        return period + " 기준 전류 불평형 " + threshold + "% 초과 계측기는 총 " + count + "개입니다.";
    }

    private static String buildHarmonicExceedCountAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "고조파 이상 건수를 찾지 못했습니다.";
        if (ctx.contains("unavailable")) return "고조파 이상 건수를 현재 조회할 수 없습니다.";
        if (ctx.contains("none") || ctx.contains("no data")) return "고조파 이상 계측기는 0개입니다.";
        Matcher periodMatcher = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = periodMatcher.find() ? EpmsWebUtil.trimToNull(periodMatcher.group(1)) : null;
        Matcher row = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        int count = 0;
        while (row.find()) count++;
        if (count <= 0) return "고조파 이상 계측기는 0개입니다.";
        if (period == null || period.isEmpty()) return "고조파 이상 계측기는 총 " + count + "개입니다.";
        return period + " 고조파 이상 계측기는 총 " + count + "개입니다.";
    }

    private static String clip(String text, int max) {
        if (text == null) return null;
        return text.length() <= max ? text : text.substring(0, max);
    }
}
