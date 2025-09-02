# === Logging setup ===
$computerName = $env:COMPUTERNAME
$logFolder = "C:\TaurisIT\Log\OCSInventory"
$logFile = "$logFolder\OCSUninstall_$computerName.log"

if (!(Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force
}
if (!(Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force | Out-Null
}
if (!(Test-Path $logFile)) {
    $logFolder = "C:\TaurisIT\Log"
    $logFile = "$logFolder\OCSUninstall_$computerName.log"
}
$unok = 0

function Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

# === Event Log setup ===
$eventLogName = "IntuneScript"
$eventSource = "OCSUninstall"

if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    New-EventLog -LogName $eventLogName -Source $eventSource
}

function Write-EventLogEntry {
    param (
        [string]$message,
        [string]$entryType = "Information",
        [int]$eventId = 6000
    )
    Write-EventLog -LogName $eventLogName -Source $eventSource -EntryType $entryType -EventId $eventId -Message $message
}

Log "=== OCS Inventory Agent Uninstall Started ==="
Write-EventLogEntry "OCS Inventory Agent Uninstall Started" "Information" 6000

# === Stop service ===
try {
    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Stop-Service -Name 'OCS Inventory Service' -Force
        Log "Service 'OCS Inventory Service' has been stopped."
        Write-EventLogEntry "Service 'OCS Inventory Service' has been stopped." "Information" 6001
    }
} catch {
    Log "ERROR stopping service: $_"
    Write-EventLogEntry "ERROR stopping service: $_" "Error" 9601
}

# === Uninstall via registry ===
try {
    $ocsagent = $null
    if (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent") {
        $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
    } elseif (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent") {
        $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
    }

    if ($ocsagent) {
        Log "Uninstall command: $ocsagent /S"
        Write-EventLogEntry "Uninstall command: $ocsagent /S" "Information" 6002
        Start-Process -FilePath "$ocsagent" -ArgumentList "/S" -Wait
        Log "OCS Agent has been uninstalled."
        Write-EventLogEntry "OCS Agent has been uninstalled." "Information" 6003
        $unok = 1
    } else {
        Log "Uninstall string not found."
        Write-EventLogEntry "Uninstall string not found." "Warning" 9602
    }
} catch {
    Log "ERROR uninstalling agent: $_"
    Write-EventLogEntry "ERROR uninstalling agent: $_" "Error" 9603
}

# === Remove registry keys ===
try {
    $registryPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )

    foreach ($path in $registryPaths) {
        if ((Test-Path -Path $path) -and ($unok -eq 1)) {
            Remove-Item -Path $path -Recurse -Force
            Log "Registry key removed: $path"
            Write-EventLogEntry "Registry key removed: $path" "Information" 6004
        }
    }
} catch {
    Log "ERROR cleaning registry: $_"
    Write-EventLogEntry "ERROR cleaning registry: $_" "Error" 9604
}

# === Remove folders ===
Start-Sleep -Seconds 15
try {
    $paths = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )

    foreach ($path in $paths) {
        if ((Test-Path -Path $path) -and ($unok -eq 1)) {
            Remove-Item -Path $path -Recurse -Force
            Log "Folder removed: $path"
            Write-EventLogEntry "Folder removed: $path" "Information" 6005
        }
    }
} catch {
    Log "ERROR deleting files: $_"
    Write-EventLogEntry "ERROR deleting files: $_" "Error" 9605
}

# === Remove service definition ===
try {
    if (Get-Command Remove-Service -ErrorAction SilentlyContinue) {
        if ((Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) -and ($unok -eq 1)) {
            Remove-Service -Name 'OCS Inventory Service'
            Log "Service 'OCS Inventory Service' has been removed."
            Write-EventLogEntry "Service 'OCS Inventory Service' has been removed." "Information" 6006
        }
    } else {
        Log "Cmdlet 'Remove-Service' not available. Try using 'sc.exe delete'."
        Write-EventLogEntry "Cmdlet 'Remove-Service' not available." "Warning" 9606
    }
} catch {
    Log "ERROR removing service: $_"
    Write-EventLogEntry "ERROR removing service: $_" "Error" 9607
}

# === Final cleanup check ===
try {
    $allClean = $true

    $pathsToCheck = @(
        "C:\Program Files (x86)\OCS Inventory Agent",
        "C:\Program Files\OCS Inventory Agent",
        "C:\ProgramData\OCS Inventory NG"
    )

    $registryPathsToCheck = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"
    )

    foreach ($path in $pathsToCheck) {
        if (Test-Path $path) {
            Log "Check: Remaining folder found: $path"
            Write-EventLogEntry "Check: Remaining folder found: $path" "Warning" 9608
            $allClean = $false
        }
    }

    foreach ($regPath in $registryPathsToCheck) {
        if (Test-Path $regPath) {
            Log "Check: Remaining registry key found: $regPath"
            Write-EventLogEntry "Check: Remaining registry key found: $regPath" "Warning" 9609
            $allClean = $false
        }
    }

    if (Get-Service -Name 'OCS Inventory Service' -ErrorAction SilentlyContinue) {
        Log "Check: Service 'OCS Inventory Service' still exists."
        Write-EventLogEntry "Check: Service 'OCS Inventory Service' still exists." "Warning" 9610
        $allClean = $false
    }

    if ($allClean) {
        Log "Cleanup successful. Waiting 60 seconds before reboot..."
        Write-EventLogEntry "Cleanup successful. System will reboot in 60 seconds." "Information" 6200
        Start-Sleep -Seconds 60
        Restart-Computer -Force
    } else {
        Log "Some components still remain. System reboot canceled."
        Write-EventLogEntry "Some components still remain. System reboot canceled." "Warning" 9611
    }

} catch {
    Log "ERROR during verification or reboot: $_"
    Write-EventLogEntry "ERROR during verification or reboot: $_" "Error" 9612
}

Log "=== OCS Inventory Agent Uninstall Completed ==="
Write-EventLogEntry "OCS Inventory Agent Uninstall Completed" "Information" 6201