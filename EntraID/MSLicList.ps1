<#
.SYNOPSIS
    Export pouzivatelov z Microsoft Entra ID

.DESCRIPTION
    Skript sa spusti interaktivne, pripoji sa k Microsoft Graph,
    ziska pouzivatelov, priradi licencie a datum posledneho prihlasenia,
    ulozi CSV a zapisuje chyby do logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-17

.VERSION
    3.1
#>
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host 'Modul Microsoft.Graph nie je nainstalovany. Instalujem...' -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph

# Zistenie adresara skriptu
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDirectory) {
    $scriptDirectory = Get-Location
}

# Cesta k log suboru
$logPath = Join-Path $scriptDirectory 'Export_ErrorLog.txt'

# Funkcia na zapis chyb do logu
function Write-ErrorLog {
    param ([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "$timestamp - CHYBA - $Message"
}

# Pokus o pripojenie k Microsoft Graph
try {
    Connect-MgGraph -Scopes 'User.Read.All','AuditLog.Read.All','Directory.Read.All'
}
catch {
    Write-ErrorLog "Nepodarilo sa pripojit k Microsoft Graph: $($_.Exception.Message)"
    exit
}

# Pokus o ziskanie pouzivatelov
try {
    $users = Get-MgUser -All
}
catch {
    Write-ErrorLog "Nepodarilo sa nacitat pouzivatelov: $($_.Exception.Message)"
    exit
}

# Priprava vysledkov
$results = @()

foreach ($user in $users) {
    try {
        $licenseDetails = Get-MgUserLicenseDetail -UserId $user.Id
        $licenseSkus = $licenseDetails.SkuPartNumber -join ', '

        $lastSignIn = (Get-MgAuditLogSignIn -Filter "userId eq '$($user.Id)'" -Top 1 | Sort-Object CreatedDateTime -Descending).CreatedDateTime

        $results += [PSCustomObject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Licenses          = $licenseSkus
            LastSignIn        = $lastSignIn
        }
    }
    catch {
        Write-ErrorLog "Chyba pri spracovani pouzivatela $($user.UserPrincipalName): $($_.Exception.Message)"
    }
}

# Export do CSV
try {
    $csvPath = Join-Path $scriptDirectory 'Entra_Users_Export.csv'
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Export dokonceny: $csvPath" -ForegroundColor Cyan
}
catch {
    Write-ErrorLog "Nepodarilo sa exportovat do CSV: $($_.Exception.Message)"
}