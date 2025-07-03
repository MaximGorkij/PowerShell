$networkDrives = Get-WmiObject -Class Win32_MappedLogicalDisk

foreach ($drive in $networkDrives) {
    $driveLetter = $drive.DeviceID
    $networkPath = $drive.ProviderName
    New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $networkPath -Persist
}
