param(
    [string]$ConfigPath = '',
    [string]$Server = '',
    [string]$Database = '',
    [string]$User = '',
    [string]$Password = '',
    [string]$BackupDir = 'C:\backup',
    [int]$RetainDays = 7
)

$ErrorActionPreference = 'Stop'

function Resolve-Value {
    param(
        [string]$Explicit,
        [string[]]$EnvNames,
        [string]$ConfigValue = '',
        [string]$Default = ''
    )
    if ($Explicit -and $Explicit.Trim() -ne '') { return $Explicit.Trim() }
    foreach ($name in $EnvNames) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value -and $value.Trim() -ne '') { return $value.Trim() }
    }
    if ($ConfigValue -and $ConfigValue.Trim() -ne '') { return $ConfigValue.Trim() }
    return $Default
}

function Get-TomlConfig {
    param([string]$Path)

    $result = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    $section = ''
    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }

        if ($line -match '^\[(.+)\]$') {
            $section = $matches[1].Trim()
            continue
        }

        if ($line -notmatch '^([A-Za-z0-9_.-]+)\s*=\s*(.+)$') { continue }

        $key = $matches[1].Trim()
        $value = $matches[2].Trim()

        $commentIndex = $value.IndexOf(' #')
        if ($commentIndex -ge 0) {
            $value = $value.Substring(0, $commentIndex).Trim()
        }

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $fullKey = if ($section) { "$section.$key" } else { $key }
        $result[$fullKey] = $value
    }

    return $result
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

function Invoke-Sql {
    param([string]$Sql)

    $arguments = @(
        '-S', $script:DbServer,
        '-d', 'master',
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
$resolvedConfigPath = if ($ConfigPath -and $ConfigPath.Trim() -ne '') {
    $ConfigPath.Trim()
} else {
    Join-Path $rootPath 'WEB-INF\config.toml'
}
$config = Get-TomlConfig -Path $resolvedConfigPath
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
$script:LogPath = Join-Path $logDir 'db_backup.log'

$script:DbServer = Resolve-Value -Explicit $Server -EnvNames @('EPMS_DB_SERVER','EPMS_IMPORT_DB_SERVER') -ConfigValue $config['database.server'] -Default 'localhost,1433'
$script:DbName = Resolve-Value -Explicit $Database -EnvNames @('EPMS_DB_NAME','EPMS_IMPORT_DB_NAME') -ConfigValue $config['database.name'] -Default 'EPMS'
$script:DbUser = Resolve-Value -Explicit $User -EnvNames @('EPMS_DB_USER','EPMS_IMPORT_DB_USER') -ConfigValue $config['database.user'] -Default 'sa'
$script:DbPassword = Resolve-Value -Explicit $Password -EnvNames @('EPMS_DB_PASSWORD','EPMS_IMPORT_DB_PASSWORD') -ConfigValue $config['database.password'] -Default '1234'
$BackupDir = Resolve-Value -Explicit $BackupDir -EnvNames @('EPMS_BACKUP_DIR') -ConfigValue $config['backup.dir'] -Default 'C:\backup'

$retainValue = if ($PSBoundParameters.ContainsKey('RetainDays')) {
    [string]$RetainDays
} else {
    Resolve-Value -Explicit '' -EnvNames @('EPMS_BACKUP_RETAIN_DAYS') -ConfigValue $config['backup.retain_days'] -Default '7'
}

try {
    $RetainDays = [int]$retainValue
} catch {
    throw "Invalid retain days value: $retainValue"
}

if ($RetainDays -lt 1) {
    throw 'RetainDays must be at least 1.'
}

if (!(Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = Join-Path $BackupDir ("{0}_{1}.bak" -f $script:DbName.ToUpperInvariant(), $timestamp)
$escapedBackupFile = $backupFile.Replace("'", "''")
$escapedDbName = $script:DbName.Replace("]", "]]")

Write-Log 'info' ("backup start server={0} db={1} file={2}" -f $script:DbServer, $script:DbName, $backupFile)
Write-Log 'info' ("config source={0}" -f ($(if (Test-Path -LiteralPath $resolvedConfigPath) { $resolvedConfigPath } else { 'defaults/env/params only' })))

$backupSql = @"
BACKUP DATABASE [$escapedDbName]
TO DISK = N'$escapedBackupFile'
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
"@

Invoke-Sql $backupSql

$cutoff = (Get-Date).AddDays(-$RetainDays)
$deletedFiles = @()
Get-ChildItem -Path $BackupDir -Filter ("{0}_*.bak" -f $script:DbName.ToUpperInvariant()) -File | Where-Object {
    $_.LastWriteTime -lt $cutoff
} | ForEach-Object {
    $deletedFiles += $_.FullName
    Remove-Item -LiteralPath $_.FullName -Force
}

Write-Log 'info' ("backup completed file={0}" -f $backupFile)
if ($deletedFiles.Count -gt 0) {
    Write-Log 'info' ("deleted old backups count={0}" -f $deletedFiles.Count)
} else {
    Write-Log 'info' 'deleted old backups count=0'
}
