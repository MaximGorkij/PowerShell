# AutoDownload-IntuneLogs-Interactive.ps1

# Priečinky a súbory
$logFolder = "IntuneDeviceLogs"
$csvFile   = "$logFolder\DownloadResults.csv"
$logFile   = "$logFolder\IntuneLogDownloader.log"

# Vytvor priečinok pre logy
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

# Funkcia pre logovanie
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

# Kontrola a inštalácia modulu
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Log "Inštalujem Microsoft.Graph modul..." "INFO"
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
}

# Prihlásenie
Write-Log "Prihlasujem sa cez Microsoft Graph..." "INFO"
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceManagementConfiguration.Read.All" -ErrorAction Stop

# Získanie prístupového tokenu z kontextu
$context = Get-MgContext
$accessToken = $context.AccessToken
if (-not $accessToken) {
    Write-Log "Access token nebol získaný." "ERROR"
    return
}

# Získanie diagnostických údajov
try {
    $diagUri = "https://graph.microsoft.com/beta/deviceManagement/deviceDiagnostics"
    $response = Invoke-RestMethod -Uri $diagUri -Headers @{ Authorization = "Bearer $accessToken" } -ErrorAction Stop
    if (-not $response.value) {
        Write-Log "Žiadne zariadenia so zberom logov sa nenašli." "WARNING"
        return
    }
} catch {
    Write-Log "Chyba pri načítaní diagnostických údajov: $_" "ERROR"
    return
}

# Príprava CSV exportu
$results = @()

# Spracovanie zariadení
foreach ($entry in $response.value | Where-Object { $_.status -eq "completed" }) {
    $deviceId  = $entry.managedDeviceId
    $user      = $entry.userPrincipalName -replace '@','_'
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName  = "$logFolder\$deviceId-$user-$timestamp.zip"
    $zipUrl    = $entry.diagnosticZipDownloadLink

    if ($zipUrl) {
        try {
            Write-Log "Sťahujem logy pre $user ($deviceId)..." "INFO"
            Invoke-WebRequest -Uri $zipUrl -OutFile $fileName -ErrorAction Stop
            $results += [PSCustomObject]@{
                DeviceID = $deviceId
                User     = $user
                Status   = "OK"
                File     = $fileName
            }
            Write-Log "Logy úspešne stiahnuté: $fileName" "INFO"
        } catch {
            $results += [PSCustomObject]@{
                DeviceID = $deviceId
                User     = $user
                Status   = "Failed"
                File     = $fileName
            }
            Write-Log "Chyba pri sťahovaní pre $user ($deviceId): $_" "ERROR"
        }
    } else {
        Write-Log "Logy pre $user ($deviceId) nie sú dostupné na stiahnutie." "WARNING"
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
    Write-Log "Výsledky exportované do: $csvFile" "INFO"
} else {
    Write-Log "Žiadne položky na export." "WARNING"
}
