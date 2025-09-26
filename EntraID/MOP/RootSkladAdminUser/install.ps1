<#
.SYNONOPSIS
    Instalacny skript pre Password Management system MOP - Intune Package
.DESCRIPTION
    Nakopiruje skripty, vytvori potrebne adresare, nastavi opravnenia
    a vytvori scheduled task pre spustanie kazdy den okrem nedele o 5:30
    Optimalizovany pre nasadenie cez Microsoft Intune
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-25
.VERSION
    1.3.4 - Opravy hladania suborov
.NOTES
    Spusta sa automaticky s SYSTEM pravami v Intune kontexte
    Vytvori task schedule: Pondelok-Sobota o 5:30
    Loguje do konzoly, suboru a event logu
#>

# === PARAMETRE PRE INTUNE ===
$ScriptFolder = "C:\TaurisIT\skript\ChangePassword"
$LogDir = "C:\TaurisIT\Log\ChangePassword"
$BackupDir = "C:\TaurisIT\Backup\ChangePassword"
$LogFile = Join-Path $LogDir "MOPPasswordInstall.txt"
$EventSource = "MOP Password Install"
$EventLogName = "IntuneAppInstall"

# Task nastavenia
$TaskName = "PasswordChangeWeekdays"
$TaskTime = "05:30"
$TaskDescription = "MOP Password Change - Weekdays Only (Monday-Saturday) - Deployed via Intune"

# Intune specific settings
$IntuneMode = $true
$SilentMode = $false
$ExitCodes = @{
    Success            = 0
    GeneralError       = 1
    FileNotFound       = 2
    AccessDenied       = 3
    TaskCreationFailed = 4
    ValidationFailed   = 5
}

# Farba pre konzolove logovanie
$Host.UI.RawUI.ForegroundColor = "White"

# Subory na instalaciu (relativne cesty pre Intune package)
$RequiredFiles = @{
    "SetPassword.ps1" = "Hlavny skript pre spravu hesiel"    
}

# === FUNKCIA: KONZOLOVE LOGOVANIE S FARBAMI ===
function Write-ConsoleLog {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [string]$Color = "White"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Nastav farbu podla typu spravy
    $consoleColor = switch ($Type) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        "Info" { "Cyan" }
        "Header" { "Magenta" }
        default { "White" }
    }
    
    # Format pre konzolu
    $logEntry = "[$timestamp] [$Type] $Message"
    
    # Vypis do konzoly s farbou
    try {
        $originalColor = $Host.UI.RawUI.ForegroundColor
        $Host.UI.RawUI.ForegroundColor = $consoleColor
        Write-Output $logEntry
        $Host.UI.RawUI.ForegroundColor = $originalColor
    }
    catch {
        # Fallback ak farby zlyhaju
        Write-Output $logEntry
    }
}

