<#
.SYNOPSIS
  Enhanced Intune Remediation Script - nastavenie lokality
.VERSION
  3.2 - Robust logging with fallback
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param()

#region Initialization
$ErrorActionPreference = "Stop"
$ScriptName = "remediation"

# Intune exit codes
$SUCCESS = 0
$FAILURE = 1

# Log configuration
$LogDir = "C:\TaurisIT\Log\IPcheck"
$RemediationLog = Join-Path $LogDir "remediation.log"
$TaskLog = Join-Path $LogDir "task_execution.log"
$FallbackLog = Join-Path $LogDir "fallback.log"

# Global variable to track logging method
$Global:LoggingMethod = "Unknown"
#endregion

#region Robust Logging Functions
function Initialize-Logging {
    try {
        # Create log directory if it doesn't exist
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        # Try multiple methods to ensure we can log
        $methods = @()
        
        # Method 1: Try to import LogHelper module
        try {
            Import-Module LogHelper -Force -ErrorAction Stop
            $Global:LoggingMethod = "LogHelper"
            Write-Verbose "Using LogHelper module for logging"
            return $true
        }
        catch {
            Write-Verbose "LogHelper module not available: $_"
            $methods += "LogHelper-Failed"
        }
        
        # Method 2: Try direct file logging
        try {
            $testMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] Logging test"
            $testMessage | Out-File -FilePath $FallbackLog -Append -Encoding UTF8 -ErrorAction Stop
            $Global:LoggingMethod = "DirectFile"
            Write-Verbose "Using direct file logging"
            return $true
        }
        catch {
            Write-Verbose "Direct file logging failed: $_"
            $methods += "DirectFile-Failed"
        }
        
        # Method 3: Try event log as last resort
        try {
            $source = "IPLocationRemediation"
            if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
                [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
            }
            $Global:LoggingMethod = "EventLog"
            Write-Verbose "Using Event Log for logging"
            return $true
        }
        catch {
            Write-Verbose "Event Log failed: $_"
            $methods += "EventLog-Failed"
        }
        
        # All methods failed
        $Global:LoggingMethod = "ConsoleOnly"
        Write-Verbose "All logging methods failed, using console only. Failed methods: $($methods -join ', ')"
        return $false
    }
    catch {
        $Global:LoggingMethod = "Error"
        Write-Verbose "Logging initialization failed: $_"
        return $false
    }
}

function Write-ScriptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory = $false)]
        [string]$EventSource = "remediation"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] [$ScriptName] $Message"
    
    # Always write to console if interactive
    if ($Host.Name -match "Console" -or $Host.Name -match "Host") {
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        try {
            Write-Host $logEntry -ForegroundColor $color
        }
        catch {
            # Console output failed, try basic write
            Write-Output $logEntry
        }
    }
    
    # Use appropriate logging method based on what's available
    switch ($Global:LoggingMethod) {
        "LogHelper" {
            try {
                # Use LogHelper module functions
                Write-IntuneLog -Message $Message -Level $Level -EventSource $EventSource
            }
            catch {
                # LogHelper failed, fallback to direct file
                Write-DirectFileLog -Message $logEntry
            }
        }
        
        "DirectFile" {
            Write-DirectFileLog -Message $logEntry
        }
        
        "EventLog" {
            Write-EventLogEntry -Message $Message -Level $Level -Source "IPLocationRemediation"
        }
        
        default {
            # Console only or error - just ensure we have it in console
            if ($Host.Name -notmatch "Console") {
                Write-Output $logEntry
            }
        }
    }
}

function Write-DirectFileLog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    
    # Try multiple log files
    $logFiles = @($RemediationLog, $TaskLog, $FallbackLog)
    
    foreach ($logFile in $logFiles) {
        try {
            $Message | Out-File -FilePath $logFile -Append -Encoding UTF8 -ErrorAction Stop
            return $true
        }
        catch {
            # Try next file
            continue
        }
    }
    
    # All files failed
    return $false
}

