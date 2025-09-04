$logPath = "C:\TaurisIT\Log\RemoteRegistryStatus.txt"

# Overí, či existuje priečinok pre log
if (!(Test-Path -Path (Split-Path $logPath))) {
    New-Item -Path (Split-Path $logPath) -ItemType Directory -Force
}

try {
    # Povolenie COM+ Network Access (DCOM-In) vo firewalle
    Set-NetFirewallRule -DisplayName "COM+ Network Access (DCOM-In)" -Enabled True

    # Nastaví službu RemoteRegistry na automatické spúšťanie
    Set-Service -Name RemoteRegistry -StartupType Automatic

    # Spustí službu
    Start-Service -Name RemoteRegistry

    # Počká chvíľu, aby sa služba stihla spustiť
    Start-Sleep -Seconds 3

    # Skontroluje stav služby
    $service = Get-Service -Name RemoteRegistry

    if ($service.Status -eq 'Running') {
        Write-Output "✅ RemoteRegistry service is running."
        Add-Content -Path $logPath -Value "$(Get-Date): RemoteRegistry status: Running"
        exit 0
    } else {
        Write-Output "❌ RemoteRegistry service is NOT running. Current status: $($service.Status)"
        Add-Content -Path $logPath -Value "$(Get-Date): RemoteRegistry status: $($service.Status)"
        exit 1
    }
}
catch {
    Write-Output "⚠️ Error: $($_.Exception.Message)"
    Add-Content -Path $logPath -Value "$(Get-Date): Error - $($_.Exception.Message)"
    exit 1
}