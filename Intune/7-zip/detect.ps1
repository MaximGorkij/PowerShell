<#
.SYNOPSIS
    Detekcny skript pre overenie pritomnosti vsetkych verzii aplikacie 7-Zip (Registry a Filesystem).
    Určene pre Intune Proactive Remediations.

.DESCRIPTION
    Skript vyhladava vsetky instalovane verzie 7-Zip v registroch (32-bit, 64-bit, HKCU) a na disku.
    Vrati exit code 0, ak je 7-Zip stale nainstalovany/pritomny (PROBLEM NAJDENY).
    Vrati exit code 1, ak 7-Zip nainstalovany nie je (PROBLEM NENAJDENY / USPESNY STAV).

.AUTHOR
    Marek Findrik (Adaptacia a rozsirenie pre 7-Zip)

.CREATED
    2025-11-25  

.VERSION
    1.2.0

.NOTES
    - Skript vyzaduje predinstalovany modul 'LogHelper'.
    - Loguje vysledok detekcie do C:\TaurisIT\Log\Detect7-zip.log a paralelne aj do Detect7-zip.txt.
#>

# --- KONFIGURACIA LOGOVANIA ---
$EventSource = "7Zip-Detection-Intune-Remediation"
$LogFileName = "Detect7-zip.log" 
$LogDirectory = "C:\TaurisIT\Log"
$TextLogFile = Join-Path $LogDirectory "Detect7-zip.txt"

# --- FUNKCIA PRE TEXTOVY LOG ---
function Write-TextLog {
    param(
        [string]$Message
    )
    try {
        $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $Line = "$TimeStamp`t$Message"
        Add-Content -Path $TextLogFile -Value $Line -ErrorAction SilentlyContinue
    }
    catch {
        Write-Error "CHYBA: Nepodarilo sa zapisat do textoveho logu! $($_.Exception.Message)"
    }
}

# --- FUNKCIA PRE VYHLADAVANIE V SYSTEME SUBOROV ---
function Find-7ZipExecutable {
    <#
    .SYNOPSIS
        Vyhladava spustitelne subory 7-Zip v spolocnych cestach.
    .OUTPUTS
        Boolean. $true, ak sa subor najde, inak $false.
    #>
    $ExecutableNames = @("7zG.exe", "7zFM.exe", "7z.exe")
    $SearchPaths = @(
        "$env:ProgramFiles\7-Zip",
        "$env:ProgramFiles(x86)\7-Zip",
        "$env:AppData\7-Zip",
        "$env:LocalAppData\7-Zip"
    )

    Write-TextLog -Message "FILESYSTEM: Start vyhladavania suborov 7-Zip v spolocnych cestach."

    foreach ($Path in $SearchPaths) {
        foreach ($Exe in $ExecutableNames) {
            $FullPath = Join-Path -Path $Path -ChildPath $Exe
            if (Test-Path -Path $FullPath -PathType Leaf) {
                $Message = "FILESYSTEM: Najdeny spustitelny subor: $FullPath"
                Write-TextLog -Message $Message
                return $true
            }
        }
    }
    
    Write-TextLog -Message "FILESYSTEM: Ziaden spustitelny subor 7-Zip nebol najdeny."
    return $false
}


# --- NACITANIE LOGOVACIEHO MODULU ---
try {
    Import-Module LogHelper -ErrorAction Stop
    if (-not (Get-Command Write-CustomLog -ErrorAction SilentlyContinue)) { exit 1 }
    if (-not (Test-Path $LogDirectory)) { New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null }
    
    $StartMsg = "START detekcneho skriptu pre 7-Zip (Registry & Filesystem)."
    Write-CustomLog -Message $StartMsg -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    Write-TextLog -Message $StartMsg
}
catch {
    Write-Error "CHYBA: Modul LogHelper sa nepodarilo nacitat! $($_.Exception.Message)"
}

# --- VYKONANIE DETEKCIE ---
try {
    # 1. Kontrola Registrov
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $AppNames = "7-Zip*" 
    $IsInstalledByRegistry = $false
    
    Write-TextLog -Message "REGISTRY: Start vyhladavania v registroch."

    foreach ($Path in $UninstallPaths) {
        $FoundApps = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
        Get-ItemProperty |
        Where-Object { $_.DisplayName -like $AppNames }

        if ($FoundApps.Count -gt 0) {
            $IsInstalledByRegistry = $true
            Write-TextLog -Message "REGISTRY: 7-Zip najdeny v ceste $Path."
            break
        }
    }

    # 2. Kontrola Filesystému
    $IsInstalledByFilesystem = Find-7ZipExecutable

    # Celkový výsledok
    $IsInstalled = $IsInstalledByRegistry -or $IsInstalledByFilesystem

    if ($IsInstalled) {
        $Source = if ($IsInstalledByRegistry -and $IsInstalledByFilesystem) { "REGISTRY A FILESYSTEM" }
        elseif ($IsInstalledByRegistry) { "REGISTRY" }
        else { "FILESYSTEM" }

        $Message = "DETEKCIA: 7-Zip je stale nainstalovany/pritomny ($Source - PROBLEM NAJDENY). Spusti sa naprava."
        Write-Host $Message
        Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
        Write-TextLog -Message $Message
        
        exit 0  # PROBLEM NAJDENY
    }
    else {
        $Message = "DETEKCIA: 7-Zip nie je nainstalovany ani pritomny (PROBLEM NENAJDENY). Nie je nutna naprava."
        Write-Host $Message
        Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
        Write-TextLog -Message $Message
        
        exit 1  # PROBLEM NENAJDENY
    }
}
catch {
    $ErrorMessage = "FATALNA CHYBA: Zlyhanie behu detekcneho bloku. Popis chyby: $($_.Exception.Message)"
    Write-Error $ErrorMessage
    Write-CustomLog -Message $ErrorMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
    Write-TextLog -Message $ErrorMessage
    
    exit 1  # default fallback
}