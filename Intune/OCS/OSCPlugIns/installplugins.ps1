<#
.SYNOPSIS
    Instalacny skript pre ScriptCopy - Intune Package
.DESCRIPTION
    Nakopiruje PS1 skripty zo zdrojoveho adresara do cieloveho umiestnenia,
    vytvori potrebne adresare a zaznamenava akcie do log suboru a Event Logu.
    Podporuje parameter -ForceUpdate pre aktualizaciu existujucich skriptov.
.AUTHOR
    Marek Findrik
.CREATED
    2025-10-03
.VERSION
    1.1
.NOTES
    Optimalizovane pre nasadenie cez Microsoft Intune.
    Spusta sa automaticky s SYSTEM pravami.
    Loguje do konzoly, suboru a event logu cez LogHelper modul.
#>

param (
    [switch]$ForceUpdate
)

# --------------------------------------------------------------------
# Import LogHelper
# --------------------------------------------------------------------
try {
    if (-not (Get-Module -ListAvailable -Name LogHelper)) {
        Write-Host "CHYBA: Modul LogHelper nie je dostupny." -ForegroundColor Red
        exit 1
    }
    Import-Module LogHelper -Force
}
catch {
    Write-Host "CHYBA: Nepodarilo sa importovat LogHelper modul. $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------------
# Premenne
# --------------------------------------------------------------------
$ScriptPath = "$PSScriptRoot\Files"
$TargetPath = "C:\Program Files\OCS Inventory Agent\Plugins"
$LogFileName = "C:\TaurisIT\Log\OCSPlugIns\ScriptCopy_{0}.txt" -f (Get-Date -Format "yyyyMMdd")

# LogHelper konfiguracia
$EventLogName = "IntuneScript"
$EventSource = "OCS PlugIns"

try {
    # vytvor cielovy adresar
    if (!(Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        Write-Host "Vytvoreny adresar: $TargetPath" -ForegroundColor Green
        Write-CustomLog -Message "Vytvoreny adresar: $TargetPath" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Information -EventId 1100
    }

    # ziskaj vsetky PS1 subory
    $SourceFiles = Get-ChildItem -Path $ScriptPath -Filter "*.ps1"
    
    foreach ($File in $SourceFiles) {
        $DestinationFile = Join-Path $TargetPath $File.Name
        
        if (!(Test-Path $DestinationFile)) {
            Copy-Item -Path $File.FullName -Destination $DestinationFile -Force
            Write-Host "Kopirovany novy subor: $($File.Name)" -ForegroundColor Green
            Write-CustomLog -Message "Kopirovany novy subor: $($File.Name)" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Information -EventId 1200
        }
        elseif ($ForceUpdate) {
            Copy-Item -Path $File.FullName -Destination $DestinationFile -Force
            Write-Host "Aktualizovany subor: $($File.Name)" -ForegroundColor Yellow
            Write-CustomLog -Message "Aktualizovany subor: $($File.Name)" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Warning -EventId 1210
        }
        else {
            Write-Host "Subor uz existuje (preskoceny): $($File.Name)" -ForegroundColor Gray
            Write-CustomLog -Message "Subor uz existuje (preskoceny): $($File.Name)" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Information -EventId 1220
        }
    }
    
    Write-CustomLog -Message "Kopirovanie skriptov bolo uspesne dokoncene." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Information -EventId 1999
    exit 0
}
catch {
    Write-Host "CHYBA: $($_.Exception.Message)" -ForegroundColor Red
    Write-CustomLog -Message "CHYBA: $($_.Exception.Message)" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Error -EventId 1400
    exit 1
}
