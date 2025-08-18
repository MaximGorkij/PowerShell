<#
    .SYNOPSIS
    Export-EntraIDUsers.ps1

    .DESCRIPTION
    Export Microsoft Entra ID users to CSV file.

    .LINK
    www.alitajran.com/export-microsoft-entra-id-users-to-csv-powershell

    .NOTES
    Written by: ALI TAJRAN
    Website:    www.alitajran.com
    LinkedIn:   linkedin.com/in/alitajran

    .CHANGELOG
    V1.60, 12/20/2024- Removed the MgBeta commands
#>

# Connect to Microsoft Graph API
Connect-MgGraph -Scopes "User.Read.All", "UserAuthenticationMethod.Read.All", "AuditLog.Read.All", "Organization.Read.All" -NoWelcome

# Create variable for the date stamp
$LogDate = Get-Date -f yyyyMMddhhmm

# Define CSV file export location variable
$Csvfile = "C:\temp\AllEntraIDUsers_$LogDate.csv"

# Check for Entra ID Premium subscription
$hasPremium = $false

# Retrieve all subscribed SKUs and check for Entra ID Premium
$hasPremium = (Get-MgSubscribedSku).ServicePlans.ServicePlanName -contains "AAD_PREMIUM"

# Display status of Premium subscription
if ($hasPremium) {
    Write-Host "Microsoft Entra ID Premium subscription available." -ForegroundColor Cyan
}
else {
    Write-Host "Microsoft Entra ID Premium subscription not available." -ForegroundColor Cyan
}

# If Premium is available, include the sign-in activity in the user query
# Define common properties
$commonProperties = @(
    'Id'
    'GivenName'
    'SurName'
    'DisplayName'
    'UserPrincipalName'
    'Mail'
    'JobTitle'
    'Department'
    'CompanyName'
    'OfficeLocation'
    'ProxyAddresses'
    'createdDateTime'
    'EmployeeID'
    'MobilePhone'
    'BusinessPhones'
    'StreetAddress'
    'City'
    'PostalCode'
    'State'
    'Country'
    'UserType'
    'onPremisesSyncEnabled'
    'AccountEnabled'
    'assignedLicenses'
)

# If Premium is available, include the sign-in activity in the user query
if ($hasPremium) {
    $propertyParams = @{
        All            = $true
        ExpandProperty = 'manager'
        Property       = @('SignInActivity') + $commonProperties
    }
}
else {
    $propertyParams = @{
        All            = $true
        ExpandProperty = 'manager', 'createdDateTime'
        Property       = $commonProperties
    }
}
$users = Get-MgUser @propertyParams
$totalUsers = $users.Count

# Initialize progress counter
$progress = 0

# Initialize a List to store the data
$Report = [System.Collections.Generic.List[Object]]::new()

