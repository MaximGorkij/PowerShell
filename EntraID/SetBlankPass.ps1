param (
    [switch]$Test
)

# Cesta k log súboru
$LogFile = "C:\Path\To\LogFile.log"

# Funkcia na zapisovanie do logu
function Write-Log {
    param (
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

# Funkcia na kontrolu a nastavenie prázdneho hesla
function Set-BlankPassword {
    param (
        [string]$Username
    )
    try {
        $User = Get-LocalUser -Name $Username
        if ($User.PasswordRequired) {
            if (-not $Test) {
                $Password = "" | ConvertTo-SecureString -AsPlainText -Force
                Set-LocalUser -Name $Username -Password $Password
            }
            Write-Log "Password for user $Username set to blank."
        } else {
            Write-Log "Password for user $Username is already blank."
        }
    } catch {
        Write-Log "Error setting password for user $Username : $_"
    }
}

# Funkcia na kontrolu a nastavenie bezpečnostných nastavení
function Set-SecuritySettings {
    try {
        $LsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        $LsaValue = Get-ItemProperty -Path $LsaPath -Name "LimitBlankPasswordUse"
        if ($LsaValue.LimitBlankPasswordUse -ne 0) {
            if (-not $Test) {
                Set-ItemProperty -Path $LsaPath -Name "LimitBlankPasswordUse" -Value 0
            }
            Write-Log "LimitBlankPasswordUse set to 0."
        } else {
            Write-Log "LimitBlankPasswordUse is already set to 0."
        }

        $UacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $UacValue = Get-ItemProperty -Path $UacPath -Name "EnableLUA"
        if ($UacValue.EnableLUA -ne 0) {
            if (-not $Test) {
                Set-ItemProperty -Path $UacPath -Name "EnableLUA" -Value 0
            }
            Write-Log "EnableLUA set to 0."
        } else {
            Write-Log "EnableLUA is already set to 0."
        }

        # Pridajte ďalšie bezpečnostné nastavenia podľa potreby
    } catch {
        Write-Log "Error setting security settings: $_"
    }
}

# Hlavný skript
Write-Log "Script started."
Set-BlankPassword -Username "MenoPouzivatela"
#Set-SecuritySettings
Write-Log "Script completed."
