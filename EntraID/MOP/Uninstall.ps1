# Premenne
$TaskName = "SetPasswordDaily"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Uninstall"
$LogFileName = "C:\TaurisIT\log\UninstallLog.txt"

# Import modulu LogHelper
Import-Module LogHelper -ErrorAction SilentlyContinue

# Vytvorenie Event Logu a zdroja, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    try {
        New-EventLog -LogName $EventLogName -Source $EventSource
        Write-CustomLog -Message "Event Log '$EventLogName' a zdroj '$EventSource' boli vytvorene." `
                        -EventSource $EventSource `
                        -EventLogName $EventLogName `
                        -LogFileName $LogFileName
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani Event Logu: $_" `
                        -Type "Error" `
                        -EventSource $EventSource `
                        -EventLogName $EventLogName `
                        -LogFileName $LogFileName
    }
}

# Odstranenie naplanovanej ulohy
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-CustomLog -Message "Uloha '$TaskName' bola uspesne odstranena." `
                    -EventSource $EventSource `
                    -EventLogName $EventLogName `
                    -LogFileName $LogFileName
} catch {
    Write-CustomLog -Message "CHYBA pri odstranovani ulohy '$TaskName': $_" `
                    -Type "Error" `
                    -EventSource $EventSource `
                    -EventLogName $EventLogName `
                    -LogFileName $LogFileName
}