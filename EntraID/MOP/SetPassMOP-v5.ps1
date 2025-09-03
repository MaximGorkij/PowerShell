param (
    [switch]$Test
)

# Nastavenia
$Username = "sklad"
$LogFolder = "C:\TaurisIT\Log"
$LogFile = "$LogFolder\SetPassword.log"
$HashFile = "$LogFolder\PasswordHash_$Username.txt"
$EventLogName = "IntuneScript"
$EventSource = "MOP Password Change"

# Import modulu LogHelper
Import-Module LogHelper -ErrorAction SilentlyContinue

# Vytvor logovaci priecinok
if (-not (Test-Path -Path $LogFolder)) {
    try {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
        Write-CustomLog -Message "Adresar '$LogFolder' bol vytvoreny." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani adresara: $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
    }
}

# Vytvor Event Log ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    try {
        New-EventLog -LogName $EventLogName -Source $EventSource
        Write-CustomLog -Message "Event Log '$EventLogName' a zdroj '$EventSource' boli vytvorene." -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani Event Logu: $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
    }
}

function Get-SuffixFromComputerName {
    $comp = $env:COMPUTERNAME
    if ($comp.Length -lt 4) {
        throw "Nazov pocitaca je prilis kratky: $comp"
    }
    return $comp.Substring($comp.Length - 4, 4)
}

function Get-PasswordHash {
    param ([string]$PlainText)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes) -replace "-", ""
}

function Set-LocalUserPassword {
    $User = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $User) {
        Write-CustomLog -Message "Pouzivatel '$Username' neexistuje." -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
        return
    }

    try {
        $suffix = Get-SuffixFromComputerName
        $NewPassword = "Tauris$suffix"
        $NewPasswordHash = Get-PasswordHash -PlainText $NewPassword

        $PasswordChangedExternally = $true
        if (Test-Path $HashFile) {
            $StoredHash = Get-Content $HashFile
            if ($StoredHash -eq $NewPasswordHash) {
                $PasswordChangedExternally = $false
                Write-CustomLog -Message "Heslo sa nezmenilo - aktualizacia nie je potrebna." -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
            } else {
                Write-CustomLog -Message "Heslo sa lisi od posledneho - bude aktualizovane." -Type "Warning" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
            }
        } else {
            Write-CustomLog -Message "Hash subor neexistuje - predpokladam prve spustenie." -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
        }

        if ($PasswordChangedExternally) {
            Write-CustomLog -Message "Generovane nove heslo pre '$Username': $NewPassword" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile

            if ($Test) {
                Write-CustomLog -Message "TEST MODE: Heslo NEBOLO zmenene." -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
            } else {
                $SecurePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
                Set-LocalUser -Name $Username -Password $SecurePassword
                $NewPasswordHash | Set-Content -Path $HashFile
                Write-CustomLog -Message "Heslo pre pouzivatela '$Username' bolo uspesne nastavene." -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
            }
        }
    } catch {
        Write-CustomLog -Message "CHYBA pri nastavovani hesla: $_" -Type "Error" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
    }
}

# Spustenie
Write-CustomLog -Message "=== ZACIATOK ZMENY HESLA ===" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
if ($Test) {
    Write-CustomLog -Message "Rezim: TEST (ziadne zmeny sa nevykonaju)" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile
}

Set-LocalUserPassword

Write-CustomLog -Message "=== UKONCENE ===" -Type "Information" -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile