param(
    [Parameter(Mandatory=$true)][string]$ExcelPath,
    [int]$PlcId = 0,
    [string]$ByteOrder = 'CDAB',
    [int]$FloatCount = 62,
    [switch]$Apply,
    [switch]$AllowDisable,
    [string]$OutputJsonPath = '',
    [string]$OverrideJsonPath = ''
)

$ErrorActionPreference = 'Stop'

function Normalize-Str([object]$v){
    if ($null -eq $v) { return '' }
    return ([string]$v).Trim()
}

function To-IntOrNull([object]$v){
    $s = Normalize-Str $v
    if ($s -eq '') { return $null }
    $s = $s -replace ',', ''
    if ($s -match '^\d+(\.\d+)?$') {
        return [int][double]$s
    }
    return $null
}

function Match-Plc([string]$cell, [int]$target){
    $s = Normalize-Str $cell
    if ($s -eq '') { return $false }
    if ($s -match '(\d+)') {
        return ([int]$Matches[1]) -eq $target
    }
    return $false
}

function To-PlcBitIndex([int]$bitNo){
    # Prefer explicit 0-based configuration (0..15). Fallback to 1-based (1..16).
    if ($bitNo -ge 0 -and $bitNo -le 15) { return $bitNo }
    if ($bitNo -ge 1 -and $bitNo -le 16) { return ($bitNo - 1) }
    return $bitNo
}

function Normalize-AiFloatCount([int]$count){
    # Keep exact float count from Excel.
    return $count
}

function Get-AiFloatIndex([int]$baseAddr, [int]$addr){
    if ($addr -le $baseAddr) { return $null }
    $delta = $addr - $baseAddr - 1
    if ($delta -lt 0) { return $null }
    if (($delta % 2) -ne 0) { return $null }
    return [int]($delta / 2)
}

function Normalize-AiHeader([object]$v){
    $s = Normalize-Str $v
    if ($s -eq '') { return '' }
    return (($s -replace '\s+', '')).ToUpperInvariant()
}

function Resolve-AiCanonicalToken([string]$rawToken, [string]$mainHeader, [string]$subHeader){
    $t = Normalize-Str $rawToken
    if ($t -eq '') { return '' }
    $t = $t -replace '^[\\??]+', ''
    $t = ($t -replace '\s+', '').Trim().ToUpperInvariant()
    if ($t -eq '') { return '' }
    if ($t -eq 'KHH') { return 'KWH' }
    if ($t -eq 'VAH') { return 'KVARH' }
    return $t
}

function Get-RowCellValue([System.Data.DataRow]$row, [string]$col){
    if ($null -eq $row) { return '' }
    return $row[$col]
}

function Build-AiMatchSyncMap([string]$metricOrder){
    $map = @{}
    $order = Normalize-Str $metricOrder
    if ($order -eq '') { return $map }
    $tokens = @($order -split '\s*,\s*')
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = (Normalize-Str $tokens[$i]).ToUpperInvariant()
        if ($token -eq '') { continue }
        if ($token -eq 'IR') { continue }
        $map[$token] = $i + 1
    }
    return $map
}

function Get-AiMatchSyncPlan($sqlCn, [hashtable]$syncMap){
    $changed = 0
    $missing = New-Object System.Collections.Generic.List[string]
    $samples = New-Object System.Collections.Generic.List[string]
    if ($null -eq $syncMap -or $syncMap.Count -eq 0) {
        return [PSCustomObject]@{
            changed_count = 0
            missing_count = 0
            changed_samples = $samples
            missing_tokens = $missing
        }
    }

    $current = @{}
    $cmd = $sqlCn.CreateCommand()
    $cmd.CommandText = "IF OBJECT_ID('dbo.plc_ai_measurements_match','U') IS NOT NULL SELECT token, float_index FROM dbo.plc_ai_measurements_match"
    $r = $cmd.ExecuteReader()
    while ($r.Read()) {
        $token = (Normalize-Str $r['token']).ToUpperInvariant()
        if ($token -eq '') { continue }
        $current[$token] = [int]$r['float_index']
    }
    $r.Close()

    foreach ($token in @($syncMap.Keys | Sort-Object)) {
        $desired = [int]$syncMap[$token]
        if (-not $current.ContainsKey($token)) {
            $missing.Add($token)
            continue
        }
        $existing = [int]$current[$token]
        if ($existing -ne $desired) {
            $changed++
            if ($samples.Count -lt 12) {
                $samples.Add(("{0}:{1}->{2}" -f $token, $existing, $desired))
            }
        }
    }

    return [PSCustomObject]@{
        changed_count = $changed
        missing_count = $missing.Count
        changed_samples = $samples
        missing_tokens = $missing
    }
}

function Apply-AiMatchSync($sqlCn, $tx, [hashtable]$syncMap){
    if ($null -eq $syncMap -or $syncMap.Count -eq 0) { return 0 }
    $affected = 0
    foreach ($token in $syncMap.Keys) {
        $check = $sqlCn.CreateCommand()
        $check.Transaction = $tx
        $check.CommandText = "SELECT COUNT(1) FROM dbo.plc_ai_measurements_match WHERE token = @token"
        [void]$check.Parameters.Add('@token', [System.Data.SqlDbType]::VarChar, 100)
        $check.Parameters['@token'].Value = [string]$token
        $exists = [int]$check.ExecuteScalar()
        if ($exists -le 0) {
            $ins = $sqlCn.CreateCommand()
            $ins.Transaction = $tx
            $ins.CommandText = @"
INSERT INTO dbo.plc_ai_measurements_match
(token, float_index, float_registers, measurement_column, target_table, is_supported, note, updated_at)
VALUES (@token, @float_index, 2, NULL, NULL, 0, 'AUTO_SYNC', SYSDATETIME())
"@
            [void]$ins.Parameters.Add('@token', [System.Data.SqlDbType]::VarChar, 100)
            [void]$ins.Parameters.Add('@float_index', [System.Data.SqlDbType]::Int)
            $ins.Parameters['@token'].Value = [string]$token
            $ins.Parameters['@float_index'].Value = [int]$syncMap[$token]
            $affected += [int]$ins.ExecuteNonQuery()
            continue
        }

        $cmd = $sqlCn.CreateCommand()
        $cmd.Transaction = $tx
        $cmd.CommandText = @"
UPDATE dbo.plc_ai_measurements_match
SET float_index = @float_index,
    updated_at = SYSDATETIME()
WHERE token = @token
  AND ISNULL(float_index, -1) <> @float_index
"@
        [void]$cmd.Parameters.Add('@float_index', [System.Data.SqlDbType]::Int)
        [void]$cmd.Parameters.Add('@token', [System.Data.SqlDbType]::VarChar, 100)
        $cmd.Parameters['@float_index'].Value = [int]$syncMap[$token]
        $cmd.Parameters['@token'].Value = [string]$token
        $affected += [int]$cmd.ExecuteNonQuery()
    }
    return $affected
}

