<#
.SYNOPSIS
    Skript na povolenie Remote Registry služby a príslušného firewall pravidla pre Intune remediation
.DESCRIPTION
    Tento skript zabezpečuje správnu konfiguráciu Remote Registry služby pre vzdialený prístup:
    1. Vytvorí/v overí existenciu firewall pravidla pre TCP port 135
    2. Nastaví službu RemoteRegistry na automatické spúšťanie
    3. Spustí službu RemoteRegistry
    4. Overí správny chod služby
    
    Skript je určený pre použitie v Microsoft Intune remediation.
    POZOR: Tento skript vyžaduje spustenie s administrátorskými právami!
.NOTES
    File Name: EnableRegistry.ps1
    Author: TaurisIT
    Version: 2.0.3
    Date Created: 2024-01-01
    Last Modified: 2024-01-01
    
    Changelog:
    v2.0.3 - Pridaná kontrola administrátorských práv
            - Pridaný alternatívny spôsob konfigurácie služby cez sc.exe
            - Vylepšená chybová kontrola
    
    v2.0.2 - Zjednodušené logovanie bez Event Logu pre Intune remediation
    
    Requirements:
    - PowerShell 5.1 alebo novší
    - Administrátorské práva (spustiť ako Administrator)
    - Windows Firewall povolený
    
    Exit Codes:
    0 - Úspech (Remote Registry služba beží)
    1 - Chyba (služba nebeží alebo iná chyba)
    2 - Nedostatočné oprávnenia
#>

# Funkcia na kontrolu administrátorských práv
function Test-AdminRights {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# Nastavenia logovania
$logDirectory = "C:\TaurisIT\Log"
$logFile = "RemoteRegistry.log"
$logPath = Join-Path $logDirectory $logFile

# Jednoduchá logovacia funkcia pre Intune remediation
function Write-SimpleLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    # Vytvor adresár ak neexistuje
    if (!(Test-Path $logDirectory)) {
        try {
            New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            # Fallback na temp adresár
            $logDirectory = "C:\Windows\Temp\TaurisIT"
            $logPath = Join-Path $logDirectory $logFile
            if (!(Test-Path $logDirectory)) {
                New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
            }
        }
    }
    
    # Časová pečiatka
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Zápis do súboru
    try {
        "$timestamp [$Level] $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Záložný zápis
        "$timestamp [$Level] Failed to write to log: $_" | Out-File "C:\Windows\Temp\RemoteRegistry_Error.log" -Append
    }
}

# Kontrola administrátorských práv na začiatku
Write-SimpleLog -Message "=== Starting Remote Registry Configuration Script ===" -Level "INFO"
Write-SimpleLog -Message "Script Version: 2.0.3 | PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"

if (-not (Test-AdminRights)) {
    Write-SimpleLog -Message "ERROR: Script must be run with administrator privileges!" -Level "ERROR"
    Write-SimpleLog -Message "Please run PowerShell as Administrator and execute the script again." -Level "ERROR"
    exit 2
}

Write-SimpleLog -Message "Administrator privileges confirmed" -Level "INFO"

