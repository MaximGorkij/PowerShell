<#
.SYNOPSIS
    Odinstaluje PowerShell modul LogHelper z klientskeho PC.
.DESCRIPTION
    Skript odstrani cely priecinok modulu LogHelper a loguje priebeh do .txt suboru aj Event Logu.
    Obsahuje robustny error handling a verifikaciu odinstalacie.
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-05
.VERSION
    1.1.0
.NOTES
    Logy sa ukladaju do C:\ProgramData\LogHelper\uninstall_log.txt
    Modul sa odstranuje z C:\Program Files\WindowsPowerShell\Modules\LogHelper
    Pridane error handling a verifikacie pre Intune kompatibilitu
#>

# =============================================================================
# PREMENNE A KONFIGURACIA
# =============================================================================
$ModuleName = "LogHelper"
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogDir = "$env:ProgramData\LogHelper"
$LogFile = "$LogDir\uninstall_log.txt"

# Event Log nastavenia
$EventLogName = "IntuneScript"
$EventSource = "LogHelper Uninstall"

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
function Write-UninstallLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information",
        
        [Parameter(Mandatory = $false)]
        [int]$EventId = 4000
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

# Funkcia na kontrolu ci je modul prave pouzivany
function Test-ModuleInUse {
    try {
        # Kontrola ci je modul nacitany v aktualnej session
        $loadedModule = Get-Module -Name $ModuleName -ErrorAction SilentlyContinue
        if ($loadedModule) {
            Write-UninstallLog -Message "Modul je nacitany v aktualnej session. Pokusam sa ho uvolnit." -Type "Warning"
            try {
                Remove-Module -Name $ModuleName -Force -ErrorAction Stop
                Write-UninstallLog -Message "Modul uspesne uvolneny z pamate."
                return $false
            }
            catch {
                Write-UninstallLog -Message "VAROVANIE: Nepodarilo sa uvolnit modul z pamate: $($_.Exception.Message)" -Type "Warning"
                return $true
            }
        }
        
        # Kontrola ci niekto ma otvorene subory v priecinku
        $openFiles = @()
        try {
            $processes = Get-Process | Where-Object { $_.Path -like "$ModulePath*" }
            if ($processes) {
                $openFiles = $processes | ForEach-Object { $_.ProcessName }
                Write-UninstallLog -Message "VAROVANIE: Nasledovne procesy mozno pouzivaju subory modulu: $($openFiles -join ', ')" -Type "Warning"
                return $true
            }
        }
        catch {
            # Ignorovat chybu - nie je kriticka
        }
        
        return $false
    }
    catch {
        Write-UninstallLog -Message "Chyba pri kontrole pouzitia modulu: $($_.Exception.Message)" -Type "Warning"
        return $false
    }
}

# Funkcia na bezpecne odstranenie modulu
function Remove-ModuleSafely {
    param([string]$Path)
    
    # Prva kontrola existencie
    if (-not (Test-Path $Path)) {
        Write-UninstallLog -Message "Modul na ceste '$Path' neexistuje."
        return $true
    }
    
    Write-UninstallLog -Message "Zacinam odstranovat modul z '$Path'..."
    
    # Ziskanie informacii o priecinku pred odstranenim
    try {
        $folderInfo = Get-ChildItem -Path $Path -Recurse -Force | Measure-Object
        Write-UninstallLog -Message "Priecinok obsahuje $($folderInfo.Count) suborov/priecinkov."
    }
    catch {
        Write-UninstallLog -Message "Nepodarilo sa ziskat informacie o priecinku." -Type "Warning"
    }
    
    # Pokus o standardne odstranenie
    try {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-UninstallLog -Message "Modul uspesne odstraneny standardnym postupom."
        return $true
    }
    catch {
        Write-UninstallLog -Message "Standardne odstranenie zlyhalo: $($_.Exception.Message)" -Type "Warning"
    }
    
    # Pokus o postupne odstranenie suborov
    try {
        Write-UninstallLog -Message "Pokusam sa o postupne odstranenie suborov..."
        
        # Najprv odstranit vsetky subory
        Get-ChildItem -Path $Path -Recurse -Force -File | ForEach-Object {
            try {
                Remove-Item $_.FullName -Force
            }
            catch {
                Write-UninstallLog -Message "Nepodarilo sa odstranit subor: $($_.FullName)" -Type "Warning"
            }
        }
        
        # Potom odstranit priecinky
        Get-ChildItem -Path $Path -Recurse -Force -Directory | Sort-Object FullName -Descending | ForEach-Object {
            try {
                Remove-Item $_.FullName -Force
            }
            catch {
                Write-UninstallLog -Message "Nepodarilo sa odstranit priecinok: $($_.FullName)" -Type "Warning"
            }
        }
        
        # Nakoniec odstranit hlavny priecinok
        Remove-Item -Path $Path -Force
        Write-UninstallLog -Message "Modul uspesne odstraneny postupnym vymazanim."
        return $true
        
    }
    catch {
        Write-UninstallLog -Message "CHYBA: Postupne odstranenie zlyhalo: $($_.Exception.Message)" -Type "Error"
        return $false
    }
}

