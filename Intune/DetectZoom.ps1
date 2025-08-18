# Desired version of Zoom
$requiredVersion = "6.5.7.9933"

# Initialize array for possible Zoom install locations
$locations = @()

# Registry paths to check for system-wide Zoom installations
$zoomPaths = @(
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Attempt to find Zoom in system registry
foreach ($path in $zoomPaths) {
    $zoomKey = Get-ChildItem $path -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DisplayName -like "*Zoom*" }

    if ($zoomKey) {
        $locations += $zoomKey.InstallLocation
        $currentVersion = $zoomKey.DisplayVersion
        break
    }
}

# If Zoom wasn't detected via registry, check user profile path
if (-not $currentVersion) {
    $userPath = "$env:APPDATA\Zoom\bin"
    $zoomExe = Join-Path $userPath "Zoom.exe"

    if (Test-Path $zoomExe) {
        $locations += $userPath

        try {
            # Retrieve version info from the Zoom executable
            $fileVersionInfo = Get-Item $zoomExe | Select-Object -ExpandProperty VersionInfo
            $currentVersion = $fileVersionInfo.ProductVersion
        } catch {
            $currentVersion = "unknown"
        }
    }
}

# Output for diagnostics
Write-Output "Detected Zoom version: $currentVersion"
Write-Output "Checked locations: $($locations -join ', ')"

# Determine if update is needed
if ($currentVersion -ne $requiredVersion -or $locations.Count -eq 0) {
    Write-Output "Zoom is outdated or missing. Update required."
    exit 0
} else {
    Write-Output "Zoom is up to date and present."
    exit 1
}