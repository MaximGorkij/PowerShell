<#
.SYNOPSIS
  Enhanced Intune Detection Script - kontrola lokality podľa IP adresy
.DESCRIPTION
  Zistí IP adresu clienta, porovná so zoznamom IP adries a lokalít
  a zistí či je lokalita nastavená správne v registry.
  
  IMPROVEMENTS:
  - Better VPN detection
  - Exponential backoff retry
  - Enhanced error handling
  - Configuration file support
  - Secure registry handling
  
.VERSION
  3.0 - Complete rewrite with enhanced features
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param()

#region Initialization
$ErrorActionPreference = "Stop"
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Intune exit codes
$SUCCESS = 0
$REMEDIATION_REQUIRED = 1
#endregion

#region Module Loading
try {
    # Load modules
    $modulePaths = @(
        "$PSScriptRoot\CommonFunctions.psm1",
        "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
    )
    
    foreach ($modulePath in $modulePaths) {
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -ErrorAction Stop
        }
        else {
            Write-Warning "Module not found: $modulePath"
        }
    }
    
    # Load LogHelper Adapter if exists
    $adapterPath = "$PSScriptRoot\LogHelperAdapter.psm1"
    if (Test-Path $adapterPath) {
        Import-Module $adapterPath -Force -ErrorAction SilentlyContinue
    }
    else {
        # Fallback functions if adapter not found
        function Write-IntuneLog { param($Message, $Level, $EventSource) Write-Host "[$Level] $Message" }
        function Initialize-LogSystem { param($LogDirectory, $EventSource) }
        function Clear-OldLogs { param($RetentionDays) }
        function Send-IntuneAlert { param($Message, $Severity, $EventSource) }
    }
}
catch {
    Write-Error "Failed to load modules: $_"
    exit $REMEDIATION_REQUIRED
}
#endregion