# === FUNKCIA: INTUNE LOGOVANIE (ROZSIRENE O KONZOLU) ===
function Write-IntuneLog {
    param (
        [string]$Message,
        [string]$Type = "Information"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    
    try {
        # Ensure log directory exists
        if (-not (Test-Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        
        # Write to log file
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        
        # Write to Event Log for Intune monitoring
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
                New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction SilentlyContinue
            }
            
            $EventType = switch ($Type) {
                "Error" { "Error" }
                "Warning" { "Warning" }
                default { "Information" }
            }
            
            Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $EventType -EventId 4000 -Message "Intune Package: $Message" -ErrorAction SilentlyContinue
        }
        catch {
            # Event log failure should not stop execution
        }
        
        # VZDY vypis do konzoly
        Write-ConsoleLog -Message $Message -Type $Type
        
    }
    catch {
        Write-Output "LOG ERROR: $Message"
    }
}

# === FUNKCIA: VYPIS HLAVICKY ===
function Show-Header {
    Write-ConsoleLog -Message "==========================================================" -Type "Header"
    Write-ConsoleLog -Message "MOP Password Management - Intune Deployment" -Type "Header"
    Write-ConsoleLog -Message "Verzia: 1.3.4 (Opravy hladania suborov)" -Type "Header"
    Write-ConsoleLog -Message "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Type "Header"
    Write-ConsoleLog -Message "PSScriptRoot: $PSScriptRoot" -Type "Header"
    Write-ConsoleLog -Message "==========================================================" -Type "Header"
    Write-ConsoleLog -Message " " -Type "Header"
}

# === FUNKCIA: VYPIS PATICKY ===
function Show-Footer {
    param([bool]$Success, [string]$Duration)
    
    Write-ConsoleLog -Message " " -Type "Header"
    Write-ConsoleLog -Message "==========================================================" -Type "Header"
    if ($Success) {
        Write-ConsoleLog -Message "INSTALACIA USPESNE DOKONCENA" -Type "Success"
        Write-ConsoleLog -Message "Trvanie: $Duration" -Type "Success"
    }
    else {
        Write-ConsoleLog -Message "INSTALACIA ZLYHALA" -Type "Error"
        Write-ConsoleLog -Message "Trvanie: $Duration" -Type "Error"
    }
    Write-ConsoleLog -Message "Koniec: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Type "Header"
    Write-ConsoleLog -Message "==========================================================" -Type "Header"
}

# === FUNKCIA: HLADANIE SUBOROV V INTUNE PACKAGE ===
function Find-IntunePackageFiles {
    Write-IntuneLog -Message "Hladam subory v Intune package..." -Type "Info"
    
    # Možné umiestnenia súborov v Intune package
    $searchPaths = @(
        $PSScriptRoot  # Hlavný adresár skriptu
        Join-Path $PSScriptRoot "Content"  # Intune Content adresár
        Join-Path $PSScriptRoot "Files"    # Intune Files adresár
        (Get-Location).Path               # Aktuálny pracovný adresár
        "C:\Windows\IMECache"             # Intune cache adresár
        "C:\Program Files\WindowsApps"     # Windows Apps adresár
    )
    
    $foundFiles = @{}
    
    foreach ($file in $RequiredFiles.Keys) {
        $fileFound = $false
        $foundPath = $null
        
        foreach ($searchPath in $searchPaths) {
            if (Test-Path $searchPath) {
                $testPath = Join-Path $searchPath $file
                if (Test-Path $testPath) {
                    $fileFound = $true
                    $foundPath = $testPath
                    Write-IntuneLog -Message "Najdeny subor: $file -> $foundPath" -Type "Success"
                    break
                }
            }
        }
        
        if (-not $fileFound) {
            # Skúsime rekurzívne vyhľadávanie v PSScriptRoot
            try {
                $allFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue
                $matchingFile = $allFiles | Where-Object { $_.Name -eq $file }
                if ($matchingFile) {
                    $fileFound = $true
                    $foundPath = $matchingFile.FullName
                    Write-IntuneLog -Message "Najdeny subor (rekurzivne): $file -> $foundPath" -Type "Success"
                }
            }
            catch {
                # Rekurzívne vyhľadávanie zlyhalo
            }
        }
        
        $foundFiles[$file] = @{
            Found       = $fileFound
            Path        = $foundPath
            Description = $RequiredFiles[$file]
        }
        
        if (-not $fileFound) {
            Write-IntuneLog -Message "SUBOR NENAJDENY: $file" -Type "Error"
        }
    }
    
    # Vypíš prehľad nájdených súborov
    Write-IntuneLog -Message "=== PREHLAD NAJDENYCH SUBOROV ===" -Type "Info"
    foreach ($file in $foundFiles.Keys) {
        $status = if ($foundFiles[$file].Found) { "OK" } else { "CHYBA" }
        Write-IntuneLog -Message "$status - $file ($($foundFiles[$file].Description))" -Type $(if ($foundFiles[$file].Found) { "Success" } else { "Error" })
    }
    
    return $foundFiles
}

# === FUNKCIA: KONTROLA SYSTEM PRAV ===
function Test-SystemRights {
    Write-IntuneLog -Message "Kontrolujem systemove prava..." -Type "Info"
    
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isSystem = $currentUser.IsSystem
    $isAdmin = ([Security.Principal.WindowsPrincipal] $currentUser).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    
    if (-not ($isSystem -or $isAdmin)) {
        Write-IntuneLog -Message "CHYBA: Skript musi byt spusteny ako SYSTEM alebo Administrator" -Type "Error"
        return $false
    }
    
    Write-IntuneLog -Message "Overenie prav: OK (User: $($currentUser.Name), System: $isSystem, Admin: $isAdmin)" -Type "Success"
    return $true
}

# === FUNKCIA: NAJDENIE POWERSHELL CESTY ===
function Find-PowerShellPath {
    Write-IntuneLog -Message "Hladam cestu k PowerShell..." -Type "Info"
    
    $PowerShellPaths = @(
        "C:\Program Files\PowerShell\7\pwsh.exe",
        "C:\Program Files\PowerShell\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",
        "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    )
    
    foreach ($path in $PowerShellPaths) {
        if (Test-Path $path) {
            Write-IntuneLog -Message "Najdena PowerShell cesta: $path" -Type "Success"
            return $path
        }
    }
    
    Write-IntuneLog -Message "Pouzije sa systemovy PowerShell" -Type "Warning"
    return "powershell.exe"
}

# === FUNKCIA: VYTVORENIE BEZPECNEHO ADRESARA ===
function New-IntuneDirectory {
    param (
        [string]$Path,
        [string]$Description
    )
    
    try {
        Write-IntuneLog -Message "Vytvaram adresar: $Description" -Type "Info"
        
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-IntuneLog -Message "Vytvoreny adresar: $Path" -Type "Success"
        }
        else {
            Write-IntuneLog -Message "Adresar uz existuje: $Path" -Type "Info"
        }
        
        try {
            $acl = Get-Acl $Path
            $acl.SetAccessRuleProtection($true, $false)
            
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            
            $acl.SetAccessRule($systemRule)
            $acl.SetAccessRule($adminRule)
            Set-Acl -Path $Path -AclObject $acl
            Write-IntuneLog -Message "Nastavene opravnenia pre: $Path" -Type "Success"
        }
        catch {
            Write-IntuneLog -Message "Chyba pri nastavovani opravneni pre $Path : $_" -Type "Warning"
        }
        
        return $true
    }
    catch {
        Write-IntuneLog -Message "Chyba pri vytvarani adresara $Path : $_" -Type "Error"
        return $false
    }
}

# === FUNKCIA: KOPIROVANIE SUBORU PRE INTUNE ===
function Copy-IntuneFile {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$Description,
        [bool]$Required = $true
    )
    
    Write-IntuneLog -Message "Kopirujem subor: $Description" -Type "Info"
    Write-IntuneLog -Message "Zdroj: $SourcePath" -Type "Info"
    Write-IntuneLog -Message "Ciel: $DestinationPath" -Type "Info"
    
    if (-not (Test-Path $SourcePath)) {
        $message = "Zdrojovy subor neexistuje: $SourcePath"
        if ($Required) {
            Write-IntuneLog -Message $message -Type "Error"
            return $false
        }
        else {
            Write-IntuneLog -Message "$message - Preskakujem (volitelny)" -Type "Warning"
            return $true
        }
    }
    
    try {
        # Vytvorit backup ak subor existuje
        if (Test-Path $DestinationPath) {
            $backupName = "$(Split-Path $DestinationPath -Leaf).backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
            $backupPath = Join-Path $BackupDir $backupName
            
            if (-not (Test-Path $BackupDir)) {
                New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
            }
            
            Copy-Item $DestinationPath $backupPath -Force
            Write-IntuneLog -Message "Vytvorena zaloha: $backupPath" -Type "Info"
        }
        
        # Kopirovat subor
        Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
        
        # Overit kopiu
        if (Test-Path $DestinationPath) {
            $sourceSize = (Get-Item $SourcePath).Length
            $destSize = (Get-Item $DestinationPath).Length
            
            if ($sourceSize -eq $destSize) {
                Write-IntuneLog -Message "Uspesne skopirovany: $(Split-Path $DestinationPath -Leaf)" -Type "Success"
                
                # Nastavit opravnenia
                try {
                    $acl = Get-Acl $DestinationPath
                    $acl.SetAccessRuleProtection($true, $false)
                    
                    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
                    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "Allow")
                    
                    $acl.SetAccessRule($systemRule)
                    $acl.SetAccessRule($adminRule)
                    Set-Acl -Path $DestinationPath -AclObject $acl
                }
                catch {
                    Write-IntuneLog -Message "Chyba pri nastavovani opravneni: $_" -Type "Warning"
                }
                
                return $true
            }
            else {
                Write-IntuneLog -Message "Chyba pri kopii - rozdielne velkosti ($sourceSize vs $destSize)" -Type "Error"
                return $false
            }
        }
        else {
            Write-IntuneLog -Message "Chyba - cielovy subor neexistuje po kopii" -Type "Error"
            return $false
        }
    }
    catch {
        Write-IntuneLog -Message "Chyba pri kopirovani $SourcePath : $_" -Type "Error"
        return $false
    }
}

