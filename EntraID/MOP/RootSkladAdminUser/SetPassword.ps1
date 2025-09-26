#Requires -RunAsAdministrator
param([switch]$WhatIf = $false)

# --- Nastavenia ---
$ScriptVersion = "2.2-Intune-Fixed"
$ScriptFolder = "C:\TaurisIT\skript\ChangePassword"
$LogFolder = "C:\TaurisIT\log\ChangePassword"
$BackupFolder = "C:\TaurisIT\Backup\ChangePassword"
$LogFile = Join-Path $LogFolder "CheckPasswordExp.log"
$EventLogName = "IntuneScript"
$EventSource = "MOP ChangePassword"

$RootPassword = "RootP@ssw0rd!"
$AdminPassword = "AdminP@ssw0rd!"
$ComputerName = $env:COMPUTERNAME
$SkladPassword = if ($ComputerName -match "^MOP(\d{4})$") { "Tauris$($Matches[1])" } else { "SkladP@ssw0rd!" }

# --- Inicializacia priecinkov ---
foreach ($folder in @($ScriptFolder, $LogFolder, $BackupFolder)) {
    if (-not (Test-Path $folder)) {
        try {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            Write-Output "Priecinok bol vytvoreny: $folder"
        }
        catch {
            Write-Output "Chyba pri vytvarani priecinka - $_"
            exit 2
        }
    }
}

# --- Kontrola administratorskych prav ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Skript musi byt spusteny ako administrator!"
    exit 2
}

# --- Inicializacia EventLogu ---
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction Stop
    }
}
catch {}

# --- Funkcie ---
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARNING", "ERROR")][string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $fullMessage = "$timestamp [$ScriptVersion] [$Level] $Message"
    Write-Output $fullMessage
    $fullMessage | Out-File -FilePath $LogFile -Append -Encoding UTF8
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            $eventId = if ($Level -eq "INFO") { 1000 } elseif ($Level -eq "WARNING") { 2000 } else { 3000 }
            $entryType = if ($Level -eq "INFO") { "Information" } elseif ($Level -eq "WARNING") { "Warning" } else { "Error" }
            Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $entryType -EventId $eventId -Message "$timestamp - $Message"
        }
    }
    catch {}
}

function Write-SecureLog {
    param([string]$Message, [ValidateSet("Information", "Warning", "Error")][string]$Type = "Information", [string]$LogFile)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Type] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Output "$timestamp [$Type] $Message"
}

