<#
.SYNOPSIS
    Kompletný LogHelper modul pre Intune remediation skripty
.DESCRIPTION
    Modul zabezpečuje komplexné logovanie do súborov, Event Logu a správu logov.
    Obsahuje všetky funkcie potrebné pre remediation skripty.
.AUTHOR
    Marek Findrik / TaurisIT
.CREATED
    2025-09-05
.VERSION
    2.0.0 - Doplnené chýbajúce funkcie pre remediation skripty
.NOTES
    - Logy sa ukladajú do: C:\TaurisIT\Log
    - Event Log používa názov: "IntuneScript"
    - Automatické čistenie starých logov (>30 dní)
    - Spätne kompatibilný s existujúcimi skriptami
#>

# Globálne premenné modulu
$script:LogDirectory = "C:\TaurisIT\Log"
$script:EventLogName = "IntuneScript"
$script:RetentionDays = 30

#region Core Logging Functions

function Write-CustomLog {
    <#
    .SYNOPSIS
        Základná funkcia pre logovanie do súboru a Event Logu
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource,
        
        [string]$EventLogName = "IntuneScript",
        
        [Parameter(Mandatory = $true)]
        [string]$LogFileName,
        
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"
    )
    
    # Použi globálny adresár, ak je nastavený
    $LogDirectory = if ($script:LogDirectory) { $script:LogDirectory } else { "C:\TaurisIT\Log" }
    
    # Vytvor adresár, ak neexistuje
    if (-not (Test-Path $LogDirectory)) {
        try {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Warning "Cannot create log directory: $_"
            return
        }
    }
    
    # Cesta k log súboru
    $LogFilePath = Join-Path $LogDirectory $LogFileName
    
    # Časová pečiatka
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Zápis do súboru
    try {
        "$Timestamp [$Type] $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Cannot write to log file: $_"
    }
    
    # Vytvorenie Event Source, ak neexistuje
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try {
            New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction Stop
        }
        catch {
            # Event Source sa nepodarilo vytvoriť, ale pokračujeme
            "$Timestamp [WARNING] Cannot create Event Source '$EventSource': $_" | 
            Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
    
    # Dynamické EventId podľa typu
    $EventId = switch ($Type) {
        "Information" { 1000 }
        "Warning" { 2000 }
        "Error" { 3000 }
        default { 9999 }
    }
    
    # Zápis do Event Logu
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message -ErrorAction Stop
    }
    catch {
        # Event Log zápis zlyhal, ale súborový log funguje
        "$Timestamp [WARNING] Cannot write to Event Log: $_" | 
        Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

function Write-IntuneLog {
    <#
    .SYNOPSIS
        Hlavná funkcia pre logovanie v Intune skriptoch (spätne kompatibilná)
    .DESCRIPTION
        Podporuje rôzne úrovne logovania (INFO, WARN, ERROR, SUCCESS, DEBUG)
        a automaticky mapuje na správne typy Event Logu
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO',
        
        [string]$LogFile = "IntuneScripts.log",
        
        [string]$EventSource = "IntuneScripts"
    )
    
    # Mapovanie úrovní na Event Log typy
    $Type = switch ($Level) {
        'INFO' { 'Information' }
        'WARN' { 'Warning' }
        'ERROR' { 'Error' }
        'SUCCESS' { 'Information' }
        'DEBUG' { 'Information' }
        default { 'Information' }
    }
    
    # Pridaj prefix úrovne do správy
    $FormattedMessage = "[$Level] $Message"
    
    Write-CustomLog -Message $FormattedMessage -EventSource $EventSource -LogFileName $LogFile -Type $Type
}

#endregion

#region Log Management Functions

