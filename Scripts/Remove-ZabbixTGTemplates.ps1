<#
.SYNOPSIS
    Vymazanie Zabbix šablón s prefixom TG_
.DESCRIPTION
    Skript nájde všetky šablóny začínajúce na TG_ a vymaže ich.
    Podporuje DryRun režim pre overenie pred ostrým mazaním.
.PARAMETER DryRun
    Ak $true, skript len vypíše čo by zmazal bez skutočného mazania.
.NOTES
    Verzia: 1.0
    Autor: Automatizácia
    Pozadovane moduly: LogHelper
    Datum vytvorenia: 13.03.2025
    Logovanie: C:\TaurisIT\Log\ZabbixInventory\template_delete.log
#>

param (
    [bool]$DryRun = $true
)

# --- Import LogHelper modulu ---
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
Import-Module $ModulePath -Force

# Konfigurácia logovania
$EventSource = "ZabbixClone"
$LogFileName = "template_delete.log"

# Inicializácia log systému
$LogInit = Initialize-LogSystem -LogDirectory "C:\TaurisIT\Log\ZabbixInventory" `
    -EventSource $EventSource -EventLogName "IntuneScript"

if (-not $LogInit) {
    Write-Error "Nepodarilo sa inicializovať logovací systém."
    exit
}

# --- Načítanie .env súboru ---
$EnvFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
        $Parts = $_.Split('=', 2)
        $Key = $Parts[0].Trim()
        $Value = $Parts[1].Trim()
        Set-Variable -Name $Key -Value $Value -Scope Script
    }
}
else {
    Write-CustomLog -Message "Súbor .env nebol nájdený v adresári $PSScriptRoot" `
        -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
    exit
}

$ZabbixUrl = $ZABBIX_URL
$ApiToken = $ZABBIX_API

if (-not $ZabbixUrl -or -not $ApiToken) {
    Write-CustomLog -Message "Chýbajúce údaje v .env súbore (ZABBIX_URL alebo ZABBIX_API)" `
        -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
    exit
}

# --- Funkcia pre volanie Zabbix API ---
function Invoke-ZabbixApi {
    param (
        [string]$Method,
        [hashtable]$Params
    )

    $Body = @{
        jsonrpc = "2.0"
        method  = $Method
        params  = $Params
        id      = 1
    } | ConvertTo-Json -Depth 10

    try {
        return Invoke-RestMethod -Uri $ZabbixUrl -Method Post `
            -Headers @{ Authorization = "Bearer $ApiToken" } `
            -ContentType "application/json" -Body $Body
    }
    catch {
        Write-CustomLog -Message "Chyba API volania ($Method): $($_.Exception.Message)" `
            -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
        return $null
    }
}

# --- Štart ---
$StatusMsg = if ($DryRun) { "VYKONÁVA SA LEN TEST (DryRun)" } else { "OSTRÝ REŽIM" }
Write-CustomLog -Message "Štart mazania TG_ šablón. Režim: $StatusMsg" `
    -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'

# Nájdi šablóny začínajúce na TG_
$TemplatesRequest = Invoke-ZabbixApi -Method "template.get" -Params @{
    output                 = @("templateid", "host", "name")
    search                 = @{ host = "TG_" }
    startSearch            = $true
    searchWildcardsEnabled = $false
}

if ($null -eq $TemplatesRequest) {
    Write-CustomLog -Message "Nepodarilo sa načítať šablóny zo Zabbix API." `
        -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
    exit
}

$TemplatesToDelete = $TemplatesRequest.result
Write-Host "Nájdených TG_ šablón na zmazanie: $($TemplatesToDelete.Count)" -ForegroundColor Cyan
Write-CustomLog -Message "Nájdených TG_ šablón na zmazanie: $($TemplatesToDelete.Count)" `
    -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'

if ($TemplatesToDelete.Count -eq 0) {
    Write-Host "Žiadne TG_ šablóny nenájdené." -ForegroundColor Yellow
    exit
}

# Vypíš čo bude zmazané
$TemplatesToDelete | ForEach-Object {
    Write-Host "  - $($_.name)" -ForegroundColor Gray
}

$CountSuccess = 0
$CountError = 0

foreach ($Template in $TemplatesToDelete) {
    if ($DryRun) {
        Write-Host "[DryRun] Plánujem zmazať: $($Template.name)" -ForegroundColor Gray
        continue
    }

    $Delete = Invoke-ZabbixApi -Method "template.delete" -Params @($Template.templateid)

    if ($null -ne $Delete -and $Delete.result.templateids.Count -gt 0) {
        Write-Host "[OK] Zmazané: $($Template.name)" -ForegroundColor Green
        Write-CustomLog -Message "Šablóna $($Template.name) úspešne zmazaná." `
            -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'
        $CountSuccess++
    }
    else {
        $ApiError = $Delete.error | ConvertTo-Json -Compress
        Write-CustomLog -Message "Chyba pri mazaní $($Template.name) - API: $ApiError" `
            -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
        $CountError++
    }
}

# Záverečný súhrn
if (-not $DryRun) {
    $Summary = "Dokončené – Zmazané: $CountSuccess | Chyby: $CountError"
    Write-CustomLog -Message $Summary -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'
    Write-Host "`n$Summary" -ForegroundColor Cyan
}

Write-Host "Log: C:\TaurisIT\Log\ZabbixInventory\$LogFileName" -ForegroundColor Green