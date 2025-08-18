<#
.SYNOPSIS
Skript na zistenie prístupových práv AD skupiny z konkrétnej OU k sieťovým zdieľaniam
#>

# 1. Import modulu ADCredentialTools
Import-Module ADCredentialTools -Force

# 2. Získanie poverení
$credentials = Get-ADCredentials -Validate

# 3. Parametre pre vyhľadávanie
$targetOU = "OU=Rada,OU=Resources,OU=HQ TG,DC=tauris,DC=local"  # Nahraďte vašou OU
$server = "FSRS21"               # Zoznam serverov
$sharePath = "D:\Rada"    # Základné cesty

# 4. Získanie všetkých skupín z cieľovej OU
$groups = Get-ADGroup -SearchBase $targetOU -Filter * -Credential $credentials

# 5. Pre každú skupinu zistiť prístupové práva
$allResults = foreach ($group in $groups) {
    Write-Host "Kontrolujem skupinu: $($group.Name)" -ForegroundColor Cyan
    write-host "Test-ADGroupShareAccess -GroupName $group.Name -Server $server -Path $sharePath -Credential $credentials"
    $access = Test-ADGroupShareAccess -GroupName $group.Name -Server $server -Path $sharePath -Credential $credentials
    
    if ($access) {
        $access | Select-Object @{
            Name = "GroupOU"; 
            Expression = { $targetOU }
        }, *
    }
}

# 6. Zobrazenie a export výsledkov
$allResults | Format-Table -AutoSize
$allResults | Export-Csv -Path "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\GroupShareAccessRights$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -NoTypeInformation -Encoding UTF8

Write-Host "Hotovo! Výsledky uložené do GroupShareAccessRights$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -ForegroundColor Green