# === FUNKCIA: VYTVORENIE VZOROVEHO KONFIGURACNEHO SUBORU ===
function New-IntunePasswordConfig {
    param (
        [string]$ConfigPath
    )
    
    Write-IntuneLog -Message "Vytvaram konfiguracny subor..." -Type "Info"
    
    if (Test-Path $ConfigPath) {
        Write-IntuneLog -Message "Konfiguracny subor uz existuje: $ConfigPath" -Type "Info"
        return $true
    }
    
    try {
        $configContent = @"
# MOP Password Management Configuration
# Toto je vzorovy konfiguracny subor
# Hesla su ulozene v plain text - zabezpecte pristupove opravnenia!

[Users]
# Format: Username=Password
root=TempRootPassword123!
admin=TempAdminPassword123!

[Settings]
LogPath=C:\TaurisIT\Log\ChangePassword
BackupPath=C:\TaurisIT\Backup\ChangePassword
"@

        Set-Content -Path $ConfigPath -Value $configContent -Encoding UTF8 -Force
        
        try {
            $acl = Get-Acl $ConfigPath
            $acl.SetAccessRuleProtection($true, $false)
            
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "Allow")
            
            $acl.SetAccessRule($systemRule)
            $acl.SetAccessRule($adminRule)
            Set-Acl -Path $ConfigPath -AclObject $acl
        }
        catch {
            Write-IntuneLog -Message "Chyba pri nastavovani opravneni: $_" -Type "Warning"
        }
        
        Write-IntuneLog -Message "Vytvoreny vzorovy konfiguracny subor: $ConfigPath" -Type "Success"
        Write-IntuneLog -Message "VAROVANIE: Hesla su v plain text - overte bezpecnostne opatrenia!" -Type "Warning"
        return $true
    }
    catch {
        Write-IntuneLog -Message "Chyba pri vytvarani konfiguracneho suboru $ConfigPath : $_" -Type "Error"
        return $false
    }
}

