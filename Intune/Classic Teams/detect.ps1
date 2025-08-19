$teamsDetected = $false
$logName = "IntuneScript"
$sourceName = "TeamsDetectionScript"

# Vytvor Event Log, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    New-EventLog -LogName $logName -Source $sourceName
}

# 1. Kontrola používateľských priečinkov
$paths = @(
    "$env:LOCALAPPDATA\Microsoft\Teams",
    "$env:APPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\SquirrelTemp",
    "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        $teamsDetected = $true
        Write-EventLog -LogName $logName -Source $sourceName -EntryType Information -EventId 1001 -Message "Teams folder detected: $p"
        break
    }
}

# 2. Kontrola systémových priečinkov
$systemPaths = @(
    "C:\ProgramData\Teams",
    "C:\Program Files (x86)\Teams Installer"
)

foreach ($p in $systemPaths) {
    if (Test-Path $p) {
        $teamsDetected = $true
        Write-EventLog -LogName $logName -Source $sourceName -EntryType Information -EventId 1002 -Message "System-level Teams folder detected: $p"
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
        Write-EventLog -LogName $logName -Source $sourceName -EntryType Information -EventId 1003 -Message "Machine-Wide Installer detected via WMI"
    }
} catch {
    Write-EventLog -LogName $logName -Source $sourceName -EntryType Warning -EventId 9001 -Message "WMI query failed: $($_.Exception.Message)"
}

# Výsledok
if ($teamsDetected) {
    Write-Host "Microsoft Teams Classic is present"
    Write-EventLog -LogName $logName -Source $sourceName -EntryType Information -EventId 2001 -Message "Teams Classic detected. Exiting with code 1."
    exit 1
} else {
    Write-Host "Microsoft Teams Classic is not present"
    Write-EventLog -LogName $logName -Source $sourceName -EntryType Information -EventId 2002 -Message "Teams Classic not detected. Exiting with code 0."
    exit 0
}