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
    2.1.0 - Opravená chyba SourceExists pri nedostatočných právach (Security, State log)
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

    # Vytvor podadresár log súboru ak neexistuje
    $LogFileDir = Split-Path $LogFilePath -Parent
    if (-not (Test-Path $LogFileDir)) {
        try {
            New-Item -Path $LogFileDir -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Warning "Cannot create log subdirectory: $_"
            return
        }
    }

    # Časová pečiatka
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Zápis do súboru
    try {
        "$Timestamp [$Type] $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Cannot write to log file: $_"
    }

    # FIX: SourceExists obalený try/catch – chyba pri nedostupných logoch (Security, State)
    $SourceExists = $false
    try { $SourceExists = [System.Diagnostics.EventLog]::SourceExists($EventSource) } catch {}

    if (-not $SourceExists) {
        try {
            New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction Stop
        }
        catch {
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
        $TestFile = Join-Path $LogDirectory "init_test_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
        try {
            "Test" | Out-File -FilePath $TestFile -ErrorAction Stop
            Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            throw "No write permissions to log directory: $_"
        }

        # FIX: SourceExists obalený try/catch – chyba pri nedostupných logoch (Security, State)
        $SourceExists = $false
        try { $SourceExists = [System.Diagnostics.EventLog]::SourceExists($EventSource) } catch {}

        if (-not $SourceExists) {
            try {
                New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction Stop
                Write-Verbose "Created Event Source: $EventSource"
            }
            catch {
                Write-Warning "Could not create Event Source: $_"
                # Pokračujeme aj bez Event Logu
            }
        }

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
    #>
    [CmdletBinding()]
    param(
        [int]$RetentionDays = 30,
        [string]$LogDirectory
    )

    try {
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

        $OldFiles = Get-ChildItem -Path $LogDirectory -Include "*.log", "*.txt" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $CutoffDate }

        if ($OldFiles) {
            $RemovedCount = 0
            $TotalSize = 0

            foreach ($File in $OldFiles) {
                try {
                    $Size = $File.Length
                    Remove-Item -Path $File.FullName -Force -ErrorAction Stop
                    $RemovedCount++
                    $TotalSize += $Size
                    Write-Verbose "Removed old log: $($File.Name) ($('{0:N2}' -f ($Size/1KB)) KB)"
                }
                catch {
                    Write-Warning "Could not remove $($File.Name): $_"
                }
            }

            $CleanMsg = "Cleaned $RemovedCount old log files ($('{0:N2}' -f ($TotalSize/1MB)) MB) older than $RetentionDays days"
            Write-Verbose $CleanMsg
            Write-IntuneLog -Message $CleanMsg -Level INFO -EventSource "LogMaintenance" -LogFile "maintenance.log"
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
        $EventType = switch ($Severity) {
            'Information' { $EventId = 5000; 'Information' }
            'Warning' { $EventId = 5001; 'Warning' }
            'Error' { $EventId = 5002; 'Error' }
            'Critical' { $EventId = 5003; 'Error' }
            default { $EventId = 5999; 'Warning' }
        }

        $AlertMessage = "[ALERT - $Severity] $Message"

        $Level = switch ($Severity) {
            'Information' { 'INFO' }
            'Warning' { 'WARN' }
            'Error' { 'ERROR' }
            'Critical' { 'ERROR' }
            default { 'WARN' }
        }

        Write-IntuneLog -Message $AlertMessage -Level $Level -EventSource $EventSource -LogFile $LogFile

        # FIX: SourceExists obalený try/catch
        $SourceExists = $false
        try { $SourceExists = [System.Diagnostics.EventLog]::SourceExists($EventSource) } catch {}

        if ($SourceExists) {
            Write-EventLog -LogName $script:EventLogName -Source $EventSource `
                -EntryType $EventType -EventId $EventId -Message $AlertMessage -ErrorAction SilentlyContinue
        }

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
        Vráti štatistiky o log súboroch
    #>
    [CmdletBinding()]
    param([string]$LogDirectory)

    if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
        $LogDirectory = $script:LogDirectory
        if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
            $LogDirectory = "C:\TaurisIT\Log"
        }
    }

    if (-not (Test-Path $LogDirectory)) { return $null }

    $Files = Get-ChildItem -Path $LogDirectory -Include "*.log", "*.txt" -Recurse -File

    [PSCustomObject]@{
        TotalFiles   = $Files.Count
        TotalSizeMB  = [math]::Round(($Files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        OldestLog    = ($Files | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
        NewestLog    = ($Files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
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