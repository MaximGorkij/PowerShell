param (
    [string]$UserPrincipalName
)

# Define log file path
$logFile = "C:\Windows\Temp\DisableUserLog-.txt"

# Function to log messages
function Write-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $message"
    Write-Output $logEntry | Out-File -FilePath $logFile -Append
}

# Function to log errors
function Write-ErrorLog {
    param (
        [string]$errorMessage
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $errorEntry = "$timestamp - ERROR: $errorMessage"
    Write-Output $errorEntry | Out-File -FilePath $logFile -Append
}

Write-Message "Starting script for user $UserPrincipalName"

try {
    # Connect to MS Entra
    Write-Message "Connecting to MS Entra"
    Connect-AzureAD
    $msEntraUser = Get-AzureADUser -ObjectId $UserPrincipalName
    if ($msEntraUser) {
        Write-Message "Disabling MS Entra user $UserPrincipalName"
        Set-AzureADUser -ObjectId $msEntraUser.ObjectId -AccountEnabled $false
    } else {
        Write-Message "MS Entra user $UserPrincipalName not found"
    }
} catch {
    Write-ErrorLog "Failed to disable MS Entra user $UserPrincipalName : $_"
}

try {
    # Connect to Exchange Online
    Write-Message "Connecting to Exchange Online"
    Connect-ExchangeOnline
    $exchangeUser = Get-Mailbox -Identity $UserPrincipalName
    if ($exchangeUser) {
        Write-Message "Disabling Exchange mailbox for user $UserPrincipalName"
        Disable-Mailbox -Identity $UserPrincipalName
    } else {
        Write-Message "Exchange mailbox for user $UserPrincipalName not found"
    }
} catch {
    Write-ErrorLog "Failed to disable Exchange mailbox for user $UserPrincipalName : $_"
}

try {
    # Connect to Intune
    Write-Message "Connecting to Intune"
    Connect-MSGraph
    $intuneUser = Get-IntuneUser -UserPrincipalName $UserPrincipalName
    if ($intuneUser) {
        Write-Message "Revoking Intune tokens for user $UserPrincipalName"
        Revoke-AzureADSignedInUserAllRefreshToken -ObjectId $intuneUser.Id
    } else {
        Write-Message "Intune user $UserPrincipalName not found"
    }
} catch {
    Write-ErrorLog "Failed to revoke Intune tokens for user $UserPrincipalName : $_"
}

try {
    # Connect to Office 365
    Write-Message "Checking Office 365 licenses for user $UserPrincipalName"
    $officeLicenses = Get-MsolUser -UserPrincipalName $UserPrincipalName | Select-Object -ExpandProperty Licenses
    if ($officeLicenses) {
        Write-Message "Removing Office 365 licenses for user $UserPrincipalName"
        Set-MsolUserLicense -UserPrincipalName $UserPrincipalName -RemoveLicenses $officeLicenses.AccountSkuId
    } else {
        Write-Message "Office 365 licenses for user $UserPrincipalName not found"
    }
} catch {
    Write-ErrorLog "Failed to remove Office 365 licenses for user $UserPrincipalName : $_"
}

Write-Message "Script completed for user $UserPrincipalName"
Write-Output "User $UserPrincipalName has been disabled in MS Entra, Exchange, Intune, and Office 365."
