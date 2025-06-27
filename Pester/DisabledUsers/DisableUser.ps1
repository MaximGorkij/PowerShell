# Variables
$UserUPN = "p1002@masiarstvoubyka.sk"
$DisabledGroup = "OU=MUB,OU=DISABLED ACCOUNTS,DC=tauris,DC=local"  # Change to actual group name
$LogPath = "C:\Tools\DisabledUsersLog.csv"
#====================#
# Konfigurácia premenných
#====================#
# $UserUPN       = "xxx@yyyy.zz"
#$DisabledGroup = "CN=DisabledUsers,OU=11,OU=22,DC=33,DC=44"  # CN= názov skupiny
#$LogPath       = "C:\Tools\DisabledUsersLog.csv"

#====================#
# Získanie používateľa
#====================#
try {
    $User = Get-ADUser -Filter "UserPrincipalName -eq '$UserUPN'" -Properties MemberOf -ErrorAction Stop
    $UserDN = $User.DistinguishedName

    #====================#
    # Skupiny (security aj distribuované)
    #====================#
    $AllGroups = Get-ADGroup -Filter * -Properties Members | Where-Object {
        $_.Members -contains $UserDN
    }

    $SecurityGroups = @()
    $DistributionGroups = @()

    foreach ($group in $AllGroups) {
        if ($group.GroupCategory -eq "Distribution") {
            $DistributionGroups += $group
        } else {
            $SecurityGroups += $group
        }
    }

    #====================#
    # Logovanie do CSV
    #====================#
    $LogEntry = [PSCustomObject]@{
        User                 = $User.SamAccountName
        DisplayName          = $User.Name
        Date                 = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Action               = "Disable Account"
        SecurityGroups       = ($SecurityGroups | Select-Object -ExpandProperty Name) -join '; '
        DistributionGroups   = ($DistributionGroups | Select-Object -ExpandProperty Name) -join '; '
    }

    if (-not (Test-Path $LogPath)) {
        $LogEntry | Export-Csv -Path $LogPath -NoTypeInformation
    } else {
        $LogEntry | Export-Csv -Path $LogPath -NoTypeInformation -Append
    }

    #====================#
    # Odobratie zo všetkých skupín
    #====================#
    foreach ($group in $AllGroups) {
        try {
            Remove-ADGroupMember -Identity $group.DistinguishedName -Members $User -Confirm:$false
            Write-Host "✔ Removed from: $($group.Name)"
        } catch {
            Write-Warning "⚠ Could not remove from $($group.Name): $_"
        }
    }

    #====================#
    # Pridanie do Disabled skupiny
    #====================#
    try {
        Add-ADGroupMember -Identity $DisabledGroup -Members $User
        Write-Host "✔ Added to disabled group: $DisabledGroup"
    } catch {
        Write-Warning "⚠ Could not add to disabled group: $_"
    }

    #====================#
    # Deaktivácia účtu
    #====================#
    try {
        Disable-ADAccount -Identity $User
        Write-Host "✔ Account disabled"
    } catch {
        Write-Warning "⚠ Could not disable account: $_"
    }

} catch {
    Write-Error "❌ Error processing user '$UserUPN': $_"
}
