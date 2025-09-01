$FolderPath = "C:\skript"
$ScriptName = "SetPassMOP-v5.ps1"
$ScriptPath = "$FolderPath\$ScriptName"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password"
$TaskName = "SetPasswordDaily"

if (-not (Test-Path $FolderPath)) {
    New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
}

if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName $EventLogName -Source $EventSource
}

function Write-EventLogEntry {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [int]$EventID = 1000
    )
    Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventID -Message $Message
}

try {
    Copy-Item -Path ".\$ScriptName" -Destination $ScriptPath -Force
    Write-EventLogEntry -Message "Skript '$ScriptName' bol skopirovany do '$FolderPath'." -Type "Information"
} catch {
    Write-EventLogEntry -Message "CHYBA pri kopirovani skriptu: $_" -Type "Error"
}

try {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -Daily -At "22:30"
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force

    Write-EventLogEntry -Message "Planovana uloha '$TaskName' bola uspesne vytvorena." -Type "Information"
} catch {
    Write-EventLogEntry -Message "CHYBA pri vytvarani ulohy '$TaskName': $_" -Type "Error"
}