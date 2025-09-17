<#
.SYNOPSIS
    Instalacia alebo aktualizacia PowerShell modulu LogHelper.

.DESCRIPTION
    Skript skontroluje existenciu modulu LogHelper, porovna verziu, a ak je starsia alebo chyba, nahradi ju novou verziou.
    Zapisuje priebeh do .txt logu a Event Logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-05

.VERSION
    1.0.0

.NOTES
    Modul sa instaluje do C:\Program Files\WindowsPowerShell\Modules\LogHelper
    Logy sa ukladaju do C:\ProgramData\LogHelper\install_update_log.txt
#>

# Nastavenie cesty k modulu a logovaciemu suboru
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogFile = "$env:ProgramData\LogHelper\install_update_log.txt"
$NewVersion = "1.5.0"
$VersionFile = "$ModulePath\version.txt"

# Vytvorenie adresara pre log ak neexistuje
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

# Funkcia na zapisovanie sprav do logu
function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
    Write-Output $Message
}

# Zaciatok instalacie/aktualizacie
Write-Log "Spustam instalaciu/aktualizaciu modulu LogHelper..."

$needsUpdate = $true

# Kontrola existencie verzie modulu
if (Test-Path $VersionFile) {
    $currentVersion = Get-Content $VersionFile
    if ($currentVersion -eq $NewVersion) {
        Write-Log "Modul je uz vo verzii $NewVersion. Aktualizacia nie je potrebna."
        $needsUpdate = $false
    }
    else {
        Write-Log "Zistena starsia verzia ($currentVersion). Aktualizujem na $NewVersion."
    }
}
else {
    Write-Log "Modul neexistuje alebo chyba verzia. Instalujem novu verziu $NewVersion."
}

# Ak je potrebna aktualizacia alebo instalacia
if ($needsUpdate) {
    # Odstranenie stareho modulu ak existuje
    if (Test-Path $ModulePath) {
        Remove-Item -Path $ModulePath -Recurse -Force
        Write-Log "Odstraneny stary modul."
    }

    # Vytvorenie noveho adresara a kopirovanie noveho modulu
    New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
    Copy-Item -Path ".\LogHelper.psm1" -Destination "$ModulePath\LogHelper.psm1" -Force
    Set-Content -Path $VersionFile -Value $NewVersion
    Write-Log "Novy modul skopirovany a verzia zapisane."
}

# Ukoncenie operacie
Write-Log "Operacia dokoncena."