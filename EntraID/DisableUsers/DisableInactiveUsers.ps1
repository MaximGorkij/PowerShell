<#
.SYNOPSIS
Disables inactive users after 180 days and converts their mailboxes to Shared.

.DESCRIPTION
- Finds AD accounts that have not logged on for more than 180 days
- Excludes accounts starting with "X-"
- Excludes accounts located in OU=Servis_Accounts,OU=Resources,OU=HQ TG,DC=tauris,DC=local
- Disables the account and converts the mailbox to Shared
- Exports results to CSV
- Supports TestMode (simulation only, no changes applied)
- Automatically connects to Exchange Online if not already connected
- Disconnects from Exchange Online at the end
#>

param(
    [switch]$TestMode,                         # Switch for test mode
    [int]$InactiveDays = 180,                  # Number of inactivity days
    [string]$ExportPath = "C:\Temp\InactiveUsers.csv"
)

# --- Import required modules ---
Import-Module ActiveDirectory

# --- Ensure Exchange Online module is loaded ---
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Error "The ExchangeOnlineManagement module is not installed. Install it using: Install-Module ExchangeOnlineManagement"
    exit 1
}

# --- Connect to Exchange Online if not already connected ---
$connected = $false
try {
    $connInfo = Get-ConnectionInformation -ErrorAction Stop
    if ($connInfo.ConnectionUri) {
        $connected = $true
        Write-Host "Already connected to Exchange Online."
    }
}
catch {
    Write-Host "Not connected to Exchange Online. Prompting for login..."
    try {
        Connect-ExchangeOnline -ShowProgress $true
        $connected = $true
        Write-Host "Connected to Exchange Online."
    }
    catch {
        Write-Error "Failed to connect to Exchange Online: $_"
        exit 1
    }
}

# --- Calculate cutoff date ---
$cutoffDate = (Get-Date).AddDays(-$InactiveDays)

# --- Get inactive AD users ---
$inactiveUsers = Get-ADUser -Filter {LastLogonDate -lt $cutoffDate -and Enabled -eq $true} -Properties LastLogonDate,UserPrincipalName,DistinguishedName

# --- Exclude accounts starting with "X-" ---
$inactiveUsers = $inactiveUsers | Where-Object { $_.SamAccountName -notmatch '^X-' }

# --- Exclude accounts from specific OU ---
$ouToSkip = "OU=Servis_Accounts,OU=Resources,OU=HQ TG,DC=tauris,DC=local"
$inactiveUsers = $inactiveUsers | Where-Object { $_.DistinguishedName -notlike "*$ouToSkip" }

# --- Results for export ---
$export = @()

foreach ($user in $inactiveUsers) {
    $obj = [PSCustomObject]@{
        SamAccountName    = $user.SamAccountName
        UserPrincipalName = $user.UserPrincipalName
        LastLogonDate     = $user.LastLogonDate
        Disabled          = $false
        MailboxConverted  = $false
        Action            = "Planned"
    }

    if ($TestMode) {
        Write-Host "[TEST] Disable-ADAccount $($user.SamAccountName)"
        Write-Host "[TEST] Set-Mailbox $($user.UserPrincipalName) -Type Shared"
        $obj.Action = "TEST - Disable + Shared mailbox"
    }
    else {
        try {
            # Disable AD Account
            Disable-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
            $obj.Disabled = $true

            # Convert mailbox to shared
            try {
                Set-Mailbox -Identity $user.UserPrincipalName -Type Shared -ErrorAction Stop
                $obj.MailboxConverted = $true
            }
            catch {
                Write-Warning "Mailbox conversion failed for $($user.UserPrincipalName): $_"
            }

            $obj.Action = "Disabled + Converted"
        }
        catch {
            Write-Warning "Failed to disable $($user.SamAccountName): $_"
            $obj.Action = "ERROR"
        }
    }

    $export += $obj
}

# --- Export results to CSV ---
$export | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
Write-Host "Done! Export saved to: $ExportPath"

# --- Disconnect from Exchange Online if connected ---
if ($connected) {
    try {
        Disconnect-ExchangeOnline -Confirm:$false
        Write-Host "Disconnected from Exchange Online."
    }
    catch {
        Write-Warning "Could not disconnect from Exchange Online: $_"
    }
}
