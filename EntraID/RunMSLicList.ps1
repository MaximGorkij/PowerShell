<#
.SYNOPSIS
    Spustenie skriptu MSLicList.ps1 pod pouzivatelom Tauris\adminfindrik

.DESCRIPTION
    Skript spusti cielovy skript MSLicList.ps1 ako iny pouzivatel, odchyti chyby a zapise ich do logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-17

.VERSION
    1.1

.NOTES
    Skript predpoklada, ze MSLicList.ps1 sa nachadza v rovnakom adresari.
    Log subor sa vytvara automaticky pri chybe.
#>

# Zistenie adresara skriptu
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDirectory) {
    $scriptDirectory = Get-Location
}

# Cesta k cielovemu skriptu
$scriptPath = Join-Path $scriptDirectory 'MSLicList.ps1'

# Cesta k log suboru
$logPath = Join-Path $scriptDirectory 'MSLicList_ErrorLog.txt'

# Funkcia na zapis chyb do logu
function Write-ErrorLog {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "$timestamp - CHYBA - $Message"
}

# Prihlasovacie udaje
$domainUser = 'Tauris\adminfindrik'
$securePassword = Read-Host "Zadaj heslo pre $domainUser" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($domainUser, $securePassword)

# Vypis cesty pre kontrolu
Write-Host "Spustam skript: $scriptPath" -ForegroundColor Cyan

# Argumenty pre spustenie
$arguments = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    $scriptPath
)

Write-Output "-ArgumentList $arguments -Credential $cred -Wait"

# Pokus o spustenie skriptu
try {
    Start-Process powershell.exe -ArgumentList $arguments -Credential $cred -Wait
}
catch {
    Write-ErrorLog "Chyba pri spusteni skriptu: $($_.Exception.Message)"
    Write-Host "Spustenie zlyhalo. Podrobnosti su v logu: $logPath" -ForegroundColor Red
}