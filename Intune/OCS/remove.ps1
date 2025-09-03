#region === Konfiguracia ===
$computerName = $env:COMPUTERNAME
$logName = "IntuneScript"
$sourceName = "OCS Uninstall"
$logFile = "C:\TaurisIT\Log\OCSUninstall_$computerName.log"
$unok = 0

# Import modulu LogHelper
Import-Module LogHelper -ErrorAction SilentlyContinue

# Vytvor Event Log, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        New-EventLog -LogName $logName -Source $sourceName
        Write-CustomLog -Message "Vytvoreny Event Log '$logName' a zdroj '$sourceName'" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani Event Logu: $_" `
                        -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
}
#endregion

#region === Odinštalovanie ===
Write-CustomLog -Message "=== OCS Inventory Agent Uninstall Started ===" `
                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile

# Stop service
try {
    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Stop-Service -Name 'OCS Inventory Service' -Force
        Write-CustomLog -Message "Service 'OCS Inventory Service' has been stopped." `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "CHYBA pri zastaveni sluzby: $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# Uninstall via registry
try {
    $ocsagent = $null
    $regPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            $ocsagent = (Get-ItemProperty -Path $reg).UninstallString
            break
        }
    }

    if ($ocsagent) {
        Write-CustomLog -Message "Uninstall command: $ocsagent /S" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        Start-Process -FilePath "$ocsagent" -ArgumentList "/S" -Wait
        Write-CustomLog -Message "OCS Agent has been uninstalled." `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        $unok = 1
    } else {
        Write-CustomLog -Message "Uninstall string not found." `
                        -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "CHYBA pri odinstalovani agenta: $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# Remove registry keys
try {
    foreach ($path in $regPaths) {
        if ((Test-Path $path) -and ($unok -eq 1)) {
            Remove-Item -Path $path -Recurse -Force
            Write-CustomLog -Message "Registry key removed: $path" `
                            -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    }
} catch {
    Write-CustomLog -Message "CHYBA pri cisteni registry: $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# Remove folders
Start-Sleep -Seconds 15
try {
    $paths = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )
    foreach ($path in $paths) {
        if ((Test-Path $path) -and ($unok -eq 1)) {
            Remove-Item -Path $path -Recurse -Force
            Write-CustomLog -Message "Folder removed: $path" `
                            -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    }
} catch {
    Write-CustomLog -Message "CHYBA pri mazani suborov: $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# Remove service definition
try {
    if (Get-Command Remove-Service -ErrorAction SilentlyContinue) {
        if ((Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) -and ($unok -eq 1)) {
            Remove-Service -Name 'OCS Inventory Service'
            Write-CustomLog -Message "Service 'OCS Inventory Service' has been removed." `
                            -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    } else {
        Write-CustomLog -Message "Cmdlet 'Remove-Service' nie je dostupny. Pouzi 'sc.exe delete'." `
                        -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "CHYBA pri odstraneni sluzby: $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}
#endregion

#region === Final Cleanup Check ===
try {
    $allClean = $true
    $pathsToCheck = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )
    $registryPathsToCheck = $regPaths

    foreach ($path in $pathsToCheck) {
        if (Test-Path $path) {
            Write-CustomLog -Message "Zostavajuci priecinok: $path" `
                            -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
            $allClean = $false
        }
    }

    foreach ($regPath in $registryPathsToCheck) {
        if (Test-Path $regPath) {
            Write-CustomLog -Message "Zostavajuci registry kluc: $regPath" `
                            -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
            $allClean = $false
        }
    }

    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Write-CustomLog -Message "Sluzba 'OCS Inventory Service' stale existuje." `
                        -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        $allClean = $false
    }

    if ($allClean) {
        Write-CustomLog -Message "Cistenie uspesne. System sa restartuje o 60 sekund." `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        Start-Sleep -Seconds 60
        Restart-Computer -Force
    } else {
        Write-CustomLog -Message "Niektore komponenty stale zostavaju. Restart zruseny." `
                        -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "CHYBA pri verifikacii alebo restarte: $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}
#endregion

Write-CustomLog -Message "=== OCS Inventory Agent Uninstall Completed ===" `
                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile