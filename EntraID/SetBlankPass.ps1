#spustit skript
# .\Set-TaurisPassword.ps1 -Username "sklad"

param (
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [switch]$Test
)

# Cesty a log
$LogFolder = "C:\Log"
$LogFile = "$LogFolder\SetPassword.log"
if (-not (Test-Path -Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Time - $Message"
    Write-Host "$Time - $Message" -ForegroundColor Cyan
}

# Získaj posledné 4 znaky názvu počítača
function Get-SuffixFromComputerName {
    $comp = $env:COMPUTERNAME
    if ($comp.Length -lt 4) {
        throw "Názov počítača je príliš krátky na extrakciu 4 znakov: $comp"
    }
    return $comp.Substring($comp.Length - 4, 4)
}

# Nastavenie hesla
function Set-LocalUserPassword {
    param ([string]$Username)

    $User = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $User) {
        Write-Log "ERROR: Používateľ '$Username' neexistuje."
        return
    }

    try {
        $suffix = Get-SuffixFromComputerName
        $NewPassword = "Tauris$suffix"
        Write-Log "Generované nové heslo pre $Username : $NewPassword"

        if ($Test) {
            Write-Log "TEST MODE: Heslo NEBOLO zmenené."
        } else {
            $SecurePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
            Set-LocalUser -Name $Username -Password $SecurePassword
            Write-Log "Heslo pre používateľa $Username bolo úspešne nastavené."
        }
    } catch {
        Write-Log "ERROR pri nastavovaní hesla: $_"
    }
}

# --- Hlavná časť ---
Write-Log "=== ZMENA HESLA PRE LOKÁLNEHO POUŽÍVATEĽA ==="
if ($Test) {
    Write-Log "Režim: TEST (žiadne zmeny nebudú vykonané)"
}

Set-LocalUserPassword -Username $Username

Write-Log "=== UKONČENÉ ==="
