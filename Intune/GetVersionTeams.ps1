<#
.SYNOPSIS
    Zisťuje verzie MS Teams a loguje ich.
#>
$DeviceName = $env:COMPUTERNAME
#$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\TeamsVersions_$DeviceName_$(Get-Date -Format 'yyyyMMdd').log"
$LogPath = "\\NAS03\log\TeamsVersion\TeamsVersions_$DeviceName_$(Get-Date -Format 'yyyyMMdd').log"

# Funkcia na zistenie verzií Teams
function Get-MSTeamsInstallations {
    $results = @()
    $paths = @(
        "$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe",
        "$env:ProgramFiles(x86)\Microsoft\Teams\current\Teams.exe",
        "$env:ProgramFiles\Microsoft\Teams\current\Teams.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $version = (Get-Item $path).VersionInfo.FileVersion
            $results += "$path | $version"
        }
    }

    $appxTeams = Get-AppxPackage -Name "*Teams*" | Select-Object Name, Version
    if ($appxTeams) {
        $results += "AppX Teams | $($appxTeams.Version)"
    }

    return $results
}

# Získanie a zápis verzií
$installations = Get-MSTeamsInstallations
if ($installations) {
    $installations | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Output "Nájdené verzie Teams:"
    $installations | ForEach-Object { Write-Output $_ }
    exit 0
} else {
    Write-Output "Teams nie je nainštalovaný."
    exit 1
}