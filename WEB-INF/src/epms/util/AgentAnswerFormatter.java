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
        return subject + " " + period + " \ud3c9\uade0 \uc8fc\ud30c\uc218\ub294 " + avg + "Hz \uc785\ub2c8\ub2e4. (\ucd5c\uc18c " + min + ", \ucd5c\ub300 " + max + ", \uc0d8\ud50c " + samples + ")";
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
        String out = label + "\uc758 \ud604\uc7ac " + subject + "\uc740 " + value + unit + "\uc785\ub2c8\ub2e4.";
        if (time != null && !time.isEmpty()) out += " \uce21\uc815 \uc2dc\uac01: " + clip(time, 19);
        return out;
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
        String out = label + "\uc758 \ud604\uc7ac " + subject + "\uc740 " + value + unit + "\uc785\ub2c8\ub2e4.";
        if (time != null && !time.isEmpty()) out += " \uce21\uc815 \uc2dc\uac01: " + clip(time, 19);
        return out;
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
        return label + "\uc758 " + periodText + " " + subject + "\uc740 " + delta + unit + "\uc785\ub2c8\ub2e4.";
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
        String prefix = periodLabel != null && !periodLabel.isEmpty()
            ? periodLabel + " \uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c\uc740 "
            : (daysLabel != null && !daysLabel.isEmpty() ? "\ucd5c\uadfc " + daysLabel + "\uc77c \uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c\uc740 " : "\uc2ec\uac01\ub3c4\ubcc4 \uc54c\ub78c\uc740 ");
        return prefix + String.join(", ", parts) + "\uc785\ub2c8\ub2e4.";
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
        String prefix = periodLabel != null && !periodLabel.isEmpty()
            ? periodLabel + " "
            : (daysLabel != null && !daysLabel.isEmpty() ? "\ucd5c\uadfc " + daysLabel + "\uc77c " : "");
        prefix += "trip".equalsIgnoreCase(scopeLabel) ? "TRIP \uc54c\ub78c \uc885\ub958\ub294 " : "\uc54c\ub78c \uc885\ub958\ub294 ";
        return prefix + String.join(", ", parts) + "\uc785\ub2c8\ub2e4.";
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
        String prefix = (period == null || period.isEmpty()) ? "\uc804\uc555 \ubd88\ud3c9\ud615 \uc0c1\uc704\ub294 " : (period + " \uc804\uc555 \ubd88\ud3c9\ud615 \uc0c1\uc704\ub294 ");
        return prefix + String.join(" / ", parts) + "\uc785\ub2c8\ub2e4.";
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
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " [" + panel + "]";
            if (thdV != null) item += " THD_V " + thdV;
            if (thdI != null) item += ", THD_I " + thdI;
            if (ts != null && !ts.isEmpty()) item += " @ " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) return "\uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        String prefix = (period == null || period.isEmpty()) ? "\uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30\ub294 " : (period + " \uace0\uc870\ud30c \uc774\uc0c1 \uacc4\uce21\uae30\ub294 ");
        return prefix + String.join(" / ", items) + "\uc785\ub2c8\ub2e4.";
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
            if (panel != null && !panel.isEmpty() && !"-".equals(panel)) item += " [" + panel + "]";
            item += " PF " + pf;
            if (ts != null && !ts.isEmpty()) item += " @ " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) {
            return noSignalCount >= 0
                ? "\uc5ed\ub960 \uc774\uc0c1(\uc720\ud6a8\uc2e0\ud638 \uae30\uc900, \uc784\uacc4 \ubbf8\ub9cc) \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4. (\uc2e0\ud638\uc5c6\uc74c " + noSignalCount + "\uac1c \ubcc4\ub3c4)"
                : "\uc5ed\ub960 \uc774\uc0c1(\uc720\ud6a8\uc2e0\ud638 \uae30\uc900, \uc784\uacc4 \ubbf8\ub9cc) \uacc4\uce21\uae30\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        }
        String prefix = (period == null || period.isEmpty()) ? "\uc5ed\ub960 \uc774\uc0c1 \uacc4\uce21\uae30\ub294 " : (period + " \uc5ed\ub960 \uc774\uc0c1 \uacc4\uce21\uae30\ub294 ");
        String suffix = noSignalCount >= 0 ? " (\uc2e0\ud638\uc5c6\uc74c " + noSignalCount + "\uac1c \ubcc4\ub3c4)" : "";
        return prefix + String.join(" / ", items) + "\uc785\ub2c8\ub2e4." + suffix;
    }

    public static String buildFrequencyOutlierDirectAnswer(String ctx) {
        if (ctx == null || ctx.trim().isEmpty()) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58 \ub370\uc774\ud130\ub97c \ucc3e\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("unavailable")) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58 \ub370\uc774\ud130\ub97c \ud604\uc7ac \uc870\ud68c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.";
        if (ctx.contains("none") || ctx.contains("no data")) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";

        Matcher pm = Pattern.compile("period=([^;]+)").matcher(ctx);
        String period = pm.find() ? trimToNull(pm.group(1)) : null;
        ArrayList<String> items = new ArrayList<String>();
        Matcher row = Pattern.compile("\\s[0-9]+\\)meter_id=([0-9]+),\\s*([^,;]+),\\s*Hz=([0-9.\\-]+),\\s*t=([^;]+);").matcher(ctx);
        while (row.find()) {
            String meterId = trimToNull(row.group(1));
            String meterName = trimToNull(row.group(2));
            String hz = trimToNull(row.group(3));
            String ts = trimToNull(row.group(4));
            if (meterId == null || meterName == null || hz == null) continue;
            String item = meterName + "(" + meterId + ") " + hz + "Hz";
            if (ts != null && !ts.isEmpty()) item += " @ " + clip(ts, 19);
            items.add(item);
        }
        if (items.isEmpty()) return "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58\uac00 \uc5c6\uc2b5\ub2c8\ub2e4.";
        String prefix = (period == null || period.isEmpty()) ? "\uc8fc\ud30c\uc218 \uc774\uc0c1\uce58\ub294 " : (period + " \uc8fc\ud30c\uc218 \uc774\uc0c1\uce58\ub294 ");
        return prefix + String.join(" / ", items) + "\uc785\ub2c8\ub2e4.";
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
        String suffix = (samples == null || samples.isEmpty()) ? "" : " (\ud45c\ubcf8 " + samples + "\uac74)";
        return meterId + "\ubc88 \uacc4\uce21\uae30\uc758 " + period + " \ud3c9\uade0\uc804\ub825\uc740 " + avgKw + "kW, \ucd5c\ub300\uc804\ub825\uc740 " + maxKw + "kW\uc785\ub2c8\ub2e4." + suffix;
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
        String prefix = unresolved == null ? "\ucd5c\uadfc \uc54c\ub78c\uc740 " : ("\ucd5c\uadfc \uc54c\ub78c\uc785\ub2c8\ub2e4. \ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c\uc740 " + unresolved + "\uac74\uc774\uba70, ");
        return compactAlarmList(rowsOut, prefix);
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
        return compactAlarmList(rowsOut, "\ud604\uc7ac \ubbf8\ud574\uacb0 \uc54c\ub78c\uc740 ");
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
}
