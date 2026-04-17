USE [epms];
GO

ALTER PROCEDURE dbo.sp_generate_billing_meter_snapshot
    @cycle_id int,
    @snapshot_type varchar(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @snapshot_type NOT IN ('OPENING', 'CLOSING')
    BEGIN
        THROW 52000, 'Invalid snapshot type.', 1;
    END;

    ;WITH scoped AS (
        SELECT
            tm.store_id,
            tm.meter_id,
            tm.allocation_ratio,
            CASE
                WHEN ts.opened_on IS NULL OR ts.opened_on < bc.cycle_start_date THEN bc.cycle_start_date
                ELSE ts.opened_on
            END AS effective_start_date,
            CASE
                WHEN ts.closed_on IS NULL OR ts.closed_on > bc.cycle_end_date THEN bc.cycle_end_date
                ELSE ts.closed_on
            END AS effective_end_date
        FROM dbo.tenant_meter_map tm
        INNER JOIN dbo.tenant_store ts
            ON ts.store_id = tm.store_id
        INNER JOIN dbo.billing_cycle bc
            ON bc.cycle_id = @cycle_id
        WHERE tm.valid_from <= bc.cycle_end_date
          AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date)
          AND (ts.closed_on IS NULL OR ts.closed_on >= bc.cycle_start_date)
          AND (ts.opened_on IS NULL OR ts.opened_on <= bc.cycle_end_date)
    ),
    bounded AS (
        SELECT
            store_id,
            meter_id,
            allocation_ratio,
            effective_start_date,
            effective_end_date,
            CASE
                WHEN @snapshot_type = 'OPENING' THEN CAST(effective_start_date AS datetime2(0))
                ELSE DATEADD(second, -1, DATEADD(day, 1, CAST(effective_end_date AS datetime2(0))))
            END AS target_dt
        FROM scoped
        WHERE effective_end_date >= effective_start_date
    ),
    picked AS (
        SELECT
            b.store_id,
            b.meter_id,
            b.allocation_ratio,
            ms.measured_at,
            CAST(ms.energy_consumed_total AS decimal(18,3)) AS energy_total_kwh,
            ROW_NUMBER() OVER (
                PARTITION BY b.store_id, b.meter_id
                ORDER BY ABS(DATEDIFF(second, ms.measured_at, b.target_dt)) ASC, ms.measured_at DESC
            ) AS rn
        FROM bounded b
        INNER JOIN dbo.measurements ms
            ON ms.meter_id = b.meter_id
        WHERE ms.energy_consumed_total IS NOT NULL
          AND ms.measured_at BETWEEN DATEADD(day, -3, b.target_dt) AND DATEADD(day, 3, b.target_dt)
    )
    MERGE dbo.billing_meter_snapshot AS t
    USING (
        SELECT
            @cycle_id AS cycle_id,
            p.store_id,
            p.meter_id,
            @snapshot_type AS snapshot_type,
            p.measured_at AS snapshot_at,
            CAST(p.energy_total_kwh * p.allocation_ratio AS decimal(18,3)) AS energy_total_kwh,
            p.measured_at AS source_measurement_time
        FROM picked p
        WHERE p.rn = 1
    ) AS s
    ON t.cycle_id = s.cycle_id
       AND t.store_id = s.store_id
       AND t.meter_id = s.meter_id
       AND t.snapshot_type = s.snapshot_type
    WHEN MATCHED THEN
        UPDATE SET
            snapshot_at = s.snapshot_at,
            energy_total_kwh = s.energy_total_kwh,
            source_kind = 'AUTO',
            source_measurement_time = s.source_measurement_time,
            updated_at = sysdatetime()
    WHEN NOT MATCHED THEN
        INSERT (cycle_id, store_id, meter_id, snapshot_type, snapshot_at, energy_total_kwh, source_kind, source_measurement_time)
        VALUES (s.cycle_id, s.store_id, s.meter_id, s.snapshot_type, s.snapshot_at, s.energy_total_kwh, 'AUTO', s.source_measurement_time);
END
GO

