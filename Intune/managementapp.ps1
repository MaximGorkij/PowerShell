# ==== NAČÍTANIE KONFIGURÁCIE ====
$configPath = ".\config.json"
if (-Not (Test-Path $configPath)) {
    Write-Host "❌ Konfiguračný súbor 'config.json' neexistuje. Ukončujem skript."
    exit
}
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$tenantId = $config.tenantId
$clientId = $config.clientId
$clientSecret = $config.clientSecret
$scope = "https://graph.microsoft.com/.default"
$jsonFilePath = "intune_apps_backup.json"

# ==== ZÍSKANIE TOKENU ====
function Get-AccessToken {
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = $scope
    }
    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
    return $tokenResponse.access_token
}

# ==== EXPORT APLIKÁCIÍ ====
function Export-IntuneApps {
    $accessToken = Get-AccessToken
    $headers = @{ Authorization = "Bearer $accessToken" }
    $uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    $response.value | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFilePath -Encoding utf8
    Write-Host "✅ Export dokončený. Súbor: $jsonFilePath"
}

# ==== IMPORT APLIKÁCIÍ ====
function Import-IntuneApps {
    $accessToken = Get-AccessToken
    $headers = @{
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $appList = Get-Content -Raw -Path $jsonFilePath | ConvertFrom-Json

    foreach ($app in $appList) {
        $app.PSObject.Properties.Remove("id")
        $app.PSObject.Properties.Remove("createdDateTime")
        $app.PSObject.Properties.Remove("lastModifiedDateTime")
        $app.PSObject.Properties.Remove("publisherState")

        $appJson = $app | ConvertTo-Json -Depth 10
        $uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $appJson
        Write-Host "📦 Importovaná aplikácia: $($response.displayName)"
    }
    Write-Host "✅ Import dokončený."
}

# ==== VOĽBA POUŽÍVATEĽA ====
Write-Host "Vyber operáciu:"
Write-Host "1 - Export aplikácií z Intune"
Write-Host "2 - Import aplikácií do Intune"
$choice = Read-Host "Zadaj číslo (1 alebo 2)"

switch ($choice) {
    "1" { Export-IntuneApps }
    "2" { Import-IntuneApps }
    default { Write-Host "❌ Neplatná voľba. Ukončujem skript." }
}
