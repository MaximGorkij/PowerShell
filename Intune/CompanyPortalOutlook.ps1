# Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All", "DeviceManagementConfiguration.ReadWrite.All", "Group.Read.All", "User.Read.All"

# Install-Module Microsoft.Graph -Scope CurrentUser

# ====== SETTINGS ======
$groupId = "<ID_skupiny_používateľov>"  # napr. z Entra ID
$companyPortalId = "com.microsoft.windowsintune.companyportal"
$outlookAppId = "com.microsoft.office.outlook"

# ====== 1. Vytvorenie App Configuration pre Outlook ======
$appConfig = @{
    displayName = "Outlook Auto Email Setup"
    description = "Pre-fills work email and enforces SSO"
    targetedAppManagementLevels = "unspecified"
    appConfigurationSchema = @{
        '@odata.type' = "#microsoft.graph.androidManagedStoreAppConfigurationSchema"
    }
    appManagementLevel = "unspecified"
    payloadJson = @{
        EmailAccountName        = "Work Email"
        EmailAccountType        = "OAuth"
        EmailAddress            = "{{UserPrincipalName}}"
        Username                = "{{UserPrincipalName}}"
        AuthenticationType      = "ModernAuth"
        AllowOnlyWorkAccounts   = "true"
    } | ConvertTo-Json -Compress
    targetedApps = @(@{
        mobileAppIdentifier = @{
            "@odata.type" = "#microsoft.graph.androidManagedStoreAppIdentifier"
            packageId = $outlookAppId
        }
    })
}

$appConfigPayload = @{
    "@odata.type" = "#microsoft.graph.androidManagedStoreAppConfiguration"
    displayName = $appConfig.displayName
    description = $appConfig.description
    targetedApps = $appConfig.targetedApps
    payloadJson = $appConfig.payloadJson
}

$appConfigResult = New-MgDeviceAppManagementMobileAppConfiguration -BodyParameter $appConfigPayload

Write-Host "✅ Vytvorená App Config Policy: $($appConfigResult.Id)"

# ====== 2. Pridanie Company Portal a Outlook ako Required Apps ======

function Add-AppAssignment {
    param (
        [string]$appId,
        [string]$groupId
    )

    $assignment = @{
        target = @{
            "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
            groupId = $groupId
        }
        intent = "required"
    }

    New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $appId -BodyParameter $assignment
    Write-Host "📦 Priradená aplikácia: $appId pre skupinu: $groupId"
}

# Získanie App ID z Intune (ak už existuje)
$apps = Get-MgDeviceAppManagementMobileApp

$companyPortal = $apps | Where-Object { $_.DisplayName -like "*Company Portal*" -and $_.IsFeatured -eq $false }
$outlookApp = $apps | Where-Object { $_.DisplayName -like "*Outlook*" -and $_.IsFeatured -eq $false }

if ($companyPortal) {
    Add-AppAssignment -appId $companyPortal.Id -groupId $groupId
} else {
    Write-Warning "❌ Company Portal app not found in Intune"
}

if ($outlookApp) {
    Add-AppAssignment -appId $outlookApp.Id -groupId $groupId
} else {
    Write-Warning "❌ Outlook app not found in Intune"
}

# ====== 3. Priradenie konfigurácie ku skupine ======
$assignmentConfig = @{
    target = @{
        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
        groupId = $groupId
    }
}

New-MgDeviceAppManagementMobileAppConfigurationAssignment `
    -MobileAppConfigurationId $appConfigResult.Id `
    -BodyParameter $assignmentConfig

Write-Host "✅ Priradená konfigurácia Outlooku pre skupinu $groupId"
