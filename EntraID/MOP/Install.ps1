# Premenne
$FolderPath = "C:\TaurisIT\skript"
$ScriptName = "SetPassMOP-v5.ps1"
$ScriptPath = "$FolderPath\$ScriptName"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Install"
$TaskName = "SetPasswordDaily"
$LogFileName = "C:\TaurisIT\log\InstallLog.txt"

# Import modulu LogHelper
Import-Module LogHelper -ErrorAction SilentlyContinue

# Vytvorenie adresara, ak neexistuje
if (-not (Test-Path $FolderPath)) {
    try {
        New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
        Write-CustomLog -Message "Adresar '$FolderPath' bol vytvoreny." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani adresara '$FolderPath': $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
    }
}

# Vytvorenie Event Logu a zdroja, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    try {
        New-EventLog -LogName $EventLogName -Source $EventSource
        Write-CustomLog -Message "Event Log '$EventLogName' a zdroj '$EventSource' boli vytvorene." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani Event Logu: $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
    }
}

# Kopirovanie skriptu
try {
    if (Test-Path $ScriptPath) {
        Write-CustomLog -Message "Skript '$ScriptName' uz existuje v '$FolderPath'. Bude prepisany." -Type "Warning" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
    }

    Copy-Item -Path ".\$ScriptName" -Destination $ScriptPath -Force
    Write-CustomLog -Message "Skript '$ScriptName' bol skopirovany do '$FolderPath'." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
} catch {
    Write-CustomLog -Message "CHYBA pri kopirovani skriptu: $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
}

# Vytvorenie naplanovanej ulohy
try {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -Daily -At "22:30"
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force

    Write-CustomLog -Message "Uloha '$TaskName' bola uspesne vytvorena." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
} catch {
    Write-CustomLog -Message "CHYBA pri vytvarani ulohy '$TaskName': $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFileName
}