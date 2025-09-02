# Premenné
$taskName = "SetPasswordDaily"
$scriptPath = "C:\TaurisIT\skript\SetPassMOP-v5.ps1"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password DFetect"

# Kontrola naplánovanej úlohy
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# Kontrola existencie skriptu
$scriptExists = Test-Path $scriptPath

# Vytvorenie Event Logu a zdroja, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName $EventLogName -Source $EventSource
}

# Vyhodnotenie a logovanie
if ($taskExists -and $scriptExists) {
    Write-Output "Detected"
    Write-EventLog -LogName $EventLogName -Source $EventSource -EventId 1000 -EntryType Information -Message "Detekcia uspesna: Uloha '$taskName' a skript '$scriptPath' existuju."
    exit 0
} else {
    Write-Output "Not Detected"
    Write-EventLog -LogName $EventLogName -Source $EventSource -EventId 1001 -EntryType Warning -Message "Detekcia zlyhala: Uloha alebo skript neexistuju. Uloha: '$taskName', Skript: '$scriptPath'."
    exit 1
}