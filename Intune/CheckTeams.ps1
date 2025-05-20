$version = $null
$exePath = "$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe"

if (Test-Path $exePath) {
    $version = (Get-Item $exePath).VersionInfo.ProductVersion
} else {
    $machinePath = "C:\Program Files (x86)\Teams Installer\Teams.exe"
    if (Test-Path $machinePath) {
        $version = (Get-Item $machinePath).VersionInfo.ProductVersion
    }
}

if ($version) {
    New-Item -Path "HKLM:\SOFTWARE\Company\Inventory" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Company\Inventory" -Name "TeamsVersion" -Value $version
}
