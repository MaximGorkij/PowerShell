<# 
.SYNOPSIS
    Kontrola a zapnutie Real-time protection v Microsoft Defender
.DESCRIPTION
    Skontroluje stav RTP. Ak je vypnutý, pokúsi sa ho zapnúť. 
    Využíva LogHelper pre zápis do C:\TaurisIT\Log\DefenderRTP.log.
.NOTES
    Verzia:            1.4
    Autor:             Automaticky report
    Pozadovane moduly: LogHelper
    Datum vytvorenia:  23.02.2026
    Logovanie:         C:\TaurisIT\Log\DefenderRTP.log
#>

#region Init
$EventSource = "IntuneDefenderScript"
$LogFileName = "DefenderRTP.log"
$LogDirectory = "C:\TaurisIT\Log"
$exitCode = 0

# Import modulu LogHelper
$modulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -ErrorAction Stop
}
else {
    Write-Error "LogHelper modul nebol najdeny $modulePath"
    exit 1
}

# Inicializacia logovacieho systemu
if (-not (Test-Path $LogDirectory)) { New-Item -Path $LogDirectory -ItemType Directory -Force }

# Kontrola administrator prav
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $msg = "Skript nema administratorske prava. Ukoncujem."
    Write-CustomLog -Message $msg -Type 'Error' -EventSource $EventSource -LogFileName $LogFileName
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [ERROR] $msg" -ForegroundColor Red
    exit 1
}
#endregion

#region Defender status check
try {
    $status = Get-MpComputerStatus -ErrorAction Stop
}
catch {
    $err = $_.Exception.Message
    $msg = "Nepodarilo sa ziskat stav Defendera $err"
    Write-CustomLog -Message $msg -Type 'Error' -EventSource $EventSource -LogFileName $LogFileName
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [ERROR] $msg" -ForegroundColor Red
    exit 1
}

# Overenie ci Defender nie je zakazany externe
if ($status.AMServiceEnabled -eq $false) {
    $msg = "Microsoft Defender service je vypnuta. Zmena nie je mozna (GPO/3rd-party AV?)."
    Write-CustomLog -Message $msg -Type 'Error' -EventSource $EventSource -LogFileName $LogFileName
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [ERROR] $msg" -ForegroundColor Red
    exit 1
}
#endregion

#region RTP check & remediation
if ($status.RealTimeProtectionEnabled -eq $true) {
    $msg = "Real-time protection je uz aktivna. Ziadna akcia nie je potrebna."
    Write-CustomLog -Message $msg -Type 'Information' -EventSource $EventSource -LogFileName $LogFileName
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [INFO] $msg" -ForegroundColor Green
    exit 0
}

$msg = "Real-time protection je vypnuta. Pokus o zapnutie..."
Write-CustomLog -Message $msg -Type 'Warning' -EventSource $EventSource -LogFileName $LogFileName
Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [WARN] $msg" -ForegroundColor Yellow

try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Start-Sleep -Seconds 5 # Predlzeny cas na inicializaciu sluzby

    $newStatus = Get-MpComputerStatus -ErrorAction Stop

    if ($newStatus.RealTimeProtectionEnabled -eq $true) {
        $msg = "Real-time protection bola uspesne zapnuta."
        Write-CustomLog -Message $msg -Type 'Information' -EventSource $EventSource -LogFileName $LogFileName
        Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [INFO] $msg" -ForegroundColor Green
    }
    else {
        # Ak status ostal false aj po Set-MpPreference
        $msg = "Real-time protection sa nepodarilo zapnut. Dovod: Tamper Protection je pravdepodobne ON."
        Write-CustomLog -Message $msg -Type 'Error' -EventSource $EventSource -LogFileName $LogFileName
        Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [ERROR] $msg" -ForegroundColor Red
        $exitCode = 1
    }
}
catch {
    $err = $_.Exception.Message
    $msg = "Chyba pri zapinani Real-time protection $err"
    Write-CustomLog -Message $msg -Type 'Error' -EventSource $EventSource -LogFileName $LogFileName
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] [ERROR] $msg" -ForegroundColor Red
    $exitCode = 1
}
#endregion

exit $exitCode