<#
.SYNOPSIS
  Health Check Script for IP Location Detection
.DESCRIPTION
  Kontroluje stav inštalácie, konfigurácie a funkčnosti systému
.VERSION
  3.0
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param(
    [switch]$Detailed,
    [switch]$TestGraphAPI,
    [switch]$ExportReport
)

#region Configuration
$ScriptName = "HealthCheck"
$HealthCheckPaths = @{
    ScriptDir    = "C:\TaurisIT\IPcheck"
    LogDir       = "C:\TaurisIT\Log\IPcheck"
    RegistryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
    ModuleDir    = "C:\Program Files\WindowsPowerShell\Modules"
}
#endregion

#region Functions
function Write-HealthLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        'SUCCESS' { 'Green' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    
    Write-Host "$timestamp [$Level] $Message" -ForegroundColor $color
}

function Test-Component {
    param(
        [string]$Name,
        [scriptblock]$TestScript
    )
    
    Write-Host "Testing: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan -NoNewline
    Write-Host " ... " -NoNewline
    
    try {
        $result = & $TestScript
        
        if ($result.Status -eq "OK") {
            Write-Host "OK" -ForegroundColor Green
            if ($Detailed -and $result.Details) {
                Write-Host "  $($result.Details)" -ForegroundColor Gray
            }
            return @{ Name = $Name; Status = "OK"; Details = $result.Details }
        }
        elseif ($result.Status -eq "WARNING") {
            Write-Host "WARNING" -ForegroundColor Yellow
            if ($result.Details) {
                Write-Host "  $($result.Details)" -ForegroundColor Yellow
            }
            return @{ Name = $Name; Status = "WARNING"; Details = $result.Details }
        }
        else {
            Write-Host "FAIL" -ForegroundColor Red
            if ($result.Details) {
                Write-Host "  $($result.Details)" -ForegroundColor Red
            }
            return @{ Name = $Name; Status = "FAIL"; Details = $result.Details }
        }
    }
    catch {
        Write-Host "ERROR" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return @{ Name = $Name; Status = "ERROR"; Details = $_.Exception.Message }
    }
}

function Test-DirectoryStructure {
    $missing = @()
    
    foreach ($path in $HealthCheckPaths.Values | Where-Object { $_ -like "*:\*" }) {
        if (-not (Test-Path $path)) {
            $missing += $path
        }
    }
    
    if ($missing.Count -eq 0) {
        return @{ Status = "OK"; Details = "All directories present" }
    }
    else {
        return @{ Status = "FAIL"; Details = "Missing: $($missing -join ', ')" }
    }
}

function Test-RequiredFiles {
    $requiredFiles = @(
        "detection.ps1",
        "remediation.ps1",
        "CommonFunctions.psm1",
        "GraphHelper.psm1",
        "IPLocationMap.json",
        "config.json"
    )
    
    $missing = @()
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $HealthCheckPaths.ScriptDir $file
        if (-not (Test-Path $filePath)) {
            $missing += $file
        }
    }
    
    if ($missing.Count -eq 0) {
        return @{ Status = "OK"; Details = "$($requiredFiles.Count) files present" }
    }
    else {
        return @{ Status = "FAIL"; Details = "Missing: $($missing -join ', ')" }
    }
}

function Test-Modules {
    $modules = @(
        "LogHelper",
        "CommonFunctions",
        "GraphHelper"
    )
    
    $missing = @()
    $available = @()
    
    foreach ($module in $modules) {
        # Check in script directory first
        $scriptModulePath = Join-Path $HealthCheckPaths.ScriptDir "$module.psm1"
        $systemModulePath = Join-Path $HealthCheckPaths.ModuleDir "$module\$module.psm1"
        
        if ((Test-Path $scriptModulePath) -or (Test-Path $systemModulePath)) {
            $available += $module
        }
        else {
            $missing += $module
        }
    }
    
    if ($missing.Count -eq 0) {
        return @{ Status = "OK"; Details = "$($available.Count) modules available" }
    }
    else {
        return @{ Status = "WARNING"; Details = "Missing: $($missing -join ', ')" }
    }
}

