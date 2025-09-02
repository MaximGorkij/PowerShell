$logPath = "C:\TaurisIT\Log\RemoteRegistryStatus.txt"

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
} else {
    Write-Output "❌ RemoteRegistry service is NOT running. Current status: $($service.Status)"
}

Add-Content -Path $logPath -Value "$(Get-Date): RemoteRegistry status: $($service.Status)"