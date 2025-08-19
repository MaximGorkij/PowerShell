param (
    [switch]$TestMode
)

# Nastavenie názvu logu a zdroja
$logName = "IntuneAppInstall"
$sourceName = "IntuneAppInstaller"

# Vytvorenie Event Logu, ak ešte neexistuje (len ak nie je TestMode)
if (-not $TestMode -and -not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        New-EventLog -LogName $logName -Source $sourceName
        Write-Output "✅ Vytvorený Event Log: $logName so zdrojom: $sourceName"
    } catch {
        Write-Output "❌ Chyba pri vytváraní Event Logu: $($_.Exception.Message)"
        exit 1
    }
}

# Funkcia na zápis do logu alebo konzoly podľa režimu
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
            Write-Output "❌ Chyba pri zápise do Event Logu: $($_.Exception.Message)"
        }
    }
}

# ================================
# Odinštalácia aplikácie
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
    Write-IntuneLog "Vytváram Scheduled Task: $TaskName" "Information" 1005

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(5))

    try {
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName `
            -Description "Opakovaná odinštalácia PDF Architect 9" `
            -User "SYSTEM" -RunLevel Highest -Force
    } catch {
        Write-IntuneLog "Chyba pri vytváraní Scheduled Task: $($_.Exception.Message)" "Error" 1006
    }
}

function RemoveScheduledTask {
    Write-IntuneLog "Odstraňujem Scheduled Task: $TaskName" "Information" 1007
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
        Write-IntuneLog "Chyba pri odstraňovaní Scheduled Task: $($_.Exception.Message)" "Error" 1008
    }
}

Write-IntuneLog "=== PDF Architect 9 Uninstall Script Started ===" "Information" 1001
Write-IntuneLog "Test Mode: $TestMode" "Information" 1001

$uninstallString = FindUninstallString

if ($uninstallString) {
    Write-IntuneLog "Nájdený odinštalačný príkaz: $uninstallString" "Information" 1002

    if ($TestMode) {
        Write-IntuneLog "TEST MODE - Odinštalácia preskočená." "Warning" 1003
    } else {
        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /VERYSILENT /NORESTART`"" -Wait
            Write-IntuneLog "Odinštalácia prebehla úspešne." "Information" 1004
        } catch {
            Write-IntuneLog "Chyba počas odinštalácie: $($_.Exception.Message)" "Error" 1009
        }
    }

    Start-Sleep -Seconds 10

    if (FindUninstallString) {
        Write-IntuneLog "Aplikácia stále prítomná - plánujem opakovanie." "Warning" 1010
        CreateScheduledTask
    } else {
        Write-IntuneLog "Aplikácia úspešne odstránená - odstraňujem plánovanú úlohu." "Information" 1011
        RemoveScheduledTask
    }
} else {
    Write-IntuneLog "Aplikácia '$AppName' nie je nainštalovaná." "Information" 1012
    RemoveScheduledTask
}

Write-IntuneLog "=== Skript dokončený ===" "Information" 1013