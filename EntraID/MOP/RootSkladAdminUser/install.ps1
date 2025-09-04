<# 
.SYNOPSIS
    Skript na instalaciu skriptu

.DESCRIPTION
    Nakopiruje skript v pripade, ze neexistuje.

.AUTHOR
    Marek

.CREATED
    2025-09-04

.VERSION
    1.0.1

.NOTES
    Logovanie pomocou LogHelper a Write-Output
#>

$ScriptFolder = "C:\TaurisIT\skript"
$ScriptFile = "SetPassword.ps1"
$ScriptPath = Join-Path $ScriptFolder $ScriptFile
$LogDir = "C:\TaurisIT\Log"
$LogFile = Join-Path $LogDir "InstallLog.txt"
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

# Vytvorenie adresara pre skript
if (-not (Test-Path $ScriptFolder)) {
    New-Item -Path $ScriptFolder -ItemType Directory -Force | Out-Null
    Write-Log -Message "Vytvoreny adresar: $ScriptFolder"
}
else {
    Write-Log -Message "Adresar uz existuje: $ScriptFolder"
}

# Skopirovanie skriptu, ak neexistuje
if (-not (Test-Path $ScriptPath)) {
    try {
        Copy-Item -Path ".\SetPassword.ps1" -Destination $ScriptPath -Force
        Write-Log -Message "Skript SetPassword.ps1 bol nakopirovany do $ScriptFolder"
    }
    catch {
        Write-Log -Message "Chyba pri kopirovani skriptu: $_" -Type "Warning"
    }
}
else {
    Write-Log -Message "Skript uz existuje: $ScriptPath"
}

# Vytvorenie adresara pre logy
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    Write-Log -Message "Vytvoreny adresar pre logy: $LogDir"
}
else {
    Write-Log -Message "Adresar pre logy uz existuje: $LogDir"
}