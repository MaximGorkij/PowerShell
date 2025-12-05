<#
.SYNOPSIS
  Common Functions Module for IP Location Detection
.DESCRIPTION
  Spoločné funkcie zdieľané medzi všetkými skriptami
.VERSION
  3.0
.AUTHOR
  TaurisIT
#>

#region Configuration Functions

function Get-Configuration {
    <#
    .SYNOPSIS
        Načíta konfiguráciu z JSON súboru
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot\config.json"
    )
    
    try {
        if (Test-Path $ConfigPath) {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            Write-Verbose "Configuration loaded from $ConfigPath"
            return $config
        }
        else {
            Write-Warning "Config file not found, using defaults"
            return Get-DefaultConfiguration
        }
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        return Get-DefaultConfiguration
    }
}

function Get-DefaultConfiguration {
    <#
    .SYNOPSIS
        Vráti default konfiguráciu
    #>
    return [PSCustomObject]@{
        Paths     = @{
            LogDirectory    = "C:\TaurisIT\Log\IPcheck"
            ScriptDirectory = "C:\TaurisIT\IPcheck"
            RegistryPath    = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
            LogModulePath   = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
        }
        GraphAPI  = @{
            RetryAttempts          = 3
            RetryDelaySeconds      = 2
            Timeout                = 30
            UseExponentialBackoff  = $true
            MaxDeviceSearchResults = 1000
        }
        Detection = @{
            CacheValidityHours          = 24
            RequireGraphUpdate          = $false
            AllowVPNDetection           = $true
            FallbackToLastKnownLocation = $true
        }
        Logging   = @{
            EnableFileLogging    = $true
            EnableEventLogging   = $true
            EnableConsoleLogging = $true
            MaxLogSizeMB         = 10
            LogRetentionDays     = 30
        }
        Security  = @{
            UseKeyVault        = $false
            KeyVaultName       = ""
            SecureRegistryPath = $true
        }
    }
}

#endregion

#region IP Location Map Functions

function Get-IPLocationMap {
    <#
    .SYNOPSIS
        Načíta a validuje IP Location mapu
    #>
    param(
        [string]$ConfigFile = "$PSScriptRoot\IPLocationMap.json"
    )
    
    try {
        if (Test-Path $ConfigFile) {
            Write-Verbose "Loading IP location map from $ConfigFile"
            
            $mapJson = Get-Content $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
            $map = @{}
            $duplicates = @()
            
            foreach ($property in $mapJson.PSObject.Properties) {
                $prefix = $property.Name
                $location = $property.Value
                
                # Validate IP prefix format
                if ($prefix -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.?$') {
                    Write-Warning "Invalid IP prefix format: $prefix (skipping)"
                    continue
                }
                
                # Check for duplicates
                if ($map.ContainsKey($prefix)) {
                    Write-Warning "Duplicate IP prefix: $prefix"
                    $duplicates += $prefix
                }
                
                $map[$prefix] = $location
            }
            
            if ($duplicates.Count -gt 0) {
                Write-Warning "Found $($duplicates.Count) duplicate IP prefixes"
            }
            
            Write-Verbose "Loaded $($map.Keys.Count) IP prefixes"
            return $map
        }
        else {
            Write-Warning "IP location map not found, using default map"
            return Get-DefaultIPLocationMap
        }
    }
    catch {
        Write-Error "Failed to load IP location map: $_"
        return Get-DefaultIPLocationMap
    }
}

