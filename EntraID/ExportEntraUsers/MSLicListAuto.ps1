<#
.SYNOPSIS
Export Microsoft 365 licencie používateľov cez Microsoft Graph API (App Registration).
Credentials sa načítajú z GraphAuth.xml.

.VERZIA
2.7
#>

param (
    [string]$AuthFile = ".\GraphAuth.xml",
    [string]$ExportPath = ".\UserLicenses.csv",
    [string]$LogPath = ".\UserLicenses.log"
)

# Funkcia pre zápis do logu a konzoly
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    
    # Zápis do konzoly
    Write-Host $logEntry -ForegroundColor $Color
    
    # Zápis do log súboru
    Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8
}

# Vytvorenie nového log súboru
if (Test-Path $LogPath) {
    Remove-Item $LogPath -Force
}
New-Item -Path $LogPath -ItemType File -Force | Out-Null

Write-Log "=== Spúšťam skript MSLicListAuto v2.7 ===" -Level "INFO" -Color "Cyan"

# --- Načítanie credentials z XML ---
if (-not (Test-Path $AuthFile)) {
    Write-Log "❌ CHYBA: Súbor $AuthFile neexistuje. Vytvor GraphAuth.xml s TenantId, ClientId, ClientSecret." -Level "ERROR" -Color "Red"
    exit 1
}

[xml]$auth = Get-Content $AuthFile
$TenantId    = $auth.GraphAuth.TenantId
$ClientId    = $auth.GraphAuth.ClientId
$ClientSecret = $auth.GraphAuth.ClientSecret

if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Log "❌ CHYBA: V GraphAuth.xml chýba TenantId, ClientId alebo ClientSecret." -Level "ERROR" -Color "Red"
    exit 1
}

# --- Pripojenie k Graph pomocou správnej metódy ---
try {
    # Disconnect first if already connected
    if (Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Odpojené existujúce pripojenie Graph." -Level "INFO" -Color "Yellow"
    }

    # Import required module
    Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop
    Write-Log "Naimportovaný modul Microsoft.Graph.Authentication" -Level "INFO" -Color "Green"
    
    # Connect using application credentials
    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
    
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop

    Write-Log "✅ Úspešne pripojené ku Microsoft Graph." -Level "INFO" -Color "Green"
}
catch {
    Write-Log "❌ CHYBA: Nepodarilo sa pripojiť k Microsoft Graph. $_" -Level "ERROR" -Color "Red"
    exit 1
}

# --- Mapovanie SKU -> Friendly názov ---
$skuMap = @{
    "ENTERPRISEPACK"     = "Office 365 E3"
    "EMS"                = "Enterprise Mobility + Security"
    "FLOW_FREE"          = "Power Automate Free"
    "POWER_BI_PRO"       = "Power BI Pro"
    "SPE_E5"             = "Microsoft 365 E5"
    "SPE_E3"             = "Microsoft 365 E3"
    "IDENTITY_THREAT_PROTECTION" = "Microsoft 365 Threat Protection"
    "STANDARDPACK"       = "Office 365 E1"
    "STANDARDWOFFPACK"   = "Office 365 F3"
    "VISIO_PLAN1"        = "Visio Plan 1"
    "VISIO_PLAN2"        = "Visio Plan 2"
    "PROJECT_PLAN1"      = "Project Plan 1"
    "PROJECT_PLAN3"      = "Project Plan 3"
    "PROJECT_PLAN5"      = "Project Plan 5"
    "DEVELOPERPACK"      = "Office 365 Developer"
    "EXCHANGESTANDARD"   = "Exchange Online Plan 1"
    "EXCHANGEENTERPRISE" = "Exchange Online Plan 2"
}

# --- Získanie používateľov a licencií ---
Write-Log "Načítavam zoznam používateľov a licencií..." -Level "INFO" -Color "Cyan"

