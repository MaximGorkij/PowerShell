# Stop SCCM service if running
$service = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Stop-Service -Name "CcmExec" -Force
    Start-Sleep -Seconds 5
}

# Uninstall SCCM client
$ccmUninstall = "C:\Windows\CCMSetup\CCMSetup.exe"
if (Test-Path $ccmUninstall) {
    Start-Process -FilePath $ccmUninstall -ArgumentList "/uninstall" -Wait
    Start-Sleep -Seconds 10
}

# Remove leftover folders
$paths = @(
    "C:\Windows\CCM",
    "C:\Windows\CCMSetup",
    "C:\Windows\CCMCache"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Optional: Clean WMI repository if needed
$repoStatus = (winmgmt /verifyrepository)
if ($repoStatus -match "inconsistent") {
    winmgmt /salvagerepository
}

Write-Output "SCCM client removed"
exit 0