function Write-EventLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Source
    )
    
    try {
        $entryType = switch ($Level) {
            "ERROR" { "Error" }
            "WARN" { "Warning" }
            default { "Information" }
        }
        
        $eventId = switch ($Level) {
            "ERROR" { 1001 }
            "WARN" { 1002 }
            "SUCCESS" { 1003 }
            default { 1000 }
        }
        
        Write-EventLog -LogName "Application" -Source $Source `
            -EventId $eventId -EntryType $entryType -Message $Message `
            -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

# Fallback functions in case LogHelper module doesn't export them
function Write-IntuneLogFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource
    )
    Write-ScriptLog -Message $Message -Level $Level -EventSource $EventSource
}

function Initialize-LogSystemFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource
    )
    Initialize-Logging | Out-Null
}

function Clear-OldLogsFallback {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$RetentionDays)
    # Simple implementation - could be expanded
    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogDir -Filter "*.log" -File | Where-Object {
            $_.LastWriteTime -lt $cutoffDate
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore cleanup errors
    }
}

function Send-IntuneAlertFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$Severity,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource
    )
    Write-ScriptLog -Message "[ALERT $Severity] $Message" -Level $Severity.ToUpper() -EventSource $EventSource
}
#endregion

#region Helper Functions
function Import-ConfigurationData {
    [CmdletBinding()]
    param()
    
    try {
        $configPath = "$PSScriptRoot\config.json"
        if (Test-Path $configPath) {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            Write-ScriptLog "Configuration loaded from $configPath" -Level INFO
            return $config
        }
        else {
            Write-ScriptLog "Configuration file not found at $configPath" -Level WARN
            return $null
        }
    }
    catch {
        Write-ScriptLog "Failed to load configuration: $_" -Level ERROR
        return $null
    }
}

function Get-DefaultConfiguration {
    [CmdletBinding()]
    param()
    
    return @{
        Security  = @{
            SecureRegistryPath = $true
        }
        Paths     = @{
            RegistryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
        }
        Detection = @{
            AllowVPNDetection  = $false
            RequireGraphUpdate = $true
        }
        GraphAPI  = @{
            RetryAttempts         = 3
            UseExponentialBackoff = $true
            TimeoutSeconds        = 30
        }
    }
}

function Initialize-RegistryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,
        
        [switch]$SecurePath
    )
    
    try {
        # Create registry path if it doesn't exist
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -ItemType Directory -Force | Out-Null
            Write-ScriptLog "Created registry path: $RegistryPath" -Level INFO
        }
        
        # Set permissions if secure path is required
        if ($SecurePath) {
            try {
                $acl = Get-Acl $RegistryPath
                $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    "BUILTIN\Administrators",
                    "FullControl",
                    "ContainerInherit,ObjectInherit",
                    "None",
                    "Allow"
                )
                $acl.SetAccessRule($rule)
                Set-Acl -Path $RegistryPath -AclObject $acl
                Write-ScriptLog "Set secure permissions on registry path" -Level INFO
            }
            catch {
                Write-ScriptLog "Could not set secure permissions: $_" -Level WARN
            }
        }
        
        return $true
    }
    catch {
        Write-ScriptLog "Failed to initialize registry path: $_" -Level ERROR
        return $false
    }
}

function Get-IPLocationMap {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ConfigFile)
    
    try {
        if (Test-Path $ConfigFile) {
            $jsonContent = Get-Content $ConfigFile -Raw -ErrorAction Stop
            $ipMap = $jsonContent | ConvertFrom-Json -ErrorAction Stop
            return $ipMap
        }
        else {
            Write-ScriptLog "IP location map file not found: $ConfigFile" -Level ERROR
            return $null
        }
    }
    catch {
        Write-ScriptLog "Failed to load IP location map: $_" -Level ERROR
        return $null
    }
}

