# =============================================================================
# MOP Password Manager - Instalacny skript
# =============================================================================

# Premenne
$FolderPath = "C:\TaurisIT\skript"
$LogFolderPath = "C:\TaurisIT\log"
$ScriptName = "SetPassMOP-v5.ps1"
$ScriptPath = "$FolderPath\$ScriptName"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Install"
$TaskName = "SetPasswordDaily"
$LogFileName = "$LogFolderPath\InstallLog.txt"
$MaxLogSize = 10MB  # Maximalna velkost log suboru

# =============================================================================
# Funkcia pre logovanie (fallback ak LogHelper modul nie je dostupny)
# =============================================================================
function Write-FallbackLog {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [int]$EventId = 2000,
        [string]$EventSource = $script:EventSource,
        [string]$EventLogName = $script:EventLogName,
        [string]$LogFileName = $script:LogFileName
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Type] $Message"
    
    # Pokus o zapis do Event Logu
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            Write-EventLog -LogName $EventLogName -Source $EventSource -EventId $EventId -EntryType $Type -Message $Message
        }
    }
    catch {
        Write-Warning "Event Log zapis zlyhal: $($_.Exception.Message)"
    }
    
    # Pokus o zapis do suboru
    try {
        # Kontrola velkosti log suboru a rotacia ak je potrebna
        if (Test-Path $LogFileName) {
            $logFile = Get-Item $LogFileName
            if ($logFile.Length -gt $MaxLogSize) {
                $backupLogFile = $LogFileName -replace '\.txt$', "_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                Move-Item $LogFileName $backupLogFile
                Write-Warning "Log subor bol prilis velky a bol premenovany na: $backupLogFile"
            }
        }
        
        Add-Content -Path $LogFileName -Value $logEntry -Encoding UTF8
    }
    catch {
        Write-Warning "File log zapis zlyhal: $($_.Exception.Message)"
    }
    
    # Vypis na konzolu
    switch ($Type) {
        "Error" { Write-Error $logEntry }
        "Warning" { Write-Warning $logEntry }
        default { Write-Host $logEntry }
    }
}

# =============================================================================
# Inicializacia a priprava prostredia
# =============================================================================

Write-Host "=== Spustanie MOP Password Manager instalacie ===" -ForegroundColor Green

# Import LogHelper modulu s fallback
$LogHelperAvailable = $false
try {
    Import-Module LogHelper -ErrorAction Stop
    $LogHelperAvailable = $true
    Write-Host "LogHelper modul uspesne importovany" -ForegroundColor Green
}
catch {
    Write-Host "LogHelper modul nie je dostupny, pouziva sa fallback logovanie" -ForegroundColor Yellow
}

# Funkcia pre logovanie - pouzie LogHelper ak je dostupny, inak fallback
function Write-InstallLog {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [int]$EventId = 2000
    )
    
    if ($LogHelperAvailable) {
        Write-CustomLog -Message $Message -Type $Type -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
    }
    else {
        Write-FallbackLog -Message $Message -Type $Type -EventId $EventId
    }
}

# =============================================================================
# Vytvorenie adresarovej struktury
# =============================================================================

Write-InstallLog -Message "Zacina instalacia MOP Password Manager..."

# Vytvorenie hlavneho adresara
if (-not (Test-Path $FolderPath)) {
    try {
        New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
        Write-InstallLog -Message "Adresar '$FolderPath' bol uspesne vytvoreny."
    }
    catch {
        Write-InstallLog -Message "KRITICKA CHYBA pri vytvarani adresara '$FolderPath': $($_.Exception.Message)" -Type "Error"
        exit 1
    }
}
else {
    Write-InstallLog -Message "Adresar '$FolderPath' uz existuje."
}

