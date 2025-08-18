
# Vyžaduje: Microsoft.Graph PowerShell SDK
# Pred spustením: Install-Module Microsoft.Graph -Scope CurrentUser
Import-Module Microsoft.Graph
Connect-MgGraph -Scopes "User.Read.All", "Device.Read.All", "Group.Read.All", "DeviceManagementManagedDevices.Read.All", "DeviceManagementManagedDevices.ReadWrite.All"

# Názov alebo ID skupiny, ktorú chceš exportovať
#$GroupName = Read-Host "Meno skupiny"
$GroupName = "KERyba-Inventory"

# Získaj skupinu podľa názvu
$group = Get-MgGroup -Filter "displayName eq '$GroupName'"

if (!$group) {
    Write-Host "Skupina '$GroupName' sa nenašla." -ForegroundColor Red
    exit
}

Write-Host "Members skupiny..."

# Získanie členov skupiny (iba používateľov)
$members = Get-MgGroupMember -GroupId $group.Id -All
#$members = Get-MgGroupMember -GroupId $group.Id -All | Where-Object {$_.ODataType -eq "#microsoft.graph.user"}

$report = @()

foreach ($member in $members) {
    $user = Get-MgUser -UserId $member.Id
    Write-Host "Member: $($user.DisplayName) - $($user.Id)"

    # Zariadenia registrované týmto používateľom
    #$devices = Get-MgUserRegisteredDevice -UserId $user.Id -ErrorAction SilentlyContinue
    $devices = Get-MgUserManagedDevice -UserId $user.Id -ErrorAction SilentlyContinue | Select-object *


    if ($devices) {
        foreach ($device in $devices) {
                $report += [PSCustomObject]@{
                UserDisplayName = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                DeviceName      = $device.DeviceName
                DeviceManagedName = $device.ManagedDeviceName
                DeviceEnrolledDateTime = $device.EnrolledDateTime
                DeviceLastSyncDateTime = $device.LastSyncDateTime
                DeviceModel = $device.Model
                DeviceSerialNumber = $device.SerialNumber
                OperatingSystem = $device.OperatingSystem
                OSVersion = $device.OSVersion
                ComplianceState = $device.ComplianceState
                IsCompliant     = $device.IsCompliant
            }
        }
    }
    else {
        $report += [PSCustomObject]@{
            UserDisplayName = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            DeviceName      = "Žiadne zariadenie"
            DeviceType      = ""
            OperatingSystem = ""
            ComplianceState = ""
            IsCompliant     = ""
        }
    }
}

# Export výsledku do CSV
$exportPath = "C:\Users\adminfindrik\Intune\GroupUsers_Devices.csv"
$report | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "Export done: $exportPath" -ForegroundColor Green
