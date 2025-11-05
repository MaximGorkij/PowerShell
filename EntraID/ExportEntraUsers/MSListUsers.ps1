<#
.SYNOPSIS
    Export Microsoft 365 users via Microsoft Graph API with batch processing and enhanced formatting.
.DESCRIPTION
    This script exports Entra ID users to CSV with comprehensive user information including sign-in activity.
    Features batch processing, shared mailbox exclusion, progress tracking, detailed logging and email notification.
.VERSION
    3.5
.AUTHOR
    PowerShell Script
.DATE
    $(Get-Date -Format "yyyy-MM-dd")
#>

param (
    [Parameter(Mandatory = $false, HelpMessage = "Path to authentication XML file")]
    [string]$AuthFile = ".\GraphAuth.xml",
    
    [Parameter(Mandatory = $false, HelpMessage = "Number of users to process per batch")]
    [ValidateRange(10, 500)]
    [int]$BatchSize = 100,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip email-related properties")]
    [switch]$SkipEmail,
    
    [Parameter(Mandatory = $false, HelpMessage = "Exclude shared mailboxes from export")]
    [switch]$ExcludeSharedMailboxes = $true,
    
    [Parameter(Mandatory = $false, HelpMessage = "Output directory for export files")]
    [string]$OutputPath = $PSScriptRoot
)

#region Initialization
# --- Timestamp and paths ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ExportPath = Join-Path $OutputPath "EntraUsers_$timestamp.csv"
$LogPath = Join-Path $OutputPath "EntraUsersLog_$timestamp.log"
$StartTime = Get-Date

# --- Required modules ---
$requiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users",
    "Microsoft.Graph.Reports",
    "Microsoft.Graph.Mail"
)

# --- Console formatting ---
$Host.UI.RawUI.WindowTitle = "Entra Users Export v3.5"
Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "ENTRA USERS EXPORT SCRIPT" -ForegroundColor Yellow
Write-Host "Version 3.5 | Started: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "`n"

# --- Logging Helper Function ---
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogPath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry -ForegroundColor White }
    }
    
    # File logging
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        # If file logging fails, continue without it
    }
}

# --- Separator in log ---
$separator = ("=" * 80)
Add-Content -Path $LogPath -Value "`n$separator"
Add-Content -Path $LogPath -Value "SCRIPT STARTED: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
Add-Content -Path $LogPath -Value "Version: 3.5 | Parameters: AuthFile=$AuthFile, BatchSize=$BatchSize, ExcludeSharedMailboxes=$ExcludeSharedMailboxes"
Add-Content -Path $LogPath -Value $separator

Write-Log -Message "=== Starting Entra Users Export v3.5 ===" -Level "INFO" -LogPath $LogPath
#endregion

#region Module Management
Write-Log -Message "Checking required PowerShell modules..." -Level "INFO" -LogPath $LogPath

foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Log -Message "Installing module: $m..." -Level "INFO" -LogPath $LogPath
        try {
            Install-Module $m -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Log -Message "Successfully installed module: $m" -Level "SUCCESS" -LogPath $LogPath
        }
        catch {
            Write-Log -Message "Failed to install module $m : $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
            exit 1
        }
    }
    try {
        Import-Module $m -Force -ErrorAction Stop
        Write-Log -Message "Imported module: $m" -Level "INFO" -LogPath $LogPath
    }
    catch {
        Write-Log -Message "Failed to import module $m : $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
        exit 1
    }
}
#endregion

#region Authentication
# --- Load credentials ---
Write-Log -Message "Loading authentication credentials from: $AuthFile" -Level "INFO" -LogPath $LogPath

if (-not (Test-Path $AuthFile)) {
    Write-Log -Message "Missing authentication file: $AuthFile" -Level "ERROR" -LogPath $LogPath
    Write-Host "`nPlease create the authentication file with the following structure:" -ForegroundColor Yellow
    Write-Host @"
<GraphAuth>
    <TenantId>your-tenant-id</TenantId>
    <ClientId>your-client-id</ClientId>
    <ClientSecret>your-client-secret</ClientSecret>
</GraphAuth>
"@ -ForegroundColor Gray
    exit 1
}

