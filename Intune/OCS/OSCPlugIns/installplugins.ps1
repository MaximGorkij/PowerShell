<#
.SYNOPSIS
    Instalacny skript pre ScriptCopy - Intune Package
.DESCRIPTION
    Nakopiruje PS1 skripty eventlogs.ps1, userinstalledapps.ps1 a winusers.ps1
    zo zdrojoveho adresara do cieloveho umiestnenia,
    vytvori potrebne adresare a zaznamenava akcie do log suboru a Event Logu.
    Podporuje parameter -ForceUpdate pre aktualizaciu existujucich skriptov.
    Po uspesnom kopirovani restartuje OCS Inventory Service.
.AUTHOR
    Marek Findrik
.CREATED
    2025-10-03
.VERSION
    1.5
.NOTES
    Optimalizovane pre nasadenie cez Microsoft Intune.
    Spusta sa automaticky s SYSTEM pravami.
    Loguje do konzoly, suboru a event logu cez LogHelper modul.
    Vylepšená diagnostika a error handling.
#>

[CmdletBinding()]
param (
    [switch]$ForceUpdate
)

# --------------------------------------------------------------------
# Konfiguracia
# --------------------------------------------------------------------
$Config = @{
    ScriptPath    = "$PSScriptRoot\Files"
    TargetPath    = "C:\Program Files\OCS Inventory Agent\Plugins"
    LogPath       = "C:\TaurisIT\Log\OCSPlugIns"
    EventLogName  = "IntuneScript"
    EventSource   = "OCS PlugIns"
    ServiceName   = "OCS Inventory Service"
    RequiredFiles = @("eventlogs.ps1", "userinstalledapps.ps1", "winusers.ps1")
}

# --------------------------------------------------------------------
# Pomocne funkcie pre diagnostiku
# --------------------------------------------------------------------
function Write-DiagnosticInfo {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] DIAGNOSTIC: $Message" -ForegroundColor Cyan
}

