param (
    [switch]$DryRun,
    [string]$ExportPath = "$env:windir\Temp\SCCMRemovalResult.csv"
)

# --- CONFIG ---
$source = "SCCMRemediation"
$logName = "Application"
$eventId = 1001
$logFile = "$env:windir\Temp\SCCMRemoval.log"

# --- PRE-CLEANUP ---
if (-not $DryRun.IsPresent -and (Test-Path $logFile)) {
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
}

# --- FUNCTIONS ---
function Test-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Log "Script must be run as Administrator." "Error"
        exit 1
    }
}

function Register-EventSource {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName $logName -Source $source
        }
    } catch {
        Write-FileLog "Failed to create Event Log source: $_"
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
        [ValidateSet("Information", "Warning", "Error")]
        [string]$entryType = "Information"
    )
    try {
        Write-EventLog -LogName $logName -Source $source -EntryType $entryType -EventId $eventId -Message $message
    } catch {
        Write-FileLog "Event Log write failed: $_"
    }
    Write-FileLog $message
    Write-Output $message
}

function Get-SCCMVersion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\CCM\Setup"
    try {
        $version = Get-ItemProperty -Path $regPath -Name "Version" -ErrorAction Stop
        return $version.Version
    } catch {
        Write-Log "Failed to read SCCM version from registry: $_" "Warning"
        return "Unknown"
    }
}

function Test-SCCMClientInstalled {
    $ccmFolder = Test-Path "C:\Windows\CCM"
    $ccmService = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
    $wmiClient = $false
    try {
        Get-WmiObject -Namespace "root\ccm" -Class SMS_Client -ErrorAction Stop | Out-Null
        $wmiClient = $true
    } catch {}
    return ($ccmFolder -or $ccmService -or $wmiClient)
}

function Export-Result {
    param (
        [string]$Status,
        [string]$Version
    )
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $obj = [PSCustomObject]@{
        Hostname = $hostname
        Timestamp = $timestamp
        SCCMVersion = $Version
        Status = $Status
    }
    $obj | Export-Csv -Path $ExportPath -Append -NoTypeInformation -Force
}

# --- MAIN ---
try {
    Test-Admin
    Register-EventSource
    Write-Log "Running on OS: $([System.Environment]::OSVersion.VersionString), PowerShell version: $($PSVersionTable.PSVersion)"

    if ($DryRun) {
        Write-Log "Starting SCCM client removal simulation (DryRun mode)..."
    } else {
        Write-Log "Starting SCCM client removal process..."
    }

    if (Test-SCCMClientInstalled) {
        $version = Get-SCCMVersion
        Write-Log "SCCM client detected. Version: $version"

        $ccmExec = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
        $ccmUninstall = "C:\Windows\CCMSetup\CCMSetup.exe"

        # Stop service
        if ($ccmExec -and $ccmExec.Status -eq "Running") {
            if ($DryRun) {
                Write-Log "DryRun: Would stop SCCM service."
            } else {
                Stop-Service -Name "CcmExec" -Force
                Start-Sleep -Seconds 5
                Write-Log "SCCM service stopped."
            }
        }

        # Uninstall
        if (Test-Path $ccmUninstall) {
            if ($DryRun) {
                Write-Log "DryRun: Would run CCMSetup.exe /uninstall."
            } else {
                Start-Process -FilePath $ccmUninstall -ArgumentList "/uninstall" -Wait
                Start-Sleep -Seconds 10
                Write-Log "SCCM client uninstall initiated."

                if (Test-Path "HKLM:\SOFTWARE\Microsoft\CCM") {
                    Write-Log "Warning: SCCM registry keys still exist after uninstall." "Warning"
                }
            }
        } else {
            Write-Log "CCMSetup.exe not found – skipping uninstall." "Warning"
        }

        # Remove folders
        $paths = @(
            "C:\Windows\CCM",
            "C:\Windows\CCMSetup",
            "C:\Windows\CCMCache"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                if ($DryRun) {
                    Write-Log "DryRun: Would remove folder $path"
                } else {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Removed folder: $path"
                }
            }
        }

        # WMI check
        try {
            $repoStatus = (winmgmt /verifyrepository)
            if ($repoStatus -match "inconsistent") {
                if ($DryRun) {
                    Write-Log "DryRun: Would salvage WMI repository."
                } else {
                    winmgmt /salvagerepository
                    Write-Log "WMI repository was inconsistent – salvaged."
                }
            }
        } catch {
            Write-Log "WMI repository check failed: $_" "Warning"
        }

        $status = $DryRun ? "DryRun completed – no changes made." : "SCCM client removal completed successfully."
        Write-Log $status
        Export-Result -Status $status -Version $version
        exit 0
    } else {
        Write-Log "No SCCM client detected. Nothing to remove."
        Export-Result -Status "No SCCM client detected." -Version "N/A"
        exit 0
    }
} catch {
    Write-Log "Fatal error in script execution: $_" "Error"
    Export-Result -Status "Fatal error" -Version "Unknown"
    exit 1
}