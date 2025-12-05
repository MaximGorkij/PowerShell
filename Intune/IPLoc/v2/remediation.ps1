<#
.SYNOPSIS
  Enhanced Intune Remediation Script - nastavenie lokality
.DESCRIPTION
  Zistí IP adresu clienta, určí lokalitu podľa zoznamu IP adries,
  uloží do registry a aktualizuje extensionAttribute1 v Entra ID cez Graph API.
  
  IMPROVEMENTS:
  - Exponential backoff retry logic
  - Better error handling and validation
  - VPN detection
  - Enhanced Graph API integration
  - Token caching
  - Secure credential handling
  
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
$FAILURE = 1
#endregion

#region Module Loading
try {
    # Load modules
    $modulePaths = @(
        "$PSScriptRoot\CommonFunctions.psm1",
        "$PSScriptRoot\GraphHelper.psm1",
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
    exit $FAILURE
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
    
    Write-IntuneLog -Message "=== Intune Remediation Script Start ===" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Script version: 3.0 (Enhanced)" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Computer: $env:COMPUTERNAME" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "User: $env:USERNAME" -Level INFO -EventSource $ScriptName
    
    # Clean old logs
    Clear-OldLogs -RetentionDays $config.Logging.LogRetentionDays
    
    # Initialize registry path
    if ($config.Security.SecureRegistryPath) {
        $registryInitialized = Initialize-RegistryPath -RegistryPath $config.Paths.RegistryPath -SecurePath
    }
    else {
        $registryInitialized = Initialize-RegistryPath -RegistryPath $config.Paths.RegistryPath
    }
    
    if (-not $registryInitialized) {
        Write-IntuneLog -Message "ERROR: Failed to initialize registry path" -Level ERROR -EventSource $ScriptName
        exit $FAILURE
    }
    
    # 1. Load IP location map
    Write-IntuneLog -Message "Step 1/5: Loading IP location map" -Level INFO -EventSource $ScriptName
    $ipMap = Get-IPLocationMap -ConfigFile "$PSScriptRoot\IPLocationMap.json"
    
    if (-not $ipMap -or $ipMap.Count -eq 0) {
        Write-IntuneLog -Message "ERROR: Failed to load IP location map" -Level ERROR -EventSource $ScriptName
        exit $FAILURE
    }
    
    # 2. Get current IP address
    Write-IntuneLog -Message "Step 2/5: Detecting IP address" -Level INFO -EventSource $ScriptName
    
    $includeVPN = -not $config.Detection.AllowVPNDetection
    $currentIP = Get-PrimaryIPAddress -IncludeVPN:$includeVPN
    
    if (-not $currentIP) {
        Write-IntuneLog -Message "FAIL: Could not detect IP address (VPN connection?)" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "Remediation failed - IP detection failed on $env:COMPUTERNAME" `
            -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "Detected IP: $currentIP" -Level INFO -EventSource $ScriptName
    
    # 3. Determine location from IP
    Write-IntuneLog -Message "Step 3/5: Determining location from IP" -Level INFO -EventSource $ScriptName
    $location = Get-LocationFromIP -IPAddress $currentIP -Map $ipMap
    
    if (-not $location) {
        Write-IntuneLog -Message "FAIL: IP $currentIP not found in location map" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "Remediation failed - Unknown network on $env:COMPUTERNAME ($currentIP)" `
            -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "Determined location: $location" -Level INFO -EventSource $ScriptName
    
    # 4. Save to registry
    Write-IntuneLog -Message "Step 4/5: Saving location to registry" -Level INFO -EventSource $ScriptName
    
    $serial = Get-DeviceSerialNumber
    if ($serial) {
        Write-IntuneLog -Message "Device serial number: $serial" -Level INFO -EventSource $ScriptName
    }
    
    $savedToRegistry = Save-LocationToRegistry -RegistryPath $config.Paths.RegistryPath `
        -Location $location `
        -IPAddress $currentIP `
        -SerialNumber $serial
    
    if (-not $savedToRegistry) {
        Write-IntuneLog -Message "ERROR: Failed to save location to registry" -Level ERROR -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "Location saved to registry successfully" -Level SUCCESS -EventSource $ScriptName
    
    # 5. Update Entra ID (optional)
    Write-IntuneLog -Message "Step 5/5: Updating Entra ID via Graph API" -Level INFO -EventSource $ScriptName
    
    if (-not $config.Detection.RequireGraphUpdate) {
        Write-IntuneLog -Message "Graph API update not required by configuration" -Level INFO -EventSource $ScriptName
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
    
    # Load credentials
    $credentials = Get-EnvCredentials -EnvFile "$PSScriptRoot\.env"
    
    if (-not $credentials) {
        Write-IntuneLog -Message "WARN: Graph API credentials not available, skipping Entra ID update" -Level WARN -EventSource $ScriptName
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS (Local Only) ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
    
    # Get Azure AD Device ID
    $azureDeviceId = Get-AzureADDeviceId
    
    if (-not $azureDeviceId) {
        Write-IntuneLog -Message "WARN: Could not get Azure AD Device ID, skipping Entra ID update" -Level WARN -EventSource $ScriptName
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS (Local Only) ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
    
    Write-IntuneLog -Message "Azure AD Device ID: $azureDeviceId" -Level INFO -EventSource $ScriptName
    
    # Update via Graph API with retry
    try {
        Invoke-GraphApiWithRetry -MaxRetries $config.GraphAPI.RetryAttempts `
            -UseExponentialBackoff:$config.GraphAPI.UseExponentialBackoff `
            -ScriptBlock {
            
            Write-IntuneLog -Message "Getting Graph API token..." -Level INFO -EventSource $ScriptName
            $token = Get-GraphToken -TenantId $credentials.TenantId `
                -ClientId $credentials.ClientId `
                -ClientSecret $credentials.ClientSecret
            
            if ([string]::IsNullOrWhiteSpace($token)) {
                throw "Failed to get Graph API token"
            }
            
            # Test connection
            $connectionOK = Test-GraphConnection -AccessToken $token
            if (-not $connectionOK) {
                throw "Graph API connection test failed"
            }
            
            Write-IntuneLog -Message "Searching for device in Entra ID..." -Level INFO -EventSource $ScriptName
            $device = Find-DeviceInGraph -AccessToken $token `
                -DeviceId $azureDeviceId `
                -ComputerName $env:COMPUTERNAME `
                -MaxResults $config.GraphAPI.MaxDeviceSearchResults
            
            if (-not $device) {
                throw "Device not found in Entra ID"
            }
            
            Write-IntuneLog -Message "Device found: $($device.displayName) (ObjectId: $($device.id))" -Level INFO -EventSource $ScriptName
            
            # Check if update is needed
            $currentEntraLocation = $device.extensionAttributes.extensionAttribute1
            if ($currentEntraLocation -eq $location) {
                Write-IntuneLog -Message "Entra ID location already correct: $currentEntraLocation" -Level INFO -EventSource $ScriptName
                return
            }
            
            Write-IntuneLog -Message "Updating extensionAttribute1 to: $location" -Level INFO -EventSource $ScriptName
            
            # Update device
            $updated = Update-DeviceInGraph -AccessToken $token `
                -DeviceObjectId $device.id `
                -Location $location `
                -SerialNumber $serial
            
            if ($updated) {
                Write-IntuneLog -Message "Entra ID updated successfully" -Level SUCCESS -EventSource $ScriptName
                
                # Log success
                $successLog = Join-Path $config.Paths.LogDirectory "GraphUpdate_Success.log"
                $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($device.displayName), Location: $location, DeviceId: $azureDeviceId"
                Add-Content -Path $successLog -Value $logEntry -ErrorAction SilentlyContinue
            }
        }
        
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-IntuneLog -Message "Graph API update failed: $errorMsg" -Level WARN -EventSource $ScriptName
        
        # Log error
        $errorLog = Join-Path $config.Paths.LogDirectory "GraphUpdate_Errors.log"
        $errorEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Computer: $env:COMPUTERNAME, Error: $errorMsg"
        Add-Content -Path $errorLog -Value $errorEntry -ErrorAction SilentlyContinue
        
        # Provide helpful error messages
        if ($errorMsg -match "404|Not Found") {
            Write-IntuneLog -Message "Device does not exist in Entra ID or not synced yet" -Level WARN -EventSource $ScriptName
        }
        elseif ($errorMsg -match "401|403|Unauthorized|Forbidden") {
            Write-IntuneLog -Message "Authentication error - check App Registration permissions (Device.ReadWrite.All required)" -Level WARN -EventSource $ScriptName
        }
        elseif ($errorMsg -match "timeout") {
            Write-IntuneLog -Message "Graph API timeout - network issue?" -Level WARN -EventSource $ScriptName
        }
        
        # Consider it a success if local registry was updated
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS (Local Only, Graph Update Failed) ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
}
catch {
    $errorMsg = $_.Exception.Message
    Write-IntuneLog -Message "CRITICAL ERROR: $errorMsg" -Level ERROR -EventSource $ScriptName
    
    if ($_.ScriptStackTrace) {
        Write-IntuneLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR -EventSource $ScriptName
    }
    
    Send-IntuneAlert -Message "Remediation script failed on $env:COMPUTERNAME: $errorMsg" `
        -Severity Error -EventSource $ScriptName
    
    exit $FAILURE
}
finally {
    # Cleanup
    Clear-GraphTokenCache
    
    if (Get-Module CommonFunctions) {
        Remove-Module CommonFunctions -Force -ErrorAction SilentlyContinue
    }
    if (Get-Module GraphHelper) {
        Remove-Module GraphHelper -Force -ErrorAction SilentlyContinue
    }
}
#endregion