<#
.SYNOPSIS
    Detekcny skript pre overenie pritomnosti vsetkych verzii aplikacie 7-Zip.
    Určene pre Intune Proactive Remediations.

.DESCRIPTION
    Skript vyhladava vsetky instalovane verzie 7-Zip v registroch (32-bit, 64-bit, HKCU) 
    a na disku (súbory, procesy, zástupce).
    Vrati exit code 0, ak je 7-Zip stale nainstalovany/pritomny (PROBLEM NAJDENY).
    Vrati exit code 1, ak 7-Zip nainstalovany nie je (PROBLEM NENAJDENY).

.AUTHOR
    Marek Findrik (Adaptacia a rozsirenie pre 7-Zip)

.CREATED
    2025-11-25

.VERSION
    1.3.0

.NOTES
    - Skript vyzaduje predinstalovany modul 'LogHelper'.
    - Loguje vysledok detekcie do C:\TaurisIT\Log\Detect7-zip.log a paralelne aj do Detect7-zip.txt.
    - Vyžaduje administrátorské práva.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# --- KONFIGURACIA ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptVersion = "1.3.0"
$EventSource = "7Zip-Detection-Intune-Remediation"
$LogFileName = "Detect7-zip.log" 
$LogDirectory = "C:\TaurisIT\Log"
$TextLogFile = Join-Path $LogDirectory "Detect7-zip.txt"

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

# --- FUNKCIA PRE VYHLADAVANIE V SYSTEME SUBOROV ---
function Find-7ZipExecutable {
    <#
    .SYNOPSIS
        Vyhladava spustitelne subory 7-Zip v spolocnych cestach.
    .OUTPUTS
        Boolean. $true, ak sa subor najde, inak $false.
    #>
    $ExecutableNames = @("7zG.exe", "7zFM.exe", "7z.exe", "7zG64.exe", "7z64.exe", "7-Zip*.exe")
    $SearchPaths = @(
        "$env:ProgramFiles\7-Zip",
        "$env:ProgramFiles(x86)\7-Zip",
        "${env:ProgramFiles}\7-Zip x64",
        "${env:ProgramFiles(x86)}\7-Zip", 
        "$env:AppData\7-Zip",
        "$env:LocalAppData\7-Zip",
        "$env:ProgramData\7-Zip",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop"
    )
    
    # Pridanie ciest z PATH premennej
    $envPaths = $env:PATH -split ';' | Where-Object { $_ -and (Test-Path $_) }
    $SearchPaths += $envPaths | Select-Object -Unique
    
    Write-TextLog -Message "FILESYSTEM: Start vyhladavania suborov 7-Zip" -Level "INFO"
    
    $foundFiles = @()
    
    # Vyhľadávanie v konkrétnych cestách
    foreach ($Path in $SearchPaths) {
        if (Test-Path -Path $Path -PathType Container) {
            foreach ($Exe in $ExecutableNames) {
                try {
                    $files = Get-ChildItem -Path $Path -Filter $Exe -Recurse -ErrorAction SilentlyContinue -File
                    foreach ($file in $files) {
                        $foundFiles += $file.FullName
                        Write-TextLog -Message "FILESYSTEM: Najdeny spustitelny subor: $($file.FullName)" -Level "WARN"
                    }
                }
                catch {
                    Write-TextLog -Message "FILESYSTEM: Chyba pri skenovaní $Path : $($_.Exception.Message)" -Level "ERROR"
                }
            }
        }
    }
    
    # Dodatočné vyhľadávanie v celom systéme (obmedzené)
    if ($foundFiles.Count -eq 0) {
        Write-TextLog -Message "FILESYSTEM: Vyhladavanie v systemových diskoch..." -Level "INFO"
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like "*:*" } | Select-Object -First 2
        
        foreach ($drive in $drives) {
            foreach ($Exe in @("7z.exe", "7zG.exe")) {
                try {
                    $file = Get-ChildItem -Path $drive.Root -Filter $Exe -Recurse -ErrorAction SilentlyContinue -File | Select-Object -First 1
                    if ($file) {
                        $foundFiles += $file.FullName
                        Write-TextLog -Message "FILESYSTEM: Najdeny v systeme: $($file.FullName)" -Level "WARN"
                        break
                    }
                }
                catch { continue }
            }
            if ($foundFiles.Count -gt 0) { break }
        }
    }
    
    if ($foundFiles.Count -gt 0) {
        Write-TextLog -Message "FILESYSTEM: Celkovo najdenych $($foundFiles.Count) suborov" -Level "INFO"
        return $true
    }
    
    Write-TextLog -Message "FILESYSTEM: Ziaden spustitelny subor 7-Zip nebol najdeny" -Level "INFO"
    return $false
}