# Loop through all users and collect user objects
foreach ($index in 0..($totalUsers - 1)) {
    $user = $users[$index]

    # Update progress counter
    $progress++

    # Calculate percentage complete
    $percentComplete = ($progress / $totalUsers) * 100

    # Define progress bar parameters
    $progressParams = @{
        Activity        = "Processing Users"
        Status          = "User $($index + 1) of $totalUsers - $($user.userPrincipalName) - $($percentComplete -as [int])% Complete"
        PercentComplete = $percentComplete
    }

    # Display progress bar
    Write-Progress @progressParams

    # Get manager information
    $managerDN = if ($user.Manager) { $user.Manager.AdditionalProperties.displayName } else { $null }
    $managerUPN = if ($user.Manager) { $user.Manager.AdditionalProperties.userPrincipalName } else { $null }

    # Create an object to store user properties
    $ReportLine = [PSCustomObject]@{
        "ID"                           = $user.id
        "First name"                   = $user.givenName
        "Last name"                    = $user.surname
        "Display name"                 = $user.displayName
        "User principal name"          = $user.userPrincipalName
        "Domain name"                  = $user.userPrincipalName.Split('@')[1]
        "Email address"                = $user.mail
        "Job title"                    = $user.jobTitle
        "Manager display name"         = $managerDN
        "Manager user principal name"  = $managerUPN
        "Department"                   = $user.department
        "Company"                      = $user.companyName
        "Office"                       = $user.officeLocation
        "Employee ID"                  = $user.employeeID
        "Mobile"                       = $user.mobilePhone
        "Phone"                        = $user.businessPhones -join ','
        "Street"                       = $user.streetAddress
        "City"                         = $user.city
        "Postal code"                  = $user.postalCode
        "State"                        = $user.state
        "Country"                      = $user.country
        "User type"                    = $user.userType
        "On-Premises sync"             = if ($user.onPremisesSyncEnabled) { "enabled" } else { "disabled" }
        "Account status"               = if ($user.accountEnabled) { "enabled" } else { "disabled" }
        "Account Created on"           = $user.createdDateTime
        "Last successful sign in"      = if ($hasPremium) { if ($user.SignInActivity.LastSuccessfulSignInDateTime) { $user.SignInActivity.LastSuccessfulSignInDateTime } else { "No sign in" } } else { "No Microsoft Entra ID Premium license" }
        "Licensed"                     = if ($user.assignedLicenses.Count -gt 0) { "Yes" } else { "No" }
        "DefaultMFAMethod"             = "-"
        "MFA status"                   = "-"
        "Email authentication"         = "-"
        "FIDO2 authentication"         = "-"
        "Microsoft Authenticator App"  = "-"
        "Microsoft Authenticator Lite" = "-"
        "Phone authentication"         = "-"
        "Software Oath"                = "-"
        "Temporary Access Pass"        = "-"
        "Windows Hello for Business"   = "-"
    }

    # Retrieve the default MFA method
    $DefaultMFAUri = "https://graph.microsoft.com/beta/users/$($user.Id)/authentication/signInPreferences"
    $DefaultMFAMethod = Invoke-MgGraphRequest -Uri $DefaultMFAUri -Method GET
    if ($DefaultMFAMethod.userPreferredMethodForSecondaryAuthentication) {
        $ReportLine.DefaultMFAMethod = $DefaultMFAMethod.userPreferredMethodForSecondaryAuthentication
    }
    else {
        $ReportLine.DefaultMFAMethod = "Not set"
    }


    # Check authentication methods for each user
    $MFAData = Get-MgUserAuthenticationMethod -UserId $user.Id

    foreach ($method in $MFAData) {
        Switch ($method.AdditionalProperties["@odata.type"]) {
            "#microsoft.graph.emailAuthenticationMethod" {
                $ReportLine."Email authentication" = $true
                $ReportLine."MFA status" = "Enabled"
            }
            "#microsoft.graph.fido2AuthenticationMethod" {
                $ReportLine."FIDO2 authentication" = $true
                $ReportLine."MFA status" = "Enabled"
            }
            "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" {
                if ($method.AdditionalProperties["deviceTag"] -eq 'SoftwareTokenActivated') {
                    $ReportLine."Microsoft Authenticator App" = $true
                    $ReportLine."MFA status" = "Enabled"
                }
                else {
                    $ReportLine."Microsoft Authenticator Lite" = $true
                    $ReportLine."MFA status" = "Enabled"
                }
            }
            "#microsoft.graph.phoneAuthenticationMethod" {
                $ReportLine."Phone authentication" = $true
                $ReportLine."MFA status" = "Enabled"
            }
            "#microsoft.graph.softwareOathAuthenticationMethod" {
                $ReportLine."Software Oath" = $true
                $ReportLine."MFA status" = "Enabled"
            }
            "#microsoft.graph.temporaryAccessPassAuthenticationMethod" {
                $ReportLine."Temporary Access Pass" = $true
                $ReportLine."MFA status" = "Enabled"
            }
            "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" {
                $ReportLine."Windows Hello for Business" = $true
                $ReportLine."MFA status" = "Enabled"
            }
        }
    }
    # Add the report line to the List
    $Report.Add($ReportLine)
}

# Complete the progress bar
Write-Progress -Activity "Processing Users" -Completed

# Export all user objects to CSV
$Report | Sort-Object "Display name" | Export-Csv -Path $Csvfile -NoTypeInformation -Encoding UTF8
Write-Host "Microsoft Entra ID users exported to $Csvfile." -ForegroundColor Cyan