function Get-DefaultIPLocationMap {
    <#
    .SYNOPSIS
        Vráti default IP location mapu
    #>
    return @{
        "10.10.0."   = "RS"
        "10.20.0."   = "RS"
        "10.20.11."  = "RS"
        "10.20.20."  = "Server"
        "10.20.30."  = "RS"
        "10.20.40."  = "RS"
        "10.20.50."  = "RS"
        "10.20.51."  = "RS"
        "10.20.70."  = "RS"
        "10.30.0."   = "SNV"
        "10.30.40."  = "SNV"
        "10.30.50."  = "SNV"
        "10.30.51."  = "SNV"
        "10.40.0."   = "NR"
        "10.40.40."  = "NR"
        "10.40.50."  = "NR"
        "10.40.51."  = "NR"
        "10.50.0."   = "LDCKE"
        "10.50.40."  = "LDCKE"
        "10.50.50."  = "LDCKE"
        "10.50.51."  = "LDCKE"
        "10.50.52."  = "LDCKE"
        "10.60.7."   = "RybaKE"
        "10.60.11."  = "RybaKE"
        "10.60.17."  = "RybaKE"
        "10.60.40."  = "RybaKE"
        "10.60.50."  = "RybaKE"
        "10.60.51."  = "RybaKE"
        "10.60.77."  = "RybaKE"
        "10.70.123." = "LDCKE"
        "10.80.0."   = "BB"
        "10.80.40."  = "BB"
        "10.80.50."  = "BB"
        "10.80.51."  = "BB"
        "10.82.0."   = "BA"
        "10.82.40."  = "BA"
        "10.82.50."  = "BA"
        "10.82.51."  = "BA"
        "10.82.70."  = "BA"
        "10.83.0."   = "ZA"
        "10.83.40."  = "ZA"
        "10.83.50."  = "ZA"
        "10.83.51."  = "ZA"
        "192.168.7." = "RybaKE"
    }
}

function Get-LocationFromIP {
    <#
    .SYNOPSIS
        Určí lokalitu zo IP adresy
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Map
    )
    
    # Sort prefixes by length (most specific first)
    $sortedPrefixes = $Map.Keys | Sort-Object -Descending { $_.Length }
    
    foreach ($prefix in $sortedPrefixes) {
        if ($IPAddress.StartsWith($prefix)) {
            Write-Verbose "IP prefix '$prefix' matches location '$($Map[$prefix])'"
            return $Map[$prefix]
        }
    }
    
    Write-Warning "No matching prefix found for IP '$IPAddress'"
    return $null
}

#endregion

#region Network Functions

