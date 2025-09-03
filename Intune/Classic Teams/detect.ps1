$teamsDetected = $false
$logName = "IntuneScript"
$sourceName = "TeamsDetectionScript"
$logFile = "C:\TaurisIT\Log\TeamsDetection.log"

# Import modulu LogHelper
Import-Module LogHelper -ErrorAction SilentlyContinue

# Vytvor Event Log, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        New-EventLog -LogName $logName -Source $sourceName
        Write-CustomLog -Message "Event Log '$logName' a zdroj '$sourceName' boli vytvorene." `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani Event Logu: $_" `
                        -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
}

# 1. Kontrola pouzivatelskych priecinkov
$paths = @(
    "$env:LOCALAPPDATA\Microsoft\Teams",
    "$env:APPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\SquirrelTemp",
    "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        $teamsDetected = $true
        Write-CustomLog -Message "Teams priecinok detekovany: $p" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        break
    }
}

# 2. Kontrola systemovych priecinkov
$systemPaths = @(
    "C:\ProgramData\Teams",
    "C:\Program Files (x86)\Teams Installer"
)

foreach ($p in $systemPaths) {
    if (Test-Path $p) {
        $teamsDetected = $true
        Write-CustomLog -Message "Systemovy priecinok Teams detekovany: $p" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        break
    }
}

# 3. Kontrola Machine-Wide Installer cez WMI
try {
    $teamsInstaller = Get-WmiObject -Class Win32_Product | Where-Object {
        $_.Name -like "*Teams*" -and $_.Name -like "*Machine-Wide Installer*"
    }
    if ($teamsInstaller) {
        $teamsDetected = $true
        Write-CustomLog -Message "Machine-Wide Installer detekovany cez WMI." `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "WMI dotaz zlyhal: $($_.Exception.Message)" `
                    -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# Vysledok
if ($teamsDetected) {
    Write-Host "Microsoft Teams Classic je pritomny"
    Write-CustomLog -Message "Teams Classic detekovany. Skript konci s kodom 1." `
                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    exit 1
} else {
    Write-Host "Microsoft Teams Classic nie je pritomny"
    Write-CustomLog -Message "Teams Classic nebol detekovany. Skript konci s kodom 0." `
                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    exit 0
}