function Resolve-AiMetricOrder([System.Data.DataTable]$aiSheet, [string]$fallback){
    if ($null -eq $aiSheet) { return $fallback }
    $best = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($row in $aiSheet.Select()) {
        $tokens = New-Object System.Collections.Generic.List[string]
        $localSeen = New-Object System.Collections.Generic.HashSet[string]
        for ($c = 6; $c -le $aiSheet.Columns.Count; $c++) {
            $col = "F$c"
            if (-not $aiSheet.Columns.Contains($col)) { continue }
            $raw = Normalize-Str $row[$col]
            if ($raw -eq '') { continue }
            if ($raw -match '^\d+(\.\d+)?$') { continue } # address/value row
            $t = $raw -replace '^[\\₩/]+', ''
            $t = ($t -replace '\s+', '').Trim().ToUpperInvariant()
            if ($t -eq '') { continue }
            if ($localSeen.Add($t)) { $tokens.Add($t) }
        }
        if ($tokens.Count -gt $best.Count -and $tokens.Count -ge 10) {
            $best = $tokens
        }
    }

    if ($best.Count -lt 1) { return $fallback }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in $best) {
        if ($seen.Add($t)) { $out.Add($t) }
    }
    if ($out.Count -lt 1) { return $fallback }
    return [string]::Join(',', $out)
}

function Build-AiTokenByColumn([System.Data.DataTable]$aiSheet){
    $map = @{}
    if ($null -eq $aiSheet) { return $map }
    $bestRow = $null
    $bestCnt = 0

    foreach ($row in $aiSheet.Select()) {
        $cnt = 0
        for ($c = 6; $c -le $aiSheet.Columns.Count; $c++) {
            $col = "F$c"
            if (-not $aiSheet.Columns.Contains($col)) { continue }
            $raw = Normalize-Str $row[$col]
            if ($raw -eq '') { continue }
            if ($raw -match '^\d+(\.\d+)?$') { continue }
            $cnt++
        }
        if ($cnt -gt $bestCnt) {
            $bestCnt = $cnt
            $bestRow = $row
        }
    }

    if ($null -eq $bestRow -or $bestCnt -lt 1) { return $map }
    for ($c = 6; $c -le $aiSheet.Columns.Count; $c++) {
        $col = "F$c"
        if (-not $aiSheet.Columns.Contains($col)) { continue }
        $raw = Normalize-Str $bestRow[$col]
        if ($raw -eq '') { continue }
        if ($raw -match '^\d+(\.\d+)?$') { continue }
        $t = $raw -replace '^[\\₩/]+', ''
        $t = ($t -replace '\s+', '').Trim().ToUpperInvariant()
        if ($t -eq '') { continue }
        $map[$c] = $t
    }
    return $map
}

function Build-AiTokenByColumnV2([System.Data.DataTable]$aiSheet){
    $map = @{}
    if ($null -eq $aiSheet) { return $map }
    $bestRowIndex = -1
    $bestCnt = 0
    $seenTokenCount = @{}

    for ($ri = 0; $ri -lt $aiSheet.Rows.Count; $ri++) {
        $row = $aiSheet.Rows[$ri]
        $cnt = 0
        for ($c = 6; $c -le $aiSheet.Columns.Count; $c++) {
            $col = "F$c"
            if (-not $aiSheet.Columns.Contains($col)) { continue }
            $raw = Normalize-Str $row[$col]
            if ($raw -eq '') { continue }
            if ($raw -match '^\d+(\.\d+)?$') { continue }
            $cnt++
        }
        if ($cnt -gt $bestCnt) {
            $bestCnt = $cnt
            $bestRowIndex = $ri
        }
    }

    if ($bestRowIndex -lt 0 -or $bestCnt -lt 1) { return $map }
    $tokenRow = $aiSheet.Rows[$bestRowIndex]
    $mainHeaderRow = if ($bestRowIndex -ge 3) { $aiSheet.Rows[$bestRowIndex - 3] } else { $null }
    $subHeaderRow = if ($bestRowIndex -ge 2) { $aiSheet.Rows[$bestRowIndex - 2] } else { $null }

    for ($c = 6; $c -le $aiSheet.Columns.Count; $c++) {
        $col = "F$c"
        if (-not $aiSheet.Columns.Contains($col)) { continue }
        $raw = Normalize-Str $tokenRow[$col]
        if ($raw -eq '') { continue }
        if ($raw -match '^\d+(\.\d+)?$') { continue }
        $token = Resolve-AiCanonicalToken `
            -rawToken $raw `
            -mainHeader (Get-RowCellValue -row $mainHeaderRow -col $col) `
            -subHeader (Get-RowCellValue -row $subHeaderRow -col $col)
        if ($token -eq '') { continue }
        if (-not $seenTokenCount.ContainsKey($token)) { $seenTokenCount[$token] = 0 }
        $seenTokenCount[$token] = [int]$seenTokenCount[$token] + 1
        if ($token -eq 'VA' -and [int]$seenTokenCount[$token] -ge 2) {
            $token = 'KVAR'
        }
        $map[$c] = $token
    }
    return $map
}

function Resolve-AiMetricOrderV2([System.Data.DataTable]$aiSheet, [string]$fallback){
    $tokenByCol = Build-AiTokenByColumnV2 -aiSheet $aiSheet
    if ($null -eq $tokenByCol -or $tokenByCol.Count -lt 1) { return $fallback }
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($c in @($tokenByCol.Keys | Sort-Object {[int]$_})) {
        $token = Normalize-Str $tokenByCol[$c]
        if ($token -eq '') { continue }
        $tokens.Add($token)
    }
    if ($tokens.Count -lt 1) { return $fallback }
    return [string]::Join(',', $tokens)
}

function New-SqlConnection {
    $cn = New-Object System.Data.SqlClient.SqlConnection
    $cn.ConnectionString = 'Server=localhost,1433;Database=epms;User ID=sa;Password=1234;TrustServerCertificate=True;Encrypt=True'
    $cn.Open()
    return $cn
}

function New-StringSet {
    return New-Object 'System.Collections.Generic.HashSet[string]'
}

function Extract-JsonText([string]$text) {
    $s = if ($null -eq $text) { '' } else { $text.Trim() }
    if ($s -eq '') { return '' }
    $start = $s.IndexOf('{')
    $end = $s.LastIndexOf('}')
    if ($start -lt 0 -or $end -lt $start) { return $s }
    return $s.Substring($start, ($end - $start + 1))
}

function Write-JsonResult([object]$obj, [int]$depth = 8) {
    $json = $obj | ConvertTo-Json -Depth $depth -Compress
    if ((Normalize-Str $OutputJsonPath) -ne '') {
        Set-Content -Path $OutputJsonPath -Value $json -Encoding UTF8
    } else {
        $json
    }
}

function Load-AiOverrideMap([string]$path){
    $map = @{}
    $p = Normalize-Str $path
    if ($p -eq '' -or -not (Test-Path -Path $p -PathType Leaf)) { return $map }
    $raw = Get-Content -Path $p -Raw -Encoding UTF8
    if ((Normalize-Str $raw) -eq '') { return $map }
    $obj = $raw | ConvertFrom-Json
    $items = @()
    if ($obj -is [System.Collections.IEnumerable]) {
        foreach ($x in $obj) { $items += $x }
    } else {
        $items += $obj
    }
    foreach ($it in $items) {
        if ($null -eq $it) { continue }
        $plcId = if ($it.PSObject.Properties.Name -contains 'plc_id') { [int]$it.plc_id } else { 0 }
        $meterId = if ($it.PSObject.Properties.Name -contains 'meter_id') { [int]$it.meter_id } else { 0 }
        if ($plcId -le 0 -or $meterId -le 0) { continue }
        $key = "{0}|{1}" -f $plcId, $meterId
        $map[$key] = $it
    }
    return $map
}

function Query-ExcelTable([string]$path, [string]$sheetName){
    $cs = "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$path;Extended Properties='Excel 12.0 Xml;HDR=NO;IMEX=1'"
    $cn = New-Object System.Data.OleDb.OleDbConnection($cs)
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM [$sheetName`$]"
        $da = New-Object System.Data.OleDb.OleDbDataAdapter($cmd)
        $dt = New-Object System.Data.DataTable
        [void]$da.Fill($dt)
        return ,$dt
    } finally {
        $cn.Close()
    }
}

