$logPath = "C:\TaurisIT\Log\RemoteRegistryStatus.txt"

# Overí, či existuje priečinok pre log
if (!(Test-Path -Path (Split-Path $logPath))) {
    New-Item -Path (Split-Path $logPath) -ItemType Directory -Force
}

try {
    # Skontroluje, či existuje pravidlo pre TCP port 135
    $ruleExists = Get-NetFirewallRule | Where-Object {
        ($_ | Get-NetFirewallPortFilter).LocalPort -contains 135 -and
        ($_ | Get-NetFirewallPortFilter).Protocol -eq "TCP" -and
        $_.Direction -eq "Inbound" -and
        $_.Action -eq "Allow"
    }

    if ($ruleExists) {
        Write-Output "Firewall rule for TCP port 135 already exists."
        Add-Content -Path $logPath -Value "$(Get-Date): Firewall rule for TCP port 135 already exists."
    }
    else {
        # Vytvorí nové pravidlo
        New-NetFirewallRule -DisplayName "Allow Remote Registry (TCP 135)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 135 `
            -Action Allow `
            -Profile Any `
            -Enabled True

        Write-Output "Firewall rule for TCP port 135 created."
        Add-Content -Path $logPath -Value "$(Get-Date): Firewall rule for TCP port 135 created."
    }

    # Nastaví službu RemoteRegistry na automatické spúšťanie
    Set-Service -Name RemoteRegistry -StartupType Automatic

    # Spustí službu
    Start-Service -Name RemoteRegistry

    # Počká chvíľu, aby sa služba stihla spustiť
    Start-Sleep -Seconds 3

    # Skontroluje stav služby
    $service = Get-Service -Name RemoteRegistry

    if ($service.Status -eq 'Running') {
        Write-Output "RemoteRegistry service is running."
        Add-Content -Path $logPath -Value "$(Get-Date): RemoteRegistry status: Running"
        exit 0
    }
    else {
        Write-Output "RemoteRegistry service is NOT running. Current status: $($service.Status)"
        Add-Content -Path $logPath -Value "$(Get-Date): RemoteRegistry status: $($service.Status)"
        exit 1
    }
}
catch {
    Write-Output "Error: $($_.Exception.Message)"
    Add-Content -Path $logPath -Value "$(Get-Date): Error - $($_.Exception.Message)"
    exit 1
}