
# Skript pre Intune – spúšťa sa na zariadení

$User = $env:USERNAME
$DeviceName = $env:COMPUTERNAME
$OS = (Get-WmiObject Win32_OperatingSystem).Caption
$OSVersion = (Get-WmiObject Win32_OperatingSystem).Version
$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"

$log = [PSCustomObject]@{
    Timestamp        = $Timestamp
    DeviceName       = $DeviceName
    User             = $User
    OperatingSystem  = $OS
    OSVersion        = $OSVersion
}

# Zapíše do lokálneho log súboru
#$logPath = "C:\ProgramData\Company\InventoryLog.csv"
$logPath = "\\NAS03\log\KeRybaInventuraIT\InventoryLog-$User-$Timestamp.csv"
if (!(Test-Path (Split-Path $logPath))) {
    New-Item -Path (Split-Path $logPath) -ItemType Directory -Force
}

$log | Export-Csv -Path $logPath -Append -NoTypeInformation -Encoding UTF8