function Get-MeterMatch([hashtable]$byName, [hashtable]$byPanel, [string]$name, [string]$panel){
    if ($null -eq $name) { $name = '' }
    if ($null -eq $panel) { $panel = '' }
    $kName = $name.Trim().ToUpperInvariant()
    if ($kName -ne '' -and $byName.ContainsKey($kName)) {
        return $byName[$kName]
    }
    $kPanel = $panel.Trim().ToUpperInvariant()
    if ($kPanel -ne '' -and $byPanel.ContainsKey($kPanel)) {
        $arr = $byPanel[$kPanel]
        if ($arr.Count -eq 1) {
            return $arr[0]
        }
    }
    return $null
}

function Resolve-AutoFloatCount([System.Data.DataTable]$aiSheet, [int]$targetPlcId, [int]$fallback){
    if ($null -eq $aiSheet) { return $fallback }
    $maxCount = 0
    $colCount = $aiSheet.Columns.Count
    if ($colCount -lt 6) { return $fallback }

    foreach ($row in $aiSheet.Select()) {
        $no = To-IntOrNull $row['F1']
        if ($null -eq $no) { continue }
        $plcCell = Normalize-Str $row['F2']
        if (-not (Match-Plc -cell $plcCell -target $targetPlcId)) { continue }
        $itemName = Normalize-Str $row['F3']
        $baseAddr = To-IntOrNull $row['F5']
        if ($itemName -eq '' -or $null -eq $baseAddr) { continue }

        $addrList = New-Object System.Collections.Generic.List[int]
        $seenAddr = New-Object 'System.Collections.Generic.HashSet[int]'
        $nonEmptyCount = 0
        for ($c = 6; $c -le $colCount; $c++) {
            $col = "F$c"
            if (-not $aiSheet.Columns.Contains($col)) { continue }
            $raw = Normalize-Str $row[$col]
            if ($raw -ne '') { $nonEmptyCount++ }
            $addr = To-IntOrNull $row[$col]
            if ($null -ne $addr -and [int]$addr -gt [int]$baseAddr) {
                $addrInt = [int]$addr
                if ($seenAddr.Add($addrInt)) {
                    $addrList.Add($addrInt)
                }
            }
        }
        $count = @($addrList | Sort-Object -Unique).Count
        if ($count -le 0 -and $nonEmptyCount -gt 0) { $count = $nonEmptyCount }
        if ($count -gt 0) { $count = Normalize-AiFloatCount -count $count }
        if ($count -gt $maxCount) { $maxCount = $count }
    }

    if ($maxCount -gt 0) { return $maxCount }
    return $fallback
}

