<# 
.SYNOPSIS
    Automatická extrakcia názvov Unifi zariadení z nájdeného .txt súboru
.DESCRIPTION
    Skript nájde prvý dostupný .txt súbor v aktuálnom adresári, vytiahne z neho
    názvy Unifi zariadení a uloží unikátny zoznam do súboru zoznam_zariadeni.txt.
.NOTES
    Verzia: 1.3
    Autor: Automaticky report
    Datum vytvorenia: 27.02.2026
#>

# 1. Vyhľadanie prvého .txt súboru v aktuálnom priečinku (okrem výsledného zoznamu)
$targetFile = Get-ChildItem -Filter "*.txt" | Where-Object { $_.Name -ne "zoznam_zariadeni.txt" } | Select-Object -First 1

if ($null -eq $targetFile) {
    Write-Host "V aktuálnom adresári sa nenašiel žiadny .txt súbor na spracovanie." -ForegroundColor Yellow
    return
}

Write-Host "Spracovávam súbor: $($targetFile.Name)..."

# 2. Načítanie obsahu
$content = Get-Content -Path $targetFile.FullName -Raw

# 3. Regex na extrakciu (hľadá "Unifi ..." medzi úvodzovkou a dvojbodkou)
$pattern = '(?<=")(Unifi [^:]+)(?=:)'

# 4. Extrakcia a unikátny zoznam
$devices = [regex]::Matches($content, $pattern).Value | Select-Object -Unique

# 5. Uloženie výsledku
$outputFile = "zoznam_zariadeni.txt"

if ($devices) {
    $devices | Out-File -FilePath $outputFile -Encoding utf8
    Write-Host "Hotovo! Extrahovaných $($devices.Count) unikátnych zariadení do $outputFile." -ForegroundColor Green
}
else {
    Write-Host "V súbore $($targetFile.Name) sa nenašli žiadne zhody." -ForegroundColor Cyan
}