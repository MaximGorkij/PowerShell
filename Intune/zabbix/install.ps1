msiexec /i "zabbix_agent2_plugins-7.4.0.msi" /qn
Start-Sleep -Seconds 5
Copy-Item "zabbix_agent2.conf" "C:\Program Files\Zabbix Agent 2\" -Force
certutil -f -p ZabbixSecret123 -importpfx "agent.pfx"
Restart-Service "Zabbix Agent 2"
        try {
            Write-Log "Sťahujem logy pre zariadenie $deviceId ($user)..." "INFO"
            Invoke-WebRequest -Uri $url -OutFile $fileName -ErrorAction Stop
            Write-Log "Logy úspešne stiahnuté: $fileName" "INFO"
            $results += [PSCustomObject]@{
                DeviceId = $deviceId
                User     = $user
                FileName = $fileName
                Status   = "Success"
            }
        } catch {
            Write-Log "Chyba pri sťahovaní logov pre zariadenie $deviceId ($user): $_" "ERROR"
            $results += [PSCustomObject]@{
                DeviceId = $deviceId
                User     = $user
                FileName = ""
                Status   = "Failed"
            }
        }
    