try {
    [xml]$auth = Get-Content $AuthFile
    $TenantId = $auth.GraphAuth.TenantId
    $ClientId = $auth.GraphAuth.ClientId
    $ClientSecret = $auth.GraphAuth.ClientSecret
    
    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        Write-Log -Message "Missing required authentication fields in XML file." -Level "ERROR" -LogPath $LogPath
        exit 1
    }
    
    Write-Log -Message "Successfully loaded authentication credentials" -Level "SUCCESS" -LogPath $LogPath
}
catch {
    Write-Log -Message "Failed to parse authentication file: $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
    exit 1
}

# --- Detect Graph module version ---
$graphModule = Get-Module Microsoft.Graph.Authentication -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
$graphVersion = $graphModule.Version
Write-Log -Message "Detected Microsoft.Graph.Authentication version: $graphVersion" -Level "INFO" -LogPath $LogPath

# --- Connect to Microsoft Graph ---
try {
    Write-Log -Message "Disconnecting existing Graph sessions..." -Level "INFO" -LogPath $LogPath
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    
    Write-Log -Message "Connecting to Microsoft Graph (App Registration)..." -Level "INFO" -LogPath $LogPath

    # Najkompatibilnejšia metóda pre všetky verzie
    Write-Log -Message "Using most compatible connection method..." -Level "INFO" -LogPath $LogPath
    
    # Metóda 1: Priame použitie parametrov (najkompatibilnejšia)
    try {
        Write-Log -Message "Attempting connection with basic parameters..." -Level "INFO" -LogPath $LogPath
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -ErrorAction Stop
        Write-Log -Message "Successfully connected using basic parameters method" -Level "SUCCESS" -LogPath $LogPath
    }
    catch {
        Write-Log -Message "Basic parameters method failed: $($_.Exception.Message)" -Level "WARNING" -LogPath $LogPath
        
        # Metóda 2: Použitie credential object
        try {
            Write-Log -Message "Trying credential object method..." -Level "INFO" -LogPath $LogPath
            
            # Vytvorenie PSCredential objektu
            $secureString = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureString)
            
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -ErrorAction Stop
            Write-Log -Message "Successfully connected using credential object method" -Level "SUCCESS" -LogPath $LogPath
        }
        catch {
            Write-Log -Message "Credential object method failed: $($_.Exception.Message)" -Level "WARNING" -LogPath $LogPath
            
            # Metóda 3: Legacy metóda pre staršie verzie
            try {
                Write-Log -Message "Trying legacy connection method..." -Level "INFO" -LogPath $LogPath
                
                # Pre staršie verzie, ktoré vyžadujú iný formát
                $body = @{
                    grant_type    = "client_credentials"
                    client_id     = $ClientId
                    client_secret = $ClientSecret
                    scope         = "https://graph.microsoft.com/.default"
                }
                
                $tokenResponse = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body
                $accessToken = $tokenResponse.access_token
                
                # Pripojenie pomocou access tokenu
                Connect-MgGraph -AccessToken $accessToken -ErrorAction Stop
                Write-Log -Message "Successfully connected using access token method" -Level "SUCCESS" -LogPath $LogPath
            }
            catch {
                Write-Log -Message "All connection methods failed: $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
                
                # Zobrazenie detailnejšej pomôcky
                Write-Host "`nTROUBLESHOOTING HELP:" -ForegroundColor Red
                Write-Host "1. Check if Microsoft Graph PowerShell module is installed correctly" -ForegroundColor Yellow
                Write-Host "2. Verify your TenantId, ClientId and ClientSecret in $AuthFile" -ForegroundColor Yellow
                Write-Host "3. Ensure the App Registration has the required permissions:" -ForegroundColor Yellow
                Write-Host "   - User.Read.All" -ForegroundColor White
                Write-Host "   - AuditLog.Read.All" -ForegroundColor White
                Write-Host "   - Mail.Send (if email notification is enabled)" -ForegroundColor White
                Write-Host "4. Try updating the module: Update-Module Microsoft.Graph -Force" -ForegroundColor Yellow
                Write-Host "`n"
                
                throw "All connection methods failed. Please check the troubleshooting guide above."
            }
        }
    }

    # Verify connection
    $context = Get-MgContext
    if ($context) {
        Write-Log -Message "Successfully connected to Microsoft Graph. Tenant: $($context.TenantId), Scopes: $($context.Scopes -join ', ')" -Level "SUCCESS" -LogPath $LogPath
        Write-Host "Connected to Microsoft Graph - Tenant: $($context.TenantId)" -ForegroundColor Green
    }
    else {
        throw "Connection verification failed - no MgContext available"
    }
}
catch {
    Write-Log -Message "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
    Write-Log -Message "Please verify your TenantId, ClientId, and ClientSecret in $AuthFile" -Level "ERROR" -LogPath $LogPath
    exit 1
}
#endregion