function Get-PrimaryIPAddress {
    <#
    .SYNOPSIS
        Získa primárnu IP adresu zariadenia
    #>
    param(
        [switch]$IncludeVPN
    )
    
    try {
        Write-Verbose "Detecting primary IP address..."
        
        # Check for VPN connection first
        if (-not $IncludeVPN) {
            $vpnAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                $_.InterfaceDescription -match "VPN|WAN Miniport|Cisco AnyConnect|FortiClient|Pulse Secure|GlobalProtect|OpenVPN" -and
                $_.Status -eq 'Up'
            }
            
            if ($vpnAdapters) {
                Write-Warning "VPN connection detected: $($vpnAdapters.InterfaceDescription -join ', ')"
                Write-Warning "Skipping IP detection while on VPN"
                return $null
            }
        }
        
        # Method 1: Get-NetIPAddress (modern)
        $ipAddresses = @()
        
        try {
            $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.IPAddress -notmatch '^(169\.254\.|127\.|0\.)' -and
                $_.AddressState -eq 'Preferred' -and
                $_.PrefixOrigin -in @('Dhcp', 'Manual', 'WellKnown')
            }
        }
        catch {
            Write-Verbose "Get-NetIPAddress failed: $_"
        }
        
        # Method 2: WMI fallback
        if (-not $ipAddresses -or $ipAddresses.Count -eq 0) {
            Write-Verbose "Using WMI fallback for IP detection"
            
            $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration `
                -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
            
            foreach ($adapter in $adapters) {
                if ($adapter.IPAddress) {
                    foreach ($ip in $adapter.IPAddress) {
                        if ($ip -match '^\d+\.\d+\.\d+\.\d+$' -and 
                            $ip -notmatch '^(169\.254\.|127\.|0\.)') {
                            
                            $ipAddresses += [PSCustomObject]@{
                                IPAddress       = $ip
                                InterfaceMetric = 0
                                InterfaceAlias  = $adapter.Description
                            }
                        }
                    }
                }
            }
        }
        
        if (-not $ipAddresses -or $ipAddresses.Count -eq 0) {
            Write-Warning "No valid IPv4 addresses found"
            
            # Debug information
            Write-Verbose "DEBUG: Network adapter information:"
            Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Verbose "  Adapter: $($_.Name), Status: $($_.Status), Description: $($_.InterfaceDescription)"
            }
            
            return $null
        }
        
        Write-Verbose "Found $($ipAddresses.Count) IP address(es)"
        
        # Prefer private network IPs
        $privateIPs = $ipAddresses | Where-Object { 
            $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
        }
        
        if ($privateIPs) {
            # Sort by: 10.x.x.x first, then by InterfaceMetric
            $primaryIP = $privateIPs | 
            Sort-Object -Property @{Expression = { $_.IPAddress -match '^10\.' }; Descending = $true },
            InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress
            
            Write-Verbose "Selected private IP: $primaryIP"
        }
        else {
            $primaryIP = $ipAddresses | 
            Sort-Object -Property InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress
            
            Write-Verbose "Selected public IP: $primaryIP"
        }
        
        return $primaryIP
    }
    catch {
        Write-Error "Failed to get IP address: $_"
        return $null
    }
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Testuje sieťovú konektivitu
    #>
    param(
        [string]$TestHost = "login.microsoftonline.com",
        [int]$TimeoutSeconds = 5
    )
    
    try {
        Write-Verbose "Testing network connectivity to $TestHost"
        
        $result = Test-Connection -ComputerName $TestHost -Count 1 -Quiet -ErrorAction Stop
        
        if ($result) {
            Write-Verbose "Network connectivity: OK"
            return $true
        }
        else {
            Write-Warning "Network connectivity: Failed"
            return $false
        }
    }
    catch {
        Write-Warning "Network connectivity test failed: $_"
        return $false
    }
}

#endregion

#region Device Information Functions

function Get-DeviceSerialNumber {
    <#
    .SYNOPSIS
        Získa serial number zariadenia
    #>
    try {
        $serial = $null
        
        # 1. BIOS (most reliable)
        $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
        if ($bios -and $bios.SerialNumber) {
            $serial = $bios.SerialNumber.Trim()
            Write-Verbose "Serial number from BIOS: $serial"
        }
        
        # 2. Computer System Product
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $csProduct = Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
            if ($csProduct -and $csProduct.IdentifyingNumber) {
                $serial = $csProduct.IdentifyingNumber.Trim()
                Write-Verbose "Serial number from ComputerSystemProduct: $serial"
            }
        }
        
        # 3. Registry (for VMs)
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $regSerial = (Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" `
                    -Name "SystemSerialNumber" -ErrorAction SilentlyContinue).SystemSerialNumber
            if ($regSerial) {
                $serial = $regSerial.Trim()
                Write-Verbose "Serial number from registry: $serial"
            }
        }
        
        # Validate serial number (skip invalid VM serial numbers)
        if ($serial -match "System Serial Number|To Be Filled|Default|O\.E\.M\.|None|0{5,}|Not Specified") {
            Write-Warning "Invalid/placeholder serial number detected: $serial"
            return $null
        }
        
        if ([string]::IsNullOrWhiteSpace($serial)) {
            Write-Warning "Could not retrieve serial number"
            return $null
        }
        
        return $serial
    }
    catch {
        Write-Error "Error getting serial number: $_"
        return $null
    }
}

