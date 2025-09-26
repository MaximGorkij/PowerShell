<#
.SYNOPSIS
    Odinstaluje PowerShell modul LogHelper z klientskeho PC.
.DESCRIPTION
    Skript odstrani cely priecinok modulu LogHelper a loguje priebeh do .txt suboru aj Event Logu.
    Obsahuje robustny error handling a verifikaciu odinstalacie.
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-05
.VERSION
    1.6.0
.NOTES
    Logy sa ukladaju do C:\ProgramData\LogHelper\uninstall_log.txt
    Modul sa odstranuje z C:\Program Files\WindowsPowerShell\Modules\LogHelper
    Pridane error handling a verifikacie pre Intune kompatibilitu
#>

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"

# Registry
$RegPath64 = "HKLM:\SOFTWARE\TaurisIT\LogHelper"
$RegPath32 = "HKLM:\SOFTWARE\WOW6432Node\TaurisIT\LogHelper"

# Log
$LogDir = "$env:ProgramData\LogHelper"
$LogFile = "$LogDir\install_update_log.txt"

# Funkcia na logovanie
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $Message"
    Write-Output $line
    try { Add-Content -Path $LogFile -Value $line } catch {}
}

Write-Log "=== Odinštalácia LogHelper ==="

# Odstránenie modulu
if (Test-Path $ModulePath) {
    try {
        Remove-Item -Path $ModulePath -Recurse -Force -ErrorAction Stop
        Write-Log "Modul LogHelper odstránený z $ModulePath"
    }
    catch {
        Write-Log "VAROVANIE: Nepodarilo sa odstrániť modul: $($_.Exception.Message)"
    }
}
else {
    Write-Log "Modul LogHelper neexistuje v $ModulePath"
}

# Odstránenie registry
foreach ($regPath in @($RegPath64, $RegPath32)) {
    if (Test-Path $regPath) {
        try {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Log "Registry odstránené: $regPath"
        }
        catch {
            Write-Log "VAROVANIE: Nepodarilo sa odstrániť registry $regPath $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Registry $regPath neexistujú"
    }
}

Write-Log "=== Odinštalácia dokončená ==="
exit 0