#region Helper Functions
# --- Retry wrapper ---
function Invoke-GraphWithRetry {
    param (
        [scriptblock]$ScriptBlock,
        [string]$Operation = "Graph Operation",
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try { 
            return & $ScriptBlock 
        }
        catch {
            $attempt++
            if ($attempt -eq $MaxRetries) {
                Write-Log -Message "$Operation failed after $MaxRetries attempts: $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
                throw
            }
            Write-Log -Message "$Operation failed (attempt $attempt/$MaxRetries). Retrying in $RetryDelay seconds..." -Level "WARNING" -LogPath $LogPath
            Start-Sleep -Seconds $RetryDelay
        }
    }
}

# --- Enhanced Shared Mailbox Detection ---
function Test-IsSharedMailbox {
    param($User)
    
    # Zjednodušená detekcia shared mailboxov - bez MailboxSettings
    $indicators = @(
        (-not $User.AssignedLicenses),
        ($User.UserPrincipalName -match "\.shared\.|\.mailbox\.|_shared_|_mailbox_"),
        ($User.DisplayName -match "(?i)shared|mailbox" -and -not $User.AssignedLicenses)
        # Odstránená kontrola MailboxSettings kôli chybe
    )
    
    return ($indicators -contains $true)
}

# --- Format DateTime Helper ---
function Format-DateTime {
    param($DateTime)
    
    if ($DateTime) {
        return $DateTime.ToString("yyyy-MM-dd HH:mm")
    }
    return "Never"
}

# --- Test Graph Connection ---
function Test-GraphConnection {
    try {
        $context = Get-MgContext
        return ($context -and $context.TenantId)
    }
    catch {
        return $false
    }
}

# --- Safe Division Helper ---
function Get-SuccessRate {
    param($Exported, $Total)
    
    if ($Total -eq 0) {
        return 0
    }
    return [math]::Round(($Exported / $Total) * 100, 1)
}
#endregion

#region Data Collection
# --- Load users ---
Write-Log -Message "Loading Entra ID users (Batch Size: $BatchSize)..." -Level "INFO" -LogPath $LogPath

try {
    # Skúsime najprv základné vlastnosti
    Write-Log -Message "Attempting to load users with basic properties..." -Level "INFO" -LogPath $LogPath
    $users = Invoke-GraphWithRetry -ScriptBlock {
        Get-MgUser -All -PageSize $BatchSize -ErrorAction Stop
    } -Operation "User Loading Basic"
    
    Write-Log -Message "Successfully loaded $($users.Count) users from Entra ID with basic properties" -Level "SUCCESS" -LogPath $LogPath
    Write-Host "Loaded $($users.Count) users from Entra ID" -ForegroundColor Green
    
    # Ak sme načítali používateľov, skúsime získať viac vlastností
    if ($users.Count -gt 0) {
        Write-Log -Message "Loading extended properties for users..." -Level "INFO" -LogPath $LogPath
        $userDetails = @()
        $userCounter = 0
        
        foreach ($user in $users) {
            $userCounter++
            try {
                $userDetail = Invoke-GraphWithRetry -ScriptBlock {
                    Get-MgUser -UserId $user.Id -Property "Id,DisplayName,UserPrincipalName,AccountEnabled,LastPasswordChangeDateTime,AssignedLicenses,CreatedDateTime,UserType,Mail,Department,JobTitle,OfficeLocation" -ErrorAction Stop
                } -Operation "User Detail Loading" -MaxRetries 2
                
                $userDetails += $userDetail
                
                if ($userCounter % 50 -eq 0) {
                    Write-Progress -Activity "Loading User Details" -Status "Processed $userCounter of $($users.Count) users" -PercentComplete (($userCounter / $users.Count) * 100)
                }
            }
            catch {
                Write-Log -Message "Failed to load details for user $($user.UserPrincipalName): $($_.Exception.Message)" -Level "WARNING" -LogPath $LogPath
                # Pridáme aspoň základné informácie
                $userDetails += $user
            }
        }
        Write-Progress -Activity "Loading User Details" -Completed
        $users = $userDetails
        Write-Log -Message "Successfully loaded extended properties for $($users.Count) users" -Level "SUCCESS" -LogPath $LogPath
    }
}
catch {
    Write-Log -Message "Failed to load users: $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
    Write-Host "Error loading users: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Ak sme nenačítali žiadnych používateľov, skončíme
if ($users.Count -eq 0) {
    Write-Log -Message "No users found in the tenant. Please check if the application has proper permissions." -Level "ERROR" -LogPath $LogPath
    Write-Host "ERROR: No users found in the tenant." -ForegroundColor Red
    Write-Host "Please verify that the App Registration has 'User.Read.All' permission." -ForegroundColor Yellow
    exit 1
}

# --- Load sign-ins ---
Write-Log -Message "Loading sign-in data (last 30 days)..." -Level "INFO" -LogPath $LogPath
$signInMap = @{}
$dateLimit = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
    $signIns = Invoke-GraphWithRetry -ScriptBlock {
        Get-MgAuditLogSignIn -Filter "createdDateTime ge $dateLimit" -All -PageSize $BatchSize -ErrorAction Stop
    } -Operation "Sign-in Data Loading"
    
    foreach ($entry in $signIns) {
        if ($entry.UserId -and $entry.CreatedDateTime) {
            $id = $entry.UserId
            if (-not $signInMap[$id] -or $entry.CreatedDateTime -gt $signInMap[$id]) {
                $signInMap[$id] = $entry.CreatedDateTime
            }
        }
    }
    Write-Log -Message "Mapped $($signInMap.Count) users with recent sign-in activity" -Level "SUCCESS" -LogPath $LogPath
    Write-Host "Found $($signInMap.Count) users with recent sign-in activity" -ForegroundColor Green
}
catch {
    Write-Log -Message "Could not load sign-in data: $($_.Exception.Message)" -Level "WARNING" -LogPath $LogPath
    Write-Host "Warning: Could not load sign-in data" -ForegroundColor Yellow
}
#endregion