function Test-ScheduledTask {
    $taskName = "TaurisIT-IPLocation-Detection"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if (-not $task) {
        return @{ Status = "FAIL"; Details = "Scheduled task not found" }
    }
    
    if ($task.State -ne "Ready") {
        return @{ Status = "WARNING"; Details = "Task state: $($task.State)" }
    }
    
    # Check last run
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    if ($taskInfo -and $taskInfo.LastRunTime) {
        $lastRun = $taskInfo.LastRunTime
        $hoursSince = ((Get-Date) - $lastRun).TotalHours
        
        if ($hoursSince -lt 48) {
            return @{ Status = "OK"; Details = "Last run: $([math]::Round($hoursSince, 1)) hours ago" }
        }
        else {
            return @{ Status = "WARNING"; Details = "Last run: $([math]::Round($hoursSince, 1)) hours ago (>48h)" }
        }
    }
    
    return @{ Status = "OK"; Details = "Task ready, never executed" }
}

function Test-RegistryData {
    if (-not (Test-Path $HealthCheckPaths.RegistryPath)) {
        return @{ Status = "WARNING"; Details = "Registry path not found (never executed?)" }
    }
    
    $location = (Get-ItemProperty -Path $HealthCheckPaths.RegistryPath -Name "CurrentLocation" -ErrorAction SilentlyContinue).CurrentLocation
    $lastUpdated = (Get-ItemProperty -Path $HealthCheckPaths.RegistryPath -Name "LastUpdated" -ErrorAction SilentlyContinue).LastUpdated
    
    if (-not $location) {
        return @{ Status = "WARNING"; Details = "No location data" }
    }
    
    if ($lastUpdated) {
        $lastUpdateDate = [datetime]::ParseExact($lastUpdated, "yyyy-MM-dd HH:mm:ss", $null)
        $hoursSince = ((Get-Date) - $lastUpdateDate).TotalHours
        
        if ($hoursSince -lt 24) {
            return @{ Status = "OK"; Details = "Location: $location (Updated: $([math]::Round($hoursSince, 1))h ago)" }
        }
        else {
            return @{ Status = "WARNING"; Details = "Location: $location (Updated: $([math]::Round($hoursSince, 1))h ago)" }
        }
    }
    
    return @{ Status = "OK"; Details = "Location: $location" }
}

function Test-NetworkConnectivity {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Where-Object { $_.IPAddress -notmatch '^(169\.254\.|127\.)' -and $_.AddressState -eq 'Preferred' } |
        Select-Object -First 1).IPAddress
    
    if (-not $ip) {
        return @{ Status = "FAIL"; Details = "No valid IP address found" }
    }
    
    # Test internet connectivity
    try {
        $response = Test-Connection -ComputerName "login.microsoftonline.com" -Count 1 -Quiet -ErrorAction Stop
        if ($response) {
            return @{ Status = "OK"; Details = "IP: $ip, Internet: Connected" }
        }
        else {
            return @{ Status = "WARNING"; Details = "IP: $ip, Internet: Not reachable" }
        }
    }
    catch {
        return @{ Status = "WARNING"; Details = "IP: $ip, Internet: Cannot test" }
    }
}

function Test-AzureADJoinStatus {
    try {
        $dsregcmdOutput = dsregcmd /status 2>$null
        
        if ($dsregcmdOutput) {
            $azureADJoined = ($dsregcmdOutput | Select-String "AzureAdJoined\s*:\s*YES") -ne $null
            $deviceId = ($dsregcmdOutput | Where-Object { $_ -match "DeviceId\s*:" }) -replace ".*:\s*", ""
            
            if ($azureADJoined) {
                return @{ Status = "OK"; Details = "Azure AD Joined (DeviceId: $($deviceId.Trim()))" }
            }
            else {
                return @{ Status = "WARNING"; Details = "Not Azure AD Joined" }
            }
        }
        
        return @{ Status = "WARNING"; Details = "Cannot determine join status" }
    }
    catch {
        return @{ Status = "WARNING"; Details = "dsregcmd not available" }
    }
}

