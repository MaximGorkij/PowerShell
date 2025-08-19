# Možné cesty k PowerShell 7
$paths = @(
    "C:\Program Files\PowerShell\7\pwsh.exe",
    "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\pwsh.exe",
    "C:\Program Files\WindowsApps\Microsoft.PowerShell_*\pwsh.exe",
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
)

# Nájde prvú existujúcu cestu
$pwshPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($pwshPath) {
    try {
        # Nastaví asociáciu .ps1 na PowerShell 7 cez CMD
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c assoc .ps1=Microsoft.PowerShellScript.1" -Verb RunAs -WindowStyle Hidden
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c ftype Microsoft.PowerShellScript.1=`"$pwshPath`" `"%1`" %*" -Verb RunAs -WindowStyle Hidden
        Write-Output "✅ PowerShell 7 detekovaný v: $pwshPath"
        Write-Output "✅ Asociácia .ps1 nastavená na PowerShell 7"
    } catch {
        Write-Error "❌ Chyba pri nastavovaní asociácie: $_"
    }
} else {
    Write-Output "⚠️ PowerShell 7 nebol nájdený v žiadnej známej ceste."
}