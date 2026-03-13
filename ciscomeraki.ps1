#Requires -Version 5.1
# ==============================================================================
# Get-MerakiNetworkGroups.ps1
# Stiahne Meraki network IDs a rozdeli ich do skupin pre Zabbix hosts
# ==============================================================================

# --- Vstupné údaje ---
$ApiKey     = "f400c6efe4f78cc923c02c7230bfb9c295dfef8c"
$OrgId      = "619244948763443878"
$GroupCount = 3

$BaseUrl = "https://api.meraki.com/api/v1"
$Headers = @{ "X-Cisco-Meraki-API-Key" = $ApiKey }

# ==============================================================================
# Stiahnutie sietí z Meraki API
# ==============================================================================
try {
    $Response = Invoke-RestMethod -Uri "$BaseUrl/organizations/$OrgId/networks" `
        -Headers $Headers -Method Get -ErrorAction Stop
}
catch {
    Write-Error "Chyba pri volaní Meraki API: $_"
    exit 1
}

$Networks = $Response | Select-Object id, name, productTypes
Write-Host "Nájdených sietí: $($Networks.Count)" -ForegroundColor Cyan

# ==============================================================================
# Rozdelenie do skupin (round-robin)
# ==============================================================================
$Groups = @{}
for ($i = 1; $i -le $GroupCount; $i++) {
    $Groups["Group_$i"] = [System.Collections.Generic.List[object]]::new()
}

$Index = 0
foreach ($Net in $Networks) {
    $GroupKey = "Group_$(($Index % $GroupCount) + 1)"
    $Groups[$GroupKey].Add($Net)
    $Index++
}

# ==============================================================================
# Výstup – Zabbix makrá per skupina
# ==============================================================================
Write-Host "`n========== ZABBIX HOST KONFIGURÁCIA ==========" -ForegroundColor Cyan

foreach ($GroupKey in ($Groups.Keys | Sort-Object)) {
    $NetList = $Groups[$GroupKey]
    $IdList  = ($NetList | ForEach-Object { $_.id }) -join ","

    Write-Host "`n[ $GroupKey ]" -ForegroundColor Yellow
    Write-Host "  Zabbix Host Name : Meraki_$GroupKey"
    Write-Host "  Makro {`$MERAKI_NETWORK_IDS} : $IdList"
    Write-Host "  Siete:"
    foreach ($Net in $NetList) {
        Write-Host "    - $($Net.name) [$($Net.id)] ($($Net.productTypes -join ', '))"
    }
}

# ==============================================================================
# Export do CSV
# ==============================================================================
$CsvPath = "$PSScriptRoot\MerakiGroups_Output.csv"
$ExportRows = foreach ($GroupKey in $Groups.Keys) {
    foreach ($Net in $Groups[$GroupKey]) {
        [PSCustomObject]@{
            ZabbixHost  = "Meraki_$GroupKey"
            NetworkName = $Net.name
            NetworkId   = $Net.id
            Types       = ($Net.productTypes -join ", ")
        }
    }
}
$ExportRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

Write-Host "`nCSV export: $CsvPath" -ForegroundColor Green