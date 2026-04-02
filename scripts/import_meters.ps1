#Requires -Version 5.1
<#
.SYNOPSIS
    Imports meter registration data from a CSV file into the dbo.meters table.
.DESCRIPTION
    Reads a CSV file containing meter information. 
    If a row has a meter_id, it updates the existing record.
    If a row does not have a meter_id, it inserts a new record.
    Outputs the result of the operation as a JSON string.
.PARAMETER ExcelPath
    The full path to the input CSV file. The file must have a header row.
.EXAMPLE
    powershell.exe -File .\import_meters.ps1 -ExcelPath "C:	emp\my_meters.csv"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ExcelPath
)

function Write-Log {
    param ([string]$Message)
    Write-Output "LOG: $Message"
}

function Normalize-ColumnName {
    param ([string]$Name)
    if ($null -eq $Name) { return '' }
    return $Name.Trim().ToLowerInvariant()
}

function Convert-ObjectsToNormalizedRows {
    param ([object[]]$Items)
    $rows = @()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $obj = [ordered]@{}
        foreach ($prop in $item.PSObject.Properties) {
            $name = Normalize-ColumnName $prop.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $value = $prop.Value
            if ($value -is [System.DBNull]) { $value = $null }
            $obj[$name] = $value
        }
        $rows += [pscustomobject]$obj
    }
    return ,$rows
}

function Import-SpreadsheetRows {
    param ([string]$Path)
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $readerPath = Join-Path $scriptDir 'read_meters_xlsx.py'
    if (-not (Test-Path -Path $readerPath -PathType Leaf)) {
        throw "XLSX reader script not found: $readerPath"
    }
    $json = & python $readerPath $Path
    if ($LASTEXITCODE -ne 0) {
        throw (($json | Out-String).Trim())
    }
    if ([string]::IsNullOrWhiteSpace(($json | Out-String))) {
        return @()
    }
    $rows = $json | ConvertFrom-Json
    return Convert-ObjectsToNormalizedRows -Items $rows
}

function Import-InputRows {
    param ([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.csv' { return Convert-ObjectsToNormalizedRows -Items (Import-Csv -Path $Path) }
        '.xlsx' { return Import-SpreadsheetRows -Path $Path }
        '.xls' { throw "Legacy .xls files are not supported. Please save the file as .xlsx and upload again." }
        default { throw "Unsupported file type: $ext. Please upload a CSV or Excel file." }
    }
}

# --- Main Script ---

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$result = @{
    ok = $false
    mode = 'apply'
    file_path = $ExcelPath
    rows_total = 0
    rows_processed = 0
    inserts = 0
    updates = 0
    errors = @()
}

try {
    # --- Database Connection ---
    # IMPORTANT: The connection string is hardcoded here. 
    # This should be configured securely based on the server environment.
    # It might need to be changed to use SQL authentication (User ID/Password) instead of Integrated Security.
    $connString = "Server=localhost;Database=epms;Integrated Security=True;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    $conn.Open()
    Write-Log "Successfully connected to database."

    # --- File Check and Import ---
    if (-not (Test-Path -Path $ExcelPath)) {
        throw "File not found at path: $ExcelPath"
    }

    $data = Import-InputRows -Path $ExcelPath
    $result.rows_total = ($data | Measure-Object).Count
    Write-Log "Found $($result.rows_total) rows in the import file."

    # --- Process Rows ---
    foreach ($row in $data) {
        $result.rows_processed++
        $meterId = $row.meter_id

        # Define columns to be processed
        $columns = @("name", "building_name", "panel_name", "usage_type", "rated_voltage", "rated_current")
        $params = @{}

        # Prepare parameters for SQL command
        foreach ($col in $columns) {
            if ($row.PSObject.Properties.Match($col).Count -gt 0) {
                $params[$col] = $row.$col
            }
        }
        
        # Trim string values and handle nulls for numeric types
        if ($params.ContainsKey("name")) { $params.name = $params.name.Trim() }
        if ($params.ContainsKey("building_name")) { $params.building_name = $params.building_name.Trim() }
        if ($params.ContainsKey("panel_name")) { $params.panel_name = $params.panel_name.Trim() }
        if ($params.ContainsKey("usage_type")) { $params.usage_type = $params.usage_type.Trim() }

        if ([string]::IsNullOrWhiteSpace($params.rated_voltage)) {
            $params.rated_voltage = [System.DBNull]::Value
        }
        if ([string]::IsNullOrWhiteSpace($params.rated_current)) {
            $params.rated_current = [System.DBNull]::Value
        }

        # Check for required 'name' field
        if ([string]::IsNullOrWhiteSpace($params.name)) {
            $result.errors += "Row $($result.rows_processed): 'name' is required and cannot be empty."
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($meterId)) {
            # --- UPDATE logic ---
            try {
                $meterId = [int]$meterId
                $cmd = $conn.CreateCommand()

                # Check if meter_id exists
                $cmd.CommandText = "SELECT COUNT(*) FROM dbo.meters WHERE meter_id = @meter_id"
                $cmd.Parameters.AddWithValue("@meter_id", $meterId) | Out-Null
                $count = $cmd.ExecuteScalar()

                if ($count -eq 0) {
                    $result.errors += "Row $($result.rows_processed): meter_id '$meterId' not found for update. Skipping."
                    continue
                }

                # Build dynamic UPDATE statement
                $setClauses = @()
                foreach ($key in $params.Keys) {
                    $setClauses += "$key = @$key"
                }
                
                $cmd.CommandText = "UPDATE dbo.meters SET $($setClauses -join ', ') WHERE meter_id = @meter_id"
                $cmd.Parameters.Clear()
                $cmd.Parameters.AddWithValue("@meter_id", $meterId) | Out-Null
                foreach ($key in $params.Keys) {
                    $cmd.Parameters.AddWithValue("@$key", $params[$key]) | Out-Null
                }

                $affected = $cmd.ExecuteNonQuery()
                if ($affected -gt 0) {
                    $result.updates++
                }
            } catch {
                $result.errors += "Row $($result.rows_processed) (meter_id $meterId): UPDATE failed. Error: $($_.Exception.Message)"
            }

        } else {
            # --- INSERT logic ---
            try {
                $cmd = $conn.CreateCommand()
                
                # Build dynamic INSERT statement
                $colNames = $params.Keys
                $colValues = $params.Keys | ForEach-Object { "@$_" }

                $cmd.CommandText = "INSERT INTO dbo.meters ($($colNames -join ', ')) VALUES ($($colValues -join ', '))"
                foreach ($key in $params.Keys) {
                    $cmd.Parameters.AddWithValue("@$key", $params[$key]) | Out-Null
                }

                $affected = $cmd.ExecuteNonQuery()
                if ($affected -gt 0) {
                    $result.inserts++
                }
            } catch {
                $result.errors += "Row $($result.rows_processed): INSERT failed. Error: $($_.Exception.Message)"
            }
        }
    }

    $result.ok = $true
}
catch {
    $result.ok = $false
    $result.errors += "A critical error occurred: $($_.Exception.Message)"
}
finally {
    if ($conn -and $conn.State -eq 'Open') {
        $conn.Close()
        Write-Log "Database connection closed."
    }
    $stopwatch.Stop()
    $result.duration_ms = $stopwatch.ElapsedMilliseconds
    
    # --- Output JSON result to stdout ---
    Write-Output ($result | ConvertTo-Json -Compress)
}
