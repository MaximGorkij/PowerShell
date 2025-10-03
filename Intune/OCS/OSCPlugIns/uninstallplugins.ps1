<#
.SYNOPSIS
    Odinštalačný skript pre ScriptCopy - Intune Package
.DESCRIPTION
    Odstráni všetky nainštalované skripty a cieľový adresár.
    Loguje udalosti do suboru a Windows Event Logu.
.AUTHOR
    Marek Findrik
.CREATED
    2025-10-03
.VERSION
    1.0
.NOTES
    Optimalizovane pre nasadenie cez Microsoft Intune.
#>

# Import LogHelper
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

# Premenne
$TargetPath = "C:\Program Files\OCS Inventory Agent\Plugins"
$LogFileName = "C:\TaurisIT\Log\OCSPlugIns\ScriptCopy_Uninstall_{0}.txt" -f (Get-Date -Format "yyyyMMdd")
$EventLogName = "IntuneScript"
$EventSource = "OCS PlugIns"

try {
    if (Test-Path $TargetPath) {
        Remove-Item -Path $TargetPath -Recurse -Force
        Write-CustomLog -Message "Odstraneny adresar: $TargetPath" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Warning -EventId 2100
    }
    else {
        Write-CustomLog -Message "Adresar $TargetPath neexistuje, nie je co odinstalovat." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Information -EventId 2110
    }

    Write-CustomLog -Message "Odinštalacia bola uspesne dokoncena." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Information -EventId 2999
    exit 0
}
catch {
    Write-CustomLog -Message "CHYBA pri odinstalacii: $($_.Exception.Message)" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName -Type Error -EventId 2400
    exit 1
}