try {
    Import-Module Microsoft.Graph.Users -Force -ErrorAction Stop
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force -ErrorAction Stop
    Import-Module Microsoft.Graph.Reports -Force -ErrorAction Stop
    
    Write-Log "Naimportované požadované moduly Graph" -Level "INFO" -Color "Green"
    
    # Get all available SKUs for mapping
    Write-Log "Získavam zoznam dostupných licencií..." -Level "INFO" -Color "Cyan"
    $allSkus = Get-MgSubscribedSku -All -ErrorAction Stop
    Write-Log "Načítaných $($allSkus.Count) typov licencií" -Level "INFO" -Color "Green"
    
    # Get users with license information and additional properties
    $selectProperties = @(
        "Id",
        "DisplayName",
        "UserPrincipalName",
        "AccountEnabled",
        "LastPasswordChangeDateTime",
        "AssignedLicenses"
    )
    
    Write-Log "Získavam zoznam používateľov..." -Level "INFO" -Color "Cyan"
    $users = Get-MgUser -All -Property $selectProperties -ErrorAction Stop
    Write-Log "Načítaných $($users.Count) používateľov" -Level "INFO" -Color "Green"
    
    # Get sign-in activity for users
    $signInActivities = @{}
    
    Write-Log "Načítavam informácie o poslednom prihlásení..." -Level "INFO" -Color "Cyan"
    
    # Process users in batches to avoid throttling
    $batchSize = 100
    $userCount = $users.Count
    $processed = 0
    
    foreach ($user in $users) {
        $processed++
        if ($processed % 50 -eq 0) {
            Write-Log "Spracovaných $processed z $userCount používateľov..." -Level "INFO" -Color "Cyan"
        }
        
        try {
            # Get last sign-in for this user
            $signIns = Get-MgAuditLogSignIn -Filter "userId eq '$($user.Id)'" -Top 1 -All -ErrorAction SilentlyContinue
            if ($signIns -and $signIns.Count -gt 0) {
                $signInActivities[$user.Id] = $signIns[0].CreatedDateTime
            }
        }
        catch {
            # Skip if we can't get sign-in data
            Write-Log "Nepodarilo sa získať údaje o prihlásení pre používateľa $($user.UserPrincipalName)" -Level "WARNING" -Color "Yellow"
        }
    }
    
    Write-Log "Údaje o prihlásení načítané pre $($signInActivities.Count) používateľov" -Level "INFO" -Color "Green"

    $result = @()
    $userCount = $users.Count
    $processed = 0
    
    Write-Log "Spracúvam údaje používateľov..." -Level "INFO" -Color "Cyan"
    
    foreach ($user in $users) {
        $processed++
        if ($processed % 50 -eq 0) {
            Write-Log "Spracovaných $processed z $userCount používateľov..." -Level "INFO" -Color "Cyan"
        }
        
        $licenses = @()
        $hasTargetLicense = $false
        
        foreach ($lic in $user.AssignedLicenses) {
            $skuId = $lic.SkuId
            $sku = $allSkus | Where-Object { $_.SkuId -eq $skuId }
            
            if ($sku) {
                if ($skuMap.ContainsKey($sku.SkuPartNumber)) {
                    $licenseName = $skuMap[$sku.SkuPartNumber]
                } else {
                    $licenseName = $sku.SkuPartNumber
                }
                
                $licenses += $licenseName
                
                # Check if user has target licenses
                if ($sku.SkuPartNumber -in @("SPE_E3", "IDENTITY_THREAT_PROTECTION")) {
                    $hasTargetLicense = $true
                }
            }
        }

        # Get last sign-in time
        $lastSignIn = if ($signInActivities.ContainsKey($user.Id)) { 
            $signInActivities[$user.Id] 
        } else { 
            "Nikdy" 
        }

        $result += [PSCustomObject]@{
            DisplayName           = $user.DisplayName
            UPN                   = $user.UserPrincipalName
            Enabled               = if ($user.AccountEnabled) { "Áno" } else { "Nie" }
            LastPasswordChange    = if ($user.LastPasswordChangeDateTime) { $user.LastPasswordChangeDateTime.ToString("yyyy-MM-dd HH:mm") } else { "Nikdy" }
            LastSignIn            = if ($lastSignIn -ne "Nikdy") { $lastSignIn.ToString("yyyy-MM-dd HH:mm") } else { $lastSignIn }
            Licencie              = if ($licenses.Count -gt 0) { ($licenses -join "; ") } else { "Žiadne" }
            MaSPEE3               = if ($hasTargetLicense) { "Áno" } else { "Nie" }
        }
    }

    # --- Export ---
    Write-Log "Exportujem údaje do CSV: $ExportPath" -Level "INFO" -Color "Cyan"
    $result | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Log "✅ Export dokončený: $ExportPath" -Level "INFO" -Color "Green"
    Write-Log "Počet exportovaných používateľov: $($result.Count)" -Level "INFO" -Color "Green"
    
    # Show summary
    $enabledUsers = $result | Where-Object { $_.Enabled -eq "Áno" }
    $withLicenses = $result | Where-Object { $_.Licencie -ne "Žiadne" }
    $withSPEE3 = $result | Where-Object { $_.MaSPEE3 -eq "Áno" }
    $neverSignedIn = $result | Where-Object { $_.LastSignIn -eq "Nikdy" }
    
    Write-Log "ŠTATISTIKA:" -Level "INFO" -Color "Cyan"
    Write-Log "  - Počet povolených používateľov: $($enabledUsers.Count)" -Level "INFO" -Color "Cyan"
    Write-Log "  - Počet používateľov s licenciami: $($withLicenses.Count)" -Level "INFO" -Color "Cyan"
    Write-Log "  - Počet používateľov s SPE_E3/IDENTITY_THREAT_PROTECTION: $($withSPEE3.Count)" -Level "INFO" -Color "Cyan"
    Write-Log "  - Počet používateľov, ktorí sa nikdy neprihlásili: $($neverSignedIn.Count)" -Level "INFO" -Color "Cyan"
    
    # Log some examples of users with target licenses
    if ($withSPEE3.Count -gt 0) {
        Write-Log "PRÍKLADY používateľov s SPE_E3/IDENTITY_THREAT_PROTECTION:" -Level "INFO" -Color "Cyan"
        $withSPEE3 | Select-Object -First 5 | ForEach-Object {
            Write-Log "  - $($_.DisplayName) ($($_.UPN))" -Level "INFO" -Color "Cyan"
        }
    }
}
catch {
    Write-Log "❌ CHYBA pri získavaní dát: $_" -Level "ERROR" -Color "Red"
    Write-Log "Zásobník volania: $($_.ScriptStackTrace)" -Level "ERROR" -Color "Red"
}
finally {
    # --- Odhlásenie ---
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Odpojené od Graph." -Level "INFO" -Color "DarkGray"
    }
    catch {
        Write-Log "Varovanie: Nepodarilo sa odpojiť od Graph: $_" -Level "WARNING" -Color "Yellow"
    }
    
    Write-Log "=== Skript ukončený ===" -Level "INFO" -Color "Cyan"
}