# Vytvorenie log adresara
if (-not (Test-Path $LogFolderPath)) {
    try {
        New-Item -Path $LogFolderPath -ItemType Directory -Force | Out-Null
        Write-InstallLog -Message "Log adresar '$LogFolderPath' bol uspesne vytvoreny."
    }
    catch {
        Write-InstallLog -Message "CHYBA pri vytvarani log adresara '$LogFolderPath': $($_.Exception.Message)" -Type "Error"
    }
}

# =============================================================================
# Vytvorenie Event Logu
# =============================================================================

if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    try {
        # Potrebujeme administratorske prava na vytvorenie noveho Event Log zdroja
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            New-EventLog -LogName $EventLogName -Source $EventSource
            Write-InstallLog -Message "Event Log '$EventLogName' a zdroj '$EventSource' boli uspesne vytvorene."
        }
        else {
            Write-InstallLog -Message "VAROVANIE: Nedostatocne prava na vytvorenie Event Log zdroja. Pokracuje sa bez Event Logu." -Type "Warning"
        }
    }
    catch {
        Write-InstallLog -Message "CHYBA pri vytvarani Event Logu: $($_.Exception.Message)" -Type "Error"
    }
}
else {
    Write-InstallLog -Message "Event Log zdroj '$EventSource' uz existuje."
}

# =============================================================================
# Validacia a kopirovanie skriptu
# =============================================================================

# Kontrola existencie zdrojoveho skriptu
$SourceScriptPath = ".\$ScriptName"
if (-not (Test-Path $SourceScriptPath)) {
    Write-InstallLog -Message "KRITICKA CHYBA: Zdrojovy skript '$SourceScriptPath' nebol najdeny!" -Type "Error"
    exit 1
}

# Ziskanie informacii o zdrojovom subore
try {
    $SourceFile = Get-Item $SourceScriptPath
    $SourceHash = Get-FileHash $SourceScriptPath -Algorithm SHA256
    Write-InstallLog -Message "Zdrojovy skript: Velkost: $($SourceFile.Length) bytes, Hash: $($SourceHash.Hash.Substring(0,16))..."
}
catch {
    Write-InstallLog -Message "CHYBA pri ziskavani informacii o zdrojovom subore: $($_.Exception.Message)" -Type "Error"
}

# Kopirovanie skriptu
try {
    # Kontrola ci cielovy subor uz existuje a porovnanie
    if (Test-Path $ScriptPath) {
        try {
            $ExistingHash = Get-FileHash $ScriptPath -Algorithm SHA256
            if ($SourceHash.Hash -eq $ExistingHash.Hash) {
                Write-InstallLog -Message "Skript '$ScriptName' je uz aktualny (identicky hash). Preskakuje sa kopirovanie."
            }
            else {
                # Vytvorenie zalohy existujuceho suboru
                $BackupPath = $ScriptPath -replace '\.ps1$', "_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
                Copy-Item -Path $ScriptPath -Destination $BackupPath
                Write-InstallLog -Message "Existujuci skript zalohovany ako: $BackupPath"
                
                Copy-Item -Path $SourceScriptPath -Destination $ScriptPath -Force
                Write-InstallLog -Message "Skript '$ScriptName' bol aktualizovany v '$FolderPath'."
            }
        }
        catch {
            Write-InstallLog -Message "CHYBA pri porovnavani suborov, vykona sa nutene kopirovanie: $($_.Exception.Message)" -Type "Warning"
            Copy-Item -Path $SourceScriptPath -Destination $ScriptPath -Force
            Write-InstallLog -Message "Skript '$ScriptName' bol nutene skopirovany do '$FolderPath'."
        }
    }
    else {
        Copy-Item -Path $SourceScriptPath -Destination $ScriptPath -Force
        Write-InstallLog -Message "Skript '$ScriptName' bol uspesne skopirovany do '$FolderPath'."
    }
    
    # Verifikacia kopirovania
    if (-not (Test-Path $ScriptPath)) {
        throw "Skript nebol uspesne skopirovany"
    }
    
    $CopiedHash = Get-FileHash $ScriptPath -Algorithm SHA256
    if ($SourceHash.Hash -ne $CopiedHash.Hash) {
        throw "Hash kopie sa nezhoduje so zdrojovym suborom"
    }
    
    Write-InstallLog -Message "Kopirovanie skriptu uspesne overene."
    
}
catch {
    Write-InstallLog -Message "KRITICKA CHYBA pri kopirovani skriptu: $($_.Exception.Message)" -Type "Error"
    exit 1
}

