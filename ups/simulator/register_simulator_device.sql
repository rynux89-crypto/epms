USE UPS_MONITOR;
GO

DECLARE @profile_id int;

SELECT @profile_id = profile_id
FROM dbo.ups_modbus_profile
WHERE profile_name = N'Schneider Easy UPS 3-Phase Modular';

IF @profile_id IS NULL
BEGIN
    RAISERROR('Schneider Easy UPS 3-Phase Modular profile not found. Run scripts/create_schneider_easy_ups_profile.sql first.', 16, 1);
    RETURN;
END

IF NOT EXISTS (
    SELECT 1
    FROM dbo.ups_device
    WHERE ip_address = '127.0.0.1'
      AND modbus_port = 1502
      AND unit_id = 1
)
BEGIN
    INSERT INTO dbo.ups_device
        (ups_name, location, ip_address, modbus_port, unit_id, profile_id, rated_capacity_kva, enabled, updated_at)
    VALUES
        (N'UPS Simulator', N'Local test simulator', '127.0.0.1', 1502, 1, @profile_id, 100, 1, sysdatetime());
END
ELSE
BEGIN
    UPDATE dbo.ups_device
    SET ups_name = N'UPS Simulator',
        location = N'Local test simulator',
        profile_id = @profile_id,
        enabled = 1,
        updated_at = sysdatetime()
    WHERE ip_address = '127.0.0.1'
      AND modbus_port = 1502
      AND unit_id = 1;
END
GO
