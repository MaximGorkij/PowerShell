<#
.SYNOPSIS
    Hromadné klonovanie aktívnych Zabbix šablón s prefixom TG_
.DESCRIPTION
    Skript načíta konfiguráciu z .env, overí existenciu logovacieho priečinka
    (ak neexistuje, vytvorí ho) a následne vykoná klonovanie šablón.
.PARAMETER DryRun
    Ak $true, skript len vypíše plánované akcie bez skutočného klonovania.
.NOTES
    Verzia: 1.6
    Autor: Automatizácia
    Pozadovane moduly: LogHelper
    Datum vytvorenia: 13.03.2025
    Logovanie: C:\TaurisIT\Log\ZabbixInventory\template_cloning.log
    POZOR: EventSource "ZabbixClone" musí byť registrovaný jednorazovo ako Admin:
           New-EventLog -LogName "IntuneScript" -Source "ZabbixClone"
#>

param (
    [bool]$DryRun = $true
)

# --- Import LogHelper modulu ---
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
Import-Module $ModulePath -Force

# Konfigurácia logovania
$EventSource = "ZabbixClone"
$LogFileName = "ZabbixInventory\template_cloning.log"  # relatívna cesta – modul doplní C:\TaurisIT\Log\

# Inicializácia log systému (vytvorí adresár, overí práva, zaregistruje EventSource)
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

# Konfigurácia
$ZabbixUrl = $ZABBIX_URL
$ApiToken = $ZABBIX_API
$ClonePrefix = "TG_"

# Validácia .env hodnôt
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

# --- Štart procesu ---
$StatusMsg = if ($DryRun) { "VYKONÁVA SA LEN TEST (DryRun)" } else { "OSTRÝ REŽIM" }
Write-CustomLog -Message "Štart procesu klonovania. Režim: $StatusMsg" `
    -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'

# 1. Získanie šablón
$TemplatesRequest = Invoke-ZabbixApi -Method "template.get" -Params @{
    output      = @("templateid", "host", "name")
    selectHosts = "count"
}

if ($null -eq $TemplatesRequest) {
    Write-CustomLog -Message "Nepodarilo sa načítať šablóny zo Zabbix API." `
        -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
    exit
}

# Bezpečný prevod hosts na int
$TemplatesToClone = $TemplatesRequest.result | Where-Object {
    $ParsedCount = 0
    [int]::TryParse($_.hosts, [ref]$ParsedCount) -and $ParsedCount -gt 0
}

Write-Host "Nájdených šablón na klonovanie: $($TemplatesToClone.Count)" -ForegroundColor Cyan
Write-CustomLog -Message "Nájdených šablón na klonovanie: $($TemplatesToClone.Count)" `
    -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'

# 2. Cyklus klonovania
foreach ($OldTemplate in $TemplatesToClone) {
    $NewName = $ClonePrefix + $OldTemplate.name
    $NewHost = $ClonePrefix + $OldTemplate.host

    if ($DryRun) {
        Write-Host "[DryRun] Plánujem klon: $($OldTemplate.name) -> $NewName" -ForegroundColor Gray
        continue
    }

    # Ostrý režim: Export -> XML úprava -> Import
    $Export = Invoke-ZabbixApi -Method "configuration.export" -Params @{
        options = @{ templates = @($OldTemplate.templateid) }
        format  = "xml"
    }

    if ($null -eq $Export) { continue }

    if ($null -ne $Export.result) {
        try {
            [xml]$XmlDoc = $Export.result

            # Zmena názvu šablóny cez XML parser – nie string replace
            $TemplateNode = $XmlDoc.SelectSingleNode("//templates/template[name='$($OldTemplate.name)']")
            if ($null -ne $TemplateNode) {
                $TemplateNode.name = $NewName
                $TemplateNode.template = $NewHost
            }

            $XmlData = $XmlDoc.OuterXml
        }
        catch {
            Write-CustomLog -Message "Chyba pri XML spracovaní šablóny $($OldTemplate.name): $($_.Exception.Message)" `
                -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
            continue
        }

        $Import = Invoke-ZabbixApi -Method "configuration.import" -Params @{
            format = "xml"
            source = $XmlData
            rules  = @{
                templates          = @{ createMissing = $true; updateExisting = $false }
                items              = @{ createMissing = $true }
                triggers           = @{ createMissing = $true }
                graphs             = @{ createMissing = $true }
                discoveryRules     = @{ createMissing = $true }
                templateLinkage    = @{ createMissing = $true }
                templateDashboards = @{ createMissing = $true }
                httptests          = @{ createMissing = $true }
                valuemaps          = @{ createMissing = $true }
            }
        }

        if ($null -ne $Import -and $Import.result -eq $true) {
            Write-CustomLog -Message "Klon $NewName úspešne vytvorený." `
                -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'
        }
        else {
            Write-CustomLog -Message "Chyba pri importe $NewName" `
                -EventSource $EventSource -LogFileName $LogFileName -Type 'Error'
        }
    }
}

# Čistenie starých logov
Clear-OldLogs -LogDirectory "C:\TaurisIT\Log\ZabbixInventory"

Write-CustomLog -Message "Operácia dokončená." `
    -EventSource $EventSource -LogFileName $LogFileName -Type 'Information'
Write-Host "`nOperácia dokončená. Log: C:\TaurisIT\Log\$LogFileName" -ForegroundColor Green