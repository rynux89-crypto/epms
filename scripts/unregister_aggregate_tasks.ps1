param(
    [string]$HourlyTaskName = 'EPMS Aggregate Hourly',
    [string]$RollupTaskName = 'EPMS Aggregate Rollup'
)

$ErrorActionPreference = 'Stop'

function Remove-TaskIfExists {
    param([string]$TaskName)

    $null = & schtasks /Query /TN $TaskName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output ("[INFO] deleting scheduled task: {0}" -f $TaskName)
        & schtasks /Delete /F /TN $TaskName | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to delete scheduled task: $TaskName"
        }
    } else {
        Write-Output ("[INFO] scheduled task not found: {0}" -f $TaskName)
    }
}

Remove-TaskIfExists -TaskName $HourlyTaskName
Remove-TaskIfExists -TaskName $RollupTaskName

Write-Output '[INFO] aggregate scheduled task cleanup completed'
