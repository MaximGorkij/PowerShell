$logFile = "C:\Windows\Temp\ocs_uninstall_log.txt"
$unok = 0
function Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

Log "=== OCS Inventory Agent Uninstall Started ==="

try {
    # Zastavenie služby
    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Stop-Service -Name 'OCS Inventory Service' -Force
		write-host "sluzba zastavena"
        Log "Sluzba 'OCS Inventory Service' bola zastavená."
    }
} catch {
    Log "CHYBA pri zastavovaní sluzby: $_"
}

try {
    # Zistenie cesty k odinštalátoru
    if (Test-path -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent") {
        $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
    } elseif (Test-path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent") {
        $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
    }

    if ($ocsagent) {
        $uninstallCmd = "$ocsagent /S"
		write-host "Odinstalacny prikaz: '$uninstallCmd'"
        Log "Odinstalacny prikaz: $uninstallCmd"
        #Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallCmd -Wait
        Start-Process -FilePath "$ocsagent" -ArgumentList "/S"
        Log "OCS Agent bol odinstalovany."
        write-host "OCS Agent bol odinstalovany."
		$unok = 1
    } else {
        Log "Nebol najdeny odinstalacny retazec."
    }
} catch {
	write-host "CHYBA pri odinstalacii agenta: $_"
    Log "CHYBA pri odinstalacii agenta: $_"
}

try {
    # Vymazanie registry
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )

    foreach ($path in $registryPaths) {
        if ((Test-Path -Path $path) -and ($unok -eq 1)) {
            Remove-Item -Path $path -Recurse -Force
			write-host "Registry odstranene: $path"
            Log "Registry odstranene: $path"
        }
    }
} catch {
	write-host "CHYBA pri cisteni registry: $_"
    Log "CHYBA pri cisteni registry: $_"
}

try {
	Start-Sleep -Seconds 15
    # Vymazanie priečinkov
    $paths = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )

    foreach ($path in $paths) {
        if ((Test-Path -Path $path) -and ($unok -eq 1)) {
            Remove-Item -Path $path -Recurse -Force
			write-host "Odstraneny priecinok: $path"
            Log "Odstraneny priecinok: $path"
        }
    }
} catch {
	write-host "CHYBA pri mazani suborov: $_"
    Log "CHYBA pri mazani suborov: $_"
}

try {
    # Odstránenie služby (ak existuje a cmdlet je dostupný)
    if (Get-Command Remove-Service -ErrorAction SilentlyContinue) {
        if ((Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) -and ($unok -eq 1)) {
            Remove-Service -Name 'OCS Inventory Service'
            Log "Služba 'OCS Inventory Service' bola odstranena."
        }
    } else {
        Log "Cmdlet 'Remove-Service' nie je dostupny. Skúste pouyit 'sc.exe delete'."
    }
} catch {
	write-host "CHYBA pri odstraneni sluzby: $_"
    Log "CHYBA pri odstraneni sluxby: $_"
}

# Na konci skriptu...

try {
    $allClean = $true

    $pathsToCheck = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )

    $registryPathsToCheck = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )

    foreach ($path in $pathsToCheck) {
        if (Test-Path $path) {
            Log "Kontrola: Zostavajuci priecinok najdeny: $path"
            $allClean = $false
        }
    }

    foreach ($regPath in $registryPathsToCheck) {
        if (Test-Path $regPath) {
            Log "Kontrola: Zostavajuci registry kluc najdeny: $regPath"
            $allClean = $false
        }
    }

    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Log "Kontrola: Sluzba 'OCS Inventory Service' stale existuje."
        $allClean = $false
    }

    if ($allClean) {
        Log "Vsetko vycistene uspesne. Cakanie 60 sekund pred restartom..."
        Start-Sleep -Seconds 60
        Log "Restartujem system."
        Restart-Computer -Force
    } else {
        Log "Nejake sucasti stale existujú. Restart systemu zrusený."
    }

} catch {
    Log "CHYBA pri overovani alebo restarte: $_"
}

Log "=== OCS Inventory Agent Uninstall Completed ==="