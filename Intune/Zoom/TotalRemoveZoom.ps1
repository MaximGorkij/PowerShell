<#
.SYNOPSIS
    Kompletne odinstalovanie vsetkych verzií Zoom z Windows systemu
.DESCRIPTION
    Tento skript odinstaluje vsetky nainstalovane verzie Zoom aplikacii
    a vycisti vsetky zvysky z registrov a uzivatelskych profilov
.NOTES
    Vyzaduje spustenie s administratorskymi pravami
#>

#Requires -RunAsAdministrator

# Premenne pre logovanie
$EventSource = "ZoomUninstallScript"
$LogFileName = "C:\TaurisIT\Log\ZoomUninstall.log"

# Kontrola a import modulu LogHelper
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$ModuleName = "LogHelper"

# Funkcia pre fallback logovanie
function Initialize-FallbackLogging {
    function Write-CustomLog {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [Parameter(Mandatory = $true)]
            [string]$EventSource,
            [string]$EventLogName = "IntuneScript",
            [Parameter(Mandatory = $true)]
            [string]$LogFileName,
            [ValidateSet("Information", "Warning", "Error")]
            [string]$Type = "Information"
        )
        $LogDirectory = Split-Path $LogFileName -Parent
        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$Timestamp [$Type] - $Message" | Out-File -FilePath $LogFileName -Append -Encoding UTF8
        Write-Output "[$Type] $Message"
        
        try {
            Write-EventLog -LogName "Application" -Source "Application" -EntryType $Type -EventId 1000 -Message "$EventSource : $Message" -ErrorAction SilentlyContinue
        }
        catch {
            # Ignoruj chyby pri zapisovani do Event Logu
        }
    }
    
    # Export funkcie do globalneho scope
    Set-Item -Path function:\global:Write-CustomLog -Value (Get-Command Write-CustomLog).ScriptBlock
}

try {
    if (-not (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue)) {
        if (Test-Path $ModulePath) {
            Import-Module $ModulePath -Force -ErrorAction Stop
            Write-Output "Modul LogHelper bol uspesne importovany"
        }
        else {
            Initialize-FallbackLogging
            Write-Output "Pouziva sa fallback logovacia funkcia"
        }
    }
}
catch {
    Write-Output "Chyba pri importe modulu LogHelper: $($_.Exception.Message)"
    Initialize-FallbackLogging
}

