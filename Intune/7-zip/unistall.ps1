<#
.SYNOPSIS
    Napravny skript pre odinstalovanie vsetkych verzii aplikacie 7-Zip.
    Určene pre Intune Proactive Remediations.

.DESCRIPTION
    Skript hlada a spusti odinstalacne prikazy pre vsetky registrovane verzie 7-Zip.
    Následne vynutene odstrani registracne kluce, subory, procesy a zástupce.
    Vrati exit code 0, ak bola odinstalacia/vycistenie USPESNA.
    Vrati exit code 1, ak odinstalacia/vycistenie ZLYHALO.

.AUTHOR
    Marek Findrik (Adaptacia a rozsirenie pre 7-Zip)

.CREATED
    2025-11-26

.VERSION
    1.3.0

.NOTES
    - Skript vyzaduje predinstalovany modul 'LogHelper'.
    - Loguje vysledok do C:\TaurisIT\Log\Remediate7-zip.log a Remediate7-zip.txt.
    - Vyžaduje administrátorské práva.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# --- KONFIGURACIA ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"  # Zmenené na Continue, aby skript pokračoval pri chybách

$ScriptVersion = "1.3.0"
$EventSource = "7Zip-Remediation-Intune-Remediation"
$LogFileName = "Remediate7-zip.log" 
$LogDirectory = "C:\TaurisIT\Log"
$TextLogFile = Join-Path $LogDirectory "Remediate7-zip.txt"
$FailureCount = 0
$SuccessCount = 0

# --- FUNKCIA PRE TEXTOVY LOG ---
function Write-TextLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    try {
        $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $Line = "$TimeStamp`t$Level`t$Message"
        Add-Content -Path $TextLogFile -Value $Line -ErrorAction SilentlyContinue
    }
    catch {
        Write-Error "CHYBA: Nepodarilo sa zapisat do textoveho logu! $($_.Exception.Message)"
    }
}

