#region Nastavenia
$moduleName = "Microsoft.Graph"
$scopes = @(
    "DeviceManagementApps.Read.All",
    "Group.Read.All",
    "DeviceManagementManagedDevices.Read.All"
)
$logName = "IntuneAppReports"
$logSource = "IntuneReportGenerator"
$reportFolder = "\\nas03\log\IntuneReports"
#endregion

#region Event Log
if (-not [System.Diagnostics.EventLog]::Exists($logName)) {
    New-EventLog -LogName $logName -Source $logSource
}
elseif (-not [System.Diagnostics.EventLog]::SourceExists($logSource)) {
    New-EventLog -LogName $logName -Source $logSource
}
#endregion

#region Modul
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Install-Module -Name $moduleName -Force -Scope CurrentUser
    Write-EventLog -LogName $logName -Source $logSource -EventId 1001 -EntryType Information -Message "Modul $moduleName nainštalovaný."
}
#endregion

#region Autentifikácia
try {
    Connect-MgGraph -Scopes $scopes -ErrorAction Stop
    Write-EventLog -LogName $logName -Source $logSource -EventId 1002 -EntryType Information -Message "Úspešné prihlásenie do Microsoft Graph."
} catch {
    Write-EventLog -LogName $logName -Source $logSource -EventId 1003 -EntryType Error -Message "Chyba pri autentifikácii: $_"
    exit 1
}
#endregion

#region Report
try {
    $dateStamp = Get-Date -Format 'yyyyMMdd'
    $appsResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
    $apps = $appsResponse.value

    $windowsTypes = @(
        "#microsoft.graph.win32LobApp",
        "#microsoft.graph.windowsStoreApp",
        "#microsoft.graph.windowsMobileMSI",
        "#microsoft.graph.windowsUniversalAppX"
    )

    $windowsApps = $apps | Where-Object { $windowsTypes -contains $_.'@odata.type' }
    $mainReport = @()

    foreach ($app in $windowsApps) {
        $appId = $app.id
        $appName = $app.displayName
        $appType = $app.'@odata.type'
        $publisher = $app.publisher
        $version = $app.version
        $safeName = ($appName -replace '[\\/:*?"<>|]', '_')

        $assignments = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/assignments"
        if ($assignments.value.Count -eq 0) {
            Write-EventLog -LogName $logName -Source $logSource -EventId 1004 -EntryType Information -Message "Aplikácia '$appName' nemá priradenia – preskočená."
            continue
        }

        foreach ($assignment in $assignments.value) {
            $groupId = $assignment.target.groupId
            $groupName = "Neznáma skupina"
            if ($groupId) {
                try {
                    $group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                    $groupName = $group.displayName
                } catch {
                    Write-EventLog -LogName $logName -Source $logSource -EventId 1005 -EntryType Warning -Message "Nepodarilo sa načítať skupinu '$groupId'."
                }
            }

            # Statusy zariadení
            $statusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/deviceStatuses"
            $statusResponse = Invoke-MgGraphRequest -Method GET -Uri $statusUri
            $successCount = ($statusResponse.value | Where-Object { $_.status -eq "success" }).Count
            $failCount    = ($statusResponse.value | Where-Object { $_.status -eq "failed" }).Count
            $pendingCount = ($statusResponse.value | Where-Object { $_.status -eq "pending" }).Count
            $installStatus = "Úspešné: $successCount, Zlyhané: $failCount, Čakajúce: $pendingCount"

            $mainReport += [PSCustomObject]@{
                AppName        = $appName
                AppType        = $appType
                Publisher      = $publisher
                Version        = $version
                AssignmentType = $assignment.intent
                TargetGroup    = $groupName
                CreatedDate    = $assignment.createdDateTime
                InstallStatus  = $installStatus
            }
        }

        # Export user statuses
        try {
            $userStatuses = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/userStatuses"
            $userCsv = Join-Path $reportFolder "$safeName_UserInstallStatus_$dateStamp.csv"
            $userStatuses.value | Select-Object userName, installState, installStateDetail | Export-Csv -Path $userCsv -NoTypeInformation
        } catch {}

        # Export device statuses
        try {
            $deviceStatuses = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/deviceStatuses"
            $deviceCsv = Join-Path $reportFolder "$safeName_DeviceInstallStatus_$dateStamp.csv"
            $deviceStatuses.value | Select-Object deviceName, installState, errorCode | Export-Csv -Path $deviceCsv -NoTypeInformation
        } catch {}
    }

    # Export hlavného reportu
    $mainCsv = Join-Path $reportFolder "WindowsApps_AssignmentReport_$dateStamp.csv"
    $mainReport | Export-Csv -Path $mainCsv -NoTypeInformation
    Write-EventLog -LogName $logName -Source $logSource -EventId 1006 -EntryType Information -Message "Hlavný report uložený do $mainCsv."
} catch {
    Write-EventLog -LogName $logName -Source $logSource -EventId 1007 -EntryType Error -Message "Chyba pri generovaní reportu: $_"
    exit 1
}
#endregion