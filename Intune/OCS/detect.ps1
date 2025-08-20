# === Logging setup ===
$computerName = $env:COMPUTERNAME
$logFolder = "\\nas03\log\OCSInventory"
$logFile = "$logFolder\OCSDetection_$computerName.log"

if (!(Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force
}
if (!(Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force | Out-Null
}
if (!(Test-Path $logFile)) {
    $logFolder = "C:\Log"
    $logFile = "$logFolder\OCSDetection_$computerName.log"
}
    function Write-Log {
    param ([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $msg"
}

# === Event Log setup ===
$eventLogName = "IntuneScript"
$eventSource = "OCSDetection"

if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    New-EventLog -LogName $eventLogName -Source $eventSource
}

function Write-EventLogEntry {
    param (
        [string]$message,
        [string]$entryType = "Information",
        [int]$eventId = 5000
    )
    Write-EventLog -LogName $eventLogName -Source $eventSource -EntryType $entryType -EventId $eventId -Message $message
}

# === Detection logic ===
$reg = "0"
$path = "C:\Program Files (x86)\OCS Inventory Agent\OCSInventory.exe"

if (Test-Path $path) {
    try {
        $versionObj = Get-WmiObject -Class Win32_Product | Where-Object { $_.Vendor -like "OCS*" }
        if ($versionObj) {
            $reg = $versionObj.Version
            Write-Log "OCS Inventory detected. Version: $reg"
            Write-EventLogEntry "OCS Inventory detected. Version: $reg" "Information" 5001
        }
    } catch {
        Write-Log "ERROR retrieving OCS Inventory version - $_"
        Write-EventLogEntry "ERROR retrieving OCS Inventory version - $_" "Error" 9009
    }
} else {
    Write-Log "OCSInventory.exe not found at expected path"
    Write-EventLogEntry "OCSInventory.exe not found at expected path" "Information" 5002
}

Write-Host $reg

# === Decision logic ===
if (($reg -ne "2.11.0.1") -and ($reg -ne "0")) {
    Write-Host "je tu je, zmazat - $reg"
    Write-Log "OCS Inventory version $reg requires remediation"
    Write-EventLogEntry "OCS Inventory version $reg requires remediation" "Warning" 5003
    exit 1
}

Write-Log "OCS Inventory not present or version is acceptable ($reg)"
Write-EventLogEntry "OCS Inventory not present or version is acceptable ($reg)" "Information" 5004
exit 0