try {
    if (-not (Test-Path -Path $ExcelPath -PathType Leaf)) {
        throw "Excel file not found: $ExcelPath"
    }

    $tokenDefault = 'V12,V23,V31,VVA,V1N,V2N,V3N,VA,A1,A2,A3,AN,AA,PF,HZ,KW,KWH,KVAR,KVARH,PEAK,IR,H_VA_1,H_VA_3,H_VA_5,H_VA_7,H_VA_9,H_VA_11,H_VB_1,H_VB_3,H_VB_5,H_VB_7,H_VB_9,H_VB_11,H_VC_1,H_VC_3,H_VC_5,H_VC_7,H_VC_9,H_VC_11,H_IA_1,H_IA_3,H_IA_5,H_IA_7,H_IA_9,H_IA_11,H_IB_1,H_IB_3,H_IB_5,H_IB_7,H_IB_9,H_IB_11,H_IC_1,H_IC_3,H_IC_5,H_IC_7,H_IC_9,H_IC_11,PV1,PV2,PV3,PI1,PI2,PI3'

    $aiSheet = Query-ExcelTable -path $ExcelPath -sheetName 'PLC_IO_Address_AI'
    $diSheet = Query-ExcelTable -path $ExcelPath -sheetName 'PLC_IO_Address_DI'
    $aiOverrideMap = Load-AiOverrideMap -path $OverrideJsonPath

    # Auto mode: if PlcId is not provided (or <= 0), detect PLC IDs from Excel and run per-PLC import.
    if ($PlcId -le 0) {
        $plcIdSet = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($tbl in @($aiSheet, $diSheet)) {
            foreach ($row in $tbl.Select()) {
                $cell = Normalize-Str $row['F2']
                if ($cell -eq '') { continue }
                if ($cell -match '(\d+)') {
                    [void]$plcIdSet.Add([int]$Matches[1])
                }
            }
        }

        $plcIds = @($plcIdSet | Sort-Object)
        if ($plcIds.Count -eq 0) {
            throw "No PLC IDs detected from Excel column F2."
        }

        $runner = (Get-Process -Id $PID).Path
        $all = New-Object System.Collections.Generic.List[object]
        $sumAiCandidates = 0
        $sumAiRows = 0
        $sumDiMapRows = 0
        $sumDiTagRows = 0
        $sumAiUnmatched = New-Object System.Collections.Generic.List[string]
        $floatCountByPlc = @{}
        $floatDistAll = @{}
        $floatMetersAll = @{}

        foreach ($plcNum in $plcIds) {
            $jsonOutPath = [System.IO.Path]::GetTempFileName()
            $args = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', $PSCommandPath,
                '-ExcelPath', $ExcelPath,
                '-PlcId', [string]$plcNum,
                '-ByteOrder', $ByteOrder,
                '-FloatCount', [string]$FloatCount,
                '-OutputJsonPath', $jsonOutPath
            )
            if ((Normalize-Str $OverrideJsonPath) -ne '') {
                $args += @('-OverrideJsonPath', $OverrideJsonPath)
            }
            if ($Apply.IsPresent) { $args += '-Apply' }
            if ($AllowDisable.IsPresent) { $args += '-AllowDisable' }

            try {
                $raw = & $runner @args 2>&1 | Out-String
                $text = ''
                if (Test-Path $jsonOutPath) {
                    $text = Extract-JsonText (Get-Content -Path $jsonOutPath -Raw -Encoding UTF8)
                }
                if ($text -eq '') {
                    $text = Extract-JsonText ($raw | Out-String)
                }
                if ($text -eq '') { throw "PLC $plcNum import returned empty output." }
                $obj = $text | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw "PLC $plcNum import parse failed: $text"
            } finally {
                try { if (Test-Path $jsonOutPath) { Remove-Item $jsonOutPath -Force } } catch {}
            }
            if (-not $obj.ok) {
                $msg = if ($obj.message) { [string]$obj.message } else { $text }
                throw "PLC $plcNum import failed: $msg"
            }

            $all.Add($obj)
            $sumAiCandidates += [int]$obj.ai_candidates
            $sumAiRows += [int]$obj.ai_rows
            $sumDiMapRows += [int]$obj.di_map_rows
            $sumDiTagRows += [int]$obj.di_tag_rows
            if ($obj.PSObject.Properties.Name -contains 'float_count_used') {
                $floatCountByPlc[[string]$obj.plc_id] = $obj.float_count_used
            }
            if ($obj.ai_unmatched) {
                foreach ($u in $obj.ai_unmatched) { $sumAiUnmatched.Add([string]$u) }
            }
            if ($obj.ai_float_distribution) {
                $pd = $obj.ai_float_distribution.PSObject.Properties
                foreach ($p in $pd) {
                    $k = [string]$p.Name
                    $v = [int]$p.Value
                    if (-not $floatDistAll.ContainsKey($k)) { $floatDistAll[$k] = 0 }
                    $floatDistAll[$k] += $v
                }
            }
            if ($obj.ai_float_meter_ids) {
                $pm = $obj.ai_float_meter_ids.PSObject.Properties
                foreach ($m in $pm) {
                    $k = [string]$m.Name
                    if (-not $floatMetersAll.ContainsKey($k)) {
                        $floatMetersAll[$k] = New-Object System.Collections.Generic.List[int]
                    }
                    foreach ($mid in @($m.Value)) {
                        $floatMetersAll[$k].Add([int]$mid)
                    }
                }
            }
        }

        $floatDistinct = @($floatCountByPlc.Values | Sort-Object -Unique)
        $floatUsed = if ($floatDistinct.Count -eq 1) { $floatDistinct[0] } else { 'VARIES' }

        $out = [PSCustomObject]@{
            ok = $true
            mode = $(if ($Apply.IsPresent) { 'apply' } else { 'preview' })
            auto = $true
            plc_id = 'AUTO'
            plc_ids = $plcIds
            excel_path = $ExcelPath
            ai_sheet_rows = $aiSheet.Rows.Count
            di_sheet_rows = $diSheet.Rows.Count
            ai_candidates = $sumAiCandidates
            ai_rows = $sumAiRows
            ai_unmatched = $sumAiUnmatched
            float_count_used = $floatUsed
            float_count_by_plc = $floatCountByPlc
            ai_float_distribution = $floatDistAll
            ai_float_meter_ids = $floatMetersAll
            di_map_rows = $sumDiMapRows
            di_tag_rows = $sumDiTagRows
            per_plc = $all
        }
        Write-JsonResult -obj $out -depth 8
        exit 0
    }

    $sqlCn = New-SqlConnection
    try {
    $effectiveFloatCount = Resolve-AutoFloatCount -aiSheet $aiSheet -targetPlcId $PlcId -fallback $FloatCount

    $meterByName = @{}
    $meterByPanel = @{}

    $cmdMeters = $sqlCn.CreateCommand()
    $cmdMeters.CommandText = 'SELECT meter_id, name, panel_name FROM dbo.meters'
    $rMeters = $cmdMeters.ExecuteReader()
    while ($rMeters.Read()) {
        $meterId = [int]$rMeters['meter_id']
        $name = Normalize-Str $rMeters['name']
        $panel = Normalize-Str $rMeters['panel_name']

        $nk = $name.ToUpperInvariant()
        if ($nk -ne '' -and -not $meterByName.ContainsKey($nk)) {
            $meterByName[$nk] = $meterId
        }

        $pk = $panel.ToUpperInvariant()
        if ($pk -ne '') {
            if (-not $meterByPanel.ContainsKey($pk)) {
                $meterByPanel[$pk] = New-Object System.Collections.Generic.List[int]
            }
            $meterByPanel[$pk].Add($meterId)
        }
    }
    $rMeters.Close()

    $metricOrderFallback = Resolve-AiMetricOrderV2 -aiSheet $aiSheet -fallback ''
    if ((Normalize-Str $metricOrderFallback) -eq '') {
        $metricOrderFallback = $tokenDefault
        $cmdMetric = $sqlCn.CreateCommand()
        $cmdMetric.CommandText = 'SELECT TOP 1 metric_order FROM dbo.plc_meter_map WHERE plc_id = @plc_id AND metric_order IS NOT NULL AND LEN(metric_order) > 0 ORDER BY map_id'
        [void]$cmdMetric.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
        $cmdMetric.Parameters['@plc_id'].Value = $PlcId
        $metricVal = $cmdMetric.ExecuteScalar()
        if ($null -ne $metricVal -and (Normalize-Str $metricVal) -ne '') {
            $metricOrderFallback = [string]$metricVal
        }
    }
    $tokenByCol = Build-AiTokenByColumnV2 -aiSheet $aiSheet

    $aiRows = New-Object System.Collections.Generic.List[object]
    $aiUnmatched = New-Object System.Collections.Generic.List[string]
    $aiCandidateCount = 0

    foreach ($row in $aiSheet.Select()) {
        $no = To-IntOrNull $row['F1']
        if ($null -eq $no) { continue }

        $plcCell = Normalize-Str $row['F2']
        if (-not (Match-Plc -cell $plcCell -target $PlcId)) { continue }

        $itemName = Normalize-Str $row['F3']
        $panelName = Normalize-Str $row['F4']
        $baseAddr = To-IntOrNull $row['F5']
        if ($itemName -eq '' -or $null -eq $baseAddr) { continue }
        $aiCandidateCount++

        $meterId = Get-MeterMatch -byName $meterByName -byPanel $meterByPanel -name $itemName -panel $panelName
        if ($null -eq $meterId) {
            $aiUnmatched.Add("AI meter unresolved: NO=$no, item=$itemName, panel=$panelName")
            continue
        }

        $maxFloatIndex = -1
        $maxPresentCol = 0
        $tokenByIndex = @{}
        $tokenAddresses = New-Object System.Collections.Generic.List[object]
        $nonEmptyCount = 0
        for ($c = 6; $c -le $aiSheet.Columns.Count; $c++) {
            $col = "F$c"
            if (-not $aiSheet.Columns.Contains($col)) { continue }
            $raw = Normalize-Str $row[$col]
            if ($raw -ne '') { $nonEmptyCount++ }
            $addr = To-IntOrNull $row[$col]
            if ($null -ne $addr -and [int]$addr -gt [int]$baseAddr) {
                $floatIndex = Get-AiFloatIndex -baseAddr ([int]$baseAddr) -addr ([int]$addr)
                if ($null -ne $floatIndex) {
                    if ($floatIndex -gt $maxFloatIndex) { $maxFloatIndex = $floatIndex }
                    if ($c -gt $maxPresentCol) { $maxPresentCol = $c }
                    $token = ''
                    if ($tokenByCol.ContainsKey($c)) { $token = [string]$tokenByCol[$c] }
                    if ((Normalize-Str $token) -eq '') { $token = "F$($floatIndex + 1)" }
                    $tokenByIndex[[int]$floatIndex] = $token
                    $tokenAddresses.Add([PSCustomObject]@{
                        float_index = [int]($floatIndex + 1)
                        token = [string]$token
                        reg_address = [int]$addr
                    })
                }
            }
        }

        $metricTokens = New-Object System.Collections.Generic.List[string]
        if ($maxPresentCol -gt 0) {
            for ($c = 6; $c -le $maxPresentCol; $c++) {
                if ($tokenByCol.ContainsKey($c)) {
                    $metricTokens.Add([string]$tokenByCol[$c])
                }
            }
        }

        $rowFloatCount = if ($maxFloatIndex -ge 0) { $maxFloatIndex + 1 } else { 0 }
        if ($rowFloatCount -le 0 -and $nonEmptyCount -gt 0) { $rowFloatCount = $nonEmptyCount }
        if ($rowFloatCount -le 0) { $rowFloatCount = $effectiveFloatCount }
        $rowFloatCount = Normalize-AiFloatCount -count ([int]$rowFloatCount)
        $rowMetricOrder = [string]::Join(',', $metricTokens)
        if ((Normalize-Str $rowMetricOrder) -eq '') { $rowMetricOrder = $metricOrderFallback }
        $previewTokenAddresses = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $metricTokens.Count; $i++) {
            $previewTokenAddresses.Add([PSCustomObject]@{
                float_index = [int]($i + 1)
                token = [string]$metricTokens[$i]
                reg_address = [int](([int]$baseAddr + 1) + ($i * 2))
            })
        }

        $obj = [PSCustomObject]@{
            meter_id = [int]$meterId
            start_address = [int]$baseAddr + 1
            float_count = [int]$rowFloatCount
            metric_order = [string]$rowMetricOrder
            item_name = $itemName
            panel_name = $panelName
            token_addresses = $previewTokenAddresses
        }

        $overrideKey = "{0}|{1}" -f $PlcId, ([int]$meterId)
        if ($aiOverrideMap.ContainsKey($overrideKey)) {
            $ov = $aiOverrideMap[$overrideKey]
            if ($ov.PSObject.Properties.Name -contains 'token_addresses' -and $null -ne $ov.token_addresses) {
                $overrideTokens = New-Object System.Collections.Generic.List[string]
                $overrideStartAddress = $null
                $expectedAddress = $null
                foreach ($ta in @($ov.token_addresses)) {
                    if ($null -eq $ta) { continue }
                    $token = (Normalize-Str $ta.token).ToUpperInvariant()
                    $regAddress = [int]$ta.reg_address
                    if ($token -eq '') { continue }
                    if ($null -eq $overrideStartAddress) {
                        $overrideStartAddress = $regAddress
                        $expectedAddress = $regAddress
                    }
                    if ($regAddress -ne $expectedAddress) {
                        throw ("Override address sequence invalid for plc_id={0}, meter_id={1}. expected={2}, actual={3}" -f $PlcId, $meterId, $expectedAddress, $regAddress)
                    }
                    $overrideTokens.Add($token)
                    $expectedAddress += 2
                }
                if ($overrideTokens.Count -gt 0 -and $null -ne $overrideStartAddress) {
                    $obj.start_address = [int]$overrideStartAddress
                    $obj.float_count = [int]$overrideTokens.Count
                    $obj.metric_order = [string]::Join(',', $overrideTokens)
                    $obj.token_addresses = @($ov.token_addresses)
                }
            } else {
                if ($ov.PSObject.Properties.Name -contains 'start_address') {
                    $obj.start_address = [int]$ov.start_address
                }
                if ($ov.PSObject.Properties.Name -contains 'float_count') {
                    $obj.float_count = [int]$ov.float_count
                }
                if ($ov.PSObject.Properties.Name -contains 'metric_order') {
                    $obj.metric_order = [string]$ov.metric_order
                }
            }
        }
        $aiRows.Add($obj)
    }

    $diMapByPoint = @{}
    $diTags = New-Object System.Collections.Generic.List[object]
    $diAllRows = $diSheet.Select()
    $diHeaderTitleRow = if ($diAllRows.Count -gt 4) { $diAllRows[4] } else { $null }
    $diHeaderCodeRow = if ($diAllRows.Count -gt 6) { $diAllRows[6] } else { $null }

    foreach ($row in $diAllRows) {
        $pointId = To-IntOrNull $row['F1']
        if ($null -eq $pointId) { continue }

        $plcCell = Normalize-Str $row['F2']
        if (-not (Match-Plc -cell $plcCell -target $PlcId)) { continue }

        $itemName = Normalize-Str $row['F3']
        $panelName = Normalize-Str $row['F4']
        $baseAddr = To-IntOrNull $row['F5']
        if ($null -eq $baseAddr) { continue }

        $usedBits = New-Object System.Collections.Generic.HashSet[int]
        for ($c = 6; $c -le $diSheet.Columns.Count; $c++) {
            $col = "F$c"
            $raw = Normalize-Str $row[$col]
            if ($raw -eq '') { continue }

            if ($raw -match '^(\d+)\.(\d+)$') {
                $addr = [int]$Matches[1]
                $bitNo = [int]$Matches[2]
            } elseif ($raw -match '^\d+$') {
                $addr = [int]$raw
                $bitNo = 0
            } else {
                continue
            }

            if ($addr -eq $baseAddr -and $bitNo -ge 0 -and $bitNo -le 16) {
                # bit_count is "how many bits are defined in Excel", so count distinct raw bit numbers.
                [void]$usedBits.Add($bitNo)
            }

            $tagTitle = if ($null -ne $diHeaderTitleRow) { Normalize-Str $diHeaderTitleRow[$col] } else { '' }
            $tagCode = if ($null -ne $diHeaderCodeRow) { Normalize-Str $diHeaderCodeRow[$col] } else { '' }
            $tagName = ("$tagTitle $tagCode").Trim()
            if ($tagName -eq '') { $tagName = $tagCode }

            $diTags.Add([PSCustomObject]@{
                point_id = [int]$pointId
                di_address = [int]$addr
                bit_no = [int]$bitNo
                tag_name = $tagName
                item_name = $itemName
                panel_name = $panelName
            })
        }

        # Represent only actual bits used in Excel (address.bit entries for this base address).
        $bitCount = if ($usedBits.Count -gt 0) { $usedBits.Count } else { 1 }
        $diMapByPoint[$pointId] = [PSCustomObject]@{
            point_id = [int]$pointId
            start_address = [int]$baseAddr
            bit_count = [int]$bitCount
        }
    }

    $canonicalAiMetricOrder = ''
    foreach ($r in $aiRows) {
        $mo = Normalize-Str $r.metric_order
        if ($mo -eq '') { continue }
        if ($canonicalAiMetricOrder -eq '' -or (@($mo -split ',').Count -gt @($canonicalAiMetricOrder -split ',').Count)) {
            $canonicalAiMetricOrder = $mo
        }
    }
    if ($canonicalAiMetricOrder -eq '') { $canonicalAiMetricOrder = $metricOrderFallback }
    $aiMatchSyncMap = Build-AiMatchSyncMap -metricOrder $canonicalAiMetricOrder
    $aiMatchSyncPlan = Get-AiMatchSyncPlan -sqlCn $sqlCn -syncMap $aiMatchSyncMap

    $newAiKeySet = New-StringSet
    foreach ($r in $aiRows) { [void]$newAiKeySet.Add([string]([int]$r.meter_id)) }

    $newDiMapKeySet = New-StringSet
    foreach ($k in $diMapByPoint.Keys) { [void]$newDiMapKeySet.Add([string]([int]$k)) }

    $newDiTagKeySet = New-StringSet
    $newEldTagCount = 0
    foreach ($r in $diTags) {
        [void]$newDiTagKeySet.Add(("{0}|{1}|{2}" -f [int]$r.point_id, [int]$r.di_address, [int]$r.bit_no))
        if (([string]$r.tag_name).ToUpperInvariant().Contains('ELD')) { $newEldTagCount++ }
    }

    $existingAiEnabled = 0
    $existingDiMapEnabled = 0
    $existingDiTagEnabled = 0
    $existingEldTagEnabled = 0
    $disabledAiSamples = New-Object System.Collections.Generic.List[string]
    $disabledDiMapSamples = New-Object System.Collections.Generic.List[string]
    $disabledDiTagSamples = New-Object System.Collections.Generic.List[string]
    $disabledAiCount = 0
    $disabledDiMapCount = 0
    $disabledDiTagCount = 0

    $cmdExistingAi = $sqlCn.CreateCommand()
    $cmdExistingAi.CommandText = @"