function Set-PasswordPolicy {
    param([string]$LogFile = (Join-Path $LogFolder "PasswordRoot.log"))

    Write-SecureLog -Message "Zacinam aplikaciu password policy..." -Type "Information" -LogFile $LogFile

    # Cistenie starych .inf a .sdb suborov
    try {
        $oldFiles = Get-ChildItem -Path $ScriptFolder -Include *.inf, *.sdb -File -ErrorAction SilentlyContinue
        foreach ($file in $oldFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            Write-SecureLog -Message "Odstraneny stary subor: $($file.Name)" -Type "Information" -LogFile $LogFile
        }
    }
    catch {
        Write-SecureLog -Message "Chyba pri cisteni suborov v $ScriptFolder - $_" -Type "Warning" -LogFile $LogFile
    }

    # Pouzitie TEMP priecinka namiesto custom priecinka
    $tempPath = [System.IO.Path]::GetTempPath()
    $randomSuffix = Get-Random
    $infPath = Join-Path $tempPath "PasswordPolicy_$randomSuffix.inf"
    $dbPath = Join-Path $tempPath "secedit_$randomSuffix.sdb"

    # Opraveny INF obsah s korektnym formatom - hesla nikdy nevyprsu
    $policyContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordLength = 4
PasswordComplexity = 1
PasswordHistorySize = 1
MaximumPasswordAge = 365
MinimumPasswordAge = 0
ClearTextPassword = 0
LockoutBadCount = 0
RequireLogonToChangePassword = 0
ForceLogoffWhenHourExpire = 0
[Profile Description]
Description=TaurisIT Password Policy - Hesla nikdy nevyprsu
"@

    try {
        # Zaloha sucasnej politiky
        $backupPath = Join-Path $BackupFolder ("secedit_backup_{0}.inf" -f (Get-Date -Format 'yyyyMMddHHmmss'))
        Write-SecureLog -Message "Vytvaranie zalohy politiky..." -Type "Information" -LogFile $LogFile
        
        $exportResult = secedit /export /cfg $backupPath /quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-SecureLog -Message "Zaloha politiky ulozena: $backupPath" -Type "Information" -LogFile $LogFile
        }
        else {
            Write-SecureLog -Message "Warning: Zaloha politiky zlyhala (exit code: $LASTEXITCODE): $($exportResult -join ' ')" -Type "Warning" -LogFile $LogFile
        }

        # Vytvorenie INF suboru s korektnym encoding
        Write-SecureLog -Message "Vytvaranie INF suboru: $infPath" -Type "Information" -LogFile $LogFile
        $policyContent | Out-File -FilePath $infPath -Encoding Unicode -Force
        
        # Overenie ze subor existuje
        if (-not (Test-Path $infPath)) {
            throw "INF subor nebol vytvoreny: $infPath"
        }

        Write-SecureLog -Message "INF subor uspesne vytvoreny (velkost: $((Get-Item $infPath).Length) bytes)" -Type "Information" -LogFile $LogFile

        # Aplikacia politiky s detailnejsim logovanim
        Write-SecureLog -Message "Aplikujem password policy pomocou secedit..." -Type "Information" -LogFile $LogFile
        Write-SecureLog -Message "secedit /configure /db `"$dbPath`" /cfg `"$infPath`" /overwrite /quiet" -Type "Information" -LogFile $LogFile
        
        $configResult = secedit /configure /db $dbPath /cfg $infPath /overwrite /quiet 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-SecureLog -Message "secedit exit code: $exitCode" -Type "Information" -LogFile $LogFile
        Write-SecureLog -Message "secedit output: $($configResult -join '`n')" -Type "Information" -LogFile $LogFile

        if ($exitCode -ne 0) {
            # Pokus o aplikaciu bez /overwrite parametra
            Write-SecureLog -Message "Prva aplikacia zlyhala, skusam bez /overwrite..." -Type "Warning" -LogFile $LogFile
            $configResult2 = secedit /configure /db $dbPath /cfg $infPath /quiet 2>&1
            $exitCode2 = $LASTEXITCODE
            
            Write-SecureLog -Message "secedit (2nd attempt) exit code: $exitCode2" -Type "Information" -LogFile $LogFile
            Write-SecureLog -Message "secedit (2nd attempt) output: $($configResult2 -join '`n')" -Type "Information" -LogFile $LogFile
            
            if ($exitCode2 -ne 0) {
                throw "secedit zlyhalo aj na druhy pokus s kodom $exitCode2. Prva chyba: $exitCode"
            }
        }

        # Refresh Group Policy
        Write-SecureLog -Message "Refreshujem Group Policy..." -Type "Information" -LogFile $LogFile
        Start-Sleep -Seconds 2
        
        $gpResult = gpupdate /force /target:computer 2>&1
        Write-SecureLog -Message "gpupdate result: $($gpResult -join '`n')" -Type "Information" -LogFile $LogFile
        
        Write-SecureLog -Message "Password policy bola uspesne aplikovana" -Type "Information" -LogFile $LogFile
    }
    catch {
        Write-SecureLog -Message "CHYBA pri aplikacii politiky hesiel: $_" -Type "Error" -LogFile $LogFile
        Write-SecureLog -Message "Detaily chyby: $($_.Exception.Message)" -Type "Error" -LogFile $LogFile
        throw $_
    }
    finally {
        # Cleanup temp suborov
        try {
            if (Test-Path $infPath) {
                Remove-Item $infPath -Force -ErrorAction SilentlyContinue
                Write-SecureLog -Message "Odstraneny INF subor: $infPath" -Type "Information" -LogFile $LogFile
            }
            if (Test-Path $dbPath) {
                Remove-Item $dbPath -Force -ErrorAction SilentlyContinue  
                Write-SecureLog -Message "Odstraneny SDB subor: $dbPath" -Type "Information" -LogFile $LogFile
            }
        }
        catch {
            Write-SecureLog -Message "Warning: Chyba pri cisteni temp suborov: $_" -Type "Warning" -LogFile $LogFile
        }
    }
}

