<#
.SYNOPSIS
  Enhanced Intune Remediation Script
.VERSION
  3.0
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$SUCCESS = 0
$FAILURE = 1

try {
    # Load modules
    $mods = @("$PSScriptRoot\CommonFunctions.psm1", "$PSScriptRoot\GraphHelper.psm1", "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1")
    foreach ($m in $mods) { if (Test-Path $m) { Import-Module $m -Force } }
    
    # Config
    $cfg = Load-Configuration
    
    # Init logging
    Initialize-LogSystem -LogDirectory $cfg.Paths.LogDirectory -EventSource $ScriptName
    
    Write-IntuneLog -Message "=== Remediation Start ===" -Level INFO -EventSource $ScriptName
    Write-IntuneLog -Message "Version: 3.0 | Computer: $env:COMPUTERNAME" -Level INFO -EventSource $ScriptName
    
    Clear-OldLogs -RetentionDays $cfg.Logging.LogRetentionDays
    
    # Init registry
    $regOk = if ($cfg.Security.SecureRegistryPath) {
        Initialize-RegistryPath -RegistryPath $cfg.Paths.RegistryPath -SecurePath
    }
    else {
        Initialize-RegistryPath -RegistryPath $cfg.Paths.RegistryPath
    }
    
    if (-not $regOk) { throw "Registry init failed" }
    
    # Load IP map
    $ipMap = Load-IPLocationMap -ConfigFile "$PSScriptRoot\IPLocationMap.json"
    if (-not $ipMap) { throw "Failed to load IP map" }
    
    # Get IP
    $ip = Get-PrimaryIPAddress -IncludeVPN:(-not $cfg.Detection.AllowVPNDetection)
    if (-not $ip) { throw "No IP detected" }
    
    Write-IntuneLog -Message "IP: $ip" -Level INFO -EventSource $ScriptName
    
    # Get location
    $loc = Get-LocationFromIP -IPAddress $ip -Map $ipMap
    if (-not $loc) { throw "IP not in map" }
    
    Write-IntuneLog -Message "Location: $loc" -Level INFO -EventSource $ScriptName
    
    # Save to registry
    $serial = Get-DeviceSerialNumber
    $saved = Save-LocationToRegistry -RegistryPath $cfg.Paths.RegistryPath -Location $loc -IPAddress $ip -SerialNumber $serial
    
    if (-not $saved) { throw "Failed to save to registry" }
    
    Write-IntuneLog -Message "Saved to registry" -Level SUCCESS -EventSource $ScriptName
    
    # Graph API update
    if (-not $cfg.Detection.RequireGraphUpdate) {
        Write-IntuneLog -Message "Graph update not required" -Level INFO -EventSource $ScriptName
        exit $SUCCESS
    }
    
    $creds = Load-EnvCredentials -EnvFile "$PSScriptRoot\.env"
    if (-not $creds) {
        Write-IntuneLog -Message "No credentials, skipping Graph" -Level WARN -EventSource $ScriptName
        exit $SUCCESS
    }
    
    $devId = Get-AzureADDeviceId
    if (-not $devId) {
        Write-IntuneLog -Message "No Device ID, skipping Graph" -Level WARN -EventSource $ScriptName
        exit $SUCCESS
    }
    
    Write-IntuneLog -Message "Device ID: $devId" -Level INFO -EventSource $ScriptName
    
    # Graph update with retry
    try {
        Invoke-GraphApiWithRetry -MaxRetries $cfg.GraphAPI.RetryAttempts -UseExponentialBackoff:$cfg.GraphAPI.UseExponentialBackoff -ScriptBlock {
            $token = Get-GraphToken -TenantId $creds.TenantId -ClientId $creds.ClientId -ClientSecret $creds.ClientSecret
            if (-not $token) { throw "No token" }
            
            if (-not (Test-GraphConnection -AccessToken $token)) { throw "Graph test failed" }
            
            $dev = Find-DeviceInGraph -AccessToken $token -DeviceId $devId -ComputerName $env:COMPUTERNAME -MaxResults $cfg.GraphAPI.MaxDeviceSearchResults
            if (-not $dev) { throw "Device not found" }
            
            Write-IntuneLog -Message "Device: $($dev.displayName) ($($dev.id))" -Level INFO -EventSource $ScriptName
            
            $currentEntraLoc = $dev.extensionAttributes.extensionAttribute1
            if ($currentEntraLoc -eq $loc) {
                Write-IntuneLog -Message "Entra location already correct" -Level INFO -EventSource $ScriptName
                return
            }
            
            $updated = Update-DeviceInGraph -AccessToken $token -DeviceObjectId $dev.id -Location $loc -SerialNumber $serial
            
            if ($updated) {
                Write-IntuneLog -Message "Entra updated" -Level SUCCESS -EventSource $ScriptName
                $slog = Join-Path $cfg.Paths.LogDirectory "GraphUpdate_Success.log"
                Add-Content -Path $slog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($dev.displayName), $loc, $devId" -ErrorAction SilentlyContinue
            }
        }
        
        Write-IntuneLog -Message "=== SUCCESS ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
    catch {
        $err = $_.Exception.Message
        Write-IntuneLog -Message "Graph failed: $err" -Level WARN -EventSource $ScriptName
        
        $elog = Join-Path $cfg.Paths.LogDirectory "GraphUpdate_Errors.log"
        Add-Content -Path $elog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $env:COMPUTERNAME, $err" -ErrorAction SilentlyContinue
        
        if ($err -match "404") {
            Write-IntuneLog -Message "Device not in Entra or not synced" -Level WARN -EventSource $ScriptName
        }
        elseif ($err -match "401|403") {
            Write-IntuneLog -Message "Auth error - check permissions" -Level WARN -EventSource $ScriptName
        }
        
        Write-IntuneLog -Message "=== SUCCESS (Local only) ===" -Level SUCCESS -EventSource $ScriptName
        exit $SUCCESS
    }
}
catch {
    Write-IntuneLog -Message "ERROR: $($_.Exception.Message)" -Level ERROR -EventSource $ScriptName
    exit $FAILURE
}
finally {
    Clear-GraphTokenCache
    if (Get-Module CommonFunctions) { Remove-Module CommonFunctions -Force -ErrorAction SilentlyContinue }
    if (Get-Module GraphHelper) { Remove-Module GraphHelper -Force -ErrorAction SilentlyContinue }
}