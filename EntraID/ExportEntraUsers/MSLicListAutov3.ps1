<#
.SYNOPSIS
Export Microsoft 365 user licenses via Microsoft Graph API with batch processing.
Resilient to missing data. Credentials loaded from GraphAuth.xml.

.VERSION
3.0
#>

param (
    [string]$AuthFile = ".\GraphAuth.xml",
    [int]$BatchSize = 100,
    [switch]$SkipEmail
)

# Timestamp and paths
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$ExportPath = Join-Path $PSScriptRoot "UserLicenses_$timestamp.csv"
$LogPath = Join-Path $PSScriptRoot "UserLicensesLog.log"  # Fixed log filename

# Required modules
$requiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Identity.DirectoryManagement", 
    "Microsoft.Graph.Users",
    "Microsoft.Graph.Reports"
)

# Function for logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$time [$Level] $Message"
    
    # Color coding for console output
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARNING" { "Yellow" }
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        default   { "Gray" }
    }
    
    Write-Host $entry -ForegroundColor $color
    
    # Append to log file (creates file if it doesn't exist)
    try {
        Add-Content -Path $LogPath -Value $entry -ErrorAction Stop
    }
    catch {
        Write-Host "ERROR: Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Test-GraphConnection {
    try {
        $context = Get-MgContext
        if ($context -and $context.TenantId -eq $TenantId) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Invoke-GraphWithRetry {
    param (
        [scriptblock]$ScriptBlock,
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
                Write-Log "Failed after $MaxRetries attempts: $($_.Exception.Message)" "ERROR"
                throw
            }
            
            Write-Log "Attempt $attempt failed. Retrying in $RetryDelay seconds..." "WARNING"
            Start-Sleep -Seconds $RetryDelay
        }
    }
}

# Add separator line to log file when script starts
try {
    $separator = "=" * 80
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "`n$separator"
    Add-Content -Path $LogPath -Value "SCRIPT STARTED: $startTime"
    Add-Content -Path $LogPath -Value $separator
}
catch {
    Write-Host "Warning: Could not write separator to log file" -ForegroundColor Yellow
}

Write-Log "=== Starting MSLicListAuto v3.0 ==="

# --- Load credentials ---
if (-not (Test-Path $AuthFile)) {
    Write-Log "ERROR: File $AuthFile does not exist." "ERROR"
    exit 1
}

try {
    [xml]$auth = Get-Content $AuthFile -ErrorAction Stop
    $TenantId = $auth.GraphAuth.TenantId.Trim()
    $ClientId = $auth.GraphAuth.ClientId.Trim()
    $ClientSecret = $auth.GraphAuth.ClientSecret.Trim()

    if ([string]::IsNullOrEmpty($TenantId) -or [string]::IsNullOrEmpty($ClientId) -or [string]::IsNullOrEmpty($ClientSecret)) {
        throw "Missing required values in XML file"
    }
}
catch {
    Write-Log "ERROR: Invalid XML file or missing values: $($_.Exception.Message)" "ERROR"
    exit 1
}

# --- Install required modules ---
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        try {
            Write-Log "Installing module $module..."
            Install-Module $module -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        }
        catch {
            Write-Log "ERROR: Failed to install module $module : $($_.Exception.Message)" "ERROR"
            exit 1
        }
    }
    Import-Module $module -Force -ErrorAction Stop
}

# --- Connect to Graph ---
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    
    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)

    # Connect using client secret credentials
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop
    Write-Log "Successfully connected to Microsoft Graph."
    
    # Verify we have the required permissions
    $context = Get-MgContext
    if ($context) {
        Write-Log "Connected to tenant: $($context.TenantId)"
    }
}
catch {
    Write-Log "ERROR: Failed to connect to Microsoft Graph: $($_.Exception.Message)" "ERROR"
    Write-Log "Please verify your App Registration in Azure Portal has the required API permissions:" "ERROR"
    Write-Log "- Application permissions: User.Read.All, Directory.Read.All, AuditLog.Read.All" "ERROR"
    if (-not $SkipEmail) {
        Write-Log "- Application permission for email: Mail.Send" "ERROR"
    }
    exit 1
}

