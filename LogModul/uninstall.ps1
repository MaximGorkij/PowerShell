<#
.SYNOPSIS
    Odinštaluje PowerShell modul LogHelper z klientského PC.

.DESCRIPTION
    Skript odstráni celý priečinok modulu LogHelper a loguje priebeh do .txt súboru aj Event Logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-05

.VERSION
    1.0.0

.NOTES
    Logy sa ukladajú do C:\ProgramData\LogHelper\uninstall_log.txt
    Modul sa odstraňuje z C:\Program Files\WindowsPowerShell\Modules\LogHelper
#>

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogFile = "$env:ProgramData\LogHelper\uninstall_log.txt"

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
    Write-Output $Message
}

Write-Log "Spúšťam odinštaláciu modulu LogHelper..."

if (Test-Path $ModulePath) {
    Remove-Item -Path $ModulePath -Recurse -Force
    Write-Log "Modul LogHelper bol úspešne odstránený."
}
else {
    Write-Log "Modul LogHelper neexistuje, nie je čo odinštalovať."
}

Write-Log "Odinštalácia dokončená."