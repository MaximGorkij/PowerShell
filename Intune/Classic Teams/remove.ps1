# === Logging setup ===
$computerName = $env:COMPUTERNAME
$logFolder = "\\nas03\log\TeamsVersion"
$logFile = "$logFolder\TeamsRemediation_$computerName.log"

if (!(Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force
}
if (!(Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force | Out-Null
}

function Write-Log {
    param ([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $msg"
}

# === Event Log setup ===
$eventLogName = "IntuneScript"
$eventSource = "TeamsRemediation"

if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    New-EventLog -LogName $eventLogName -Source $eventSource
}

function Write-EventLogEntry {
    param (
        [string]$message,
        [string]$entryType = "Information",
        [int]$eventId = 3000
    )
    Write-EventLog -LogName $eventLogName -Source $eventSource -EntryType $entryType -EventId $eventId -Message $message
}

Write-Log "=== Starting Microsoft Teams Classic removal ==="
Write-EventLogEntry "Starting Microsoft Teams Classic removal" "Information" 1000

# === 1. Remove Teams from user profiles ===
try {
    $users = Get-ChildItem "C:\Users" -Exclude "Public","Default","Default User","All Users"
    foreach ($user in $users) {
        $base = "C:\Users\$($user.Name)\AppData"
        $paths = @(
            "$base\Local\Microsoft\Teams",
            "$base\Roaming\Microsoft\Teams",
            "$base\Local\SquirrelTemp",
            "$base\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Teams.lnk"
        )

        foreach ($p in $paths) {
            if (Test-Path $p) {
                try {
                    Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed: $p"
                    Write-EventLogEntry "Removed: $p" "Information" 3001
                } catch {
                    Write-Log "ERROR removing: $p - $_"
                    Write-EventLogEntry "ERROR removing: $p - $_" "Error" 9001
                }
            }
        }
    }
} catch {
    Write-Log "ERROR processing user profiles - $_"
    Write-EventLogEntry "ERROR processing user profiles - $_" "Error" 9002
}

# === 2. Remove Machine-Wide Installer via WMI ===
try {
    $teamsInstaller = Get-WmiObject -Class Win32_Product | Where-Object {
        $_.Name -like "*Teams*" -and $_.Name -like "*Machine-Wide Installer*"
    }

    if ($teamsInstaller) {
        foreach ($app in $teamsInstaller) {
            try {
                $app.Uninstall() | Out-Null
                Write-Log "Uninstalled via WMI: $($app.Name)"
                Write-EventLogEntry "Uninstalled via WMI: $($app.Name)" "Information" 4001
            } catch {
                Write-Log "ERROR uninstalling via WMI: $($app.Name) - $_"
                Write-EventLogEntry "ERROR uninstalling via WMI: $($app.Name) - $_" "Error" 9003
            }
        }
    } else {
        Write-Log "Machine-Wide Installer not found via WMI"
        Write-EventLogEntry "Machine-Wide Installer not found via WMI" "Information" 4002
    }
} catch {
    Write-Log "ERROR retrieving WMI objects - $_"
    Write-EventLogEntry "ERROR retrieving WMI objects - $_" "Error" 9004
}

# === 3. Alternative uninstall via registry ===
try {
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $regPaths) {
        $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like "*Teams*" -and $_.DisplayName -like "*Machine-Wide Installer*"
        }

        foreach ($app in $apps) {
            $uninstallCmd = $app.UninstallString
            if ($uninstallCmd) {
                try {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCmd /quiet" -Wait
                    Write-Log "Uninstalled via registry: $($app.DisplayName)"
                    Write-EventLogEntry "Uninstalled via registry: $($app.DisplayName)" "Information" 4003
                } catch {
                    Write-Log "ERROR uninstalling via registry: $($app.DisplayName) - $_"
                    Write-EventLogEntry "ERROR uninstalling via registry: $($app.DisplayName) - $_" "Error" 9005
                }
            }
        }
    }
} catch {
    Write-Log "ERROR processing registry uninstall - $_"
    Write-EventLogEntry "ERROR processing registry uninstall - $_" "Error" 9006
}

# === 4. Remove system folders ===
$extraPaths = @(
    "C:\ProgramData\Teams",
    "C:\Program Files (x86)\Teams Installer"
)

foreach ($p in $extraPaths) {
    if (Test-Path $p) {
        try {
            Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
            Write-Log "Removed: $p"
            Write-EventLogEntry "Removed: $p" "Information" 3002
        } catch {
            Write-Log "ERROR removing: $p - $_"
            Write-EventLogEntry "ERROR removing: $p - $_" "Error" 9007
        }
    }
}

# === 5. Remove Teams from Run registry key ===
try {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path "$runKey\Teams") {
        Remove-ItemProperty -Path $runKey -Name "Teams" -ErrorAction Stop
        Write-Log "Removed Teams from Run registry key"
        Write-EventLogEntry "Removed Teams from Run registry key" "Information" 3003
    }
} catch {
    Write-Log "ERROR removing Teams from Run registry - $_"
    Write-EventLogEntry "ERROR removing Teams from Run registry - $_" "Error" 9008
}

Write-Log "=== Microsoft Teams Classic removal completed ==="
Write-EventLogEntry "Microsoft Teams Classic removal completed" "Information" 2000