# === FUNKCIA: VYTVORENIE SCHEDULED TASKU ===
function New-IntuneScheduledTask {
    param (
        [string]$TaskName,
        [string]$Time,
        [string]$PowerShellPath,
        [string]$ScriptPath,
        [string]$Description
    )

    try {
        Write-IntuneLog -Message "Vytvaram scheduled task..." -Type "Info"

        # Remove existing task
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($null -ne $existingTask) {
            Write-IntuneLog -Message "Odstranujem existujuci task..." -Type "Info"
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-IntuneLog -Message "Odstraneny existujuci task: $TaskName" -Type "Success"
        }

        Write-IntuneLog -Message "Vytváram novy task: $TaskName - Weekdays o $Time" -Type "Info"

        # Verify script exists
        if (-not (Test-Path $ScriptPath)) {
            throw "Hlavny skript neexistuje: $ScriptPath"
        }

        # Create action
        $Action = New-ScheduledTaskAction -Execute $PowerShellPath -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File `"$ScriptPath`""
        
        # Create trigger for weekdays (Monday-Saturday)
        $trigger = New-ScheduledTaskTrigger -Daily -At $Time
        $trigger.DaysOfWeek = 62
        
        # Create principal
        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount

        # Create settings
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 2)

        # Register task
        $Task = New-ScheduledTask -Action $Action -Trigger $trigger -Principal $Principal -Settings $Settings -Description $Description
        Register-ScheduledTask -TaskName $TaskName -InputObject $Task -ErrorAction Stop

        # Verify task creation
        Start-Sleep -Seconds 2
        $verifyTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        
        if ($verifyTask.State -eq "Ready") {
            Write-IntuneLog -Message "Task uspesne vytvoreny: $TaskName (Stav: $($verifyTask.State))" -Type "Success"
            return $true
        }
        else {
            Write-IntuneLog -Message "Task vytvoreny ale nie je Ready: $($verifyTask.State)" -Type "Warning"
            return $false
        }
    }
    catch {
        $msg = "Chyba pri vytvarani task $TaskName : $_"
        Write-IntuneLog -Message $msg -Type "Error"
        return $false
    }
}

