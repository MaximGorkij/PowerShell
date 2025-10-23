<#
.SYNOPSIS
    Nastavuje heslá pre lokálne účty a aplikuje password policy.
.DESCRIPTION
    Skript zabezpečuje nastavenie hesiel pre lokálne účty (Root, Admin, Sklad) 
    a aplikuje password policy cez secedit. Heslá vypršia o 365 dní.
    Automaticky ruší príznak "User must change password at next logon".
.AUTHOR
    Marek Findrik
.CREATED
    2025-01-15
.VERSION
    2.4
.NOTES
    - Vyžaduje spustenie ako Administrator
    - Používa modul LogHelper pre logovanie
    - Logy sa ukladajú do: C:\TaurisIT\log\ChangePassword
    - Zálohy secedit politiky: C:\TaurisIT\Backup\ChangePassword
    - Password policy: MinLength=4, Complexity=1, MaxAge=365 dní
    - Event Log: IntuneScript / MOP ChangePassword
.PARAMETER WhatIf
    Simulačný režim - nevykoná žiadne zmeny, len zobrazí čo by sa urobilo
.EXAMPLE
    .\ChangePassword.ps1
    Nastaví heslá a aplikuje password policy
.EXAMPLE
    .\ChangePassword.ps1 -WhatIf
    Simulácia bez vykonania zmien
#>

#Requires -RunAsAdministrator
#Requires -Modules LogHelper
param([switch]$WhatIf = $false)

# --- Nastavenia ---
$ScriptVersion = "2.4"
$ScriptFolder = "C:\TaurisIT\skript\ChangePassword"
$LogFolder = "C:\TaurisIT\log\ChangePassword"
$BackupFolder = "C:\TaurisIT\Backup\ChangePassword"
$LogFile = Join-Path $LogFolder "CheckPasswordExp.log"
$EventSource = "MOP ChangePassword"

# BEZPECNOSTNE NASTAVENIE: Heslá by mali byť načítané z bezpečného úložiska
# Pre produkčné použitie odporúčam Azure Key Vault alebo Intune Secure Variables
$RootPassword = "Tlacenka1"
$AdminPassword = "DRUFhijac1"
$ComputerName = $env:COMPUTERNAME
$SkladPassword = if ($ComputerName -match "^MOP(\d{4})$") { "Tauris$($Matches[1])" } else { "SkladP@ssw0rd!" }

# DÔLEŽITÉ: Heslá vypršia o 365 dní
$PasswordNeverExpires = $false  # Fixne nastavené na 365 dní

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

# --- Import modulu LogHelper ---
try {
    Import-Module LogHelper -ErrorAction Stop
}
catch {
    Write-Error "Nepodarilo sa nacitat modul LogHelper: $_"
    exit 2
}

