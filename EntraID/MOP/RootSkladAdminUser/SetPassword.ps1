<#
.SYNOPSIS
    Skript na kontrolu a zmenu hesla pre používateľov root, admin a sklad pre MOP PC.

.DESCRIPTION
    Overenie a obnova hesla pre používateľov "root", "admin" a "sklad" na MOP počítačoch.

.AUTHOR
    Marek Findrik

.VERSION
    1.6.4
#>

# === PARAMETRE ===
$ScriptFolder = "C:\TaurisIT\skript"
$LogFolder = "C:\TaurisIT\Log"
$RootLogFile = "$LogFolder\PasswordRoot.log"
$AdminLogFile = "$LogFolder\PasswordAdmin.log"
$SkladLogFile = "$LogFolder\PasswordSklad.log"

$RootUser = "root"
$AdminUser = "admin"
$SkladUser = "sklad"

$RootPwdFile = "$ScriptFolder\RootPwd.xml"
$AdminPwdFile = "$ScriptFolder\AdminPwd.xml"

$ScriptPath = "$ScriptFolder\SetPasswords.ps1"
$StartupTaskName = "PasswordCheckStartup"
$DailyTaskName = "PasswordCheckDaily"
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Change"

# === IMPORT MODULU ===
Import-Module LogHelper -ErrorAction SilentlyContinue

# === FUNKCIA: KONTROLA ADMIN PRAV ===
function Test-AdminRights {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Output "ERROR: Tento skript musí byť spustený ako správca (Run as Administrator)."
        exit 1
    }
}

# === FUNKCIA: NASTAVENIE POLITIKY HESIEL ===
function NastavPolitikuHesiel {
    $infPath = "$env:TEMP\PasswordPolicy.inf"
    $dbPath = "$env:TEMP\secedit.sdb"

    @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
revision=1
[System Access]
MinimumPasswordLength = 4
MaximumPasswordAge = 365
PasswordComplexity = 1
PasswordHistorySize = 1
[Registry Values]
[Privilege Rights]
[Profile Description]
Description="TaurisIT Password Policy"
[Section Links]
"@ | Set-Content -Path $infPath -Encoding Unicode

    try {
        # Import policy using secedit
        secedit /configure /db $dbPath /cfg $infPath /overwrite /quiet
        if ($LASTEXITCODE -ne 0) {
            throw "secedit failed with exit code $LASTEXITCODE"
        }

        # Force policy update
        gpupdate /force /target:computer | Out-Null
        
        # Additional registry method to ensure settings are applied
        Set-LocalPasswordPolicy
        
        Write-CustomLog -Message "Politika hesiel bola úspešne nastavená." -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
        Write-Output "INFO: Politika hesiel bola úspešne nastavená."
        
        # Verify settings
        Test-PasswordPolicy
    }
    catch {
        $msg = "Chyba pri nastavovaní politiky hesiel: $_"
        Write-CustomLog -Message $msg -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
        Write-Output "ERROR: $msg"
    }
    finally {
        # Cleanup
        if (Test-Path $infPath) { Remove-Item $infPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dbPath) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue }
    }
}

# === FUNKCIA: NASTAVENIE POLITIKY PRIAMO DO REGISTRA ===
function Set-LocalPasswordPolicy {
    try {
        # Minimum password length
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "MinPasswordLength" -Value 4 -Type DWord -Force
        
        # Password history
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "PasswordHistory" -Value 1 -Type DWord -Force
        
        # Password complexity
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "PasswordComplexity" -Value 1 -Type DWord -Force
        
        # Maximum password age (in days, 365 days = 0x16D0000 in seconds)
        $maxPwdAge = 365 * 86400 # Convert days to seconds
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "MaximumPasswordAge" -Value $maxPwdAge -Type DWord -Force
        
        Write-Output "INFO: Politika hesiel bola nastavená priamo v registri."
    }
    catch {
        Write-Output "ERROR: Chyba pri nastavovaní politiky cez register: $_"
    }
}

# === FUNKCIA: TESTOVANIE NASTAVENYCH HODNOT ===
function Test-PasswordPolicy {
    try {
        $minLength = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "MinPasswordLength" -ErrorAction SilentlyContinue
        $pwdHistory = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "PasswordHistory" -ErrorAction SilentlyContinue
        $pwdComplexity = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "PasswordComplexity" -ErrorAction SilentlyContinue
        
        Write-Output "INFO: Overenie politiky hesiel:"
        Write-Output "INFO:   MinPasswordLength = $minLength"
        Write-Output "INFO:   PasswordHistory = $pwdHistory"
        Write-Output "INFO:   PasswordComplexity = $pwdComplexity"
        
        if ($minLength -eq 4 -and $pwdHistory -eq 1 -and $pwdComplexity -eq 1) {
            Write-Output "INFO: Politika hesiel je správne nastavená."
            return $true
        }
        else {
            Write-Output "WARNING: Nie všetky politiky sú správne nastavené."
            return $false
        }
    }
    catch {
        Write-Output "ERROR: Nepodarilo sa overiť nastavenia politiky: $_"
        return $false
    }
}