function Write-FallbackLog {
    param(
        [string]$Message,
        [string]$Type = "Information"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    
    # Console output
    $color = switch ($Type) {
        "Error"   { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
    
    # Pokus o zapis do suboru
    try {
        $fallbackLogPath = "C:\Windows\Temp\OCS_Install_Fallback.log"
        Add-Content -Path $fallbackLogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch { }
}

# --------------------------------------------------------------------
# Pre-flight checks
# --------------------------------------------------------------------
Write-DiagnosticInfo "=== ZACIATOK DIAGNOSTIKY ==="
Write-DiagnosticInfo "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-DiagnosticInfo "Execution Policy: $(Get-ExecutionPolicy)"
Write-DiagnosticInfo "Script Root: $PSScriptRoot"
Write-DiagnosticInfo "Working Directory: $(Get-Location)"
Write-DiagnosticInfo "Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# Kontrola admin prav
try {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-DiagnosticInfo "Is Admin: $isAdmin"
}
catch {
    Write-DiagnosticInfo "Is Admin: Unable to determine"
}

Write-DiagnosticInfo "ForceUpdate: $ForceUpdate"

# --------------------------------------------------------------------
# Inicializacia
# --------------------------------------------------------------------
$LogHelperAvailable = $false
$LogFileName = $null

try {
    # Vytvor log adresar ak neexistuje
    Write-DiagnosticInfo "Vytvaranie log adresara: $($Config.LogPath)"
    if (!(Test-Path $Config.LogPath)) {
        New-Item -ItemType Directory -Path $Config.LogPath -Force -ErrorAction Stop | Out-Null
        Write-DiagnosticInfo "Log adresar vytvoreny uspesne"
    }
    else {
        Write-DiagnosticInfo "Log adresar uz existuje"
    }
    
    $LogFileName = Join-Path $Config.LogPath ("ScriptCopy_{0}.txt" -f (Get-Date -Format "yyyyMMdd"))
    Write-DiagnosticInfo "Log subor: $LogFileName"

    # Import LogHelper s detailnou diagnostikou
    Write-DiagnosticInfo "Pokus o import LogHelper modulu..."
    
    $logHelperModule = Get-Module -ListAvailable -Name LogHelper
    if ($logHelperModule) {
        Write-DiagnosticInfo "LogHelper modul najdeny na: $($logHelperModule.Path)"
        Import-Module LogHelper -Force -ErrorAction Stop
        $LogHelperAvailable = $true
        Write-DiagnosticInfo "LogHelper modul uspesne naimportovany"
        
        Write-CustomLog -Message "Spustenie ScriptCopy instalacneho skriptu v1.5" -EventSource $Config.EventSource -EventLogName $Config.EventLogName -LogFileName $LogFileName -Type Information
        Write-CustomLog -Message "Diagnostika: PSVersion=$($PSVersionTable.PSVersion), User=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -EventSource $Config.EventSource -EventLogName $Config.EventLogName -LogFileName $LogFileName -Type Information
    }
    else {
        Write-DiagnosticInfo "VAROVANIE: LogHelper modul nebol najdeny"
        Write-FallbackLog -Message "LogHelper modul nie je dostupny, pouzivam fallback logovanie" -Type "Warning"
        
        # Skontroluj PSModulePath
        Write-DiagnosticInfo "PSModulePath:"
        $env:PSModulePath -split ';' | ForEach-Object {
            Write-DiagnosticInfo "  - $_"
        }
        
        throw "Modul LogHelper nie je dostupny."
    }
}
catch {
    $errorMsg = "CHYBA INICIALIZACIE: $($_.Exception.Message)"
    Write-FallbackLog -Message $errorMsg -Type "Error"
    Write-FallbackLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Type "Error"
    
    # Pokus o zapis do event logu priamo ak LogHelper zlyhal
    try {
        Write-DiagnosticInfo "Pokus o priamy zapis do Event Logu..."
        if (-not [System.Diagnostics.EventLog]::SourceExists($Config.EventSource)) {
            Write-DiagnosticInfo "Vytvaranie Event Log source: $($Config.EventSource)"
            [System.Diagnostics.EventLog]::CreateEventSource($Config.EventSource, $Config.EventLogName)
            Start-Sleep -Seconds 2
        }
        Write-EventLog -LogName $Config.EventLogName -Source $Config.EventSource -EventId 1401 -EntryType Error -Message $errorMsg
        Write-DiagnosticInfo "Event Log zapis uspesny"
    }
    catch { 
        Write-DiagnosticInfo "Event Log zapis zlyhal: $($_.Exception.Message)"
    }
    
    Write-DiagnosticInfo "=== KONIEC DIAGNOSTIKY (FAILED) ==="
    exit 1
}

# --------------------------------------------------------------------
# Funkcie
# --------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"
    )
    
    if ($LogHelperAvailable) {
        Write-CustomLog -Message $Message -EventSource $Config.EventSource -EventLogName $Config.EventLogName -LogFileName $LogFileName -Type $Type
    }
    else {
        Write-FallbackLog -Message $Message -Type $Type
    }
}

function Restart-OCSService {
    param(
        [string]$ServiceName
    )
    
    try {
        Write-Host "Kontrola stavu sluzby: $ServiceName" -ForegroundColor Cyan
        Write-Log -Message "Kontrola stavu sluzby: $ServiceName" -Type Information
        
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        Write-DiagnosticInfo "Sluzba status: $($service.Status)"
        
        if ($service.Status -eq 'Running') {
            Write-Host "Restartujem sluzbu: $ServiceName" -ForegroundColor Yellow
            Write-Log -Message "Restartujem sluzbu: $ServiceName" -Type Information
            
            Restart-Service -Name $ServiceName -Force -ErrorAction Stop
            
            # Cakaj kym sa sluzba kompletne restartuje (max 30 sekund)
            $timeout = 30
            $elapsed = 0
            do {
                Start-Sleep -Seconds 2
                $elapsed += 2
                $service.Refresh()
                Write-DiagnosticInfo "Cakam na restart sluzby... ($elapsed/$timeout s) Status: $($service.Status)"
            } while ($service.Status -ne 'Running' -and $elapsed -lt $timeout)
            
            if ($service.Status -eq 'Running') {
                Write-Host "Sluzba uspesne restartovana: $ServiceName" -ForegroundColor Green
                Write-Log -Message "Sluzba uspesne restartovana: $ServiceName" -Type Information
                return $true
            }
            else {
                Write-Host "Varovanie: Sluzba po restarte nie je spustena: $ServiceName (Status: $($service.Status))" -ForegroundColor Yellow
                Write-Log -Message "Varovanie: Sluzba po restarte nie je spustena: $ServiceName (Status: $($service.Status))" -Type Warning
                return $false
            }
        }
        elseif ($service.Status -eq 'Stopped') {
            Write-Host "Sluzba je zastavena, spustam: $ServiceName" -ForegroundColor Yellow
            Write-Log -Message "Sluzba je zastavena, spustam: $ServiceName" -Type Information
            
            Start-Service -Name $ServiceName -ErrorAction Stop
            Start-Sleep -Seconds 3
            $service.Refresh()
            
            if ($service.Status -eq 'Running') {
                Write-Host "Sluzba uspesne spustena: $ServiceName" -ForegroundColor Green
                Write-Log -Message "Sluzba uspesne spustena: $ServiceName" -Type Information
                return $true
            }
            else {
                Write-Host "Nepodarilo sa spustit sluzbu: $ServiceName (Status: $($service.Status))" -ForegroundColor Red
                Write-Log -Message "Nepodarilo sa spustit sluzbu: $ServiceName (Status: $($service.Status))" -Type Error
                return $false
            }
        }
        else {
            Write-Host "Neocakavany stav sluzby: $ServiceName (Status: $($service.Status))" -ForegroundColor Yellow
            Write-Log -Message "Neocakavany stav sluzby: $ServiceName (Status: $($service.Status))" -Type Warning
            return $null
        }
    }
    catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
        if ($_.Exception.Message -like "*Cannot find any service*") {
            Write-Host "Sluzba nebola najdena: $ServiceName" -ForegroundColor Yellow
            Write-Log -Message "Sluzba nebola najdena: $ServiceName" -Type Warning
            return $null
        }
        else {
            throw
        }
    }
    catch {
        Write-Host "Chyba pri praci so sluzbou $ServiceName : $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Message "Chyba pri praci so sluzbou $ServiceName : $($_.Exception.Message)" -Type Error
        return $false
    }
}

function Test-RequiredFiles {
    param(
        [string]$SourcePath,
        [string[]]$FileNames
    )
    
    Write-DiagnosticInfo "Kontrola zdrojoveho adresara: $SourcePath"
    $missingFiles = @()
    
    foreach ($fileName in $FileNames) {
        $filePath = Join-Path $SourcePath $fileName
        Write-DiagnosticInfo "Kontrola suboru: $filePath"
        
        if (-not (Test-Path $filePath)) {
            $missingFiles += $fileName
            Write-DiagnosticInfo "  -> CHYBA: Subor nenajdeny!"
        }
        else {
            $fileInfo = Get-Item $filePath
            Write-DiagnosticInfo "  -> OK (Velkost: $($fileInfo.Length) bytes, Modified: $($fileInfo.LastWriteTime))"
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        $errorMsg = "Chybajuce subory v zdrojovom adresari '$SourcePath': $($missingFiles -join ', ')"
        Write-Host $errorMsg -ForegroundColor Red
        Write-Log -Message $errorMsg -Type Error
        
        # Vypis vsetky subory v adresari pre diagnostiku
        Write-DiagnosticInfo "Dostupne subory v zdrojovom adresari:"
        try {
            Get-ChildItem -Path $SourcePath -ErrorAction Stop | ForEach-Object {
                Write-DiagnosticInfo "  - $($_.Name)"
            }
        }
        catch {
            Write-DiagnosticInfo "Nemozem vypis obsah adresara: $($_.Exception.Message)"
        }
        
        return $false
    }
    
    Write-Host "Vsetky pozadovane subory su pritomne v zdrojovom adresari" -ForegroundColor Green
    Write-Log -Message "Vsetky pozadovane subory su pritomne v zdrojovom adresari" -Type Information
    return $true
}

# --------------------------------------------------------------------
# Hlavna logika
# --------------------------------------------------------------------
try {
    Write-DiagnosticInfo "=== ZACIATOK HLAVNEJ LOGIKY ==="
    
    # Overenie zdrojoveho adresara
    Write-DiagnosticInfo "Overenie zdrojoveho adresara: $($Config.ScriptPath)"
    if (!(Test-Path $Config.ScriptPath)) {
        $errorMsg = "Zdrojovy adresar neexistuje: $($Config.ScriptPath)"
        Write-Host $errorMsg -ForegroundColor Red
        Write-Log -Message $errorMsg -Type Error
        
        # Skus alternativne cesty
        $alternativePaths = @(
            "$PSScriptRoot\Files",
            "$PSScriptRoot",
            ".\Files"
        )
        
        Write-DiagnosticInfo "Pokus o najdenie alternativnej cesty..."
        foreach ($altPath in $alternativePaths) {
            Write-DiagnosticInfo "  Skusam: $altPath"
            if (Test-Path $altPath) {
                Write-DiagnosticInfo "    -> Najdene!"
                $Config.ScriptPath = $altPath
                break
            }
        }
        
        if (!(Test-Path $Config.ScriptPath)) {
            Write-DiagnosticInfo "Ziadna alternativna cesta nebola najdena"
            exit 1
        }
    }

    # Kontrola pritomnosti vsetkych pozadovanych suborov
    $filesCheck = Test-RequiredFiles -SourcePath $Config.ScriptPath -FileNames $Config.RequiredFiles
    if (-not $filesCheck) {
        Write-DiagnosticInfo "Kontrola suborov zlyhala"
        exit 1
    }

    # Vytvor cielovy adresar
    Write-DiagnosticInfo "Overenie/vytvorenie cieloveho adresara: $($Config.TargetPath)"
    if (!(Test-Path $Config.TargetPath)) {
        New-Item -ItemType Directory -Path $Config.TargetPath -Force -ErrorAction Stop | Out-Null
        $message = "Vytvoreny cielovy adresar: $($Config.TargetPath)"
        Write-Host $message -ForegroundColor Green
        Write-Log -Message $message -Type Information
    }
    else {
        Write-DiagnosticInfo "Cielovy adresar uz existuje"
    }

    # Spracovanie suborov
    $stats = @{
        New     = 0
        Updated = 0
        Skipped = 0
        Errors  = 0
    }

    $needsRestart = $false

    Write-DiagnosticInfo "=== SPRACOVANIE SUBOROV ==="
    foreach ($fileName in $Config.RequiredFiles) {
        $sourceFile = Join-Path $Config.ScriptPath $fileName
        $destinationFile = Join-Path $Config.TargetPath $fileName
        
        Write-DiagnosticInfo "Spracovavam: $fileName"
        Write-DiagnosticInfo "  Zdroj: $sourceFile"
        Write-DiagnosticInfo "  Ciel: $destinationFile"
        
        try {
            if (!(Test-Path $destinationFile)) {
                # Novy subor
                Write-DiagnosticInfo "  Akcia: NOVA INSTALACIA"
                Copy-Item -Path $sourceFile -Destination $destinationFile -Force -ErrorAction Stop
                $stats.New++
                $needsRestart = $true
                $message = "Kopirovany novy subor: $fileName"
                Write-Host $message -ForegroundColor Green
                Write-Log -Message $message -Type Information
            }
            elseif ($ForceUpdate) {
                # Aktualizacia existujuceho suboru
                Write-DiagnosticInfo "  Akcia: AKTUALIZACIA (ForceUpdate=true)"
                
                # Vytvor zalohu
                $backupFile = "$destinationFile.backup_$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -Path $destinationFile -Destination $backupFile -Force -ErrorAction SilentlyContinue
                Write-DiagnosticInfo "  Zaloha vytvorena: $backupFile"
                
                Copy-Item -Path $sourceFile -Destination $destinationFile -Force -ErrorAction Stop
                $stats.Updated++
                $needsRestart = $true
                $message = "Aktualizovany subor: $fileName"
                Write-Host $message -ForegroundColor Yellow
                Write-Log -Message $message -Type Warning
            }
            else {
                # Subor uz existuje
                Write-DiagnosticInfo "  Akcia: PRESKOCENY (existuje, ForceUpdate=false)"
                $stats.Skipped++
                Write-Host "Subor uz existuje (preskoceny): $fileName" -ForegroundColor Gray
                Write-Log -Message "Subor uz existuje (preskoceny): $fileName" -Type Information
            }
            
            # Overenie ze subor bol uspesne skopirovany
            if (Test-Path $destinationFile) {
                $destInfo = Get-Item $destinationFile
                Write-DiagnosticInfo "  Overenie: OK (Velkost: $($destInfo.Length) bytes)"
            }
            else {
                Write-DiagnosticInfo "  VAROVANIE: Cielovy subor nebol najdeny po kopii!"
            }
        }
        catch {
            $stats.Errors++
            $errorMsg = "Chyba pri spracovani suboru $fileName : $($_.Exception.Message)"
            Write-Host $errorMsg -ForegroundColor Red
            Write-Log -Message $errorMsg -Type Error
            Write-DiagnosticInfo "  ERROR: $($_.Exception.Message)"
            Write-DiagnosticInfo "  Stack: $($_.ScriptStackTrace)"
        }
    }

    Write-DiagnosticInfo "=== STATISTIKA SPRACOVANIA ==="
    Write-DiagnosticInfo "Nove: $($stats.New)"
    Write-DiagnosticInfo "Aktualizovane: $($stats.Updated)"
    Write-DiagnosticInfo "Preskocene: $($stats.Skipped)"
    Write-DiagnosticInfo "Chyby: $($stats.Errors)"
    Write-DiagnosticInfo "Potrebny restart: $needsRestart"

    # Restart sluzby ak boli vykonane zmeny
    if ($needsRestart -and ($stats.New -gt 0 -or $stats.Updated -gt 0)) {
        Write-Host "Boli vykonane zmeny v suboroch, restartujem sluzbu..." -ForegroundColor Cyan
        Write-Log -Message "Boli vykonane zmeny v suboroch, restartujem sluzbu..." -Type Information
        
        $serviceResult = Restart-OCSService -ServiceName $Config.ServiceName
        
        if ($serviceResult -eq $true) {
            $restartMessage = "Sluzba '$($Config.ServiceName)' bola uspesne restartovana po zmene suborov"
        }
        elseif ($serviceResult -eq $false) {
            $restartMessage = "Nepodarilo sa restartovat sluzbu '$($Config.ServiceName)' po zmene suborov"
        }
        else {
            $restartMessage = "Sluzba '$($Config.ServiceName)' nebola najdena, restart nebol vykonany"
        }
    }
    else {
        $restartMessage = "Neboli vykonane ziadne zmeny v suboroch, restart sluzby nie je potrebny"
    }

    # Finalna sprava
    $completionMessage = @"
Kopirovanie OCS Inventory pluginov dokoncene.
Spracovane subory: $($Config.RequiredFiles -join ', ')
Statistika: Nove: $($stats.New), Aktualizovane: $($stats.Updated), Preskočene: $($stats.Skipped), Chyby: $($stats.Errors)
$restartMessage
"@
    
    Write-Host $completionMessage -ForegroundColor Cyan
    Write-Log -Message $completionMessage -Type Information
    
    Write-DiagnosticInfo "=== KONIEC DIAGNOSTIKY (SUCCESS) ==="
    
    # Exit kod podla chyb
    if ($stats.Errors -gt 0) {
        Write-DiagnosticInfo "Exit kod: 1 (Chyby detegované)"
        exit 1
    }
    else {
        Write-DiagnosticInfo "Exit kod: 0 (Uspech)"
        exit 0
    }
}
catch {
    $errorMsg = "NEOCAKAVANA CHYBA: $($_.Exception.Message)"
    Write-Host $errorMsg -ForegroundColor Red
    Write-Log -Message $errorMsg -Type Error
    Write-DiagnosticInfo "FATAL ERROR: $($_.Exception.Message)"
    Write-DiagnosticInfo "Stack Trace: $($_.ScriptStackTrace)"
    Write-DiagnosticInfo "=== KONIEC DIAGNOSTIKY (FATAL ERROR) ==="
    exit 1
}