function Initialize-LogSystem {
    <#
    .SYNOPSIS
        Inicializuje logový systém - vytvára adresáre a nastavuje konfiguráciu
    .DESCRIPTION
        Táto funkcia sa volá na začiatku každého remediation skriptu.
        Vytvára potrebné adresáre a overuje zápisové oprávnenia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource,
        
        [string]$EventLogName = "IntuneScript",
        
        [int]$RetentionDays = 30
    )
    
    try {
        # Nastav globálne premenné modulu
        $script:LogDirectory = $LogDirectory
        $script:EventLogName = $EventLogName
        $script:RetentionDays = $RetentionDays
        
        # Vytvor log adresár, ak neexistuje
        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created log directory: $LogDirectory"
        }
        
        # Otestuj zápisové oprávnenia
        $testFile = Join-Path $LogDirectory "init_test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
        try {
            "Test" | Out-File -FilePath $testFile -ErrorAction Stop
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            throw "No write permissions to log directory: $_"
        }
        
        # Vytvor Event Source, ak neexistuje
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            try {
                New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction Stop
                Write-Verbose "Created Event Source: $EventSource"
            }
            catch {
                Write-Warning "Could not create Event Source: $_"
                # Pokračujeme aj bez Event Logu
            }
        }
        
        # Log inicializačnej správy
        Write-IntuneLog -Message "Log system initialized - Directory: $LogDirectory, Source: $EventSource" `
            -Level INFO -EventSource $EventSource -LogFile "system.log"
        
        return $true
    }
    catch {
        Write-Error "Failed to initialize log system: $_"
        return $false
    }
}

function Clear-OldLogs {
    <#
    .SYNOPSIS
        Čistí staré log súbory na základe retention politiky
    .DESCRIPTION
        Odstráni všetky .log a .txt súbory staršie ako zadaný počet dní.
        Štandardne odstraňuje súbory staršie ako 30 dní.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$RetentionDays = 30,
        
        [string]$LogDirectory
    )
    
    try {
        # Použij globálny adresár, ak nie je špecifikovaný
        if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
            $LogDirectory = $script:LogDirectory
            if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
                $LogDirectory = "C:\TaurisIT\Log"
            }
        }
        
        if (-not (Test-Path $LogDirectory)) {
            Write-Verbose "Log directory does not exist: $LogDirectory"
            return
        }
        
        $CutoffDate = (Get-Date).AddDays(-$RetentionDays)
        
        # Nájdi staré súbory
        $oldFiles = Get-ChildItem -Path $LogDirectory -Include "*.log", "*.txt" -Recurse -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.LastWriteTime -lt $CutoffDate }
        
        if ($oldFiles) {
            $removedCount = 0
            $totalSize = 0
            
            foreach ($file in $oldFiles) {
                try {
                    $size = $file.Length
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $removedCount++
                    $totalSize += $size
                    Write-Verbose "Removed old log: $($file.Name) ($('{0:N2}' -f ($size/1KB)) KB)"
                }
                catch {
                    Write-Warning "Could not remove $($file.Name): $_"
                }
            }
            
            $message = "Cleaned $removedCount old log files ($('{0:N2}' -f ($totalSize/1MB)) MB) older than $RetentionDays days"
            Write-Verbose $message
            
            # Log čistiacu operáciu
            Write-IntuneLog -Message $message -Level INFO -EventSource "LogMaintenance" -LogFile "maintenance.log"
        }
        else {
            Write-Verbose "No old log files found to clean"
        }
    }
    catch {
        Write-Warning "Error during log cleanup: $_"
    }
}

#endregion

#region Alert Functions

function Send-IntuneAlert {
    <#
    .SYNOPSIS
        Posiela alerty pre kritické udalosti
    .DESCRIPTION
        Zapisuje vysokoprioritné správy do Event Logu s príslušným EventId
        a môže byť rozšírený o email notifikácie alebo iné alerting mechanizmy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Warning', 'Error', 'Critical')]
        [string]$Severity,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource,
        
        [string]$LogFile = "alerts.log"
    )
    
    try {
        # Mapuj severity na Event Log typ
        $EventType = switch ($Severity) {
            'Information' { 'Information'; $EventId = 5000 }
            'Warning' { 'Warning'; $EventId = 5001 }
            'Error' { 'Error'; $EventId = 5002 }
            'Critical' { 'Error'; $EventId = 5003 }
            default { 'Warning'; $EventId = 5999 }
        }
        
        # Formátovaná správa
        $AlertMessage = "[ALERT - $Severity] $Message"
        
        # Použij Write-IntuneLog pre konzistentné logovanie
        $Level = switch ($Severity) {
            'Information' { 'INFO' }
            'Warning' { 'WARN' }
            'Error' { 'ERROR' }
            'Critical' { 'ERROR' }
            default { 'WARN' }
        }
        
        Write-IntuneLog -Message $AlertMessage -Level $Level -EventSource $EventSource -LogFile $LogFile
        
        # Dodatočný zápis do Event Logu s príslušným EventId
        if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            Write-EventLog -LogName $script:EventLogName -Source $EventSource `
                -EntryType $EventType -EventId $EventId -Message $AlertMessage -ErrorAction SilentlyContinue
        }
        
        # Tu môžete pridať ďalšie alerting mechanizmy:
        # - Email notifikácie
        # - Teams/Slack webhooks
        # - SIEM integrácia
        # - atď.
        
        Write-Verbose "Alert sent: [$Severity] $Message"
    }
    catch {
        Write-Warning "Failed to send alert: $_"
    }
}

#endregion

#region Utility Functions

function Get-LogFiles {
    <#
    .SYNOPSIS
        Vráti zoznam všetkých log súborov v log adresári
    #>
    [CmdletBinding()]
    param(
        [string]$LogDirectory,
        [string]$Filter = "*.log"
    )
    
    if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
        $LogDirectory = $script:LogDirectory
        if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
            $LogDirectory = "C:\TaurisIT\Log"
        }
    }
    
    if (Test-Path $LogDirectory) {
        Get-ChildItem -Path $LogDirectory -Filter $Filter -Recurse -File | 
        Select-Object Name, Length, LastWriteTime, FullName
    }
}

function Get-LogStatistics {
    <#
    .SYNOPSIS
        Vráti statistiky o log súboroch
    #>
    [CmdletBinding()]
    param([string]$LogDirectory)
    
    if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
        $LogDirectory = $script:LogDirectory
        if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
            $LogDirectory = "C:\TaurisIT\Log"
        }
    }
    
    if (-not (Test-Path $LogDirectory)) {
        return $null
    }
    
    $files = Get-ChildItem -Path $LogDirectory -Include "*.log", "*.txt" -Recurse -File
    
    [PSCustomObject]@{
        TotalFiles   = $files.Count
        TotalSizeMB  = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        OldestLog    = ($files | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
        NewestLog    = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        LogDirectory = $LogDirectory
    }
}

#endregion

# Export všetkých funkcií
Export-ModuleMember -Function @(
    'Write-CustomLog',
    'Write-IntuneLog',
    'Initialize-LogSystem',
    'Clear-OldLogs',
    'Send-IntuneAlert',
    'Get-LogFiles',
    'Get-LogStatistics'
)