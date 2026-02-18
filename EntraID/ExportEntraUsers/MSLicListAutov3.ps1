<#
.SYNOPSIS
Export Microsoft 365 licencie používateľov cez Microsoft Graph API (App Registration).
Credentials sa načítajú z GraphAuth.xml.

.VERZIA
2.5
#>

param (
    [string]$AuthFile = ".\GraphAuth.xml",
    [string]$ExportPath = ".\UserLicenses.csv"
)

Write-Host "=== Spúšťam skript MSLicListAuto v2.5 ===" -ForegroundColor Cyan

# --- Načítanie credentials z XML ---
if (-not (Test-Path $AuthFile)) {
    Write-Error "❌ CHYBA: Súbor $AuthFile neexistuje. Vytvor GraphAuth.xml s TenantId, ClientId, ClientSecret."
    exit 1
}

[xml]$auth = Get-Content $AuthFile
$TenantId    = $auth.GraphAuth.TenantId
$ClientId    = $auth.GraphAuth.ClientId
$ClientSecret = $auth.GraphAuth.ClientSecret

if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "❌ CHYBA: V GraphAuth.xml chýba TenantId, ClientId alebo ClientSecret."
    exit 1
}

# --- Pripojenie k Graph pomocou správnej metódy ---
try {
    # Disconnect first if already connected
    if (Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }

    # Import required module
    Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop
    
    # Connect using application credentials
    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
    
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop

    Write-Host "✅ Úspešne pripojené ku Microsoft Graph." -ForegroundColor Green
}
catch {
    Write-Error "❌ CHYBA: Nepodarilo sa pripojiť k Microsoft Graph. $_"
    exit 1
}

# --- Mapovanie SKU -> Friendly názov ---
$skuMap = @{
    "ENTERPRISEPACK"     = "Office 365 E3"
    "EMS"                = "Enterprise Mobility + Security"
    "FLOW_FREE"          = "Power Automate Free"
    "POWER_BI_PRO"       = "Power BI Pro"
    "SPE_E5"             = "Microsoft 365 E5"
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
Write-Host "Načítavam zoznam používateľov a licencií..." -ForegroundColor Cyan

try {
    Import-Module Microsoft.Graph.Users -Force -ErrorAction Stop
    
    # Get users with license information
    $users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,AssignedLicenses" -ErrorAction Stop
    
    # Get all available SKUs for mapping
    Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force -ErrorAction Stop
    $allSkus = Get-MgSubscribedSku -All -ErrorAction Stop
    
    $result = foreach ($user in $users) {
        $licenses = @()
        
        foreach ($lic in $user.AssignedLicenses) {
            $skuId = $lic.SkuId
            $sku = $allSkus | Where-Object { $_.SkuId -eq $skuId }
            
            if ($sku) {
                if ($skuMap.ContainsKey($sku.SkuPartNumber)) {
                    $licenses += $skuMap[$sku.SkuPartNumber]
                } else {
                    $licenses += $sku.SkuPartNumber
                }
            }
        }

        [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UPN         = $user.UserPrincipalName
            Licencie    = if ($licenses.Count -gt 0) { ($licenses -join "; ") } else { "Žiadne" }
        }
    }

    # --- Export ---
    $result | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "✅ Export dokončený: $ExportPath" -ForegroundColor Green
    Write-Host "Počet exportovaných používateľov: $($result.Count)" -ForegroundColor Green
}
catch {
    Write-Error "❌ CHYBA pri získavaní dát: $_"
}
finally {
    # --- Odhlásenie ---
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Odpojené od Graph." -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Varovanie: Nepodarilo sa odpojiť od Graph: $_"
    }
}