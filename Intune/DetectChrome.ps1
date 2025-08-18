$chromeFound = $false

$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($path in $paths) {
    Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        if ($props.DisplayName -like "*Google Chrome*") {
            $chromeFound = $true
        }
    }
}

if ($chromeFound) {
    Write-Output "Google Chrome found"
    exit 1
} else {
    Write-Output "Google Chrome not found"
    exit 0
}
