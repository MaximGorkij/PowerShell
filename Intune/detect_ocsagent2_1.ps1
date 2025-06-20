# Detekcia, či existuje aspoň jedna inštalácia OCS Inventory
#$path = "C:\Program Files (x86)\OCS Inventory Agent\OCSInventory.exe"


$reg = (Get-WmiObject -Class Win32_Product | Where-Object vendor -like 'OCS*' | select-object Version).Version

Write-Host $reg

#if (!$reg) {
if ($reg -ne "2.11.0.1") {    
    write-host "tu je cesta - " $reg
    exit 1
} # OCS Inventory nájdený → spustiť nápravu

<#
if (Test-Path $path) { 
        write-host "tu je cesta - " $path
        exit 1 
    } # OCS Inventory nájdený → spustiť nápravu
#>

exit 0 # OCS Inventory nenájdený, náprava nie je potrebná