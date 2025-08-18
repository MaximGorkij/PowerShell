# Skript pre Intune – spúšťa sa na zariadení

#$User = (Get-WmiObject -Class Win32_ComputerSystem).UserName
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
write-host $User
write-host $Timestamp
# Zapíše do lokálneho log súboru (alebo zdieľaného, ak máš pripojený disk)
$logPath = "\\NAS03\log\KeRybaInventuraIT\InventoryLogS-$User-$Timestamp.csv"
#$logPath = "C:\Windows\Temp\InventoryLog-$User-$Timestamp.csv"
if (!(Test-Path (Split-Path $logPath))) {
    New-Item -Path (Split-Path $logPath) -ItemType Directory -Force
}

$log | Export-Csv -Path $logPath -Append -NoTypeInformation -Encoding UTF8
