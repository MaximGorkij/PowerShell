<#
.SYNOPSIS
    Instalacia alebo aktualizacia PowerShell modulu LogHelper.
.DESCRIPTION
    Skript skontroluje existenciu modulu LogHelper, porovna verziu, a ak je starsia alebo chyba, nahradi ju novou verziou.
    Zapisuje priebeh do .txt logu a Event Logu.
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-05
.VERSION
    1.1.0
.NOTES
    Modul sa instaluje do C:\Program Files\WindowsPowerShell\Modules\LogHelper
    Logy sa ukladaju do C:\ProgramData\LogHelper\install_update_log.txt
    Pridane error handling a validacie pre Intune kompatibilitu
#>

# =============================================================================
# PREMENNE A KONFIGURACIA
# =============================================================================
$ModuleName = "LogHelper"
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogDir = "$env:ProgramData\LogHelper"
$LogFile = "$LogDir\install_update_log.txt"
$NewVersion = "1.6.0"  # Aktualizovane na verziu z detekcie
$VersionFile = "$ModulePath\version.txt"
$ModuleFile = "$ModulePath\LogHelper.psm1"
$SourceModuleFile = ".\LogHelper.psm1"

# Event Log nastavenia
$EventLogName = "IntuneScript"
$EventSource = "LogHelper Install"

# =============================================================================
# FUNKCIE
# =============================================================================

# Funkcia na vytvorenie Event Log zdroja
function Initialize-EventLog {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            # Kontrola administratorskych prav
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                New-EventLog -LogName $EventLogName -Source $EventSource
                return $true
            }
            else {
                Write-Warning "Nedostatocne prava na vytvorenie Event Log zdroja."
                return $false
            }
        }
        return $true
    }
    catch {
        Write-Warning "Chyba pri inicializacii Event Logu: $($_.Exception.Message)"
        return $false
    }
}

# Vylepšena funkcia na logovania
function Write-InstallLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information",
        
        [Parameter(Mandatory = $false)]
        [int]$EventId = 3000
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$Type] $Message"
    
    # Zapis do konzoly
    switch ($Type) {
        "Error" { Write-Error $LogEntry }
        "Warning" { Write-Warning $LogEntry }
        default { Write-Host $LogEntry }
    }
    
    # Zapis do suboru
    try {
        Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
    }
    catch {
        Write-Warning "Nepodarilo sa zapisat do log suboru: $($_.Exception.Message)"
    }
    
    # Zapis do Event Logu
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            Write-EventLog -LogName $EventLogName -Source $EventSource -EventId $EventId -EntryType $Type -Message $Message
        }
    }
    catch {
        # Ticho zlyhanie - Event Log nie je kriticka funkcionalita
    }
}

# Funkcia na validaciu zdrojovych suborov
function Test-SourceFiles {
    $missingFiles = @()
    
    if (-not (Test-Path $SourceModuleFile -PathType Leaf)) {
        $missingFiles += $SourceModuleFile
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-InstallLog -Message "KRITICKA CHYBA: Chybaju zdrojove subory: $($missingFiles -join ', ')" -Type "Error"
        return $false
    }
    
    # Validacia obsahu PSM1 suboru
    try {
        $moduleContent = Get-Content $SourceModuleFile -ErrorAction Stop
        if (-not $moduleContent -or $moduleContent.Count -eq 0) {
            Write-InstallLog -Message "KRITICKA CHYBA: Zdrojovy modul je prazdny" -Type "Error"
            return $false
        }
        
        # Zakladna kontrola ci je to PowerShell modul
        $hasFunction = $moduleContent | Where-Object { $_ -match "^function\s+\w+" }
        if (-not $hasFunction) {
            Write-InstallLog -Message "VAROVANIE: Zdrojovy subor neobsahuje ziadne funkcie" -Type "Warning"
        }
        
    }
    catch {
        Write-InstallLog -Message "CHYBA pri validacii zdrojoveho modulu: $($_.Exception.Message)" -Type "Error"
        return $false
    }
    
    return $true
}

# Funkcia na bezpecne odstranenie adresara
function Remove-ModuleSafely {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return $true
    }
    
    try {
        # Najprv skusime standardne odstranenie
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-InstallLog -Message "Stary modul uspesne odstraneny."
        return $true
    }
    catch {
        Write-InstallLog -Message "VAROVANIE: Standardne odstranenie zlyhalo: $($_.Exception.Message)" -Type "Warning"
        
        # Pokus o manualne odstranenie suborov
        try {
            Get-ChildItem -Path $Path -Recurse -Force | Remove-Item -Force -Recurse
            Remove-Item -Path $Path -Force
            Write-InstallLog -Message "Stary modul odstraneny po manualom postupe."
            return $true
        }
        catch {
            Write-InstallLog -Message "CHYBA: Nepodarilo sa odstranit stary modul: $($_.Exception.Message)" -Type "Error"
            return $false
        }
    }
}

# =============================================================================
# HLAVNA LOGIKA
# =============================================================================

Write-Host "=== Instalacia/aktualizacia modulu LogHelper v$NewVersion ===" -ForegroundColor Green

# Inicializacia prostredia
try {
    # Vytvorenie log adresara
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Write-Host "Vytvoreny log adresar: $LogDir"
    }
    
    # Inicializacia Event Logu
    Initialize-EventLog | Out-Null
    
}
catch {
    Write-Error "Kriticka chyba pri inicializacii: $($_.Exception.Message)"
    exit 1
}

# Zaciatok logovania
Write-InstallLog -Message "=== ZACIATOK INSTALACIE/AKTUALIZACIE MODULU LogHelper v$NewVersion ==="