# === FUNKCIA: VALIDACIA INSTALACIE ===
function Test-IntuneInstallation {
    $success = $true
    $issues = @()
    
    Write-IntuneLog -Message "Validujem instalaciu..." -Type "Info"
    
    # Check directories
    $directories = @($ScriptFolder, $LogDir, $BackupDir)
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            $issue = "Chyba - adresar neexistuje: $dir"
            $issues += $issue
            $success = $false
            Write-IntuneLog -Message $issue -Type "Error"
        }
        else {
            Write-IntuneLog -Message "Adresar OK: $dir" -Type "Success"
        }
    }
    
    # Check main script
    $mainScript = Join-Path $ScriptFolder "SetPassword.ps1"
    if (-not (Test-Path $mainScript)) {
        $issue = "Chyba - hlavny skript neexistuje: $mainScript"
        $issues += $issue
        $success = $false
        Write-IntuneLog -Message $issue -Type "Error"
    }
    else {
        Write-IntuneLog -Message "Hlavny skript OK: $mainScript" -Type "Success"
    }
    
    # Check scheduled task
    $scheduledTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $scheduledTask) {
        $issue = "Chyba - scheduled task neexistuje: $TaskName"
        $issues += $issue
        $success = $false
        Write-IntuneLog -Message $issue -Type "Error"
    }
    else {
        Write-IntuneLog -Message "Scheduled task OK: $TaskName (Stav: $($scheduledTask.State))" -Type "Success"
    }
    
    if ($success) {
        Write-IntuneLog -Message "Validacia USPESNA - instalacia kompletna" -Type "Success"
    }
    else {
        Write-IntuneLog -Message "Validacia ZLYHALA - najdene problemy: $($issues.Count)" -Type "Error"
    }
    
    return @{
        Success = $success
        Issues  = $issues
    }
}

# === HLAVNY KOD PRE INTUNE DEPLOYMENT ===

$startTime = Get-Date
Show-Header