function Get-PrimaryIPAddress {
    [CmdletBinding()]
    param([switch]$IncludeVPN)
    
    try {
        # Get network adapters
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        
        if (-not $adapters) {
            Write-ScriptLog "No active physical adapters found" -Level WARN
            return $null
        }
        
        foreach ($adapter in $adapters) {
            $ipAddresses = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            
            foreach ($ip in $ipAddresses) {
                # Skip private/internal IPs if we want public only
                $ipParts = $ip.IPAddress.Split('.')
                if ($ipParts[0] -eq '10' -or 
                    ($ipParts[0] -eq '172' -and $ipParts[1] -ge '16' -and $ipParts[1] -le '31') -or
                    ($ipParts[0] -eq '192' -and $ipParts[1] -eq '168')) {
                    Write-ScriptLog "Skipping private IP: $($ip.IPAddress)" -Level DEBUG
                    continue
                }
                
                # Skip VPN IPs if not included
                if (-not $IncludeVPN -and $adapter.Name -match "VPN|Virtual|Tunnel") {
                    Write-ScriptLog "Skipping VPN adapter: $($adapter.Name)" -Level DEBUG
                    continue
                }
                
                Write-ScriptLog "Selected IP address: $($ip.IPAddress) from adapter: $($adapter.Name)" -Level INFO
                return $ip.IPAddress
            }
        }
        
        # If no public IP found, use first available
        $firstAdapter = $adapters[0]
        $firstIP = Get-NetIPAddress -InterfaceIndex $firstAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($firstIP) {
            Write-ScriptLog "Using first available IP: $($firstIP.IPAddress)" -Level INFO
            return $firstIP.IPAddress
        }
        
        return $null
    }
    catch {
        Write-ScriptLog "Error getting IP address: $_" -Level ERROR
        return $null
    }
}

function Get-LocationFromIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,
        
        [Parameter(Mandatory = $true)]
        $Map
    )
    
    try {
        # Convert IP to decimal for comparison
        $ipParts = $IPAddress.Split('.')
        $ipDecimal = [int]$ipParts[0] * 16777216 + [int]$ipParts[1] * 65536 + [int]$ipParts[2] * 256 + [int]$ipParts[3]
        
        foreach ($entry in $Map) {
            # Check if IP falls within the prefix range
            if ($ipDecimal -ge $entry.StartRange -and $ipDecimal -le $entry.EndRange) {
                Write-ScriptLog "IP $IPAddress matches range $($entry.StartRange)-$($entry.EndRange)" -Level DEBUG
                return $entry.Location
            }
        }
        
        return $null
    }
    catch {
        Write-ScriptLog "Error determining location from IP: $_" -Level ERROR
        return $null
    }
}

function Get-DeviceSerialNumber {
    [CmdletBinding()]
    param()
    
    try {
        $serial = (Get-WmiObject -Class Win32_BIOS -ErrorAction Stop).SerialNumber
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $serial = "UNKNOWN"
        }
        return $serial
    }
    catch {
        Write-ScriptLog "Could not retrieve serial number: $_" -Level WARN
        return "UNKNOWN"
    }
}

function Save-LocationToRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,
        
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Create/update registry values
        New-ItemProperty -Path $RegistryPath -Name "Location" -Value $Location -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name "IPAddress" -Value $IPAddress -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name "SerialNumber" -Value $SerialNumber -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name "LastUpdated" -Value $timestamp -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name "UpdatedBy" -Value "IntuneRemediation" -PropertyType String -Force | Out-Null
        
        # Verify the values were saved
        $savedLocation = Get-ItemProperty -Path $RegistryPath -Name "Location" -ErrorAction SilentlyContinue
        if ($savedLocation.Location -eq $Location) {
            Write-ScriptLog "Registry values saved successfully" -Level INFO
            return $true
        }
        else {
            Write-ScriptLog "Failed to verify registry values" -Level ERROR
            return $false
        }
    }
    catch {
        Write-ScriptLog "Failed to save to registry: $_" -Level ERROR
        return $false
    }
}

function Get-EnvCredentials {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$EnvFile)
    
    try {
        if (Test-Path $EnvFile) {
            $envContent = Get-Content $EnvFile
            $credentials = @{}
            
            foreach ($line in $envContent) {
                if ($line -match '^\s*([^=]+)\s*=\s*(.+)\s*$') {
                    $credentials[$matches[1]] = $matches[2].Trim()
                }
            }
            
            # Check required values
            if ($credentials.ContainsKey('TENANT_ID') -and 
                $credentials.ContainsKey('CLIENT_ID') -and 
                $credentials.ContainsKey('CLIENT_SECRET')) {
                
                return @{
                    TenantId     = $credentials['TENANT_ID']
                    ClientId     = $credentials['CLIENT_ID']
                    ClientSecret = $credentials['CLIENT_SECRET']
                }
            }
        }
        
        Write-ScriptLog "Environment file not found or incomplete" -Level WARN
        return $null
    }
    catch {
        Write-ScriptLog "Error loading credentials: $_" -Level WARN
        return $null
    }
}