SELECT m.meter_id, mt.name
FROM dbo.plc_meter_map m
LEFT JOIN dbo.meters mt ON mt.meter_id = m.meter_id
WHERE m.plc_id = @plc_id AND m.enabled = 1
"@
    [void]$cmdExistingAi.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
    $cmdExistingAi.Parameters['@plc_id'].Value = $PlcId
    $rExistingAi = $cmdExistingAi.ExecuteReader()
    while ($rExistingAi.Read()) {
        $existingAiEnabled++
        $meterId = [int]$rExistingAi['meter_id']
        if (-not $newAiKeySet.Contains([string]$meterId)) {
            $disabledAiCount++
            if ($disabledAiSamples.Count -lt 10) {
                $disabledAiSamples.Add(("meter_id={0}, name={1}" -f $meterId, (Normalize-Str $rExistingAi['name'])))
            }
        }
    }
    $rExistingAi.Close()

    $cmdExistingDiMap = $sqlCn.CreateCommand()
    $cmdExistingDiMap.CommandText = @"
SELECT point_id, start_address
FROM dbo.plc_di_map
WHERE plc_id = @plc_id AND enabled = 1
"@
    [void]$cmdExistingDiMap.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
    $cmdExistingDiMap.Parameters['@plc_id'].Value = $PlcId
    $rExistingDiMap = $cmdExistingDiMap.ExecuteReader()
    while ($rExistingDiMap.Read()) {
        $existingDiMapEnabled++
        $pointId = [int]$rExistingDiMap['point_id']
        if (-not $newDiMapKeySet.Contains([string]$pointId)) {
            $disabledDiMapCount++
            if ($disabledDiMapSamples.Count -lt 10) {
                $disabledDiMapSamples.Add(("point_id={0}, start_address={1}" -f $pointId, [int]$rExistingDiMap['start_address']))
            }
        }
    }
    $rExistingDiMap.Close()

    $cmdExistingDiTag = $sqlCn.CreateCommand()
    $cmdExistingDiTag.CommandText = @"
