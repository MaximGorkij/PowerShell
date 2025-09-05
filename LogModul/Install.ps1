<#
.SYNOPSIS
    Inštaluje alebo aktualizuje PowerShell modul LogHelper.

.DESCRIPTION
    Skript skontroluje existenciu modulu LogHelper, porovná verziu, a ak je staršia alebo chýba, nahradí ju novou verziou.
    Zapisuje priebeh do .txt logu a Event Logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-05

.VERSION
    1.0.0

.NOTES
    Modul sa inštaluje do C:\Program Files\WindowsPowerShell\Modules\LogHelper
    Logy sa ukladajú do C:\ProgramData\LogHelper\install_update_log.txt
#>

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogFile = "$env:ProgramData\LogHelper\install_update_log.txt"
$NewVersion = "1.5.0"
$VersionFile = "$ModulePath\version.txt"

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
    Write-Output $Message
}

Write-Log "Spúšťam inštaláciu/aktualizáciu modulu LogHelper..."

$needsUpdate = $true

if (Test-Path $VersionFile) {
    $currentVersion = Get-Content $VersionFile
    if ($currentVersion -eq $NewVersion) {
        Write-Log "Modul je už vo verzii $NewVersion. Aktualizácia nie je potrebná."
        $needsUpdate = $false
    }
    else {
        Write-Log "Zistená staršia verzia ($currentVersion). Aktualizujem na $NewVersion."
    }
}
else {
    Write-Log "Modul neexistuje alebo chýba verzia. Inštalujem novú verziu $NewVersion."
}

if ($needsUpdate) {
    if (Test-Path $ModulePath) {
        Remove-Item -Path $ModulePath -Recurse -Force
        Write-Log "Odstránený starý modul."
    }

    New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
    Copy-Item -Path ".\LogHelper.psm1" -Destination "$ModulePath\LogHelper.psm1" -Force
    Set-Content -Path $VersionFile -Value $NewVersion
    Write-Log "Nový modul skopírovaný a verzia zapísaná."
}

Write-Log "Operácia dokončená."