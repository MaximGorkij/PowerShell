<#
.SYNOPSIS
    Získa zoznam všetkých užívateľov v špecifikovanej organizačnej jednotke (OU) Active Directory.
.DESCRIPTION
    Tento skript vypíše alebo exportuje do CSV zoznam užívateľov v zadanej OU vrátane základných atribútov.
.PARAMETER OUPath
    Cesta k organizačnej jednotke v tvare "OU=Poddelenie,OU=Oddelenie,DC=domain,DC=com"
.PARAMETER ExportToCSV
    Prepínač, ktorý určuje, či sa má vygenerovať CSV export
.PARAMETER CSVPath
    Voliteľná cesta pre export CSV súboru (ak nie je zadaná, použije sa východzia cesta)
.EXAMPLE
    .\Get-ADUsersInOU.ps1 -OUPath "OU=Users,OU=Slovakia,DC=company,DC=com"
.EXAMPLE
    .\Get-ADUsersInOU.ps1 -OUPath "OU=Users,OU=Slovakia,DC=company,DC=com" -ExportToCSV
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$OUPath,
    
    [switch]$ExportToCSV,
    
    [string]$CSVPath = "C:\temp\ADUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
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
    # Získanie všetkých užívateľov v OU
    $users = Get-ADUser -Filter * -SearchBase $OUPath -Properties * |
             Select-Object Name, SamAccountName, UserPrincipalName, Enabled, 
                 EmailAddress, Title, Department, Company,
                 @{Name="OU";Expression={($_.DistinguishedName -split ',',2)[1]}},
                 @{Name="LastLogonDate";Expression={$_.LastLogonDate}},
                 @{Name="PasswordLastSet";Expression={$_.PasswordLastSet}},
                 @{Name="AccountExpirationDate";Expression={$_.AccountExpirationDate}}
    
    # Výpis výsledkov
    if ($users) {
        Write-Host "Zoznam užívateľov v OU '$OUPath':" -ForegroundColor Green
        $users | Format-Table Name, SamAccountName, UserPrincipalName, Enabled -AutoSize
        Write-Host "Celkový počet užívateľov: $($users.Count)"
        
        # Export do CSV ak je požadovaný
        if ($ExportToCSV) {
            $users | Export-Csv -Path $CSVPath -NoTypeInformation -Encoding UTF8
            Write-Host "Údaje boli exportované do: $CSVPath" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "Organizačná jednotka '$OUPath' neobsahuje žiadnych užívateľov alebo neexistuje." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Chyba pri získavaní užívateľov: $_" -ForegroundColor Red
    exit 1
}