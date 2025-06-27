# Názov počítača
$computerName = $env:COMPUTERNAME

# Timestamp vo formáte yyyyMMdd_HHmmss
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"

# Cieľová UNC cesta (ZMEŇ podľa seba, napr. \\server\share\logs)
$uncRoot = "\\nas03\LOG\ListSW"

# Kompletná cesta pre export
$csvPath = Join-Path -Path $uncRoot -ChildPath "${computerName}_WMI_vs_Registry_${timestamp}.csv"

# Ak výstupný priečinok neexistuje, vytvoriť (ak máš práva)
$csvFolder = Split-Path -Path $csvPath
if (-not (Test-Path -Path $csvFolder)) {
    New-Item -Path $csvFolder -ItemType Directory -Force | Out-Null
}

# Získanie zoznamu aplikácií z WMI (POZOR na re-konfiguráciu MSI)
$wmiApps = Get-WmiObject -Class Win32_Product | Select-Object -ExpandProperty Name
$wmiApps = $wmiApps | Sort-Object -Unique

# Získanie zoznamu aplikácií z Registry
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$regApps = Get-ItemProperty $regPaths | Where-Object { $_.DisplayName } |
           Select-Object -ExpandProperty DisplayName
$regApps = $regApps | Sort-Object -Unique

# Porovnanie
$comparison = Compare-Object -ReferenceObject $regApps -DifferenceObject $wmiApps -IncludeEqual -PassThru |
              Select-Object @{Name="AppName";Expression={$_}}, SideIndicator

# Overenie existencie adresára aplikácie (nepresné, voliteľné)
$comparison = $comparison | ForEach-Object {
    $exists = (Test-Path "C:\Program Files\$($_.AppName)") -or (Test-Path "C:\Program Files (x86)\$($_.AppName)")
    $_ | Add-Member -MemberType NoteProperty -Name "ExistsOnDisk" -Value $exists
    $_
}

# Export do CSV na UNC share
$comparison | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Výsledok bol uložený do: $csvPath"