function Set-UserPassword {
    param([string]$UserName, [string]$ExpectedPassword)
    try {
        $user = Get-LocalUser -Name $UserName -ErrorAction Stop
        if (-not $user.Enabled) {
            Write-Log "Ucet $UserName je zakazany - heslo sa nenastavuje." "WARNING"
            return $true
        }
        if ($WhatIf) {
            Write-Log "[SIMULACIA] Heslo pre $UserName by bolo nastavene." "INFO"
            return $true
        }
        
        $securePwd = ConvertTo-SecureString $ExpectedPassword -AsPlainText -Force
        
        try {
            #$user | Set-LocalUser -Password $securePwd -PasswordNeverExpires $true -ErrorAction Stop
            $user | Set-LocalUser -Password $securePwd -ErrorAction Stop
            Write-Log "Heslo pre $UserName bolo uspesne nastavene (heslo vyprsi o 365 dni)." "INFO"
            return $true
        }
        catch [Microsoft.PowerShell.Commands.InvalidPasswordException] {
            Write-Log "CHYBA: Heslo pre $UserName nespina poziadavky politiky hesiel: $_" "ERROR"
            return $false
        }
        catch [System.UnauthorizedAccessException] {
            Write-Log "CHYBA: Nedostatocne opravnenia pre zmenu hesla $UserName - $_" "ERROR" 
            return $false
        }
        catch {
            Write-Log "CHYBA: Neocakavana chyba pri nastavovani hesla pre $UserName - $_" "ERROR"
            return $false
        }
    }
    catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
        Write-Log "CHYBA: Pouzivatel $UserName neexistuje." "ERROR"
        return $false
    }
    catch {
        Write-Log "CHYBA: Neocakavana chyba pri prace s pouzivatelom $UserName - $_" "ERROR"
        return $false
    }
}

# --- Hlavna logika ---
try {
    Write-Log "=== Start skriptu ===" "INFO"
    Write-Log "Verzia: $ScriptVersion" "INFO"
    Write-Log "Pocitac: $ComputerName" "INFO"
    Write-Log "Heslo pre Sklad: $SkladPassword" "INFO"
    if ($WhatIf) { Write-Log "REZIM SIMULACIE: Ziadne zmeny nebudu vykonane" "INFO" }

    $accounts = @(
        @{ Name = "Root"; Password = $RootPassword },
        @{ Name = "Admin"; Password = $AdminPassword },
        @{ Name = "Sklad"; Password = $SkladPassword }
    )

    $results = @()
    foreach ($account in $accounts) {
        Write-Log "Spracovavam ucet: $($account.Name)" "INFO"
        $success = Set-UserPassword -UserName $account.Name -ExpectedPassword $account.Password
        $results += @{ UserName = $account.Name; Success = $success }
    }

    $successCount = ($results | Where-Object { $_.Success }).Count
    $totalCount = $results.Count

    # Aplikacia password policy len ak nie je WhatIf
    if (-not $WhatIf) {
        Write-Log "Aplikujem politiku hesiel..." "INFO"
        try {
            Set-PasswordPolicy
            Write-Log "Politika hesiel bola uspesne aplikovana" "INFO"
        }
        catch {
            Write-Log "VAROVANIE: Politika hesiel nebola aplikovana: $_" "WARNING"
            Write-Log "Pokracujem v nastavovani hesiel bez zmeny politiky..." "INFO"
        }
    }
    else {
        Write-Log "[SIMULACIA] Politika hesiel by bola aplikovana" "INFO"
    }
    
    Write-Log "=== Sumarizacia ===" "INFO"
    Write-Log "Celkovy pocet uctov: $totalCount" "INFO"
    Write-Log "Uspesne: $successCount" "INFO"
    Write-Log "Neuspesne: $($totalCount - $successCount)" "INFO"

    foreach ($result in $results) {
        $status = if ($result.Success) { "USPESNE" } else { "CHYBA" }
        $level = if ($result.Success) { "INFO" } else { "WARNING" }
        Write-Log "Ucet $($result.UserName): $status" $level
    }

    if ($successCount -eq $totalCount) {
        Write-Log "INTUNE_RESULT: SUCCESS - Vsetky ucty boli uspesne spracovane." "INFO"
        $exitCode = 0
    }
    elseif ($successCount -gt 0) {
        Write-Log "INTUNE_RESULT: PARTIAL_FAILURE - Niektore ucty neboli uspesne spracovane." "WARNING"
        $exitCode = 1
    }
    else {
        Write-Log "INTUNE_RESULT: FAILURE - Ziadny ucet nebol uspesne spracovany." "ERROR"
        $exitCode = 1
    }

    Write-Log "=== Koniec skriptu ===" "INFO"
    exit $exitCode
}
catch {
    Write-Log "INTUNE_RESULT: CRITICAL_ERROR - $_" "ERROR"
    exit 2
}