# Funkcia na vyčistenie zvyskov
function Clear-ModuleReferences {
    try {
        # Odstranenie z PowerShell module cache ak existuje
        $moduleCache = "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ModuleAnalysisCache"
        if (Test-Path $moduleCache) {
            try {
                Remove-Item $moduleCache -Force -ErrorAction SilentlyContinue
                Write-UninstallLog -Message "PowerShell module cache vyčistena."
            }
            catch {
                Write-UninstallLog -Message "Nepodarilo sa vyčistit module cache." -Type "Warning"
            }
        }
        
        # Kontrola ci sa modul este stale nachadza v Get-Module -ListAvailable
        $availableModule = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
        if ($availableModule) {
            Write-UninstallLog -Message "VAROVANIE: Modul je stale viditelny v Get-Module -ListAvailable" -Type "Warning"
            return $false
        }
        
        return $true
    }
    catch {
        Write-UninstallLog -Message "Chyba pri čisteni referencii: $($_.Exception.Message)" -Type "Warning"
        return $true  # Nie je kriticka chyba
    }
}

# =============================================================================
# HLAVNA LOGIKA
# =============================================================================

Write-Host "=== Odinstalacia modulu LogHelper ===" -ForegroundColor Yellow

# Inicializacia prostredia
try {
    # Vytvorenie log adresara ak neexistuje
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
Write-UninstallLog -Message "=== ZACIATOK ODINSTALACIE MODULU LogHelper ==="

# Kontrola existencie modulu
if (-not (Test-Path $ModulePath)) {
    Write-UninstallLog -Message "Modul LogHelper na ceste '$ModulePath' neexistuje."
    Write-UninstallLog -Message "Nie je co odinstalovat - operacia dokoncena."
    Write-Host "=== Modul neexistoval - odinstalacia dokoncena ===" -ForegroundColor Green
    exit 0
}

# Ziskanie informacii o module pred odstranenim
try {
    $moduleSize = (Get-ChildItem -Path $ModulePath -Recurse -Force | Measure-Object -Property Length -Sum).Sum
    $fileSizeMB = [Math]::Round($moduleSize / 1MB, 2)
    Write-UninstallLog -Message "Zisteny modul LogHelper (velkost: $fileSizeMB MB)."
    
    # Kontrola verzie ak existuje
    $versionFile = "$ModulePath\version.txt"
    if (Test-Path $versionFile) {
        try {
            $version = (Get-Content $versionFile -ErrorAction Stop)[0].Trim()
            Write-UninstallLog -Message "Odinstaalovava sa verzia: $version"
        }
        catch {
            Write-UninstallLog -Message "Nepodarilo sa zistit verziu modulu." -Type "Warning"
        }
    }
}
catch {
    Write-UninstallLog -Message "Nepodarilo sa ziskat informacie o module." -Type "Warning"
}

# Kontrola ci je modul pouzivany
$moduleInUse = Test-ModuleInUse
if ($moduleInUse) {
    Write-UninstallLog -Message "Modul je mozno pouzivany, ale pokracujem v odinstalacii." -Type "Warning"
}

# Odstranenie modulu
Write-UninstallLog -Message "Spustam odinstalaci modulu..."

$removalSuccess = Remove-ModuleSafely -Path $ModulePath

if ($removalSuccess) {
    # Verifikacia odstranenia
    if (Test-Path $ModulePath) {
        Write-UninstallLog -Message "CHYBA: Modul stale existuje po pokuse o odstranenie!" -Type "Error"
        exit 1
    }
    else {
        Write-UninstallLog -Message "Modul LogHelper bol uspesne odstraneny."
        
        # Vyčistenie referencii
        Clear-ModuleReferences | Out-Null
        
        Write-UninstallLog -Message "USPECH: Odinstalacia modulu LogHelper dokoncena."
    }
}
else {
    Write-UninstallLog -Message "KRITICKA CHYBA: Nepodarilo sa odstranit modul LogHelper!" -Type "Error"
    exit 1
}

# Volitelne - odstranenie log adresara ak je prazdny
try {
    $logDirItems = Get-ChildItem -Path $LogDir -ErrorAction SilentlyContinue
    if (-not $logDirItems -or $logDirItems.Count -eq 1) {
        # Len uninstall_log.txt
        # Write-UninstallLog -Message "Odstranujem prazdny log adresar..."
        # Remove-Item -Path $LogDir -Recurse -Force
        # Write-Host "Log adresar odstraneny."
        Write-UninstallLog -Message "Log adresar ponechany pre uchovanie uninstall logu."
    }
}
catch {
    Write-UninstallLog -Message "Nepodarilo sa spracovat log adresar." -Type "Warning"
}

Write-UninstallLog -Message "=== ODINSTALACIA USPESNE DOKONCENA ==="
Write-Host "=== LogHelper modul uspesne odinstalovany ===" -ForegroundColor Green

exit 0