$TaskName = "SetPasswordDaily"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password"

if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName $EventLogName -Source $EventSource
}

function Write-EventLogEntry {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [int]$EventID = 1001
    )
    Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventID -Message $Message
}

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-EventLogEntry -Message "Planovana uloha '$TaskName' bola uspesne odstranena." -Type "Information"
} catch {
    Write-EventLogEntry -Message "CHYBA pri odstranovani ulohy '$TaskName': $_" -Type "Error"
}