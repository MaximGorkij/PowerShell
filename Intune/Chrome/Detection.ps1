<# 
.SYNOPSIS
    Inteligentna detekcia cesty Chrome
.NOTES
    Vypisuje len cistu cestu pre Intune CSV report.
    Pouziva modul: LogHelper
#>

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogFileName = "C:\TaurisIT\Log\detectchrome.log"
$EventSource = "ChromeDetection"

if (Test-Path $ModulePath) { Import-Module $ModulePath -Force }

# Funkcia na zapis do vasho logu
function Write-InternalLog {
    param([string]$Message, [string]$Type = "Information")
    Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFileName -Type $Type
}

$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$Apps = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Google Chrome*" }

if ($Apps) {
    $FinalPath = ""
    $App = $Apps[0] # Zoberieme prvy nalez
    
    if ($App.InstallLocation) {
        $FinalPath = $App.InstallLocation
    }
    else {
        # Skusime manualne overit typicke cesty ak register mlci
        $StandardPaths = @(
            "C:\Program Files\Google\Chrome\Application",
            "C:\Program Files (x86)\Google\Chrome\Application",
            "$env:LOCALAPPDATA\Google\Chrome\Application"
        )
        foreach ($P in $StandardPaths) {
            if (Test-Path "$P\chrome.exe") {
                $FinalPath = $P
                break
            }
        }
    }

    if ([string]::IsNullOrEmpty($FinalPath)) {
        $FinalPath = "Cesta nenajdena ani na disku"
    }

    # Zapiseme do vasho suboru detail
    Write-InternalLog "Detegovany Chrome. Cesta: $FinalPath" "Warning"
    
    # DO KONZOLY (CSV) POSLEME LEN CISTU CESTU
    Write-Output $FinalPath
    
    exit 1
}
else {
    exit 0
}