function Test-GraphAPICredentials {
    $envFile = Join-Path $HealthCheckPaths.ScriptDir ".env"
    
    if (-not (Test-Path $envFile)) {
        return @{ Status = "WARNING"; Details = ".env file not found" }
    }
    
    $envContent = Get-Content $envFile -ErrorAction SilentlyContinue
    $hasAll = ($envContent | Select-String "GRAPH_TENANT_ID") -and
    ($envContent | Select-String "GRAPH_CLIENT_ID") -and
    ($envContent | Select-String "GRAPH_CLIENT_SECRET")
    
    if ($hasAll) {
        if ($TestGraphAPI) {
            # Try to get token
            try {
                . (Join-Path $HealthCheckPaths.ScriptDir "GraphHelper.psm1")
                
                $creds = @{}
                foreach ($line in $envContent) {
                    if ($line -match '^\s*([^=]+)\s*=\s*(.*?)\s*$') {
                        $creds[$matches[1].Trim()] = $matches[2].Trim() -replace '^["'']|["'']$', ''
                    }
                }
                
                $token = Get-GraphToken -TenantId $creds["GRAPH_TENANT_ID"] `
                    -ClientId $creds["GRAPH_CLIENT_ID"] `
                    -ClientSecret $creds["GRAPH_CLIENT_SECRET"]
                
                if ($token) {
                    return @{ Status = "OK"; Details = "Credentials valid, token acquired" }
                }
                else {
                    return @{ Status = "FAIL"; Details = "Credentials present but token acquisition failed" }
                }
            }
            catch {
                return @{ Status = "FAIL"; Details = "Credentials invalid: $($_.Exception.Message)" }
            }
        }
        else {
            return @{ Status = "OK"; Details = "Credentials present (not tested)" }
        }
    }
    else {
        return @{ Status = "WARNING"; Details = "Incomplete credentials" }
    }
}

function Test-LogFiles {
    if (-not (Test-Path $HealthCheckPaths.LogDir)) {
        return @{ Status = "WARNING"; Details = "Log directory not found" }
    }
    
    $logFiles = Get-ChildItem -Path $HealthCheckPaths.LogDir -Filter "*.log" -ErrorAction SilentlyContinue
    
    if ($logFiles.Count -eq 0) {
        return @{ Status = "WARNING"; Details = "No log files found" }
    }
    
    $totalSize = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $newestLog = ($logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    $hoursSince = ((Get-Date) - $newestLog).TotalHours
    
    return @{ Status = "OK"; Details = "$($logFiles.Count) files, ${totalSize}MB, newest: $([math]::Round($hoursSince, 1))h ago" }
}

function Test-Configuration {
    $configFile = Join-Path $HealthCheckPaths.ScriptDir "config.json"
    
    if (-not (Test-Path $configFile)) {
        return @{ Status = "WARNING"; Details = "config.json not found (using defaults)" }
    }
    
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        
        # Validate structure
        $requiredSections = @("Paths", "GraphAPI", "Detection", "Logging", "Security")
        $missing = $requiredSections | Where-Object { -not $config.$_ }
        
        if ($missing.Count -gt 0) {
            return @{ Status = "WARNING"; Details = "Missing sections: $($missing -join ', ')" }
        }
        
        return @{ Status = "OK"; Details = "Configuration valid" }
    }
    catch {
        return @{ Status = "FAIL"; Details = "Invalid JSON: $($_.Exception.Message)" }
    }
}

function Test-IPLocationMap {
    $mapFile = Join-Path $HealthCheckPaths.ScriptDir "IPLocationMap.json"
    
    if (-not (Test-Path $mapFile)) {
        return @{ Status = "FAIL"; Details = "IPLocationMap.json not found" }
    }
    
    try {
        $map = Get-Content $mapFile -Raw | ConvertFrom-Json
        $count = ($map.PSObject.Properties).Count
        
        if ($count -eq 0) {
            return @{ Status = "FAIL"; Details = "Empty location map" }
        }
        
        return @{ Status = "OK"; Details = "$count IP prefixes defined" }
    }
    catch {
        return @{ Status = "FAIL"; Details = "Invalid JSON: $($_.Exception.Message)" }
    }
}

