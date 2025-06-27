Write-Output "Running Chrome Remediation..."

# Stop running Chrome processes
$chromeProcesses = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
if ($chromeProcesses) {
    try {
        Stop-Process -Name "chrome" -Force
        Write-Output "Stopped Chrome processes."
    } catch {
        Write-Output "Failed to stop Chrome processes: $_"
    }
}

function Uninstall-Chrome {
    $ChromeNames = @("Google Chrome", "Chrome")
    $UninstallKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($keyPath in $UninstallKeys) {
        Get-ChildItem -Path $keyPath -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath
            if ($ChromeNames -contains $props.DisplayName -or $props.DisplayName -like "*Chrome*") {
                $uninstallString = $props.UninstallString
                if ($uninstallString) {
                    try {
                        Write-Output "Uninstalling $($props.DisplayName)..."
                        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$uninstallString`" /quiet /norestart" -Wait
                    } catch {
                        Write-Output "Failed to uninstall $($props.DisplayName): $_"
                    }
                }
            }
        }
    }
}

Uninstall-Chrome

# Remove leftover folders
$folders = @(
    "$env:ProgramFiles\Google\Chrome",
    "$env:ProgramFiles(x86)\Google\Chrome",
    "$env:LocalAppData\Google\Chrome",
    "$env:AppData\Google\Chrome",
    "$env:LocalAppData\Google",
    "$env:AppData\Google"
)

foreach ($folder in $folders) {
    if (Test-Path $folder) {
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Output "Deleted folder: $folder"
        } catch {
            Write-Output "Could not delete folder: $folder"
        }
    }
}

# Remove registry keys
$regKeys = @(
    "HKCU:\Software\Google",
    "HKCU:\Software\Google\Chrome",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome",
    "HKLM:\Software\Google",
    "HKLM:\Software\Google\Chrome",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome",
    "HKLM:\Software\WOW6432Node\Google",
    "HKLM:\Software\WOW6432Node\Google\Chrome",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome"
)

foreach ($regKey in $regKeys) {
    if (Test-Path $regKey) {
        try {
            Remove-Item -Path $regKey -Recurse -Force
            Write-Output "Deleted registry key: $regKey"
        } catch {
            Write-Output "Failed to delete registry key: $regKey - $_"
        }
    } else {
        Write-Output "Registry key not found (already removed): $regKey"
    }
}

Write-Output "Chrome remediation completed."
exit 0