function Get-AzureADDeviceId {
    <#
    .SYNOPSIS
        Získa Azure AD Device ID
    #>
    try {
        Write-Verbose "Getting Azure AD Device ID..."
        
        $deviceId = $null
        
        # 1. dsregcmd (for Azure AD Joined devices)
        try {
            $dsregcmdOutput = dsregcmd /status 2>$null
            if ($dsregcmdOutput) {
                $deviceIdLine = $dsregcmdOutput | Where-Object { $_ -match "^\s*DeviceId\s*:" }
                if ($deviceIdLine) {
                    $deviceId = ($deviceIdLine -split ":")[1].Trim()
                    Write-Verbose "Azure AD Device ID from dsregcmd: $deviceId"
                }
            }
        }
        catch {
            Write-Verbose "dsregcmd not available or failed"
        }
        
        # 2. Registry - CloudDomainJoin
        if ([string]::IsNullOrWhiteSpace($deviceId)) {
            $cloudJoinPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo"
            
            if (Test-Path $cloudJoinPath) {
                $subKeys = Get-ChildItem -Path $cloudJoinPath -ErrorAction SilentlyContinue
                
                foreach ($key in $subKeys) {
                    $id = (Get-ItemProperty -Path $key.PSPath -Name "DeviceId" -ErrorAction SilentlyContinue).DeviceId
                    if ($id) {
                        $deviceId = $id
                        Write-Verbose "Azure AD Device ID from registry: $deviceId"
                        break
                    }
                }
            }
        }
        
        # 3. Intune Management Extension
        if ([string]::IsNullOrWhiteSpace($deviceId)) {
            $intunePath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Settings"
            
            if (Test-Path $intunePath) {
                $id = (Get-ItemProperty -Path $intunePath -Name "EntDMID" -ErrorAction SilentlyContinue).EntDMID
                if ($id) {
                    $deviceId = $id
                    Write-Verbose "Device ID from Intune: $deviceId"
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($deviceId)) {
            Write-Warning "Could not retrieve Azure AD Device ID"
            return $null
        }
        
        return $deviceId
    }
    catch {
        Write-Error "Error getting Azure AD Device ID: $_"
        return $null
    }
}

function Get-DeviceModel {
    <#
    .SYNOPSIS
        Získa model zariadenia
    #>
    try {
        $cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs) {
            $manufacturer = $cs.Manufacturer
            $model = $cs.Model
            
            Write-Verbose "Device: $manufacturer $model"
            return "$manufacturer $model"
        }
        
        return "Unknown"
    }
    catch {
        Write-Error "Error getting device model: $_"
        return "Unknown"
    }
}

function Test-IsVirtualMachine {
    <#
    .SYNOPSIS
        Zistí či je zariadenie virtuálna mašina
    #>
    try {
        $cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
        
        if ($cs) {
            $manufacturer = $cs.Manufacturer
            $model = $cs.Model
            
            # Check common VM identifiers
            $vmIndicators = @(
                "VMware",
                "Virtual",
                "Microsoft Corporation",
                "Xen",
                "QEMU",
                "VirtualBox",
                "Parallels"
            )
            
            foreach ($indicator in $vmIndicators) {
                if ($manufacturer -match $indicator -or $model -match $indicator) {
                    Write-Verbose "Virtual machine detected: $manufacturer $model"
                    return $true
                }
            }
        }
        
        Write-Verbose "Physical device detected"
        return $false
    }
    catch {
        Write-Verbose "Could not determine if VM"
        return $false
    }
}

#endregion

#region Registry Functions

function Initialize-RegistryPath {
    <#
    .SYNOPSIS
        Inicializuje a zabezpečí registry path
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,
        
        [switch]$SecurePath
    )
    
    try {
        # Create path if doesn't exist
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Registry path created: $RegistryPath"
        }
        
        # Secure the registry path
        if ($SecurePath) {
            try {
                $acl = Get-Acl $RegistryPath
                $acl.SetAccessRuleProtection($true, $false) # Disable inheritance
                
                # Add SYSTEM full control
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
                $systemRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $systemSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
                )
                $acl.AddAccessRule($systemRule)
                
                # Add Administrators full control
                $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
                $adminRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $adminSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
                )
                $acl.AddAccessRule($adminRule)
                
                Set-Acl -Path $RegistryPath -AclObject $acl
                Write-Verbose "Registry path secured"
            }
            catch {
                Write-Warning "Could not secure registry path: $_"
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to initialize registry path: $_"
        return $false
    }
}

