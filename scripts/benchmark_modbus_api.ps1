param(
    [string]$BaseUrl = "http://localhost:8080/epms/modbus_api.jsp",
    [int]$PlcId = 1,
    [int]$Requests = 50,
    [int]$Concurrency = 10,
    [ValidateSet("read", "polling_status", "polling_snapshot")]
    [string]$Action = "read",
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = "Stop"

if ($Requests -lt 1) { throw "Requests must be >= 1" }
if ($Concurrency -lt 1) { throw "Concurrency must be >= 1" }
if ($Concurrency -gt $Requests) { $Concurrency = $Requests }

$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
$jobs = @()

for ($i = 1; $i -le $Requests; $i++) {
    while (($jobs | Where-Object { $_.State -eq "Running" }).Count -ge $Concurrency) {
        Start-Sleep -Milliseconds 50
    }

    $jobs += Start-Job -ScriptBlock {
        param($BaseUrl, $PlcId, $Action, $TimeoutSec, $Idx)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $uri = "${BaseUrl}?action=$Action&plc_id=$PlcId&_ts=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())_$Idx"
            $res = Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec $TimeoutSec
            $ok = $false
            try {
                $obj = $res.Content | ConvertFrom-Json
                if ($obj -and $obj.ok -eq $true) { $ok = $true }
            } catch {}
            [PSCustomObject]@{
                ok = $ok
                status = [int]$res.StatusCode
                ms = [int]$sw.ElapsedMilliseconds
                err = $null
            }
        } catch {
            [PSCustomObject]@{
                ok = $false
                status = 0
                ms = [int]$sw.ElapsedMilliseconds
                err = $_.Exception.Message
            }
        }
    } -ArgumentList $BaseUrl, $PlcId, $Action, $TimeoutSec, $i
}

Wait-Job -Job $jobs | Out-Null
$results = $jobs | Receive-Job
$jobs | Remove-Job -Force | Out-Null
$swTotal.Stop()

$total = $results.Count
$success = ($results | Where-Object { $_.ok }).Count
$failed = $total - $success

$lat = $results | Where-Object { $_.ok } | Select-Object -ExpandProperty ms
if (-not $lat -or $lat.Count -eq 0) {
    Write-Output ("No successful responses. total={0}, failed={1}" -f $total, $failed)
    $sampleErr = $results | Where-Object { $_.err } | Select-Object -First 3
    if ($sampleErr) {
        Write-Output "Sample errors:"
        $sampleErr | ForEach-Object { Write-Output ("- {0}" -f $_.err) }
    }
    exit 1
}

$sorted = @($lat | Sort-Object)
function Get-Percentile([int[]]$arr, [double]$p) {
    if ($arr.Count -eq 0) { return 0 }
    $idx = [Math]::Ceiling(($p / 100.0) * $arr.Count) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $arr.Count) { $idx = $arr.Count - 1 }
    return [int]$arr[$idx]
}

$avg = [Math]::Round((($lat | Measure-Object -Average).Average), 2)
$min = ($sorted | Select-Object -First 1)
$max = ($sorted | Select-Object -Last 1)
$p50 = Get-Percentile -arr $sorted -p 50
$p95 = Get-Percentile -arr $sorted -p 95
$p99 = Get-Percentile -arr $sorted -p 99
$rps = [Math]::Round(($total / $swTotal.Elapsed.TotalSeconds), 2)

Write-Output "=== modbus_api benchmark ==="
Write-Output ("action={0}, plc_id={1}, requests={2}, concurrency={3}" -f $Action, $PlcId, $Requests, $Concurrency)
Write-Output ("success={0}, failed={1}, elapsed_total_ms={2}, throughput_rps={3}" -f $success, $failed, [int]$swTotal.ElapsedMilliseconds, $rps)
Write-Output ("latency_ms: min={0}, p50={1}, p95={2}, p99={3}, max={4}, avg={5}" -f $min, $p50, $p95, $p99, $max, $avg)

$errors = $results | Where-Object { -not $_.ok -and $_.err } | Group-Object err | Sort-Object Count -Descending | Select-Object -First 5
if ($errors) {
    Write-Output "top_errors:"
    foreach ($e in $errors) {
        Write-Output ("- {0} x {1}" -f $e.Count, $e.Name)
    }
}
