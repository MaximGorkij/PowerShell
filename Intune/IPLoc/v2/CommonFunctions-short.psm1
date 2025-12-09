<#
.SYNOPSIS
  Common Functions Module for IP Location Detection
.VERSION
  3.0
.AUTHOR
  TaurisIT
#>

#region Configuration
function Get-Configuration {
    param([string]$ConfigPath = "$PSScriptRoot\config.json")
    
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    
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
            MaxLogSizeMB     = 10
            LogRetentionDays = 30
        }
        Security  = @{ SecureRegistryPath = $true }
    }
}

function Get-IPLocationMap {
    param([string]$ConfigFile = "$PSScriptRoot\IPLocationMap.json")
    
    if (Test-Path $ConfigFile) {
        $mapJson = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $map = @{}
        $mapJson.PSObject.Properties | ForEach-Object { $map[$_.Name] = $_.Value }
        return $map
    }
    
    return @{
        "10.10.0." = "RS"; "10.20.0." = "RS"; "10.20.11." = "RS"; "10.20.20." = "Server"
        "10.20.30." = "RS"; "10.20.40." = "RS"; "10.20.50." = "RS"; "10.20.51." = "RS"
        "10.20.70." = "RS"; "10.30.0." = "SNV"; "10.30.40." = "SNV"; "10.30.50." = "SNV"
        "10.30.51." = "SNV"; "10.40.0." = "NR"; "10.40.40." = "NR"; "10.40.50." = "NR"
        "10.40.51." = "NR"; "10.50.0." = "LDCKE"; "10.50.40." = "LDCKE"; "10.50.50." = "LDCKE"
        "10.50.51." = "LDCKE"; "10.50.52." = "LDCKE"; "10.60.7." = "RybaKE"; "10.60.11." = "RybaKE"
        "10.60.17." = "RybaKE"; "10.60.40." = "RybaKE"; "10.60.50." = "RybaKE"; "10.60.51." = "RybaKE"
        "10.60.77." = "RybaKE"; "10.70.123." = "LDCKE"; "10.80.0." = "BB"; "10.80.40." = "BB"
        "10.80.50." = "BB"; "10.80.51." = "BB"; "10.82.0." = "BA"; "10.82.40." = "BA"
        "10.82.50." = "BA"; "10.82.51." = "BA"; "10.82.70." = "BA"; "10.83.0." = "ZA"
        "10.83.40." = "ZA"; "10.83.50." = "ZA"; "10.83.51." = "ZA"; "192.168.7." = "RybaKE"
    }
}

function Get-LocationFromIP {
    param([string]$IPAddress, [hashtable]$Map)
    
    foreach ($prefix in ($Map.Keys | Sort-Object -Descending { $_.Length })) {
        if ($IPAddress.StartsWith($prefix)) { return $Map[$prefix] }
    }
    return $null
}
#endregion

#region Network
function Get-PrimaryIPAddress {
    param([switch]$IncludeVPN)
    
    if (-not $IncludeVPN) {
        $vpn = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
            $_.InterfaceDescription -match "VPN|Cisco|FortiClient|Pulse|GlobalProtect" -and $_.Status -eq 'Up'
        }
        if ($vpn) { return $null }
    }
    
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { 
        $_.IPAddress -notmatch '^(169\.254\.|127\.|0\.)' -and $_.AddressState -eq 'Preferred'
    }
    
    if (-not $ips) {
        $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue
        foreach ($a in $adapters) {
            foreach ($ip in $a.IPAddress) {
                if ($ip -match '^\d+\.\d+\.\d+\.\d+$' -and $ip -notmatch '^(169\.254\.|127\.)') {
                    return $ip
                }
            }
        }
        return $null
    }
    
    $private = $ips | Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' }
    
    if ($private) {
        return ($private | Sort-Object -Property @{Expression = { $_.IPAddress -match '^10\.' }; Descending = $true }, InterfaceMetric | Select-Object -First 1).IPAddress
    }
    
    return ($ips | Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress
}
#endregion

#region Device
function Get-DeviceSerialNumber {
    $bios = Get-WmiObject Win32_BIOS -ErrorAction SilentlyContinue
    if ($bios -and $bios.SerialNumber) {
        $s = $bios.SerialNumber.Trim()
        if ($s -notmatch "System Serial|To Be Filled|Default|O\.E\.M\.|None|0{5,}") { return $s }
    }
    
    $cs = Get-WmiObject Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    if ($cs -and $cs.IdentifyingNumber) {
        $s = $cs.IdentifyingNumber.Trim()
        if ($s -notmatch "System Serial|To Be Filled|Default|O\.E\.M\.|None") { return $s }
    }
    
    return $null
}

