<# 
.SYNOPSIS
    Skript na odinstalovanie skriptu

.DESCRIPTION
    Odstrani skript, logy a naplanovane ulohy.

.AUTHOR
    Marek

.CREATED
    2025-09-04

.VERSION
    1.0.0

.NOTES
    Logovanie pomocou LogHelper a Write-Output
#>

$ScriptFolder = "C:\TaurisIT\skript"
$LogFolder = "C:\TaurisIT\Log"
$ScriptFile = "SetPassword.ps1"
$InstallFile = "install.ps1"
$ScriptPath = Join-Path $ScriptFolder $ScriptFile
$InstallPath = Join-Path $ScriptFolder $InstallFile
$LogFile = Join-Path $LogFolder "InstallLog.txt"
$StartupTaskName = "PasswordCheckStartup"
$DailyTaskName = "PasswordCheckDaily"
$EventSource = "MOP Password Install"
$EventLogName = "Application"

# Import LogHelper modulu, ak je dostupny
Import-Module LogHelper -ErrorAction SilentlyContinue

function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "Information"
    )

    Write-Output "$Type - $Message"

    if (Get-Command -Name Write-CustomLog -ErrorAction SilentlyContinue) {
        Write-CustomLog -Message $Message -Type $Type -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
    }
    else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogFile -Value "$timestamp [$Type] $Message"
    }
}

# Odstranenie skriptov
foreach ($file in @($ScriptPath, $InstallPath)) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Log -Message "Odstraneny subor: $file"
    }
    else {
        Write-Log -Message "Subor neexistuje: $file"
    }
}

# Odstranenie prazdnych priecinkov
foreach ($folder in @($ScriptFolder, $LogFolder)) {
    if (Test-Path $folder -and !(Get-ChildItem $folder)) {
        Remove-Item $folder -Force
        Write-Log -Message "Odstraneny prazdny priecinok: $folder"
    }
    else {
        Write-Log -Message "Priecinok neexistuje alebo nie je prazdny: $folder"
    }
}

# Odstranenie naplanovanych uloh
foreach ($task in @($StartupTaskName, $DailyTaskName)) {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
        Write-Log -Message "Odstranena naplanovana uloha: $task"
    }
    else {
        Write-Log -Message "Naplanovana uloha neexistuje: $task"
    }
}

Write-Log -Message "Odinstalacia dokoncena"