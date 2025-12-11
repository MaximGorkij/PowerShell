#Requires -Version 5.1
<#
.SYNOPSIS
    Detection script pre Intune - kontroluje či je nastavená lokácia v Extension Attribute
.DESCRIPTION
    Kontroluje či je v Azure AD Extension Attribute 1 nastavená správna lokácia zariadenia
    Na základe IP adresy overí či lokácia sedí s IPLocationMap.json
.NOTES
    Autor: Marek Findrik / TaurisIT
    Dátum: 2025-01-10
    Typ: Detection Script
.OUTPUTS
    Exit 0 = Lokácia je správne nastavená (Compliant)
    Exit 1 = Lokácia nie je nastavená alebo je nesprávna (Non-Compliant, spustí remediation)
#>

#region Initialization
$ErrorActionPreference = 'Stop'
$LogDirectory = "C:\TaurisIT\Log\IPcheck"
$EventSource = "IntuneLocation-Detection"
$ScriptVersion = "1.0.0"

# Import LogHelper modul
try {
    Import-Module LogHelper -Force -ErrorAction Stop
    Initialize-LogSystem -LogDirectory $LogDirectory -EventSource $EventSource -RetentionDays 30
    Write-IntuneLog -Message "=== Detection Script Started (v$ScriptVersion) ===" -Level INFO -EventSource $EventSource
}
catch {
    Write-Warning "Cannot import LogHelper module: $_"
    exit 1
}
#endregion

#region Functions
function Get-CurrentIPAddress {
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual |
        Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
        Sort-Object -Property InterfaceIndex | Select-Object -First 1
        
        if ($adapters) {
            $ip = $adapters.IPAddress
            Write-IntuneLog -Message "Detected IP address: $ip" -Level INFO -EventSource $EventSource
            return $ip
        }
        return $null
    }
    catch {
        Write-IntuneLog -Message "Error getting IP address: $_" -Level ERROR -EventSource $EventSource
        return $null
    }
}

function Get-LocationFromIP {
    param([string]$IPAddress, [hashtable]$LocationMap)
    
    if ([string]::IsNullOrWhiteSpace($IPAddress)) {
        Write-IntuneLog -Message "IP address is null or empty" -Level WARN -EventSource $EventSource
        return $null
    }
    
    # Extrakcia prefixu (prvé 3 oktety + bod)
    if ($IPAddress -match '^(\d+\.\d+\.\d+\.)') {
        $prefix = $matches[1]
        
        if ($LocationMap.ContainsKey($prefix)) {
            $location = $LocationMap[$prefix]
            Write-IntuneLog -Message "Matched prefix '$prefix' to location: $location" -Level INFO -EventSource $EventSource
            return $location
        }
        else {
            Write-IntuneLog -Message "No location mapping found for prefix: $prefix" -Level WARN -EventSource $EventSource
        }
    }
    
    return $null
}

function Get-DeviceExtensionAttribute {
    param([string]$AttributeName = "extensionAttribute1")
    
    try {
        # Získaj Intune Device ID z registry
        $intuneKey = "HKLM:\SOFTWARE\Microsoft\Enrollments"
        $enrollments = Get-ChildItem -Path $intuneKey -ErrorAction SilentlyContinue
        
        if (-not $enrollments) {
            Write-IntuneLog -Message "No Intune enrollment found in registry" -Level WARN -EventSource $EventSource
            return $null
        }
        
        foreach ($enrollment in $enrollments) {
            $upn = Get-ItemProperty -Path $enrollment.PSPath -Name "UPN" -ErrorAction SilentlyContinue
            if ($upn) {
                Write-IntuneLog -Message "Found Intune enrollment for UPN: $($upn.UPN)" -Level INFO -EventSource $EventSource
                break
            }
        }
        
        # Poznámka: Detection script beží v SYSTEM kontexte a nemôže priamo čítať Graph API
        # Musíme použiť alternatívny prístup cez lokálne uložené údaje
        
        $localStatePath = "C:\TaurisIT\LocationState.json"
        if (Test-Path $localStatePath) {
            $state = Get-Content $localStatePath -Raw | ConvertFrom-Json
            Write-IntuneLog -Message "Current stored location: $($state.Location)" -Level INFO -EventSource $EventSource
            return $state.Location
        }
        
        Write-IntuneLog -Message "No local state file found" -Level WARN -EventSource $EventSource
        return $null
    }
    catch {
        Write-IntuneLog -Message "Error reading extension attribute: $_" -Level ERROR -EventSource $EventSource
        return $null
    }
}
#endregion