ALTER PROCEDURE dbo.sp_generate_billing_statement
    @cycle_id int
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH cycle_window AS (
        SELECT cycle_id, cycle_start_date, cycle_end_date
        FROM dbo.billing_cycle
        WHERE cycle_id = @cycle_id
    ),
    store_window AS (
        SELECT
            ts.store_id,
            CASE
                WHEN ts.opened_on IS NULL OR ts.opened_on < cw.cycle_start_date THEN cw.cycle_start_date
                ELSE ts.opened_on
            END AS effective_start_date,
            CASE
                WHEN ts.closed_on IS NULL OR ts.closed_on > cw.cycle_end_date THEN cw.cycle_end_date
                ELSE ts.closed_on
            END AS effective_end_date
        FROM dbo.tenant_store ts
        CROSS JOIN cycle_window cw
        WHERE (ts.closed_on IS NULL OR ts.closed_on >= cw.cycle_start_date)
          AND (ts.opened_on IS NULL OR ts.opened_on <= cw.cycle_end_date)
    ),
    valid_store_window AS (
        SELECT store_id, effective_start_date, effective_end_date
        FROM store_window
        WHERE effective_end_date >= effective_start_date
    ),
    contract_pick AS (
        SELECT
            cw.cycle_id,
            c.store_id,
            c.contract_id,
            c.contracted_demand_kw,
            r.rate_id,
            r.basic_charge_amount,
            r.unit_price_per_kwh,
            r.demand_unit_price,
            r.vat_rate,
            r.fund_rate,
            ROW_NUMBER() OVER (
                PARTITION BY c.store_id
                ORDER BY c.contract_start_date DESC, c.contract_id DESC
            ) AS rn
        FROM cycle_window cw
        INNER JOIN valid_store_window sw
            ON 1 = 1
        INNER JOIN dbo.tenant_billing_contract c
            ON c.store_id = sw.store_id
           AND c.contract_start_date <= sw.effective_end_date
           AND (c.contract_end_date IS NULL OR c.contract_end_date >= sw.effective_start_date)
           AND c.is_active = 1
        INNER JOIN dbo.billing_rate r
            ON r.rate_id = c.rate_id
           AND r.effective_from <= sw.effective_end_date
           AND (r.effective_to IS NULL OR r.effective_to >= sw.effective_start_date)
           AND r.is_active = 1
    ),
    openings AS (
        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS opening_kwh
        FROM dbo.billing_meter_snapshot
        WHERE cycle_id = @cycle_id AND snapshot_type = 'OPENING'
        GROUP BY cycle_id, store_id
    ),
    closings AS (
        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS closing_kwh
        FROM dbo.billing_meter_snapshot
        WHERE cycle_id = @cycle_id AND snapshot_type = 'CLOSING'
        GROUP BY cycle_id, store_id
    ),
    peak AS (
        SELECT
            tm.store_id,
            MAX(CAST(ms.active_power_total AS decimal(18,3)) * tm.allocation_ratio) AS peak_demand_kw
        FROM valid_store_window sw
        INNER JOIN dbo.tenant_meter_map tm
            ON tm.store_id = sw.store_id
           AND tm.valid_from <= sw.effective_end_date
           AND (tm.valid_to IS NULL OR tm.valid_to >= sw.effective_start_date)
        INNER JOIN dbo.measurements ms
            ON ms.meter_id = tm.meter_id
           AND ms.measured_at >= sw.effective_start_date
           AND ms.measured_at < DATEADD(day, 1, sw.effective_end_date)
        WHERE ms.active_power_total IS NOT NULL
        GROUP BY tm.store_id
    )
    MERGE dbo.billing_statement AS t
    USING (
        SELECT
            cp.cycle_id,
            cp.store_id,
            cp.contract_id,
            ISNULL(o.opening_kwh, 0) AS opening_kwh,
            ISNULL(c.closing_kwh, 0) AS closing_kwh,
            CASE
                WHEN ISNULL(c.closing_kwh, 0) >= ISNULL(o.opening_kwh, 0)
                    THEN ISNULL(c.closing_kwh, 0) - ISNULL(o.opening_kwh, 0)
                ELSE 0
            END AS usage_kwh,
            p.peak_demand_kw,
            cp.basic_charge_amount,
            CAST(CASE
                WHEN ISNULL(c.closing_kwh, 0) >= ISNULL(o.opening_kwh, 0)
                    THEN (ISNULL(c.closing_kwh, 0) - ISNULL(o.opening_kwh, 0)) * cp.unit_price_per_kwh
                ELSE 0
            END AS decimal(18,2)) AS energy_charge_amount,
            CAST(ISNULL(p.peak_demand_kw, ISNULL(cp.contracted_demand_kw, 0)) * cp.demand_unit_price AS decimal(18,2)) AS demand_charge_amount,
            cp.vat_rate,
            cp.fund_rate
        FROM contract_pick cp
        LEFT JOIN openings o ON o.cycle_id = cp.cycle_id AND o.store_id = cp.store_id
        LEFT JOIN closings c ON c.cycle_id = cp.cycle_id AND c.store_id = cp.store_id
        LEFT JOIN peak p ON p.store_id = cp.store_id
        WHERE cp.rn = 1
    ) AS s
    ON t.cycle_id = s.cycle_id AND t.store_id = s.store_id
    WHEN MATCHED THEN
        UPDATE SET
            contract_id = s.contract_id,
            opening_kwh = s.opening_kwh,
            closing_kwh = s.closing_kwh,
            usage_kwh = s.usage_kwh,
            peak_demand_kw = s.peak_demand_kw,
            basic_charge_amount = s.basic_charge_amount,
            energy_charge_amount = s.energy_charge_amount,
            demand_charge_amount = s.demand_charge_amount,
            adjustment_amount = ISNULL(t.adjustment_amount, 0),
            vat_amount = CAST((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)) * s.vat_rate AS decimal(18,2)),
            fund_amount = CAST((s.energy_charge_amount) * s.fund_rate AS decimal(18,2)),
            total_amount = CAST(
                s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)
                + ((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)) * s.vat_rate)
                + ((s.energy_charge_amount) * s.fund_rate)
                AS decimal(18,2)
            ),
            updated_at = sysdatetime()
    WHEN NOT MATCHED THEN
        INSERT (
            cycle_id, store_id, contract_id, opening_kwh, closing_kwh, usage_kwh, peak_demand_kw,
            basic_charge_amount, energy_charge_amount, demand_charge_amount, adjustment_amount,
            vat_amount, fund_amount, total_amount
        )
        VALUES (
            s.cycle_id, s.store_id, s.contract_id, s.opening_kwh, s.closing_kwh, s.usage_kwh, s.peak_demand_kw,
            s.basic_charge_amount, s.energy_charge_amount, s.demand_charge_amount, 0,
            CAST((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount) * s.vat_rate AS decimal(18,2)),
            CAST((s.energy_charge_amount) * s.fund_rate AS decimal(18,2)),
            CAST(
                s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount
                + ((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount) * s.vat_rate)
                + ((s.energy_charge_amount) * s.fund_rate)
                AS decimal(18,2)
            )
        );
END
GO