#region Data Processing
# --- Filter shared mailboxes with progress tracking ---
Write-Log -Message "Processing users and filtering data..." -Level "INFO" -LogPath $LogPath

$skippedShared = 0
$result = [System.Collections.Generic.List[PSObject]]::new()
$counter = 0
$totalUsers = $users.Count

Write-Host "`nProcessing Users:" -ForegroundColor Cyan
Write-Host ("-" * 50) -ForegroundColor Cyan

foreach ($u in $users) {
    $counter++
    $percentComplete = [math]::Round(($counter / $totalUsers) * 100, 2)
    
    # Progress display
    if ($counter % 20 -eq 0 -or $counter -eq $totalUsers) {
        Write-Progress -Activity "Processing Users" -Status "User $counter of $totalUsers ($percentComplete%)" -PercentComplete $percentComplete
    }

    try {
        # Shared mailbox exclusion
        if ($ExcludeSharedMailboxes -and (Test-IsSharedMailbox -User $u)) {
            $skippedShared++
            continue
        }

        # User data processing
        $enabled = if ($u.AccountEnabled) { "Yes" } else { "No" }
        $pwdChanged = Format-DateTime -DateTime $u.LastPasswordChangeDateTime
        $signIn = Format-DateTime -DateTime $signInMap[$u.Id]
        $created = Format-DateTime -DateTime $u.CreatedDateTime
        $userType = if ($u.UserType) { $u.UserType } else { "Member" }
        $licensed = if ($u.AssignedLicenses.Count -gt 0) { "Yes" } else { "No" }
        $email = if ($u.Mail) { $u.Mail } else { $u.UserPrincipalName }

        $result.Add([PSCustomObject]@{
                DisplayName        = $u.DisplayName ?? "N/A"
                UPN                = $u.UserPrincipalName ?? "N/A"
                Email              = $email
                UserType           = $userType
                Enabled            = $enabled
                Licensed           = $licensed
                CreatedDateTime    = $created
                LastPasswordChange = $pwdChanged
                LastSignIn         = $signIn
                Department         = $u.Department ?? "N/A"
                JobTitle           = $u.JobTitle ?? "N/A"
                OfficeLocation     = $u.OfficeLocation ?? "N/A"
            })
    }
    catch {
        Write-Log -Message "Error processing user $($u.UserPrincipalName): $($_.Exception.Message)" -Level "WARNING" -LogPath $LogPath
        continue
    }
}