# --- Funkcie ---
function Write-Log {
    param(
        [string]$Message, 
        [ValidateSet("INFO", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    
    # Mapovanie na LogHelper format
    $logType = switch ($Level) {
        "INFO" { "Information" }
        "WARNING" { "Warning" }
        "ERROR" { "Error" }
    }
    
    $fullMessage = "[$ScriptVersion] [$Level] $Message"
    
    Write-CustomLog -Message $fullMessage `
        -EventSource $EventSource `
        -LogFileName $LogFile `
        -Type $logType
    
    Write-Output $fullMessage
}

function Set-PasswordPolicy {
    Write-Log "Zacinam aplikaciu password policy..." "INFO"

    # Cistenie starych .inf a .sdb suborov
    try {
        $oldFiles = Get-ChildItem -Path $ScriptFolder -Include *.inf, *.sdb -File -ErrorAction SilentlyContinue
        foreach ($file in $oldFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Odstraneny stary subor: $($file.Name)" "INFO"
        }
    }
    catch {
        Write-Log "Chyba pri cisteni suborov v $ScriptFolder - $_" "WARNING"
    }

    # Pouzitie TEMP priecinka
    $tempPath = [System.IO.Path]::GetTempPath()
    $randomSuffix = Get-Random
    $infPath = Join-Path $tempPath "PasswordPolicy_$randomSuffix.inf"
    $dbPath = Join-Path $tempPath "secedit_$randomSuffix.sdb"

    # MaximumPasswordAge: fixne nastavené na 365 dní
    $maxPasswordAge = 365
    
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
MaximumPasswordAge = $maxPasswordAge
MinimumPasswordAge = 0
ClearTextPassword = 0
LockoutBadCount = 0
RequireLogonToChangePassword = 0
ForceLogoffWhenHourExpire = 0
[Profile Description]
Description=TaurisIT Password Policy v$ScriptVersion
"@

    try {
        # Zaloha sucasnej politiky
        $backupPath = Join-Path $BackupFolder ("secedit_backup_{0}.inf" -f (Get-Date -Format 'yyyyMMddHHmmss'))
        Write-Log "Vytvaranie zalohy politiky..." "INFO"
        
        $exportResult = secedit /export /cfg $backupPath /quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Zaloha politiky ulozena: $backupPath" "INFO"
        }
        else {
            Write-Log "Warning: Zaloha politiky zlyhala (exit code: $LASTEXITCODE)" "WARNING"
        }

        # Vytvorenie INF suboru
        Write-Log "Vytvaranie INF suboru: $infPath" "INFO"
        $policyContent | Out-File -FilePath $infPath -Encoding Unicode -Force
        
        if (-not (Test-Path $infPath)) {
            throw "INF subor nebol vytvoreny: $infPath"
        }

        $fileSize = (Get-Item $infPath).Length
        Write-Log "INF subor vytvoreny (velkost: $fileSize bytes)" "INFO"
        Write-Log "MaximumPasswordAge: 365 dni (hesla vyprsu po roku)" "INFO"

        # Aplikacia politiky
        Write-Log "Aplikujem password policy pomocou secedit..." "INFO"
        Write-Log "Prikaz: secedit /configure /db `"$dbPath`" /cfg `"$infPath`" /overwrite /quiet" "INFO"
        
        $configResult = secedit /configure /db $dbPath /cfg $infPath /overwrite /quiet 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-Log "secedit exit code: $exitCode" "INFO"
        if ($configResult) {
            Write-Log "secedit output: $($configResult -join '; ')" "INFO"
        }

        if ($exitCode -ne 0) {
            Write-Log "Prva aplikacia zlyhala, skusam bez /overwrite..." "WARNING"
            $configResult2 = secedit /configure /db $dbPath /cfg $infPath /quiet 2>&1
            $exitCode2 = $LASTEXITCODE
            
            Write-Log "secedit (2. pokus) exit code: $exitCode2" "INFO"
            
            if ($exitCode2 -ne 0) {
                throw "secedit zlyhalo aj na druhy pokus s kodom $exitCode2. Prva chyba: $exitCode"
            }
        }

        # Refresh Group Policy
        Write-Log "Refreshujem Group Policy..." "INFO"
        Start-Sleep -Seconds 2
        
        $gpResult = gpupdate /force /target:computer 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Group Policy uspesne aktualizovana" "INFO"
        }
        else {
            Write-Log "Warning: gpupdate vratil kod $LASTEXITCODE" "WARNING"
        }
        
        Write-Log "Password policy uspesne aplikovana" "INFO"
    }
    catch {
        Write-Log "CHYBA pri aplikacii politiky hesiel: $_" "ERROR"
        Write-Log "Detaily: $($_.Exception.Message)" "ERROR"
        throw $_
    }
    finally {
        # Cleanup temp suborov
        try {
            if (Test-Path $infPath) {
                Remove-Item $infPath -Force -ErrorAction SilentlyContinue
                Write-Log "Odstraneny INF subor: $infPath" "INFO"
            }
            if (Test-Path $dbPath) {
                Remove-Item $dbPath -Force -ErrorAction SilentlyContinue
                Write-Log "Odstraneny SDB subor: $dbPath" "INFO"
            }
        }
        catch {
            Write-Log "Warning: Chyba pri cisteni temp suborov: $_" "WARNING"
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
        
        # Kontrola "User must change password at next logon"
        if ($user.PasswordChangeableDate -gt (Get-Date)) {
            Write-Log "Ucet $UserName ma nastavene 'User must change password at next logon' - ruším nastavenie" "WARNING"
        }
        
        if ($WhatIf) {
            Write-Log "[SIMULACIA] Heslo pre $UserName by bolo nastavene (vyprsi o 365 dni)" "INFO"
            if ($user.PasswordChangeableDate -gt (Get-Date)) {
                Write-Log "[SIMULACIA] 'User must change password at next logon' by bolo zrusene" "INFO"
            }
            return $true
        }
        
        $securePwd = ConvertTo-SecureString $ExpectedPassword -AsPlainText -Force
        
        try {
            # Nastavenie hesla - vyprší o 365 dní a zrušenie "change at next logon"
            $user | Set-LocalUser -Password $securePwd -PasswordNeverExpires $false -UserMayChangePassword $true -ErrorAction Stop
            Write-Log "Heslo pre $UserName uspesne nastavene (vyprsi o 365 dni)" "INFO"
            
            # Overenie či bolo zrušené "change at next logon"
            $userAfter = Get-LocalUser -Name $UserName -ErrorAction Stop
            if ($userAfter.PasswordChangeableDate -le (Get-Date)) {
                Write-Log "'User must change password at next logon' bolo uspesne zrusene" "INFO"
            }
            
            return $true
        }
        catch [Microsoft.PowerShell.Commands.InvalidPasswordException] {
            Write-Log "CHYBA: Heslo pre $UserName nespina poziadavky politiky: $_" "ERROR"
            return $false
        }
        catch [System.UnauthorizedAccessException] {
            Write-Log "CHYBA: Nedostatocne opravnenia pre zmenu hesla $UserName - $_" "ERROR" 
            return $false
        }
        catch {
            Write-Log "CHYBA: Neocakavana chyba pri nastavovani hesla pre $UserName - $_" "ERROR"
            Write-Log "Exception type: $($_.Exception.GetType().FullName)" "ERROR"
            return $false
        }
    }
    catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
        Write-Log "CHYBA: Pouzivatel $UserName neexistuje" "ERROR"
        return $false
    }
    catch {
        Write-Log "CHYBA: Neocakavana chyba pri prace s pouzivatelom $UserName - $_" "ERROR"
        return $false
    }
}

# --- Hlavna logika ---
try {
    Write-Log "=======================================" "INFO"
    Write-Log "=== START SKRIPTU ===" "INFO"
    Write-Log "=======================================" "INFO"
    Write-Log "Verzia: $ScriptVersion" "INFO"
    Write-Log "Pocitac: $ComputerName" "INFO"
    Write-Log "Password expiracia: 365 dni" "INFO"
    Write-Log "Cas spustenia: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    
    if ($WhatIf) { 
        Write-Log "!!! REZIM SIMULACIE: Ziadne zmeny nebudu vykonane !!!" "WARNING" 
    }

    # KROK 1: Najprv aplikovať password policy
    if (-not $WhatIf) {
        Write-Log "=======================================" "INFO"
        Write-Log "KROK 1: Aplikacia password policy" "INFO"
        Write-Log "=======================================" "INFO"
        try {
            Set-PasswordPolicy
            Write-Log "Password policy uspesne aplikovana" "INFO"
            Write-Log "Cakam 3 sekundy na aplikovanie zmien..." "INFO"
            Start-Sleep -Seconds 3
        }
        catch {
            Write-Log "VAROVANIE: Password policy nebola aplikovana: $_" "WARNING"
            Write-Log "Pokracujem v nastavovani hesiel bez zmeny politiky..." "WARNING"
        }
    }
    else {
        Write-Log "[SIMULACIA] Password policy by bola aplikovana" "INFO"
    }

    # KROK 2: Potom nastaviť heslá
    Write-Log "=======================================" "INFO"
    Write-Log "KROK 2: Nastavenie hesiel pouzivatelov" "INFO"
    Write-Log "=======================================" "INFO"
    
    $accounts = @(
        @{ Name = "Root"; Password = $RootPassword },
        @{ Name = "Admin"; Password = $AdminPassword },
        @{ Name = "Sklad"; Password = $SkladPassword }
    )

    Write-Log "Pocet uctov na spracovanie: $($accounts.Count)" "INFO"

    $results = @()
    foreach ($account in $accounts) {
        Write-Log "---------------------------------------" "INFO"
        Write-Log "Spracovavam ucet: $($account.Name)" "INFO"
        $success = Set-UserPassword -UserName $account.Name -ExpectedPassword $account.Password
        $results += @{ UserName = $account.Name; Success = $success }
    }

    # Sumarizácia výsledkov
    Write-Log "=======================================" "INFO"
    Write-Log "=== SUMARIZACIA VYSLEDKOV ===" "INFO"
    Write-Log "=======================================" "INFO"
    
    $successCount = ($results | Where-Object { $_.Success }).Count
    $totalCount = $results.Count
    
    Write-Log "Celkovy pocet uctov: $totalCount" "INFO"
    Write-Log "Uspesne spracovane: $successCount" "INFO"
    Write-Log "Neuspesne spracovane: $($totalCount - $successCount)" "INFO"
    Write-Log "Uspesnost: $([math]::Round(($successCount / $totalCount) * 100, 2))%" "INFO"

    Write-Log "---------------------------------------" "INFO"
    Write-Log "Detail jednotlivych uctov:" "INFO"
    foreach ($result in $results) {
        $status = if ($result.Success) { "✓ USPESNE" } else { "✗ CHYBA" }
        $level = if ($result.Success) { "INFO" } else { "ERROR" }
        Write-Log "  $($result.UserName): $status" $level
    }

    # Určenie exit kódu a INTUNE výsledku
    Write-Log "=======================================" "INFO"
    if ($successCount -eq $totalCount) {
        Write-Log "INTUNE_RESULT: SUCCESS" "INFO"
        Write-Log "Vsetky ucty boli uspesne spracovane" "INFO"
        $exitCode = 0
    }
    elseif ($successCount -gt 0) {
        Write-Log "INTUNE_RESULT: PARTIAL_FAILURE" "WARNING"
        Write-Log "Niektore ucty neboli uspesne spracovane" "WARNING"
        $exitCode = 1
    }
    else {
        Write-Log "INTUNE_RESULT: FAILURE" "ERROR"
        Write-Log "Ziadny ucet nebol uspesne spracovany" "ERROR"
        $exitCode = 1
    }

    Write-Log "Exit kod: $exitCode" "INFO"
    Write-Log "=== KONIEC SKRIPTU ===" "INFO"
    Write-Log "=======================================" "INFO"
    
    exit $exitCode
}
catch {
    Write-Log "=======================================" "ERROR"
    Write-Log "KRITICKÁ CHYBA" "ERROR"
    Write-Log "=======================================" "ERROR"
    Write-Log "INTUNE_RESULT: CRITICAL_ERROR" "ERROR"
    Write-Log "Chybova sprava: $_" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "Exception type: $($_.Exception.GetType().FullName)" "ERROR"
    Write-Log "=======================================" "ERROR"
    exit 2
}