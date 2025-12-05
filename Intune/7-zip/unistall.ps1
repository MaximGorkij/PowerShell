<#
.SYNOPSIS
    Napravny skript pre odinstalovanie vsetkych verzii aplikacie 7-Zip, vratane vynuteneho cistenia registra a filesystemu.
    Určene pre Intune Proactive Remediations.

.DESCRIPTION
    Skript hlada a spusti odinstalacne prikazy pre vsetky registrovane verzie 7-Zip (HKLM/HKCU).
    Následne vynutene odstrani registracne kluce a skontroluje a odstrani typicke instalacne adresare a sputitelne subory 7-Zip.
    Vrati exit code 0, ak bola odinstalacia/vycistenie USPESNA.
    Vrati exit code 1, ak odinstalacia/vycistenie ZLYHALO.

.AUTHOR
    Marek Findrik (Adaptacia a rozsirenie pre 7-Zip)

.CREATED
    2025-11-26  

.VERSION
    1.2.0

.NOTES
    - Skript vyzaduje predinstalovany modul 'LogHelper'.
    - Loguje vysledok do C:\TaurisIT\Log\Remediate7-zip.log a paralelne aj do Remediate7-zip.txt.
#>

# --- KONFIGURACIA LOGOVANIA ---
$EventSource = "7Zip-Remediation-Intune-Remediation"
$LogFileName = "Remediate7-zip.log" 
$LogDirectory = "C:\TaurisIT\Log"
$TextLogFile = Join-Path $LogDirectory "Remediate7-zip.txt"
$FailureCount = 0

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

# --- NACITANIE LOGOVACIEHO MODULU ---
try {
    Import-Module LogHelper -ErrorAction Stop
    if (-not (Get-Command Write-CustomLog -ErrorAction SilentlyContinue)) { exit 1 }
    if (-not (Test-Path $LogDirectory)) { New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null }
    
    $StartMsg = "START napravneho skriptu pre 7-Zip (kompletna odinstalacia)."
    Write-CustomLog -Message $StartMsg -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    Write-TextLog -Message $StartMsg
}
catch {
    Write-Error "CHYBA: Modul LogHelper sa nepodarilo nacitat! $($_.Exception.Message)"
    exit 1
}

# --- 1. ODINŠTALÁCIA A VYČISTENIE REGISTRA ---
try {
    Write-CustomLog -Message "1/2: Start odinstalacie a vynuteneho cistenia registrovanych verzii 7-Zip." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $AppNames = "7-Zip*" 
    $FoundApps = @()

    # Zozbieranie vsetkych inštancií
    foreach ($Path in $UninstallPaths) {
        $FoundApps += Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
        Get-ItemProperty |
        Where-Object { $_.DisplayName -like $AppNames }
    }
    
    if ($FoundApps.Count -eq 0) {
        Write-CustomLog -Message "REGISTRY: Neboli najdene ziadne registrovane verzie 7-Zip." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    }

    # Spustenie odinštalácie a vynútené vymazanie kľúča
    foreach ($App in $FoundApps) {
        $DisplayName = $App.DisplayName
        $UninstallString = $App.UninstallString
        $KeyPath = $App.PSPath # Cesta k registračnému kľúču
        
        Write-TextLog -Message "--- Spracovanie aplikacie: '$DisplayName' ---"

        # A. Pokus o tichú odinštaláciu
        if (-not [string]::IsNullOrWhiteSpace($UninstallString)) {
            $Message = "Odinstalovavam (Pokus 1/2): '$DisplayName' s prikazom: '$UninstallString'"
            Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            
            $UninstallCommand = $UninstallString
            if ($UninstallCommand -notmatch " /S|/quiet|/qn|/norestart|/passive") {
                if ($UninstallCommand -like "*msiexec*") { $UninstallCommand += " /qn /norestart" }
                elseif ($UninstallCommand -like "*.exe*") { $UninstallCommand += " /S" }
            }
            
            try {
                Invoke-Expression -Command "cmd.exe /c '$UninstallCommand'" -ErrorAction Stop
                Start-Sleep -Seconds 5 # Pockame, kym sa odinstalacia dokonci
                Write-TextLog -Message "Odinstalacia '$DisplayName' uspesne spustena."
            }
            catch {
                $ErrorMessage = "CHYBA ODINSTALACIE: Zlyhala odinstalacia '$DisplayName'. Popis: $($_.Exception.Message)"
                Write-CustomLog -Message $ErrorMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
                Write-TextLog -Message $ErrorMessage
                $FailureCount++
            }
        }
        
        # B. Vynútené odstránenie registračného kľúča
        if (-not [string]::IsNullOrWhiteSpace($KeyPath)) {
            $Message = "CISTENIE REGISTRA (Pokus 2/2): Vynutene odstranujem registracny kluc pre '$DisplayName'."
            Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
             
            try {
                Remove-Item -Path $KeyPath -Recurse -Force -ErrorAction Stop
                Write-TextLog -Message "Registracny kluc uspesne odstraneny: $KeyPath"
            }
            catch {
                $ErrorMessage = "CHYBA CISTENIA: Nepodarilo sa odstranit registracny kluc '$KeyPath'. Popis: $($_.Exception.Message)"
                Write-CustomLog -Message $ErrorMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
                Write-TextLog -Message $ErrorMessage
                $FailureCount++
            }
        }
    }
}
catch {
    $ErrorMessage = "FATALNA CHYBA: Zlyhanie bloku odinstalacie registrovanych verzii. Popis: $($_.Exception.Message)"
    Write-CustomLog -Message $ErrorMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
    Write-TextLog -Message $ErrorMessage
    $FailureCount++
}

