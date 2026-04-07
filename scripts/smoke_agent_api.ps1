param(
    [string]$ServletUrl = "http://localhost:8080/api/agent",
    [string]$CompatUrl = "http://localhost:8080/epms/agent.jsp",
    [int]$TimeoutSec = 45,
    [int]$RetryDelaySec = 6,
    [int]$MaxRetries = 2
)

$ErrorActionPreference = "Stop"

function Normalize-JsonText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $value = $Text.Trim()
    if ($value.Length -gt 0 -and [int][char]$value[0] -eq 65279) {
        $value = $value.Substring(1)
    }
    return $value
}

function Invoke-AgentRequest {
    param(
        [string]$Url,
        [string]$Message
    )

    $body = @{ message = $Message } | ConvertTo-Json -Compress

    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        try {
            $res = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $Url -ContentType "application/json; charset=UTF-8" -Body $body -TimeoutSec $TimeoutSec
            $content = Normalize-JsonText $res.Content
            $obj = $content | ConvertFrom-Json
            return [PSCustomObject]@{
                ok = $true
                status = [int]$res.StatusCode
                body = $obj
                err = $null
            }
        } catch {
            $message = $_.Exception.Message
            if (($message -match "\(429\)" -or $message -like "*초과*" -or $message -match "timed out") -and $attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelaySec
                continue
            }
            return [PSCustomObject]@{
                ok = $false
                status = 0
                body = $null
                err = $message
            }
        }
    }

    return [PSCustomObject]@{
        ok = $false
        status = 0
        body = $null
        err = "Unknown request failure"
    }
}

$tests = @(
    @{
        Name = "servlet-direct-energy"
        Url = $ServletUrl
        Message = "1번 계측기의 현재 전력량은?"
        Validate = {
            param($body)
            (-not [string]::IsNullOrWhiteSpace([string]$body.db_context_user)) -or (-not [string]::IsNullOrWhiteSpace([string]$body.provider_response))
        }
    },
    @{
        Name = "servlet-panel-monthly"
        Url = $ServletUrl
        Message = "MDB_3C 패널 전체 사용량은?"
        Validate = {
            param($body)
            -not [string]::IsNullOrWhiteSpace([string]$body.db_context_user)
        }
    },
    @{
        Name = "servlet-alarm-summary"
        Url = $ServletUrl
        Message = "current alarm status"
        Validate = {
            param($body)
            -not [string]::IsNullOrWhiteSpace([string]$body.provider_response)
        }
    },
    @{
        Name = "servlet-outlier"
        Url = $ServletUrl
        Message = "전류 불평형 계측기 수는?"
        Validate = {
            param($body)
            (-not [string]::IsNullOrWhiteSpace([string]$body.db_context_user)) -or (-not [string]::IsNullOrWhiteSpace([string]$body.provider_response))
        }
    },
    @{
        Name = "compat-direct-energy"
        Url = $CompatUrl
        Message = "1번 계측기의 현재 전력량은?"
        Validate = {
            param($body)
            (-not [string]::IsNullOrWhiteSpace([string]$body.db_context_user)) -or (-not [string]::IsNullOrWhiteSpace([string]$body.provider_response))
        }
    }
)

$results = @()

foreach ($test in $tests) {
    $result = Invoke-AgentRequest -Url $test.Url -Message $test.Message
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

Write-Output "=== agent_api smoke test ==="
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
