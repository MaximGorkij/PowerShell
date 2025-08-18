$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

if (Test-Path $pwshPath) {
    try {
        # Nastaví asociáciu .ps1 na PowerShell 7 cez CMD
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c assoc .ps1=Microsoft.PowerShellScript.1" -Verb RunAs -WindowStyle Hidden
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c ftype Microsoft.PowerShellScript.1=`"$pwshPath`" `"%1`" %*" -Verb RunAs -WindowStyle Hidden
        Write-Output "✅ Asociácia .ps1 nastavená na PowerShell 7"
    } catch {
        Write-Error "❌ Chyba pri nastavovaní asociácie: $_"
    }
} else {
    Write-Output "⚠️ PowerShell 7 nie je nainštalovaný. Skript preskočený."
}