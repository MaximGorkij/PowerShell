<# 
.SYNOPSIS
    Skript na odinstalovanie skriptu

.DESCRIPTION
    Odstrani skript, logy a naplanovane ulohy.

.AUTHOR
    Marek

.CREATED
    2025-09-04

.VERSION
    2.3.0

.NOTES
    Logovanie pomocou LogHelper a Write-Output
#>

$ErrorActionPreference = "Stop"
$targetPath = "C:\TaurisIT\skript\ChangePassword"
$scriptName = "SetPassword.ps1"
$logFileName = "C:\TaurisIT\Log\Uninstall_SetPassword.txt"
$eventSource = "SetPassword_Uninstall"

# Import logovacieho modulu
try {
    Import-Module LogHelper -Force
    $moduleLoaded = $true
}
catch {
    $moduleLoaded = $false
}

# Fallback logovanie ak modul nie je dostupný
function Write-FallbackLog {
    param([string]$Message, [string]$Type = "Information")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logDir = Split-Path $logFileName -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    "$timestamp - [$Type] $Message" | Out-File -FilePath $logFileName -Append -Encoding UTF8
    Write-Host "[$Type] $Message"
}

function Write-Log {
    param([string]$Message, [string]$Type = "Information")
    if ($moduleLoaded) {
        Write-CustomLog -Message $Message -EventSource $eventSource -LogFileName $logFileName -Type $Type
    }
    else {
        Write-FallbackLog -Message $Message -Type $Type
    }
}

try {
    Write-Log -Message "=== START ODINSTALACIE ===" -Type Information
    Write-Log -Message "Cielovy priecinok: $targetPath" -Type Information

    # Odstránenie Scheduled Task
    $taskName = "TaurisIT_SetPassword"
    try {
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Log -Message "Scheduled Task '$taskName' uspesne odstranena" -Type Information
        }
        else {
            Write-Log -Message "Scheduled Task '$taskName' nebola najdena" -Type Warning
        }
    }
    catch {
        Write-Log -Message "ERROR pri odstranovani Scheduled Task: $($_.Exception.Message)" -Type Error
    }

    $scriptPath = Join-Path $targetPath $scriptName

    # Odstránenie SetPassword.ps1
    if (Test-Path $scriptPath) {
        Remove-Item -Path $scriptPath -Force
        Write-Log -Message "Skript $scriptName uspesne odstraneny z $targetPath" -Type Information
    }
    else {
        Write-Log -Message "Skript $scriptName nebol najdeny v $targetPath" -Type Warning
    }

    # Odstránenie priečinka ChangePassword ak je prázdny
    if (Test-Path $targetPath) {
        $items = Get-ChildItem -Path $targetPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $items -or $items.Count -eq 0) {
            Remove-Item -Path $targetPath -Force -Recurse
            Write-Log -Message "Prazdny priecinok odstraneny: $targetPath" -Type Information
        }
        else {
            Write-Log -Message "Priecinok $targetPath obsahuje dalsie subory ($($items.Count)), ponechany" -Type Information
        }
    }

    # Odstránenie priečinka skript ak je prázdny
    $scriptFolder = "C:\TaurisIT\skript"
    if (Test-Path $scriptFolder) {
        $items = Get-ChildItem -Path $scriptFolder -Force -ErrorAction SilentlyContinue
        if ($null -eq $items -or $items.Count -eq 0) {
            Remove-Item -Path $scriptFolder -Force -Recurse
            Write-Log -Message "Prazdny priecinok odstraneny: $scriptFolder" -Type Information
        }
        else {
            Write-Log -Message "Priecinok $scriptFolder obsahuje dalsie subory ($($items.Count)), ponechany" -Type Information
        }
    }

    # Kontrola hlavného priečinka TaurisIT
    $rootFolder = "C:\TaurisIT"
    if (Test-Path $rootFolder) {
        $items = Get-ChildItem -Path $rootFolder -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "Log" }
        if ($null -eq $items -or $items.Count -eq 0) {
            Write-Log -Message "Hlavny priecinok $rootFolder je prazdny (okrem Log priecinka)" -Type Information
        }
        else {
            Write-Log -Message "Hlavny priecinok $rootFolder obsahuje dalsie subory ($($items.Count)), ponechany" -Type Information
        }
    }

    Write-Log -Message "=== ODINASTALACIA UKONCENA USPESNE ===" -Type Information
    exit 0

}
catch {
    Write-Log -Message "CRITICAL ERROR: $($_.Exception.Message)" -Type Error
    Write-Log -Message "Stack Trace: $($_.ScriptStackTrace)" -Type Error
    Write-Log -Message "=== ODINASTALACIA ZLYHALA ===" -Type Error
    exit 1
}