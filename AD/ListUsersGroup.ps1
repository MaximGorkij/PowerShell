# Skript na zobrazenie zoznamu užívateľov v AD skupine s OU informáciami
param (
    [string]$GroupName = $(throw "Prosím zadajte názov skupiny pomocou parametra -GroupName"),
    [switch]$ExportToCSV
)

# Načítanie modulu Active Directory
if (-not (Get-Module -Name ActiveDirectory)) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-Host "Modul ActiveDirectory nie je nainštalovaný alebo nie je k dispozícii." -ForegroundColor Red
        exit 1
    }
}

try {
    # Získanie členov skupiny
    $groupMembers = Get-ADGroupMember -Identity $GroupName -Recursive | 
                    Where-Object {$_.objectClass -eq 'user'} |
                    Get-ADUser -Properties Name, SamAccountName, UserPrincipalName, Enabled, DistinguishedName |
                    Select-Object Name, SamAccountName, UserPrincipalName, Enabled, 
                        @{Name="OrganizationalUnit";Expression={($_.DistinguishedName -split ',',2)[1]}}
    
    # Výpis výsledkov
    if ($groupMembers) {
        Write-Host "Zoznam užívateľov v skupine '$GroupName':" -ForegroundColor Green
        $groupMembers | Format-Table -AutoSize
        Write-Host "Celkový počet užívateľov: $($groupMembers.Count)"
        
        # Export do CSV ak je požadovaný
        if ($ExportToCSV) {
            $exportPath = "C:\temp\${GroupName}_Members_OU.csv"
            $groupMembers | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Host "Údaje boli exportované do: $exportPath" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "Skupina '$GroupName' neobsahuje žiadnych užívateľov alebo neexistuje." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Chyba pri získavaní členov skupiny: $_" -ForegroundColor Red
}