#Requires -Module ActiveDirectory
#Requires -Module ImportExcel

<#
.SYNOPSIS
    Audits Windows share permissions for root and one level of subdirectories, exports to Excel with logging.
    Optimized to avoid re-checking already processed AD groups.
.DESCRIPTION
    This script checks NTFS permissions on a UNC path, identifies AD groups with access,
    enumerates their members (without duplicates), and exports all data to an Excel file with separate sheets.
.NOTES
    Version: 1.1
    Author: Your Name
    Date: $(Get-Date -Format 'yyyy-MM-dd')
    Changes: Added optimization to avoid re-processing the same AD groups
#>

param (
<#    [Parameter(Mandatory=$true)]
    [string]$UncPath = "\\fsrs21\Rada$",
    
    [Parameter(Mandatory=$true)]
    [string]$OutputExcelFile = "ShareAudit$timestamp.xlsx",
    
    [Parameter(Mandatory=$true)]
    [string]$LogFile = "ShareAudit$timestamp.log",
#>    
    [PSCredential]$Credential
)

# Initialize logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    
    if ($Level -eq "ERROR") {
        Write-Host $logEntry -ForegroundColor Red
    } elseif ($Level -eq "WARNING") {
        Write-Host $logEntry -ForegroundColor Yellow
    } else {
        Write-Host $logEntry
    }
}


