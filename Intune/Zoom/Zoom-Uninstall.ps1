# Uninstall Zoom via registry (system-wide MSI install)
$zoomPaths = @(
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
)

$uninstalled = $false

foreach ($path in $zoomPaths) {
    $zoomKey = Get-ChildItem $path -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DisplayName -like "*Zoom*" }

    if ($zoomKey) {
        $productCode = $zoomKey.PSChildName
        Write-Output "Uninstalling Zoom via MSI: $productCode"
        Start-Process "msiexec.exe" -ArgumentList "/x $productCode /quiet /norestart" -Wait
        $uninstalled = $true
        break
    }
}

# Remove Zoom from user profile (non-MSI install)
$users = Get-ChildItem "C:\Users" -ErrorAction SilentlyContinue

foreach ($user in $users) {
    $zoomUserPath = "$($user.FullName)\AppData\Roaming\Zoom"
    if (Test-Path $zoomUserPath) {
        Write-Output "Removing Zoom from user profile: $zoomUserPath"
        Remove-Item -Path $zoomUserPath -Recurse -Force -ErrorAction SilentlyContinue
        $uninstalled = $true
    }
}

# Final output
if ($uninstalled) {
    Write-Output "Zoom has been successfully removed."
    exit 0
} else {
    Write-Output "Zoom was not found on this device."
    exit 1
}