# ============================================
# Script: Personal Device Usage Report
# Author: Marek + Copilot
# Description: Tracks personal device usage via Intune and FortiAnalyzer
# ============================================

# Define paths
$reportFolder = "D:\Reports"
$logPath = "$reportFolder\PersonalDeviceUsage.log"
$csvPath = "$reportFolder\PersonalDeviceUsage.csv"
$allDevicesPath = "$reportFolder\AllDevices.csv"
$vpnLogPath = "$reportFolder\FortiVPN.csv"

# Ensure report folder and log file exist
if (-not (Test-Path $reportFolder)) { New-Item -Path $reportFolder -ItemType Directory -Force }
if (-not (Test-Path $logPath)) { New-Item -Path $logPath -ItemType File -Force }

# Logging function
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $message"
}

Write-Log "Script started"

# Load Microsoft.Graph module
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
    Write-Log "Installed Microsoft.Graph module"
}
Import-Module Microsoft.Graph -ErrorAction Stop
Write-Log "Imported Microsoft.Graph module"

# Connect to Graph
try {
    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "AuditLog.Read.All"
    Write-Log "Connected to Microsoft Graph"
} catch {
    Write-Log "Graph connection failed $_"
    throw "Unable to connect to Microsoft Graph"
}

# Get devices via Graph API
try {
    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri
    $devices = $response.value
    Write-Log "Retrieved $($devices.Count) devices"
} catch {
    Write-Log "Device retrieval failed $_"
    throw
}

# Filter personal devices (case-insensitive)
$personalDevices = $devices | Where-Object {
    ($_.managedDeviceOwnerType -ne $null -and $_.managedDeviceOwnerType.ToLower() -eq "personal") -or
    $_.managedDeviceOwnerType -eq $null -or
    $_.managedDeviceOwnerType -eq ""
}
Write-Log "Found $($personalDevices.Count) personal devices"

# Load VPN logs
$vpnLogs = @()
if (Test-Path $vpnLogPath) {
    try {
        $vpnLogs = Import-Csv $vpnLogPath
        Write-Log "Loaded VPN logs from $vpnLogPath"
    } catch {
        Write-Log "Failed to load VPN logs $_"
    }
} else {
    Write-Log "VPN log file not found at $vpnLogPath"
}

# Build report
$report = @()
foreach ($device in $personalDevices) {
    try {
        $deviceInfo = @{
            DeviceName        = $device.deviceName
            UserPrincipalName = $device.userPrincipalName
            LastSyncDateTime  = $device.lastSyncDateTime
            OfficeAccess      = "Unknown"
            VPNConnection     = "No"
        }

        # Check Office 365 usage via Graph API
        try {
            $upn = $device.userPrincipalName
            if ($upn) {
                $signInUri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=userPrincipalName eq '$($upn)'"
                $signInResponse = Invoke-MgGraphRequest -Method GET -Uri $signInUri
                if ($signInResponse.value.Count -gt 0) {
                    $deviceInfo.OfficeAccess = "Yes"
                }
            }
        } catch {
            Write-Log "Failed to retrieve sign-in logs for $upn $_"
        }

        # Check VPN usage
        if ($vpnLogs.Count -gt 0) {
            $vpnMatch = $vpnLogs | Where-Object {
                ($_.DeviceName -ne $null -and $_.DeviceName.ToLower() -eq $device.deviceName.ToLower()) -or
                ($_.User -ne $null -and $_.User.ToLower() -eq $device.userPrincipalName.ToLower())
            }
            if ($vpnMatch) {
                $deviceInfo.VPNConnection = "Yes"
            }
        }

        $report += New-Object PSObject -Property $deviceInfo
        Write-Log "Processed device $($device.deviceName)"
    } catch {
        Write-Log "Error processing device $($device.deviceName) $_"
    }
}

# Export personal device report
try {
    if ($report.Count -eq 0) {
        Write-Log "No personal devices matched criteria. Exporting empty report."
        "" | Select-Object @{Name="DeviceName";Expression={""}},
                          @{Name="UserPrincipalName";Expression={""}},
                          @{Name="LastSyncDateTime";Expression={""}},
                          @{Name="OfficeAccess";Expression={""}},
                          @{Name="VPNConnection";Expression={""}} |
        Export-Csv -Path $csvPath -NoTypeInformation
    } else {
        $report | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "Exported personal device report with $($report.Count) entries"
    }
} catch {
    Write-Log "Failed to export personal report $_"
}

# Export all devices
try {
    $devices | Select-Object deviceName, operatingSystem, complianceState, managedDeviceOwnerType, userPrincipalName, lastSyncDateTime |
    Export-Csv -Path $allDevicesPath -NoTypeInformation -Encoding UTF8
    Write-Log "Exported all devices to $allDevicesPath with $($devices.Count) entries"
} catch {
    Write-Log "Failed to export all devices $_"
}

Write-Log "Script completed"