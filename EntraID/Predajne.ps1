<#
.SYNOPSIS
    Script for gracefully exiting a specific user's sessions in Microsoft Entra and Office 365 with logging.
.DESCRIPTION
    This script disconnects all active sessions for a specified user in Microsoft Entra ID and Office 365 services,
    logs all actions, and handles errors appropriately.
.NOTES
    File Name      : Exit-UserSessions.ps1
    Author         : Your Name
    Prerequisite   : PowerShell 5.1 or later, Microsoft.Graph module, ExchangeOnlineManagement module
    Version        : 1.1
    run: .\Predajne.ps1 -UserEmail "user@domain.com"
#>

#region Parameters
param (
    [Parameter(Mandatory=$true, HelpMessage="Enter the user's email address")]
    [ValidateScript({
        if ($_ -match '^\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$') {
            $true
        } else {
            throw "Please enter a valid email address"
        }
    })]
    [string]$UserEmail
)
#endregion

#region Initialization
$scriptVersion = "1.1"
$executionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logFileName = "UserSessionExit_$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"
$errorLogFileName = "UserSessionExit_Errors_$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"

# Create log directory if it doesn't exist
$logDir = Join-Path -Path $env:USERPROFILE -ChildPath "Logs\UserSessionExit"
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logPath = Join-Path -Path $logDir -ChildPath $logFileName
$errorLogPath = Join-Path -Path $logDir -ChildPath $errorLogFileName

# Function for consistent logging
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
        
        # Also write to console with appropriate colors
        switch ($Level) {
            "INFO" { Write-Host $logEntry -ForegroundColor Cyan }
            "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
            "ERROR" { Write-Host $logEntry -ForegroundColor Red }
            "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        }
    }
    catch {
        Write-Host "[$timestamp] [ERROR] Failed to write to log file: $_" -ForegroundColor Red
    }
}

# Function for error handling
function Chyba {
    param (
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$CustomMessage
    )
    
    $errorMessage = if ($CustomMessage) { $CustomMessage } else { $ErrorRecord.Exception.Message }
    $fullError = "[Line $($ErrorRecord.InvocationInfo.ScriptLineNumber)] $errorMessage`n$($ErrorRecord | Out-String)"
    
    Write-Log -Message $fullError -Level "ERROR"
    
    try {
        Add-Content -Path $errorLogPath -Value $fullError -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to write to error log file: $_" -ForegroundColor Red
    }
    
    # Optionally continue or break based on error severity
    if ($ErrorRecord.Exception -is [System.Management.Automation.CommandNotFoundException]) {
        return $false
    }
    
    return $true
}

# Start logging
Write-Log -Message "Script execution started (Version $scriptVersion)" -Level "INFO"
Write-Log -Message "Execution date: $executionDate" -Level "INFO"
Write-Log -Message "Target user email: $UserEmail" -Level "INFO"
#endregion

#region Module Management
try {
    # Check for required modules
    $requiredModules = @(
        @{ Name = "Microsoft.Graph.Authentication"; MinimumVersion = "2.0.0" },
        @{ Name = "Microsoft.Graph.Identity.SignIns"; MinimumVersion = "2.0.0" },
        @{ Name = "ExchangeOnlineManagement"; MinimumVersion = "3.0.0" }
    )
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module.Name -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Module $($module.Name) not found, installing..." -Level "WARNING"
            Install-Module -Name $module.Name -Force -AllowClobber -Scope CurrentUser -MinimumVersion $module.MinimumVersion
        }
        
        # Import module
        Import-Module -Name $module.Name -MinimumVersion $module.MinimumVersion -Force -ErrorAction Stop
        Write-Log -Message "Successfully imported module $($module.Name)" -Level "SUCCESS"
    }
}
catch {
    $continue = Chyba -ErrorRecord $_ -CustomMessage "Failed to setup required modules"
    if (-not $continue) {
        Write-Log -Message "Critical module error, exiting script" -Level "ERROR"
        exit 1
    }
}
#endregion

#region Authentication
try {
    Write-Log -Message "Connecting to Microsoft Graph..." -Level "INFO"
    
    # Connect to Microsoft Graph with appropriate scopes
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "AuditLog.Read.All" -ErrorAction Stop
    Write-Log -Message "Successfully connected to Microsoft Graph" -Level "SUCCESS"
    
    Write-Log -Message "Connecting to Exchange Online..." -Level "INFO"
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Log -Message "Successfully connected to Exchange Online" -Level "SUCCESS"
}
catch {
    Chyba -ErrorRecord $_ -CustomMessage "Authentication failed"
    exit 1
}
#endregion

#region User Verification
try {
    Write-Log -Message "Verifying user $UserEmail exists..." -Level "INFO"
    
    $user = Get-MgUser -Filter "userPrincipalName eq '$UserEmail'" -ErrorAction Stop
    
    if (-not $user) {
        Write-Log -Message "User $UserEmail not found in Microsoft Entra ID" -Level "ERROR"
        exit 1
    }
    
    Write-Log -Message "Verified user: $($user.UserPrincipalName) (ID: $($user.Id))" -Level "SUCCESS"
}
catch {
    Chyba -ErrorRecord $_ -CustomMessage "User verification failed"
    exit 1
}
#endregion

