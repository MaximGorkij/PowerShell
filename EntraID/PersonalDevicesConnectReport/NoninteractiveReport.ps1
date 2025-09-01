# === Nastavenie premenných ===
$tenantId     = "ebf9edb5-a5f7-4d70-9a59-501865f222ee"
$clientId     = "5fedee17-9a32-4856-992e-d5db97596721"
$clientSecret = "fxG8Q~Aj3uB9c14dJcpobSzyGv6Xaslh5DvpicI."

$inputCsv     = "PersonalDevices.csv"
$outputCsv    = "nonInteractiveSignIns.csv"
$logFile      = "nonInteractiveSignIns_log.txt"

# === Funkcia na logovanie ===
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

# === Získanie access tokenu ===
Write-Log "Získavanie access tokenu..."
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
try {
    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
    $accessToken = $tokenResponse.access_token
    $headers = @{ Authorization = "Bearer $accessToken" }
    Write-Log "Access token získaný úspešne."
    Write-Host "Access token: $accessToken"
} catch {
    Write-Log "CHYBA: Nepodarilo sa získať token. $_"
    exit
}

# === Načítanie emailov z CSV ===
try {
    $users = Import-Csv -Path $inputCsv
    Write-Log "Načítaných používateľov: $($users.Count)"
    $users | Format-Table
} catch {
    Write-Log "CHYBA: Nepodarilo sa načítať CSV. $_"
    exit
}

# === Inicializácia výstupného CSV ===
"UserPrincipalName,IPAddress,AppDisplayName,Status,TimeGenerated,SignInEventTypes" | Out-File -FilePath $outputCsv -Encoding UTF8

# === Spracovanie každého používateľa ===
foreach ($user in $users) {
    $email = $user.userPrincipalName
    Write-Log "Spracovávam: $email"

    # Použitie beta endpointu
    $uri = "https://graph.microsoft.com/beta/auditLogs/signIns?\$filter=userPrincipalName eq '$email'"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        if ($response.value.Count -eq 0) {
            Write-Log "Žiadne prihlásenia pre $email."
        } else {
            foreach ($entry in $response.value) {
                # Filtrovanie na non-interactive sign-ins
                if ($entry.signInEventTypes -contains "nonInteractive") {
                    $eventTypes = $entry.signInEventTypes -join "|"
                    $line = "$($entry.userPrincipalName),$($entry.ipAddress),$($entry.appDisplayName),$($entry.status.errorCode),$($entry.createdDateTime),$eventTypes"
                    Add-Content -Path $outputCsv -Value $line
                }
            }
            Write-Log "Záznamy pre $email spracované."
        }
    } catch {
        Write-Log "CHYBA pri spracovaní $email : $_"
    }
}

Write-Log "✅ Skript dokončený."