# --- FUNKCIA PRE BEZPEČNÚ ODINŠTALÁCIU ---
function Invoke-SafeUninstall {
    param(
        [string]$DisplayName,
        [string]$UninstallString,
        [string]$KeyPath
    )
    
    $localSuccess = $false
    $attempts = @()
    
    Write-TextLog -Message "--- Spracovanie aplikacie: '$DisplayName' ---" -Level "INFO"
    
    # POKUS 1: Štandardná odinštalácia
    if (-not [string]::IsNullOrWhiteSpace($UninstallString)) {
        $attempts += "Standardna odinstalacia"
        
        try {
            $Message = "Odinstalovavam (Pokus 1/3): '$DisplayName'"
            Write-TextLog -Message $Message -Level "WARN"
            
            # Bezpečná extrakcia parametrov
            if ($UninstallString -match '^"(.*?)"(?:\s+(.*))?$') {
                $exePath = $Matches[1]
                $arguments = $Matches[2]
            }
            else {
                $parts = $UninstallString -split '\s+', 2
                $exePath = $parts[0]
                $arguments = if ($parts.Count -gt 1) { $parts[1] } else { $null }
            }
            
            # Normalizácia ciest
            $exePath = $exePath.Trim('"')
            
            # Pridanie tichých parametrov
            if ($exePath -like "*msiexec*") {
                if ($arguments -match '/I') {
                    $arguments = $arguments -replace '/I', '/x'
                }
                if ($arguments -notmatch '/qn') {
                    $arguments += " /qn /norestart"
                }
            }
            elseif ($exePath -like "*.exe") {
                if ($arguments -notmatch '/S|/quiet') {
                    $arguments += " /S"
                }
            }
            
            # Spustenie procesu
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exePath
            $psi.Arguments = $arguments
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            
            Write-TextLog -Message "Spustam: $exePath $arguments" -Level "INFO"
            
            if ($process.Start()) {
                # Čakanie s timeoutom
                $timeout = 120  # sekundy
                if (-not $process.WaitForExit($timeout * 1000)) {
                    $process.Kill()
                    Write-TextLog -Message "Proces bol ukonceny po timeout ($timeout s)" -Level "WARN"
                }
                
                $exitCode = $process.ExitCode
                $output = $process.StandardOutput.ReadToEnd()
                $errorOutput = $process.StandardError.ReadToEnd()
                
                if ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1641) {
                    Write-TextLog -Message "Odinstalacia uspesna (Exit Code: $exitCode)" -Level "INFO"
                    $localSuccess = $true
                    $script:SuccessCount++
                }
                else {
                    Write-TextLog -Message "Odinstalacia zlyhala (Exit Code: $exitCode)" -Level "ERROR"
                    Write-TextLog -Message "STDOUT: $output" -Level "DEBUG"
                    Write-TextLog -Message "STDERR: $errorOutput" -Level "DEBUG"
                }
            }
        }
        catch {
            $errorMsg = "CHYBA pri odinstalacii: $($_.Exception.Message)"
            Write-TextLog -Message $errorMsg -Level "ERROR"
        }
        
        Start-Sleep -Seconds 3
    }
    
    # POKUS 2: Odstránenie registračného kľúča
    if (-not [string]::IsNullOrWhiteSpace($KeyPath) -and (Test-Path $KeyPath)) {
        $attempts += "Odstranenie registra"
        
        try {
            $Message = "CISTENIE REGISTRA (Pokus 2/3): '$DisplayName'"
            Write-TextLog -Message $Message -Level "INFO"
            
            # Záloha registra
            $backupFile = "$env:TEMP\7zip-reg-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').reg"
            $regPath = $KeyPath.Replace('HKLM:\', 'HKEY_LOCAL_MACHINE\').Replace('HKCU:\', 'HKEY_CURRENT_USER\')
            
            try {
                & reg.exe export "`"$regPath`"" "`"$backupFile`"" 2>&1 | Out-Null
                if (Test-Path $backupFile) {
                    Write-TextLog -Message "Zaloha registra vytvorena: $backupFile" -Level "INFO"
                }
            }
            catch { }
            
            # Odstránenie kľúča
            Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop
            Write-TextLog -Message "Registracny kluc odstraneny: $KeyPath" -Level "INFO"
            
            if (-not (Test-Path $KeyPath)) {
                $localSuccess = $true
                $script:SuccessCount++
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-TextLog -Message "Nedostatocne opravnenia pre odstranenie registra" -Level "ERROR"
            $script:FailureCount++
        }
        catch {
            $errorMsg = "CHYBA pri mazani registra: $($_.Exception.Message)"
            Write-TextLog -Message $errorMsg -Level "ERROR"
            $script:FailureCount++
        }
    }
    
    # POKUS 3: Vynútené odstránenie súborov
    $attempts += "Vynutene odstranenie suborov"
    
    try {
        $Message = "VYNUTENE CISTENIE (Pokus 3/3): '$DisplayName'"
        Write-TextLog -Message $Message -Level "INFO"
        
        # Hľadanie súborov podľa DisplayName
        $searchTerms = @()
        if ($DisplayName -match "7-Zip (\d+(\.\d+)*)") {
            $version = $Matches[1]
            $searchTerms += "*7*zip*$version*"
        }
        $searchTerms += "*7*zip*", "*7zip*"
        
        $commonPaths = @(
            "$env:ProgramFiles",
            "$env:ProgramFiles(x86)",
            "$env:AppData",
            "$env:LocalAppData",
            "$env:ProgramData"
        )
        
        foreach ($path in $commonPaths) {
            foreach ($term in $searchTerms) {
                try {
                    $items = Get-ChildItem -Path $path -Filter $term -Recurse -ErrorAction SilentlyContinue -Depth 2
                    foreach ($item in $items) {
                        try {
                            if ($item.PSIsContainer) {
                                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                                Write-TextLog -Message "Odstraneny adresar: $($item.FullName)" -Level "INFO"
                            }
                            else {
                                Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                                Write-TextLog -Message "Odstraneny subor: $($item.FullName)" -Level "INFO"
                            }
                            $localSuccess = $true
                        }
                        catch {
                            Write-TextLog -Message "Nepodarilo sa odstranit: $($item.FullName)" -Level "WARN"
                        }
                    }
                }
                catch { }
            }
        }
    }
    catch {
        Write-TextLog -Message "Chyba pri vynutenom cisteni: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $localSuccess, ($attempts -join ", ")
}

# --- HLAVNY SKRIPT ---
try {
    # Vytvorenie logovacieho adresára
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Inicializácia logovania
    $StartMsg = "START napravneho skriptu pre 7-Zip verzie $ScriptVersion"
    Write-Host $StartMsg
    Write-TextLog -Message $StartMsg -Level "INFO"
    
    # Načítanie logovacieho modulu
    try {
        Import-Module LogHelper -ErrorAction Stop
        if (-not (Get-Command Write-CustomLog -ErrorAction SilentlyContinue)) {
            throw "Modul LogHelper neobsahuje funkciu Write-CustomLog"
        }
        Write-CustomLog -Message $StartMsg -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    }
    catch {
        $errorMsg = "UPOZORNENIE: Modul LogHelper sa nepodarilo nacitat, pokracujem iba s textovym logom. $($_.Exception.Message)"
        Write-TextLog -Message $errorMsg -Level "WARN"
    }
    
    # --- 1. UKONČENIE PROCESOV 7-ZIP ---
    Write-TextLog -Message "1/4: Ukoncovanie bezucich procesov 7-Zip" -Level "INFO"
    
    $processNames = @("7z*", "7zg*", "7zfm*", "7zG*", "7zFM*")
    $killedProcesses = @()
    
    foreach ($procName in $processNames) {
        try {
            $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
            foreach ($process in $processes) {
                try {
                    Write-TextLog -Message "Ukoncujem proces: $($process.Name) (PID: $($process.Id))" -Level "WARN"
                    $process.Kill()
                    Start-Sleep -Milliseconds 500
                    if ($process.HasExited) {
                        $killedProcesses += "$($process.Name):$($process.Id)"
                        Write-TextLog -Message "Proces uspesne ukonceny" -Level "INFO"
                    }
                }
                catch {
                    Write-TextLog -Message "Nepodarilo sa ukoncit proces $($process.Name): $($_.Exception.Message)" -Level "ERROR"
                    $script:FailureCount++
                }
            }
        }
        catch { }
    }
    
    Start-Sleep -Seconds 2
    
    # --- 2. ODINŠTALÁCIA Z REGISTRA ---
    Write-TextLog -Message "2/4: Odinstalacia registrovanych verzii 7-Zip" -Level "INFO"
    
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    $foundApps = @()
    
    # Zozbieranie všetkých inštancií
    foreach ($Path in $UninstallPaths) {
        try {
            if (Test-Path $Path) {
                $apps = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.DisplayName -and (
                        $_.DisplayName -like "*7-Zip*" -or 
                        $_.DisplayName -like "*7zip*" -or
                        $_.DisplayName -like "*7z*"
                    )
                }
                
                foreach ($app in $apps) {
                    $foundApps += [PSCustomObject]@{
                        DisplayName     = $app.DisplayName
                        UninstallString = $app.UninstallString
                        KeyPath         = $app.PSPath
                        Publisher       = $app.Publisher
                        Version         = $app.DisplayVersion
                    }
                }
            }
        }
        catch {
            Write-TextLog -Message "Chyba pri pristupe k $Path : $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    if ($foundApps.Count -eq 0) {
        Write-TextLog -Message "REGISTRY: Neboli najdene ziadne registrovane verzie 7-Zip" -Level "INFO"
    }
    else {
        Write-TextLog -Message "REGISTRY: Najdenych $($foundApps.Count) aplikacii na odinstalovanie" -Level "INFO"
        
        foreach ($App in $foundApps) {
            $result = Invoke-SafeUninstall -DisplayName $App.DisplayName -UninstallString $App.UninstallString -KeyPath $App.KeyPath
            
            if (-not $result[0]) {
                $script:FailureCount++
                Write-TextLog -Message "Odinstalacia '$($App.DisplayName)' zlyhala" -Level "ERROR"
            }
            
            Start-Sleep -Seconds 2
        }
    }
    
    # --- 3. ODSTRÁNENIE SÚBOROV A ADRESÁROV ---
    Write-TextLog -Message "3/4: Odstranenie suborov a adresarov 7-Zip" -Level "INFO"
    
    $PathsToDelete = @(
        "$env:ProgramFiles\7-Zip",
        "$env:ProgramFiles(x86)\7-Zip",
        "$env:ProgramFiles\7-Zip x64",
        "$env:AppData\7-Zip",
        "$env:LocalAppData\7-Zip",
        "$env:ProgramData\7-Zip",
        "$env:USERPROFILE\AppData\Roaming\7-Zip",
        "$env:USERPROFILE\AppData\Local\7-Zip"
    )
    
    # Pre každého používateľa v systéme
    try {
        $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue
        foreach ($user in $userFolders) {
            $PathsToDelete += "$($user.FullName)\AppData\Roaming\7-Zip"
            $PathsToDelete += "$($user.FullName)\AppData\Local\7-Zip"
        }
    }
    catch { }
    
    foreach ($Path in $PathsToDelete) {
        if (Test-Path -Path $Path) {
            try {
                Write-TextLog -Message "Odstranujem: $Path" -Level "INFO"
                
                # Ošetrenie dlhých ciest
                $fullPath = if ($Path.Length -gt 240 -and $Path -notlike "\\?\*") {
                    "\\?\$Path"
                }
                else {
                    $Path
                }
                
                Remove-Item -Path $fullPath -Recurse -Force -ErrorAction Stop
                Write-TextLog -Message "Uspesne odstranene: $Path" -Level "INFO"
                $script:SuccessCount++
            }
            catch [System.IO.IOException] {
                Write-TextLog -Message "Subor/Adresar je pouzivany: $Path" -Level "WARN"
                $script:FailureCount++
            }
            catch [System.UnauthorizedAccessException] {
                Write-TextLog -Message "Nedostatocne opravnenia pre: $Path" -Level "ERROR"
                $script:FailureCount++
            }
            catch {
                Write-TextLog -Message "Chyba pri odstranovani $Path : $($_.Exception.Message)" -Level "ERROR"
                $script:FailureCount++
            }
        }
    }
    
    # --- 4. ODSTRÁNENIE ZÁSTUPCU A KONTEXTOVEJ PONUKY ---
    Write-TextLog -Message "4/4: Odstranenie zastupcov a kontextovej ponuky" -Level "INFO"
    
    # Zástupce
    $shortcutPatterns = @(
        "*7-Zip*.lnk",
        "*7z*.lnk"
    )
    
    $shortcutLocations = @(
        "$env:PUBLIC\Desktop",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:USERPROFILE\Desktop",
        "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs"
    )
    
    foreach ($location in $shortcutLocations) {
        foreach ($pattern in $shortcutPatterns) {
            try {
                $shortcuts = Get-ChildItem -Path $location -Filter $pattern -Recurse -ErrorAction SilentlyContinue
                foreach ($shortcut in $shortcuts) {
                    try {
                        Remove-Item -Path $shortcut.FullName -Force -ErrorAction Stop
                        Write-TextLog -Message "Odstraneny zastupca: $($shortcut.FullName)" -Level "INFO"
                        $script:SuccessCount++
                    }
                    catch {
                        Write-TextLog -Message "Nepodarilo sa odstranit zastupca $($shortcut.FullName)" -Level "WARN"
                    }
                }
            }
            catch { }
        }
    }
    
    # Kontextová ponuka
    $contextMenuPaths = @(
        "HKLM:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\7-Zip",
        "HKLM:\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\7-Zip",
        "HKLM:\SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\7-Zip",
        "HKCU:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\7-Zip"
    )
    
    foreach ($path in $contextMenuPaths) {
        try {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-TextLog -Message "Odstranena kontextova ponuka: $path" -Level "INFO"
                $script:SuccessCount++
            }
        }
        catch {
            Write-TextLog -Message "Nepodarilo sa odstranit kontextovu ponuku $path" -Level "WARN"
        }
    }
    
    # --- FINÁLNE VYHODNOTENIE ---
    $totalOperations = $SuccessCount + $FailureCount
    $successRate = if ($totalOperations -gt 0) { [math]::Round(($SuccessCount / $totalOperations) * 100, 2) } else { 100 }
    
    if ($FailureCount -eq 0 -or $successRate -ge 90) {
        $FinalMessage = "USPECH: Odinstalacia 7-Zip dokoncena. Úspešnosť: $successRate% ($SuccessCount/$totalOperations operacii)"
        
        Write-Host $FinalMessage
        Write-TextLog -Message $FinalMessage -Level "INFO"
        
        if ($killedProcesses.Count -gt 0) {
            Write-TextLog -Message "Ukoncene procesy: $($killedProcesses -join ', ')" -Level "INFO"
        }
        
        if (Get-Command Write-CustomLog -ErrorAction SilentlyContinue) {
            Write-CustomLog -Message $FinalMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
        }
        
        exit 0  # ÚSPEŠNÝ STAV
    }
    else {
        $FinalMessage = "CHYBA: Odinstalacia 7-Zip skoncila s $FailureCount chybami. Úspešnosť: $successRate%"
        
        Write-Host $FinalMessage
        Write-TextLog -Message $FinalMessage -Level "ERROR"
        
        if (Get-Command Write-CustomLog -ErrorAction SilentlyContinue) {
            Write-CustomLog -Message $FinalMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
        }
        
        exit 1  # ZLYHANIE NÁPRAVY
    }
}
catch {
    $errorMessage = "FATALNA CHYBA: Neočakávaná chyba skriptu. Popis: $($_.Exception.Message)`nStack: $($_.ScriptStackTrace)"
    
    Write-Host $errorMessage
    Write-TextLog -Message $errorMessage -Level "ERROR"
    
    exit 1  # ZLYHANIE
}