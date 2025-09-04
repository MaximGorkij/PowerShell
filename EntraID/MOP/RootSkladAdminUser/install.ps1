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
    1.0.0

.NOTES
    .
#>

$ScriptPath = "C:\TaurisIT\skript\SetPassword.ps1"
$LogDir = "C:\TaurisIT\Log"

# Vytvorenie adresára pre modul
if (-not (Test-Path $ScriptPath)) {
    New-Item -Path $ScriptPath -ItemType Directory -Force
}

# Skopírovanie modulu
Copy-Item -Path ".\SetPassword.ps1" -Destination $ScriptPath -Force

# Vytvorenie adresára pre logy
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force
}