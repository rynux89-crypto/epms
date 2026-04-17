package epms.billing;

import epms.util.EpmsDataSourceProvider;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;

public final class BillingRepository {
    public Connection openConnection() throws Exception {
        return EpmsDataSourceProvider.resolveDataSource().getConnection();
    }

    public Integer ensureMonthlyCycle(Connection conn, String ym) throws Exception {
        if (ym == null || !ym.matches("\\d{4}-\\d{2}")) return null;
        try (PreparedStatement ps = conn.prepareStatement("SELECT cycle_id FROM dbo.billing_cycle WHERE cycle_code = ?")) {
            ps.setString(1, ym);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return Integer.valueOf(rs.getInt(1));
            }
        }
        YearMonth yearMonth = YearMonth.parse(ym);
        Date cycleStart = Date.valueOf(yearMonth.atDay(1));
        Date cycleEnd = Date.valueOf(yearMonth.atEndOfMonth());
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.billing_cycle (cycle_code, cycle_start_date, cycle_end_date, status) VALUES (?, ?, ?, 'DRAFT')",
                Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, ym);
            ps.setDate(2, cycleStart);
            ps.setDate(3, cycleEnd);
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return Integer.valueOf(rs.getInt(1));
            }
        }
        try (PreparedStatement ps = conn.prepareStatement("SELECT cycle_id FROM dbo.billing_cycle WHERE cycle_code = ?")) {
            ps.setString(1, ym);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return Integer.valueOf(rs.getInt(1));
            }
        }
        return null;
    }

    public String nextRateCode(Connection conn) throws Exception {
        int nextNo = 1;
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT ISNULL(MAX(TRY_CONVERT(int, SUBSTRING(rate_code, 5, 20))), 0) + 1 " +
                "FROM dbo.billing_rate WHERE rate_code LIKE 'RATE%'")) {
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) nextNo = rs.getInt(1);
            }
        }
        return String.format(java.util.Locale.ROOT, "RATE%04d", nextNo);
    }

    public void addRate(Connection conn, String rateCode, String rateName, Date effectiveFrom,
            Double unitPrice, Double basicCharge, Double demandPrice) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.billing_rate (rate_code, rate_name, effective_from, unit_price_per_kwh, basic_charge_amount, demand_unit_price, vat_rate, fund_rate, is_active) VALUES (?, ?, ?, ?, ?, ?, 0.1, 0.037, 1)")) {
            ps.setString(1, rateCode);
            ps.setString(2, rateName);
            ps.setDate(3, effectiveFrom);
            ps.setDouble(4, unitPrice);
            ps.setDouble(5, basicCharge);
            ps.setDouble(6, demandPrice);
            ps.executeUpdate();
        }
    }

    public void deleteRate(Connection conn, Integer rateId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.billing_rate WHERE rate_id = ?")) {
            ps.setInt(1, rateId.intValue());
            ps.executeUpdate();
        }
    }

    public void addContract(Connection conn, Integer storeId, Integer rateId, Date startDate, Double demandKw) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO dbo.tenant_billing_contract (store_id, rate_id, contract_start_date, contracted_demand_kw, billing_day, shared_area_ratio, is_active) VALUES (?, ?, ?, ?, 1, 0, 1)")) {
            ps.setInt(1, storeId.intValue());
            ps.setInt(2, rateId.intValue());
            ps.setDate(3, startDate);
            if (demandKw == null) ps.setNull(4, Types.DOUBLE); else ps.setDouble(4, demandKw.doubleValue());
            ps.executeUpdate();
        }
    }

    public void deleteContract(Connection conn, Long contractId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.tenant_billing_contract WHERE contract_id = ?")) {
            ps.setLong(1, contractId.longValue());
            ps.executeUpdate();
        }
    }

    public void deleteCycle(Connection conn, Integer cycleId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("DELETE FROM dbo.billing_cycle WHERE cycle_id = ?")) {
            ps.setInt(1, cycleId.intValue());
            ps.executeUpdate();
        }
    }

    public void runSnapshot(Connection conn, Integer cycleId, String snapshotType) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("EXEC dbo.sp_generate_billing_meter_snapshot ?, ?")) {
            ps.setInt(1, cycleId.intValue());
            ps.setString(2, snapshotType);
            ps.execute();
        }
    }

    public void runStatement(Connection conn, Integer cycleId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("EXEC dbo.sp_generate_billing_statement ?")) {
            ps.setInt(1, cycleId.intValue());
            ps.execute();
        }
    }

    public void updateStatementStatus(Connection conn, Long statementId, String statementStatus) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.billing_statement SET statement_status=?, issued_at=CASE WHEN ?='ISSUED' AND issued_at IS NULL THEN sysdatetime() ELSE issued_at END, confirmed_at=CASE WHEN ?='CONFIRMED' AND confirmed_at IS NULL THEN sysdatetime() ELSE confirmed_at END, updated_at=sysdatetime() WHERE statement_id=?")) {
            ps.setString(1, statementStatus);
            ps.setString(2, statementStatus);
            ps.setString(3, statementStatus);
            ps.setLong(4, statementId.longValue());
            ps.executeUpdate();
        }
    }

    public List<BillingOption> listStoreOptions(Connection conn) throws Exception {
        List<BillingOption> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement("SELECT store_id, store_code, store_name FROM dbo.tenant_store ORDER BY store_code");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) rows.add(new BillingOption(rs.getString(1), rs.getString(2) + " - " + rs.getString(3)));
        }
        return rows;
    }

    public List<BillingRateRow> listRates(Connection conn) throws Exception {
        List<BillingRateRow> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT rate_id, rate_code, rate_name, effective_from, unit_price_per_kwh, basic_charge_amount, demand_unit_price FROM dbo.billing_rate ORDER BY effective_from DESC, rate_id DESC");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                rows.add(new BillingRateRow(
                        rs.getInt("rate_id"),
                        rs.getString("rate_code"),
                        rs.getString("rate_name"),
                        rs.getDate("effective_from"),
                        rs.getBigDecimal("unit_price_per_kwh"),
                        rs.getBigDecimal("basic_charge_amount"),
                        rs.getBigDecimal("demand_unit_price")));
            }
        }
        return rows;
    }

    public List<BillingOption> toRateOptions(List<BillingRateRow> rates) {
        List<BillingOption> options = new ArrayList<>();
        for (BillingRateRow row : rates) {
            options.add(new BillingOption(String.valueOf(row.getRateId()), row.getRateCode() + " - " + row.getRateName()));
        }
        return options;
    }

    public List<BillingContractRow> listContracts(Connection conn) throws Exception {
        List<BillingContractRow> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT c.contract_id, ts.store_code, ts.store_name, br.rate_code, br.rate_name, c.contract_start_date, c.contracted_demand_kw " +
                "FROM dbo.tenant_billing_contract c INNER JOIN dbo.tenant_store ts ON ts.store_id = c.store_id INNER JOIN dbo.billing_rate br ON br.rate_id = c.rate_id ORDER BY c.contract_start_date DESC, c.contract_id DESC");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                rows.add(new BillingContractRow(
                        rs.getLong("contract_id"),
                        rs.getString("store_code"),
                        rs.getString("store_name"),
                        rs.getString("rate_code"),
                        rs.getString("rate_name"),
                        rs.getDate("contract_start_date"),
                        rs.getObject("contracted_demand_kw")));
            }
        }
        return rows;
    }

    public List<BillingCycleRow> listCycles(Connection conn) throws Exception {
        List<BillingCycleRow> rows = new ArrayList<>();
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT cycle_id, cycle_code, cycle_start_date, cycle_end_date, status FROM dbo.billing_cycle ORDER BY cycle_start_date DESC, cycle_id DESC");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                rows.add(new BillingCycleRow(
                        rs.getInt("cycle_id"),
                        rs.getString("cycle_code"),
                        rs.getDate("cycle_start_date"),
                        rs.getDate("cycle_end_date"),
                        rs.getString("status")));
            }
        }
        return rows;
    }

    public int countStatements(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM dbo.billing_statement");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    public int countSnapshots(Connection conn) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM dbo.billing_meter_snapshot");
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getInt(1) : 0;
        }
    }

    public List<BillingStatementRow> listStatements(Connection conn, String cycleFilter) throws Exception {
        List<BillingStatementRow> rows = new ArrayList<>();
        if (cycleFilter == null || cycleFilter.trim().isEmpty()) return rows;
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT bs.statement_id, ts.store_code, ts.store_name, bs.usage_kwh, bs.peak_demand_kw, bs.total_amount, bs.statement_status, bs.issued_at " +
                "FROM dbo.billing_statement bs INNER JOIN dbo.tenant_store ts ON ts.store_id = bs.store_id WHERE bs.cycle_id = ? ORDER BY ts.store_code")) {
            ps.setInt(1, Integer.parseInt(cycleFilter));
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    rows.add(new BillingStatementRow(
                            rs.getLong("statement_id"),
                            rs.getString("store_code"),
                            rs.getString("store_name"),
                            rs.getBigDecimal("usage_kwh"),
                            rs.getObject("peak_demand_kw"),
                            rs.getBigDecimal("total_amount"),
                            rs.getString("statement_status"),
                            rs.getTimestamp("issued_at")));
                }
            }
        }
        return rows;
    }

    public boolean cycleExists(Connection conn, int cycleId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement("SELECT 1 FROM dbo.billing_cycle WHERE cycle_id = ?")) {
            ps.setInt(1, cycleId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    public int countActiveStoreMeterMapsForCycle(Connection conn, int cycleId) throws Exception {
        String sql =
                "SELECT COUNT(*) " +
                "FROM dbo.tenant_meter_map tm " +
                "INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id " +
                "INNER JOIN dbo.billing_cycle bc ON bc.cycle_id = ? " +
                "WHERE tm.valid_from <= bc.cycle_end_date " +
                "  AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date) " +
                "  AND (ts.closed_on IS NULL OR ts.closed_on >= bc.cycle_start_date) " +
                "  AND (ts.opened_on IS NULL OR ts.opened_on <= bc.cycle_end_date)";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, cycleId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        }
    }

    public int countSnapshotMeasurementCandidates(Connection conn, int cycleId, String snapshotType) throws Exception {
        String sql =
                "WITH scoped AS ( " +
                "    SELECT tm.store_id, tm.meter_id, " +
                "           CASE WHEN ts.opened_on IS NULL OR ts.opened_on < bc.cycle_start_date THEN bc.cycle_start_date ELSE ts.opened_on END AS effective_start_date, " +
                "           CASE WHEN ts.closed_on IS NULL OR ts.closed_on > bc.cycle_end_date THEN bc.cycle_end_date ELSE ts.closed_on END AS effective_end_date " +
                "    FROM dbo.tenant_meter_map tm " +
                "    INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id " +
                "    INNER JOIN dbo.billing_cycle bc ON bc.cycle_id = ? " +
                "    WHERE tm.valid_from <= bc.cycle_end_date " +
                "      AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date) " +
                "      AND (ts.closed_on IS NULL OR ts.closed_on >= bc.cycle_start_date) " +
                "      AND (ts.opened_on IS NULL OR ts.opened_on <= bc.cycle_end_date) " +
                "), bounded AS ( " +
                "    SELECT store_id, meter_id, " +
                "           CASE WHEN ? = 'OPENING' THEN CAST(effective_start_date AS datetime2(0)) " +
                "                ELSE DATEADD(second, -1, DATEADD(day, 1, CAST(effective_end_date AS datetime2(0)))) END AS target_dt " +
                "    FROM scoped WHERE effective_end_date >= effective_start_date " +
                ") " +
                "SELECT COUNT(*) " +
                "FROM bounded b " +
                "WHERE EXISTS ( " +
                "    SELECT 1 FROM dbo.measurements ms " +
                "    WHERE ms.meter_id = b.meter_id " +
                "      AND ms.energy_consumed_total IS NOT NULL " +
                "      AND ms.measured_at BETWEEN DATEADD(day, -3, b.target_dt) AND DATEADD(day, 3, b.target_dt)" +
                ")";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, cycleId);
            ps.setString(2, snapshotType);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        }
    }

    public int countActiveContractsForCycle(Connection conn, int cycleId) throws Exception {
        String sql =
                "WITH cycle_window AS ( " +
                "    SELECT cycle_start_date, cycle_end_date FROM dbo.billing_cycle WHERE cycle_id = ? " +
                "), store_window AS ( " +
                "    SELECT ts.store_id, " +
                "           CASE WHEN ts.opened_on IS NULL OR ts.opened_on < cw.cycle_start_date THEN cw.cycle_start_date ELSE ts.opened_on END AS effective_start_date, " +
                "           CASE WHEN ts.closed_on IS NULL OR ts.closed_on > cw.cycle_end_date THEN cw.cycle_end_date ELSE ts.closed_on END AS effective_end_date " +
                "    FROM dbo.tenant_store ts CROSS JOIN cycle_window cw " +
                "    WHERE (ts.closed_on IS NULL OR ts.closed_on >= cw.cycle_start_date) " +
                "      AND (ts.opened_on IS NULL OR ts.opened_on <= cw.cycle_end_date) " +
                ") " +
                "SELECT COUNT(*) " +
                "FROM store_window sw " +
                "INNER JOIN dbo.tenant_billing_contract c ON c.store_id = sw.store_id " +
                " AND c.contract_start_date <= sw.effective_end_date " +
                " AND (c.contract_end_date IS NULL OR c.contract_end_date >= sw.effective_start_date) " +
                " AND c.is_active = 1 " +
                "WHERE sw.effective_end_date >= sw.effective_start_date";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, cycleId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        }
    }

    public int countClosingSnapshots(Connection conn, int cycleId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) FROM dbo.billing_meter_snapshot WHERE cycle_id = ? AND snapshot_type = 'CLOSING'")) {
            ps.setInt(1, cycleId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        }
    }

    public int countOpeningSnapshots(Connection conn, int cycleId) throws Exception {
        try (PreparedStatement ps = conn.prepareStatement(
                "SELECT COUNT(*) FROM dbo.billing_meter_snapshot WHERE cycle_id = ? AND snapshot_type = 'OPENING'")) {
            ps.setInt(1, cycleId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        }
    }
}
