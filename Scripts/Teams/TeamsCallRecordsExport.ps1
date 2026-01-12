param(
    [string]$OrganizerUpn = $env:DEFAULT_ORGANIZER,
    [datetime]$StartTime,
    [datetime]$EndTime
)

Import-Module "D:\findrik\PowerShell\Scripts\Teams\Load-Env.psm1"
Initialize-Env

$ClientId = $env:CLIENT_ID
$ExportDir = $env:EXPORT_DIR

if (-not (Test-Path $ExportDir)) {
    New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $ExportDir "TeamsCallRecords_Delegated.log"
$CsvFile = Join-Path $ExportDir ("TeamsCallRecords_{0}_{1:yyyyMMdd}_{2:yyyyMMdd}.csv" -f `
    ($OrganizerUpn -replace "@", "_"), $StartTime, $EndTime)

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[Delegated] $ts $Message"
    $entry | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    Write-Host $entry
}

Write-Log "Starting delegated export. Organizer=$OrganizerUpn"

Import-Module Microsoft.Graph -ErrorAction Stop

$Scopes = @(
    "CallRecords.Read.All",
    "OnlineMeetings.Read.All",
    "User.Read",
    "Reports.Read.All"
)

Connect-MgGraph -ClientId $ClientId -Scopes $Scopes

Write-Log "Connected to Graph."

# PAGINÁCIA - získanie VŠETKYCH záznamov
$allRecords = @()
$page = Get-MgCommunicationCallRecord -PageSize 999 -All

foreach ($rec in $page) {
    $org = $rec.Organizer.Identity.User.Id
    if ($org -and ($org -ieq $OrganizerUpn)) {
        $start = [datetime]$rec.StartDateTime
        if ($start -ge $StartTime -and $start -le $EndTime) {
            $allRecords += [pscustomobject]@{
                Id            = $rec.Id
                OrganizerUpn  = $org
                StartDateTime = $rec.StartDateTime
                EndDateTime   = $rec.EndDateTime
                Modalities    = ($rec.Modalities -join ",")
                CallType      = $rec.Type
                Duration      = if ($rec.EndDateTime -and $rec.StartDateTime) {
                    New-TimeSpan -Start $rec.StartDateTime -End $rec.EndDateTime
                }
                else { $null }
            }
        }
    }
}

if ($allRecords.Count -gt 0) {
    $allRecords | Export-Csv -Path $CsvFile -Encoding UTF8 -NoTypeInformation
    Write-Log "Export complete: $CsvFile ($($allRecords.Count) records)"
}
else {
    Write-Log "No records found for the specified criteria"
}

Disconnect-MgGraph