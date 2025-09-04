# ===============================
# Skript na zmenu asociacie .ps1 na PowerShell 7
# Autor: Marek Findrik
# Datum: 2025-09-03
# ===============================

# Cesty k moznej instalacii PowerShell 7
$paths = @(
    "C:\Program Files\PowerShell\7\pwsh.exe",
    "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\pwsh.exe",
    "C:\Program Files\WindowsApps\Microsoft.PowerShell_*\pwsh.exe",
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
)

# Parametre pre logovanie
$eventSource = "PWSH AssociationScript"
$eventLogName = "IntuneScript"
$logFileName = "SetPS.log"

# Import modulu LogHelper ak je dostupny
$logHelperAvailable = Get-Module -ListAvailable -Name LogHelper
if ($logHelperAvailable) {
    Import-Module LogHelper -ErrorAction SilentlyContinue
}

# Detekcia PowerShell 7
$pwshPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($pwshPath) {
    try {
        # Nastavenie asociacie cez CMD
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c assoc .ps1=Microsoft.PowerShellScript.1" -Verb RunAs -WindowStyle Hidden
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c ftype Microsoft.PowerShellScript.1=`"$pwshPath`" `"%1`" %*" -Verb RunAs -WindowStyle Hidden

        $msg1 = "PowerShell 7 detekovany v: $pwshPath"
        $msg2 = "Asociacia .ps1 bola nastavena na PowerShell 7"

        Write-Output $msg1
        Write-Output $msg2

        Write-CustomLog -Message $msg1 -EventSource $eventSource -EventLogName $eventLogName -LogFileName $logFileName -Type "Information"
        Write-CustomLog -Message $msg2 -EventSource $eventSource -EventLogName $eventLogName -LogFileName $logFileName -Type "Information"
    } catch {
        $errMsg = "Chyba pri nastavovani asociacie: $_"
        Write-Error $errMsg
        Write-CustomLog -Message $errMsg -EventSource $eventSource -EventLogName $eventLogName -LogFileName $logFileName -Type "Error"
    }
} else {
    $warnMsg = "PowerShell 7 nebol najdeny v ziadnej znamej ceste."
    Write-Output $warnMsg
    Write-CustomLog -Message $warnMsg -EventSource $eventSource -EventLogName $eventLogName -LogFileName $logFileName -Type "Warning"
}