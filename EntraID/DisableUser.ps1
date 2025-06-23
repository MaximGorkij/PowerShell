# Variables
$UserUPN = "p1002@masiarstvoubyka.sk"
$DisabledGroup = "OU=MUB,OU=DISABLED ACCOUNTS,DC=tauris,DC=local"  # Change to actual group name
$LogPath = "C:\Tools\DisabledUsersLog.csv"

# Get user by UPN
try {
    $User = Get-ADUser -Filter "UserPrincipalName -eq '$UserUPN'" -Properties MemberOf -ErrorAction Stop
    
    # Log current group memberships
    $Groups = $User.MemberOf
    $LogEntry = [PSCustomObject]@{
        User        = $User.SamAccountName
        DisplayName = $User.Name
        Date        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Action      = "Disable Account"
        Groups      = ($Groups | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }) -join '; '
        # Groups      = ($Groups | ForEach-Object { ($_ -split ',')[0] -replace '^CN=' }).Join('; ')
    }
    
    # Export to CSV
    $LogEntry | Export-Csv -Path $LogPath -NoTypeInformation -Append
    
    # Remove from all groups
    foreach ($GroupDN in $Groups) {
        Remove-ADGroupMember -Identity $GroupDN -Members $User -Confirm:$false -WhatIf
        Write-Host "Removed from $($GroupDN)"
    }
    
    # Add to Disabled group
    Add-ADGroupMember -Identity $DisabledGroup -Members $User -WhatIf
    Write-Host "Added to disabled group"
    
    # Disable the account
    Disable-ADAccount -Identity $User -WhatIf
    Write-Host "Account disabled"
}
catch {
    Write-Error "Error processing user: $_"
}