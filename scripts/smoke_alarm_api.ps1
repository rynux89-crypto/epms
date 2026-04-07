param(
    [string]$ServletUrl = "http://localhost:8080/api/alarm",
    [string]$CompatUrl = "http://localhost:8080/epms/alarm_api.jsp",
    [int]$PlcId = 1,
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = "Stop"

function Invoke-JsonRequest {
    param(
        [string]$Method,
        [string]$Url,
        [hashtable]$Body = $null
    )

    try {
        if ($Method -eq "POST") {
            $res = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $Url -Body $Body -TimeoutSec $TimeoutSec
        } else {
            $res = Invoke-WebRequest -UseBasicParsing -Method Get -Uri $Url -TimeoutSec $TimeoutSec
        }
        $obj = $res.Content | ConvertFrom-Json
        [PSCustomObject]@{
            ok = $true
            status = [int]$res.StatusCode
            body = $obj
            err = $null
        }
    } catch {
        [PSCustomObject]@{
            ok = $false
            status = 0
            body = $null
            err = $_.Exception.Message
        }
    }
}

$tests = @(
    @{
        Name = "servlet-health"
        Method = "GET"
        Url = "${ServletUrl}?action=health&_ts=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
        Validate = {
            param($body)
            $body.ok -eq $true -and $body.info -like "*alarm servlet alive*"
        }
    },
    @{
        Name = "servlet-diag"
        Method = "GET"
        Url = "${ServletUrl}?action=diag&_ts=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
        Validate = {
            param($body)
            $body.ok -eq $true -and $null -ne $body.queuePressureLevel -and $null -ne $body.diagStatus
        }
    },
    @{
        Name = "compat-health"
        Method = "GET"
        Url = "${CompatUrl}?action=health&_ts=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
        Validate = {
            param($body)
            $body.ok -eq $true -and $body.info -like "*alarm servlet alive*"
        }
    },
    @{
        Name = "servlet-process-ai-empty"
        Method = "POST"
        Url = $ServletUrl
        Body = @{
            action = "process_ai"
            plc_id = "$PlcId"
            measured_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
            rows = ""
        }
        Validate = {
            param($body)
            $body.ok -eq $true -and $body.rows -eq 0
        }
    },
    @{
        Name = "compat-process-di-empty"
        Method = "POST"
        Url = $CompatUrl
        Body = @{
            action = "process_di"
            plc_id = "$PlcId"
            measured_at_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
            rows = ""
        }
        Validate = {
            param($body)
            $body.ok -eq $true -and $body.rows -eq 0
        }
    }
)

$results = @()

foreach ($test in $tests) {
    $result = Invoke-JsonRequest -Method $test.Method -Url $test.Url -Body $test.Body
    $passed = $false
    if ($result.ok -and $result.body) {
        try {
            $passed = & $test.Validate $result.body
        } catch {
            $passed = $false
        }
    }

    $results += [PSCustomObject]@{
        name = $test.Name
        passed = [bool]$passed
        status = $result.status
        err = $result.err
    }
}

$failed = @($results | Where-Object { -not $_.passed })

Write-Output "=== alarm_api smoke test ==="
foreach ($r in $results) {
    if ($r.passed) {
        Write-Output ("PASS {0} (status={1})" -f $r.name, $r.status)
    } else {
        Write-Output ("FAIL {0} (status={1}) {2}" -f $r.name, $r.status, $r.err)
    }
}

if ($failed.Count -gt 0) {
    Write-Output ("failed={0}" -f $failed.Count)
    exit 1
}

Write-Output ("passed={0}" -f $results.Count)
