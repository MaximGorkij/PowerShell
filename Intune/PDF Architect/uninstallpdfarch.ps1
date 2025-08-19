param (
    [switch]$TestMode = $false  # Set to $true for testing
)

function Write-IntuneLog {
    param ([string]$Message)
    Write-Output $Message
}

$AppName = "PDF Architect 9"
$TaskName = "RetryUninstallPDFArchitect9"
$ScriptPath = $MyInvocation.MyCommand.Path
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

function FindUninstallString {
    foreach ($path in $uninstallKeyPaths) {
        $apps = Get-ChildItem $path
        foreach ($app in $apps) {
            $props = Get-ItemProperty $app.PSPath
            if ($props.DisplayName -like "*$AppName*") {
                return $props.UninstallString
            }
        }
    }
    return $null
}

function CreateScheduledTask {
    Write-IntuneLog "Vytváram Scheduled Task: $TaskName"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
        -RepetitionInterval (New-TimeSpan -Minutes 30) `
        -RepetitionDuration (New-TimeSpan -Days 1)
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description "Opakovana odinstalacia PDF Architect 9" -User "SYSTEM" -RunLevel Highest
}

function RemoveScheduledTask {
    Write-IntuneLog "Odstraňujem Scheduled Task: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

Write-IntuneLog "=== PDF Architect 9 Uninstall Script Started ==="
Write-IntuneLog "Test Mode: $TestMode"

$uninstallString = FindUninstallString

if ($uninstallString) {
    Write-IntuneLog "Najdeny odinstalacny prikaz: $uninstallString"

    if ($TestMode) {
        Write-IntuneLog "TEST MODE - Odinstalacia preskocena."
    } else {
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /VERYSILENT /NORESTART`"" -Wait
            Write-IntuneLog "Odinstalacia prebehla uspesne."
        } catch {
            Write-IntuneLog "Chyba pocas odinstalacie: $_"
        }
    }

    Start-Sleep -Seconds 10
    if (FindUninstallString) {
        CreateScheduledTask
    } else {
        RemoveScheduledTask
    }
} else {
    Write-IntuneLog "Aplikacia '$AppName' nie je nainstalovana."
    RemoveScheduledTask
}

Write-IntuneLog "=== Skript dokonceny ==="