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


$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$VersionFile = "$ModulePath\version.txt"
$ExpectedVersion = "1.5.0"

# Overenie cesty
if (-Not (Test-Path $ModulePath)) {
    Write-Output "Modulový priečinok neexistuje."
    exit 1
}

# Overenie version.txt
if (-Not (Test-Path $VersionFile)) {
    Write-Output "Súbor version.txt neexistuje."
    exit 1
}

# Overenie verzie
$InstalledVersion = Get-Content $VersionFile -ErrorAction SilentlyContinue
if ($InstalledVersion -eq $ExpectedVersion) {
    Write-Output "Modul je vo verzii $ExpectedVersion."
    exit 0
}
else {
    Write-Output "Zistená verzia: $InstalledVersion. Očakávaná: $ExpectedVersion."
    exit 1
}