try {
    $UncPath = "\\fsrs21\Rada$"
    $OutputExcelFile = "ShareAudit$timestamp.xlsx"
    $LogFile = "ShareAudit$timestamp.log"

    # Start logging
    Write-Log "Starting Windows Share Audit Script (Optimized Version)"
    Write-Log "Target UNC Path: $UncPath"
    Write-Log "Output Excel File: $OutputExcelFile"
    
    # Test UNC path accessibility
    Write-Log "Testing connection to $UncPath"
    try {
        if ($Credential) {
            $testPath = Test-Path -Path $UncPath #-Credential $Credential
        } else {
            $testPath = Test-Path -Path $UncPath
        }
        
        if (-not $testPath) {
            throw "Path $UncPath is not accessible"
        }
    } catch {
        Write-Log "Error accessing $UncPath : $_" -Level ERROR
        throw
    }
    
    # Initialize data collections
    $rootPermissions = @()
    $subDirPermissions = @()
    $groupMembers = @()
    $processedGroups = @{} # Hash table to track already processed groups
    
    # Function to get permissions for a directory
    function Get-DirectoryPermissions {
        param (
            [string]$Path,
            [bool]$IsRoot
        )
        
        Write-Log "Processing permissions for: $Path"
        
        try {
            if ($Credential) {
                $acl = Get-Acl -Path $Path -Credential $Credential
            } else {
                $acl = Get-Acl -Path $Path
            }
            
            foreach ($access in $acl.Access) {
                $identity = $access.IdentityReference.Value
                
                # Skip non-AD accounts (like BUILTIN, NT AUTHORITY)
                if (-not $identity.Contains("\")) {
                    Write-Log "Skipping non-domain identity: $identity" -Level WARNING
                    continue
                }
                
                if (-not $identity.Contains("TAURIS\DL_")) {
                    Write-Log "Skipping non-DL group: $identity" -Level WARNING
                    continue
                }
                # Extract domain and name
                $domain, $name = $identity -split "\\", 2
                
                # Create permission object
                $obj = [PSCustomObject]@{
                    Path = $Path
                    Domain = $domain
                    Identity = $name
                    IsRoot = $IsRoot
                    AccessType = $access.AccessControlType
                    Rights = $access.FileSystemRights -join ", "
                    IsInherited = $access.IsInherited
                    InheritanceFlags = $access.InheritanceFlags
                    PropagationFlags = $access.PropagationFlags
                }
                
                if ($IsRoot) {
                    $script:rootPermissions += $obj
                } else {
                    $script:subDirPermissions += $obj
                }
                
                # Check if this is an AD group and not already processed
                if (-not $processedGroups.ContainsKey($name)) {
                    try {
                        $adObject = Get-ADObject -Filter { SamAccountName -eq $name } -Properties SamAccountName, ObjectClass
                        
                        if ($adObject.ObjectClass -eq "group") {
                            Write-Log "Found new AD group with access: $name"
                            $processedGroups[$name] = $true # Mark as processed
                            
                            # Get group members
                            $members = Get-ADGroupMember -Identity $name -Recursive | 
                                Get-ADUser -Properties Enabled, PasswordNeverExpires, PasswordExpired, LastLogonDate |
                                Select-Object @{Name="Group";Expression={$name}},
                                    SamAccountName,
                                    Name,
                                    UserPrincipalName,
                                    Enabled,
                                    @{Name="AccountStatus";Expression={
                                        if (-not $_.Enabled) { "Disabled" }
                                        elseif ($_.PasswordExpired) { "Password Expired" }
                                        elseif ($_.PasswordNeverExpires) { "Password Never Expires" }
                                        else { "Active" }
                                    }},
                                    LastLogonDate,
                                    DistinguishedName
                            
                            $script:groupMembers += $members
                        }
                    } catch {
                        Write-Log "Error processing AD object $name : $_" -Level WARNING
                    }
                } else {
                    Write-Log "Skipping already processed group: $name" -Level INFO
                }
            }
        } catch {
            Write-Log "Error getting permissions for $Path : $_" -Level ERROR
        }
    }
    
    # Process root directory
    Get-DirectoryPermissions -Path $UncPath -IsRoot $true
    
    # Process one level of subdirectories
    Write-Log "Processing subdirectories under $UncPath"
    try {
        if ($Credential) {
            $subDirs = Get-ChildItem -Path $UncPath -Directory -Credential $Credential
        } else {
            $subDirs = Get-ChildItem -Path $UncPath -Directory
        }
        
        foreach ($dir in $subDirs) {
            $fullPath = Join-Path -Path $UncPath -ChildPath $dir.Name
            Get-DirectoryPermissions -Path $fullPath -IsRoot $false
        }
    } catch {
        Write-Log "Error processing subdirectories: $_" -Level ERROR
    }
    
    # Export data to CSVs and then to Excel
    Write-Log "Exporting data to Excel workbook"
    
    # Create temporary directory for CSVs
    $tempDir = Join-Path -Path $env:TEMP -ChildPath "ShareAudit_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    # Export root permissions
    $rootCsv = Join-Path -Path $tempDir -ChildPath "RootPermissions.csv"
    $rootPermissions | Export-Csv -Path $rootCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Exported root permissions to $rootCsv"
    
    # Export subdirectory permissions
    $subDirCsv = Join-Path -Path $tempDir -ChildPath "SubDirPermissions.csv"
    $subDirPermissions | Export-Csv -Path $subDirCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Exported subdirectory permissions to $subDirCsv"
    
    # Export group members
    $membersCsv = Join-Path -Path $tempDir -ChildPath "GroupMembers.csv"
    $groupMembers | Export-Csv -Path $membersCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Exported group members to $membersCsv"
    
    # Combine CSVs into Excel
    try {
        $excelParams = @{
            Path = $OutputExcelFile
            Show = $false
            AutoSize = $true
            FreezeTopRow = $true
            BoldTopRow = $true
            WorksheetName = "Root Permissions", "SubDir Permissions", "Group Members"
            ClearSheet = $true
        }
        
        Import-Csv $rootCsv | Export-Excel @excelParams -WorksheetName "Root Permissions"
        Import-Csv $subDirCsv | Export-Excel @excelParams -WorksheetName "SubDir Permissions"
        Import-Csv $membersCsv | Export-Excel @excelParams -WorksheetName "Group Members" | Sort-Object Group, Name
        
        Write-Log "Successfully created Excel workbook at $OutputExcelFile"
    } catch {
        Write-Log "Error creating Excel workbook: $_" -Level ERROR
        throw
    }
    
    # Clean up temp files
    Remove-Item -Path $tempDir -Recurse -Force
    Write-Log "Cleaned up temporary files"
    
    Write-Log "Script completed successfully. Processed $($processedGroups.Count) unique AD groups."
} catch {
    Write-Log "Script failed: $_" -Level ERROR
    exit 1
}