# Hlavna logika skriptu
try {
    Write-CustomLog -Message "=== Zaciatok odinstalacie Zoom aplikacii ===" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"

    # 1. Zastavenie vsetkych Zoom procesov (pred odinstalovanim)
    Write-CustomLog -Message "Zastavenie Zoom procesov..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    $ZoomProcesses = @("zoom", "ZoomPhone", "ZoomChat", "CptHost", "ZoomUninstall", "ZoomRooms", "ZoomWebHelper")
    $ProcessesStopped = $false
    
    foreach ($ProcessName in $ZoomProcesses) {
        $RunningProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($RunningProcesses) {
            $ProcessesStopped = $true
            try {
                $RunningProcesses | Stop-Process -Force -ErrorAction Stop
                Write-CustomLog -Message "Zastaveny proces: $ProcessName (PID: $($RunningProcesses.Id -join ', '))" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
            }
            catch {
                Write-CustomLog -Message "Chyba pri zastavovani procesu $ProcessName : $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            }
        }
    }
    
    if ($ProcessesStopped) {
        Write-CustomLog -Message "Cakanie na ukoncenie procesov (5 sekund)..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
        Start-Sleep -Seconds 5
    }

    # 2. Najdenie vsetkych nainstalovanych verzií Zoom
    Write-CustomLog -Message "Vyhladavanie nainstalovanych Zoom aplikacii..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    $ZoomProducts = @()
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($Path in $UninstallPaths) {
        try {
            $Apps = Get-ItemProperty $Path -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*Zoom*" -and $_.UninstallString }
            
            foreach ($App in $Apps) {
                $ZoomProducts += [PSCustomObject]@{
                    DisplayName     = $App.DisplayName
                    UninstallString = $App.UninstallString
                    PSChildName     = $App.PSChildName
                    Publisher       = $App.Publisher
                }
            }
        }
        catch {
            Write-CustomLog -Message "Chyba pri prehladavani $Path : $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
        }
    }

    Write-CustomLog -Message "Najdene Zoom aplikacie: $($ZoomProducts.Count)" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    foreach ($Product in $ZoomProducts) {
        Write-CustomLog -Message "  - $($Product.DisplayName)" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    }

    # 3. Odinstalovanie kazdeho najdeneho Zoom produktu
    foreach ($Product in $ZoomProducts) {
        Write-CustomLog -Message "Spustam odinstalaciu: $($Product.DisplayName)" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
        
        $UninstallString = $Product.UninstallString.Trim()
        $UninstallExe = ""
        $UninstallArgs = ""
        
        # Spracovanie roznych formatov uninstall stringu
        if ($UninstallString -match '^"([^"]+)"(.*)$') {
            # Format: "C:\path\to\uninstall.exe" /args
            $UninstallExe = $Matches[1]
            $UninstallArgs = $Matches[2].Trim() + " /quiet /norestart"
        }
        elseif ($UninstallString -match '^msiexec(\.exe)?\s+(.+)$') {
            # Format: msiexec /X{GUID} alebo msiexec.exe /I{GUID}
            $UninstallExe = "msiexec.exe"
            $MsiArgs = $Matches[2]
            if ($MsiArgs -match '/[IX]\{?([A-Z0-9-]+)\}?') {
                $ProductCode = $Matches[1]
                $UninstallArgs = "/x {$ProductCode} /quiet /norestart /l*v `"$LogFileName.msi.log`""
            }
            else {
                $UninstallArgs = "$MsiArgs /quiet /norestart"
            }
        }
        elseif ($UninstallString -match '\.exe') {
            # Format: C:\path\to\uninstall.exe (bez uvodzoviek)
            if ($UninstallString -match '^(.+\.exe)(.*)$') {
                $UninstallExe = $Matches[1].Trim()
                $UninstallArgs = $Matches[2].Trim() + " /quiet /norestart"
            }
        }
        else {
            Write-CustomLog -Message "Neznamy format uninstall stringu pre $($Product.DisplayName): $UninstallString" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            continue
        }

        # Overenie existencie uninstall exe
        if (-not $UninstallExe) {
            Write-CustomLog -Message "Nepodarilo sa extrahovat uninstall executable z: $UninstallString" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            continue
        }

        # Spustenie odinstalacie
        try {
            if ($UninstallExe -eq "msiexec.exe" -or (Test-Path $UninstallExe -ErrorAction SilentlyContinue)) {
                Write-CustomLog -Message "Spustam: $UninstallExe $UninstallArgs" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
                
                $ProcessParams = @{
                    FilePath     = $UninstallExe
                    ArgumentList = $UninstallArgs
                    Wait         = $true
                    PassThru     = $true
                    NoNewWindow  = $true
                }
                
                $Process = Start-Process @ProcessParams
                
                # Uspesne exit kody: 0 (uspech), 3010 (uspech, restart pozadovany), 1605 (produkt uz nie je nainstalovany)
                if ($Process.ExitCode -in @(0, 3010, 1605)) {
                    Write-CustomLog -Message "Uspesne odinstalovane: $($Product.DisplayName) (Exit code: $($Process.ExitCode))" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
                }
                else {
                    Write-CustomLog -Message "Odinstalacia vratila neocakavany kod pre $($Product.DisplayName). Exit code: $($Process.ExitCode)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
                }
            }
            else {
                Write-CustomLog -Message "Uninstall executable neexistuje: $UninstallExe" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            }
        }
        catch {
            Write-CustomLog -Message "Chyba pri spustani odinstalacie pre $($Product.DisplayName): $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
        }
    }

    # 4. Dalsi pokus o zastavenie pripadnych zvyskovych procesov
    Write-CustomLog -Message "Kontrola zvyskovych Zoom procesov..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    foreach ($ProcessName in $ZoomProcesses) {
        try {
            $RemainingProcesses = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
            if ($RemainingProcesses) {
                $RemainingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-CustomLog -Message "Zastaveny zvyskovy proces: $ProcessName" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
            }
        }
        catch {
            # Ignoruj chyby
        }
    }
    Start-Sleep -Seconds 2

    # 5. Odstranenie Zoom priecinkov
    Write-CustomLog -Message "Odstranujem Zoom priecinky..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    $ZoomFolders = @(
        "$env:PROGRAMFILES\Zoom",
        "${env:PROGRAMFILES(X86)}\Zoom",
        "$env:LOCALAPPDATA\Zoom",
        "$env:APPDATA\Zoom",
        "$env:PROGRAMDATA\Zoom",
        "$env:PUBLIC\Desktop\Zoom.lnk",
        "$env:USERPROFILE\Desktop\Zoom.lnk",
        "$env:ALLUSERSPROFILE\Desktop\Zoom.lnk"
    )

    foreach ($Folder in $ZoomFolders) {
        if (Test-Path $Folder) {
            try {
                Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                Write-CustomLog -Message "Odstraneny: $Folder" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
            }
            catch {
                # Pokus o nulovanie atributov a opakovanoe mazanie
                try {
                    Get-ChildItem -Path $Folder -Recurse -Force | ForEach-Object {
                        $_.Attributes = 'Normal'
                    }
                    Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                    Write-CustomLog -Message "Odstraneny (po resetovani atributov): $Folder" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
                }
                catch {
                    Write-CustomLog -Message "Nepodarilo sa odstranit $Folder : $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
                }
            }
        }
    }

    # 6. Vyčistenie registrov
    Write-CustomLog -Message "Cistenie registrov..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Zoom",
        "HKLM:\SOFTWARE\WOW6432Node\Zoom",
        "HKCU:\SOFTWARE\Zoom",
        "HKCU:\SOFTWARE\Classes\ZoomLauncher"
    )
    
    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path $RegPath) {
            try {
                Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop
                Write-CustomLog -Message "Odstraneny registry kluc: $RegPath" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
            }
            catch {
                Write-CustomLog -Message "Chyba pri odstranovani registry $RegPath : $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            }
        }
    }

    # 7. Vyčistenie zo Start Menu
    Write-CustomLog -Message "Odstranenie zo Start Menu..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    $StartMenuPaths = @(
        "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Zoom",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Zoom",
        "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Zoom"
    )
    
    foreach ($StartMenuPath in $StartMenuPaths) {
        if (Test-Path $StartMenuPath) {
            try {
                Remove-Item -Path $StartMenuPath -Recurse -Force -ErrorAction Stop
                Write-CustomLog -Message "Odstranene zo Start Menu: $StartMenuPath" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
            }
            catch {
                Write-CustomLog -Message "Chyba pri odstranovani zo Start Menu: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            }
        }
    }

    # 8. Vyčistenie zo vsetkych uzivatelskych profilov
    Write-CustomLog -Message "Cistenie uzivatelskych profilov..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    
    try {
        $UserProfiles = Get-CimInstance -ClassName Win32_UserProfile | 
        Where-Object { -not $_.Special -and $_.LocalPath -notlike "*Windows*" }
        
        foreach ($Profile in $UserProfiles) {
            $UserPath = $Profile.LocalPath
            $UserName = Split-Path $UserPath -Leaf
            
            $UserZoomPaths = @(
                "$UserPath\AppData\Local\Zoom",
                "$UserPath\AppData\Roaming\Zoom",
                "$UserPath\Desktop\Zoom.lnk"
            )
            
            foreach ($ZoomPath in $UserZoomPaths) {
                if (Test-Path $ZoomPath) {
                    try {
                        Remove-Item -Path $ZoomPath -Recurse -Force -ErrorAction Stop
                        Write-CustomLog -Message "Odstranene z profilu '$UserName': $ZoomPath" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
                    }
                    catch {
                        Write-CustomLog -Message "Chyba pri odstranovani z profilu '$UserName' ($ZoomPath): $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
                    }
                }
            }
        }
    }
    catch {
        Write-CustomLog -Message "Chyba pri spracovani uzivatelskych profilov: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
    }

    # 9. Finalna verifikacia
    Write-CustomLog -Message "Verifikacia odinstalacie..." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    $RemainingZoomApps = @()
    foreach ($Path in $UninstallPaths) {
        $RemainingZoomApps += Get-ItemProperty $Path -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -like "*Zoom*" }
    }
    
    if ($RemainingZoomApps.Count -eq 0) {
        Write-CustomLog -Message "=== Odinstalacia Zoom bola uspesne dokoncena! ===" -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
        exit 0
    }
    else {
        Write-CustomLog -Message "Upozornenie: Najdene zvyskove Zoom aplikacie ($($RemainingZoomApps.Count))" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
        foreach ($App in $RemainingZoomApps) {
            Write-CustomLog -Message "  - Zvyskova aplikacia: $($App.DisplayName)" -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
        }
        exit 0
    }
}
catch {
    Write-CustomLog -Message "KRITICKA CHYBA: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
    Write-CustomLog -Message "Stack Trace: $($_.ScriptStackTrace)" -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
    exit 1
}