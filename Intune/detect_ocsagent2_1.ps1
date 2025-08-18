# Detekcia, či existuje aspoň jedna inštalácia OCS Inventory
$reg = "0"
$path = "C:\Program Files (x86)\OCS Inventory Agent\OCSInventory.exe"
if (Test-Path $path) {
	$reg = (Get-WmiObject -Class Win32_Product | Where-Object vendor -like 'OCS*' | select-object Version).Version
}
Write-Host $reg

#if (!$reg) {
if (($reg -ne "2.11.0.1") -and ($reg -ne "0")) {    
    write-host "je tu je, zmazat - " $reg
    exit 1
} # OCS Inventory nájdený → spustiť nápravu

<#
if (Test-Path $path) { 
        write-host "tu je cesta - " $path
        exit 1 
    } # OCS Inventory nájdený → spustiť nápravu
#>

exit 0 # OCS Inventory nenájdený, náprava nie je potrebná