# --- FUNKCIA PRE KONTROLU ZASTUPCU ---
function Test-7ZipShortcuts {
    <#
    .SYNOPSIS
        Kontroluje prítomnosť zástupcov 7-Zip.
    #>
    $shortcutPaths = @(
        "$env:PUBLIC\Desktop\7-Zip*.lnk",
        "$env:USERPROFILE\Desktop\7-Zip*.lnk",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\7-Zip",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\7-Zip*.lnk",
        "$env:PUBLIC\Desktop\7z*.lnk"
    )
    
    foreach ($path in $shortcutPaths) {
        if (Test-Path -Path $path) {
            $shortcuts = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            foreach ($shortcut in $shortcuts) {
                Write-TextLog -Message "SHORTCUT: Najdeny zástupca: $($shortcut.FullName)" -Level "WARN"
            }
            if ($shortcuts.Count -gt 0) {
                return $true
            }
        }
    }
    
    return $false
}

# --- HLAVNY SKRIPT ---
try {
    # Vytvorenie logovacieho adresára
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Inicializácia logovania
    $StartMsg = "START detekcneho skriptu pre 7-Zip verzie $ScriptVersion"
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
        $errorMsg = "CHYBA: Modul LogHelper sa nepodarilo nacitat! $($_.Exception.Message)"
        Write-TextLog -Message $errorMsg -Level "ERROR"
        Write-Host $errorMsg
        # Pokracujeme bez modulu, iba s textovym logom
    }
    
    # Premenné pre výsledky
    $detectionResults = @{
        Registry    = $false
        Filesystem  = $false
        Processes   = $false
        Shortcuts   = $false
        ContextMenu = $false
    }
    
    # --- 1. KONTROLA REGISTROV ---
    Write-TextLog -Message "REGISTRY: Start vyhladavania v registroch" -Level "INFO"
    
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    $foundRegistryEntries = @()
    
    foreach ($Path in $UninstallPaths) {
        try {
            if (Test-Path $Path) {
                $entries = Get-ChildItem -Path $Path -ErrorAction Stop | 
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.DisplayName -and (
                        $_.DisplayName -like "*7-Zip*" -or 
                        $_.DisplayName -like "*7zip*" -or
                        $_.DisplayName -like "*7z*"
                    )
                }
                
                if ($entries) {
                    foreach ($entry in $entries) {
                        $foundRegistryEntries += [PSCustomObject]@{
                            DisplayName     = $entry.DisplayName
                            UninstallString = $entry.UninstallString
                            Path            = $entry.PSPath
                        }
                        Write-TextLog -Message "REGISTRY: Najdeny vstup: $($entry.DisplayName) v $Path" -Level "WARN"
                    }
                }
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-TextLog -Message "REGISTRY: Nedostatocne opravnenia pre pristup k $Path" -Level "ERROR"
        }
        catch {
            Write-TextLog -Message "REGISTRY: Chyba pri pristupe k $Path : $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    # Kontrola kontextovej ponuky
    try {
        $contextMenuPath = "HKLM:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\7-Zip"
        if (Test-Path $contextMenuPath) {
            $detectionResults.ContextMenu = $true
            Write-TextLog -Message "REGISTRY: Najdeny kontextovy menu handler 7-Zip" -Level "WARN"
        }
    }
    catch {
        Write-TextLog -Message "REGISTRY: Chyba pri kontrole kontextoveho menu" -Level "ERROR"
    }
    
    $detectionResults.Registry = ($foundRegistryEntries.Count -gt 0) -or $detectionResults.ContextMenu
    
    # --- 2. KONTROLA FILESYSTEMU ---
    $detectionResults.Filesystem = Find-7ZipExecutable
    
    # --- 3. KONTROLA PROCESOV ---
    Write-TextLog -Message "PROCESS: Kontrola bezucich procesov 7-Zip" -Level "INFO"
    
    $processNames = @("7z*", "7zg*", "7zfm*")
    $runningProcesses = @()
    
    foreach ($procName in $processNames) {
        try {
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
            foreach ($proc in $procs) {
                $runningProcesses += $proc
                Write-TextLog -Message "PROCESS: Beziaci proces: $($proc.Name) (PID: $($proc.Id))" -Level "WARN"
            }
        }
        catch { continue }
    }
    
    $detectionResults.Processes = ($runningProcesses.Count -gt 0)
    
    # --- 4. KONTROLA ZÁSTUPCU ---
    $detectionResults.Shortcuts = Test-7ZipShortcuts
    
    # --- CELKOVÉ VYHODNOTENIE ---
    $isInstalled = $detectionResults.Values -contains $true
    
    if ($isInstalled) {
        $sources = @()
        if ($detectionResults.Registry) { $sources += "Registry" }
        if ($detectionResults.Filesystem) { $sources += "Filesystem" }
        if ($detectionResults.Processes) { $sources += "Procesy" }
        if ($detectionResults.Shortcuts) { $sources += "Zástupce" }
        if ($detectionResults.ContextMenu) { $sources += "ContextMenu" }
        
        $sourceStr = $sources -join ", "
        $message = "DETEKCIA: 7-Zip je stale pritomny ($sourceStr) - PROBLEM NAJDENY"
        
        # Detailný výpis
        $details = @"
Detailná detekcia:
- Registry: $($detectionResults.Registry) ($($foundRegistryEntries.Count) vstupov)
- Filesystem: $($detectionResults.Filesystem)
- Beziace procesy: $($detectionResults.Processes) ($($runningProcesses.Count) procesov)
- Zástupce: $($detectionResults.Shortcuts)
- Context Menu: $($detectionResults.ContextMenu)
"@
        
        Write-Host $message
        Write-TextLog -Message $message -Level "WARN"
        Write-TextLog -Message $details -Level "INFO"
        
        # Log do Event Logu (ak je modul dostupný)
        if (Get-Command Write-CustomLog -ErrorAction SilentlyContinue) {
            Write-CustomLog -Message $message -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
        }
        
        # Vypis detailov na konzolu pre Intune
        Write-Host $details
        
        exit 0  # PROBLEM NAJDENY - spustí sa náprava
    }
    else {
        $message = "DETEKCIA: 7-Zip nie je pritomny - PROBLEM NENAJDENY"
        
        Write-Host $message
        Write-TextLog -Message $message -Level "INFO"
        
        if (Get-Command Write-CustomLog -ErrorAction SilentlyContinue) {
            Write-CustomLog -Message $message -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
        }
        
        exit 1  # PROBLEM NENAJDENY - nespustí sa náprava
    }
}
catch {
    $errorMessage = "FATALNA CHYBA: Zlyhanie skriptu. Popis: $($_.Exception.Message)`nStack: $($_.ScriptStackTrace)"
    
    Write-Host $errorMessage
    Write-TextLog -Message $errorMessage -Level "ERROR"
    
    # V prípade chyby považujeme za problém nájdený (fail-safe)
    exit 0
}