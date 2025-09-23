<#
.SYNOPSIS
    Detekcia modulu LogHelper

.DESCRIPTION
    Overi, ci je modul LogHelper uz nacitany. Ak nie, importuje ho z pevnej cesty.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-04

.VERSION
    1.1

.NOTES
    Modul sa importuje len ak este nie je nacitany.
#>
Write-Output "Zaciatok detekcie."

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$VersionFile = "$ModulePath\version.txt"
$ExpectedVersion = "1.6.0"

# Overenie cesty
if (-Not (Test-Path $ModulePath)) {
    Write-Host "Modulovy priecinok neexistuje."
    exit 1
}

# Overenie version.txt
if (-Not (Test-Path $VersionFile)) {
    Write-Host "Subor version.txt neexistuje."
    exit 1
}

# Overenie verzie
#$InstalledVersion = Get-Content $VersionFile -ErrorAction SilentlyContinue
$InstalledVersion = (Get-Content $VersionFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
if ($InstalledVersion -eq $ExpectedVersion) {
    Write-Host "Modul je vo verzii $ExpectedVersion."
    exit 0
}
else {
    Write-Host "Zistena verzia: $InstalledVersion. Ocakavana: $ExpectedVersion."
    exit 1
}