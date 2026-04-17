SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE [epms];
GO

/*==============================================================
  EPMS Tenant Billing Subschema
  Purpose:
    - Department-store tenant electricity settlement
    - Keep metering tables as-is and add billing-side tables
==============================================================*/

IF OBJECT_ID(N'dbo.tenant_store', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tenant_store (
        store_id int IDENTITY(1,1) NOT NULL,
        store_code varchar(50) NOT NULL,
        store_name nvarchar(150) NOT NULL,
        business_number varchar(30) NULL,
        building_name varchar(100) NULL,
        floor_name varchar(50) NULL,
        room_name varchar(50) NULL,
        zone_name varchar(100) NULL,
        category_name varchar(100) NULL,
        contact_name nvarchar(80) NULL,
        contact_phone varchar(50) NULL,
        status varchar(20) NOT NULL CONSTRAINT DF_tenant_store_status DEFAULT ('ACTIVE'),
        opened_on date NULL,
        closed_on date NULL,
        notes nvarchar(500) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_store_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_store_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_tenant_store PRIMARY KEY CLUSTERED (store_id ASC),
        CONSTRAINT UX_tenant_store_code UNIQUE NONCLUSTERED (store_code ASC)
    );

    CREATE INDEX IX_tenant_store_building_status ON dbo.tenant_store(building_name ASC, status ASC);
END
GO

IF OBJECT_ID(N'dbo.tenant_meter_map', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tenant_meter_map (
        map_id bigint IDENTITY(1,1) NOT NULL,
        store_id int NOT NULL,
        meter_id int NOT NULL,
        billing_scope varchar(20) NOT NULL CONSTRAINT DF_tenant_meter_map_scope DEFAULT ('DIRECT'),
        allocation_ratio decimal(9,6) NOT NULL CONSTRAINT DF_tenant_meter_map_ratio DEFAULT ((1.000000)),
        is_primary bit NOT NULL CONSTRAINT DF_tenant_meter_map_primary DEFAULT ((0)),
        valid_from date NOT NULL,
        valid_to date NULL,
        notes nvarchar(300) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_meter_map_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_meter_map_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_tenant_meter_map PRIMARY KEY CLUSTERED (map_id ASC),
        CONSTRAINT FK_tenant_meter_map_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),
        CONSTRAINT FK_tenant_meter_map_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id),
        CONSTRAINT CK_tenant_meter_map_ratio CHECK (allocation_ratio > 0 AND allocation_ratio <= 1.000000),
        CONSTRAINT CK_tenant_meter_map_valid_range CHECK (valid_to IS NULL OR valid_to >= valid_from)
    );

    CREATE INDEX IX_tenant_meter_map_store_dates ON dbo.tenant_meter_map(store_id ASC, valid_from ASC, valid_to ASC);
    CREATE INDEX IX_tenant_meter_map_meter_dates ON dbo.tenant_meter_map(meter_id ASC, valid_from ASC, valid_to ASC);
END
GO

