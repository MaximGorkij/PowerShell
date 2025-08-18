param (
    [switch]$DryRun,
    [string]$ExportPath
)

# ===============================
# SCCM Client Removal Script for PowerShell 5.1
# Author: Copilot for Marek
# ===============================

# --- CONFIG ---
$source    = "SCCMRemediation"
$logName   = "Application"
$eventId   = 1001
$logFile   = "$env:windir\Temp\SCCMRemoval.log"

# Ensure ExportPath ends with .csv
if ($ExportPath) {
    if (-not $ExportPath.EndsWith(".csv")) {
        $ExportPath += ".csv"
    }
    $csvExport = $ExportPath
} else {
    $csvExport = "$env:windir\Temp\SCCMRemoval.csv"
}

# Ensure export folder exists
$exportFolder = Split-Path $csvExport
if (-not (Test-Path $exportFolder)) {
    New-Item -Path $exportFolder -ItemType Directory -Force | Out-Null
}

# --- FUNCTIONS ---
function Register-EventSource {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName $logName -Source $source
        }
    } catch {
        Write-FileLog ("Failed to create Event Log source: {0}" -f $_)
    }
}

function Write-FileLog {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

function Write-Log {
    param (
        [string]$message,
        [string]$entryType = "Information"
    )
    try {
        Write-EventLog -LogName $logName -Source $source -EntryType $entryType -EventId $eventId -Message $message
    } catch {
        Write-FileLog ("Event Log write failed: {0}" -f $_)
    }
    Write-FileLog $message
    Write-Output $message
}

function Get-SCCMVersion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\CCM\Setup"
    try {
        $version = Get-ItemProperty -Path $regPath -Name "Version" -ErrorAction SilentlyContinue
        if ($version -and $version.Version) {
            return $version.Version
        } else {
            return "Unknown"
        }
    } catch {
        Write-Log ("Failed to read SCCM version from registry: {0}" -f $_) "Warning"
        return "Unknown"
    }
}

function IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- MAIN ---
try {
    if (-not (IsAdmin)) {
        Write-Log "This script must be run as Administrator." "Error"
        exit 1
    }

    Register-EventSource

    if ($DryRun) {
        Write-Log "Starting SCCM client removal simulation (DryRun mode)..."
    } else {
        Write-Log "Starting SCCM client removal process..."
    }

    $clientFolder  = "C:\Windows\CCM"
    $clientService = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
    $ccmUninstall  = "C:\Windows\CCMSetup\CCMSetup.exe"
    $wmiCheck      = Get-WmiObject -Namespace "root\ccm" -List -ErrorAction SilentlyContinue
    $regExists     = Test-Path "HKLM:\SOFTWARE\Microsoft\CCM"

    $detected = $false
    if (Test-Path $clientFolder) { $detected = $true }
    if ($clientService)          { $detected = $true }
    if ($wmiCheck)               { $detected = $true }
    if ($regExists)              { $detected = $true }

    $version = Get-SCCMVersion
    $os      = (Get-CimInstance Win32_OperatingSystem).Caption
    $psver   = $PSVersionTable.PSVersion.ToString()

    if ($detected) {
        Write-Log ("SCCM client detected. Version: {0}" -f $version)

        if ($clientService -and $clientService.Status -eq "Running") {
            if ($DryRun) {
                Write-Log "DryRun: Would stop SCCM service."
            } else {
                Stop-Service -Name "CcmExec" -Force
                Start-Sleep -Seconds 5
                Write-Log "SCCM service stopped."
            }
        }

        if (Test-Path $ccmUninstall) {
            if ($DryRun) {
                Write-Log "DryRun: Would run CCMSetup.exe /uninstall."
            } else {
                Start-Process -FilePath $ccmUninstall -ArgumentList "/uninstall" -Wait
                Start-Sleep -Seconds 10
                Write-Log "SCCM client uninstall initiated."
            }
        } else {
            Write-Log "CCMSetup.exe not found - skipping uninstall." "Warning"
        }

        # ✅ DELETE SERVICE
        if ($clientService) {
            if ($DryRun) {
                Write-Log "DryRun: Would delete SCCM service 'CcmExec'."
            } else {
                try {
                    sc.exe delete CcmExec | Out-Null
                    Write-Log "SCCM service 'CcmExec' deleted."
                } catch {
                    Write-Log ("Failed to delete service 'CcmExec': {0}" -f $_) "Warning"
                }
            }
        }

        $paths = @(
            "C:\Windows\CCM",
            "C:\Windows\CCMSetup",
            "C:\Windows\CCMCache"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                if ($DryRun) {
                    Write-Log ("DryRun: Would remove folder {0}" -f $path)
                } else {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log ("Removed folder: {0}" -f $path)
                }
            }
        }

        try {
            $repoStatus = (winmgmt /verifyrepository)
            if ($repoStatus -match "inconsistent") {
                if ($DryRun) {
                    Write-Log "DryRun: Would salvage WMI repository."
                } else {
                    winmgmt /salvagerepository
                    Write-Log "WMI repository was inconsistent - salvaged."
                }
            }
        } catch {
            Write-Log ("WMI repository check failed: {0}" -f $_) "Warning"
        }

        # ✅ STATUS
        if ($DryRun) {
            $status = "DryRun completed - no changes made."
        } else {
            $status = "SCCM client removal completed successfully."
        }
        Write-Log $status

        $export = [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            SCCMVersion  = $version
            PowerShell   = $psver
            OS           = $os
            Time         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Result       = $status
        }

        if (-not (Test-Path $csvExport)) {
            $export | Export-Csv -Path $csvExport -NoTypeInformation
        } else {
            $export | Export-Csv -Path $csvExport -Append -NoTypeInformation
        }

        Write-Log ("Exported result to {0}" -f $csvExport)
        exit 0

    } else {
        Write-Log "No SCCM client detected. Nothing to remove."
        exit 0
    }

} catch {
    Write-Log ("Fatal error in script execution: {0}" -f $_) "Error"
    exit 1
}