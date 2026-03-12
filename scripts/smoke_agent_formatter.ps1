param(
    [string]$BaseUrl = "http://localhost:8080/epms/agent.jsp",
    [int]$DelayMs = 3000,
    [int]$MaxRetries = 2,
    [string]$TestGroup = "all"
)

$ErrorActionPreference = "Stop"

$tests = @(
    "current alarm status",
    "meter 77 current status",
    "frequency outlier",
    "A phase voltage",
    "meter 77 A phase voltage",
    "open alarms"
)

if ($TestGroup -eq "core") {
    $tests = @(
        "current alarm status",
        "meter 77 current status",
        "frequency outlier"
    )
} elseif ($TestGroup -eq "phase") {
    $tests = @(
        "A phase voltage",
        "meter 77 A phase voltage",
        "open alarms"
    )
}

function Get-ProviderText {
    param([string]$ProviderResponse)

    if ([string]::IsNullOrWhiteSpace($ProviderResponse)) {
        return ""
    }

    $lines = $ProviderResponse -split "`n"
    $buf = New-Object System.Text.StringBuilder
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($obj.response) {
                [void]$buf.Append($obj.response)
            }
        } catch {
        }
    }
    return $buf.ToString().Trim()
}

function Normalize-ResponseObject {
    param($Response)

    if ($null -eq $Response) {
        return $null
    }

    if ($Response -is [string]) {
        $trimmed = $Response.Trim()
        if ($trimmed.StartsWith([char]0xFEFF)) {
            $trimmed = $trimmed.Substring(1)
        }
        try {
            return $trimmed | ConvertFrom-Json
        } catch {
            return $null
        }
    }

    return $Response
}

foreach ($message in $tests) {
    Write-Host "==================================================" -ForegroundColor DarkGray
    Write-Host "Q: $message" -ForegroundColor Cyan

    $body = @{ message = $message } | ConvertTo-Json -Compress
    $res = $null
    $attempt = 0
    while ($attempt -le $MaxRetries) {
        try {
            $res = Invoke-RestMethod -Uri $BaseUrl -Method Post -ContentType "application/json; charset=UTF-8" -Body $body
            break
        } catch {
            $attempt++
            $msg = $_.Exception.Message
            if ($msg -match "\(429\)" -and $attempt -le $MaxRetries) {
                Write-Host "Rate limited, retrying in 5s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 5
                continue
            }
            Write-Host "Request failed: $msg" -ForegroundColor Red
            break
        }
    }

    if ($null -eq $res) {
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
        continue
    }

    $res = Normalize-ResponseObject -Response $res
    if ($null -eq $res) {
        Write-Host "Response parse failed" -ForegroundColor Red
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
        continue
    }

    $providerText = Get-ProviderText -ProviderResponse $res.provider_response
    $dbContextUser = [string]$res.db_context_user

    Write-Host "[provider_response]" -ForegroundColor Yellow
    if ([string]::IsNullOrWhiteSpace($providerText)) {
        Write-Host "(empty)"
    } else {
        Write-Host $providerText
    }

    Write-Host ""
    Write-Host "[db_context_user]" -ForegroundColor Yellow
    if ([string]::IsNullOrWhiteSpace($dbContextUser)) {
        Write-Host "(empty)"
    } else {
        Write-Host $dbContextUser
    }

    Write-Host ""

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}
