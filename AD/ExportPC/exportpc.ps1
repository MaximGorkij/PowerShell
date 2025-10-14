<#
.SYNOPSIS
    Export počítačov z špecifikovaných OU do CSV súboru.
.DESCRIPTION
    Skript exportuje všetky počítače z definovaných OU do CSV súboru
    so všetkými potrebnými atribútmi pre následný import do novej domény.
#>

# Import modulu Active Directory
Import-Module ActiveDirectory

# Definícia OU pre export
$exportOU = @(
    "OU=Workstations,OU=UBYKA,DC=tauris,DC=local",
    "OU=Workstations,OU=NITRIA,DC=tauris,DC=local", 
    "OU=Workstations,OU=HQ TG,DC=tauris,DC=local",
    "OU=Workstations,OU=CASSOVIA,DC=tauris,DC=local",
    "OU=Workstations,OU=TAURIS,DC=tauris,DC=local",
    "OU=Workstations,OU=RYBA,DC=tauris,DC=local"
)

# Cesta pre export
$exportDir = "C:\TaurisIT\Export"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$exportPath = Join-Path $exportDir "AD_Computers_Export_$timestamp.csv"

# Vytvorenie priečinka ak neexistuje
if (-not (Test-Path $exportDir)) {
    New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
}

Write-Host "Zacinam export pocitacov z AD..." -ForegroundColor Green
Write-Host "Export subor: $exportPath" -ForegroundColor Cyan
Write-Host ""

$allComputers = @()
$totalComputers = 0

foreach ($ou in $exportOU) {
    Write-Host "Spracuvam OU: $ou" -ForegroundColor Yellow
    
    try {
        $computers = Get-ADComputer -Filter * -SearchBase $ou -Properties @(
            'Name',
            'Description', 
            'DistinguishedName',
            'Enabled',
            'Created',
            'Modified',
            'LastLogonDate',
            'OperatingSystem',
            'OperatingSystemVersion',
            'IPv4Address',
            'ManagedBy',
            'Location',
            'Department'
        )
        
        Write-Host "  Najdenych pocitacov: $($computers.Count)" -ForegroundColor Green
        
        foreach ($computer in $computers) {
            $computerInfo = [PSCustomObject]@{
                OldName                = $computer.Name
                Description            = $computer.Description
                Enabled                = $computer.Enabled
                OperatingSystem        = $computer.OperatingSystem
                OperatingSystemVersion = $computer.OperatingSystemVersion
                IPv4Address            = $computer.IPv4Address
                LastLogonDate          = if ($computer.LastLogonDate) { $computer.LastLogonDate.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                ManagedBy              = $computer.ManagedBy
                Location               = $computer.Location
                Department             = $computer.Department
                SourceOU               = $ou
                DistinguishedName      = $computer.DistinguishedName
                Created                = if ($computer.Created) { $computer.Created.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                Modified               = if ($computer.Modified) { $computer.Modified.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                ExportTimestamp        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            $allComputers += $computerInfo
            $totalComputers++
        }
    }
    catch {
        Write-Host "  ERROR: Chyba pri spracovani OU $ou - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Export do CSV
if ($allComputers.Count -gt 0) {
    $allComputers | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "EXPORT UKONCENY" -ForegroundColor Green
    Write-Host "Celkovo exportovanych pocitacov: $totalComputers" -ForegroundColor Green
    Write-Host "Subor: $exportPath" -ForegroundColor Cyan
    
    # Zobrazenie ukážky dát
    Write-Host ""
    Write-Host "Ukazka exportovanych dat:" -ForegroundColor Yellow
    $allComputers | Select-Object -First 5 | Format-Table OldName, Enabled, OperatingSystem, SourceOU -AutoSize
    
    # Zoznam všetkých export súborov
    Write-Host ""
    Write-Host "Vsetky export subory v poradi:" -ForegroundColor Magenta
    Get-ChildItem -Path $exportDir -Filter "AD_Computers_Export_*.csv" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object Name, LastWriteTime, @{Name = "SizeMB"; Expression = { [math]::Round($_.Length / 1MB, 2) } } | 
    Format-Table -AutoSize
}
else {
    Write-Host "ERROR: Neboli najdené žiadne počítače na export." -ForegroundColor Red
}