#region Microsoft Entra (Azure AD) Session Termination
try {
    Write-Log -Message "Starting Microsoft Entra ID session termination for $UserEmail..." -Level "INFO"
    
    # Check if user has active sessions
    $lastSignIn = $user.SignInActivity.LastSignInDateTime
    $isActive = $lastSignIn -and ($lastSignIn -gt (Get-Date).AddDays(-1))
    
    if ($isActive) {
        Write-Log -Message "User has active sessions (last sign-in: $lastSignIn)" -Level "INFO"
        
        try {
            # Revoke all refresh tokens (sign out user from all devices)
            Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop
            Write-Log -Message "Successfully revoked all sessions for $UserEmail" -Level "SUCCESS"
            
            # Additional check to confirm sessions were revoked
            Start-Sleep -Seconds 5
            $updatedUser = Get-MgUser -UserId $user.Id -Property SignInActivity -ErrorAction SilentlyContinue
            if ($updatedUser.SignInActivity.LastSignInDateTime -ge $lastSignIn) {
                Write-Log -Message "Warning: User session may not have been fully terminated" -Level "WARNING"
            }
        }
        catch {
            Chyba -ErrorRecord $_ -CustomMessage "Failed to revoke sessions for $UserEmail"
        }
    }
    else {
        Write-Log -Message "No recent active sessions found for $UserEmail (last sign-in: $lastSignIn)" -Level "INFO"
    }
}
catch {
    Chyba -ErrorRecord $_ -CustomMessage "Microsoft Entra ID session termination failed"
}
#endregion

#region Office 365 Session Termination
try {
    Write-Log -Message "Starting Office 365 session termination for $UserEmail..." -Level "INFO"
    
    # Disconnect active Exchange Online sessions
    try {
        $mailbox = Get-EXOMailbox -Identity $UserEmail -ErrorAction SilentlyContinue
        
        if ($mailbox) {
            $sessions = Get-EXOMailboxSession -Mailbox $UserEmail -ErrorAction SilentlyContinue
            
            if ($sessions) {
                Write-Log -Message "Found $($sessions.Count) active Exchange Online sessions for $UserEmail" -Level "INFO"
                
                foreach ($session in $sessions) {
                    try {
                        Remove-PSSession -Id $session.Id -ErrorAction Stop
                        Write-Log -Message "Successfully disconnected Exchange Online session $($session.Id)" -Level "SUCCESS"
                    }
                    catch {
                        Chyba -ErrorRecord $_ -CustomMessage "Failed to disconnect Exchange Online session $($session.Id)"
                    }
                }
            }
            else {
                Write-Log -Message "No active Exchange Online sessions found for $UserEmail" -Level "INFO"
            }
            
            # Block sign-in temporarily (optional)
            try {
                Set-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction SilentlyContinue
                Write-Log -Message "Temporarily disabled user account to prevent new sessions" -Level "INFO"
                
                # Re-enable after a delay (adjust as needed)
                Start-Sleep -Seconds 30
                Set-MgUser -UserId $user.Id -AccountEnabled:$true -ErrorAction SilentlyContinue
                Write-Log -Message "Re-enabled user account" -Level "INFO"
            }
            catch {
                Chyba -ErrorRecord $_ -CustomMessage "Failed to toggle account enabled status"
            }
        }
        else {
            Write-Log -Message "No Exchange mailbox found for $UserEmail" -Level "INFO"
        }
    }
    catch {
        Chyba -ErrorRecord $_ -CustomMessage "Exchange Online session termination failed"
    }
}
catch {
    Chyba -ErrorRecord $_ -CustomMessage "Office 365 session termination failed"
}
#endregion

#region Cleanup and Disconnect
try {
    Write-Log -Message "Disconnecting from services..." -Level "INFO"
    
    # Disconnect from Exchange Online
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log -Message "Successfully disconnected from Exchange Online" -Level "SUCCESS"
    }
    catch {
        Chyba -ErrorRecord $_ -CustomMessage "Failed to disconnect from Exchange Online"
    }
    
    # Disconnect from Microsoft Graph
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Log -Message "Successfully disconnected from Microsoft Graph" -Level "SUCCESS"
    }
    catch {
        Chyba -ErrorRecord $_ -CustomMessage "Failed to disconnect from Microsoft Graph"
    }
}
catch {
    Chyba -ErrorRecord $_ -CustomMessage "Service disconnection failed"
}
#endregion

#region Finalization
$executionTime = [math]::Round((New-TimeSpan -Start $executionDate -End (Get-Date)).TotalMinutes, 2)
Write-Log -Message "Script execution completed in $executionTime minutes" -Level "INFO"
Write-Log -Message "Log files can be found at:`n$logPath`n$errorLogPath" -Level "INFO"

# Open log directory in Explorer
try {
    Start-Process explorer.exe -ArgumentList $logDir
}
catch {
    Write-Log -Message "Failed to open log directory: $_" -Level "WARNING"
}

exit 0
#endregion