try {
    # Kontrola prav
    if (-not (Test-SystemRights)) {
        exit $ExitCodes.AccessDenied
    }
    
    # Intune context info
    Write-IntuneLog -Message "Bezi v Intune kontexte, USER: $env:USERNAME" -Type "Info"
    Write-IntuneLog -Message "Computer: $env:COMPUTERNAME, PSVersion: $($PSVersionTable.PSVersion)" -Type "Info"
    Write-IntuneLog -Message "PSScriptRoot: $PSScriptRoot" -Type "Info"
    Write-IntuneLog -Message "Aktualny adresar: $(Get-Location)" -Type "Info"
    
    # Najdi vsetky subory v Intune package
    $packageFiles = Find-IntunePackageFiles
    
    # Skontroluj kriticke subory
    $criticalFilesMissing = $false
    foreach ($file in $RequiredFiles.Keys) {
        if (-not $packageFiles[$file].Found -and $file -eq "SetPassword.ps1") {
            $criticalFilesMissing = $true
            Write-IntuneLog -Message "KRITICKA CHYBA: Chyba hlavny skript SetPassword.ps1" -Type "Error"
        }
    }
    
    if ($criticalFilesMissing) {
        Write-IntuneLog -Message "Zobrazujem obsah adresara $PSScriptRoot pre debug:" -Type "Error"
        try {
            Get-ChildItem -Path $PSScriptRoot -Recurse -ErrorAction SilentlyContinue | 
            ForEach-Object { Write-IntuneLog -Message "  - $($_.FullName)" -Type "Error" }
        }
        catch {
            Write-IntuneLog -Message "Chyba pri zobrazovani obsahu adresara: $_" -Type "Error"
        }
        throw "Kriticke subory chybaju v Intune package"
    }
    
    # Find PowerShell path
    $pwshPath = Find-PowerShellPath
    
    # Create directories
    Write-IntuneLog -Message "Vytváram adresare..." -Type "Info"
    $dirResults = @()
    $dirResults += New-IntuneDirectory -Path $ScriptFolder -Description "Skripty"
    $dirResults += New-IntuneDirectory -Path $LogDir -Description "Logy"
    $dirResults += New-IntuneDirectory -Path $BackupDir -Description "Zalohy"
    
    if ($dirResults -contains $false) {
        throw "Zlyhalo vytvaranie adresarov"
    }
    
    # Copy files
    Write-IntuneLog -Message "Kopirujem subory..." -Type "Info"
    $copyResults = @()
    
    foreach ($file in $RequiredFiles.Keys) {
        if ($packageFiles[$file].Found) {
            $description = $RequiredFiles[$file]
            $isRequired = $file -eq "SetPassword.ps1"
            
            $destinationPath = Join-Path $ScriptFolder $file
            $result = Copy-IntuneFile -SourcePath $packageFiles[$file].Path -DestinationPath $destinationPath -Description $description -Required $isRequired
            $copyResults += $result
        }
        else {
            Write-IntuneLog -Message "Subor $file nebol najdeny v package - preskakujem" -Type "Warning"
        }
    }
    
    # Verify main script was copied
    $mainScriptPath = Join-Path $ScriptFolder "SetPassword.ps1"
    if (-not (Test-Path $mainScriptPath)) {
        throw "Hlavny skript nebol nainstalovany: $mainScriptPath"
    }
    
    # Create sample config file if needed
    $configPath = Join-Path $ScriptFolder "passwords.config"
    if (-not (Test-Path $configPath)) {
        Write-IntuneLog -Message "Vytváram vzorový konfiguračný súbor..." -Type "Info"
        New-IntunePasswordConfig -ConfigPath $configPath | Out-Null
    }
    
    # Create scheduled task
    Write-IntuneLog -Message "Vytváram scheduled task..." -Type "Info"
    $taskResult = New-IntuneScheduledTask -TaskName $TaskName -Time $TaskTime -PowerShellPath $pwshPath -ScriptPath $mainScriptPath -Description $TaskDescription
    
    if (-not $taskResult) {
        Write-IntuneLog -Message "Varovanie - scheduled task nebol vytvoreny" -Type "Warning"
    }
    
    # Validate installation
    $validationResult = Test-IntuneInstallation
    
    $endTime = Get-Date
    $duration = "$([math]::Round(($endTime - $startTime).TotalSeconds, 2)) sekund"
    
    if ($validationResult.Success) {
        Write-IntuneLog -Message "=== INSTALACIA USPESNA ===" -Type "Success"
        Write-IntuneLog -Message "Trvanie: $duration" -Type "Success"
        
        Show-Footer -Success $true -Duration $duration
        exit $ExitCodes.Success
    }
    else {
        Write-IntuneLog -Message "=== INSTALACIA ZLYHALA ===" -Type "Error"
        Write-IntuneLog -Message "Problemy: $($validationResult.Issues.Count)" -Type "Error"
        
        Show-Footer -Success $false -Duration $duration
        exit $ExitCodes.ValidationFailed
    }
}
catch {
    $errorMsg = "Kriticka chyba pocas instalacie: $_"
    Write-IntuneLog -Message $errorMsg -Type "Error"
    Write-IntuneLog -Message "StackTrace: $($_.ScriptStackTrace)" -Type "Error"
    
    $endTime = Get-Date
    $duration = "$([math]::Round(($endTime - $startTime).TotalSeconds, 2)) sekund"
    Show-Footer -Success $false -Duration $duration
    
    if ($_.Exception.Message -like "*Access*denied*") {
        exit $ExitCodes.AccessDenied
    }
    elseif ($_.Exception.Message -like "*not*found*") {
        exit $ExitCodes.FileNotFound
    }
    else {
        exit $ExitCodes.GeneralError
    }
}