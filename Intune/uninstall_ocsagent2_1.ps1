$logFile = "C:\Windows\Temp\ocs_uninstall_log.txt"
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
        Log "Služba 'OCS Inventory Service' bola zastavená."
    }
} catch {
    Log "CHYBA pri zastavovaní služby: $_"
}

try {
    # Zistenie cesty k odinštalátoru
    if (Test-path -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent") {
        $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
    } elseif (Test-path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent") {
        $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
    }

    if ($ocsagent) {
        $uninstallCmd = "$ocsagent /x /qn"
        Log "Odinštalačný príkaz: $uninstallCmd"
        #Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallCmd -Wait
        & Start-Process -FilePath $uninstallCmd
        Log "OCS Agent bol odinštalovaný."
        write-host "OCS Agent bol odinštalovaný."
    } else {
        Log "Nebol nájdený odinštalačný reťazec."
    }
} catch {
    Log "CHYBA pri odinštalácii agenta: $_"
}

try {
    # Vymazanie registry
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )

    foreach ($path in $registryPaths) {
        if (Test-Path -Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Log "Registry odstránené: $path"
        }
    }
} catch {
    Log "CHYBA pri čistení registry: $_"
}

try {
    # Vymazanie priečinkov
    $paths = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )

    foreach ($path in $paths) {
        if (Test-Path -Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Log "Odstránený priečinok: $path"
        }
    }
} catch {
    Log "CHYBA pri mazaní súborov: $_"
}

try {
    # Odstránenie služby (ak existuje a cmdlet je dostupný)
    if (Get-Command Remove-Service -ErrorAction SilentlyContinue) {
        if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
            Remove-Service -Name 'OCS Inventory Service'
            Log "Služba 'OCS Inventory Service' bola odstránená."
        }
    } else {
        Log "Cmdlet 'Remove-Service' nie je dostupný. Skúste použiť 'sc.exe delete'."
    }
} catch {
    Log "CHYBA pri odstránení služby: $_"
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
            Log "Kontrola: Zostávajúci priečinok nájdený: $path"
            $allClean = $false
        }
    }

    foreach ($regPath in $registryPathsToCheck) {
        if (Test-Path $regPath) {
            Log "Kontrola: Zostávajúci registry kľúč nájdený: $regPath"
            $allClean = $false
        }
    }

    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Log "Kontrola: Služba 'OCS Inventory Service' stále existuje."
        $allClean = $false
    }

    if ($allClean) {
        Log "Všetko vyčistené úspešne. Čakanie 60 sekúnd pred reštartom..."
        Start-Sleep -Seconds 60
        Log "Reštartujem systém."
        Restart-Computer -Force
    } else {
        Log "Nejaké súčasti stále existujú. Reštart systému zrušený."
    }

} catch {
    Log "CHYBA pri overovaní alebo reštarte: $_"
}

Log "=== OCS Inventory Agent Uninstall Completed ==="