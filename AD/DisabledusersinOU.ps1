# Import Active Directory module
Import-Module ActiveDirectory

# Define the target OU (distinguished name)
$TargetOU = "OU=Rada,OU=Resources,OU=HQ TG,DC=tauris,DC=local"  # Replace with your OU

$path = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\DisabledUsers_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
# Get all groups in the specified OU
$Groups = Get-ADGroup -Filter * -SearchBase $TargetOU -Properties Members

# Initialize an array to store results
$Results = @()

foreach ($Group in $Groups) {
    # Get all members of the current group
    $Members = $Group.Members
    
    foreach ($Member in $Members) {
        try {
            # Check if the member is a user (not a group/computer)
            $User = Get-ADObject $Member -Properties Enabled, ObjectClass
            
            if ($User.ObjectClass -eq "user") {
                # Get full user details to check disabled status
                $UserDetails = Get-ADUser $User -Properties Enabled
                
                if ($UserDetails.Enabled -eq $false) {
                    # Add to results if user is disabled
                    $Results += [PSCustomObject]@{
                        GroupName    = $Group.Name
                        GroupDN      = $Group.DistinguishedName
                        DisabledUser = $UserDetails.SamAccountName
                        UserDN       = $UserDetails.DistinguishedName
                    }
                }
            }
        } catch {
            Write-Warning "Error processing member $Member : $_"
        }
    }
}

# Export results to CSV
$Results | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8

# Display results
$Results | Format-Table -AutoSize

Write-Host "Report generated: $path" -ForegroundColor Green