#region Main Execution
try {
    # Load configuration
    $config = Get-Configuration
    if (-not $config) {
        $config = Get-DefaultConfiguration
    }
    
    # Initialize logging
    Initialize-LogSystem -LogDirectory $config.Paths.LogDirectory -EventSource $ScriptName
    
    Write-IntuneLog -Message "=== Intune Detection Script Start ===" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Script version: 3.0 (Enhanced)" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Computer: $env:COMPUTERNAME" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "User: $env:USERNAME" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "OS: $([System.Environment]::OSVersion.VersionString)" -Level INFO -EventSource $ScriptName
    
    # Clean old logs
    Clear-OldLogs -RetentionDays $config.Logging.LogRetentionDays
    
    # Initialize registry path
    if ($config.Security.SecureRegistryPath) {
        Initialize-RegistryPath -RegistryPath $config.Paths.RegistryPath -SecurePath
    }
    else {
        Initialize-RegistryPath -RegistryPath $config.Paths.RegistryPath
    }
    
    # 1. Load IP location map
    Write-IntuneLog -Message "Step 1/4: Loading IP location map" -Level INFO -EventSource $ScriptName
    $ipMap = Get-IPLocationMap -ConfigFile "$PSScriptRoot\IPLocationMap.json"
    
    if (-not $ipMap -or $ipMap.Count -eq 0) {
        Write-IntuneLog -Message "ERROR: Failed to load IP location map" -Level ERROR -EventSource $ScriptName
        exit $REMEDIATION_REQUIRED
    }
    
    # 2. Check if location cache is valid
    Write-IntuneLog -Message "Step 2/4: Checking location cache" -Level INFO -EventSource $ScriptName
    $currentLocation = Get-LocationFromRegistry -RegistryPath $config.Paths.RegistryPath
    $cacheValid = Test-LocationCacheValid -RegistryPath $config.Paths.RegistryPath `
        -ValidityHours $config.Detection.CacheValidityHours
    
    if ($cacheValid -and $currentLocation) {
        Write-IntuneLog -Message "Location cache is valid: $currentLocation" -Level SUCCESS -EventSource $ScriptName
        Write-IntuneLog -Message "=== Script End: COMPLIANT ===" -Level INFO -EventSource $ScriptName
        exit $SUCCESS
    }
    
    # 3. Get current IP address
    Write-IntuneLog -Message "Step 3/4: Detecting IP address" -Level INFO -EventSource $ScriptName
    
    $includeVPN = -not $config.Detection.AllowVPNDetection
    $currentIP = Get-PrimaryIPAddress -IncludeVPN:$includeVPN
    
    if (-not $currentIP) {
        if ($config.Detection.FallbackToLastKnownLocation -and $currentLocation) {
            Write-IntuneLog -Message "Could not detect IP (VPN?), using cached location: $currentLocation" -Level WARN -EventSource $ScriptName
            Write-IntuneLog -Message "=== Script End: COMPLIANT (Fallback) ===" -Level INFO -EventSource $ScriptName
            exit $SUCCESS
        }
        else {
            Write-IntuneLog -Message "FAIL: Could not detect IP address and no cached location" -Level ERROR -EventSource $ScriptName
            Send-IntuneAlert -Message "IP detection failed on $env:COMPUTERNAME" -Severity Warning -EventSource $ScriptName
            exit $REMEDIATION_REQUIRED
        }
    }
    
    Write-IntuneLog -Message "Detected IP: $currentIP" -Level INFO -EventSource $ScriptName
    
    # 4. Determine expected location from IP
    Write-IntuneLog -Message "Step 4/4: Determining location from IP" -Level INFO -EventSource $ScriptName
    $expectedLocation = Get-LocationFromIP -IPAddress $currentIP -Map $ipMap
    
    if (-not $expectedLocation) {
        if ($config.Detection.FallbackToLastKnownLocation -and $currentLocation) {
            Write-IntuneLog -Message "IP $currentIP not in known network, using cached location: $currentLocation" -Level WARN -EventSource $ScriptName
            Write-IntuneLog -Message "=== Script End: COMPLIANT (Unknown Network) ===" -Level INFO -EventSource $ScriptName
            exit $SUCCESS
        }
        else {
            Write-IntuneLog -Message "FAIL: IP $currentIP not found in location map" -Level ERROR -EventSource $ScriptName
            Send-IntuneAlert -Message "Unknown network detected on $env:COMPUTERNAME ($currentIP)" -Severity Warning -EventSource $ScriptName
            exit $REMEDIATION_REQUIRED
        }
    }
    
    Write-IntuneLog -Message "Expected location: $expectedLocation" -Level INFO -EventSource $ScriptName
    
    # 5. Compare with current location
    if (-not $currentLocation) {
        Write-IntuneLog -Message "FAIL: Location not set in registry" -Level ERROR -EventSource $ScriptName
        exit $REMEDIATION_REQUIRED
    }
    
    if ($currentLocation -eq $expectedLocation) {
        Write-IntuneLog -Message "SUCCESS: Location is correct ($currentLocation)" -Level SUCCESS -EventSource $ScriptName
        Write-IntuneLog -Message "=== Script End: COMPLIANT ===" -Level INFO -EventSource $ScriptName
        exit $SUCCESS
    }
    else {
        Write-IntuneLog -Message "FAIL: Location mismatch - Current: '$currentLocation', Expected: '$expectedLocation'" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "Location mismatch on $env:COMPUTERNAME (Current: $currentLocation, Expected: $expectedLocation)" `
            -Severity Warning -EventSource $ScriptName
        exit $REMEDIATION_REQUIRED
    }
}
catch {
    $errorMsg = $_.Exception.Message
    Write-IntuneLog -Message "CRITICAL ERROR: $errorMsg" -Level ERROR -EventSource $ScriptName
    
    if ($_.ScriptStackTrace) {
        Write-IntuneLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR -EventSource $ScriptName
    }
    
    Send-IntuneAlert -Message "Detection script failed on $env:COMPUTERNAME: $errorMsg" `
        -Severity Error -EventSource $ScriptName
    
    exit $REMEDIATION_REQUIRED
}
finally {
    # Cleanup
    if (Get-Module CommonFunctions) {
        Remove-Module CommonFunctions -Force -ErrorAction SilentlyContinue
    }
}
#endregion