function Get-AzureADDeviceId {
    [CmdletBinding()]
    param()
    
    try {
        # Try to get device ID from DSREGCMD
        $dsregCmdStatus = dsregcmd /status
        $deviceIdLine = $dsregCmdStatus | Where-Object { $_ -match 'DeviceId\s*:\s*([A-Za-z0-9-]+)' }
        
        if ($deviceIdLine -and $matches[1]) {
            return $matches[1]
        }
        
        # Alternative method: Get from registry
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-AAD%4Operational"
        if (Test-Path $regPath) {
            $deviceId = Get-ItemProperty -Path $regPath -Name "DeviceId" -ErrorAction SilentlyContinue
            if ($deviceId) {
                return $deviceId.DeviceId
            }
        }
        
        Write-ScriptLog "Could not retrieve Azure AD Device ID" -Level WARN
        return $null
    }
    catch {
        Write-ScriptLog "Error getting Azure AD Device ID: $_" -Level WARN
        return $null
    }
}

function Invoke-GraphApiWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [switch]$UseExponentialBackoff,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )
    
    $retryCount = 0
    $delay = 2  # Initial delay in seconds
    
    while ($retryCount -le $MaxRetries) {
        try {
            Write-ScriptLog "Attempt $($retryCount + 1) of $($MaxRetries + 1)" -Level INFO
            return & $ScriptBlock
        }
        catch {
            $retryCount++
            
            if ($retryCount -gt $MaxRetries) {
                Write-ScriptLog "Max retries reached. Last error: $_" -Level ERROR
                throw $_
            }
            
            if ($UseExponentialBackoff) {
                $delay = [math]::Pow(2, $retryCount)  # Exponential backoff
            }
            
            Write-ScriptLog "Attempt failed. Retrying in $delay seconds... Error: $_" -Level WARN
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-GraphToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )
    
    try {
        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $body = @{
            client_id     = $ClientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        }
        
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        Write-ScriptLog "Failed to get Graph token: $_" -Level ERROR
        return $null
    }
}

function Update-DeviceLocationInGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )
    
    try {
        $graphUrl = "https://graph.microsoft.com/v1.0/devices/$DeviceId"
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = "application/json"
        }
        
        $body = @{
            "extensionAttributes" = @{
                "extensionAttribute1" = $Location
            }
        } | ConvertTo-Json -Depth 3
        
        $response = Invoke-RestMethod -Uri $graphUrl -Method Patch -Headers $headers -Body $body -ErrorAction Stop
        
        Write-ScriptLog "Graph API update successful for device $DeviceId" -Level SUCCESS
        return $true
    }
    catch {
        Write-ScriptLog "Graph API update failed: $_" -Level ERROR
        return $false
    }
}
#endregion

#region Module Loading with Fallbacks
try {
    # Initialize logging FIRST (before anything else)
    $loggingInitialized = Initialize-Logging
    Write-ScriptLog "Logging initialized using method: $Global:LoggingMethod" -Level "INFO"
    
    # Load CommonFunctions (required)
    $commonFunctionsPath = "$PSScriptRoot\CommonFunctions.psm1"
    if (Test-Path $commonFunctionsPath) {
        Import-Module $commonFunctionsPath -Force -ErrorAction Stop
        Write-ScriptLog "Loaded CommonFunctions module" -Level "INFO"
    }
    else {
        Write-ScriptLog "ERROR: CommonFunctions.psm1 not found at $commonFunctionsPath" -Level "ERROR"
        exit $FAILURE
    }
    
    # Load GraphHelper
    $graphHelperPath = "$PSScriptRoot\GraphHelper.psm1"
    if (Test-Path $graphHelperPath) {
        Import-Module $graphHelperPath -Force -ErrorAction Stop
        Write-ScriptLog "Loaded GraphHelper module" -Level "INFO"
    }
    else {
        Write-ScriptLog "WARN: GraphHelper.psm1 not found, Graph API updates disabled" -Level "WARN"
    }
    
    # Check if LogHelper module was loaded successfully
    if ($Global:LoggingMethod -ne "LogHelper") {
        Write-ScriptLog "LogHelper module not available, using fallback logging" -Level "WARN"
        
        # Create alias for LogHelper functions to use our fallbacks
        Set-Alias -Name Write-IntuneLog -Value Write-IntuneLogFallback -Scope Global -ErrorAction SilentlyContinue
        Set-Alias -Name Initialize-LogSystem -Value Initialize-LogSystemFallback -Scope Global -ErrorAction SilentlyContinue
        Set-Alias -Name Clear-OldLogs -Value Clear-OldLogsFallback -Scope Global -ErrorAction SilentlyContinue
        Set-Alias -Name Send-IntuneAlert -Value Send-IntuneAlertFallback -Scope Global -ErrorAction SilentlyContinue
    }
    else {
        Write-ScriptLog "LogHelper module loaded successfully" -Level "INFO"
    }
}
catch {
    # Critical error - can't even load modules
    Write-Host "CRITICAL: Failed to initialize script: $_" -ForegroundColor Red
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] Script initialization failed: $_" | 
        Out-File -FilePath $FallbackLog -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Even fallback logging failed
    }
    exit $FAILURE
}
#endregion