try {
    # Skontroluje, či existuje pravidlo pre TCP port 135
    Write-SimpleLog -Message "Checking firewall rule for TCP port 135" -Level "INFO"
    
    $ruleExists = Get-NetFirewallRule | Where-Object {
        ($_ | Get-NetFirewallPortFilter).LocalPort -contains 135 -and
        ($_ | Get-NetFirewallPortFilter).Protocol -eq "TCP" -and
        $_.Direction -eq "Inbound" -and
        $_.Action -eq "Allow"
    }

    if ($ruleExists) {
        $ruleName = $ruleExists.DisplayName -join ", "
        Write-SimpleLog -Message "Firewall rule for TCP port 135 already exists: $ruleName" -Level "INFO"
    }
    else {
        # Vytvorí nové pravidlo
        Write-SimpleLog -Message "Creating firewall rule for TCP port 135" -Level "INFO"
        
        try {
            New-NetFirewallRule -DisplayName "Allow Remote Registry (TCP 135)" `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 135 `
                -Action Allow `
                -Profile Any `
                -Enabled True -ErrorAction Stop

            Write-SimpleLog -Message "Firewall rule for TCP port 135 created successfully" -Level "SUCCESS"
        }
        catch {
            Write-SimpleLog -Message "Failed to create firewall rule: $_" -Level "ERROR"
            # Pokračujeme, firewall rule nie je vždy povinný pre Remote Registry
        }
    }

    # Nastaví službu RemoteRegistry na automatické spúšťanie - alternatívne metódy
    Write-SimpleLog -Message "Configuring RemoteRegistry service startup type" -Level "INFO"
    
    $serviceConfigured = $false
    
    # Metóda 1: Skúsime cez Set-Service
    try {
        Set-Service -Name RemoteRegistry -StartupType Automatic -ErrorAction Stop
        Write-SimpleLog -Message "Service startup type set to Automatic via Set-Service" -Level "INFO"
        $serviceConfigured = $true
    }
    catch {
        Write-SimpleLog -Message "Set-Service failed: $_" -Level "WARN"
        
        # Metóda 2: Skúsime cez sc.exe (často funguje aj keď Set-Service zlyhá)
        try {
            Write-SimpleLog -Message "Attempting to configure service via sc.exe" -Level "INFO"
            $scResult = sc.exe config RemoteRegistry start= auto
            if ($LASTEXITCODE -eq 0) {
                Write-SimpleLog -Message "Service startup type set to Automatic via sc.exe" -Level "INFO"
                $serviceConfigured = $true
            }
            else {
                Write-SimpleLog -Message "sc.exe failed with exit code $LASTEXITCODE - $scResult" -Level "WARN"
            }
        }
        catch {
            Write-SimpleLog -Message "sc.exe also failed: $_" -Level "ERROR"
        }
        
        # Metóda 3: Skúsime cez WMI
        if (-not $serviceConfigured) {
            try {
                Write-SimpleLog -Message "Attempting to configure service via WMI" -Level "INFO"
                $service = Get-WmiObject -Class Win32_Service -Filter "Name='RemoteRegistry'"
                if ($service) {
                    $service.ChangeStartMode("Automatic")
                    Write-SimpleLog -Message "Service startup type set to Automatic via WMI" -Level "INFO"
                    $serviceConfigured = $true
                }
            }
            catch {
                Write-SimpleLog -Message "WMI method failed: $_" -Level "ERROR"
            }
        }
    }

    if (-not $serviceConfigured) {
        Write-SimpleLog -Message "WARNING: Could not configure service startup type. Service might already be configured." -Level "WARN"
    }

    # Spustí službu
    Write-SimpleLog -Message "Starting RemoteRegistry service" -Level "INFO"
    
    $serviceStarted = $false
    
    # Metóda 1: Skúsime cez Start-Service
    try {
        Start-Service -Name RemoteRegistry -ErrorAction Stop
        Write-SimpleLog -Message "Service started via Start-Service" -Level "INFO"
        $serviceStarted = $true
    }
    catch {
        Write-SimpleLog -Message "Start-Service failed: $_" -Level "WARN"
        
        # Metóda 2: Skúsime cez sc.exe
        try {
            Write-SimpleLog -Message "Attempting to start service via sc.exe" -Level "INFO"
            $scResult = sc.exe start RemoteRegistry
            if ($LASTEXITCODE -eq 0) {
                Write-SimpleLog -Message "Service started via sc.exe" -Level "INFO"
                $serviceStarted = $true
            }
            else {
                Write-SimpleLog -Message "sc.exe start failed with exit code $LASTEXITCODE - $scResult" -Level "WARN"
            }
        }
        catch {
            Write-SimpleLog -Message "sc.exe start also failed: $_" -Level "ERROR"
        }
    }

    # Počká chvíľu, aby sa služba stihla spustiť
    Start-Sleep -Seconds 5

    # Skontroluje stav služby
    $service = Get-Service -Name RemoteRegistry -ErrorAction SilentlyContinue

    if ($service -and $service.Status -eq 'Running') {
        Write-SimpleLog -Message "RemoteRegistry service is running successfully" -Level "SUCCESS"
        
        # Vyčisti staré logy (>30 dní)
        try {
            $cutoffDate = (Get-Date).AddDays(-30)
            $oldLogs = Get-ChildItem -Path $logDirectory -Include "*.log", "*.txt" -Recurse -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate }
            
            if ($oldLogs) {
                $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-SimpleLog -Message "Cleaned $($oldLogs.Count) old log files" -Level "INFO"
            }
        }
        catch {
            Write-SimpleLog -Message "Log cleanup failed: $_" -Level "WARN"
        }
        
        Write-SimpleLog -Message "=== Remote Registry Configuration Completed Successfully ===" -Level "SUCCESS"
        
        exit 0
    }
    else {
        $status = if ($service) { $service.Status } else { "Service not found" }
        Write-SimpleLog -Message "RemoteRegistry service is NOT running. Current status: $status" -Level "ERROR"
        
        # Skúsime získať viac informácií o chybe
        try {
            $serviceInfo = Get-WmiObject -Class Win32_Service -Filter "Name='RemoteRegistry'" -ErrorAction SilentlyContinue
            if ($serviceInfo) {
                Write-SimpleLog -Message "Service details - State: $($serviceInfo.State), StartMode: $($serviceInfo.StartMode)" -Level "INFO"
            }
        }
        catch {
            # Ignorovať chybu
        }
        
        Write-SimpleLog -Message "=== Remote Registry Configuration Failed ===" -Level "ERROR"
        
        exit 1
    }
}
catch {
    Write-SimpleLog -Message "Unhandled error: $($_.Exception.Message)" -Level "ERROR"
    Write-SimpleLog -Message "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    Write-SimpleLog -Message "=== Script Execution Terminated with Error ===" -Level "ERROR"
    
    exit 1
}