<#
.SYNOPSIS
    Získa zoznam všetkých skupín v špecifikovanej OU a ich členov.
.DESCRIPTION
    Tento skript vypíše alebo exportuje do CSV zoznam skupín v zadanej OU a všetkých ich členov.
.PARAMETER OUPath
    Cesta k organizačnej jednotke v tvare "OU=Poddelenie,OU=Oddelenie,DC=domain,DC=com"
.PARAMETER ExportToCSV
    Prepínač, ktorý určuje, či sa má vygenerovať CSV export
.PARAMETER CSVPath
    Voliteľná cesta pre export CSV súboru
.PARAMETER IncludeNestedGroups
    Zahrnúť aj vnorené skupiny (skupiny, ktoré sú členmi iných skupín)
.EXAMPLE
    .\Get-ADGroupMembersInOU.ps1 -OUPath "OU=Groups,OU=Slovakia,DC=company,DC=com"
.EXAMPLE
    .\Get-ADGroupMembersInOU.ps1 -OUPath "OU=Groups,OU=Slovakia,DC=company,DC=com" -ExportToCSV -IncludeNestedGroups
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$OUPath,
    
    [switch]$ExportToCSV,
    
    [string]$CSVPath = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\ADGroupMembers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    
    [switch]$IncludeNestedGroups
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
    # Získanie všetkých skupín v OU
    $groups = Get-ADGroup -Filter * -SearchBase $OUPath -Properties Description
    
    if (-not $groups) {
        Write-Host "Organizačná jednotka '$OUPath' neobsahuje žiadne skupiny alebo neexistuje." -ForegroundColor Yellow
        exit
    }

    $results = @()
    $groupCount = $groups.Count
    $currentGroup = 0

    foreach ($group in $groups) {
        $currentGroup++
        $progress = [math]::Round(($currentGroup / $groupCount) * 100)
        Write-Progress -Activity "Spracovávam skupiny" -Status "Skupina $currentGroup z $groupCount ($progress%)" -CurrentOperation $group.Name -PercentComplete $progress

        try {
            # Získanie členov skupiny
            $members = Get-ADGroupMember -Identity $group -Recursive:$IncludeNestedGroups
            
            foreach ($member in $members) {
                $memberType = $member.objectClass
                $memberDetails = $null

                # Získanie detailov podľa typu objektu
                if ($memberType -eq 'user') {
                    $memberDetails = Get-ADUser -Identity $member -Properties Name, SamAccountName, UserPrincipalName, Enabled
                    $memberName = $memberDetails.Name
                    $memberLogin = $memberDetails.SamAccountName
                    $memberStatus = $memberDetails.Enabled
                }
                elseif ($memberType -eq 'group') {
                    $memberDetails = Get-ADGroup -Identity $member -Properties Name
                    $memberName = $memberDetails.Name + " (skupina)"
                    $memberLogin = $memberDetails.SamAccountName
                    $memberStatus = $null
                }
                else {
                    $memberName = $member.Name
                    $memberLogin = $member.SamAccountName
                    $memberStatus = $null
                }

                # Pridanie do výsledkov
                $results += [PSCustomObject]@{
                    GroupName        = $group.Name
                    GroupDN          = $group.DistinguishedName
                    GroupDescription = $group.Description
                    MemberName       = $memberName
                    MemberLogin      = $memberLogin
                    MemberType       = $memberType
                    MemberStatus     = $memberStatus
                    MemberDN         = $member.DistinguishedName
                }
            }
        }
        catch {
            Write-Host "Chyba pri spracovaní skupiny $($group.Name): $_" -ForegroundColor Yellow
        }
    }

    # Výpis výsledkov
    if ($results) {
        Write-Host "`nZoznam skupín a ich členov v OU '$OUPath':" -ForegroundColor Green
        $results | Format-Table GroupName, MemberName, MemberLogin, MemberType, MemberStatus -AutoSize
        Write-Host "`nCelkový počet skupín: $groupCount"
        Write-Host "Celkový počet členov: $($results.Count)"

        # Export do CSV ak je požadovaný
        if ($ExportToCSV) {
            $results | Export-Csv -Path $CSVPath -NoTypeInformation -Encoding UTF8
            Write-Host "`nÚdaje boli exportované do: $CSVPath" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host "Nenašli sa žiadni členovia v skupinách v OU '$OUPath'." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Chyba pri spracovaní: $_" -ForegroundColor Red
    exit 1
}