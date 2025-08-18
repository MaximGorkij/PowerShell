param (
    [switch]$TestMode = $true  # Enables test mode (no actual uninstall)
)

# Function to log messages to Intune script output
function Write-IntuneLog {
    param ([string]$Message)
    Write-Output $Message
}

Write-IntuneLog "=== PDF Architect 9 Uninstall Script Started ==="
Write-IntuneLog "Test Mode: $TestMode"

# Registry paths to search for installed applications
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$found = $false  # Flag to track if the app was found

# Loop through registry paths
foreach ($path in $uninstallKeyPaths) {
    $apps = Get-ChildItem $path
    foreach ($app in $apps) {
        $props = Get-ItemProperty $app.PSPath
        # Check if the app name matches PDF Architect 9
        if ($props.DisplayName -like "*PDF Architect 9*") {
            $uninstallString = $props.UninstallString
            Write-IntuneLog "Found PDF Architect 9 at: $($app.PSPath)"
            Write-IntuneLog "Uninstall command: $uninstallString"

            if ($TestMode) {
                # In test mode, skip actual uninstall
                Write-IntuneLog "TEST MODE ENABLED – Skipping actual uninstall."
            } else {
                try {
                    # Run uninstall command silently
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /VERYSILENT /NORESTART`"" -Wait
                    Write-IntuneLog "Uninstallation completed successfully."
                } catch {
                    # Log any errors during uninstall
                    Write-IntuneLog "Error during uninstallation: $_"
                }
            }

            $found = $true
            break
        }
    }
    if ($found) { break }
}

# If app was not found, log that info
if (-not $found) {
    Write-IntuneLog "PDF Architect 9 not found on this device."
}

Write-IntuneLog "=== Script Finished ==="