SELECT point_id, di_address, bit_no, tag_name, item_name, panel_name
FROM dbo.plc_di_tag_map
WHERE plc_id = @plc_id AND enabled = 1
"@
    [void]$cmdExistingDiTag.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
    $cmdExistingDiTag.Parameters['@plc_id'].Value = $PlcId
    $rExistingDiTag = $cmdExistingDiTag.ExecuteReader()
    while ($rExistingDiTag.Read()) {
        $existingDiTagEnabled++
        $tagName = Normalize-Str $rExistingDiTag['tag_name']
        if ($tagName.ToUpperInvariant().Contains('ELD')) { $existingEldTagEnabled++ }
        $key = "{0}|{1}|{2}" -f ([int]$rExistingDiTag['point_id']), ([int]$rExistingDiTag['di_address']), ([int]$rExistingDiTag['bit_no'])
        if (-not $newDiTagKeySet.Contains($key)) {
            $disabledDiTagCount++
            if ($disabledDiTagSamples.Count -lt 12) {
                $disabledDiTagSamples.Add((
                    "point_id={0}, addr={1}, bit={2}, tag={3}, item={4}, panel={5}" -f
                    ([int]$rExistingDiTag['point_id']),
                    ([int]$rExistingDiTag['di_address']),
                    ([int]$rExistingDiTag['bit_no']),
                    $tagName,
                    (Normalize-Str $rExistingDiTag['item_name']),
                    (Normalize-Str $rExistingDiTag['panel_name'])
                ))
            }
        }
    }
    $rExistingDiTag.Close()

    $disableSummary = [PSCustomObject]@{
        ai_disabled = $disabledAiCount
        di_map_disabled = $disabledDiMapCount
        di_tag_disabled = $disabledDiTagCount
        existing_ai_enabled = $existingAiEnabled
        existing_di_map_enabled = $existingDiMapEnabled
        existing_di_tag_enabled = $existingDiTagEnabled
        existing_eld_tag_enabled = $existingEldTagEnabled
        new_eld_tag_count = $newEldTagCount
        ai_disabled_samples = $disabledAiSamples
        di_map_disabled_samples = $disabledDiMapSamples
        di_tag_disabled_samples = $disabledDiTagSamples
    }

    if ($Apply.IsPresent -and -not $AllowDisable.IsPresent) {
        if ($disabledAiCount -gt 0 -or $disabledDiMapCount -gt 0 -or $disabledDiTagCount -gt 0) {
            throw ("This apply would disable existing mappings. Preview first and re-run with disable confirmation. ai={0}, di_map={1}, di_tag={2}" -f $disabledAiCount, $disabledDiMapCount, $disabledDiTagCount)
        }
    }

    if ($Apply.IsPresent) {
        $tx = $sqlCn.BeginTransaction()
        try {
            $aiMatchSyncUpdated = Apply-AiMatchSync -sqlCn $sqlCn -tx $tx -syncMap $aiMatchSyncMap

            # Soft-reset existing mappings for this PLC, then re-enable only rows present in Excel.
            foreach ($tbl in @('dbo.plc_meter_map', 'dbo.plc_di_map', 'dbo.plc_di_tag_map')) {
                $cmdDisable = $sqlCn.CreateCommand()
                $cmdDisable.Transaction = $tx
                $cmdDisable.CommandText = "UPDATE $tbl SET enabled = 0, updated_at = SYSUTCDATETIME() WHERE plc_id = @plc_id"
                [void]$cmdDisable.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
                $cmdDisable.Parameters['@plc_id'].Value = $PlcId
                [void]$cmdDisable.ExecuteNonQuery()
            }

            foreach ($r in $aiRows) {
                $cmd = $sqlCn.CreateCommand()
                $cmd.Transaction = $tx
                $cmd.CommandText = @"
MERGE dbo.plc_meter_map AS t
USING (SELECT @plc_id AS plc_id, @meter_id AS meter_id) s
ON (t.plc_id = s.plc_id AND t.meter_id = s.meter_id)
WHEN MATCHED THEN
  UPDATE SET start_address = @start_address,
             float_count = @float_count,
             byte_order = @byte_order,
             metric_order = @metric_order,
             enabled = 1,
             updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
  INSERT (plc_id, meter_id, start_address, float_count, byte_order, enabled, updated_at, metric_order)
  VALUES (@plc_id, @meter_id, @start_address, @float_count, @byte_order, 1, SYSUTCDATETIME(), @metric_order);
"@
                [void]$cmd.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@meter_id', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@start_address', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@float_count', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@byte_order', [System.Data.SqlDbType]::NVarChar, 10)
                [void]$cmd.Parameters.Add('@metric_order', [System.Data.SqlDbType]::NVarChar, -1)
                $cmd.Parameters['@plc_id'].Value = $PlcId
                $cmd.Parameters['@meter_id'].Value = [int]$r.meter_id
                $cmd.Parameters['@start_address'].Value = [int]$r.start_address
                $cmd.Parameters['@float_count'].Value = [int]$r.float_count
                $cmd.Parameters['@byte_order'].Value = $ByteOrder
                $cmd.Parameters['@metric_order'].Value = [string]$r.metric_order
                [void]$cmd.ExecuteNonQuery()
            }

            foreach ($k in $diMapByPoint.Keys) {
                $r = $diMapByPoint[$k]
                $cmd = $sqlCn.CreateCommand()
                $cmd.Transaction = $tx
                $cmd.CommandText = @"
MERGE dbo.plc_di_map AS t
USING (SELECT @plc_id AS plc_id, @point_id AS point_id) s
ON (t.plc_id = s.plc_id AND t.point_id = s.point_id)
WHEN MATCHED THEN
  UPDATE SET start_address = @start_address,
             bit_count = @bit_count,
             enabled = 1,
             updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
  INSERT (plc_id, point_id, start_address, bit_count, enabled, updated_at)
  VALUES (@plc_id, @point_id, @start_address, @bit_count, 1, SYSUTCDATETIME());
"@
                [void]$cmd.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@point_id', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@start_address', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@bit_count', [System.Data.SqlDbType]::Int)
                $cmd.Parameters['@plc_id'].Value = $PlcId
                $cmd.Parameters['@point_id'].Value = [int]$r.point_id
                $cmd.Parameters['@start_address'].Value = [int]$r.start_address
                $cmd.Parameters['@bit_count'].Value = [int]$r.bit_count
                [void]$cmd.ExecuteNonQuery()
            }

            foreach ($r in $diTags) {
                $cmd = $sqlCn.CreateCommand()
                $cmd.Transaction = $tx
                $cmd.CommandText = @"
MERGE dbo.plc_di_tag_map AS t
USING (SELECT @plc_id AS plc_id, @point_id AS point_id, @di_address AS di_address, @bit_no AS bit_no) s
ON (t.plc_id = s.plc_id AND t.point_id = s.point_id AND t.di_address = s.di_address AND t.bit_no = s.bit_no)
WHEN MATCHED THEN
  UPDATE SET tag_name = @tag_name,
             item_name = @item_name,
             panel_name = @panel_name,
             enabled = 1,
             updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
  INSERT (plc_id, point_id, di_address, bit_no, tag_name, item_name, panel_name, enabled, updated_at)
  VALUES (@plc_id, @point_id, @di_address, @bit_no, @tag_name, @item_name, @panel_name, 1, SYSUTCDATETIME());
"@
                [void]$cmd.Parameters.Add('@plc_id', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@point_id', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@di_address', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@bit_no', [System.Data.SqlDbType]::Int)
                [void]$cmd.Parameters.Add('@tag_name', [System.Data.SqlDbType]::NVarChar, 255)
                [void]$cmd.Parameters.Add('@item_name', [System.Data.SqlDbType]::NVarChar, 255)
                [void]$cmd.Parameters.Add('@panel_name', [System.Data.SqlDbType]::NVarChar, 255)
                $cmd.Parameters['@plc_id'].Value = $PlcId
                $cmd.Parameters['@point_id'].Value = [int]$r.point_id
                $cmd.Parameters['@di_address'].Value = [int]$r.di_address
                $cmd.Parameters['@bit_no'].Value = [int]$r.bit_no
                $cmd.Parameters['@tag_name'].Value = $r.tag_name
                $cmd.Parameters['@item_name'].Value = $r.item_name
                $cmd.Parameters['@panel_name'].Value = $r.panel_name
                [void]$cmd.ExecuteNonQuery()
            }

            $tx.Commit()
            $aiMatchSyncPlan | Add-Member -NotePropertyName applied_count -NotePropertyValue $aiMatchSyncUpdated -Force
        } catch {
            $tx.Rollback()
            throw
        }
    }

    $floatUsedLocal = $effectiveFloatCount
    if ($aiRows.Count -gt 0) {
        $floatUsedLocal = @($aiRows | ForEach-Object { [int]$_.float_count } | Measure-Object -Maximum).Maximum
    }

    $floatDist = @{}
    $floatMeters = @{}
    foreach ($r in $aiRows) {
        $k = [string]([int]$r.float_count)
        if (-not $floatDist.ContainsKey($k)) { $floatDist[$k] = 0 }
        $floatDist[$k] += 1
        if (-not $floatMeters.ContainsKey($k)) { $floatMeters[$k] = New-Object System.Collections.Generic.List[int] }
        $floatMeters[$k].Add([int]$r.meter_id)
    }
    $aiRowsSample = @($aiRows | Select-Object -First 20)

    $out = [PSCustomObject]@{
        ok = $true
        mode = $(if ($Apply.IsPresent) { 'apply' } else { 'preview' })
        plc_id = $PlcId
        excel_path = $ExcelPath
        ai_sheet_rows = $aiSheet.Rows.Count
        di_sheet_rows = $diSheet.Rows.Count
        ai_candidates = $aiCandidateCount
        ai_rows = $aiRows.Count
        ai_unmatched = $aiUnmatched
        float_count_used = $floatUsedLocal
        ai_float_distribution = $floatDist
        ai_float_meter_ids = $floatMeters
        ai_rows_sample = $aiRowsSample
        ai_rows_preview = $aiRows
        di_map_rows = $diMapByPoint.Count
        di_tag_rows = $diTags.Count
        ai_match_sync = $aiMatchSyncPlan
        disable_summary = $disableSummary
        allow_disable = [bool]$AllowDisable.IsPresent
    }
    Write-JsonResult -obj $out -depth 6
    }
    finally {
        $sqlCn.Close()
    }
}
catch {
    $line = $_.InvocationInfo.ScriptLineNumber
    $msg = $_.Exception.Message
    $src = $_.InvocationInfo.Line
    $errObj = [PSCustomObject]@{
        ok = $false
        line = $line
        message = $msg
        source = $src
    }
    Write-JsonResult -obj $errObj -depth 4
    exit 1
}
