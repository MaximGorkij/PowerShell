<#
.SYNOPSIS
    Vytvorenie OU štruktúry v novej doméne podľa pôvodnej štruktúry.
#>

Import-Module ActiveDirectory

# Základ nového doménového mena
$newDomainBase = "DC=nova-domena,DC=local"  # UPRAVTE

# Štruktúra OU ktorú treba vytvoriť
$ouStructure = @(
    "OU=Workstations,OU=UBYKA,$newDomainBase",
    "OU=Workstations,OU=NITRIA,$newDomainBase", 
    "OU=Workstations,OU=HQ TG,$newDomainBase",
    "OU=Workstations,OU=CASSOVIA,$newDomainBase",
    "OU=Workstations,OU=TAURIS,$newDomainBase",
    "OU=Workstations,OU=RYBA,$newDomainBase"
)

Write-Host "Vytvaram OU strukturu v novej domene..." -ForegroundColor Green

foreach ($ouDN in $ouStructure) {
    try {
        # Rozdelenie DN na jednotlivé časti
        $ouParts = $ouDN -split ','
        $currentPath = $newDomainBase
        
        # Postupné vytváranie hierarchie OU
        for ($i = $ouParts.Count - 1; $i -ge 0; $i--) {
            $currentOU = $ouParts[$i]
            
            if ($currentOU -match "^OU=(.+)$") {
                $ouName = $matches[1]
                $fullPath = $currentOU + "," + $currentPath
                
                # Kontrola či OU už existuje
                try {
                    Get-ADOrganizationalUnit -Identity $fullPath -ErrorAction Stop | Out-Null
                    Write-Host "EXISTS: $fullPath" -ForegroundColor Gray
                }
                catch {
                    # OU neexistuje, vytvoríme ju
                    New-ADOrganizationalUnit -Name $ouName -Path $currentPath -ProtectedFromAccidentalDeletion $false
                    Write-Host "CREATED: $fullPath" -ForegroundColor Green
                }
                
                $currentPath = $fullPath
            }
        }
    }
    catch {
        Write-Host "ERROR: Chyba pri vytvarani OU $ouDN - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Vytvaranie OU struktury dokoncene." -ForegroundColor Green