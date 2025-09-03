# Premenne
$taskName = "SetPasswordDaily"
$scriptPath = "C:\TaurisIT\skript\SetPassMOP-v5.ps1"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Detect"
$LogFileName = "C:\TaurisIT\log\DetectionLog.txt"

# Vytvorenie Event Logu a zdroja, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName $EventLogName -Source $EventSource
}

# Funkcia na logovanie
function Write-CustomLog {
    param (
        [string]$Message,
        [string]$Type = "Information",  # Information, Warning, Error
        [int]$EventId = 1000,
        [string]$LogFile = $LogFileName
    )

    # Zapis do Event Logu
    Write-EventLog -LogName $EventLogName -Source $EventSource -EventId $EventId -EntryType $Type -Message $Message

    # Zapis do textoveho logu
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$timestamp [$Type] $Message"
}

# Kontrola naplanovanej ulohy
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# Kontrola existencie skriptu
$scriptExists = Test-Path $scriptPath

# Vyhodnotenie a logovanie
if ($taskExists -and $scriptExists) {
    Write-Output "Detected"
    Write-CustomLog -Message "Detekcia uspesna: Uloha '$taskName' a skript '$scriptPath' existuju." -Type "Information" -EventId 1000
    exit 0
} elseif (-not $taskExists -and -not $scriptExists) {
    Write-Output "Not Detected"
    Write-CustomLog -Message "Detekcia zlyhala: Uloha ani skript neexistuju. Uloha: '$taskName', Skript: '$scriptPath'." -Type "Error" -EventId 1002
    exit 1
} elseif (-not $taskExists) {
    Write-Output "Not Detected"
    Write-CustomLog -Message "Varovanie: Skript existuje, ale uloha '$taskName' chyba." -Type "Warning" -EventId 1003
    exit 1
} elseif (-not $scriptExists) {
    Write-Output "Not Detected"
    Write-CustomLog -Message "Varovanie: Uloha existuje, ale skript '$scriptPath' chyba." -Type "Warning" -EventId 1004
    exit 1
}