function Save-LocationToRegistry {
    <#
    .SYNOPSIS
        Uloží lokalitu do registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,
        
        [string]$SerialNumber,
        
        [string]$DeviceModel
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        Set-ItemProperty -Path $RegistryPath -Name "CurrentLocation" -Value $Location -Type String -Force
        Set-ItemProperty -Path $RegistryPath -Name "DetectedIP" -Value $IPAddress -Type String -Force
        Set-ItemProperty -Path $RegistryPath -Name "LastUpdated" -Value $timestamp -Type String -Force
        Set-ItemProperty -Path $RegistryPath -Name "ComputerName" -Value $env:COMPUTERNAME -Type String -Force
        
        if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
            Set-ItemProperty -Path $RegistryPath -Name "SerialNumber" -Value $SerialNumber -Type String -Force
        }
        
        if (-not [string]::IsNullOrWhiteSpace($DeviceModel)) {
            Set-ItemProperty -Path $RegistryPath -Name "DeviceModel" -Value $DeviceModel -Type String -Force
        }
        
        # Version tracking
        Set-ItemProperty -Path $RegistryPath -Name "ScriptVersion" -Value "3.0" -Type String -Force
        
        Write-Verbose "Location '$Location' saved to registry (IP: $IPAddress)"
        return $true
    }
    catch {
        Write-Error "Failed to save location to registry: $_"
        return $false
    }
}

function Get-LocationFromRegistry {
    <#
    .SYNOPSIS
        Získa lokalitu z registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )
    
    try {
        if (-not (Test-Path $RegistryPath)) {
            return $null
        }
        
        $location = (Get-ItemProperty -Path $RegistryPath -Name "CurrentLocation" -ErrorAction SilentlyContinue).CurrentLocation
        
        if ($location) {
            $detectedIP = (Get-ItemProperty -Path $RegistryPath -Name "DetectedIP" -ErrorAction SilentlyContinue).DetectedIP
            $lastUpdated = (Get-ItemProperty -Path $RegistryPath -Name "LastUpdated" -ErrorAction SilentlyContinue).LastUpdated
            
            Write-Verbose "Location from registry: $location (IP: $detectedIP, Updated: $lastUpdated)"
        }
        
        return $location
    }
    catch {
        Write-Error "Failed to read location from registry: $_"
        return $null
    }
}

function Get-RegistryLocationData {
    <#
    .SYNOPSIS
        Získa všetky location data z registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )
    
    try {
        if (-not (Test-Path $RegistryPath)) {
            return $null
        }
        
        $data = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
        
        if ($data) {
            return [PSCustomObject]@{
                CurrentLocation = $data.CurrentLocation
                DetectedIP      = $data.DetectedIP
                LastUpdated     = $data.LastUpdated
                ComputerName    = $data.ComputerName
                SerialNumber    = $data.SerialNumber
                DeviceModel     = $data.DeviceModel
                ScriptVersion   = $data.ScriptVersion
            }
        }
        
        return $null
    }
    catch {
        Write-Error "Failed to read registry data: $_"
        return $null
    }
}

function Test-LocationCacheValid {
    <#
    .SYNOPSIS
        Testuje či je cache lokality stále platný
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,
        
        [int]$ValidityHours = 24
    )
    
    try {
        if (-not (Test-Path $RegistryPath)) {
            Write-Verbose "Registry path does not exist: $RegistryPath"
            return $false
        }
        
        $lastUpdated = (Get-ItemProperty -Path $RegistryPath -Name "LastUpdated" -ErrorAction SilentlyContinue).LastUpdated
        
        if ([string]::IsNullOrWhiteSpace($lastUpdated)) {
            Write-Verbose "LastUpdated value is empty or null"
            return $false
        }
        
        Write-Verbose "LastUpdated value from registry: $lastUpdated"
        
        # Try to parse the datetime
        $lastUpdateDate = $null
        $parsed = $false
        
        try {
            $lastUpdateDate = [datetime]::ParseExact($lastUpdated, "yyyy-MM-dd HH:mm:ss", $null)
            $parsed = $true
        }
        catch {
            Write-Verbose "Could not parse timestamp: $lastUpdated, trying alternative format..."
            # Try alternative parsing
            try {
                $lastUpdateDate = [datetime]::Parse($lastUpdated)
                $parsed = $true
            }
            catch {
                Write-Verbose "Alternative parsing also failed"
                $parsed = $false
            }
        }
        
        if ($parsed -and $lastUpdateDate) {
            $hoursSinceUpdate = ((Get-Date) - $lastUpdateDate).TotalHours
            
            Write-Verbose "Last update: $lastUpdateDate ($([math]::Round($hoursSinceUpdate, 2)) hours ago)"
            
            if ($hoursSinceUpdate -le $ValidityHours) {
                Write-Verbose "Location cache is valid ($([math]::Round($hoursSinceUpdate, 2)) hours old, max: $ValidityHours)"
                return $true
            }
            else {
                Write-Verbose "Location cache expired ($([math]::Round($hoursSinceUpdate, 2)) hours old, max: $ValidityHours)"
                return $false
            }
        }
        else {
            Write-Verbose "Could not parse LastUpdated timestamp: $lastUpdated"
            return $false
        }
    }
    catch {
        Write-Error "Failed to validate location cache: $_"
        return $false
    }
}

