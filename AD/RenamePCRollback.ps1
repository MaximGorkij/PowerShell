<#
.SYNOPSIS
    Rollback premenovanych pocitacov v Active Directory podla backup CSV.
.DESCRIPTION
    Skript obnovi povodne nazvy pocitacov z posledneho alebo vybraneho backupu.
    Obsahuje TestMode rezim, logovanie a ochranu pred duplicitami.
.PARAMETER TestMode
    Simulacia rollbacku bez skutocneho vykonania.
.AUTHOR
    Uprava podla LogHelper modulu
.CREATED
    2025-10-03
.VERSION
    1.0.0
.NOTES
    - Vyzaduje Active Directory modul
    - Backup sa ocakava v: C:\TaurisIT\Backup\AD_Rename
    - Logy sa ukladaju do: C:\TaurisIT\Log
    - EventLogName: CustomizeAD
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$TestMode
)

#region LogHelper
function Write-CustomLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$EventSource,
        [string]$EventLogName = "CustomizeAD",
        [Parameter(Mandatory = $true)]
        [string]$LogFileName,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"
    )
    $LogDirectory = "C:\TaurisIT\Log"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    $LogFilePath = Join-Path $LogDirectory $LogFileName
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Type] - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try { New-EventLog -LogName $EventLogName -Source $EventSource } catch {}
    }
    switch ($Type) {
        "Information" { $EventId = 1100 }
        "Warning" { $EventId = 2100 }
        "Error" { $EventId = 3100 }
        default { $EventId = 9999 }
    }
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message
    }
    catch {}
}
#endregion

#region Inicializacia
$ErrorActionPreference = "Stop"
$ScriptName = "AD-ComputerRollback"
$LogFileName = "AD_Rollback_$(Get-Date -Format 'yyyyMMdd').txt"
$EventSource = "AD_Rename_Rollback"

Write-CustomLog -Message "========== SPUSTENIE ROLLBACK ==========" -EventSource $EventSource -LogFileName $LogFileName -Type Information
Write-CustomLog -Message "Rezim: $(if($TestMode){'SIMULACIA (TestMode)'}else{'PRODUKCNY'})" -EventSource $EventSource -LogFileName $LogFileName -Type Information

# Kontrola AD modulu
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-CustomLog -Message "CRITICAL: Active Directory modul nie je nainstalovany!" -EventSource $EventSource -LogFileName $LogFileName -Type Error
    Write-Host "Active Directory modul nie je dostupny. Ukoncujem." -ForegroundColor Red
    exit 1
}
Import-Module ActiveDirectory
#endregion

#region Vyber backupu
$BackupDir = "C:\TaurisIT\Backup\AD_Rename"
if (-not (Test-Path $BackupDir)) {
    Write-Host "Backup adresar neexistuje: $BackupDir" -ForegroundColor Red
    exit 1
}

$backups = Get-ChildItem -Path $BackupDir -Filter "*.csv" | Sort-Object LastWriteTime -Descending
if ($backups.Count -eq 0) {
    Write-Host "Neboli najdene ziadne backupy." -ForegroundColor Red
    exit 1
}

Write-Host "`nDostupne backupy:" -ForegroundColor Cyan
for ($i = 0; $i -lt $backups.Count; $i++) {
    Write-Host "[$i] $($backups[$i].Name) ($($backups[$i].LastWriteTime))"
}
[int]$choice = Read-Host "`nZadaj cislo backupu pre rollback"
if ($choice -lt 0 -or $choice -ge $backups.Count) {
    Write-Host "Neplatna volba." -ForegroundColor Red
    exit 1
}
$backupFile = $backups[$choice].FullName
Write-Host "`nVybrany backup: $backupFile" -ForegroundColor Green
Write-CustomLog -Message "Rollback zo suboru: $backupFile" -EventSource $EventSource -LogFileName $LogFileName -Type Information

$csv = Import-Csv -Path $backupFile
#endregion

#region Rollback proces
$totalRestored = 0
$totalSkipped = 0
$totalErrors = 0

foreach ($entry in $csv) {
    try {
        $dn = $entry.DistinguishedName
        $originalName = $entry.Name

        # Ziskaj aktualne meno v AD
        $adComp = Get-ADComputer -Identity $dn -Properties Name -ErrorAction Stop
        $currentName = $adComp.Name

        if ($currentName -eq $originalName) {
            Write-Host "$currentName uz ma povodny nazov - preskakujem" -ForegroundColor Gray
            $totalSkipped++
            continue
        }

        $targetName = $originalName

        if ($TestMode) {
            Write-Host "[TESTMODE] Premenoval by som: $currentName -> $targetName" -ForegroundColor Yellow
            Write-CustomLog -Message "[TESTMODE] $currentName -> $targetName" -EventSource $EventSource -LogFileName $LogFileName -Type Information
            $totalRestored++
        }
        else {
            Write-Host "Obnovujem: $currentName -> $targetName" -ForegroundColor Yellow
            Rename-ADComputer -Identity $adComp.DistinguishedName -NewName $targetName -ErrorAction Stop
            Write-Host "Obnovene: $targetName" -ForegroundColor Green
            Write-CustomLog -Message "USPECH rollback: $currentName -> $targetName" -EventSource $EventSource -LogFileName $LogFileName -Type Information
            $totalRestored++
        }
    }
    catch {
        Write-Host "Chyba pri rollbacku $($entry.Name): $($_.Exception.Message)" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA rollbacku $($entry.Name): $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Error
        $totalErrors++
    }
}

# Zhrnutie
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   ZHRNUTIE ROLLBACK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rezim: $(if($TestMode){'SIMULACIA'}else{'PRODUKCNY'})" -ForegroundColor $(if ($TestMode) { "Yellow" }else { "Green" })
Write-Host "Obnovenych: $totalRestored" -ForegroundColor Green
Write-Host "Preskocenych: $totalSkipped" -ForegroundColor Gray
Write-Host "Chyb: $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { "Red" }else { "Green" })
Write-Host "========================================`n" -ForegroundColor Cyan

Write-CustomLog -Message "ZHRNUTIE rollback: Obnovenych=$totalRestored, Preskocenych=$totalSkipped, Chyb=$totalErrors" -EventSource $EventSource -LogFileName $LogFileName -Type Information
Write-CustomLog -Message "========== ROLLBACK UKONCENY ==========" -EventSource $EventSource -LogFileName $LogFileName -Type Information
#endregion