# --- 2. VYČISTENIE FILESYSTÉMU (Odstránenie adresárov) ---
try {
    Write-CustomLog -Message "2/2: Start vycistenia zvyskov 7-Zip na filesysteme." -EventSource $EventSource -LogFileName $LogFileName -Type "Information"

    $PathsToDelete = @(
        "$env:ProgramFiles\7-Zip",
        "$env:ProgramFiles(x86)\7-Zip",
        "$env:AppData\7-Zip",
        "$env:LocalAppData\7-Zip"
    )

    foreach ($Path in $PathsToDelete) {
        if (Test-Path -Path $Path -PathType Container) {
            $Message = "Odstranujem zvysky adresara: $Path"
            Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFileName -Type "Warning"
            Write-TextLog -Message $Message
            
            try {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
                Write-TextLog -Message "Adresar $Path uspesne odstraneny."
            }
            catch {
                $ErrorMessage = "CHYBA: Nepodarilo sa odstranit adresar '$Path'. Popis: $($_.Exception.Message)"
                Write-CustomLog -Message $ErrorMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
                Write-TextLog -Message $ErrorMessage
                $FailureCount++
            }
        }
    }
}
catch {
    $ErrorMessage = "FATALNA CHYBA: Zlyhanie bloku vycistenia filesystemu. Popis: $($_.Exception.Message)"
    Write-CustomLog -Message $ErrorMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
    Write-TextLog -Message $ErrorMessage
    $FailureCount++
}

# --- KONEČNÝ VÝSLEDOK PRE INTUNE ---
if ($FailureCount -eq 0) {
    $FinalMessage = "USPECH: Odinstalacia a vycistenie 7-Zip dokoncene uspesne. PC je vycistene."
    Write-CustomLog -Message $FinalMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Information"
    Write-TextLog -Message $FinalMessage
    exit 0 # USPEŠNÝ STAV (Náprava bola vykonaná a je hotovo)
}
else {
    $FinalMessage = "CHYBA: Odinstalacia/vycistenie 7-Zip skoncilo s $FailureCount chybami. Skontrolujte logy."
    Write-CustomLog -Message $FinalMessage -EventSource $EventSource -LogFileName $LogFileName -Type "Error"
    Write-TextLog -Message $FinalMessage
    exit 1 # ZLYHANIE NÁPRAVY (Náprava nebola uspokojivo dokončená)
}