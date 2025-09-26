<#
.SYNOPSIS
    Intune App Trace Script s GUI výberom aplikácie
.DESCRIPTION
    Skript sa pripája na Microsoft Graph API, načíta aplikácie z Intune
    a zobrazí ich pomocou Out-GridView. Po výbere aplikácie spustí logovanie.
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-24
.VERSION
    2.0.0
.NOTES
    Vyžaduje modul Microsoft.Graph a prístupové práva k Intune (DeviceAppManagement.Read.All).
    Logy: C:\ProgramData\LogHelper\trace_log.txt
#>

#region --- Nastavenie premenných ---
$LogFolder = "C:\ProgramData\LogHelper"
$LogFile = Join-Path $LogFolder "trace_log.txt"
$EventSource = "IntuneAppTrace"
$EventLogName = "Application"
$RequiredModules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceAppManagement")
#endregion

#region --- Funkcie ---
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"

    Add-Content -Path $LogFile -Value $logEntry

    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        New-EventLog -LogName $EventLogName -Source $EventSource
    }
    Write-EventLog -LogName $EventLogName -Source $EventSource -EventId 1000 -EntryType Information -Message $logEntry
}
#endregion

#region --- Kontrola a inštalácia modulov ---
foreach ($mod in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        try {
            Write-Host "Inštalujem chýbajúci modul: $mod" -ForegroundColor Yellow
            Install-Module $mod -Force -Scope AllUsers -AllowClobber
        }
        catch {
            Write-Log "Nepodarilo sa nainštalovať modul $mod $_" "ERROR"
            throw
        }
    }
    Import-Module $mod -Force
}
#endregion

#region --- Príprava log priečinka ---
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
#endregion

#region --- Pripojenie ku Graph API ---
try {
    Connect-MgGraph -Scopes "DeviceAppManagement.Read.All"
    Write-Log "Pripojenie ku Graph API úspešné." "INFO"
}
catch {
    Write-Log "Nepodarilo sa pripojiť ku Graph API: $_" "ERROR"
    throw
}
#endregion

#region --- Načítanie aplikácií z Intune ---
try {
    $apps = Get-MgDeviceAppManagementMobileApp -All | 
    Select-Object DisplayName, Publisher, Id, LastModifiedDateTime

    if (-not $apps) {
        Write-Log "Neboli nájdené žiadne aplikácie v Intune." "WARN"
        exit
    }
}
catch {
    Write-Log "Chyba pri načítaní aplikácií z Intune: $_" "ERROR"
    throw
}
#endregion

#region --- Výber aplikácie cez GUI ---
$selectedApp = $apps | Out-GridView -Title "Vyber aplikáciu z Intune" -PassThru

if (-not $selectedApp) {
    Write-Host "Žiadna aplikácia nebola vybraná." -ForegroundColor Yellow
    Write-Log "Užívateľ nevybral žiadnu aplikáciu." "WARN"
    exit
}

Write-Host "Vybraná aplikácia: $($selectedApp.DisplayName)" -ForegroundColor Green
Write-Log "Vybraná aplikácia: $($selectedApp.DisplayName)" "INFO"
#endregion

#region --- Simulácia trasovania ---
Write-Log "Spúšťam trasovanie pre $($selectedApp.DisplayName)" "INFO"
Start-Sleep -Seconds 5
Write-Log "Trasovanie ukončené pre $($selectedApp.DisplayName)" "INFO"
#endregion
