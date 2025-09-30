<#
.SYNONOPSIS
    Instalacny skript pre Password Management system MOP - Intune Package
.DESCRIPTION
    Nakopiruje skripty, vytvori potrebne adresare, nastavi opravnenia
    a vytvori scheduled task pre spustanie kazdy den okrem nedele o 5:30
    Optimalizovany pre nasadenie cez Microsoft Intune
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-25
.VERSION
    2.3 
.NOTES
    Spusta sa automaticky s SYSTEM pravami v Intune kontexte
    Vytvori task schedule: Pondelok-Sobota o 5:30
    Loguje do konzoly, suboru a event logu
#>


$ErrorActionPreference = "Stop"
$targetPath = "C:\TaurisIT\skript\ChangePassword"
$scriptName = "SetPassword.ps1"
$logFileName = "C:\TaurisIT\Log\Install_SetPassword.txt"
$eventSource = "SetPassword_Install"

# Import logovacieho modulu
Import-Module LogHelper -Force

try {
    Write-CustomLog -Message "=== START INSTALACIE ===" -EventSource $eventSource -LogFileName $logFileName -Type Information
    Write-CustomLog -Message "Cielovy priecinok: $targetPath" -EventSource $eventSource -LogFileName $logFileName -Type Information

    # Vytvorenie cieľového priečinka
    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        Write-CustomLog -Message "Cielovy priecinok vytvoreny: $targetPath" -EventSource $eventSource -LogFileName $logFileName -Type Information
    }
    else {
        Write-CustomLog -Message "Cielovy priecinok uz existuje: $targetPath" -EventSource $eventSource -LogFileName $logFileName -Type Information
    }

    # Skopírovanie SetPassword.ps1
    $sourcePath = Join-Path $PSScriptRoot $scriptName
    $destinationPath = Join-Path $targetPath $scriptName

    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force
        Write-CustomLog -Message "Skript $scriptName uspesne skopirovany do $destinationPath" -EventSource $eventSource -LogFileName $logFileName -Type Information
    }
    else {
        Write-CustomLog -Message "Zdrojovy skript nenajdeny: $sourcePath" -EventSource $eventSource -LogFileName $logFileName -Type Error
        throw "Zdrojovy skript nenajdeny"
    }

    # Overenie inštalácie
    if (Test-Path $destinationPath) {
        Write-CustomLog -Message "Overenie: Skript uspesne nainstalovany" -EventSource $eventSource -LogFileName $logFileName -Type Information
    }
    else {
        Write-CustomLog -Message "Skript sa nepodarilo nainstalovat" -EventSource $eventSource -LogFileName $logFileName -Type Error
        throw "Instalacia zlyhala"
    }

    # Vytvorenie Scheduled Task
    $taskName = "TaurisIT_SetPassword"
    $taskDescription = "Denné spustanie SetPassword.ps1 o 5:30 ráno"
    $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$destinationPath`""
    $taskTrigger = New-ScheduledTaskTrigger -Daily -At "05:30"
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    try {
        # Odstránenie existujúcej úlohy ak existuje
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-CustomLog -Message "Existujuca Scheduled Task '$taskName' bola odstranena" -EventSource $eventSource -LogFileName $logFileName -Type Information
        }

        # Vytvorenie novej úlohy
        Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings | Out-Null
        Write-CustomLog -Message "Scheduled Task '$taskName' uspesne vytvorena (denne o 5:30)" -EventSource $eventSource -LogFileName $logFileName -Type Information
    }
    catch {
        Write-CustomLog -Message "ERROR pri vytvarani Scheduled Task: $($_.Exception.Message)" -EventSource $eventSource -LogFileName $logFileName -Type Error
        throw "Vytvorenie Scheduled Task zlyhalo"
    }

    Write-CustomLog -Message "=== INSTALACIA UKONCENA USPESNE ===" -EventSource $eventSource -LogFileName $logFileName -Type Information
    exit 0

}
catch {
    Write-CustomLog -Message "CRITICAL ERROR: $($_.Exception.Message)" -EventSource $eventSource -LogFileName $logFileName -Type Error
    Write-CustomLog -Message "=== INSTALACIA ZLYHALA ===" -EventSource $eventSource -LogFileName $logFileName -Type Error
    exit 1
}