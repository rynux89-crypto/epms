package epms.ups;

import epms.util.UpsDataSourceProvider;
import epms.util.UpsFormatSupport;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public final class UpsDashboardRenderSupport {
    private UpsDashboardRenderSupport() {
    }

    public static String statusText(String cls) {
        if ("normal".equals(cls)) return "정상";
        if ("critical".equals(cls)) return "장애";
        if ("warning".equals(cls)) return "경고";
        return "오프라인";
    }

    public static String operationModeText(Object value, boolean online) {
        if (!online) return "오프라인";
        return UpsFormatSupport.upsModeLabel(value);
    }

    public static String pctStyle(Object value) {
        int v = Math.max(0, Math.min(100, intNum(value, 0)));
        return "width:" + v + "%";
    }

    public static String kpiLoadMiniPoints(double fallback) {
        return sparkPoints(recentAggregateSeries("load_percent", fallback), 80.0, 44.0, 4.0);
    }

    public static String kpiBatteryMiniBars(double fallback) {
        return batteryGauge(fallback, 120.0, 44.0);
    }

    private static int intNum(Object value, int fallback) {
        if (value == null) return fallback;
        if (value instanceof Number) return (int)Math.round(((Number)value).doubleValue());
        try {
            return (int)Math.round(Double.parseDouble(String.valueOf(value).trim()));
        } catch (Exception ignore) {
            return fallback;
        }
    }

    private static String metricColumn(String key) {
        if ("load_percent".equals(key)) return "load_percent";
        if ("battery_charge_percent".equals(key)) return "battery_charge_percent";
        return null;
    }

    private static List<Double> recentAggregateSeries(String key, double fallback) {
        List<Double> values = new ArrayList<Double>();
        String column = metricColumn(key);
        if (column == null) {
            values.add(Double.valueOf(fallback));
            return values;
        }

        Double[] buckets = new Double[60];
        String sql =
            "SELECT DATEDIFF(minute, measured_at, SYSDATETIME()) AS minute_ago, AVG(CAST(" + column + " AS float)) AS measured_value " +
            "FROM dbo.ups_measurement " +
            "WHERE measured_at >= DATEADD(hour, -1, SYSDATETIME()) " +
            "AND measured_at <= SYSDATETIME() " +
            "AND " + column + " IS NOT NULL " +
            "GROUP BY DATEDIFF(minute, measured_at, SYSDATETIME())";
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                int minuteAgo = rs.getInt("minute_ago");
                if (minuteAgo >= 0 && minuteAgo < 60) {
                    buckets[59 - minuteAgo] = Double.valueOf(rs.getDouble("measured_value"));
                }
            }
        } catch (Exception ignore) {
            return Arrays.asList(Double.valueOf(fallback), Double.valueOf(fallback));
        }

        Double carry = firstNonNull(buckets, Double.valueOf(fallback));
        for (int i = 0; i < buckets.length; i++) {
            if (buckets[i] == null) {
                buckets[i] = carry;
            } else {
                carry = buckets[i];
            }
            values.add(buckets[i]);
        }
        return values;
    }

    private static Double firstNonNull(Double[] values, Double fallback) {
        if (values != null) {
            for (Double value : values) {
                if (value != null) return value;
            }
        }
        return fallback;
    }

    private static String sparkPoints(List<Double> values, double width, double height, double pad) {
        if (values == null || values.isEmpty()) values = Arrays.asList(Double.valueOf(0));
        if (values.size() == 1) values = Arrays.asList(values.get(0), values.get(0));
        double min = Double.MAX_VALUE;
        double max = -Double.MAX_VALUE;
        for (Double raw : values) {
            double v = raw == null ? 0 : raw.doubleValue();
            if (v < min) min = v;
            if (v > max) max = v;
        }
        if (max - min < 0.0001) {
            max = max + 1;
            min = min - 1;
        }
        StringBuilder points = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            double v = values.get(i) == null ? min : values.get(i).doubleValue();
            double x = values.size() == 1 ? width / 2 : (width * i) / (values.size() - 1);
            double y = pad + (height - (pad * 2)) * (1 - ((v - min) / (max - min)));
            if (i > 0) points.append(' ');
            points.append(String.format(Locale.US, "%.1f,%.1f", x, y));
        }
        return points.toString();
    }

    private static String miniBars(List<Double> values, double width, double height, int barCount) {
        if (values == null || values.isEmpty()) values = Arrays.asList(Double.valueOf(0));
        int count = Math.max(1, barCount);
        double gap = 5.0;
        double barWidth = Math.max(2.0, (width - (gap * (count + 1))) / count);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < count; i++) {
            int idx = count == 1 ? values.size() - 1 : (int)Math.round((values.size() - 1) * (i / (double)(count - 1)));
            double raw = values.get(Math.max(0, Math.min(values.size() - 1, idx))).doubleValue();
            double pct = Math.max(0.0, Math.min(100.0, raw));
            double barHeight = Math.max(3.0, (height - 8.0) * (pct / 100.0));
            double x = gap + i * (barWidth + gap);
            double y = height - barHeight - 2.0;
            out.append(String.format(Locale.US,
                "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" fill=\"#29e675\"/>",
                x, y, barWidth, barHeight));
        }
        return out.toString();
    }

    private static String batteryGauge(double value, double width, double height) {
        double pct = Math.max(0.0, Math.min(100.0, value));
        String color = pct <= 20.0 ? "#ff5c52" : (pct <= 50.0 ? "#ffbf31" : "#29e675");
        double x = 5.0;
        double y = 4.0;
        double bodyWidth = width - 14.0;
        double bodyHeight = 36.0;
        double fillWidth = Math.max(0.0, (bodyWidth - 4.0) * (pct / 100.0));
        StringBuilder out = new StringBuilder();
        out.append(String.format(Locale.US,
            "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"5\" fill=\"none\" stroke=\"#2f4960\" stroke-width=\"2\"/>",
            x, y, bodyWidth, bodyHeight));
        out.append(String.format(Locale.US,
            "<rect x=\"%.1f\" y=\"%.1f\" width=\"5.0\" height=\"18.0\" rx=\"2\" fill=\"#2f4960\"/>",
            x + bodyWidth + 1.0, y + 9.0));
        out.append(String.format(Locale.US,
            "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"4\" fill=\"%s\"/>",
            x + 2.0, y + 2.0, fillWidth, bodyHeight - 4.0, color));
        return out.toString();
    }
}
