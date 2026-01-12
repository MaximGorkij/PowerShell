param(
    [datetime]$Date = (Get-Date).AddDays(-1)  # Default: včerajší deň
)

# Konzistentná cesta k modulu
Import-Module "D:\findrik\PowerShell\Scripts\Teams\Load-Env.psm1"
Initialize-Env

$ClientId = $env:CLIENT_ID
$ExportDir = $env:EXPORT_DIR

if (-not (Test-Path $ExportDir)) {
    New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
}

$CsvFile = Join-Path $ExportDir ("TeamsUserActivity_{0:yyyyMMdd}.csv" -f $Date)
$LogFile = Join-Path $ExportDir "TeamsUserActivity.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[UserActivity] $ts $Message"
    $entry | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    Write-Host $entry
}

Write-Log "Starting Teams user activity export for date: $($Date.ToString('yyyy-MM-dd'))"

Import-Module Microsoft.Graph.Reports -ErrorAction Stop

Connect-MgGraph -ClientId $ClientId -Scopes "Reports.Read.All"

try {
    $stream = Get-MgReportTeamsUserActivityUserDetail -Date $Date.ToString("yyyy-MM-dd")
    
    if ($stream) {
        $reader = New-Object System.IO.StreamReader($stream)
        $content = $reader.ReadToEnd()
        $reader.Close()
        
        $content | Out-File -FilePath $CsvFile -Encoding UTF8
        Write-Log "Export complete: $CsvFile"
    }
    else {
        Write-Log "No data available for the specified date"
    }
}
catch {
    Write-Log "Error during export: $_"
}

Disconnect-MgGraph