param (
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Detection", "Requirement")]
    [string]$Method = "Detection"
)

function Convert-ToVersion {
    param ([string]$VersionString)
    $segments = ($VersionString -split '[^\d]+') | Where-Object { $_ -match '^\d+$' }
    while ($segments.Count -lt 4) { $segments += 0 }
    if ($segments.Count -gt 4) { $segments = $segments[0..3] }
    try {
        return New-Object System.Version($segments[0], $segments[1], $segments[2], $segments[3])
    } catch {
        return $null
    }
}

function Get-InstalledVersion {
    param ([string]$AppName)

    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $registryPaths) {
        $apps = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        foreach ($app in $apps) {
            $displayName = $app.GetValue("DisplayName")
            $displayVersion = $app.GetValue("DisplayVersion")
            if ($displayName -and $displayName -like "*$AppName*" -and $displayVersion) {
                return $displayVersion
            }
        }
    }

    return $null
}

# Main logic
$installedVersionRaw = Get-InstalledVersion -AppName $Name
$installedVersion = Convert-ToVersion $installedVersionRaw
$targetVersion = Convert-ToVersion $Version

if (-not $installedVersion) {
    Write-Host "[$Name][$Version]: Not installed"
    if ($Method -eq "Detection") { exit 1 }
    return "NotInstalled"
}

if ($installedVersion -eq $targetVersion) {
    Write-Host "[$Name][$Version]: Same version installed"
    if ($Method -eq "Detection") { exit 0 }
    return "SameVersion"
} elseif ($installedVersion -gt $targetVersion) {
    Write-Host "[$Name][$Version]: Downgrade required (installed: $installedVersionRaw)"
    if ($Method -eq "Detection") { exit 0 }
    return "Downgrade"
} elseif ($installedVersion -lt $targetVersion) {
    Write-Host "[$Name][$Version]: Upgrade required (installed: $installedVersionRaw)"
    if ($Method -eq "Requirement") { return "Upgrade" }
}

Write-Host "[$Name][$Version]: Unknown status"
exit 1