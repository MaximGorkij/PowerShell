<#
.SYNOPSIS
    Detection: Skontroluje, či extensionAttribute1 obsahuje správnu lokáciu podľa aktuálnej IP
#>

Import-Module LogHelper -ErrorAction SilentlyContinue

$LogDir = "C:\TaurisIT\Log\IPcheck"
$LogFile = "IPcheck.log"
$EventSource = "IPLocationRemediation"

if (Test-Path "C:\Program Files\WindowsPowerShell\Modules\LogHelper") {
    Initialize-LogSystem -LogDirectory $LogDir -EventSource $EventSource -RetentionDays 30
    Write-IntuneLog -Message "Detection script spustený" -Level INFO -LogFile $LogFile
}
else {
    Write-Output "LogHelper modul chýba"
}

try {
    # Načítaj JSON mapu – musí byť súčasťou balíčka (uploadneš ju spolu so skriptami)
    $jsonPath = "$PSScriptRoot\IPLocationMap.json"
    if (-not (Test-Path $jsonPath)) { throw "IPLocationMap.json nenájdený" }
    $ipMap = Get-Content $jsonPath -Raw | ConvertFrom-Json -AsHashtable

    # Získaj aktuálnu IP (10.x rozsah)
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -match '^10\.' -and $_.InterfaceOperationalStatus -eq 'Up' } |
        Select-Object -First 1 -ExpandProperty IPAddress)

    if (-not $ip) { throw "Žiadna interná 10.x IP nenájdená" }

    # Najdlhší prefix match
    $location = $null
    $longest = ""
    foreach ($prefix in $ipMap.Keys) {
        if ($ip.StartsWith($prefix) -and $prefix.Length -gt $longest.Length) {
            $longest = $prefix
            $location = $ipMap[$prefix]
        }
    }

    if (-not $location) { throw "Žiadna lokácia pre IP $ip" }

    # Graph autentifikácia (nahraď hodnoty !!!)
    $clientId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    $tenantId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    $clientSecret = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    $body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $clientId
        client_secret = $clientSecret
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body -ContentType "application/x-www-form-urlencoded"
    $token = $tokenResponse.access_token

    Connect-MgGraph -AccessToken $token -NoWelcome

    # Aktuálne meno zariadenia
    $deviceName = $env:COMPUTERNAME
    $device = Get-MgDevice -Filter "displayName eq '$deviceName'" -All -ErrorAction Stop
    if (-not $device) { throw "Zariadenie $deviceName nenájdené v Entra ID" }

    $currentExt = $device.OnPremisesExtensionAttributes.ExtensionAttribute1

    if ($currentExt -eq $location) {
        Write-IntuneLog -Message "OK – extensionAttribute1 = $location (IP: $ip)" -Level INFO -LogFile $LogFile
        Write-Output "Compliant – lokácia už nastavená"
        exit 0
    }
    else {
        Write-IntuneLog -Message "Nesprávna hodnota: $currentExt | Malo by byť: $location (IP: $ip)" -Level WARN -LogFile $LogFile
        Write-Output "Non-compliant – extensionAttribute1 = $currentExt, malo by byť $location"
        exit 1
    }

}
catch {
    Write-IntuneLog -Message "Detection chyba: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Write-Output "Chyba: $($_.Exception.Message)"
    exit 1
}