
# Vyžaduje: Microsoft.Graph PowerShell SDK
# Pred spustením: Install-Module Microsoft.Graph -Scope CurrentUser
Import-Module Microsoft.Graph
Connect-MgGraph -Scopes "User.Read.All", "Device.Read.All", "Group.Read.All"

# Názov alebo ID skupiny, ktorú chceš exportovať
$GroupName = Read-Host "Zadaj názov alebo ID skupiny"

# Získaj skupinu podľa názvu
$group = Get-MgGroup -Filter "displayName eq '$GroupName'"

if (!$group) {
    Write-Host "Skupina '$GroupName' sa nenašla." -ForegroundColor Red
    exit
}

Write-Host "Načítavam členov skupiny..."

# Získanie členov skupiny (iba používateľov)
$members = Get-MgGroupMember -GroupId $group.Id -All | Where-Object {$_.ODataType -eq "#microsoft.graph.user"}

$report = @()

foreach ($member in $members) {
    $user = Get-MgUser -UserId $member.Id
    Write-Host "Používateľ: $($user.DisplayName)"

    # Zariadenia registrované týmto používateľom
    $devices = Get-MgUserRegisteredDevice -UserId $user.Id -ErrorAction SilentlyContinue

    if ($devices) {
        foreach ($device in $devices) {
            $report += [PSCustomObject]@{
                UserDisplayName = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                DeviceName      = $device.DisplayName
                DeviceType      = $device.DeviceType
                OperatingSystem = $device.OperatingSystem
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
$exportPath = "$env:USERPROFILE\Desktop\GroupUsers_Devices.csv"
$report | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "Export dokončený: $exportPath" -ForegroundColor Green