function Clear-RegistryLocationData {
    <#
    .SYNOPSIS
        Vyčistí location data z registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )
    
    try {
        if (Test-Path $RegistryPath) {
            Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
            Write-Verbose "Registry location data cleared"
            return $true
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to clear registry data: $_"
        return $false
    }
}

#endregion

#region Credential Functions

function Get-EnvCredentials {
    <#
    .SYNOPSIS
        Načíta credentials z .env súboru
    #>
    param(
        [string]$EnvFile = "$PSScriptRoot\.env"
    )
    
    try {
        if (-not (Test-Path $EnvFile)) {
            Write-Warning ".env file not found at $EnvFile"
            return $null
        }
        
        Write-Verbose "Loading credentials from .env file"
        
        $envContent = Get-Content $EnvFile -ErrorAction Stop
        $envVars = @{}
        
        foreach ($line in $envContent) {
            # Skip comments and empty lines
            if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Parse KEY=VALUE
            if ($line -match '^\s*([^=]+)\s*=\s*(.*?)\s*$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Remove quotes
                $value = $value -replace '^["'']|["'']$', ''
                
                $envVars[$key] = $value
            }
        }
        
        $tenantId = $envVars["GRAPH_TENANT_ID"]
        $clientId = $envVars["GRAPH_CLIENT_ID"]
        $clientSecret = $envVars["GRAPH_CLIENT_SECRET"]
        
        if ([string]::IsNullOrWhiteSpace($tenantId) -or 
            [string]::IsNullOrWhiteSpace($clientId) -or 
            [string]::IsNullOrWhiteSpace($clientSecret)) {
            
            Write-Warning "Incomplete credentials in .env file"
            return $null
        }
        
        Write-Verbose "Credentials loaded successfully"
        
        return @{
            TenantId     = $tenantId
            ClientId     = $clientId
            ClientSecret = $clientSecret
        }
    }
    catch {
        Write-Error "Failed to load .env credentials: $_"
        return $null
    }
}

function Test-EnvCredentials {
    <#
    .SYNOPSIS
        Testuje či sú credentials validné
    #>
    param(
        [string]$EnvFile = "$PSScriptRoot\.env"
    )
    
    $credentials = Get-EnvCredentials -EnvFile $EnvFile
    
    if ($credentials) {
        Write-Verbose "Credentials present and loaded"
        return $true
    }
    else {
        Write-Warning "Credentials missing or invalid"
        return $false
    }
}

#endregion

#region Utility Functions

function Get-ScriptVersion {
    <#
    .SYNOPSIS
        Vráti verziu skriptu
    #>
    return "3.0"
}

function Get-OSVersion {
    <#
    .SYNOPSIS
        Získa verziu OS
    #>
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
        
        if ($os) {
            return "$($os.Caption) (Build $($os.BuildNumber))"
        }
        
        return [System.Environment]::OSVersion.VersionString
    }
    catch {
        return "Unknown"
    }
}

function Get-PowerShellVersion {
    <#
    .SYNOPSIS
        Získa verziu PowerShell
    #>
    return "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Testuje či beží s admin právami
    #>
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-ComputerDomain {
    <#
    .SYNOPSIS
        Získa domain zariadenia
    #>
    try {
        $cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
        
        if ($cs) {
            if ($cs.PartOfDomain) {
                return $cs.Domain
            }
            else {
                return "WORKGROUP"
            }
        }
        
        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formátuje veľkosť súboru
    #>
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes
    )
    
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes Bytes"
    }
}

