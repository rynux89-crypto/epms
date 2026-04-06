param(
    [string]$AppRoot = '',
    [string]$DbServer = '',
    [string]$DbName = 'epms',
    [string]$DbUser = '',
    [string]$DbPassword = '',
    [string]$HourlyTaskName = 'EPMS Aggregate Hourly',
    [string]$RollupTaskName = 'EPMS Aggregate Rollup',
    [string]$HourlyStartBoundary = '',
    [string]$RollupStartBoundary = '',
    [switch]$SkipImmediateRun
)

$ErrorActionPreference = 'Stop'

function Resolve-AppRoot {
    param([string]$ExplicitRoot)
    if ($ExplicitRoot -and $ExplicitRoot.Trim() -ne '') {
        return (Resolve-Path $ExplicitRoot.Trim()).Path
    }
    return (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
}

function Escape-Xml {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape($Value)
}

function Write-Info {
    param([string]$Message)
    Write-Output ("[INFO] {0}" -f $Message)
}

function Write-TempXml {
    param(
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::Unicode)
}

function Register-TaskFromXml {
    param(
        [string]$TaskName,
        [string]$XmlPath
    )
    & schtasks /Create /F /TN $TaskName /XML $XmlPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to register scheduled task: $TaskName"
    }
}

function Build-HourlyTaskXml {
    param(
        [string]$CommandPath,
        [string]$StartBoundary
    )
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>EPMS</Author>
    <Description>Run EPMS hourly aggregation every 15 minutes.</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT15M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$(Escape-Xml $StartBoundary)</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>/c ""$(Escape-Xml $CommandPath)""</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

function Build-RollupTaskXml {
    param(
        [string]$CommandPath,
        [string]$StartBoundary
    )
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>EPMS</Author>
    <Description>Run EPMS daily rollup aggregation and monthly/yearly rollups when applicable.</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$(Escape-Xml $StartBoundary)</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>/c ""$(Escape-Xml $CommandPath)""</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

$resolvedAppRoot = Resolve-AppRoot -ExplicitRoot $AppRoot
$scriptsDir = Join-Path $resolvedAppRoot 'scripts'
$aggregateScript = Join-Path $scriptsDir 'run_aggregate_measurements.ps1'

if (!(Test-Path $aggregateScript)) {
    throw "Aggregate script not found: $aggregateScript"
}

$resolvedDbServer = if ($DbServer -and $DbServer.Trim() -ne '') { $DbServer.Trim() } else { 'localhost,1433' }
$resolvedDbName = if ($DbName -and $DbName.Trim() -ne '') { $DbName.Trim() } else { 'epms' }
$resolvedDbUser = if ($DbUser -and $DbUser.Trim() -ne '') { $DbUser.Trim() } else { 'sa' }
$resolvedDbPassword = if ($DbPassword -and $DbPassword.Trim() -ne '') { $DbPassword } else { '1234' }

$hourlyCmdPath = Join-Path $scriptsDir 'run_aggregate_hourly.cmd'
$rollupCmdPath = Join-Path $scriptsDir 'run_aggregate_rollup.cmd'

$hourlyCmd = @(
    '@echo off',
    ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode hourly -Server "{1}" -Database "{2}" -User "{3}" -Password "{4}"' -f $aggregateScript, $resolvedDbServer, $resolvedDbName, $resolvedDbUser, $resolvedDbPassword)
)
$rollupCmd = @(
    '@echo off',
    ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode rollup -Server "{1}" -Database "{2}" -User "{3}" -Password "{4}"' -f $aggregateScript, $resolvedDbServer, $resolvedDbName, $resolvedDbUser, $resolvedDbPassword)
)

Set-Content -Path $hourlyCmdPath -Value $hourlyCmd -Encoding ASCII
Set-Content -Path $rollupCmdPath -Value $rollupCmd -Encoding ASCII

$now = Get-Date
if (-not $HourlyStartBoundary) {
    $minuteBlock = [math]::Ceiling(($now.Minute + 1) / 15.0) * 15
    $hourlyStart = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $now.Hour -Minute 0 -Second 0
    $hourlyStart = $hourlyStart.AddMinutes($minuteBlock)
    if ($hourlyStart -le $now) {
        $hourlyStart = $hourlyStart.AddMinutes(15)
    }
    $HourlyStartBoundary = $hourlyStart.ToString('yyyy-MM-ddTHH:mm:ss')
}
if (-not $RollupStartBoundary) {
    $rollupStart = (Get-Date -Hour 0 -Minute 10 -Second 0)
    if ($rollupStart -le $now) {
        $rollupStart = $rollupStart.AddDays(1)
    }
    $RollupStartBoundary = $rollupStart.ToString('yyyy-MM-ddTHH:mm:ss')
}

$hourlyXmlPath = Join-Path $env:TEMP 'epms_aggregate_hourly_task.xml'
$rollupXmlPath = Join-Path $env:TEMP 'epms_aggregate_rollup_task.xml'

Write-TempXml -Path $hourlyXmlPath -Content (Build-HourlyTaskXml -CommandPath $hourlyCmdPath -StartBoundary $HourlyStartBoundary)
Write-TempXml -Path $rollupXmlPath -Content (Build-RollupTaskXml -CommandPath $rollupCmdPath -StartBoundary $RollupStartBoundary)

Write-Info ("registering hourly task: {0}" -f $HourlyTaskName)
Register-TaskFromXml -TaskName $HourlyTaskName -XmlPath $hourlyXmlPath

Write-Info ("registering rollup task: {0}" -f $RollupTaskName)
Register-TaskFromXml -TaskName $RollupTaskName -XmlPath $rollupXmlPath

if (-not $SkipImmediateRun) {
    Write-Info 'running hourly task once for verification'
    & schtasks /Run /TN $HourlyTaskName | Out-Host
    Write-Info 'running rollup task once for verification'
    & schtasks /Run /TN $RollupTaskName | Out-Host
}

Write-Info ("hourly wrapper: {0}" -f $hourlyCmdPath)
Write-Info ("rollup wrapper: {0}" -f $rollupCmdPath)
Write-Info ("db target: server={0} db={1} user={2}" -f $resolvedDbServer, $resolvedDbName, $resolvedDbUser)
Write-Info 'task registration completed'
