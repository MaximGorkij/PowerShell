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


$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
if (Test-Path $ModulePath) {
    Write-Output "Installed"
    exit 0
} else {
    Write-Output "Not Installed"
    exit 1
}