# Clear progress bar
Write-Progress -Activity "Processing Users" -Completed
Write-Host "`nProcessing completed: $($result.Count) users ready for export" -ForegroundColor Green
Write-Log -Message "User processing completed: $($result.Count) users exported, $skippedShared shared mailboxes skipped" -Level "INFO" -LogPath $LogPath
#endregion

#region Export Results
# --- Export CSV ---
Write-Log -Message "Exporting data to CSV file..." -Level "INFO" -LogPath $LogPath

try {
    if ($result.Count -gt 0) {
        $result | Sort-Object DisplayName | Export-Csv -Path $ExportPath -Encoding UTF8 -NoTypeInformation
        Write-Log -Message "Data successfully exported to: $ExportPath" -Level "SUCCESS" -LogPath $LogPath
        
        # Display file info
        $fileInfo = Get-Item $ExportPath
        Write-Host "`nExport File Information:" -ForegroundColor Cyan
        Write-Host "-" * 50 -ForegroundColor Cyan
        Write-Host "Location: $($fileInfo.FullName)" -ForegroundColor White
        Write-Host "Size: $([math]::Round($fileInfo.Length/1KB, 2)) KB" -ForegroundColor White
        Write-Host "Users Exported: $($result.Count)" -ForegroundColor White
    }
    else {
        Write-Log -Message "No data to export. Creating empty CSV file." -Level "WARNING" -LogPath $LogPath
        # Create empty CSV with headers
        $emptyData = [PSCustomObject]@{
            DisplayName        = "No users found"
            UPN                = "N/A"
            Email              = "N/A"
            UserType           = "N/A"
            Enabled            = "N/A"
            Licensed           = "N/A"
            CreatedDateTime    = "N/A"
            LastPasswordChange = "N/A"
            LastSignIn         = "N/A"
            Department         = "N/A"
            JobTitle           = "N/A"
            OfficeLocation     = "N/A"
        }
        @($emptyData) | Export-Csv -Path $ExportPath -Encoding UTF8 -NoTypeInformation
        Write-Host "No users to export. Empty CSV file created." -ForegroundColor Yellow
    }
}
catch {
    Write-Log -Message "Failed to export CSV: $($_.Exception.Message)" -Level "ERROR" -LogPath $LogPath
    exit 1
}
#endregion