#region Main Execution
try {
    # Initialize logging system (using whichever method is available)
    Initialize-LogSystem -LogDirectory $LogDir -EventSource $ScriptName
    
    Write-IntuneLog -Message "=== Remediation Script Start ===" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Script version: 3.2 (Robust logging)" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Computer: $env:COMPUTERNAME" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "User: $env:USERNAME" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Logging method: $Global:LoggingMethod" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -Level INFO -EventSource $ScriptName
    
    # Clean old logs (if function is available)
    try {
        Clear-OldLogs -RetentionDays 30
    }
    catch {
        Write-IntuneLog -Message "Note: Could not clear old logs: $_" -Level WARN -EventSource $ScriptName
    }
    
    # Load configuration
    $config = Import-ConfigurationData
    if (-not $config) {
        $config = Get-DefaultConfiguration
        Write-IntuneLog -Message "Using default configuration" -Level WARN -EventSource $ScriptName
    }
    
    # Initialize registry path
    if ($config.Security.SecureRegistryPath) {
        $registryInitialized = Initialize-RegistryPath -RegistryPath $config.Paths.RegistryPath -SecurePath
    }
    else {
        $registryInitialized = Initialize-RegistryPath -RegistryPath $config.Paths.RegistryPath
    }
    
    if (-not $registryInitialized) {
        Write-IntuneLog -Message "ERROR: Failed to initialize registry path" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "Registry initialization failed on $env:COMPUTERNAME" -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    # 1. Load IP location map
    Write-IntuneLog -Message "Loading IP location map..." -Level INFO -EventSource $ScriptName
    $ipMap = Get-IPLocationMap -ConfigFile "$PSScriptRoot\IPLocationMap.json"
    
    if (-not $ipMap -or $ipMap.Count -eq 0) {
        Write-IntuneLog -Message "ERROR: Failed to load IP location map" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "IP location map load failed on $env:COMPUTERNAME" -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "Loaded $($ipMap.Count) IP prefixes" -Level INFO -EventSource $ScriptName
    
    # 2. Get current IP address
    Write-IntuneLog -Message "Detecting IP address..." -Level INFO -EventSource $ScriptName
    
    $includeVPN = -not $config.Detection.AllowVPNDetection
    $currentIP = Get-PrimaryIPAddress -IncludeVPN:$includeVPN
    
    if (-not $currentIP) {
        Write-IntuneLog -Message "FAIL: Could not detect IP address (VPN connection?)" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "IP detection failed on $env:COMPUTERNAME" -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "Detected IP: $currentIP" -Level INFO -EventSource $ScriptName
    
    # 3. Determine location from IP
    Write-IntuneLog -Message "Determining location from IP..." -Level INFO -EventSource $ScriptName
    $location = Get-LocationFromIP -IPAddress $currentIP -Map $ipMap
    
    if (-not $location) {
        Write-IntuneLog -Message "FAIL: IP $currentIP not found in location map" -Level ERROR -EventSource $ScriptName
        Send-IntuneAlert -Message "Unknown network on $env:COMPUTERNAME ($currentIP)" -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "Determined location: $location" -Level INFO -EventSource $ScriptName
    
    # 4. Save to registry
    Write-IntuneLog -Message "Saving location to registry..." -Level INFO -EventSource $ScriptName
    
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
        Send-IntuneAlert -Message "Registry save failed on $env:COMPUTERNAME" -Severity Error -EventSource $ScriptName
        exit $FAILURE
    }
    
    Write-IntuneLog -Message "SUCCESS: Location saved to registry" -Level SUCCESS -EventSource $ScriptName
    
    # 5. Update Entra ID (optional)
    if (-not $config.Detection.RequireGraphUpdate) {
        Write-IntuneLog -Message "Graph API update not required by configuration" -Level INFO -EventSource $ScriptName
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
    
    Write-IntuneLog -Message "Updating Entra ID via Graph API..." -Level INFO -EventSource $ScriptName
    
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
        $result = Invoke-GraphApiWithRetry -MaxRetries $config.GraphAPI.RetryAttempts `
            -UseExponentialBackoff:$config.GraphAPI.UseExponentialBackoff `
            -ScriptBlock {
            
            Write-IntuneLog -Message "Getting Graph API token..." -Level INFO -EventSource $ScriptName
            $token = Get-GraphToken -TenantId $credentials.TenantId `
                -ClientId $credentials.ClientId `
                -ClientSecret $credentials.ClientSecret
            
            if ([string]::IsNullOrWhiteSpace($token)) {
                throw "Failed to obtain Graph API token"
            }
            
            Write-IntuneLog -Message "Updating device location in Entra ID..." -Level INFO -EventSource $ScriptName
            $updateResult = Update-DeviceLocationInGraph -DeviceId $azureDeviceId -Location $location -AccessToken $token
            
            if (-not $updateResult) {
                throw "Failed to update device location via Graph API"
            }
            
            return $updateResult
        }
        
        if ($result) {
            Write-IntuneLog -Message "SUCCESS: Device location updated in Entra ID" -Level SUCCESS -EventSource $ScriptName
            
            # Update registry with Graph update status
            New-ItemProperty -Path $config.Paths.RegistryPath -Name "GraphUpdateStatus" -Value "Success" -PropertyType String -Force | Out-Null
            New-ItemProperty -Path $config.Paths.RegistryPath -Name "GraphLastUpdate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -PropertyType String -Force | Out-Null
            
            Write-IntuneLog -Message "=== Remediation Script End: SUCCESS (Full Update) ===" -Level SUCCESS -EventSource $ScriptName
            exit $SUCCESS
        }
        else {
            throw "Graph API update failed without exception"
        }
    }
    catch {
        Write-IntuneLog -Message "ERROR: Graph API update failed: $_" -Level ERROR -EventSource $ScriptName
        
        # Update registry with failure status
        try {
            New-ItemProperty -Path $config.Paths.RegistryPath -Name "GraphUpdateStatus" -Value "Failed" -PropertyType String -Force | Out-Null
            New-ItemProperty -Path $config.Paths.RegistryPath -Name "GraphLastUpdate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -PropertyType String -Force | Out-Null
            New-ItemProperty -Path $config.Paths.RegistryPath -Name "GraphError" -Value $_.ToString() -PropertyType String -Force | Out-Null
        }
        catch {
            # Ignore registry update errors
        }
        
        # Send alert about Graph update failure
        Send-IntuneAlert -Message "Graph API update failed on $env:COMPUTERNAME: $_" -Severity Error -EventSource $ScriptName
        
        # Local update succeeded, but Graph failed - still exit with success for local remediation
        Write-IntuneLog -Message "=== Remediation Script End: SUCCESS (Local Only, Graph Failed) ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
}
catch {
    # Unhandled error
    Write-IntuneLog -Message "CRITICAL: Unhandled error in main execution: $_" -Level ERROR -EventSource $ScriptName
    Write-IntuneLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR -EventSource $ScriptName
    
    # Try to send alert
    try {
        Send-IntuneAlert -Message "Critical error in remediation script on $env:COMPUTERNAME: $_" -Severity Critical -EventSource $ScriptName
    }
    catch {
        # Alert sending failed too
    }
    
    Write-IntuneLog -Message "=== Remediation Script End: FAILURE ===" -Level ERROR -EventSource $ScriptName
    exit $FAILURE
}
#endregion