# =============================================================================
# Sprava naplanovanych uloh
# =============================================================================

try {
    # Kontrola existencie ulohy
    $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if ($ExistingTask) {
        Write-InstallLog -Message "Uloha '$TaskName' uz existuje. Bude aktualizovana."
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-InstallLog -Message "Existujuca uloha '$TaskName' bola odstranena."
    }
    
    # Vytvorenie novej ulohy
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    
    # Nastavenie spustania kazdy den o 22:30
    $Trigger = New-ScheduledTaskTrigger -Daily -At "22:30"
    
    # Spustenie pod SYSTEM uctom s najvyssimi pravami
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Nastavenia ulohy
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false
    
    # Registracia ulohy
    $Task = Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force
    
    Write-InstallLog -Message "Uloha '$TaskName' bola uspesne vytvorena/aktualizovana."
    
    # Verifikacia ulohy
    $VerifyTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($VerifyTask) {
        Write-InstallLog -Message "Verifikacia: Uloha '$TaskName' je spravne zaregistrovana. Stav: $($VerifyTask.State)"
        
        # Zobrazenie detailov ulohy
        $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($TaskInfo) {
            Write-InstallLog -Message "Detaily ulohy - Posledne spustenie: $($TaskInfo.LastRunTime), Posledny vysledok: $($TaskInfo.LastTaskResult)"
        }
    }
    else {
        throw "Uloha nebola spravne zaregistrovana"
    }
    
}
catch {
    Write-InstallLog -Message "KRITICKA CHYBA pri vytvarani ulohy '$TaskName': $($_.Exception.Message)" -Type "Error"
    exit 1
}

# =============================================================================
# Finalizacia instalacie
# =============================================================================

# Nastavenie spravnych opravneni na subory
try {
    $Acl = Get-Acl $ScriptPath
    # Pridanie full control pre SYSTEM
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
    $Acl.SetAccessRule($AccessRule)
    Set-Acl -Path $ScriptPath -AclObject $Acl
    Write-InstallLog -Message "Opravnenia na subor '$ScriptPath' boli nastavene."
}
catch {
    Write-InstallLog -Message "VAROVANIE: Nepodarilo sa nastavit opravnenia na subor: $($_.Exception.Message)" -Type "Warning"
}

# Zaverecne informacie
Write-InstallLog -Message "=== INSTALACIA USPESNE DOKONCENA ==="
Write-InstallLog -Message "Skript umiestneny: $ScriptPath"
Write-InstallLog -Message "Scheduled Task: $TaskName (spusta sa denne o 22:30)"
Write-InstallLog -Message "Log subory: $LogFolderPath"

Write-Host "=== MOP Password Manager bol uspesne nainstalovany ===" -ForegroundColor Green

# Volitelne - test spustenia skriptu (odkomentujte ak chcete otestovat)
# try {
#     Write-InstallLog -Message "Spusta sa test ulohy..."
#     Start-ScheduledTask -TaskName $TaskName
#     Start-Sleep -Seconds 5
#     $TaskResult = Get-ScheduledTaskInfo -TaskName $TaskName
#     Write-InstallLog -Message "Test ulohy dokonceny. Vysledok: $($TaskResult.LastTaskResult)"
# } catch {
#     Write-InstallLog -Message "VAROVANIE: Test ulohy zlyhal: $($_.Exception.Message)" -Type "Warning"
# }

exit 0