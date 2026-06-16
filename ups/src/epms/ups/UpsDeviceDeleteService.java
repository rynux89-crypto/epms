package epms.ups;

import epms.util.UpsDataSourceProvider;
import java.sql.Connection;
import java.sql.PreparedStatement;

public final class UpsDeviceDeleteService {
    private UpsDeviceDeleteService() {
    }

    public static void deleteDevice(String upsIdRaw) throws Exception {
        if (upsIdRaw == null || upsIdRaw.trim().isEmpty()) {
            throw new IllegalArgumentException("삭제할 UPS를 선택하세요.");
        }
        int upsId = Integer.parseInt(upsIdRaw.trim());
        try (Connection conn = UpsDataSourceProvider.resolveDataSource().getConnection()) {
            boolean oldAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);
            try {
                deleteByUpsId(conn, "dbo.ups_measurement", upsId);
                deleteByUpsId(conn, "dbo.ups_alarm_log", upsId);
                int deleted;
                try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.ups_device WHERE ups_id=?")) {
                    ps.setInt(1, upsId);
                    deleted = ps.executeUpdate();
                }
                if (deleted == 0) throw new IllegalArgumentException("삭제할 UPS를 찾을 수 없습니다.");
                conn.commit();
            } catch (Exception e) {
                conn.rollback();
                throw e;
            } finally {
                conn.setAutoCommit(oldAutoCommit);
            }
        }
    }

    private static void deleteByUpsId(Connection conn, String tableName, int upsId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM " + tableName + " WHERE ups_id=?")) {
            ps.setInt(1, upsId);
            ps.executeUpdate();
        }
    }
}
