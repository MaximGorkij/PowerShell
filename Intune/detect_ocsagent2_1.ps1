# Detekcia, či existuje aspoň jedna inštalácia OCS Inventory
$path = "C:\Program Files (x86)\OCS Inventory Agent\OCSInventory.exe"

if (Test-Path $path) { 
        write-host "tu je cesta - " $path
        exit 1 
    } # OCS Inventory nájdený → spustiť nápravu


exit 0 # OCS Inventory nenájdený, náprava nie je potrebná