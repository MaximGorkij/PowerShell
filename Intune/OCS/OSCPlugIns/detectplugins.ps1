<#
.SYNOPSIS
    Detection script pre OCS Inventory Plugins - Intune Package
.DESCRIPTION
    Kontroluje pritomnost vsetkych pozadovanych PS1 plugin suborov
    v cielovom adresari OCS Inventory Agent.
    Pouziva sa pre detekciu instalacie v Microsoft Intune.
.AUTHOR
    Marek Findrik
.CREATED
    2025-10-03
.VERSION
    1.0
.NOTES
    Skript vracia exit code 0 ak su vsetky subory pritomne, inak 1.
    Pouziva sa ako detection script pre Win32 App v Intune.
#>

# --------------------------------------------------------------------
# Konfiguracia
# --------------------------------------------------------------------
$Config = @{
    TargetPath    = "C:\Program Files\OCS Inventory Agent\Plugins"
    RequiredFiles = @("eventlogs.ps1", "userinstalledapps.ps1", "winusers.ps1")
}

# --------------------------------------------------------------------
# Hlavna logika
# --------------------------------------------------------------------
try {
    Write-Host "Kontrola pritomnosti OCS Inventory plugin suborov..." -ForegroundColor Cyan
    Write-Host "Cielovy adresar: $($Config.TargetPath)" -ForegroundColor Gray
    
    $missingFiles = @()
    
    foreach ($file in $Config.RequiredFiles) {
        $filePath = Join-Path $Config.TargetPath $file
        if (-not (Test-Path $filePath)) {
            $missingFiles += $file
            Write-Host "CHYBA: Chybajuci subor: $file" -ForegroundColor Red
        }
        else {
            Write-Host "OK: Subor pritomny: $file" -ForegroundColor Green
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Host "`nDetekcia NEUSPESNA - Chybajuce subory: $($missingFiles -join ', ')" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`nDetekcia USPESNA - Vsetky pozadovane subory su pritomne" -ForegroundColor Green
    Write-Host "Najdene subory: $($Config.RequiredFiles -join ', ')" -ForegroundColor Gray
    exit 0
}
catch {
    Write-Host "CHYBA pri detekcii: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}