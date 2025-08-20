param (
    [switch]$TestMode = $false  # Set to $true for testing
)

# Define custom event log and source
$logName = "IntuneAppInstall"
$sourceName = "IntuneAppInstaller"

# Define app and task details
$AppName = "PDF Architect 9"
$TaskName = "RetryUninstallPDFArchitect9"
$ScriptPath = $MyInvocation.MyCommand.Path

# Registry paths to search for uninstall string
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Create event log if it doesn't exist
if (-not $TestMode -and -not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        New-EventLog -LogName $logName -Source $sourceName
        Write-Output "✅ Event Log '$logName' with source '$sourceName' created."
    } catch {
        Write-Output "❌ Failed to create Event Log: $($_.Exception.Message)"
        exit 1
    }
}

# Logging function
function Write-IntuneLog {
    param (
        [string]$Message,
        [string]$EntryType = "Information",
        [int]$EventId = 1000
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $fullMessage = "$timestamp | $Message"

    if ($TestMode) {
        Write-Output "[TEST MODE] $fullMessage"
    } else {
        try {
            Write-EventLog -LogName $logName -Source $sourceName -EntryType $EntryType -EventId $EventId -Message $fullMessage
        } catch {
            Write-Output "❌ Logging error: $($_.Exception.Message)"
        }
    }
}

# Find uninstall string
function FindUninstallString {
    foreach ($path in $uninstallKeyPaths) {
        $apps = Get-ChildItem $path -ErrorAction SilentlyContinue
        foreach ($app in $apps) {
            $props = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -like "*$AppName*") {
                return $props.UninstallString
            }
        }
    }
    return $null
}

# Create scheduled task
function CreateScheduledTask {
    Write-IntuneLog "Creating Scheduled Task: $TaskName" "Information" 1005
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(5)) `
        -RepetitionInterval (New-TimeSpan -Minutes 30) `
        -RepetitionDuration (New-TimeSpan -Days 1)
    try {
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName `
            -Description "Repeated uninstallation of PDF Architect 9" -User "SYSTEM" -RunLevel Highest -Force
    } catch {
        Write-IntuneLog "Error creating Scheduled Task: $($_.Exception.Message)" "Error" 1006
    }
}

# Remove scheduled task
function RemoveScheduledTask {
    Write-IntuneLog "Removing Scheduled Task: $TaskName" "Information" 1007
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
        Write-IntuneLog "Error removing Scheduled Task: $($_.Exception.Message)" "Error" 1008
    }
}

# === Main Execution ===
Write-IntuneLog "=== PDF Architect 9 Uninstall Script Started ===" "Information" 1001
Write-IntuneLog "Test Mode: $TestMode" "Information" 1002

$uninstallString = FindUninstallString

if ($uninstallString) {
    Write-IntuneLog "Uninstall command found: $uninstallString" "Information" 1003

    if ($TestMode) {
        Write-IntuneLog "TEST MODE - Uninstallation skipped." "Warning" 1004
    } else {
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /VERYSILENT /NORESTART`"" -Wait
            Write-IntuneLog "Uninstallation completed successfully." "Information" 1005
        } catch {
            Write-IntuneLog "Error during uninstallation: $($_.Exception.Message)" "Error" 1009
        }
    }

    Start-Sleep -Seconds 10

    if (FindUninstallString) {
        Write-IntuneLog "App still present — scheduling retry." "Warning" 1010
        CreateScheduledTask
    } else {
        Write-IntuneLog "App successfully removed — cleaning up task." "Information" 1011
        RemoveScheduledTask
    }
} else {
    Write-IntuneLog "Application '$AppName' is not installed." "Information" 1012
    RemoveScheduledTask
}

Write-IntuneLog "=== PDF Architect 9 Uninstall Script completed ===" "Information" 1013