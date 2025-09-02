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

# Vytvor logovaci priecinok
if (-not (Test-Path -Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# Vytvor Event Log ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    New-EventLog -LogName $EventLogName -Source $EventSource
}

function Write-EventLogEntry {
    param (
        [string]$Message,
        [string]$Type = "Information",
        [int]$EventID = 1000
    )
    Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventID -Message $Message
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "Information"
    )
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FullMessage = "$Time - $Message"
    Add-Content -Path $LogFile -Value $FullMessage
    Write-Host $FullMessage -ForegroundColor Cyan

    # Zapis do Event Logu
    $eventType = switch ($Type.ToLower()) {
        "error" { "Error" }
        "warning" { "Warning" }
        default { "Information" }
    }
    Write-EventLogEntry -Message $Message -Type $eventType
}

function Get-SuffixFromComputerName {
    $comp = $env:COMPUTERNAME
    if ($comp.Length -lt 4) {
        throw "Computer name is too short to extract 4 characters: $comp"
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
        Write-Log "ERROR: Pouzivatel '$Username' neexistuje." "Error"
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
                Write-Log "Heslo sa nezmenilo - aktualizacia nie je potrebna." "Information"
            } else {
                Write-Log "Heslo sa lisi od posledneho - bude aktualizovane." "Warning"
            }
        } else {
            Write-Log "Hash subor neexistuje - predpokladam prve spustenie." "Information"
        }

        if ($PasswordChangedExternally) {
            Write-Log "Generovane nove heslo pre '$Username': $NewPassword" "Information"

            if ($Test) {
                Write-Log "TEST MODE: Heslo NEBOLO zmenene." "Information"
            } else {
                $SecurePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
                Set-LocalUser -Name $Username -Password $SecurePassword
                $NewPasswordHash | Set-Content -Path $HashFile
                Write-Log "Heslo pre pouzivatela '$Username' bolo uspesne nastavene." "Information"
            }
        }
    } catch {
        Write-Log "CHYBA pri nastavovani hesla: $_" "Error"
    }
}

# Spustenie
Write-Log "=== ZACIATOK ZMENY HESLA ===" "Information"
if ($Test) {
    Write-Log "Rezim: TEST (ziadne zmeny sa nevykonaju)" "Information"
}

Set-LocalUserPassword

Write-Log "=== UKONCENE ===" "Information"