# Skript: TestTlaceExcel.ps1
# Popis: Testuje tlac Excel suboru z roznych umiestneni
# Slovencina bez diakritiky, auditovatelne logovanie
# Spustit .\TestTlaceExcel.ps1 alebo .\TestTlaceExcel.ps1 -DryRun

param (
    [switch]$DryRun
)

# Nacitanie konfiguracie z .env
$envPath = ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

# Validacia export adresara
$exportDir = "C:\Skripty\ExportIntuneLogs"
if (-not (Test-Path $exportDir)) {
    Write-Host "Chyba: Export adresar neexistuje: $exportDir"
    exit 1
}

# Cesta k suboru
$excelPath = $env:EXCEL_PATH
if (-not $excelPath) {
    Write-Host "Chyba: Premenna EXCEL_PATH nie je nastavena v .env"
    exit 1
}
if (-not (Test-Path $excelPath)) {
    Write-Host "Chyba: Subor neexistuje: $excelPath"
    exit 1
}

# Logovanie
$logFile = Join-Path $exportDir "TestTlaceExcel.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logFile "`n[$timestamp] Start testu tlace pre subor: $excelPath"

if ($DryRun) {
    Add-Content $logFile "DryRun aktivny - tlac sa neuskutocni"
    Write-Host "DryRun: Skript by spustil tlac suboru: $excelPath"
    exit 0
}

# Pokus o tlac
try {
    $excel = New-Object -ComObject Excel.Application
    $workbook = $excel.Workbooks.Open($excelPath)
    $workbook.PrintOut()
    $workbook.Close($false)
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    Add-Content $logFile "Tlac uspesna"
    Write-Host "Tlac uspesna"
}
catch {
    Add-Content $logFile "Chyba pri tlaci: $_"
    Write-Host "Chyba pri tlaci: $_"
}