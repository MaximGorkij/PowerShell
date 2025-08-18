<#
.SYNOPSIS
Služba na čistenie odpojených SMB súborov s logovaním a email notifikáciou.
#>

param (
    [switch]$InstallService = $false,
    [switch]$AsService = $false
)

# ======= KONFIGURÁCIA =======
$config = @{
    CheckInterval = 300
    LogFile = "C:\ProgramData\SMBFileCleaner\SMBFileCleaner.log"
    MaxLogSize = 5MB
    KeepLogs = 5
    CompressOldLogs = $true
    ServiceName = "SMBFileCleaner"
    DisplayName = "SMB File Cleaner Service"
    Description = "Zatvára odpojené SMB súbory."
}
# =======================================

# Inicializácia log adresára
$logDir = Split-Path $config.LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param ([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $entry = "[$timestamp][$level] $message"
    Add-Content -Path $config.LogFile -Value $entry
    if (-not $AsService) { Write-Host $entry }

    # Rotácia logov
    if ((Get-Item $config.LogFile).Length -gt $config.MaxLogSize) {
        for ($i = $config.KeepLogs; $i -gt 0; $i--) {
            $src = "$($config.LogFile).$i"
            $dst = "$($config.LogFile).$($i + 1)"
            if (Test-Path $src) {
                Move-Item $src $dst -Force
            }
        }
        Move-Item $config.LogFile "$($config.LogFile).1" -Force
        New-Item -ItemType File -Path $config.LogFile -Force | Out-Null
    }

    # Kompresia
    if ($config.CompressOldLogs) {
        Get-ChildItem "$logDir\*.log.*" | Where-Object { $_.Extension -ne ".zip" } | ForEach-Object {
            $zip = "$($_.FullName).zip"
            Compress-Archive -Path $_.FullName -DestinationPath $zip -Force
            Remove-Item $_.FullName
        }
    }
}

function Get-DisconnectedOpenFiles {
    $lines = & openfiles /query /fo csv /s fske21 /v 2>&1 | ConvertFrom-Csv
    $disconnected = $lines | Where-Object { $_.'Accessed By' -like "*Dis*" }
    return $disconnected
}

function Close-OpenFile {
    param ($id)
    try {
        & openfiles /disconnect /s fske21 /id $id | Out-Null
        Write-Log "Zatvorený súbor s ID: $id" "INFO"
    } catch {
        Write-Log "Chyba pri zatváraní súboru ID $id : $_" "ERROR"
    }
}

function Start-Monitor {
    while ($true) {
        Write-Log "Spúšťam kontrolu odpojených súborov..." "INFO"
        $files = Get-DisconnectedOpenFiles
        if ($files.Count -gt 0) {
            Write-Log "Nájdených odpojených súborov: $($files.Count)" "WARNING"
            foreach ($file in $files) {
                Close-OpenFile -id $file.ID
            }
        } else {
            Write-Log "Žiadne odpojené súbory." "INFO"
        }
        Start-Sleep -Seconds $config.CheckInterval
    }
}

function Install-Service {
    $svcPath = "$($MyInvocation.MyCommand.Path) -AsService"
    New-Service -Name $config.ServiceName -BinaryPathName "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$svcPath`"" `
        -DisplayName $config.DisplayName -Description $config.Description -StartupType Automatic
    Write-Log "Služba nainštalovaná: $($config.ServiceName)" "INFO"
}

if ($InstallService) {
    Install-Service
    exit
}

Start-Monitor
