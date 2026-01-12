# Cesta k log súboru
$LogPath = "C:\Skripty\ExportIntuneLogs\Epson2255U_update.log"
$ProjectorIP = "10.60.17.220"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Funkcia na logovanie
function Write-Log {
    param([string]$Message)
    Add-Content -Path $LogPath -Value "$Timestamp`t$Message"
}

# Ping test
Write-Log "=== Test Epson EB-2255U WebControl ==="
Write-Log "Ping test to $ProjectorIP..."
$ping = Test-Connection -ComputerName $ProjectorIP -Count 2 -Quiet
if ($ping) {
    Write-Log "Ping OK"
}
else {
    Write-Log "Ping FAILED"
    exit 1
}

# HTTP test
Write-Log "HTTP test to http://$ProjectorIP..."
try {
    $response = Invoke-WebRequest -Uri "http://$ProjectorIP" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Log "HTTP OK - Status 200"
    }
    else {
        Write-Log "HTTP response: $($response.StatusCode)"
    }
}
catch {
    Write-Log "HTTP FAILED - $($_.Exception.Message)"
}

# Kontrola obsahu
if ($response.Content -match "plug-in isn't supported") {
    Write-Log "WebControl obsahuje nekompatibilný plug-in - pravdepodobne ActiveX"
    Write-Log "Odporúčanie: Použiť Internet Explorer alebo Edge v IE režime"
}

Write-Log "=== Test dokončený ===`n"