# Module: Get-PIMApprovers.psm1

# Requires -Modules Microsoft.Graph.Identity.Governance, Microsoft.Graph.Groups, Microsoft.Graph.Users, Microsoft.Graph.DirectoryObjects
# Requires -Version 5.1

function Get-PIMApprovers {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$OutputPath = ".\PIMApprovers.csv",
        
        [Parameter()]
        [switch]$IncludeInactiveRoles
    )

    begin {
        try {
            # Check if already connected to Microsoft Graph
            $context = Get-MgContext
            if (-not $context) {
                Write-Error "Not connected to Microsoft Graph. Please run Connect-MgGraph with Directory.Read.All and PrivilegedAccess.Read.AzureAD permissions"
                return
            }

            # Initialize results array
            $results = @()
            
            # Create a hashtable to store role definitions
            $roleDefinitions = @{}
        }
        catch {
            Write-Error "Error in initialization: $_"
            return
        }
    }

    process {
        try {
        
            # Get all role definitions in one call
            Write-Verbose "Fetching all role definitions..."
            $allRoleDefinitions = Get-MgDirectoryRoleTemplate
            foreach ($def in $allRoleDefinitions) {
                $roleDefinitions[$def.Id] = $def
            }
        
            # Get all policy assignments and their rules in one call
            Write-Verbose "Fetching policy assignments and rules..."
            $policyAssignments = Get-MgPolicyRoleManagementPolicyAssignment -Filter "scopeId eq '/' and scopeType eq 'Directory'" -ExpandProperty "policy(`$expand=rules)"
            
            # Setup progress bar
            $totalAssignments = $policyAssignments.Count
            $currentAssignment = 0
        
            foreach ($assignment in $policyAssignments) {
                # Update progress bar
                $currentAssignment++
                $percentComplete = [math]::Round(($currentAssignment / $totalAssignments) * 100)
                $roleName = $roleDefinitions[$assignment.RoleDefinitionId].DisplayName
                
                Write-Progress -Activity "Processing PIM Role Approvers" -Status "Role $currentAssignment of $totalAssignments" `
                    -PercentComplete $percentComplete -CurrentOperation $roleName
                
                Write-Verbose "Processing assignment for role template: $($assignment.RoleDefinitionId)"
                        
                # Get role definition from our hashtable
                $roleDefinition = $roleDefinitions[$assignment.RoleDefinitionId]
                if (-not $roleDefinition) {
                    Write-Warning "Could not find role definition for template ID: $($assignment.RoleDefinitionId)"
                    continue
                }
        
                # Get approval settings from policy rules
                $approvalRule = $assignment.Policy.Rules | Where-Object { $_.Id -eq 'Approval_EndUser_Assignment' -and $_.AdditionalProperties.setting.isApprovalRequired -eq $true }
                if (-not $approvalRule) {
                    Write-Verbose "No approval settings found / or is required for role: $($roleDefinition.DisplayName)"
                    continue
                }
        
                # https://learn.microsoft.com/en-us/graph/api/resources/unifiedrolemanagementpolicyapprovalrule?view=graph-rest-1.0
                # Process primary approvers
                $primaryApprovers = $approvalRule.AdditionalProperties.setting.approvalStages.primaryApprovers
                if ($primaryApprovers) {
                    foreach ($approver in $primaryApprovers) {
                        if ($approver["@odata.type"] -eq '#microsoft.graph.singleUser') {
                            # Get user details
                            $approverDetails = Get-MgUser -UserId $approver.userId -Property "displayName,id,userPrincipalName,accountEnabled"
                                    
                            if ($approverDetails) {
                                $results += [PSCustomObject]@{
                                    RoleName         = $roleDefinition.DisplayName
                                    RoleDescription  = $roleDefinition.Description
                                    RoleTemplateId   = $assignment.RoleDefinitionId
                                    ApproverId       = $approverDetails.Id
                                    ApproverName     = $approverDetails.DisplayName
                                    ApproverUPN      = $approverDetails.UserPrincipalName
                                    ApproverType     = 'Direct'
                                    ApprovalStep     = 'Primary'
                                    ApproverEnabled  = $approverDetails.AccountEnabled
                                    GroupId          = ''
                                    GroupName        = ''
                                    PolicyId         = $assignment.PolicyId
                                    RequiresApproval = $true
                                    ApproverCount    = $approvalRule.AdditionalProperties.setting.approvalRequired
                                    ApprovalDuration = $approvalRule.AdditionalProperties.setting.durationInDays
                                }
                            }
                        }
                        elseif ($approver["@odata.type"] -eq '#microsoft.graph.groupMembers') {
                            # Get group members
                            $groupMembers = Get-MgGroupMemberAsUser -GroupId $approver.groupId -Property "displayName,id,userPrincipalName,accountEnabled" -All
                            foreach ($member in $groupMembers) {
                                $results += [PSCustomObject]@{
                                    RoleName         = $roleDefinition.DisplayName
                                    RoleDescription  = $roleDefinition.Description
                                    RoleTemplateId   = $assignment.RoleDefinitionId
                                    ApproverId       = $member.Id
                                    ApproverName     = $member.DisplayName
                                    ApproverUPN      = $member.UserPrincipalName
                                    ApproverType     = 'Group Member'
                                    ApprovalStep     = 'Primary'
                                    ApproverEnabled  = $member.AccountEnabled
                                    GroupId          = $approver.groupId
                                    GroupName        = $approver.description
                                    PolicyId         = $assignment.PolicyId
                                    RequiresApproval = $true
                                    ApproverCount    = $approvalRule.AdditionalProperties.setting.approvalRequired
                                    ApprovalDuration = $approvalRule.AdditionalProperties.setting.durationInDays
                                }
                            }
                        }
                    }
                }
        
                # Process escalation approvers
                $escalationApprovers = $approvalRule.AdditionalProperties.setting.approvalStages.escalationApprovers
                if ($escalationApprovers) {
                    foreach ($approver in $escalationApprovers) {
                        if ($approver["@odata.type"] -eq '#microsoft.graph.singleUser') {
                            # Get user details
                            $approverDetails = Get-MgUser -UserId $approver.userId -Property "displayName,id,userPrincipalName,accountEnabled"
                                    
                            if ($approverDetails) {
                                $results += [PSCustomObject]@{
                                    RoleName         = $roleDefinition.DisplayName
                                    RoleDescription  = $roleDefinition.Description
                                    RoleTemplateId   = $assignment.RoleDefinitionId
                                    ApproverId       = $approverDetails.Id
                                    ApproverName     = $approverDetails.DisplayName
                                    ApproverUPN      = $approverDetails.UserPrincipalName
                                    ApproverType     = 'Direct'
                                    ApprovalStep     = 'Escalation'
                                    ApproverEnabled  = $approverDetails.AccountEnabled
                                    GroupId          = ''
                                    GroupName        = ''
                                    PolicyId         = $assignment.PolicyId
                                    RequiresApproval = $true
                                    ApproverCount    = $approvalRule.AdditionalProperties.setting.approvalRequired
                                    ApprovalDuration = $approvalRule.AdditionalProperties.setting.durationInDays
                                    EscalationTime   = $approvalRule.AdditionalProperties.setting.approvalStages.escalationTimeInMinutes
                                }
                            }
                        }
                        elseif ($approver["@odata.type"] -eq '#microsoft.graph.groupMembers') {
                            # Get group members
                            $groupMembers = Get-MgGroupMemberAsUser -GroupId $approver.groupId -Property "displayName,id,userPrincipalName,accountEnabled" -All
                            foreach ($member in $groupMembers) {
                                $results += [PSCustomObject]@{
                                    RoleName         = $roleDefinition.DisplayName
                                    RoleDescription  = $roleDefinition.Description
                                    RoleTemplateId   = $assignment.RoleDefinitionId
                                    ApproverId       = $member.Id
                                    ApproverName     = $member.DisplayName
                                    ApproverUPN      = $member.UserPrincipalName
                                    ApproverType     = 'Group Member'
                                    ApprovalStep     = 'Escalation'
                                    ApproverEnabled  = $member.AccountEnabled
                                    GroupId          = $approver.groupId
                                    GroupName        = $approver.description
                                    PolicyId         = $assignment.PolicyId
                                    RequiresApproval = $true
                                    ApproverCount    = $approvalRule.AdditionalProperties.setting.approvalRequired
                                    ApprovalDuration = $approvalRule.AdditionalProperties.setting.durationInDays
                                    EscalationTime   = $approvalRule.AdditionalProperties.setting.approvalStages.escalationTimeInMinutes
                                }
                            }
                        }
                    }
                }
            }
            
            # Clear progress bar
            Write-Progress -Activity "Processing PIM Role Approvers" -Completed
                    
            # Export results to CSV
            if ($results.Count -gt 0) {
                $results | Export-Csv -Path $OutputPath -NoTypeInformation
                Write-Host "Exported $($results.Count) PIM approvers to $OutputPath"
            }
            else {
                Write-Warning "No PIM approvers found to export"
            }
        }
        catch {
            Write-Error "Error processing roles: $_"
            Write-Error $_.Exception.StackTrace
        }
    }

    end {
        try {
            # Return the results object for pipeline use
            return $results
        }
        catch {
            Write-Error "Error in cleanup: $_"
        }
    }
}

Export-ModuleMember -Function Get-PIMApprovers