IF OBJECT_ID(N'dbo.billing_cycle', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.billing_cycle (
        cycle_id int IDENTITY(1,1) NOT NULL,
        cycle_code varchar(20) NOT NULL,
        period_type varchar(20) NOT NULL CONSTRAINT DF_billing_cycle_period_type DEFAULT ('MONTHLY'),
        cycle_start_date date NOT NULL,
        cycle_end_date date NOT NULL,
        reading_closed_at datetime2(0) NULL,
        status varchar(20) NOT NULL CONSTRAINT DF_billing_cycle_status DEFAULT ('DRAFT'),
        notes nvarchar(300) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_cycle_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_cycle_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_billing_cycle PRIMARY KEY CLUSTERED (cycle_id ASC),
        CONSTRAINT UX_billing_cycle_code UNIQUE NONCLUSTERED (cycle_code ASC),
        CONSTRAINT CK_billing_cycle_range CHECK (cycle_end_date >= cycle_start_date)
    );

    CREATE INDEX IX_billing_cycle_dates ON dbo.billing_cycle(cycle_start_date ASC, cycle_end_date ASC, status ASC);
END
GO

IF OBJECT_ID(N'dbo.billing_rate', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.billing_rate (
        rate_id int IDENTITY(1,1) NOT NULL,
        rate_code varchar(50) NOT NULL,
        rate_name nvarchar(150) NOT NULL,
        effective_from date NOT NULL,
        effective_to date NULL,
        currency_code varchar(10) NOT NULL CONSTRAINT DF_billing_rate_currency DEFAULT ('KRW'),
        unit_price_per_kwh decimal(18,4) NOT NULL CONSTRAINT DF_billing_rate_unit_price DEFAULT ((0)),
        basic_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_rate_basic DEFAULT ((0)),
        demand_unit_price decimal(18,4) NOT NULL CONSTRAINT DF_billing_rate_demand DEFAULT ((0)),
        vat_rate decimal(9,6) NOT NULL CONSTRAINT DF_billing_rate_vat DEFAULT ((0.100000)),
        fund_rate decimal(9,6) NOT NULL CONSTRAINT DF_billing_rate_fund DEFAULT ((0.037000)),
        is_active bit NOT NULL CONSTRAINT DF_billing_rate_active DEFAULT ((1)),
        notes nvarchar(500) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_rate_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_rate_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_billing_rate PRIMARY KEY CLUSTERED (rate_id ASC),
        CONSTRAINT UX_billing_rate_code UNIQUE NONCLUSTERED (rate_code ASC),
        CONSTRAINT CK_billing_rate_effective CHECK (effective_to IS NULL OR effective_to >= effective_from)
    );

    CREATE INDEX IX_billing_rate_effective ON dbo.billing_rate(effective_from ASC, effective_to ASC, is_active ASC);
END
GO

IF OBJECT_ID(N'dbo.tenant_billing_contract', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tenant_billing_contract (
        contract_id bigint IDENTITY(1,1) NOT NULL,
        store_id int NOT NULL,
        rate_id int NOT NULL,
        contract_start_date date NOT NULL,
        contract_end_date date NULL,
        contracted_demand_kw decimal(18,3) NULL,
        billing_day tinyint NULL,
        shared_area_ratio decimal(9,6) NOT NULL CONSTRAINT DF_tenant_billing_contract_shared_ratio DEFAULT ((0)),
        is_active bit NOT NULL CONSTRAINT DF_tenant_billing_contract_active DEFAULT ((1)),
        notes nvarchar(500) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_billing_contract_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_billing_contract_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_tenant_billing_contract PRIMARY KEY CLUSTERED (contract_id ASC),
        CONSTRAINT FK_tenant_billing_contract_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),
        CONSTRAINT FK_tenant_billing_contract_rate FOREIGN KEY (rate_id) REFERENCES dbo.billing_rate(rate_id),
        CONSTRAINT CK_tenant_billing_contract_dates CHECK (contract_end_date IS NULL OR contract_end_date >= contract_start_date)
    );

    CREATE INDEX IX_tenant_billing_contract_store_dates ON dbo.tenant_billing_contract(store_id ASC, contract_start_date ASC, contract_end_date ASC, is_active ASC);
END
GO

IF OBJECT_ID(N'dbo.billing_meter_snapshot', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.billing_meter_snapshot (
        snapshot_id bigint IDENTITY(1,1) NOT NULL,
        cycle_id int NOT NULL,
        store_id int NOT NULL,
        meter_id int NOT NULL,
        snapshot_type varchar(20) NOT NULL,
        snapshot_at datetime2(0) NOT NULL,
        energy_total_kwh decimal(18,3) NOT NULL,
        source_kind varchar(20) NOT NULL CONSTRAINT DF_billing_meter_snapshot_source DEFAULT ('AUTO'),
        source_measurement_time datetime2(0) NULL,
        note nvarchar(300) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_meter_snapshot_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_meter_snapshot_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_billing_meter_snapshot PRIMARY KEY CLUSTERED (snapshot_id ASC),
        CONSTRAINT FK_billing_meter_snapshot_cycle FOREIGN KEY (cycle_id) REFERENCES dbo.billing_cycle(cycle_id),
        CONSTRAINT FK_billing_meter_snapshot_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),
        CONSTRAINT FK_billing_meter_snapshot_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id),
        CONSTRAINT CK_billing_meter_snapshot_type CHECK (snapshot_type IN ('OPENING', 'CLOSING'))
    );

    CREATE UNIQUE INDEX UX_billing_meter_snapshot_cycle_store_meter_type
        ON dbo.billing_meter_snapshot(cycle_id ASC, store_id ASC, meter_id ASC, snapshot_type ASC);
    CREATE INDEX IX_billing_meter_snapshot_meter_time
        ON dbo.billing_meter_snapshot(meter_id ASC, snapshot_at DESC);
END
GO

IF OBJECT_ID(N'dbo.billing_statement', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.billing_statement (
        statement_id bigint IDENTITY(1,1) NOT NULL,
        cycle_id int NOT NULL,
        store_id int NOT NULL,
        contract_id bigint NULL,
        opening_kwh decimal(18,3) NOT NULL CONSTRAINT DF_billing_statement_opening DEFAULT ((0)),
        closing_kwh decimal(18,3) NOT NULL CONSTRAINT DF_billing_statement_closing DEFAULT ((0)),
        usage_kwh decimal(18,3) NOT NULL CONSTRAINT DF_billing_statement_usage DEFAULT ((0)),
        peak_demand_kw decimal(18,3) NULL,
        basic_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_basic DEFAULT ((0)),
        energy_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_energy DEFAULT ((0)),
        demand_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_demand DEFAULT ((0)),
        adjustment_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_adjust DEFAULT ((0)),
        vat_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_vat DEFAULT ((0)),
        fund_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_fund DEFAULT ((0)),
        total_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_total DEFAULT ((0)),
        statement_status varchar(20) NOT NULL CONSTRAINT DF_billing_statement_status DEFAULT ('DRAFT'),
        issued_at datetime2(0) NULL,
        confirmed_at datetime2(0) NULL,
        notes nvarchar(500) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_statement_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_statement_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_billing_statement PRIMARY KEY CLUSTERED (statement_id ASC),
        CONSTRAINT FK_billing_statement_cycle FOREIGN KEY (cycle_id) REFERENCES dbo.billing_cycle(cycle_id),
        CONSTRAINT FK_billing_statement_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),
        CONSTRAINT FK_billing_statement_contract FOREIGN KEY (contract_id) REFERENCES dbo.tenant_billing_contract(contract_id),
        CONSTRAINT UX_billing_statement_cycle_store UNIQUE NONCLUSTERED (cycle_id ASC, store_id ASC)
    );

    CREATE INDEX IX_billing_statement_status ON dbo.billing_statement(statement_status ASC, cycle_id ASC);
END
GO

IF OBJECT_ID(N'dbo.billing_statement_line', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.billing_statement_line (
        line_id bigint IDENTITY(1,1) NOT NULL,
        statement_id bigint NOT NULL,
        line_type varchar(30) NOT NULL,
        description nvarchar(200) NOT NULL,
        quantity decimal(18,3) NULL,
        unit_price decimal(18,4) NULL,
        amount decimal(18,2) NOT NULL,
        sort_order int NOT NULL CONSTRAINT DF_billing_statement_line_sort DEFAULT ((0)),
        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_statement_line_created_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_billing_statement_line PRIMARY KEY CLUSTERED (line_id ASC),
        CONSTRAINT FK_billing_statement_line_statement FOREIGN KEY (statement_id) REFERENCES dbo.billing_statement(statement_id)
    );

    CREATE INDEX IX_billing_statement_line_statement ON dbo.billing_statement_line(statement_id ASC, sort_order ASC);
END
GO

IF OBJECT_ID(N'dbo.vw_tenant_billing_meter_usage', N'V') IS NULL
EXEC('
CREATE VIEW dbo.vw_tenant_billing_meter_usage
AS
SELECT
    ts.store_id,
    ts.store_code,
    ts.store_name,
    tm.map_id,
    tm.billing_scope,
    tm.allocation_ratio,
    tm.valid_from,
    tm.valid_to,
    m.meter_id,
    m.name AS meter_name,
    m.panel_name,
    m.building_name,
    m.usage_type
FROM dbo.tenant_meter_map tm
INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id
INNER JOIN dbo.meters m ON m.meter_id = tm.meter_id;
');
GO

IF OBJECT_ID(N'dbo.sp_generate_billing_meter_snapshot', N'P') IS NULL
EXEC('
CREATE PROCEDURE dbo.sp_generate_billing_meter_snapshot
    @cycle_id int,
    @snapshot_type varchar(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @target_date datetime2(0);

    SELECT @target_date =
        CASE
            WHEN @snapshot_type = ''OPENING'' THEN CAST(cycle_start_date AS datetime2(0))
            WHEN @snapshot_type = ''CLOSING'' THEN DATEADD(second, -1, DATEADD(day, 1, CAST(cycle_end_date AS datetime2(0))))
            ELSE NULL
        END
    FROM dbo.billing_cycle
    WHERE cycle_id = @cycle_id;

    IF @target_date IS NULL
    BEGIN
        THROW 52000, ''Invalid cycle or snapshot type.'', 1;
    END;

    ;WITH active_map AS (
        SELECT
            tm.store_id,
            tm.meter_id,
            tm.allocation_ratio
        FROM dbo.tenant_meter_map tm
        INNER JOIN dbo.billing_cycle bc
            ON bc.cycle_id = @cycle_id
        WHERE tm.valid_from <= bc.cycle_end_date
          AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date)
    ),
    picked AS (
        SELECT
            am.store_id,
            am.meter_id,
            am.allocation_ratio,
            ms.measured_at,
            CAST(ms.energy_consumed_total AS decimal(18,3)) AS energy_total_kwh,
            ROW_NUMBER() OVER (
                PARTITION BY am.store_id, am.meter_id
                ORDER BY ABS(DATEDIFF(second, ms.measured_at, @target_date)) ASC, ms.measured_at DESC
            ) AS rn
        FROM active_map am
        INNER JOIN dbo.measurements ms
            ON ms.meter_id = am.meter_id
        WHERE ms.energy_consumed_total IS NOT NULL
          AND ms.measured_at BETWEEN DATEADD(day, -3, @target_date) AND DATEADD(day, 3, @target_date)
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
            source_kind = ''AUTO'',
            source_measurement_time = s.source_measurement_time,
            updated_at = sysdatetime()
    WHEN NOT MATCHED THEN
        INSERT (cycle_id, store_id, meter_id, snapshot_type, snapshot_at, energy_total_kwh, source_kind, source_measurement_time)
        VALUES (s.cycle_id, s.store_id, s.meter_id, s.snapshot_type, s.snapshot_at, s.energy_total_kwh, ''AUTO'', s.source_measurement_time);
END
');
GO

IF OBJECT_ID(N'dbo.sp_generate_billing_statement', N'P') IS NULL
EXEC('
CREATE PROCEDURE dbo.sp_generate_billing_statement
    @cycle_id int
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH contract_pick AS (
        SELECT
            bc.cycle_id,
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
        FROM dbo.billing_cycle bc
        INNER JOIN dbo.tenant_billing_contract c
            ON c.contract_start_date <= bc.cycle_end_date
           AND (c.contract_end_date IS NULL OR c.contract_end_date >= bc.cycle_start_date)
           AND c.is_active = 1
        INNER JOIN dbo.billing_rate r
            ON r.rate_id = c.rate_id
           AND r.effective_from <= bc.cycle_end_date
           AND (r.effective_to IS NULL OR r.effective_to >= bc.cycle_start_date)
           AND r.is_active = 1
        WHERE bc.cycle_id = @cycle_id
    ),
    openings AS (
        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS opening_kwh
        FROM dbo.billing_meter_snapshot
        WHERE cycle_id = @cycle_id AND snapshot_type = ''OPENING''
        GROUP BY cycle_id, store_id
    ),
    closings AS (
        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS closing_kwh
        FROM dbo.billing_meter_snapshot
        WHERE cycle_id = @cycle_id AND snapshot_type = ''CLOSING''
        GROUP BY cycle_id, store_id
    ),
    peak AS (
        SELECT
            tm.store_id,
            MAX(CAST(ms.active_power_total AS decimal(18,3)) * tm.allocation_ratio) AS peak_demand_kw
        FROM dbo.billing_cycle bc
        INNER JOIN dbo.tenant_meter_map tm
            ON tm.valid_from <= bc.cycle_end_date
           AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date)
        INNER JOIN dbo.measurements ms
            ON ms.meter_id = tm.meter_id
           AND ms.measured_at >= bc.cycle_start_date
           AND ms.measured_at < DATEADD(day, 1, bc.cycle_end_date)
        WHERE bc.cycle_id = @cycle_id
          AND ms.active_power_total IS NOT NULL
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
');
GO
