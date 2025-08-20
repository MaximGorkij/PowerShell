param (
    [switch]$TestMode
)

# Set log name and source
$logName = "IntuneAppInstall"
$sourceName = "IntuneAppInstaller"

# Create Event Log if it doesn't exist (only if not in TestMode)
if (-not $TestMode -and -not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        New-EventLog -LogName $logName -Source $sourceName
        Write-Output "✅ Event Log created: $logName with source: $sourceName"
    } catch {
        Write-Output "❌ Error creating Event Log: $($_.Exception.Message)"
        exit 1
    }
}

# Function to write to log or console depending on mode
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
            Write-Output "❌ Error writing to Event Log: $($_.Exception.Message)"
        }
    }
}

# ================================
# Application Uninstallation
# ================================

$AppName = "PDF Architect 9"
$TaskName = "RetryUninstallPDFArchitect9"
$ScriptPath = $MyInvocation.MyCommand.Path

$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

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

function CreateScheduledTask {
    Write-IntuneLog "Creating Scheduled Task: $TaskName" "Information" 1005

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(5))

    try {
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName `
            -Description "Retry uninstall of PDF Architect 9" `
            -User "SYSTEM" -RunLevel Highest -Force
    } catch {
        Write-IntuneLog "Error creating Scheduled Task: $($_.Exception.Message)" "Error" 1006
    }
}

function RemoveScheduledTask {
    Write-IntuneLog "Removing Scheduled Task: $TaskName" "Information" 1007
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
        Write-IntuneLog "Error removing Scheduled Task: $($_.Exception.Message)" "Error" 1008
    }
}

Write-IntuneLog "=== PDF Architect 9 Uninstall Script Started ===" "Information" 1001
Write-IntuneLog "Test Mode: $TestMode" "Information" 1001

$uninstallString = FindUninstallString

if ($uninstallString) {
    Write-IntuneLog "Found uninstall command: $uninstallString" "Information" 1002

    if ($TestMode) {
        Write-IntuneLog "TEST MODE - Uninstallation skipped." "Warning" 1003
    } else {
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /VERYSILENT /NORESTART`"" -Wait
            Write-IntuneLog "Uninstallation completed successfully." "Information" 1004
        } catch {
            Write-IntuneLog "Error during uninstallation: $($_.Exception.Message)" "Error" 1009
        }
    }

    Start-Sleep -Seconds 10

    if (FindUninstallString) {
        Write-IntuneLog "Application still present - scheduling retry." "Warning" 1010
        CreateScheduledTask
    } else {
        Write-IntuneLog "Application successfully removed - deleting scheduled task." "Information" 1011
        RemoveScheduledTask
    }
} else {
    Write-IntuneLog "Application '$AppName' is not installed." "Information" 1012
    RemoveScheduledTask
}

Write-IntuneLog "=== Script completed Uninstall PDF Architect ===" "Information" 1013