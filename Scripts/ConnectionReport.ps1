# === Setup ===
$reportPath = "D:\Reports"
$vpnLogPath = "$reportPath\FortiVPN.csv"
$personalReport = "$reportPath\PersonalDeviceUsage.csv"
$logPath = "$reportPath\PersonalDeviceUsage.log"

# Create report folder if needed
if (!(Test-Path $reportPath)) {
    New-Item -Path $reportPath -ItemType Directory | Out-Null
}

# === Logging Function ===
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $message"
}
Write-Log "=== Script started ==="

# === Connect to Microsoft Graph ===
Write-Log "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "AuditLog.Read.All"
Write-Log "Connected to Microsoft Graph."

# === Load Personal Windows Devices ===
Write-Log "Loading personal Windows devices from Intune..."
$devices = Get-MgDeviceManagementManagedDevice | Where-Object {
    $_.DeviceOwnership -eq "Personal" -and $_.OperatingSystem -eq "Windows"
}
Write-Log "Devices loaded: $($devices.Count)"

# === Load VPN Logs ===
$vpnLogs = @{}
if (Test-Path $vpnLogPath) {
    Write-Log "Loading VPN logs from $vpnLogPath"
    $vpnData = Import-Csv $vpnLogPath
    foreach ($entry in $vpnData) {
        $cleanUPN = ($entry.UserPrincipalName).Trim()
        if (-not $vpnLogs.ContainsKey($cleanUPN)) {
            $vpnLogs[$cleanUPN] = $true
        }
    }
    Write-Log "VPN records loaded: $($vpnData.Count)"
} else {
    Write-Log "VPN log file not found at: $vpnLogPath"
}

# === Process Devices ===
$report = @()
foreach ($device in $devices) {
    $upn = $device.UserPrincipalName
    $deviceName = $device.DeviceName
    $lastSync = $device.LastSyncDateTime

    # Check Office 365 sign-ins
    $officeAccess = $false
    try {
        $signIns = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$upn'" -Top 50
        $officeAccess = $signIns | Where-Object {
            $_.AppDisplayName -match "Office|Exchange|SharePoint|Teams"
        }
    } catch {
        Write-Log "Error retrieving sign-ins for $upn : $_"
    }

    # Check VPN connection
    $vpnConnected = $vpnLogs.ContainsKey($upn)

    # Log device summary
    Write-Log "Processed: $deviceName | UPN: $upn | Office365: $($officeAccess.Count -gt 0) | VPN: $vpnConnected"

    # Add to report
    $report += [PSCustomObject]@{
        DeviceName        = $deviceName
        UserPrincipalName = $upn
        LastSync          = $lastSync
        Office365Access   = if ($officeAccess) { "Yes" } else { "No" }
        VPNConnection     = if ($vpnConnected) { "Yes" } else { "No" }
    }
}

# === Export Report ===
try {
    $report | Export-Csv -Path $personalReport -NoTypeInformation -Encoding UTF8
    Write-Log "Report exported to: $personalReport"
} catch {
    Write-Log "Error exporting report: $_"
}

Write-Log "=== Script completed ==="