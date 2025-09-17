<#
.SYNOPSIS
    Odinstaluje PowerShell modul LogHelper z klientskeho PC.

.DESCRIPTION
    Skript odstrani cely priecinok modulu LogHelper a loguje priebeh do .txt suboru aj Event Logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-05

.VERSION
    1.0.0

.NOTES
    Logy sa ukladaju do C:\ProgramData\LogHelper\uninstall_log.txt
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

Write-Log "Spustam odinstalaciu modulu LogHelper..."

if (Test-Path $ModulePath) {
    Remove-Item -Path $ModulePath -Recurse -Force
    Write-Log "Modul LogHelper bol uspesne odstraneny."
}
else {
    Write-Log "Modul LogHelper neexistuje, nie je co odinstalovat."
}

Write-Log "Odinstalacia dokoncena."