#region Main Logic
try {
    # Načítaj IP Location mapu z embedded data
    $ipLocationMapJson = @'
{
    "10.10.0.": "RS",
    "10.20.11.": "RS",
    "10.20.20.": "Server",
    "10.20.30.": "RS",
    "10.20.40.": "RS",
    "10.20.50.": "RS",
    "10.20.51.": "RS",
    "10.20.70.": "RS",
    "10.30.0.": "SNV",
    "10.30.40.": "SNV",
    "10.30.50.": "SNV",
    "10.30.51.": "SNV",
    "10.40.0.": "NR",
    "10.40.40.": "NR",
    "10.40.50.": "NR",
    "10.40.51.": "NR",
    "10.50.0.": "LDCKE",
    "10.50.40.": "LDCKE",
    "10.50.50.": "LDCKE",
    "10.50.51.": "LDCKE",
    "10.50.52.": "LDCKE",
    "10.60.7.": "RybaKE",
    "10.60.11.": "RybaKE",
    "10.60.17.": "RybaKE",
    "10.60.40.": "RybaKE",
    "10.60.50.": "RybaKE",
    "10.60.51.": "RybaKE",
    "10.60.77.": "RybaKE",
    "10.70.123.": "LDCKE",
    "10.80.0.": "BB",
    "10.80.40.": "BB",
    "10.80.50.": "BB",
    "10.80.51.": "BB",
    "10.82.0.": "BA",
    "10.82.40.": "BA",
    "10.82.50.": "BA",
    "10.82.51.": "BA",
    "10.82.70.": "BA",
    "10.83.0.": "ZA",
    "10.83.40.": "ZA",
    "10.83.50.": "ZA",
    "10.83.51.": "ZA",
    "192.168.7.": "RybaKE"
}
'@
    
    $locationMap = $ipLocationMapJson | ConvertFrom-Json -AsHashtable
    Write-IntuneLog -Message "Loaded $($locationMap.Count) location mappings" -Level INFO -EventSource $EventSource
    
    # Získaj aktuálnu IP adresu
    $currentIP = Get-CurrentIPAddress
    if (-not $currentIP) {
        Write-IntuneLog -Message "Cannot determine IP address - marking as non-compliant" -Level ERROR -EventSource $EventSource
        exit 1
    }
    
    # Zisti lokáciu z IP
    $expectedLocation = Get-LocationFromIP -IPAddress $currentIP -LocationMap $locationMap
    if (-not $expectedLocation) {
        Write-IntuneLog -Message "IP $currentIP does not match any known location - device is compliant (no action needed)" -Level INFO -EventSource $EventSource
        exit 0
    }
    
    # Skontroluj aktuálne uloženú lokáciu
    $currentLocation = Get-DeviceExtensionAttribute
    
    if ($currentLocation -eq $expectedLocation) {
        Write-IntuneLog -Message "Location is correct: $currentLocation - Device is COMPLIANT" -Level SUCCESS -EventSource $EventSource
        Write-IntuneLog -Message "=== Detection Completed Successfully ===" -Level INFO -EventSource $EventSource
        exit 0
    }
    else {
        Write-IntuneLog -Message "Location mismatch - Current: '$currentLocation', Expected: '$expectedLocation' - Device is NON-COMPLIANT" -Level WARN -EventSource $EventSource
        Write-IntuneLog -Message "=== Detection Completed - Remediation Needed ===" -Level INFO -EventSource $EventSource
        exit 1
    }
}
catch {
    Write-IntuneLog -Message "Detection script failed: $_" -Level ERROR -EventSource $EventSource
    Send-IntuneAlert -Message "Detection script critical error: $_" -Severity Critical -EventSource $EventSource
    exit 1
}
finally {
    Clear-OldLogs -RetentionDays 30 -LogDirectory $LogDirectory
}
#endregion