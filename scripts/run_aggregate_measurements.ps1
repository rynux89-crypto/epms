param(
    [ValidateSet('hourly','rollup','all')]
    [string]$Mode = 'all',
    [string]$Server = '',
    [string]$Database = '',
    [string]$User = '',
    [string]$Password = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-Value {
    param(
        [string]$Explicit,
        [string[]]$EnvNames,
        [string]$Default = ''
    )
    if ($Explicit -and $Explicit.Trim() -ne '') { return $Explicit.Trim() }
    foreach ($name in $EnvNames) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value -and $value.Trim() -ne '') { return $value.Trim() }
    }
    return $Default
}

function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Message
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    Write-Output $line
}

function Invoke-SqlCmdText {
    param([string]$Sql)

    $arguments = @(
        '-S', $script:DbServer,
        '-d', $script:DbName,
        '-U', $script:DbUser,
        '-P', $script:DbPassword,
        '-b',
        '-Q', $Sql
    )
    & sqlcmd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed with exit code $LASTEXITCODE"
    }
}

$rootPath = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$logDir = Join-Path $rootPath 'logs'
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
$script:LogPath = Join-Path $logDir 'aggregate_measurements.log'

$script:DbServer = Resolve-Value -Explicit $Server -EnvNames @('EPMS_DB_SERVER','EPMS_IMPORT_DB_SERVER') -Default 'localhost,1433'
$script:DbName = Resolve-Value -Explicit $Database -EnvNames @('EPMS_DB_NAME','EPMS_IMPORT_DB_NAME') -Default 'epms'
$script:DbUser = Resolve-Value -Explicit $User -EnvNames @('EPMS_DB_USER','EPMS_IMPORT_DB_USER') -Default 'sa'
$script:DbPassword = Resolve-Value -Explicit $Password -EnvNames @('EPMS_DB_PASSWORD','EPMS_IMPORT_DB_PASSWORD') -Default '1234'

Write-Log 'info' ("aggregate run start mode={0} server={1} db={2}" -f $Mode, $script:DbServer, $script:DbName)

try {
    switch ($Mode) {
        'hourly' {
            Invoke-SqlCmdText "EXEC dbo.sp_aggregate_hourly_measurements;"
            Write-Log 'info' 'hourly aggregation completed'
        }
        'rollup' {
            Invoke-SqlCmdText "EXEC dbo.sp_aggregate_daily_measurements;"
            Write-Log 'info' 'daily aggregation completed'
            $today = Get-Date
            if ($today.Day -eq 1) {
                Invoke-SqlCmdText "EXEC dbo.sp_aggregate_monthly_measurements;"
                Write-Log 'info' 'monthly aggregation completed'
            }
            if ($today.DayOfYear -eq 1) {
                Invoke-SqlCmdText "EXEC dbo.sp_aggregate_yearly_measurements;"
                Write-Log 'info' 'yearly aggregation completed'
            }
        }
        'all' {
            Invoke-SqlCmdText "EXEC dbo.sp_aggregate_hourly_measurements;"
            Write-Log 'info' 'hourly aggregation completed'
            Invoke-SqlCmdText "EXEC dbo.sp_aggregate_daily_measurements;"
            Write-Log 'info' 'daily aggregation completed'
            $today = Get-Date
            if ($today.Day -eq 1) {
                Invoke-SqlCmdText "EXEC dbo.sp_aggregate_monthly_measurements;"
                Write-Log 'info' 'monthly aggregation completed'
            }
            if ($today.DayOfYear -eq 1) {
                Invoke-SqlCmdText "EXEC dbo.sp_aggregate_yearly_measurements;"
                Write-Log 'info' 'yearly aggregation completed'
            }
        }
    }
    Write-Log 'info' 'aggregate run finished'
    exit 0
} catch {
    Write-Log 'error' $_.Exception.Message
    throw
}
