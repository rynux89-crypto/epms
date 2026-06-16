package epms.ups;

import epms.util.UpsDataSourceProvider;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class UpsEnabledActiveAlarmQueryService {
    private UpsEnabledActiveAlarmQueryService() {
    }

    public static List<Map<String, Object>> rows(String searchText) throws Exception {
        String normalized = normalize(searchText);
        StringBuilder sql = new StringBuilder();
        List<Object> params = new ArrayList<Object>();
        sql.append("SELECT TOP 200 a.alarm_id, d.ups_name, d.enabled AS device_enabled, ")
           .append("a.severity, a.metric_key, a.alarm_message, a.occurred_at, a.cleared_at, a.status ")
           .append("FROM dbo.ups_alarm_log a INNER JOIN dbo.ups_device d ON d.ups_id = a.ups_id ")
           .append("WHERE a.status = 'ACTIVE' AND d.enabled = 1 ");
        appendSearch(sql, params, searchText, normalized);
        sql.append("ORDER BY a.occurred_at DESC");

        List<UpsAlarmRow> out = new ArrayList<UpsAlarmRow>();
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setObject(i + 1, params.get(i));
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    out.add(UpsAlarmRow.from(rs));
                }
            }
        }
        return UpsAlarmRow.toMaps(out);
    }

    private static void appendSearch(StringBuilder sql, List<Object> params, String searchText, String normalizedSearchText) {
        if (searchText == null || searchText.trim().isEmpty()) return;
        sql.append("AND (d.ups_name LIKE ? OR d.location LIKE ? OR d.ip_address LIKE ? OR a.rule_code LIKE ? OR a.alarm_message LIKE ? ");
        String like = "%" + searchText.trim() + "%";
        params.add(like);
        params.add(like);
        params.add(like);
        params.add(like);
        params.add(like);
        if (!normalizedSearchText.isEmpty()) {
            sql.append("OR REPLACE(d.ups_name, ' ', '') LIKE ? OR REPLACE(d.location, ' ', '') LIKE ? OR REPLACE(a.rule_code, ' ', '') LIKE ? OR REPLACE(a.alarm_message, ' ', '') LIKE ? ");
            String nlike = "%" + normalizedSearchText + "%";
            params.add(nlike);
            params.add(nlike);
            params.add(nlike);
            params.add(nlike);
        }
        if (searchText.toLowerCase(Locale.ROOT).contains("sim")) {
            sql.append("OR (d.ip_address = '127.0.0.1' AND d.modbus_port = 1502) ");
        }
        sql.append(") ");
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", "");
    }
}
