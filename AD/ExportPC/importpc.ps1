<#
.SYNOPSIS
    Import počítačov do novej domény z najnovšieho CSV súboru.
.DESCRIPTION
    Skript automaticky nájde najnovší CSV súbor v priečinku exportu
    a importuje počítače do novej domény na základe exportovaných dát.
#>

# Import modulu Active Directory
Import-Module ActiveDirectory

# Funkcia na nájdenie najnovšieho CSV súboru
function Get-LatestExportFile {
    param(
        [string]$SearchPath = "C:\TaurisIT\Export"
    )
    
    if (-not (Test-Path $SearchPath)) {
        Write-Host "ERROR: Export directory neexistuje: $SearchPath" -ForegroundColor Red
        return $null
    }
    
    $latestFile = Get-ChildItem -Path $SearchPath -Filter "AD_Computers_Export_*.csv" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1
    
    if (-not $latestFile) {
        Write-Host "ERROR: Nebol najdeny ziadny CSV subor v: $SearchPath" -ForegroundColor Red
        return $null
    }
    
    return $latestFile
}

# Hlavné parametre
$exportDirectory = "C:\TaurisIT\Export"  # UPRAVTE AK TREBA
$newDomainBase = "DC=nova-domena,DC=local"  # UPRAVTE PRE NOVÚ DOMÉNU

# Nájdenie najnovšieho CSV súboru
Write-Host "Hladam najnovsi export subor..." -ForegroundColor Yellow
$latestCsv = Get-LatestExportFile -SearchPath $exportDirectory

if (-not $latestCsv) {
    exit 1
}

$csvPath = $latestCsv.FullName
Write-Host "Najdeny najnovsi subor: $($latestCsv.Name)" -ForegroundColor Green
Write-Host "Cesta: $csvPath" -ForegroundColor Cyan
Write-Host "Datum vytvorenia: $($latestCsv.LastWriteTime)" -ForegroundColor Cyan
Write-Host ""

# Mapovanie OU z pôvodnej do novej domény
$ouMapping = @{
    "OU=Workstations,OU=UBYKA,DC=tauris,DC=local"    = "OU=Workstations,OU=UBYKA,$newDomainBase"
    "OU=Workstations,OU=NITRIA,DC=tauris,DC=local"   = "OU=Workstations,OU=NITRIA,$newDomainBase"
    "OU=Workstations,OU=HQ TG,DC=tauris,DC=local"    = "OU=Workstations,OU=HQ TG,$newDomainBase"
    "OU=Workstations,OU=CASSOVIA,DC=tauris,DC=local" = "OU=Workstations,OU=CASSOVIA,$newDomainBase"
    "OU=Workstations,OU=TAURIS,DC=tauris,DC=local"   = "OU=Workstations,OU=TAURIS,$newDomainBase"
    "OU=Workstations,OU=RYBA,DC=tauris,DC=local"     = "OU=Workstations,OU=RYBA,$newDomainBase"
}

# Načítanie dát z CSV
try {
    $computers = Import-Csv -Path $csvPath -Encoding UTF8
    Write-Host "CSV subor uspesne nacitany." -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Chyba pri nacitavani CSV suboru: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Zacinam import pocitacov do novej domény..." -ForegroundColor Green
Write-Host "Pocet zaznamov v CSV: $($computers.Count)" -ForegroundColor Cyan
Write-Host ""

# Potvrdenie pred spustením
$confirm = Read-Host "Chcete pokracovat v importe? (A/N)"
if ($confirm -notmatch "^[Aa]$") {
    Write-Host "Import zruseny." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

$importedCount = 0
$skippedCount = 0
$errorCount = 0

foreach ($computer in $computers) {
    $oldName = $computer.OldName
    $sourceOU = $computer.SourceOU
    
    # Získanie cieľovej OU z mapovania
    if ($ouMapping.ContainsKey($sourceOU)) {
        $targetOU = $ouMapping[$sourceOU]
    }
    else {
        Write-Host "SKIP: Pre OU '$sourceOU' nie je definovane mapovanie - $oldName" -ForegroundColor Yellow
        $skippedCount++
        continue
    }
    
    # Kontrola či OU existuje v novej doméne
    try {
        Get-ADOrganizationalUnit -Identity $targetOU -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "ERROR: Cielova OU neexistuje: $targetOU - $oldName" -ForegroundColor Red
        $errorCount++
        continue
    }
    
    # Kontrola či počítač už existuje
    try {
        $existingComputer = Get-ADComputer -Filter "Name -eq '$oldName'" -SearchBase $targetOU -ErrorAction SilentlyContinue
        if ($existingComputer) {
            Write-Host "SKIP: Pocitac uz existuje - $oldName v $targetOU" -ForegroundColor Yellow
            $skippedCount++
            continue
        }
    }
    catch {
        # Počítač neexistuje, pokračujeme
    }
    
    # Vytvorenie nového počítačového účtu
    try {
        $newComputerParams = @{
            Name        = $oldName
            Path        = $targetOU
            Enabled     = [bool]::Parse($computer.Enabled)
            Description = $computer.Description
        }
        
        # Voliteľné parametre
        if ($computer.ManagedBy) {
            $newComputerParams.ManagedBy = $computer.ManagedBy
        }
        
        if ($computer.Location) {
            $newComputerParams.Location = $computer.Location
        }
        
        if ($computer.Department) {
            $newComputerParams.Department = $computer.Department
        }
        
        New-ADComputer @newComputerParams -ErrorAction Stop
        
        Write-Host "OK: Vytvoreny pocitac - $oldName v $targetOU" -ForegroundColor Green
        $importedCount++
    }
    catch {
        Write-Host "ERROR: Chyba pri vytvarani pocitaca $oldName - $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

# Zhrnutie
Write-Host ""
Write-Host "IMPORT UKONCENY" -ForegroundColor Cyan
Write-Host "=" * 50
Write-Host "Pouzity subor: $($latestCsv.Name)" -ForegroundColor Gray
Write-Host "Importovanych pocitacov: $importedCount" -ForegroundColor Green
Write-Host "Preskocenych: $skippedCount" -ForegroundColor Yellow
Write-Host "Chyb: $errorCount" -ForegroundColor Red
Write-Host "Celkom spracovanych: $($computers.Count)" -ForegroundColor Cyan

# Uloženie reportu
$reportPath = "C:\TaurisIT\Export\Import_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$reportContent = @"
IMPORT REPORT
Cas: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Subor: $($latestCsv.Name)
Importovanych: $importedCount
Preskocenych: $skippedCount
Chyb: $errorCount
Celkom: $($computers.Count)
"@

$reportContent | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Report ulozeny: $reportPath" -ForegroundColor Cyan