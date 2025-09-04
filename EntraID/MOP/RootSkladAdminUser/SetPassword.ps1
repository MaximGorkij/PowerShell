<#
.SYNOPSIS
    Skript na kontrolu a zmenu hesla pouzivatelov root, admin a sklad pre MOP PC

.DESCRIPTION
    Overenie a obnova hesla pre pouzivatelov "root", "admin" a "sklad" na MOP pocitacoch

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-04

.VERSION
    1.4.0

.NOTES
    Pouziva Start-Process na overenie hesla
#>

# === PARAMETRE ===
$ScriptFolder = "C:\TaurisIT\skript"
$LogFolder = "C:\TaurisIT\Log"
$RootLogFile = "$LogFolder\PasswordRoot.log"
$SkladLogFile = "$LogFolder\PasswordSklad.log"
$RootUser = "root"
$RootPlainPassword = "TvojeNemenneHeslo123!"
$AdminUser = "admin"
$AdminPlainPassword = "DRUFhijac1"
$SkladUser = "sklad"
$ScriptPath = "$ScriptFolder\SetPasswords.ps1"
$StartupTaskName = "PasswordCheckStartup"
$DailyTaskName = "PasswordCheckDaily"
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Change"

# === IMPORT MODULU ===
Import-Module LogHelper -ErrorAction SilentlyContinue

# === FUNKCIA: TEST PRIHLASENIA CEZ Start-Process ===
function Test-Login {
    param (
        [System.Management.Automation.PSCredential]$Credential
    )
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command `"exit`"" -Credential $Credential -WindowStyle Hidden -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# === FUNKCIA: OVERENIE A PRIPADNA OBNOVA HESLA ===
function OverHesloAPripadneObnov {
    param (
        [string]$Uzivatel,
        [string]$Heslo,
        [string]$LogSubor,
        [string]$ZobrazeneMeno = $Uzivatel
    )

    $SecurePassword = ConvertTo-SecureString $Heslo -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ($Uzivatel, $SecurePassword)

    if (Test-Login -Credential $Credential) {
        Write-CustomLog -Message "$ZobrazeneMeno - Heslo je platne" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "Information $ZobrazeneMeno Heslo je platne"
    }
    else {
        $msg = "$ZobrazeneMeno - Heslo je neplatne. Obnovujem"
        Write-CustomLog -Message $msg -Type "Warning" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "Warning $ZobrazeneMeno Heslo je neplatne. Obnovujem"

        # Zápis do systémového Event Logu
        if (-not (Get-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction SilentlyContinue)) {
            New-EventLog -LogName $EventLogName -Source $EventSource
        }
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType Warning -EventId 2001 -Message $msg

        if ($Uzivatel -eq "sklad") {
            Set-LocalUser -Name $Uzivatel -Password $SecurePassword
        }
        else {
            net user $Uzivatel $Heslo
        }

        Write-CustomLog -Message "$ZobrazeneMeno - Heslo bolo obnovene" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogSubor
        Write-Output "Information $ZobrazeneMeno Heslo bolo obnovene"
    }
}

# === VYTVORENIE PRIECINKOV ===
if (-not (Test-Path $ScriptFolder)) {
    New-Item -Path $ScriptFolder -ItemType Directory -Force | Out-Null
    Write-CustomLog -Message "Vytvoreny priecinok $ScriptFolder" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
    Write-Output "Information Vytvoreny priecinok $ScriptFolder"
}
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    Write-CustomLog -Message "Vytvoreny priecinok $LogFolder" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
    Write-Output "Information Vytvoreny priecinok $LogFolder"
}

# === GENEROVANIE HESLA PRE SKLAD ===
$ComputerName = $env:COMPUTERNAME
$Suffix = $ComputerName.Substring($ComputerName.Length - 4)
$SkladPassword = "Tauris$Suffix"

# === KONTROLA HESIEL ===
OverHesloAPripadneObnov -Uzivatel $RootUser -Heslo $RootPlainPassword -LogSubor $RootLogFile -ZobrazeneMeno "ROOT"
OverHesloAPripadneObnov -Uzivatel $AdminUser -Heslo $AdminPlainPassword -LogSubor $RootLogFile -ZobrazeneMeno "ADMIN"
OverHesloAPripadneObnov -Uzivatel $SkladUser -Heslo $SkladPassword -LogSubor $SkladLogFile -ZobrazeneMeno "SKLAD"

# === VYTVORENIE SCHEDULED TASKOV ===
function Test-TaskExists {
    param (
        [string]$TaskName,
        [string]$TriggerType,
        [string]$Time
    )

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $existingTask) {
        Write-CustomLog -Message "TASK $TaskName sa vytvara" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
        Write-Output "Information TASK $TaskName sa vytvara"

        $Action = New-ScheduledTaskAction -Execute $pwshPath -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        $Trigger = if ($TriggerType -eq "Startup") {
            New-ScheduledTaskTrigger -AtStartup
        }
        elseif ($TriggerType -eq "Daily") {
            New-ScheduledTaskTrigger -Daily -At $Time
        }

        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -ErrorAction Stop
        Write-CustomLog -Message "TASK $TaskName bol uspesne vytvoreny" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
        Write-Output "Information TASK $TaskName bol uspesne vytvoreny"
    }
    else {
        Write-CustomLog -Message "TASK $TaskName uz existuje" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $RootLogFile
        Write-Output "Information TASK $TaskName uz existuje"
    }
}

Test-TaskExists -TaskName $StartupTaskName -TriggerType "Startup" -Time ""
Test-TaskExists -TaskName $DailyTaskName -TriggerType "Daily" -Time "22:30"