# --- Custom SKU names ---
$customSkuNames = @{
    "SPE_E3"                     = "Microsoft 365 E3"
    "IDENTITY_THREAT_PROTECTION" = "Defender for Identity"
    "ENTERPRISEPACK"             = "Office 365 E3"
    "SPE_E5"                     = "Microsoft 365 E5"
    "STANDARDPACK"               = "Office 365 E1"
    "STANDARDWOFFPACK"           = "Office 365 F3"
    "SPE_F1"                     = "Microsoft 365 F1"
    "FLOW_FREE"                  = "Power Automate Free"
}

# --- Load SKU licenses ---
try {
    $allSkus = Invoke-GraphWithRetry -ScriptBlock {
        Get-MgSubscribedSku -All -ErrorAction Stop
    }
    Write-Log "Loaded SKU licenses: $($allSkus.Count)"
}
catch {
    Write-Log "ERROR: Failed to load SKUs: $($_.Exception.Message)" "ERROR"
    exit 1
}

# --- Create SKU map ---
$skuMap = @{}
foreach ($sku in $allSkus) {
    $part = $sku.SkuPartNumber
    if (-not $skuMap.ContainsKey($part)) {
        $skuMap[$part] = if ($customSkuNames.ContainsKey($part)) { 
            $customSkuNames[$part] 
        } else { 
            $part
        }
    }
}
Write-Log "Created SKU map with $($skuMap.Count) entries"

