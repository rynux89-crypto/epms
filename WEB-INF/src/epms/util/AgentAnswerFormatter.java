package epms.util;

import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AgentAnswerFormatter {
    private AgentAnswerFormatter() {
    }

    public static String buildFrequencyDirectAnswer(String frequencyCtx, Integer meterId, Integer month) {
        if (frequencyCtx == null || frequencyCtx.trim().isEmpty()) {
            return "\uc6d4 \ud3c9\uade0 \uc8fc\ud30c\uc218 \uc815\ubcf4\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        String ctx = frequencyCtx.trim();
        String period = "-";
        Matcher p = Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        if (p.find()) period = p.group(1);

        String subject = (meterId == null ? "\uc804\uccb4 \uacc4\uce21\uae30\uc758" : (meterId + "\ubc88 \uacc4\uce21\uae30\uc758"));
        if (ctx.contains("no data")) {
            return subject + " " + period + " \ud3c9\uade0 \uc8fc\ud30c\uc218 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        Matcher a = Pattern.compile("avg_hz=([0-9.\\-]+)").matcher(ctx);
        Matcher n = Pattern.compile("samples=([0-9]+)").matcher(ctx);
        Matcher mn = Pattern.compile("min_hz=([0-9.\\-]+)").matcher(ctx);
        Matcher mx = Pattern.compile("max_hz=([0-9.\\-]+)").matcher(ctx);
        String avg = a.find() ? a.group(1) : "-";
        String samples = n.find() ? n.group(1) : "-";
        String min = mn.find() ? mn.group(1) : "-";
        String max = mx.find() ? mx.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(subject).append(" ").append(period).append(" \ud3c9\uade0 \uc8fc\ud30c\uc218\uc785\ub2c8\ub2e4.\n\n")
            .append("\ud575\uc2ec \uac12:\n")
            .append("- \ud3c9\uade0 \uc8fc\ud30c\uc218: ").append(avg).append("Hz\n")
            .append("- \ucd5c\uc18c: ").append(min).append("Hz\n")
            .append("- \ucd5c\ub300: ").append(max).append("Hz\n")
            .append("- \uc0d8\ud50c \uc218: ").append(samples);
        return out.toString();
    }

    public static String buildPowerValueDirectAnswer(String meterCtx, boolean reactive) {
        if (meterCtx == null || meterCtx.trim().isEmpty()) {
            return reactive ? "\ubb34\ud6a8\uc804\ub825 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4." : "\uc720\ud6a8\uc804\ub825 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        if (meterCtx.contains("unavailable")) {
            return reactive ? "\ubb34\ud6a8\uc804\ub825\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc720\ud6a8\uc804\ub825\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        if (meterCtx.contains("no data")) {
            return reactive ? "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \ubb34\ud6a8\uc804\ub825 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \uc720\ud6a8\uc804\ub825 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(meterCtx);
        Matcher mn = Pattern.compile("meter_id=[0-9]+,\\s*([^,;]+),").matcher(meterCtx);
        Matcher ts = Pattern.compile("@\\s*([0-9\\-:\\s]+)\\s*V=").matcher(meterCtx);
        Matcher kw = Pattern.compile("kW=([0-9.\\-]+)").matcher(meterCtx);
        Matcher kvar = Pattern.compile("kVAr=([0-9.\\-]+)").matcher(meterCtx);
        String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
        String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
        String time = ts.find() ? trimToNull(ts.group(1)) : null;
        String value = reactive ? (kvar.find() ? trimToNull(kvar.group(1)) : null) : (kw.find() ? trimToNull(kw.group(1)) : null);
        if (meterId == null || value == null) {
            return reactive ? "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \ubb34\ud6a8\uc804\ub825 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \uc720\ud6a8\uc804\ub825 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        String label = meterId + "\ubc88 \uacc4\uce21\uae30";
        if (meterName != null && !meterName.isEmpty() && !"-".equals(meterName)) label += "(" + meterName + ")";
        String unit = reactive ? "kVAr" : "kW";
        String subject = reactive ? "\ubb34\ud6a8\uc804\ub825" : "\uc720\ud6a8\uc804\ub825";
        StringBuilder out = new StringBuilder();
        out.append(label).append(" ").append(subject).append(" \uc870\ud68c \uacb0\uacfc\uc785\ub2c8\ub2e4.\n\n")
            .append("\ud575\uc2ec \uac12:\n")
            .append("- ").append(subject).append(": ").append(value).append(unit);
        if (time != null && !time.isEmpty()) {
            out.append("\n\n\uba54\ud0c0 \uc815\ubcf4:\n")
                .append("- \uce21\uc815 \uc2dc\uac01: ").append(clip(time, 19));
        }
        return out.toString();
    }

    public static String buildEnergyValueDirectAnswer(String energyCtx, boolean reactive) {
        if (energyCtx == null || energyCtx.trim().isEmpty()) {
            return reactive ? "\ubb34\ud6a8\uc804\ub825\ub7c9 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4." : "\uc804\ub825\ub7c9 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        if (energyCtx.contains("unavailable")) {
            return reactive ? "\ubb34\ud6a8\uc804\ub825\ub7c9\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc804\ub825\ub7c9\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        if (energyCtx.contains("no data")) {
            return reactive ? "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \ubb34\ud6a8\uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(energyCtx);
        Matcher mn = Pattern.compile("meter_id=[0-9]+,\\s*([^,;]+),").matcher(energyCtx);
        Matcher ts = Pattern.compile("t=([0-9\\-:\\s]+)").matcher(energyCtx);
        Matcher kwh = Pattern.compile("kWh=([0-9.\\-]+)").matcher(energyCtx);
        Matcher kvarh = Pattern.compile("kVArh=([0-9.\\-]+)").matcher(energyCtx);
        String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
        String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
        String time = ts.find() ? trimToNull(ts.group(1)) : null;
        String value = reactive ? (kvarh.find() ? trimToNull(kvarh.group(1)) : null) : (kwh.find() ? trimToNull(kwh.group(1)) : null);
        if (meterId == null || value == null) {
            return reactive ? "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \ubb34\ud6a8\uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc694\uccad\ud55c \uacc4\uce21\uae30\uc758 \uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        String label = meterId + "\ubc88 \uacc4\uce21\uae30";
        if (meterName != null && !meterName.isEmpty() && !"-".equals(meterName)) label += "(" + meterName + ")";
        String subject = reactive ? "\ubb34\ud6a8\uc804\ub825\ub7c9" : "\uc804\ub825\ub7c9";
        String unit = reactive ? "kVArh" : "kWh";
        StringBuilder out = new StringBuilder();
        out.append(label).append(" ").append(subject).append(" \uc870\ud68c \uacb0\uacfc\uc785\ub2c8\ub2e4.\n\n")
            .append("\ud575\uc2ec \uac12:\n")
            .append("- ").append(subject).append(": ").append(value).append(unit);
        if (time != null && !time.isEmpty()) {
            out.append("\n\n\uba54\ud0c0 \uc815\ubcf4:\n")
                .append("- \uce21\uc815 \uc2dc\uac01: ").append(clip(time, 19));
        }
        return out.toString();
    }

    public static String buildEnergyDeltaDirectAnswer(String ctx, boolean reactive) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return reactive ? "\ubb34\ud6a8\uc804\ub825\ub7c9 \uc99d\uac00 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4." : "\uc804\ub825\ub7c9 \uc99d\uac00 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("unavailable")) {
            return reactive ? "\ubb34\ud6a8\uc804\ub825\ub7c9 \uc99d\uac00\ub7c9\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc804\ub825\ub7c9 \uc99d\uac00\ub7c9\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        if (ctx.contains("meter_id required")) return "\uacc4\uce21\uae30\ub97c \uc9c0\uc815\ud574 \uc8fc\uc138\uc694.";
        if (ctx.contains("period required")) return "\uae30\uac04\uc744 \uc9c0\uc815\ud574 \uc8fc\uc138\uc694.";
        if (ctx.contains("no data")) {
            return reactive ? "\uc694\uccad\ud55c \uae30\uac04\uc758 \ubb34\ud6a8\uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc694\uccad\ud55c \uae30\uac04\uc758 \uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        Matcher mn = Pattern.compile("meter=([^,]+)").matcher(ctx);
        Matcher pm = Pattern.compile("period=([^,]+)").matcher(ctx);
        Matcher dm = Pattern.compile("delta=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
        String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        String delta = dm.find() ? trimToNull(dm.group(1)) : null;
        if (meterId == null || delta == null) {
            return reactive ? "\uc694\uccad\ud55c \uae30\uac04\uc758 \ubb34\ud6a8\uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4." : "\uc694\uccad\ud55c \uae30\uac04\uc758 \uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        String label = meterId + "\ubc88 \uacc4\uce21\uae30";
        if (meterName != null && !meterName.isEmpty() && !"-".equals(meterName)) label += "(" + meterName + ")";
        String subject = reactive ? "\ubb34\ud6a8\uc804\ub825\ub7c9 \uc99d\uac00\ub7c9" : "\uc804\ub825\ub7c9 \uc99d\uac00\ub7c9";
        String unit = reactive ? "kVArh" : "kWh";
        String periodText = (period == null || period.isEmpty() || "-".equals(period)) ? "\uc9c0\uc815 \uae30\uac04" : period;
        return label + " " + periodText + " " + subject + " \uc870\ud68c \uacb0\uacfc\uc785\ub2c8\ub2e4.\n\n"
            + "\ud575\uc2ec \uac12:\n- " + subject + ": " + delta + unit;
    }

    public static String buildAlarmSeverityDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        Matcher dm = Pattern.compile("days=([0-9]+)").matcher(ctx);
        String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
        String daysLabel = dm.find() ? dm.group(1) : null;
        Matcher row = Pattern.compile("(?:^|;)\\s*([^=;\\[\\]]+)=([0-9]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String sev = trimToNull(row.group(1));
            String cnt = trimToNull(row.group(2));
            if (sev == null || cnt == null) continue;
            if ("days".equalsIgnoreCase(sev) || "count".equalsIgnoreCase(sev) || "period".equalsIgnoreCase(sev)) continue;
            parts.add(sev + " " + cnt + "\uac74");
        }
        if (parts.isEmpty()) return "\uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        if (periodLabel != null && !periodLabel.isEmpty()) {
            out.append(periodLabel).append(" \uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4\uc785\ub2c8\ub2e4.\n");
        } else if (daysLabel != null && !daysLabel.isEmpty()) {
            out.append("\ucd5c\uadfc ").append(daysLabel).append("\uc77c \uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4\uc785\ub2c8\ub2e4.\n");
        } else {
            out.append("\uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c \uc9d1\uacc4\uc785\ub2c8\ub2e4.\n");
        }
        for (int i = 0; i < parts.size(); i++) {
            out.append("- ").append(parts.get(i));
            if (i + 1 < parts.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildAlarmTypeDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc54c\ub78c \uc885\ub958\ubcc4 \uc9d1\uacc4 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc54c\ub78c \uc885\ub958\ubcc4 \uc9d1\uacc4\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\uc54c\ub78c \uc885\ub958\ubcc4 \uc9d1\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        Matcher dm = Pattern.compile("days=([0-9]+)").matcher(ctx);
        Matcher sm = Pattern.compile("scope=([^;]+)").matcher(ctx);
        String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
        String daysLabel = dm.find() ? trimToNull(dm.group(1)) : null;
        String scopeLabel = sm.find() ? trimToNull(sm.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^=;]+)=([0-9]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String type = trimToNull(row.group(1));
            String cnt = trimToNull(row.group(2));
            if (type == null || cnt == null) continue;
            parts.add(type + " " + cnt + "\uac74");
        }
        if (parts.isEmpty()) return "\uc54c\ub78c \uc885\ub958\ubcc4 \uc9d1\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        if (periodLabel != null && !periodLabel.isEmpty()) {
            out.append(periodLabel).append(" ");
        } else if (daysLabel != null && !daysLabel.isEmpty()) {
            out.append("\ucd5c\uadfc ").append(daysLabel).append("\uc77c ");
        }
        out.append("trip".equalsIgnoreCase(scopeLabel) ? "TRIP \uc54c\ub78c \uc885\ub958\ubcc4 \uc9d1\uacc4\uc785\ub2c8\ub2e4.\n" : "\uc54c\ub78c \uc885\ub958\ubcc4 \uc9d1\uacc4\uc785\ub2c8\ub2e4.\n");
        for (int i = 0; i < parts.size(); i++) {
            out.append("- ").append(parts.get(i));
            if (i + 1 < parts.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildAlarmMeterTopDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uacc4\uce21\uae30\ubcc4 \uc54c\ub78c \uc9d1\uacc4 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uacc4\uce21\uae30\ubcc4 \uc54c\ub78c \uc9d1\uacc4\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\uc870\uac74\uc5d0 \ub9de\ub294 \uacc4\uce21\uae30\ubcc4 \uc54c\ub78c \uc9d1\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        Matcher dm = Pattern.compile("days=([0-9]+)").matcher(ctx);
        String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
        String daysLabel = dm.find() ? trimToNull(dm.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^=;]+)=([0-9]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String meter = trimToNull(row.group(1));
            String cnt = trimToNull(row.group(2));
            if (meter == null || cnt == null) continue;
            parts.add(meter + " - " + cnt + "\uac74");
        }
        if (parts.isEmpty()) return "\uc870\uac74\uc5d0 \ub9de\ub294 \uacc4\uce21\uae30\ubcc4 \uc54c\ub78c \uc9d1\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        StringBuilder out = new StringBuilder();
        if (periodLabel != null && !periodLabel.isEmpty()) {
            out.append(periodLabel).append(" \uc54c\ub78c \ubc1c\uc0dd \uac74\uc218\uac00 \ub9ce\uc740 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        } else if (daysLabel != null && !daysLabel.isEmpty()) {
            out.append("\ucd5c\uadfc ").append(daysLabel).append("\uc77c \uc54c\ub78c \ubc1c\uc0dd \uac74\uc218\uac00 \ub9ce\uc740 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        } else {
            out.append("\uc54c\ub78c \ubc1c\uc0dd \uac74\uc218\uac00 \ub9ce\uc740 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        }
        for (int i = 0; i < parts.size(); i++) {
            out.append(i + 1).append(". ").append(parts.get(i));
            if (i + 1 < parts.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildUsageTypeListDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc6a9\ub3c4 \ubaa9\ub85d \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc6a9\ub3c4 \ubaa9\ub85d\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\ub4f1\ub85d\ub41c \uc6a9\ub3c4 \ubaa9\ub85d\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^;]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String usage = trimToNull(row.group(1));
            if (usage == null) continue;
            parts.add(usage);
        }
        if (parts.isEmpty()) return "\ub4f1\ub85d\ub41c \uc6a9\ub3c4 \ubaa9\ub85d\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        out.append("\ub4f1\ub85d\ub41c \uc6a9\ub3c4 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        for (int i = 0; i < parts.size(); i++) {
            out.append("- ").append(parts.get(i));
            if (i + 1 < parts.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildBuildingPowerTopDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uac74\ubb3c\ubcc4 \uc804\ub825 TOP \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uac74\ubb3c\ubcc4 \uc804\ub825 TOP\uc744 \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\uac74\ubb3c\ubcc4 \uc804\ub825 TOP \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher pm = Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        String period = pm.find() ? pm.group(1) : "-";
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^:;]+):\\s*avg_kw=([0-9.\\-]+),\\s*sum_kwh=([0-9.\\-]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String building = trimToNull(row.group(1));
            String avgKw = trimToNull(row.group(2));
            String sumKwh = trimToNull(row.group(3));
            if (building == null || avgKw == null || sumKwh == null) continue;
            parts.add(building + " \ud3c9\uade0\uc804\ub825 " + avgKw + "kW, \ub204\uc801 " + sumKwh + "kWh");
        }
        if (parts.isEmpty()) return "\uac74\ubb3c\ubcc4 \uc804\ub825 TOP \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        return period + " \uac74\ubb3c\ubcc4 \uc804\ub825 TOP\uc740 " + String.join(" / ", parts) + "\uc785\ub2c8\ub2e4.";
    }

    public static String buildVoltageUnbalanceTopDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc804\uc555 \ubd88\ud3c9\ud615 \uc0c1\uc704 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc804\uc555 \ubd88\ud3c9\ud615 \uc0c1\uc704\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\uc804\uc555 \ubd88\ud3c9\ud615 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        ArrayList<String> parts = new ArrayList<String>();
        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*unb=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        while (row.find()) {
            String meterId = trimToNull(row.group(1));
            String meterName = trimToNull(row.group(2));
            String unb = trimToNull(row.group(3));
            String ts = trimToNull(row.group(4));
            if (meterId == null || meterName == null || unb == null) continue;
            String item = meterName + "(" + meterId + ") " + unb + "%";
            if (ts != null && !ts.isEmpty()) item += " @ " + clip(ts, 19);
            parts.add(item);
        }
        if (parts.isEmpty()) return "\uc804\uc555 \ubd88\ud3c9\ud615 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("\uc804\uc555 \ubd88\ud3c9\ud615 \uc0c1\uc704 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        else out.append(period).append(" \uc804\uc555 \ubd88\ud3c9\ud615 \uc0c1\uc704 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        for (int i = 0; i < parts.size(); i++) {
            out.append("- ").append(parts.get(i).replace(" @ ", " / "));
            if (i + 1 < parts.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildHarmonicExceedDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uace0\uc870\ud30c \uc774\uc0c1 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uace0\uc870\ud30c \uc774\uc0c1 \ub370\uc774\ud130\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("none") || ctx.contains("no data")) return "\uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        ArrayList<String> items = new ArrayList<String>();
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),(?:\\s*panel=([^,;]*),)?\\s*t=([^,;]+),\\s*TV=([0-9./\\-]+),\\s*TI=([0-9./\\-]+);").matcher(ctx);
        while (row.find()) {
            String meterId = trimToNull(row.group(1));
            String meterName = trimToNull(row.group(2));
            String panel = trimToNull(row.group(3));
            String ts = trimToNull(row.group(4));
            String thdV = trimToNull(row.group(5));
            String thdI = trimToNull(row.group(6));
            if (meterId == null || meterName == null) continue;
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
            if (thdV != null) item += " / THD_V " + thdV;
            if (thdI != null) item += " / THD_I " + thdI;
            if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) return "\uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("\uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        else out.append(period).append(" \uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildPowerFactorOutlierDirectAnswer(String ctx, int noSignalCount) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc5ed\ub960 \uc774\uc0c1 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc5ed\ub960 \uc774\uc0c1 \ub370\uc774\ud130\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("none") || ctx.contains("no data")) {
            return noSignalCount >= 0
                ? "\uc5ed\ub960 \uc774\uc0c1(\uc720\ud6a8\uc2e0\ud638 \uae30\uc900, \uc784\uacc4 \ubbf8\ub9cc) \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4. (\uc2e0\ud638\uc5c6\uc74c " + noSignalCount + "\uac1c \ubcc4\ub3c4)"
                : "\uc5ed\ub960 \uc774\uc0c1(\uc720\ud6a8\uc2e0\ud638 \uae30\uc900, \uc784\uacc4 \ubbf8\ub9cc) \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        ArrayList<String> items = new ArrayList<String>();
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*),\\s*pf=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        while (row.find()) {
            String meterId = trimToNull(row.group(1));
            String meterName = trimToNull(row.group(2));
            String panel = trimToNull(row.group(3));
            String pf = trimToNull(row.group(4));
            String ts = trimToNull(row.group(5));
            if (meterId == null || meterName == null || pf == null) continue;
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
            item += " / PF " + pf;
            if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) {
            return noSignalCount >= 0
                ? "\uc5ed\ub960 \uc774\uc0c1(\uc720\ud6a8\uc2e0\ud638 \uae30\uc900, \uc784\uacc4 \ubbf8\ub9cc) \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4. (\uc2e0\ud638\uc5c6\uc74c " + noSignalCount + "\uac1c \ubcc4\ub3c4)"
                : "\uc5ed\ub960 \uc774\uc0c1(\uc720\ud6a8\uc2e0\ud638 \uae30\uc900, \uc784\uacc4 \ubbf8\ub9cc) \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("\uc5ed\ub960 \uc774\uc0c1 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        else out.append(period).append(" \uc5ed\ub960 \uc774\uc0c1 \uacc4\uce21\uae30 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) out.append("\n");
        }
        if (noSignalCount >= 0) {
            out.append("\n\n\uba54\ud0c0 \uc815\ubcf4:\n- \uc2e0\ud638\uc5c6\uc74c \ubcc4\ub3c4 \uacc4\uce21\uae30: ").append(noSignalCount).append("\uac1c");
        }
        return out.toString();
    }

    public static String buildFrequencyOutlierDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58 \ub370\uc774\ud130\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("none") || ctx.contains("no data")) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        ArrayList<String> items = new ArrayList<String>();
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+)(?:,\\s*panel=([^,;]*))?,\\s*Hz=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        while (row.find()) {
            String meterId = trimToNull(row.group(1));
            String meterName = trimToNull(row.group(2));
            String panel = trimToNull(row.group(3));
            String hz = trimToNull(row.group(4));
            String ts = trimToNull(row.group(5));
            if (meterId == null || meterName == null || hz == null) continue;
            String item = meterName + "(" + meterId + ")";
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " / " + panel;
            item += " / " + hz + "Hz";
            if (ts != null && !ts.isEmpty()) item += " / " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        if (period == null || period.isEmpty()) out.append("\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        else out.append(period).append(" \uc8fc\ud30c\uc218 \uc774\uc0c1\uce58 \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        for (int i = 0; i < items.size(); i++) {
            out.append("- ").append(items.get(i));
            if (i + 1 < items.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildMonthlyPowerStatsDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc6d4 \uc804\ub825 \ud1b5\uacc4 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc6d4 \uc804\ub825 \ud1b5\uacc4\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("meter_id required")) return "\uacc4\uce21\uae30\ub97c \uc9c0\uc815\ud574 \uc8fc\uc138\uc694.";
        if (ctx.contains("no data")) return "\uc694\uccad\ud55c \uc6d4 \uc804\ub825 \ud1b5\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        Matcher pm = Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        Matcher am = Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
        Matcher mm = Pattern.compile("max_kw=([0-9.\\-]+)").matcher(ctx);
        Matcher sm = Pattern.compile("samples=([0-9]+)").matcher(ctx);
        String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        String avgKw = am.find() ? trimToNull(am.group(1)) : null;
        String maxKw = mm.find() ? trimToNull(mm.group(1)) : null;
        String samples = sm.find() ? trimToNull(sm.group(1)) : null;
        if (meterId == null || period == null || avgKw == null || maxKw == null) return "\uc694\uccad\ud55c \uc6d4 \uc804\ub825 \ud1b5\uacc4 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("\ubc88 \uacc4\uce21\uae30 ").append(period).append(" \uc6d4 \uc804\ub825 \ud1b5\uacc4\uc785\ub2c8\ub2e4.\n\n")
            .append("\ud575\uc2ec \uac12:\n")
            .append("- \ud3c9\uade0\uc804\ub825: ").append(avgKw).append("kW\n")
            .append("- \ucd5c\ub300\uc804\ub825: ").append(maxKw).append("kW");
        if (samples != null && !samples.isEmpty()) {
            out.append("\n\n\uba54\ud0c0 \uc815\ubcf4:\n")
                .append("- \ud45c\ubcf8 \uc218: ").append(samples).append("\uac74");
        }
        return out.toString();
    }

    public static String buildMonthlyPeakPowerDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc6d4 \ucd5c\ub300 \ud53c\ud06c \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc6d4 \ucd5c\ub300 \ud53c\ud06c\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no data")) return "\uc694\uccad\ud55c \uc6d4 \ucd5c\ub300 \ud53c\ud06c \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher pm = Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        Matcher mn = Pattern.compile("meter_name=([^;]+)").matcher(ctx);
        Matcher pn = Pattern.compile("panel=([^;]+)").matcher(ctx);
        Matcher pk = Pattern.compile("peak_kw=([0-9.\\-]+)").matcher(ctx);
        Matcher tm = Pattern.compile("t=([^;]+)").matcher(ctx);
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        String meterId = mid.find() ? trimToNull(mid.group(1)) : null;
        String meterName = mn.find() ? trimToNull(mn.group(1)) : null;
        String panel = pn.find() ? trimToNull(pn.group(1)) : null;
        String peakKw = pk.find() ? trimToNull(pk.group(1)) : null;
        String measuredAt = tm.find() ? trimToNull(tm.group(1)) : null;
        if (period == null || peakKw == null) return "\uc694\uccad\ud55c \uc6d4 \ucd5c\ub300 \ud53c\ud06c \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        out.append(period).append(" \ucd5c\ub300 \ud53c\ud06c \uc804\ub825 \uc870\ud68c \uacb0\uacfc\uc785\ub2c8\ub2e4.\n\n");
        out.append("\ud575\uc2ec \uac12:\n");
        out.append("- \ucd5c\ub300 \ud53c\ud06c: ").append(peakKw).append("kW");
        if (meterId != null && meterName != null) {
            out.append("\n- \uacc4\uce21\uae30: ").append(meterName).append(" (").append(meterId).append(")");
        }
        if (panel != null && !panel.isEmpty() && !"-".equals(panel)) {
            out.append("\n- \ud328\ub110: ").append(panel);
        }
        if (measuredAt != null && !measuredAt.isEmpty()) {
            out.append("\n- \uc2dc\uac01: ").append(measuredAt);
        }
        return out.toString();
    }

    public static String buildLatestAlarmsDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\ucd5c\uadfc \uc54c\ub78c \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc54c\ub78c \ub370\uc774\ud130\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("no recent alarm")) return "\ucd5c\uadfc \uc54c\ub78c\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher um = Pattern.compile("unresolved=([0-9]+)").matcher(ctx);
        String unresolved = um.find() ? um.group(1) : null;
        ArrayList<String[]> rowsOut = new ArrayList<String[]>();
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^/;]+)/([^@;]+) @ ([^,;]+) t=([0-9\\-:\\s]+),\\s*cleared=([YN])(?:,\\s*desc=([^;]+))?;").matcher(ctx);
        while (row.find()) {
            String sev = trimToNull(row.group(1));
            String type = trimToNull(row.group(2));
            String meter = trimToNull(row.group(3));
            String ts = trimToNull(row.group(4));
            String cleared = trimToNull(row.group(5));
            String desc = trimToNull(row.group(6));
            if (type == null || meter == null) continue;
            rowsOut.add(new String[] {
                sev, type, meter, ts,
                "Y".equalsIgnoreCase(cleared) ? "\ud574\uacb0" : "\ubbf8\ud574\uacb0",
                shortenAlarmDescription(desc)
            });
        }
        if (rowsOut.isEmpty()) {
            return unresolved != null ? "\ucd5c\uadfc \uc54c\ub78c \uc694\uc57d\uc785\ub2c8\ub2e4. \ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c\uc740 " + unresolved + "\uac74\uc785\ub2c8\ub2e4." : "\ucd5c\uadfc \uc54c\ub78c\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        StringBuilder out = new StringBuilder();
        if (unresolved != null) {
            out.append("\ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c\uc740 ").append(unresolved).append("\uac74\uc785\ub2c8\ub2e4.\n\n");
        } else {
            out.append("\ucd5c\uadfc \uc54c\ub78c \uc694\uc57d\uc785\ub2c8\ub2e4.\n\n");
        }
        out.append("\ucd5c\uadfc \uc54c\ub78c:\n");
        int limit = Math.min(rowsOut.size(), 3);
        for (int i = 0; i < limit; i++) {
            String[] rowData = rowsOut.get(i);
            String sev = trimToNull(rowData[0]);
            String type = trimToNull(rowData[1]);
            String meter = trimToNull(rowData[2]);
            String ts = trimToNull(rowData[3]);
            String state = trimToNull(rowData[4]);
            String desc = trimToNull(rowData[5]);
            out.append("- ");
            if (sev != null && !sev.isEmpty()) out.append("[").append(sev).append("] ");
            out.append(type == null ? "-" : type);
            out.append(" / ").append(meter == null ? "-" : meter);
            if (ts != null && !ts.isEmpty()) out.append(" / ").append(clip(ts, 19));
            if (state != null && !state.isEmpty()) out.append(" / ").append(state);
            if (desc != null && !desc.isEmpty()) out.append(" / ").append(desc);
            if (i + 1 < limit) out.append("\n");
        }
        if (rowsOut.size() > limit) {
            out.append("\n\n\uadf8 \uc678 ").append(rowsOut.size() - limit).append("\uac74\uc758 \ucd5c\uadfc \uc54c\ub78c\uc774 \ub354 \uc788\uc2b5\ub2c8\ub2e4.");
        }
        return out.toString();
    }

    public static String buildOpenAlarmsDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc5f4\ub9b0 \uc54c\ub78c \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc5f4\ub9b0 \uc54c\ub78c \ub370\uc774\ud130\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("none")) return "\ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.";
        ArrayList<String[]> rowsOut = new ArrayList<String[]>();
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^/;]+)/([^@;]+) @ ([^,;]+),\\s*t=([0-9\\-:\\s]+),\\s*desc=([^;]+);").matcher(ctx);
        while (row.find()) {
            String sev = trimToNull(row.group(1));
            String type = trimToNull(row.group(2));
            String meter = trimToNull(row.group(3));
            String ts = trimToNull(row.group(4));
            String desc = trimToNull(row.group(5));
            if (type == null || meter == null) continue;
            rowsOut.add(new String[] { sev, type, meter, ts, "\ubbf8\ud574\uacb0", shortenAlarmDescription(desc) });
        }
        if (rowsOut.isEmpty()) return "\ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.";
        StringBuilder out = new StringBuilder();
        out.append("\ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c \ubaa9\ub85d\uc785\ub2c8\ub2e4.\n");
        int limit = Math.min(rowsOut.size(), 5);
        for (int i = 0; i < limit; i++) {
            String[] rowData = rowsOut.get(i);
            String sev = trimToNull(rowData[0]);
            String type = trimToNull(rowData[1]);
            String meter = trimToNull(rowData[2]);
            String ts = trimToNull(rowData[3]);
            String desc = trimToNull(rowData[5]);
            out.append("- ");
            if (sev != null && !sev.isEmpty()) out.append("[").append(sev).append("] ");
            out.append(type == null ? "-" : type);
            out.append(" / ").append(meter == null ? "-" : meter);
            if (ts != null && !ts.isEmpty()) out.append(" / ").append(clip(ts, 19));
            if (desc != null && !desc.isEmpty()) out.append(" / ").append(desc);
            if (i + 1 < limit) out.append("\n");
        }
        if (rowsOut.size() > limit) {
            out.append("\n\n\uadf8 \uc678 ").append(rowsOut.size() - limit).append("\uac74\uc758 \ubbf8\ud574\uacb0 \uc54c\ub78c\uc774 \ub354 \uc788\uc2b5\ub2c8\ub2e4.");
        }
        return out.toString();
    }

    public static String buildVoltageAverageDirectAnswer(String voltageCtx, Integer meterId) {
        if (voltageCtx == null || voltageCtx.trim().isEmpty()) return "\uae30\uac04 \ud3c9\uade0 \uc804\uc555 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (voltageCtx.contains("no data")) return "\uc694\uccad \uae30\uac04 \uc804\uc555 \ud3c9\uade0 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (voltageCtx.contains("unavailable")) return "\uc804\uc555 \ud3c9\uade0 \uc870\ud68c\ub97c \ud604\uc7ac \uc218\ud589\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        String period = null;
        Matcher p = Pattern.compile("period=([^;]+)").matcher(voltageCtx);
        if (p.find()) period = p.group(1);
        Matcher avg = Pattern.compile("avg_v=([0-9.\\-]+)").matcher(voltageCtx);
        Matcher mn = Pattern.compile("min_v=([0-9.\\-]+)").matcher(voltageCtx);
        Matcher mx = Pattern.compile("max_v=([0-9.\\-]+)").matcher(voltageCtx);
        Matcher sn = Pattern.compile("samples=([0-9]+)").matcher(voltageCtx);
        String a = avg.find() ? avg.group(1) : "-";
        String nmin = mn.find() ? mn.group(1) : "-";
        String nmax = mx.find() ? mx.group(1) : "-";
        String s = sn.find() ? sn.group(1) : "-";
        String scope = period == null ? "\uc9c0\uc815 \uae30\uac04" : period;
        if (meterId != null) {
            return "meter_id=" + meterId + "\uc758 " + scope + " \ud3c9\uade0 \uc804\uc555\uc740 " + a + "V \uc785\ub2c8\ub2e4. (\ucd5c\uc18c " + nmin + ", \ucd5c\ub300 " + nmax + ", \uc0d8\ud50c " + s + ")";
        }
        return scope + " \uc804\uc555 \ud3c9\uade0 \uc870\ud68c \uacb0\uacfc\uc785\ub2c8\ub2e4.";
    }

    public static String buildPerMeterPowerDirectAnswer(String powerCtx) {
        if (powerCtx == null || powerCtx.trim().isEmpty()) return "\uacc4\uce21\uae30\ubcc4 \uc804\ub825\ub7c9 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (powerCtx.contains("no data")) return "\uacc4\uce21\uae30\ubcc4 \uc804\ub825\ub7c9 \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (powerCtx.contains("unavailable")) return "\uacc4\uce21\uae30\ubcc4 \uc804\ub825\ub7c9 \uc870\ud68c\ub97c \ud604\uc7ac \uc218\ud589\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher m = Pattern.compile("total=([0-9]+)\\s+meters").matcher(powerCtx);
        if (m.find()) {
            return "\uac01 \uacc4\uce21\uae30\uc758 \ucd5c\uc2e0 \uc804\ub825\ub7c9\uc744 \uc870\ud68c\ud588\uc2b5\ub2c8\ub2e4. \ucd1d " + m.group(1) + "\uac1c \uacc4\uce21\uae30\uc774\uba70, \uc0c1\uc704 30\uac1c\ub97c \ud45c\uc2dc\ud569\ub2c8\ub2e4.";
        }
        return "\uac01 \uacc4\uce21\uae30\uc758 \ucd5c\uc2e0 \uc804\ub825\ub7c9(kW/kWh)\uc744 \uc870\ud68c\ud588\uc2b5\ub2c8\ub2e4.";
    }

    public static String buildHarmonicDirectAnswer(String harmonicCtx, Integer meterId) {
        if (harmonicCtx == null || harmonicCtx.trim().isEmpty()) return "\uace0\uc870\ud30c \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (harmonicCtx.contains("no data")) return (meterId == null ? "" : ("meter_id=" + meterId + "\uc758 ")) + "\uace0\uc870\ud30c \ub370\uc774\ud130\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (harmonicCtx.contains("unavailable")) return "\uace0\uc870\ud30c \uc870\ud68c\ub97c \ud604\uc7ac \uc218\ud589\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        Matcher tv = Pattern.compile("THD_V\\(A/B/C\\)=([0-9.\\-]+)/([0-9.\\-]+)/([0-9.\\-]+)").matcher(harmonicCtx);
        Matcher ti = Pattern.compile("THD_I\\(A/B/C\\)=([0-9.\\-]+)/([0-9.\\-]+)/([0-9.\\-]+)").matcher(harmonicCtx);
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(harmonicCtx);
        String m = mid.find() ? mid.group(1) : (meterId == null ? "-" : String.valueOf(meterId));
        String tvs = tv.find() ? (tv.group(1) + "/" + tv.group(2) + "/" + tv.group(3)) : "-";
        String tis = ti.find() ? (ti.group(1) + "/" + ti.group(2) + "/" + ti.group(3)) : "-";
        return "meter_id=" + m + "\uc758 \ucd5c\uc2e0 \uace0\uc870\ud30c \uc0c1\ud0dc\uc785\ub2c8\ub2e4. THD \uc804\uc555(A/B/C)=" + tvs + ", THD \uc804\ub958(A/B/C)=" + tis + ".";
    }

    public static String buildPowerFactorStandardDirectAnswer(String userMessage) {
        String m = userMessage == null ? "" : userMessage.toLowerCase(java.util.Locale.ROOT).replaceAll("\\s+", "");
        if (m.contains("ieee")) {
            return "IEEE\uc5d0\ub294 \ubaa8\ub4e0 \uc124\ube44\uc5d0 \uacf5\ud1b5\uc73c\ub85c \uc801\uc6a9\ub418\ub294 \ub2e8\uc77c \uc5ed\ub960 \ucd5c\uc18c \uae30\uc900\uce58\uac00 \uba85\uc2dc\ub3fc \uc788\ub2e4\uace0 \ubcf4\uae30 \uc5b4\ub835\uc2b5\ub2c8\ub2e4. \uc2e4\ubb34\uc5d0\uc11c\ub294 \ubcf4\ud1b5 0.9 \uc774\uc0c1\uc744 \ucd5c\uc18c \uad00\ub9ac \uae30\uc900\uc73c\ub85c \ubcf4\uace0, \uc6b4\uc601 \ubaa9\ud45c\ub294 0.95 \uc774\uc0c1\uc73c\ub85c \ub450\ub294 \uacbd\uc6b0\uac00 \ub9ce\uc2b5\ub2c8\ub2e4.";
        }
        return "\uc5ed\ub960 \uae30\uc900\uc740 \uc801\uc6a9 \uaddc\uc815\uacfc \uacc4\uc57d \uc870\uac74\uc5d0 \ub530\ub77c \ub2ec\ub77c\uc9c8 \uc218 \uc788\uc9c0\ub9cc, \uc2e4\ubb34\uc5d0\uc11c\ub294 \ubcf4\ud1b5 0.9 \uc774\uc0c1\uc744 \ucd5c\uc18c \uad00\ub9ac \uae30\uc900\uc73c\ub85c \ubcf4\uace0 0.95 \uc774\uc0c1\uc744 \ubaa9\ud45c\ub85c \uad00\ub9ac\ud558\ub294 \uacbd\uc6b0\uac00 \ub9ce\uc2b5\ub2c8\ub2e4.";
    }

    public static String buildUserDbContext(String dbContext) {
        String ctx = dbContext == null ? "" : dbContext.trim();
        if (ctx.isEmpty()) return "";

        if (ctx.startsWith("Meter:") || ctx.startsWith("Alarm:")) {
            String meterPart = null;
            String alarmPart = null;
            int meterIdx = ctx.indexOf("Meter:");
            int alarmIdx = ctx.indexOf("Alarm:");
            if (meterIdx >= 0 && alarmIdx >= 0) {
                if (meterIdx < alarmIdx) {
                    meterPart = trimToNull(ctx.substring(meterIdx + 6, alarmIdx));
                    alarmPart = trimToNull(ctx.substring(alarmIdx + 6));
                } else {
                    alarmPart = trimToNull(ctx.substring(alarmIdx + 6, meterIdx));
                    meterPart = trimToNull(ctx.substring(meterIdx + 6));
                }
            } else if (meterIdx >= 0) {
                meterPart = trimToNull(ctx.substring(meterIdx + 6));
            } else if (alarmIdx >= 0) {
                alarmPart = trimToNull(ctx.substring(alarmIdx + 6));
            }
            StringBuilder combined = new StringBuilder();
            if (meterPart != null) {
                String meterText = buildUserDbContext(meterPart);
                if (meterText != null && !meterText.trim().isEmpty()) combined.append(meterText.trim());
            }
            if (alarmPart != null) {
                String alarmText = buildLatestAlarmsDirectAnswer(alarmPart);
                if (alarmText != null && !alarmText.trim().isEmpty()) {
                    if (combined.length() > 0) combined.append("\n\n");
                    combined.append(alarmText.trim());
                }
            }
            if (combined.length() > 0) return combined.toString();
        }

        if (ctx.contains("[Latest meter readings")) {
            if (ctx.contains("unavailable")) return "계측 데이터를 현재 조회할 수 없습니다.";
            if (ctx.contains("no data")) return "요청한 조건의 계측 데이터가 없습니다.";
            Matcher m = Pattern.compile(
                "meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^@;]+)\\s*@\\s*([0-9\\-:\\s]+)\\s*V=([0-9.\\-]+),\\s*I=([0-9.\\-]+),\\s*PF=([0-9.\\-]+),\\s*kW=([0-9.\\-]+)(?:,\\s*kVAr=([0-9.\\-]+))?(?:,\\s*Hz=([0-9.\\-]+))?",
                Pattern.CASE_INSENSITIVE
            ).matcher(ctx);
            if (m.find()) {
                String meterId = m.group(1);
                String meterName = clip(m.group(2), 40);
                String panelName = clip(m.group(3), 40);
                String ts = clip(m.group(4), 19);
                String v = m.group(5);
                String i = m.group(6);
                String pf = m.group(7);
                String kw = m.group(8);
                String kvar = m.group(9);
                String hz = m.group(10);
                boolean noSignal = ctx.contains("STATE=NO_SIGNAL");
                StringBuilder out = new StringBuilder();
                out.append(meterId).append("번 계측기");
                if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) {
                    out.append("(").append(meterName.trim()).append(")");
                }
                out.append(" 현재 상태입니다.\n\n")
                    .append("핵심 값:\n")
                    .append("- 전압(V, 평균 우선): ").append(v).append("V\n")
                    .append("- 전류(I): ").append(i).append("A\n")
                    .append("- 역률(PF): ").append(pf).append("\n");
                if (hz != null && !hz.trim().isEmpty()) out.append("- 주파수(Hz): ").append(hz).append("Hz\n");
                out.append("- 유효전력(kW): ").append(kw).append("kW\n");
                if (kvar != null && !kvar.trim().isEmpty()) out.append("- 무효전력(kVAr): ").append(kvar).append("kVAr\n");
                out.append("\n메타 정보:\n")
                    .append("- 측정 시각: ").append(ts);
                if (panelName != null && !panelName.trim().isEmpty() && !"-".equals(panelName.trim())) out.append("\n- 패널: ").append(panelName.trim());
                if (noSignal) out.append("\n- 상태: 신호 없음(NO_SIGNAL), 데이터 미수신 가능성이 큽니다.");
                return out.toString();
            }
        }
        if (ctx.contains("[Alarm count]")) {
            if (ctx.contains("unavailable")) return "알람 건수를 현재 조회할 수 없습니다.";
            Matcher p = Pattern.compile("period=([^;]+)").matcher(ctx);
            Matcher d = Pattern.compile("days=([0-9]+)").matcher(ctx);
            Matcher s = Pattern.compile("scope=([^;]+)").matcher(ctx);
            Matcher a = Pattern.compile("area=([^;]+)").matcher(ctx);
            Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
            Matcher c = Pattern.compile("count=([0-9]+)").matcher(ctx);
            String period = p.find() ? p.group(1) : null;
            String days = d.find() ? d.group(1) : null;
            String scopeRaw = s.find() ? s.group(1) : "all";
            String area = a.find() ? a.group(1) : null;
            String meterId = mid.find() ? mid.group(1) : null;
            String cnt = c.find() ? c.group(1) : "0";
            String scope = "";
            if (meterId != null) scope += meterId + "번 계측기 ";
            if (area != null && !area.trim().isEmpty()) scope += area.trim() + " ";
            String alarmLabel = "알람";
            if (scopeRaw != null && scopeRaw.toLowerCase(java.util.Locale.ROOT).startsWith("type:")) {
                String t = scopeRaw.substring(5).trim();
                if (!t.isEmpty()) alarmLabel = t + " 알람";
            }
            String periodText = null;
            if (period != null && !period.trim().isEmpty() && !"-".equals(period.trim())) periodText = period.trim();
            else if (days != null) periodText = "최근 " + days + "일";
            StringBuilder out = new StringBuilder();
            if (scope != null && !scope.trim().isEmpty()) out.append(scope.trim()).append(" ");
            out.append(alarmLabel).append(" 건수 조회 결과입니다.\n\n")
                .append("핵심 값:\n")
                .append("- 건수: ").append(cnt).append("건");
            if (periodText != null && !periodText.isEmpty()) {
                out.append("\n\n메타 정보:\n")
                    .append("- 기간: ").append(periodText);
            }
            return out.toString();
        }
        if (ctx.contains("[Meter list]")) {
            if (ctx.contains("unavailable")) return "계측기 목록을 현재 조회할 수 없습니다.";
            if (ctx.contains("no data")) return "조건에 맞는 계측기 목록이 없습니다.";
            Matcher sc = Pattern.compile("scope=([^;]+)").matcher(ctx);
            Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*panel=([^,;]*)(?:,\\s*building=([^,;]*))?(?:,\\s*usage=([^;]*))?;").matcher(ctx);
            String scope = sc.find() ? sc.group(1) : null;
            StringBuilder out = new StringBuilder();
            out.append(scope != null && !scope.trim().isEmpty() ? scope.trim() + " 관련 계측기 목록입니다:\n" : "계측기 목록입니다:\n");
            int i = 0;
            while (row.find() && i < 20) {
                i++;
                String panel = row.group(3) == null ? "-" : row.group(3).trim();
                String building = row.group(4) == null ? "-" : row.group(4).trim();
                String usage = row.group(5) == null ? "-" : row.group(5).trim();
                out.append("- ").append(row.group(1)).append("번(").append(row.group(2).trim()).append(")")
                    .append(" / 패널 ").append(panel);
                if (!"-".equals(building) || !"-".equals(usage)) out.append(" / ").append(building).append(" / ").append(usage);
                out.append("\n");
            }
            if (i == 0) return "조건에 맞는 계측기 목록을 찾지 못했습니다.";
            return out.toString().trim();
        }
        if (ctx.contains("[Voltage phase angle]")) return buildPhaseAngleCard(ctx, true);
        if (ctx.contains("[Current phase angle]")) return buildPhaseAngleCard(ctx, false);
        if (ctx.contains("[Phase current]")) return buildPhaseValueCard(ctx, false);
        if (ctx.contains("[Phase voltage]")) return buildPhaseValueCard(ctx, true);
        if (ctx.contains("[Line voltage]")) return buildLineVoltageCard(ctx);
        if (ctx.contains("[Latest alarms]")) return buildLatestAlarmsDirectAnswer(ctx);
        if (ctx.contains("[Scoped monthly energy]")) return buildScopedMonthlyEnergyDirectAnswer(ctx);
        if (ctx.contains("[Monthly frequency avg]")) {
            Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
            Integer meterId = mid.find() ? Integer.valueOf(mid.group(1)) : null;
            return buildFrequencyDirectAnswer(ctx, meterId, null);
        }
        if (ctx.contains("[Latest energy")) return buildEnergyValueDirectAnswer(ctx, false);
        if (ctx.contains("[Energy delta]")) return buildEnergyDeltaDirectAnswer(ctx, false);
        if (ctx.contains("[Reactive energy delta]")) return buildEnergyDeltaDirectAnswer(ctx, true);
        if (ctx.contains("[Monthly power stats]")) return buildMonthlyPowerStatsDirectAnswer(ctx);
        if (ctx.contains("[Monthly peak power]")) return buildMonthlyPeakPowerDirectAnswer(ctx);
        if (ctx.contains("[Alarm types]")) return buildAlarmTypeDirectAnswer(ctx);
        if (ctx.contains("[Alarm meter TOP]")) return buildAlarmMeterTopDirectAnswer(ctx);
        if (ctx.contains("[Usage type list]")) return buildUsageTypeListDirectAnswer(ctx);
        if (ctx.contains("[Voltage unbalance TOP")) return buildVoltageUnbalanceTopDirectAnswer(ctx);
        if (ctx.contains("[Harmonic exceed]")) return buildHarmonicExceedDirectAnswer(ctx);
        if (ctx.contains("[Power factor outlier]")) return buildPowerFactorOutlierDirectAnswer(ctx, -1);
        if (ctx.contains("[Frequency outlier]")) return buildFrequencyOutlierDirectAnswer(ctx);
        if (ctx.contains("[Open alarms]")) return buildOpenAlarmsDirectAnswer(ctx);

        String fallback = ctx
            .replace("STATE=NO_SIGNAL", "신호없음")
            .replace("meter_id=", "계측기 ")
            .replace("no data", "데이터 없음")
            .replace("unavailable", "조회 불가");
        return clip(fallback, 600);
    }

    public static String buildScopedMonthlyEnergyDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return "구역별 전력 사용량 데이터를 찾지 못했습니다.";
        }
        if (ctx.contains("scope required")) {
            return "건물이나 구역을 지정해 주세요. 예: 동관의 전체 사용량은?";
        }
        if (ctx.contains("unavailable")) {
            return "구역별 전력 사용량을 현재 조회할 수 없습니다.";
        }
        if (ctx.contains("no data")) {
            return "요청한 구역의 전력 사용량 데이터가 없습니다.";
        }
        Matcher sm = Pattern.compile("scope=([^;]+)").matcher(ctx);
        Matcher pm = Pattern.compile("period=([0-9]{4}-[0-9]{2})").matcher(ctx);
        Matcher mm = Pattern.compile("meter_count=([0-9]+)").matcher(ctx);
        Matcher am = Pattern.compile("avg_kw=([0-9.\\-]+)").matcher(ctx);
        Matcher km = Pattern.compile("sum_kwh=([0-9.\\-]+)").matcher(ctx);
        String scope = sm.find() ? trimToNull(sm.group(1)) : null;
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        String meterCount = mm.find() ? trimToNull(mm.group(1)) : "0";
        String avgKw = am.find() ? trimToNull(am.group(1)) : "-";
        String sumKwh = km.find() ? trimToNull(km.group(1)) : "-";
        String label = (scope == null || scope.isEmpty()) ? "해당 구역" : scope;
        String prefix = (period == null || period.isEmpty()) ? (label + " 전체 사용량 조회 결과입니다.") : (label + " " + period + " 전력 사용량입니다.");
        return prefix + "\n\n핵심 값:\n- 누적 전력량: " + sumKwh + "kWh\n- 평균전력: " + avgKw + "kW\n\n메타 정보:\n- 집계 계측기 수: " + meterCount + "개";
    }

    public static String buildUsageAlarmTopDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uC9D1\uACC4 \uB370\uC774\uD130\uB97C \uCC3E\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.";
        }
        if (ctx.contains("unavailable")) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uC9D1\uACC4\uB97C \uD604\uC7AC \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        if (ctx.contains("no data")) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uC9D1\uACC4 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        Matcher dm = Pattern.compile("days=([0-9]+)").matcher(ctx);
        String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
        String daysLabel = dm.find() ? trimToNull(dm.group(1)) : null;
        Matcher row = Pattern.compile("\\s[0-9]+\\)([^=;]+)=([0-9]+);").matcher(ctx);
        ArrayList<String> parts = new ArrayList<String>();
        while (row.find()) {
            String usage = trimToNull(row.group(1));
            String cnt = trimToNull(row.group(2));
            if (usage == null || cnt == null) continue;
            parts.add(usage + " " + cnt + "\uAC74");
        }
        if (parts.isEmpty()) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uC9D1\uACC4 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }

        StringBuilder out = new StringBuilder();
        if (periodLabel != null && !periodLabel.isEmpty()) {
            out.append(periodLabel).append(" \uC54C\uB78C\uC774 \uB9CE\uC740 \uC6A9\uB3C4\uC785\uB2C8\uB2E4.\n");
        } else if (daysLabel != null && !daysLabel.isEmpty()) {
            out.append("\uCD5C\uADFC ").append(daysLabel).append("\uC77C \uC54C\uB78C\uC774 \uB9CE\uC740 \uC6A9\uB3C4\uC785\uB2C8\uB2E4.\n");
        } else {
            out.append("\uC54C\uB78C\uC774 \uB9CE\uC740 \uC6A9\uB3C4\uC785\uB2C8\uB2E4.\n");
        }
        for (int i = 0; i < parts.size(); i++) {
            out.append(i + 1).append(". ").append(parts.get(i));
            if (i + 1 < parts.size()) out.append("\n");
        }
        return out.toString();
    }

    public static String buildUsageAlarmCountDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uAC74\uC218 \uB370\uC774\uD130\uB97C \uCC3E\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.";
        }
        if (ctx.contains("usage token required")) {
            return "\uC6A9\uB3C4 \uC815\uBCF4\uB97C \uC9C0\uC815\uD574 \uC8FC\uC138\uC694.";
        }
        if (ctx.contains("unavailable")) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uAC74\uC218\uB97C \uD604\uC7AC \uC870\uD68C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }
        if (ctx.contains("no data")) {
            return "\uC6A9\uB3C4\uBCC4 \uC54C\uB78C \uAC74\uC218 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.";
        }

        Matcher um = Pattern.compile("usage=([^;]+)").matcher(ctx);
        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        Matcher dm = Pattern.compile("days=([0-9]+)").matcher(ctx);
        Matcher cm = Pattern.compile("count=([0-9]+)").matcher(ctx);
        String usage = um.find() ? trimToNull(um.group(1)) : null;
        String periodLabel = pm.find() ? trimToNull(pm.group(1)) : null;
        String daysLabel = dm.find() ? trimToNull(dm.group(1)) : null;
        String count = cm.find() ? trimToNull(cm.group(1)) : "0";

        String prefix = (usage == null ? "\uD574\uB2F9 \uC6A9\uB3C4" : usage) + " \uC54C\uB78C \uAC74\uC218 \uC870\uD68C \uACB0\uACFC\uC785\uB2C8\uB2E4.";
        if (periodLabel != null && !periodLabel.isEmpty()) {
            return prefix + "\n\n\uD575\uC2EC \uAC12:\n- \uAC74\uC218: " + count + "\uAC74\n\n\uBA54\uD0C0 \uC815\uBCF4:\n- \uAE30\uAC04: " + periodLabel;
        }
        if (daysLabel != null && !daysLabel.isEmpty()) {
            return prefix + "\n\n\uD575\uC2EC \uAC12:\n- \uAC74\uC218: " + count + "\uAC74\n\n\uBA54\uD0C0 \uC815\uBCF4:\n- \uAE30\uAC04: \uCD5C\uADFC " + daysLabel + "\uC77C";
        }
        return prefix + "\n\n\uD575\uC2EC \uAC12:\n- \uAC74\uC218: " + count + "\uAC74";
    }

    private static String trimToNull(String s) {
        return EpmsWebUtil.trimToNull(s);
    }

    private static String shortenAlarmDescription(String desc) {
        String text = trimToNull(desc);
        if (text == null) return null;
        Matcher tag = Pattern.compile("tag=([^,]+)").matcher(text);
        Matcher point = Pattern.compile("point=([0-9]+)").matcher(text);
        Matcher addr = Pattern.compile("addr=([0-9]+)").matcher(text);
        Matcher bit = Pattern.compile("bit=([0-9]+)").matcher(text);
        ArrayList<String> parts = new ArrayList<String>();
        if (tag.find()) parts.add(clip(trimToNull(tag.group(1)), 20));
        if (point.find()) parts.add("point " + point.group(1));
        if (addr.find()) parts.add("addr " + addr.group(1));
        if (bit.find()) parts.add("bit " + bit.group(1));
        if (!parts.isEmpty()) return String.join(", ", parts);
        text = text.replace("PLC 1 DI ON:", "").replace("PLC 1 DI OFF:", "").trim();
        return clip(text, 36);
    }

    private static String compactAlarmList(ArrayList<String[]> rows, String prefix) {
        if (rows == null || rows.isEmpty()) return prefix + "\uc5c6\uc2b5\ub2c8\ub2e4.";
        String firstSev = trimToNull(rows.get(0)[0]);
        String firstType = trimToNull(rows.get(0)[1]);
        boolean sameHeader = firstType != null;
        for (int i = 1; i < rows.size(); i++) {
            String sev = trimToNull(rows.get(i)[0]);
            String type = trimToNull(rows.get(i)[1]);
            if (!java.util.Objects.equals(firstSev, sev) || !java.util.Objects.equals(firstType, type)) {
                sameHeader = false;
                break;
            }
        }
        ArrayList<String> items = new ArrayList<String>();
        for (String[] row : rows) {
            String sev = trimToNull(row[0]);
            String type = trimToNull(row[1]);
            String meter = trimToNull(row[2]);
            String ts = trimToNull(row[3]);
            String state = trimToNull(row[4]);
            String desc = trimToNull(row[5]);
            String item;
            if (sameHeader) {
                item = (meter == null ? "-" : meter);
                if (ts != null) item += " " + clip(ts, 19);
                if (state != null && !state.isEmpty()) item += " [" + state + "]";
            } else {
                item = (sev == null ? "-" : sev) + "/" + (type == null ? "-" : type) + " @ " + (meter == null ? "-" : meter);
                if (ts != null) item += " " + clip(ts, 19);
                if (state != null && !state.isEmpty()) item += " [" + state + "]";
            }
            if (desc != null && !desc.isEmpty()) item += " - " + desc;
            items.add(item);
        }
        if (sameHeader) {
            String header = (firstSev == null ? "-" : firstSev) + "/" + firstType;
            return prefix + header + " " + rows.size() + "\uac74\uc73c\ub85c, " + String.join(" / ", items) + "\uc785\ub2c8\ub2e4.";
        }
        java.util.LinkedHashMap<String, ArrayList<String>> grouped = new java.util.LinkedHashMap<String, ArrayList<String>>();
        for (String[] row : rows) {
            String sev = trimToNull(row[0]);
            String type = trimToNull(row[1]);
            String meter = trimToNull(row[2]);
            String ts = trimToNull(row[3]);
            String state = trimToNull(row[4]);
            String desc = trimToNull(row[5]);
            String header = (sev == null ? "-" : sev) + "/" + (type == null ? "-" : type);
            ArrayList<String> bucket = grouped.get(header);
            if (bucket == null) {
                bucket = new ArrayList<String>();
                grouped.put(header, bucket);
            }
            String item = (meter == null ? "-" : meter);
            if (ts != null) item += " " + clip(ts, 19);
            if (state != null && !state.isEmpty()) item += " [" + state + "]";
            if (desc != null && !desc.isEmpty()) item += " - " + desc;
            bucket.add(item);
        }
        ArrayList<String> groups = new ArrayList<String>();
        for (java.util.Map.Entry<String, ArrayList<String>> e : grouped.entrySet()) {
            ArrayList<String> bucket = e.getValue();
            groups.add(e.getKey() + " " + bucket.size() + "\uac74: " + String.join(" / ", bucket));
        }
        return prefix + String.join(" ; ", groups) + "\uc785\ub2c8\ub2e4.";
    }

    private static String clip(String s, int maxLen) {
        if (s == null) return "-";
        String t = s.replaceAll("\\s+", " ").trim();
        if (t.isEmpty()) return "-";
        return t.length() > maxLen ? t.substring(0, maxLen) + "..." : t;
    }

    private static String buildPhaseAngleCard(String ctx, boolean voltage) {
        if (ctx.contains("unavailable")) return voltage ? "전압 위상각 데이터를 현재 조회할 수 없습니다." : "전류 위상각 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("no data")) return voltage ? "요청한 계측기의 전압 위상각 데이터가 없습니다." : "요청한 계측기의 전류 위상각 데이터가 없습니다.";
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        Matcher mn = Pattern.compile("meter=([^,]+)").matcher(ctx);
        Matcher pn = Pattern.compile("panel=([^,]+)").matcher(ctx);
        Matcher ts = Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        Matcher aM = Pattern.compile((voltage ? "Va" : "Ia") + "=([0-9.\\-]+)").matcher(ctx);
        Matcher bM = Pattern.compile((voltage ? "Vb" : "Ib") + "=([0-9.\\-]+)").matcher(ctx);
        Matcher cM = Pattern.compile((voltage ? "Vc" : "Ic") + "=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String a = aM.find() ? aM.group(1) : "-";
        String b = bM.find() ? bM.group(1) : "-";
        String c = cM.find() ? cM.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) out.append("(").append(meterName.trim()).append(")");
        out.append(voltage ? " 전압 위상각 조회 결과입니다.\n\n" : " 전류 위상각 조회 결과입니다.\n\n")
            .append("핵심 값:\n")
            .append("- ").append(voltage ? "Va" : "Ia").append(": ").append(a).append("°\n")
            .append("- ").append(voltage ? "Vb" : "Ib").append(": ").append(b).append("°\n")
            .append("- ").append(voltage ? "Vc" : "Ic").append(": ").append(c).append("°\n\n")
            .append("메타 정보:\n")
            .append("- 측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) out.append("\n- 패널: ").append(panel.trim());
        return out.toString();
    }

    private static String buildPhaseValueCard(String ctx, boolean voltage) {
        if (ctx.contains("unavailable")) return voltage ? "상전압 데이터를 현재 조회할 수 없습니다." : "상전류 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("phase required") || ctx.contains("invalid phase")) return "A/B/C 상을 지정해 주세요.";
        if (ctx.contains("no data")) return voltage ? "요청한 계측기의 상전압 데이터가 없습니다." : "요청한 계측기의 상전류 데이터가 없습니다.";
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        Matcher mn = Pattern.compile("meter=([^,]+)").matcher(ctx);
        Matcher pn = Pattern.compile("panel=([^,]+)").matcher(ctx);
        Matcher ts = Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        Matcher ph = Pattern.compile("phase=([ABC])").matcher(ctx);
        Matcher vm = Pattern.compile((voltage ? "V" : "I") + "=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String phase = ph.find() ? ph.group(1) : "-";
        String value = vm.find() ? vm.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) out.append("(").append(meterName.trim()).append(")");
        out.append(" ").append(phase).append("상 ").append(voltage ? "전압" : "전류").append(" 조회 결과입니다.\n\n")
            .append("핵심 값:\n")
            .append("- ").append(phase).append("상 ").append(voltage ? "전압" : "전류").append(": ").append(value).append(voltage ? "V" : "A").append("\n\n")
            .append("메타 정보:\n")
            .append("- 측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) out.append("\n- 패널: ").append(panel.trim());
        return out.toString();
    }

    private static String buildLineVoltageCard(String ctx) {
        if (ctx.contains("unavailable")) return "선간전압 데이터를 현재 조회할 수 없습니다.";
        if (ctx.contains("meter_id required")) return "계측기를 지정해 주세요.";
        if (ctx.contains("no data")) return "요청한 계측기의 선간전압 데이터가 없습니다.";
        Matcher mid = Pattern.compile("meter_id=([0-9]+)").matcher(ctx);
        Matcher mn = Pattern.compile("meter=([^,]+)").matcher(ctx);
        Matcher pn = Pattern.compile("panel=([^,]+)").matcher(ctx);
        Matcher ts = Pattern.compile("t=([0-9\\-:\\s]+)").matcher(ctx);
        Matcher pr = Pattern.compile("pair=([A-Z]+)").matcher(ctx);
        Matcher vabm = Pattern.compile("Vab=([0-9.\\-]+)").matcher(ctx);
        Matcher vbcm = Pattern.compile("Vbc=([0-9.\\-]+)").matcher(ctx);
        Matcher vcam = Pattern.compile("Vca=([0-9.\\-]+)").matcher(ctx);
        String meterId = mid.find() ? mid.group(1) : "-";
        String meterName = mn.find() ? clip(mn.group(1), 40) : "-";
        String panel = pn.find() ? clip(pn.group(1), 40) : "-";
        String time = ts.find() ? clip(ts.group(1), 19) : "-";
        String pair = pr.find() ? pr.group(1) : "ALL";
        String vab = vabm.find() ? vabm.group(1) : "-";
        String vbc = vbcm.find() ? vbcm.group(1) : "-";
        String vca = vcam.find() ? vcam.group(1) : "-";
        StringBuilder out = new StringBuilder();
        out.append(meterId).append("번 계측기");
        if (meterName != null && !meterName.trim().isEmpty() && !"-".equals(meterName.trim())) out.append("(").append(meterName.trim()).append(")");
        out.append(" 선간전압 조회 결과입니다.\n\n");
        if ("AB".equals(pair)) out.append("핵심 값:\n- AB 선간전압: ").append(vab).append("V\n");
        else if ("BC".equals(pair)) out.append("핵심 값:\n- BC 선간전압: ").append(vbc).append("V\n");
        else if ("CA".equals(pair)) out.append("핵심 값:\n- CA 선간전압: ").append(vca).append("V\n");
        else out.append("핵심 값:\n- AB: ").append(vab).append("V\n- BC: ").append(vbc).append("V\n- CA: ").append(vca).append("V\n");
        out.append("\n메타 정보:\n- 측정 시각: ").append(time);
        if (panel != null && !panel.trim().isEmpty() && !"-".equals(panel.trim())) out.append("\n- 패널: ").append(panel.trim());
        return out.toString();
    }
}