# Validacia zdrojovych suborov
if (-not (Test-SourceFiles)) {
    Write-InstallLog -Message "Instalacia prerušena kvoli chybajucim alebo chybnym zdrojovym suborom." -Type "Error"
    exit 1
}

Write-InstallLog -Message "Zdrojove subory uspesne validovane."

# Kontrola aktualnej verzie
$needsUpdate = $true
$currentVersion = $null

if (Test-Path $VersionFile) {
    try {
        $versionContent = Get-Content $VersionFile -ErrorAction Stop
        if ($versionContent -and $versionContent.Count -gt 0) {
            $currentVersion = $versionContent[0].Trim()
            
            if ([string]::IsNullOrWhiteSpace($currentVersion)) {
                Write-InstallLog -Message "Version.txt je prazdny, bude prepisany." -Type "Warning"
            }
            elseif ($currentVersion -eq $NewVersion) {
                Write-InstallLog -Message "Modul je uz vo verzii $NewVersion."
                
                # Dodatocna kontrola ci existuje aj samotny modul
                if (Test-Path $ModuleFile) {
                    Write-InstallLog -Message "Modul existuje a je aktualny. Aktualizacia nie je potrebna."
                    $needsUpdate = $false
                }
                else {
                    Write-InstallLog -Message "Version.txt je aktualny ale chyba modul. Reinstaluje sa." -Type "Warning"
                }
            }
            else {
                Write-InstallLog -Message "Zistena verzia: $currentVersion, pozadovana: $NewVersion. Aktualizuje sa."
            }
        }
        else {
            Write-InstallLog -Message "Version.txt je prazdny." -Type "Warning"
        }
    }
    catch {
        Write-InstallLog -Message "Chyba pri citani verzie: $($_.Exception.Message). Pokracuje sa s instaliciou." -Type "Warning"
    }
}
else {
    Write-InstallLog -Message "Modul neexistuje alebo chyba version.txt. Instaluje sa nova verzia $NewVersion."
}

# Instalacia/aktualizacia ak je potrebna
if ($needsUpdate) {
    Write-InstallLog -Message "Zacinam instalciu/aktualizaciu modulu..."
    
    # Odstranenie stareho modulu
    if (Test-Path $ModulePath) {
        Write-InstallLog -Message "Odstranujem stary modul z $ModulePath..."
        if (-not (Remove-ModuleSafely -Path $ModulePath)) {
            Write-InstallLog -Message "KRITICKA CHYBA: Nepodarilo sa odstranit stary modul." -Type "Error"
            exit 1
        }
    }
    
    # Vytvorenie adresara pre novy modul
    try {
        New-Item -ItemType Directory -Path $ModulePath -Force | Out-Null
        Write-InstallLog -Message "Vytvoreny adresar pre modul: $ModulePath"
    }
    catch {
        Write-InstallLog -Message "KRITICKA CHYBA pri vytvarani adresara modulu: $($_.Exception.Message)" -Type "Error"
        exit 1
    }
    
    # Kopirovanie noveho modulu
    try {
        Copy-Item -Path $SourceModuleFile -Destination $ModuleFile -Force -ErrorAction Stop
        Write-InstallLog -Message "Modul uspesne skopirovany."
        
        # Verifikacia kopirovania
        if (-not (Test-Path $ModuleFile)) {
            throw "Subor sa neskopiroval"
        }
        
        # Porovnanie velkosti suborov
        $sourceSize = (Get-Item $SourceModuleFile).Length
        $targetSize = (Get-Item $ModuleFile).Length
        
        if ($sourceSize -ne $targetSize) {
            throw "Velkost suborov sa nezhoduje (zdroj: $sourceSize, ciel: $targetSize)"
        }
        
        Write-InstallLog -Message "Kopirovanie modulu uspesne overene."
        
    }
    catch {
        Write-InstallLog -Message "KRITICKA CHYBA pri kopirovani modulu: $($_.Exception.Message)" -Type "Error"
        exit 1
    }
    
    # Zapisanie verzie
    try {
        Set-Content -Path $VersionFile -Value $NewVersion -Encoding UTF8 -ErrorAction Stop
        Write-InstallLog -Message "Verzia $NewVersion zapisana do $VersionFile"
        
        # Verifikacia zapisu verzie
        $writtenVersion = (Get-Content $VersionFile -ErrorAction Stop)[0].Trim()
        if ($writtenVersion -ne $NewVersion) {
            throw "Zapisana verzia sa nezhoduje: '$writtenVersion' != '$NewVersion'"
        }
        
    }
    catch {
        Write-InstallLog -Message "KRITICKA CHYBA pri zapisovani verzie: $($_.Exception.Message)" -Type "Error"
        exit 1
    }
    
    Write-InstallLog -Message "Modul LogHelper v$NewVersion uspesne nainstalovany/aktualizovany."
    
}
else {
    Write-InstallLog -Message "Aktualizacia nebola potrebna."
}

# Finalna verifikacia
try {
    if ((Test-Path $ModuleFile) -and (Test-Path $VersionFile)) {
        $finalVersion = (Get-Content $VersionFile)[0].Trim()
        Write-InstallLog -Message "USPECH: Finalna verifikacia prebehla uspesne. Nainstalovana verzia: $finalVersion"
    }
    else {
        Write-InstallLog -Message "VAROVANIE: Finalna verifikacia zistila chybajuce subory." -Type "Warning"
        exit 1
    }
}
catch {
    Write-InstallLog -Message "CHYBA pri finalnej verifikacii: $($_.Exception.Message)" -Type "Error"
    exit 1
}

Write-InstallLog -Message "=== OPERACIA USPESNE DOKONCENA ==="
Write-Host "=== LogHelper modul uspesne nainstalovany/aktualizovany ===" -ForegroundColor Green

exit 0