#region Email Notification
if (-not $SkipEmail -and $result.Count -gt 0) {
    Write-Log -Message "Preparing to send email notification with CSV attachment..." -Level "INFO" -LogPath $LogPath
    
    try {
        if (Test-GraphConnection) {
            Write-Log -Message "Graph connection verified, preparing email..." -Level "INFO" -LogPath $LogPath
            
            # Overenie existencie súboru
            if (-not (Test-Path $ExportPath)) {
                Write-Log -Message "ERROR: CSV file not found: $ExportPath" -Level "ERROR" -LogPath $LogPath
                exit 1
            }

            # Načítanie súboru a informácií
            $fileInfo = Get-Item $ExportPath
            $fileSize = [math]::Round($fileInfo.Length / 1KB, 2)
            Write-Log -Message "CSV file found: $($fileInfo.Name) ($fileSize KB)" -Level "INFO" -LogPath $LogPath

            # Načítanie súboru ako Base64
            $csvBytes = [System.IO.File]::ReadAllBytes($ExportPath)
            $csvBase64 = [System.Convert]::ToBase64String($csvBytes)
            
            Write-Log -Message "CSV file encoded to Base64 ($($csvBytes.Length) bytes)" -Level "INFO" -LogPath $LogPath

            # Príjemca a správa
            $recipient = "findrik@tauris.sk"
            $sender = "servisit@tauris.sk"
            $subject = "Entra ID Users Report - $timestamp"
            
            $bodyText = @"
Hello,

Please find the Entra ID users report attached.

Report Details:
- Generated: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
- Total Users: $($users.Count)
- Exported Users: $($result.Count)
- Shared Mailboxes Skipped: $skippedShared
- File: $($fileInfo.Name)

This is an automated report generated by the Entra Users Export Script v3.5.

Best regards,
IT Automation System
"@

            Write-Log -Message "Creating email message..." -Level "INFO" -LogPath $LogPath
            
            $emailMessage = @{
                Message         = @{
                    Subject      = $subject
                    Body         = @{
                        ContentType = "Text"
                        Content     = $bodyText
                    }
                    ToRecipients = @(
                        @{ 
                            EmailAddress = @{ 
                                Address = $recipient 
                            } 
                        }
                    )
                    Attachments  = @(
                        @{
                            "@odata.type" = "#microsoft.graph.fileAttachment"
                            Name          = "EntraUsers_$timestamp.csv"
                            ContentType   = "text/csv"
                            ContentBytes  = $csvBase64
                        }
                    )
                }
                SaveToSentItems = $true
            }

            Write-Log -Message "Sending email via Microsoft Graph..." -Level "INFO" -LogPath $LogPath
            
            # Odoslanie emailu
            Send-MgUserMail -UserId $sender -BodyParameter $emailMessage -ErrorAction Stop
            
            Write-Log -Message "Email successfully sent to $recipient with CSV attachment" -Level "SUCCESS" -LogPath $LogPath
            Write-Host "Email notification sent to: $recipient" -ForegroundColor Green
        }
        else {
            Write-Log -Message "WARNING: Not connected to Microsoft Graph, skipping email notification" -Level "WARNING" -LogPath $LogPath
            Write-Host "Warning: Could not send email notification - no Graph connection" -ForegroundColor Yellow
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Log -Message "ERROR: Failed to send email: $errorMsg" -Level "ERROR" -LogPath $LogPath
        Write-Host "Error sending email: $errorMsg" -ForegroundColor Red
        
        # Detailnejšia chybová analýza
        if ($errorMsg -like "*Insufficient privileges*" -or $errorMsg -like "*Authorization_RequestDenied*") {
            Write-Log -Message "Please ensure the service principal has 'Mail.Send' application permission" -Level "ERROR" -LogPath $LogPath
            Write-Host "Required permission: Mail.Send (application permission)" -ForegroundColor Yellow
        }
        elseif ($errorMsg -like "*User not found*") {
            Write-Log -Message "Sender user '$sender' not found or no mailbox available" -Level "ERROR" -LogPath $LogPath
        }
    }
}
else {
    if ($SkipEmail) {
        Write-Log -Message "Email notification skipped (SkipEmail parameter used)" -Level "INFO" -LogPath $LogPath
    }
    else {
        Write-Log -Message "Email notification skipped (no users to export)" -Level "INFO" -LogPath $LogPath
    }
}
#endregion

#region Cleanup and Summary
# --- Disconnect Graph ---
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Log -Message "Disconnected from Microsoft Graph" -Level "INFO" -LogPath $LogPath
}
catch {
    Write-Log -Message "Warning: Could not properly disconnect from Graph" -Level "WARNING" -LogPath $LogPath
}

# --- Enhanced Summary Report ---
$EndTime = Get-Date
$Duration = $EndTime - $StartTime

$successRate = Get-SuccessRate -Exported $result.Count -Total $users.Count

$summary = @"
=== EXPORT SUMMARY ===
Start Time:    $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
End Time:      $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))
Duration:      $($Duration.ToString('hh\:mm\:ss'))
Total Users:   $($users.Count) users processed
Exported:      $($result.Count) users in export
Skipped:       $skippedShared shared mailboxes
Success Rate:  $successRate% successful exports
Export File:   $ExportPath
"@

Write-Log -Message $summary -Level "INFO" -LogPath $LogPath

# Console summary with formatting
Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "EXPORT SUMMARY" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Start Time:    $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "End Time:      $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "Duration:      $($Duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "Total Users:   $($users.Count) users processed" -ForegroundColor White
Write-Host "Exported:      $($result.Count) users in export" -ForegroundColor Green
Write-Host "Skipped:       $skippedShared shared mailboxes" -ForegroundColor Yellow

# Safe success rate display
$successColor = if ($users.Count -eq 0) { "Yellow" } elseif ($successRate -gt 95) { "Green" } else { "Yellow" }
Write-Host "Success Rate:  $successRate% successful exports" -ForegroundColor $successColor

Write-Host "Export File:   $ExportPath" -ForegroundColor Cyan
Write-Host "Log File:      $LogPath" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

# Final log entry
Add-Content -Path $LogPath -Value $separator
Add-Content -Path $LogPath -Value "SCRIPT COMPLETED: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
Add-Content -Path $LogPath -Value $separator

Write-Log -Message "Script execution completed successfully" -Level "SUCCESS" -LogPath $LogPath

# Display completion message
Write-Host "`nScript execution completed successfully!" -ForegroundColor Green
Write-Host "Check the log file for detailed information: $LogPath" -ForegroundColor Gray
Write-Host "`n"
#endregion