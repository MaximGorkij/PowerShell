$AppName = "PDF Architect 9"

# Registry paths to check
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Add current user's uninstall path
$uninstallKeyPaths += "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

function IsAppInstalled {
    foreach ($path in $uninstallKeyPaths) {
        try {
            $apps = Get-ChildItem $path -ErrorAction SilentlyContinue
            foreach ($app in $apps) {
                $props = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName -like "*$AppName*" -and $props.UninstallString) {
                    Write-Output "Found in: $path"
                    return $true
                }
            }
        } catch {
            Write-Output "Error accessing $path : $($_.Exception.Message)"
        }
    }
    return $false
}

if (IsAppInstalled) {
    Write-Output "$AppName is installed (system or user scope)."
    exit 1  # App is present
} else {
    Write-Output "$AppName is not installed."
    exit 0  # App not found
}