function Get-AzureADDeviceId {
    try {
        $out = dsregcmd /status 2>$null
        if ($out) {
            $line = $out | Where-Object { $_ -match "^\s*DeviceId\s*:" }
            if ($line) { return ($line -split ":")[1].Trim() }
        }
    }
    catch {}
    
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo"
    if (Test-Path $path) {
        foreach ($key in (Get-ChildItem $path -ErrorAction SilentlyContinue)) {
            $id = (Get-ItemProperty $key.PSPath -Name "DeviceId" -ErrorAction SilentlyContinue).DeviceId
            if ($id) { return $id }
        }
    }
    
    return $null
}
#endregion

#region Registry
function Initialize-RegistryPath {
    param([string]$RegistryPath, [switch]$SecurePath)
    
    if (-not (Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }
    
    if ($SecurePath) {
        try {
            $acl = Get-Acl $RegistryPath
            $acl.SetAccessRuleProtection($true, $false)
            
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
            $systemRule = New-Object System.Security.AccessControl.RegistryAccessRule($systemSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($systemRule)
            
            $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            $adminRule = New-Object System.Security.AccessControl.RegistryAccessRule($adminSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($adminRule)
            
            Set-Acl -Path $RegistryPath -AclObject $acl
        }
        catch {}
    }
    
    return $true
}

function Save-LocationToRegistry {
    param([string]$RegistryPath, [string]$Location, [string]$IPAddress, [string]$SerialNumber)
    
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    Set-ItemProperty -Path $RegistryPath -Name "CurrentLocation" -Value $Location -Type String -Force
    Set-ItemProperty -Path $RegistryPath -Name "DetectedIP" -Value $IPAddress -Type String -Force
    Set-ItemProperty -Path $RegistryPath -Name "LastUpdated" -Value $ts -Type String -Force
    Set-ItemProperty -Path $RegistryPath -Name "ComputerName" -Value $env:COMPUTERNAME -Type String -Force
    
    if ($SerialNumber) {
        Set-ItemProperty -Path $RegistryPath -Name "SerialNumber" -Value $SerialNumber -Type String -Force
    }
    
    return $true
}

function Get-LocationFromRegistry {
    param([string]$RegistryPath)
    
    if (-not (Test-Path $RegistryPath)) { return $null }
    return (Get-ItemProperty -Path $RegistryPath -Name "CurrentLocation" -ErrorAction SilentlyContinue).CurrentLocation
}

function Test-LocationCacheValid {
    param([string]$RegistryPath, [int]$ValidityHours = 24)
    
    if (-not (Test-Path $RegistryPath)) { return $false }
    
    $lu = (Get-ItemProperty -Path $RegistryPath -Name "LastUpdated" -ErrorAction SilentlyContinue).LastUpdated
    if (-not $lu) { return $false }
    
    $date = $null
    if ([datetime]::TryParseExact($lu, "yyyy-MM-dd HH:mm:ss", $null, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
        return (((Get-Date) - $date).TotalHours -le $ValidityHours)
    }
    
    return $false
}
#endregion

#region Credentials
function Get-EnvCredentials {
    param([string]$EnvFile = "$PSScriptRoot\.env")
    
    if (-not (Test-Path $EnvFile)) { return $null }
    
    $vars = @{}
    foreach ($line in (Get-Content $EnvFile)) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*([^=]+)\s*=\s*(.*?)\s*$') {
            $vars[$matches[1].Trim()] = ($matches[2].Trim() -replace '^["'']|["'']$', '')
        }
    }
    
    $tid = $vars["GRAPH_TENANT_ID"]
    $cid = $vars["GRAPH_CLIENT_ID"]
    $sec = $vars["GRAPH_CLIENT_SECRET"]
    
    if ($tid -and $cid -and $sec) {
        return @{ TenantId = $tid; ClientId = $cid; ClientSecret = $sec }
    }
    
    return $null
}
#endregion

Export-ModuleMember -Function Get-Configuration, Get-IPLocationMap, Get-LocationFromIP, `
    Get-PrimaryIPAddress, Get-DeviceSerialNumber, Get-AzureADDeviceId, `
    Initialize-RegistryPath, Save-LocationToRegistry, Get-LocationFromRegistry, `
    Test-LocationCacheValid, Get-EnvCredentials