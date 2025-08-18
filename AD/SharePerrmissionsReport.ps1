# Import required modules
Import-Module ActiveDirectory

# Define servers and share paths to check (modify as needed)
$servers = @(
    "Server1",
    "Server2",
    "Server3"
)
$server="FSRS21"

$sharePaths = @(
    "C:\SharedFolder",
    "D:\Data"
)

$path="D:\Rada"
# Output file

$outputFile = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\SharePermissionsReport$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
$results = @()

#foreach ($server in $servers) {
#    foreach ($path in $sharePaths) {
        # Check if the path exists
        $fullPath = "\\$server\$($path -replace ':','$')"
        if (-not (Test-Path $fullPath)) {
            Write-Warning "Path not found: $fullPath"
            continue
        }

        # Get ACL (Access Control List) of the folder
        $acl = Get-Acl -Path $fullPath

        # Process each access rule
        foreach ($accessRule in $acl.Access) {
            # Check if the rule applies to an AD group
            if ($accessRule.IdentityReference -like "*\*") {
                $identity = $accessRule.IdentityReference.Value
                $groupName = $identity.Split('\')[1]

                # Get AD group details (if it exists)
                try {
                    $group = Get-ADGroup -Identity $groupName -ErrorAction Stop
                    $results += [PSCustomObject]@{
                        Server        = $server
                        SharePath     = $path
                        GroupName     = $groupName
                        GroupDN       = $group.DistinguishedName
                        Permission    = $accessRule.FileSystemRights
                        AccessType    = $accessRule.AccessControlType
                        IsInherited   = $accessRule.IsInherited
                    }
                } catch {
                    Write-Warning "Group not found in AD: $groupName (on $server)"
                }
            }
        }
#    }
#}

# Export results to CSV
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

# Display summary
Write-Host "`n=== Report Summary ==="
$results | Group-Object GroupName | ForEach-Object {
    Write-Host "Group '$($_.Name)' has access to:"
    $_.Group | Select-Object Server, SharePath, Permission | Format-Table -AutoSize
}

Write-Host "`nFull report saved to: $outputFile" -ForegroundColor Green