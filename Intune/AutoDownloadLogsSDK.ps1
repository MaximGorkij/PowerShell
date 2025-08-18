# Ciel: Použije Graph SDK na login a volá beta endpoint cez Invoke-MgGraphRequest

# Nastavenie priečinkov
$logFolder = "IntuneDeviceLogs"
$csvFile = "$logFolder\DownloadResults.csv"
$logFile = "$logFolder\IntuneLogDownloader.log"
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

# Logovacia funkcia
function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Type] $Message"
    $entry | Out-File -FilePath $logFile -Append -Encoding utf8
    if ($Type -eq "ERROR") {
        Write-Host $entry -ForegroundColor Red
    } elseif ($Type -eq "WARNING") {
        Write-Host $entry -ForegroundColor Yellow
    } else {
        Write-Host $entry
    }
}

# Kontrola modulu
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Log "Inštalujem Microsoft.Graph modul..." "INFO"
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
}

# Prihlásenie
Write-Log "Prihlasovanie do Microsoft Graph..." "INFO"
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"

# Vykonanie beta dotazu cez Invoke-MgGraphRequest
try {
    Write-Log "Získavam diagnostické požiadavky z beta endpointu..." "INFO"
    $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceDiagnostics"

    if (-not $response.value) {
        Write-Log "Žiadne zariadenia so zberom logov sa nenašli." "WARNING"
        return
    }
} catch {
    Write-Log "Chyba pri volaní Graph API: $_" "ERROR"
    return
}

# Spracovanie záznamov
$results = @()

foreach ($entry in $response.value | Where-Object { $_.status -eq "completed" }) {
    $deviceId = $entry.managedDeviceId
    $user     = $entry.userPrincipalName -replace '@','_'
    $url      = $entry.diagnosticZipDownloadLink
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = "$logFolder\$deviceId-$user-$timestamp.zip"

    if ($url) {
        try {
            Write-Log "Sťahujem logy pre $user ($deviceId)..." "INFO"
            Invoke-WebRequest -Uri $url -OutFile $fileName -ErrorAction Stop
            Write-Log "Stiahnuté: $fileName" "INFO"

            $results += [PSCustomObject]@{
                DeviceID = $deviceId
                User     = $user
                Status   = "OK"
                File     = $fileName
            }
        } catch {
            Write-Log "Chyba pri sťahovaní pre $user ($deviceId): $_" "ERROR"
            $results += [PSCustomObject]@{
                DeviceID = $deviceId
                User     = $user
                Status   = "DownloadError"
                File     = $fileName
            }
        }
    } else {
        Write-Log "Zariadenie $user ($deviceId) nemá ZIP odkaz." "WARNING"
        $results += [PSCustomObject]@{
            DeviceID = $deviceId
            User     = $user
            Status   = "NoDownloadLink"
            File     = ""
        }
    }
}

# Export do CSV
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Log "Výsledky exportované do CSV: $csvFile" "INFO"
}