function Get-TimeSince {
    <#
    .SYNOPSIS
        Vráti čas od daného dátumu v human-readable formáte
    #>
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime
    )
    
    $timeSpan = (Get-Date) - $DateTime
    
    if ($timeSpan.TotalDays -ge 1) {
        return "{0:N1} days ago" -f $timeSpan.TotalDays
    }
    elseif ($timeSpan.TotalHours -ge 1) {
        return "{0:N1} hours ago" -f $timeSpan.TotalHours
    }
    elseif ($timeSpan.TotalMinutes -ge 1) {
        return "{0:N0} minutes ago" -f $timeSpan.TotalMinutes
    }
    else {
        return "{0:N0} seconds ago" -f $timeSpan.TotalSeconds
    }
}

function New-RandomString {
    <#
    .SYNOPSIS
        Generuje náhodný string
    #>
    param(
        [int]$Length = 16,
        [switch]$IncludeSpecialChars
    )
    
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    
    if ($IncludeSpecialChars) {
        $chars += '!@#$%^&*()_+-='
    }
    
    $random = 1..$Length | ForEach-Object { Get-Random -Maximum $chars.Length }
    return -join ($random | ForEach-Object { $chars[$_] })
}

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Konvertuje PSCustomObject na Hashtable
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$InputObject
    )
    
    process {
        $hash = @{}
        
        $InputObject.PSObject.Properties | ForEach-Object {
            $hash[$_.Name] = $_.Value
        }
        
        return $hash
    }
}

function Test-RegistryValue {
    <#
    .SYNOPSIS
        Testuje či registry value existuje
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Zapisuje farebný output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 
            'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 
            'Magenta', 'Yellow', 'White')]
        [string]$ForegroundColor = 'White',
        
        [switch]$NoNewLine
    )
    
    $params = @{
        Object          = $Message
        ForegroundColor = $ForegroundColor
    }
    
    if ($NoNewLine) {
        $params.NoNewLine = $true
    }
    
    Write-Host @params
}

#endregion

#region Validation Functions

function Test-IPAddress {
    <#
    .SYNOPSIS
        Validuje IP adresu
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress
    )
    
    try {
        $ip = [System.Net.IPAddress]::Parse($IPAddress)
        return $true
    }
    catch {
        return $false
    }
}

function Test-JsonValid {
    <#
    .SYNOPSIS
        Testuje či je JSON validný
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonString
    )
    
    try {
        $null = ConvertFrom-Json -InputObject $JsonString -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-PathWritable {
    <#
    .SYNOPSIS
        Testuje či je path zapisovateľný
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        $testFile = Join-Path $Path "test_write_$(Get-Random).tmp"
        
        # Try to create test file
        $null = New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop
        
        # Clean up
        Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region Alias Definitions
Set-Alias Load-Configuration Get-Configuration
Set-Alias Load-IPLocationMap Get-IPLocationMap
Set-Alias Load-EnvCredentials Get-EnvCredentials
#endregion

#region Export Module Members
Export-ModuleMember -Function `
    Get-Configuration, `
    Get-DefaultConfiguration, `
    Get-IPLocationMap, `
    Get-DefaultIPLocationMap, `
    Get-LocationFromIP, `
    Get-PrimaryIPAddress, `
    Test-NetworkConnectivity, `
    Get-DeviceSerialNumber, `
    Get-AzureADDeviceId, `
    Get-DeviceModel, `
    Test-IsVirtualMachine, `
    Initialize-RegistryPath, `
    Save-LocationToRegistry, `
    Get-LocationFromRegistry, `
    Get-RegistryLocationData, `
    Test-LocationCacheValid, `
    Clear-RegistryLocationData, `
    Get-EnvCredentials, `
    Test-EnvCredentials, `
    Get-ScriptVersion, `
    Get-OSVersion, `
    Get-PowerShellVersion, `
    Test-IsAdministrator, `
    Get-ComputerDomain, `
    Format-FileSize, `
    Get-TimeSince, `
    New-RandomString, `
    ConvertTo-Hashtable, `
    Test-RegistryValue, `
    Write-ColorOutput, `
    Test-IPAddress, `
    Test-JsonValid, `
    Test-PathWritable `
    -Alias *
#endregion