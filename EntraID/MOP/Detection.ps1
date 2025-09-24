# Premenne
$taskName = "SetPasswordDaily"
$scriptPath = "C:\TaurisIT\skript\SetPassMOP-v5.ps1"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Detect"
$LogFileName = "C:\TaurisIT\log\DetectionLog.txt"

# Čakanie na dokončenie inštalácie
Start-Sleep -Seconds 20

# Vytvorenie adresára pre log ak neexistuje
$logDirectory = Split-Path $LogFileName -Parent
if (-not (Test-Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force
}

# Bezpečné vytvorenie Event Logu
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        New-EventLog -LogName $EventLogName -Source $EventSource
    }
}
catch {
    Write-Warning "Event Log sa nepodarilo vytvoriť: $($_.Exception.Message)"
}

# Funkcia na logovanie (bez zmien)
function Write-CustomLog {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [int]$EventId = 1000,
        [string]$LogFile = $LogFileName
    )
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EventId $EventId -EntryType $Type -Message $Message
    }
    catch {
        Write-Warning "Event Log zapis zlyhal: $($_.Exception.Message)"
    }
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "$timestamp [$Type] $Message"
    }
    catch {
        Write-Warning "File log zapis zlyhal: $($_.Exception.Message)"
    }
}

# Rozšírená kontrola scheduled task
$taskExists = $null
try {
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Write-CustomLog -Message "Kontrola scheduled task '$taskName': $(if($taskExists){'Existuje'}else{'Neexistuje'})" -Type "Information"
}
catch {
    Write-CustomLog -Message "Chyba pri kontrole scheduled task: $($_.Exception.Message)" -Type "Error" -EventId 1005
}

# Kontrola adresára a skriptu
$scriptDirectory = Split-Path $scriptPath -Parent
$directoryExists = Test-Path $scriptDirectory
$scriptExists = Test-Path $scriptPath

Write-CustomLog -Message "Kontrola adresara '$scriptDirectory': $(if($directoryExists){'Existuje'}else{'Neexistuje'})" -Type "Information"
Write-CustomLog -Message "Kontrola skriptu '$scriptPath': $(if($scriptExists){'Existuje'}else{'Neexistuje'})" -Type "Information"

# Vyhodnotenie
if ($taskExists -and $scriptExists) {
    Write-Output "Detected"
    Write-CustomLog -Message "Detekcia uspesna: Uloha '$taskName' a skript '$scriptPath' existuju." -Type "Information" -EventId 1000
    exit 0
}
else {
    Write-Output "Not Detected"
    $missingItems = @()
    if (-not $taskExists) { $missingItems += "scheduled task" }
    if (-not $scriptExists) { $missingItems += "skript" }
    
    Write-CustomLog -Message "Detekcia zlyhala. Chybaju: $($missingItems -join ', ')" -Type "Error" -EventId 1002
    exit 1
}