function Export-HealthReport {
    param([array]$Results)
    
    $reportFile = Join-Path $HealthCheckPaths.LogDir "HealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    
    $report = @"
========================================
IP Location Detection - Health Check
========================================
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
User: $env:USERNAME
OS: $([System.Environment]::OSVersion.VersionString)

========================================
Results:
========================================

"@
    
    foreach ($result in $Results) {
        $report += "[$($result.Status)] $($result.Name)`n"
        if ($result.Details) {
            $report += "    $($result.Details)`n"
        }
        $report += "`n"
    }
    
    $okCount = ($Results | Where-Object { $_.Status -eq "OK" }).Count
    $warnCount = ($Results | Where-Object { $_.Status -eq "WARNING" }).Count
    $failCount = ($Results | Where-Object { $_.Status -in @("FAIL", "ERROR") }).Count
    
    $report += @"
========================================
Summary:
========================================
Total Tests: $($Results.Count)
OK: $okCount
WARNING: $warnCount
FAIL: $failCount

Overall Status: $(if ($failCount -gt 0) { "CRITICAL" } elseif ($warnCount -gt 0) { "WARNING" } else { "HEALTHY" })
"@
    
    Set-Content -Path $reportFile -Value $report
    Write-HealthLog -Message "Report exported to: $reportFile" -Level SUCCESS
}
#endregion

#region Main Execution
try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  IP Location Detection - Health Check" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    Write-Host ""
    
    $results = @()
    
    # Run tests
    $results += Test-Component -Name "Directory Structure" -TestScript { Test-DirectoryStructure }
    $results += Test-Component -Name "Required Files" -TestScript { Test-RequiredFiles }
    $results += Test-Component -Name "PowerShell Modules" -TestScript { Test-Modules }
    $results += Test-Component -Name "Scheduled Task" -TestScript { Test-ScheduledTask }
    $results += Test-Component -Name "Registry Data" -TestScript { Test-RegistryData }
    $results += Test-Component -Name "Configuration File" -TestScript { Test-Configuration }
    $results += Test-Component -Name "IP Location Map" -TestScript { Test-IPLocationMap }
    $results += Test-Component -Name "Network Connectivity" -TestScript { Test-NetworkConnectivity }
    $results += Test-Component -Name "Azure AD Join Status" -TestScript { Test-AzureADJoinStatus }
    $results += Test-Component -Name "Graph API Credentials" -TestScript { Test-GraphAPICredentials }
    $results += Test-Component -Name "Log Files" -TestScript { Test-LogFiles }
    
    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $okCount = ($results | Where-Object { $_.Status -eq "OK" }).Count
    $warnCount = ($results | Where-Object { $_.Status -eq "WARNING" }).Count
    $failCount = ($results | Where-Object { $_.Status -in @("FAIL", "ERROR") }).Count
    
    Write-Host "Total Tests: " -NoNewline
    Write-Host $results.Count -ForegroundColor White
    Write-Host "OK: " -NoNewline
    Write-Host $okCount -ForegroundColor Green
    Write-Host "WARNING: " -NoNewline
    Write-Host $warnCount -ForegroundColor Yellow
    Write-Host "FAIL: " -NoNewline
    Write-Host $failCount -ForegroundColor Red
    Write-Host ""
    
    $overallStatus = if ($failCount -gt 0) { 
        Write-Host "Overall Status: " -NoNewline
        Write-Host "CRITICAL" -ForegroundColor Red
        "CRITICAL"
    } 
    elseif ($warnCount -gt 0) { 
        Write-Host "Overall Status: " -NoNewline
        Write-Host "WARNING" -ForegroundColor Yellow
        "WARNING"
    } 
    else { 
        Write-Host "Overall Status: " -NoNewline
        Write-Host "HEALTHY" -ForegroundColor Green
        "HEALTHY"
    }
    Write-Host ""
    
    # Export report if requested
    if ($ExportReport) {
        Export-HealthReport -Results $results
    }
    
    # Exit code based on status
    exit $(if ($failCount -gt 0) { 1 } else { 0 })
}
catch {
    Write-HealthLog -Message "Health check failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
#endregion