# === FUNKCIA: OVERENIE A OBNOVA HESLA ===
function OverHesloAPripadneObnov {
    param (
        [string]$Uzivatel,
        [securestring]$SecurePassword,
        [string]$LogSubor,
        [string]$ZobrazeneMeno = $Uzivatel
    )

    $UserObj = Get-LocalUser -Name $Uzivatel -ErrorAction SilentlyContinue
    if (-not $UserObj) {
        $msg = "$ZobrazeneMeno - Užívateľ neexistuje"
        Write-CustomLog -Message $msg -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "ERROR: $msg"
        return
    }

    if (-not $UserObj.Enabled) {
        Enable-LocalUser -Name $Uzivatel
        Write-CustomLog -Message "$ZobrazeneMeno - Užívateľ bol aktivovaný" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "INFO: $ZobrazeneMeno - Užívateľ bol aktivovaný"
    }

    try {
        Set-LocalUser -Name $Uzivatel -Password $SecurePassword

        Write-CustomLog -Message "$ZobrazeneMeno - Heslo bolo nastavené" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "INFO: $ZobrazeneMeno - Heslo bolo nastavené"
    }
    catch {
        $msg = "$ZobrazeneMeno - Chyba pri nastavovaní hesla: $_"
        Write-CustomLog -Message $msg -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "ERROR: $msg"
    }
}

# === FUNKCIA: VYTVORENIE TASKU ===
function Test-TaskExists {
    param (
        [string]$TaskName,
        [string]$TriggerType,
        [string]$Time
    )

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -ne $existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Write-CustomLog -Message "TASK $TaskName sa vytvára" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
    Write-Output "INFO: TASK $TaskName sa vytvára"

    $Action = New-ScheduledTaskAction -Execute $pwshPath -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Trigger = if ($TriggerType -eq "Startup") {
        New-ScheduledTaskTrigger -AtStartup
    }
    elseif ($TriggerType -eq "Daily") {
        New-ScheduledTaskTrigger -Daily -At $Time
    }

    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -ErrorAction Stop

    Write-CustomLog -Message "TASK $TaskName bol úspešne vytvorený" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
    Write-Output "INFO: TASK $TaskName bol úspešne vytvorený"
}

# === VYTVORENIE PRIECINKOV ===
if (-not (Test-Path $ScriptFolder)) {
    New-Item -Path $ScriptFolder -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# === KONTROLA ADMIN PRÁV ===
Test-AdminRights

# === NASTAVENIE POLITIKY HESIEL ===
NastavPolitikuHesiel

# === NAČÍTANIE HESIEL Z XML ===
if (-not (Test-Path $RootPwdFile)) {
    Write-CustomLog -Message "Chýba súbor $RootPwdFile" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
    exit 1
}
if (-not (Test-Path $AdminPwdFile)) {
    Write-CustomLog -Message "Chýba súbor $AdminPwdFile" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $AdminLogFile
    exit 1
}

$RootSecurePassword = Import-Clixml $RootPwdFile
$AdminSecurePassword = Import-Clixml $AdminPwdFile

# === GENEROVANIE HESLA PRE SKLAD ===
$ComputerName = $env:COMPUTERNAME
$Suffix = if ($ComputerName.Length -ge 4) {
    $ComputerName.Substring($ComputerName.Length - 4)
}
else {
    $ComputerName
}
$SkladPassword = "Tauris$Suffix"
$SkladSecurePassword = ConvertTo-SecureString $SkladPassword -AsPlainText -Force

# === KONTROLA HESIEL ===
OverHesloAPripadneObnov -Uzivatel $RootUser -SecurePassword $RootSecurePassword -LogSubor $RootLogFile -ZobrazeneMeno "ROOT"
OverHesloAPripadneObnov -Uzivatel $AdminUser -SecurePassword $AdminSecurePassword -LogSubor $AdminLogFile -ZobrazeneMeno "ADMIN"
OverHesloAPripadneObnov -Uzivatel $SkladUser -SecurePassword $SkladSecurePassword -LogSubor $SkladLogFile -ZobrazeneMeno "SKLAD"

# === VYTVORENIE TASKOV ===
Test-TaskExists -TaskName $StartupTaskName -TriggerType "Startup" -Time ""
Test-TaskExists -TaskName $DailyTaskName -TriggerType "Daily" -Time "22:30"

Write-Output "INFO: Skript úspešne dokončený. Pre aplikovanie zmien restartujte počítač."