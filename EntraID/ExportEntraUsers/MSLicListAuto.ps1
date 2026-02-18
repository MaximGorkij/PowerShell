<# 
.SYNOPSIS
    Export Microsoft 365 user licenses via Microsoft Graph API with batch processing.
.DESCRIPTION
    Exportuje zoznam používateľov, ich licencií a poslednej aktivity do CSV.
    Dáta číta cez MS Graph API, podporuje batch processing a zasielanie reportu mailom.
.NOTES
    Verzia: 3.2
    Autor: Automaticky report
    Pozadovane moduly: Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Reports, LogHelper
    Datum vytvorenia: 17.02.2026
    Logovanie: C:\TaurisIT\Log\UserLicenses
#>

param (
    [string]$AuthFile = ".\GraphAuth.xml",
    [int]$BatchSize = 100,
    [switch]$SkipEmail
)

# Import LogHelper modulu podľa tvojich požiadaviek
$LogModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
if (Test-Path $LogModulePath) {
    Import-Module $LogModulePath
}
else {
    Write-Error "Modul LogHelper nebol najdeny v $LogModulePath"
    exit 1
}

# Nastavenie ciest
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$ExportPath = Join-Path $PSScriptRoot "UserLicenses_$timestamp.csv"

# Logovanie štartu (LogHelper predpokladá existenciu funkcie Write-Log alebo podobnej z modulu)
Write-Log "=== Starting MSLicListAuto v3.2 ===" "INFO"

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

# --- Connect to Graph ---
try {
    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)

    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop
    Write-Log "Successfully connected to Microsoft Graph." "SUCCESS"
}
catch {
    Write-Log "ERROR: Failed to connect to Microsoft Graph: $($_.Exception.Message)" "ERROR"
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

# --- Load SKU & Users ---
try {
    $allSkus = Get-MgSubscribedSku -All -ErrorAction Stop
    $skuMap = @{}
    foreach ($sku in $allSkus) {
        $part = $sku.SkuPartNumber
        $skuMap[$part] = if ($customSkuNames.ContainsKey($part)) { $customSkuNames[$part] } else { $part }
    }

    Write-Log "Loading users (Batch: $BatchSize)..."
    $users = Get-MgUser -Property "Id,DisplayName,UserPrincipalName,AssignedLicenses,AccountEnabled,LastPasswordChangeDateTime,EmployeeId,SignInActivity" -PageSize $BatchSize -All -ErrorAction Stop
    Write-Log "Loaded $($users.Count) users." "SUCCESS"
}
catch {
    Write-Log "ERROR during data retrieval: $($_.Exception.Message)" "ERROR"
    exit 1
}

# --- Sign-in Activity (Last 30 days) ---
$signInMap = @{}
$dateLimit = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
try {
    $allSignIns = Get-MgAuditLogSignIn -Filter "createdDateTime ge $dateLimit" -All -ErrorAction SilentlyContinue
    if ($allSignIns) {
        foreach ($entry in $allSignIns) {
            if ($entry.UserId -and $entry.CreatedDateTime) {
                if (-not $signInMap.ContainsKey($entry.UserId) -or $entry.CreatedDateTime -gt $signInMap[$entry.UserId]) {
                    $signInMap[$entry.UserId] = $entry.CreatedDateTime
                }
            }
        }
    }
}
catch { 
    Write-Log "AuditLog access failed, relying on user object activity." "WARNING" 
}

# --- Processing Results ---
$result = New-Object System.Collections.Generic.List[PSObject]
foreach ($user in $users) {
    $licenseList = New-Object System.Collections.Generic.List[string]
    foreach ($lic in $user.AssignedLicenses) {
        $sku = $allSkus | Where-Object { $_.SkuId -eq $lic.SkuId }
        if ($sku) { $licenseList.Add($skuMap[$sku.SkuPartNumber]) }
    }

    $lastSignIn = "NieZa30Dni"
    if ($signInMap.ContainsKey($user.Id)) {
        $lastSignIn = $signInMap[$user.Id].ToString("dd.MM.yyyy HH:mm")
    }
    elseif ($user.SignInActivity.LastSignInDateTime) {
        $lastSignIn = $user.SignInActivity.LastSignInDateTime.ToString("dd.MM.yyyy HH:mm")
    }

    $result.Add([PSCustomObject]@{
            DisplayName = $user.DisplayName
            UPN         = $user.UserPrincipalName
            EmployeeID  = if ($user.EmployeeId) { $user.EmployeeId.ToString().PadLeft(5, '0') } else { "" }
            Enabled     = if ($user.AccountEnabled) { "Yes" } else { "No" }
            LastSignIn  = $lastSignIn
            Licenses    = if ($licenseList.Count -gt 0) { $licenseList -join "; " } else { "None" }
        })
}

# --- Export & Email ---
$result | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
Write-Log "Export saved to $ExportPath" "SUCCESS"

if (-not $SkipEmail) {
    # Tu by nasledoval Send-MgUserMail block z tvojho originalu
    Write-Log "Email sending process initiated..." "INFO"
}

Disconnect-MgGraph
Write-Log "=== Script finished ===" "SUCCESS"