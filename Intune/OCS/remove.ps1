#region === Konfiguracia ===
$computerName = $env:COMPUTERNAME
$logFile = "C:\TaurisIT\Log\OCSUninstall_$computerName.log"
$uninstallSuccess = $false

# Vytvor log adresar ak neexistuje
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    catch {
        # Pokracuj bez logu ak sa nepodarilo vytvorit adresar
    }
}

# Jednoducha log funkcia
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    
    # Zapis do suboru ak je mozne
    try {
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Ignoruj chyby pri zapise do suboru
    }
    
    # Vzdy zapis do konzoly pre Intune
    Write-Output $logMessage
}
#endregion

#region === Hlavna logika uninstall ===
Write-Log "=== OCS Inventory Agent Uninstall Started ==="

try {
    # 1. Zastavenie sluzieb
    Write-Log "Zastavujem OCS sluzby..."
    $services = @('OCS Inventory Service', 'OcsService')
    
    foreach ($serviceName in $services) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Write-Log "Zastavujem sluzbu: $serviceName"
                Stop-Service -Name $serviceName -Force -NoWait
                
                # Krátke čakanie na zastavenie
                Start-Sleep -Seconds 5
                
                $serviceAfter = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($serviceAfter -and $serviceAfter.Status -eq 'Stopped') {
                    Write-Log "Sluzba '$serviceName' uspesne zastavena"
                }
                else {
                    Write-Log "Sluzba '$serviceName' sa nezastavila kompletne" "Warning"
                }
            }
        }
        catch {
            Write-Log "Chyba pri zastaveni sluzby '$serviceName': $_" "Warning"
        }
    }

    # 2. Najdenie a spustenie uninstallera
    Write-Log "Hladam OCS uninstaller..."
    $uninstallString = $null
    
    # Hladaj v registry
    $regPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($regPath in $regPaths) {
        try {
            $apps = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*OCS Inventory*" -or 
                $_.DisplayName -like "*OCS Agent*"
            }
            
            if ($apps) {
                foreach ($app in $apps) {
                    if ($app.UninstallString) {
                        $uninstallString = $app.UninstallString
                        Write-Log "Najdena OCS aplikacia: $($app.DisplayName)"
                        Write-Log "Uninstall string: $uninstallString"
                        break
                    }
                }
            }
        }
        catch {
            Write-Log "Chyba pri hladani v registry: $_" "Warning"
        }
        
        if ($uninstallString) { break }
    }

    # Spusti uninstaller ak bol najdeny
    if ($uninstallString) {
        try {
            Write-Log "Spustam OCS uninstaller..."
            
            # Parsuj uninstall string
            if ($uninstallString -match '^"([^"]*)"(.*)$') {
                $exePath = $matches[1]
                $arguments = $matches[2].Trim() + " /S"
            }
            else {
                $parts = $uninstallString -split ' ', 2
                $exePath = $parts[0]
                $arguments = if ($parts.Length -gt 1) { $parts[1] + " /S" } else { "/S" }
            }
            
            Write-Log "Spustam: $exePath $arguments"
            $process = Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow -ErrorAction Stop
            
            Write-Log "Uninstaller exit code: $($process.ExitCode)"
            if ($process.ExitCode -eq 0) {
                $uninstallSuccess = $true
                Write-Log "Uninstaller uspesne dokonceny"
            }
            
        }
        catch {
            Write-Log "Chyba pri spusteni uninstallera: $_" "Error"
        }
    }
    else {
        Write-Log "OCS uninstaller nebol najdeny v registry"
    }

    # 3. Manualne cistenie
    Write-Log "Vykonavam manualne cistenie..."
    Start-Sleep -Seconds 10
    
    # Odstranenie priecinkov
    $foldersToRemove = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent", 
        "C:\ProgramData\OCS Inventory NG"
    )

    foreach ($folder in $foldersToRemove) {
        try {
            if (Test-Path $folder) {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Log "Priecinok odstraneny: $folder"
            }
        }
        catch {
            Write-Log "Chyba pri mazani priecinku $folder : $_" "Warning"
        }
    }

    # Odstranenie registry klucov
    $regKeysToRemove = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )

    foreach ($regKey in $regKeysToRemove) {
        try {
            if (Test-Path $regKey) {
                Remove-Item -Path $regKey -Recurse -Force
                Write-Log "Registry kluc odstraneny: $regKey"
            }
        }
        catch {
            Write-Log "Chyba pri mazani registry kluca $regKey : $_" "Warning"
        }
    }

    # Odstranenie sluzieb
    foreach ($serviceName in $services) {
        try {
            if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
                # Pokus sa pouzit sc.exe (univerzalnejsie)
                $result = & sc.exe delete $serviceName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Sluzba '$serviceName' odstranena"
                }
                else {
                    Write-Log "Chyba pri mazani sluzby '$serviceName': $result" "Warning"
                }
            }
        }
        catch {
            Write-Log "Chyba pri mazani sluzby '$serviceName': $_" "Warning"
        }
    }

    # 4. Finalna verifikacia
    Write-Log "Verifikujem uspesnost odinstalace..."
    $cleanupSuccess = $true
    
    # Kontrola priecinkov
    foreach ($folder in $foldersToRemove) {
        if (Test-Path $folder) {
            Write-Log "ZOSTAVA: Priecinok $folder" "Warning"
            $cleanupSuccess = $false
        }
    }
    
    # Kontrola sluzieb  
    foreach ($serviceName in $services) {
        if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
            Write-Log "ZOSTAVA: Sluzba $serviceName" "Warning"
            $cleanupSuccess = $false
        }
    }

    # Vysledok
    if ($cleanupSuccess) {
        Write-Log "SUCCESS: OCS Inventory Agent uspesne odstraneny" "Success"
        Write-Output "RESULT: OCS Inventory successful uninstalled"
    }
    else {
        Write-Log "WARNING: Niektore komponenty OCS Inventory zostali v systeme" "Warning"
        Write-Output "RESULT: OCS Inventory partially uninstalled - manual cleanup required"
    }

}
catch {
    Write-Log "KRITICKA CHYBA pri uninstall procese: $_" "Error"
    Write-Output "RESULT: OCS Inventory uninstall failed with critical error"
    throw $_
}

Write-Log "=== OCS Inventory Agent Uninstall Completed ==="