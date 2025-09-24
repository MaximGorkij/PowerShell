#region === Konfiguracia ===
param(
    [string]$ExpectedVersion = "2.11.0.1",
    [string]$ExePath = "C:\Program Files (x86)\OCS Inventory Agent\OCSInventory.exe",
    [string]$LogPath = "C:\TaurisIT\Log"
)

$logFile = Join-Path $LogPath "OCSDetection_$env:COMPUTERNAME.log"

# Vytvor log adresar ak neexistuje
if (-not (Test-Path $LogPath)) {
    try {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    catch {
        # Ticho pokracuj ak sa nepodari vytvorit log
    }
}

# Jednoducha log funkcia pre Win32 app detection
function Write-DetectionLog {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    
    try {
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Ticho pokracuj ak logging zlyha
    }
}

Write-DetectionLog "=== OCS Inventory Detection Start ==="
Write-DetectionLog "Ocakavana verzia: $ExpectedVersion"
#endregion

#region === Detekcia aplikacie ===
$detectedVersion = $null
$appInstalled = $false

# Metoda 1: Kontrola executable suboru
if (Test-Path $ExePath) {
    $appInstalled = $true
    Write-DetectionLog "OCS Inventory exe najdeny: $ExePath"
    
    try {
        $fileVersion = (Get-ItemProperty $ExePath).VersionInfo.FileVersion
        if ($fileVersion) {
            $detectedVersion = $fileVersion
            Write-DetectionLog "Verzia zo suboru: $detectedVersion"
        }
    }
    catch {
        Write-DetectionLog "Chyba pri ziskavani verzie zo suboru: $_" "Warning"
    }
}
else {
    Write-DetectionLog "OCS Inventory exe nenajdeny na: $ExePath"
}

# Metoda 2: Registry kontrola (rychlejsia ako WMI)
if (-not $detectedVersion) {
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $registryPaths) {
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*OCS Inventory*" -or 
                $_.Publisher -like "*OCS*" -or
                $_.DisplayName -like "*OCS Agent*"
            }
            
            if ($apps) {
                $appInstalled = $true
                foreach ($app in $apps) {
                    if ($app.DisplayVersion) {
                        $detectedVersion = $app.DisplayVersion
                        Write-DetectionLog "Registry: $($app.DisplayName) - Verzia: $detectedVersion"
                        break
                    }
                }
            }
        }
        catch {
            Write-DetectionLog "Chyba pri kontrole registry $path : $_" "Warning"
        }
        
        if ($detectedVersion) { break }
    }
}

# Metoda 3: Kontrola sluzby OCS
try {
    $ocsService = Get-Service -Name "*OCS*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ocsService) {
        $appInstalled = $true
        Write-DetectionLog "OCS sluzba najdena: $($ocsService.Name) - Status: $($ocsService.Status)"
        
        # Ak sluzba bezi a nemame verziu, skus ziskat z registry sluzby
        if (-not $detectedVersion) {
            try {
                $servicePath = (Get-WmiObject Win32_Service | Where-Object { $_.Name -like "*OCS*" }).PathName
                if ($servicePath -and (Test-Path $servicePath.Split('"')[1])) {
                    $serviceVersion = (Get-ItemProperty $servicePath.Split('"')[1]).VersionInfo.FileVersion
                    if ($serviceVersion) {
                        $detectedVersion = $serviceVersion
                        Write-DetectionLog "Verzia zo sluzby: $detectedVersion"
                    }
                }
            }
            catch {
                Write-DetectionLog "Chyba pri ziskavani verzie sluzby: $_" "Warning"
            }
        }
    }
}
catch {
    Write-DetectionLog "Chyba pri kontrole sluzieb: $_" "Warning"
}
#endregion

#region === Win32 App Detection Logic ===
Write-DetectionLog "Finalny stav - Nainstalovane: $appInstalled, Verzia: $detectedVersion"

# Pre Win32 aplikacie v Intune:
# - Ak aplikacia je spravne nainstalovana -> napis text a exit 0
# - Ak aplikacia nie je nainstalovana alebo ma zlu verziu -> exit 1 alebo ziadny vystup

if ($appInstalled -and $detectedVersion -and $detectedVersion -eq $ExpectedVersion) {
    # Aplikacia je spravne nainstalovana
    Write-DetectionLog "SUCCESS: OCS Inventory verzia $detectedVersion je spravne nainstalovana" "Success"
    Write-Host "OCS Inventory verzia $detectedVersion je nainstalovana"
    exit 0
    
}
elseif ($appInstalled -and $detectedVersion -and $detectedVersion -ne $ExpectedVersion) {
    # Aplikacia je nainstalovana ale ma zlu verziu
    Write-DetectionLog "MISMATCH: Nainstalovana verzia $detectedVersion, ocakavana $ExpectedVersion" "Warning"
    exit 1
    
}
elseif ($appInstalled -and -not $detectedVersion) {
    # Aplikacia je detekovana ale verziu sa nepodarilo urcit
    Write-DetectionLog "UNKNOWN: OCS Inventory detekovany ale verzia neznama" "Warning"
    exit 1
    
}
else {
    # Aplikacia nie je nainstalovana
    Write-DetectionLog "NOT FOUND: OCS Inventory nie je nainstalovany" "Info"
    exit 1
}
#endregion