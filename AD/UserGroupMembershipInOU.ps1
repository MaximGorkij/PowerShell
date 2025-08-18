<#
.SYNOPSIS
    Vyhľadá všetky skupiny v špecifikovanej OU, kde je daný užívateľ členom.
.DESCRIPTION
    Tento skript nájde všetky skupiny v zadanej OU, ktoré obsahujú špecifikovaného užívateľa ako člena.
    Podporuje aj rekurzívne členstvo (skupiny v skupinách).
.PARAMETER UserIdentity
    Identifikátor užívateľa (SamAccountName, UserPrincipalName alebo DistinguishedName)
.PARAMETER OUPath
    Cesta k organizačnej jednotke v tvare "OU=Poddelenie,OU=Oddelenie,DC=domain,DC=com"
.PARAMETER IncludeNested
    Zahrnúť aj nepriame členstvo (ak je užívateľ členom skupiny, ktorá je členom hľadanej skupiny)
.PARAMETER ExportToCSV
    Prepínač, ktorý určuje, či sa má vygenerovať CSV export
.PARAMETER CSVPath
    Voliteľná cesta pre export CSV súboru
.EXAMPLE
    .\Find-UserGroupMembershipInOU.ps1 -UserIdentity "janko" -OUPath "OU=Groups,OU=Slovakia,DC=company,DC=com"
.EXAMPLE
    .\Find-UserGroupMembershipInOU.ps1 -UserIdentity "janko.hrasko@company.com" -OUPath "OU=Groups,OU=Slovakia,DC=company,DC=com" -IncludeNested -ExportToCSV
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$UserIdentity,
    
    [Parameter(Mandatory=$true)]
    [string]$OUPath,
    
    [switch]$IncludeNested,
    
    [switch]$ExportToCSV,
    
    [string]$CSVPath = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\UserGroupMembership_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
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
    # Získanie užívateľa
    $user = Get-ADUser -Identity $UserIdentity -Properties MemberOf, DistinguishedName
    
    # Získanie všetkých skupín v OU
    $groupsInOU = Get-ADGroup -Filter * -SearchBase $OUPath -Properties Member, MemberOf
    
    if (-not $groupsInOU) {
        Write-Host "Organizačná jednotka '$OUPath' neobsahuje žiadne skupiny alebo neexistuje." -ForegroundColor Yellow
        exit
    }

    $results = @()
    $groupCount = $groupsInOU.Count
    $currentGroup = 0

    foreach ($group in $groupsInOU) {
        $currentGroup++
        $progress = [math]::Round(($currentGroup / $groupCount) * 100)
        Write-Progress -Activity "Vyhľadávam členstvo užívateľa" -Status "Skupina $currentGroup z $groupCount ($progress%)" -CurrentOperation $group.Name -PercentComplete $progress

        $isMember = $false
        $membershipType = ""

        # Kontrola priameho členstva
        $directMembers = Get-ADGroupMember -Identity $group | Where-Object {$_.DistinguishedName -eq $user.DistinguishedName}
        if ($directMembers) {
            $isMember = $true
            $membershipType = "Priame"
        }

        # Kontrola nepriameho členstva (ak je požadované)
        if ($IncludeNested -and -not $isMember) {
            $allMembers = Get-ADGroupMember -Identity $group -Recursive | Where-Object {$_.DistinguishedName -eq $user.DistinguishedName}
            if ($allMembers) {
                $isMember = $true
                $membershipType = "Nepriame (rekurzívne)"
            }
        }

        if ($isMember) {
            $results += [PSCustomObject]@{
                GroupName = $group.Name
                GroupDN = $group.DistinguishedName
                MembershipType = $membershipType
                UserName = $user.Name
                UserLogin = $user.SamAccountName
                UserDN = $user.DistinguishedName
            }
        }
    }

    # Výpis výsledkov
    if ($results) {
        Write-Host "`nUžívateľ '$($user.Name)' je členom nasledujúcich skupín v OU '$OUPath':" -ForegroundColor Green
        $results | Format-Table GroupName, MembershipType -AutoSize

        # Export do CSV ak je požadovaný
        if ($ExportToCSV) {
            $results | Export-Csv -Path $CSVPath -NoTypeInformation -Encoding UTF8
            Write-Host "`nÚdaje boli exportované do: $CSVPath" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "Užívateľ '$($user.Name)' nie je členom žiadnej skupiny v OU '$OUPath'." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Chyba pri spracovaní: $_" -ForegroundColor Red
    exit 1
}