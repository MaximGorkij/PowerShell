<# 
.SYNOPSIS
    Spolocny skript na migraciu dat do Edge/Firefox a odstranenie Chrome.
.DESCRIPTION
    1. Nastavi registre pre Microsoft Edge (Import pri prvom spusteni).
    2. Nastavi registre pre Mozilla Firefox (ImportSettings politika).
    3. Odinstaluje vsetky verzie Google Chrome.
.NOTES
    Verzia: 3.0
    Autor: Automaticky report
    Pozadovane moduly: LogHelper
    Logovanie: C:\TaurisIT\Log\FullMigration.txt
#>

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogFile = "C:\TaurisIT\Log\FullMigration.txt"
$Source = "MultiBrowserMigration"

# Import modulu LogHelper podla vasho standardu
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
}
else {
    Write-Host "[ERROR] Modul LogHelper nebol najdeny na ceste $ModulePath" -ForegroundColor Red
    exit 1
}

# Pomocna funkcia pre dualne logovanie bez diakritiky
function Write-LogProgress {
    param(
        [string]$Message,
        [string]$Type = "Information"
    )
    $Color = switch ($Type) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $Color

    # Volanie vasej funkcie Write-CustomLog z modulu LogHelper
    Write-CustomLog -Message $Message -EventSource $Source -LogFileName $LogFile -Type $Type
}

Write-LogProgress "Zacinam proces hromadnej migracie a cistenia."

# --- 1. KROK: Nastavenie Microsoft Edge ---
Write-LogProgress "Konfigurujem registre pre Microsoft Edge."
$EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (!(Test-Path $EdgePath)) { New-Item -Path $EdgePath -Force | Out-Null }

$EdgeSettings = @{
    "AutoImportAtFirstRun"   = 1
    "ImportBookmarks"        = 1
    "ImportSavedPasswords"   = 1
    "ImportAutofillFormData" = 1
}

foreach ($EKey in $EdgeSettings.Keys) {
    $EVal = $EdgeSettings[$EKey]
    # Ziadna dvojbodka za premennou podla vasho pravidla
    New-ItemProperty -Path $EdgePath -Name $EKey -Value $EVal -PropertyType DWord -Force | Out-Null
}

# --- 2. KROK: Nastavenie Mozilla Firefox ---
Write-LogProgress "Konfigurujem registre pre Mozilla Firefox."
$FFPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (!(Test-Path $FFPath)) { New-Item -Path $FFPath -Force | Out-Null }

try {
    # ImportSettings = 1 znamena povolenie importu z ineho prehliadaca
    New-ItemProperty -Path $FFPath -Name "ImportSettings" -Value 1 -PropertyType DWord -Force | Out-Null
    Write-LogProgress "Firefox registre boli uspesne nastavene."
}
catch {
    Write-LogProgress "Nepodarilo sa nastavit registre pre Firefox: $($_.Exception.Message)" "Warning"
}

# --- 3. KROK: Odinstalacia Google Chrome ---
Write-LogProgress "Hladam nainstalovany Google Chrome pre odstranenie."
$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$ChromeFound = $false
foreach ($P in $RegPaths) {
    $Apps = Get-ItemProperty $P -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Google Chrome*" }
    foreach ($App in $Apps) {
        $ChromeFound = $true
        $AName = $App.DisplayName
        Write-LogProgress "Odinstalovavam: $AName" "Warning"

        if ($App.UninstallString -like "*msiexec*") {
            $MsiArgs = "/x $($App.PSChildName) /qn /norestart"
            $Proc = Start-Process msiexec.exe -ArgumentList $MsiArgs -Wait -PassThru
        }
        else {
            $UStr = $App.UninstallString
            $PathOnly = if ($UStr -match '"([^"]+)"') { $matches[1] } else { $UStr.Split(' ')[0] }
            $Proc = Start-Process $PathOnly -ArgumentList "--uninstall --system-level --force-uninstall" -Wait -PassThru
        }

        if ($Proc.ExitCode -eq 0 -or $Proc.ExitCode -eq 3010) {
            Write-LogProgress "Chrome ($AName) bol uspesne odstraneny." "Information"
        }
        else {
            Write-LogProgress "Odinstalacia $AName zlyhala s kodom: $($Proc.ExitCode)" "Error"
        }
    }
}

if (!$ChromeFound) { Write-LogProgress "Ziadna instalacia Google Chrome nebola najdena." }

Write-LogProgress "Vsetky operacie su ukoncene."