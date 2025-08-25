#region === Configuration ===
$AppName = "PDF Architect 9"
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)
#endregion

#region === Functions ===
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$timestamp [$Level] $Message"
}

function FindUninstallEntries {
    $entries = @()
    foreach ($path in $uninstallKeyPaths) {
        try {
            $apps = Get-ChildItem $path -ErrorAction SilentlyContinue
            foreach ($app in $apps) {
                $props = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName -like "*$AppName*" -and $props.UninstallString) {
                    $entries += [PSCustomObject]@{
                        DisplayName     = $props.DisplayName
                        UninstallString = $props.UninstallString
                        RegistryPath    = $app.PSPath
                    }
                }
            }
        } catch {
            Write-Log "Error accessing $path : $($_.Exception.Message)" "ERROR"
        }
    }
    return $entries
}

function Uninstall-App {
    param ([string]$Command)

    try {
        Write-Log "Executing uninstall: $Command"
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Command /VERYSILENT /NORESTART`"" -Wait -PassThru
        Write-Log "Uninstall exited with code: $($process.ExitCode)"
        return $process.ExitCode -eq 0
    } catch {
        Write-Log "Uninstall failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
#endregion

#region === Main Execution ===
Write-Log "=== PDF Architect 9 remediation started ==="

$uninstallEntries = FindUninstallEntries

if ($uninstallEntries.Count -gt 0) {
    $successCount = 0
    foreach ($entry in $uninstallEntries) {
        Write-Log "Found: $($entry.DisplayName) in $($entry.RegistryPath)"
        $result = Uninstall-App -Command $entry.UninstallString
        if ($result) { $successCount++ }
        Start-Sleep -Seconds 5
    }

    # Re-check after uninstall
    $remaining = FindUninstallEntries
    if ($remaining.Count -eq 0) {
        Write-Log "All instances of '$AppName' successfully removed."
        exit 0
    } else {
        Write-Log "Some instances of '$AppName' still remain." "WARNING"
        exit 1
    }
} else {
    Write-Log "'$AppName' is not installed in system or user scope."
    exit 0
}
#endregion