# --- Load users in batches ---
Write-Log "Loading users in batches of $BatchSize..."
try {
    $users = Invoke-GraphWithRetry -ScriptBlock {
        Get-MgUser -Property "Id,DisplayName,UserPrincipalName,AssignedLicenses,AccountEnabled,LastPasswordChangeDateTime" `
                  -PageSize $BatchSize -All -ErrorAction Stop
    }
    Write-Log "Loaded users: $($users.Count)"
}
catch {
    Write-Log "ERROR: Failed to load users: $($_.Exception.Message)" "ERROR"
    exit 1
}

# --- Load sign-ins for last 90 days ---
Write-Log "Loading sign-ins for the last 90 days..."
$signInMap = @{}
$dateLimit = (Get-Date).AddDays(-90).ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
    $allSignIns = Invoke-GraphWithRetry -ScriptBlock {
        Get-MgAuditLogSignIn -Filter "createdDateTime ge $dateLimit" -All -ErrorAction Stop
    }
    Write-Log "Loaded sign-ins: $($allSignIns.Count)"

    foreach ($entry in $allSignIns) {
        if ($entry.UserId -and $entry.CreatedDateTime) {
            $userId = $entry.UserId
            $currentTime = $signInMap[$userId]
            if (-not $currentTime -or $entry.CreatedDateTime -gt $currentTime) {
                $signInMap[$userId] = $entry.CreatedDateTime
            }
        }
    }
    Write-Log "Mapped users with sign-ins: $($signInMap.Count)"
}
catch {
    Write-Log "WARNING: Failed to load sign-ins: $($_.Exception.Message)" "WARNING"
}

# --- Process results ---
$result = [System.Collections.Generic.List[PSObject]]::new()
$processed = 0

foreach ($user in $users) {
    $processed++
    if ($processed % 50 -eq 0) {
        Write-Log "Processed: $processed of $($users.Count)"
    }

    $licenseList = [System.Collections.Generic.List[string]]::new()
    if ($user.AssignedLicenses) {
        foreach ($lic in $user.AssignedLicenses) {
            $sku = $allSkus | Where-Object { $_.SkuId -eq $lic.SkuId }
            if ($sku) {
                $skuPart = $sku.SkuPartNumber
                $friendlyName = $skuMap[$skuPart]
                $licenseList.Add($friendlyName)
            }
        }
    }

    $enabled = if ($null -ne $user.AccountEnabled) {
        if ($user.AccountEnabled) { "Yes" } else { "No" }
    } else {
        "Unknown"
    }

    $lastPasswordChange = if ($user.LastPasswordChangeDateTime) {
        $user.LastPasswordChangeDateTime.ToString("yyyy-MM-dd HH:mm")
    } else {
        "Never"
    }

    $lastSignIn = if ($signInMap.ContainsKey($user.Id)) {
        $signInMap[$user.Id].ToString("yyyy-MM-dd HH:mm")
    } else {
        "Never"
    }

    $licenseStatus = if ($licenseList.Count -gt 0) { "Licensed" } else { "Unlicensed" }

    $result.Add([PSCustomObject]@{
        DisplayName        = $user.DisplayName
        UPN                = $user.UserPrincipalName
        Enabled            = $enabled
        LastPasswordChange = $lastPasswordChange
        LastSignIn         = $lastSignIn
        Licenses           = if ($licenseList.Count -gt 0) { ($licenseList -join "; ") } else { "None" }
        LicenseStatus      = $licenseStatus
    })
}

# --- Export ---
try {
    $result | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Log "Export completed: $ExportPath"
    Write-Log "Exported users: $($result.Count)"
}
catch {
    Write-Log "ERROR: Failed to export CSV: $($_.Exception.Message)" "ERROR"
    exit 1
}

# --- Statistics ---
$activeUsers = $result | Where-Object { $_.Enabled -eq "Yes" }
$licensedUsers = $result | Where-Object { $_.LicenseStatus -eq "Licensed" }
$neverSignedIn = $result | Where-Object { $_.LastSignIn -eq "Never" }

Write-Log "Statistics:"
Write-Log " - Active users: $($activeUsers.Count)"
Write-Log " - Licensed users: $($licensedUsers.Count)"
Write-Log " - Users never signed in: $($neverSignedIn.Count)"
Write-Log " - Unlicensed users: $($result.Count - $licensedUsers.Count)"

# --- Send email ---
if (-not $SkipEmail) {
    try {
        if (Test-GraphConnection) {
            $recipient = "findrik@tauris.sk"
            $subject = "Quarterly Report - M365 Licenses"
            $bodyText = "Hello, please find the quarterly user license report attached."

            $emailMessage = @{
                Message = @{
                    Subject = $subject
                    Body = @{
                        ContentType = "Text"
                        Content = $bodyText
                    }
                    ToRecipients = @(@{ EmailAddress = @{ Address = $recipient } })
                    Attachments = @(
                        @{
                            "@odata.type" = "#microsoft.graph.fileAttachment"
                            Name = "UserLicenses_$timestamp.csv"
                            ContentBytes = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($ExportPath))
                        }
                    )
                }
                SaveToSentItems = $true
            }

            Send-MgUserMail -UserId "servisit@tauris.sk" -BodyParameter $emailMessage
            Write-Log "Email sent successfully to $recipient"
        } else {
            Write-Log "WARNING: Not connected to Graph, skipping email send" "WARNING"
        }
    }
    catch {
        Write-Log "ERROR: Failed to send email: $($_.Exception.Message)" "ERROR"
    }
}

# --- Disconnect ---
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Write-Log "Disconnected from Graph."
}
catch {
    Write-Log "WARNING: Failed to disconnect from Graph: $($_.Exception.Message)" "WARNING"
}

Write-Log "=== Script completed successfully ==="

# Add separator line to log file when script ends
try {
    $endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $separator = "=" * 80
    Add-Content -Path $LogPath -Value $separator
    Add-Content -Path $LogPath -Value "SCRIPT COMPLETED: $endTime"
    Add-Content -Path $LogPath -Value $separator
}
catch {
    Write-Host "Warning: Could not write separator to log file" -ForegroundColor Yellow
}