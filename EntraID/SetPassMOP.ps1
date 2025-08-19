param (
    [switch]$Test
)

# Fixed username
$Username = "sklad"

# Paths and logging
$LogFolder = "C:\Log"
$LogFile = "$LogFolder\SetPassword.log"
$HashFile = "$LogFolder\PasswordHash_$Username.txt"

if (-not (Test-Path -Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Time - $Message"
    Write-Host "$Time - $Message" -ForegroundColor Cyan
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
        Write-Log "ERROR: User '$Username' does not exist."
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
                Write-Log "Password has not been changed externally - no update needed."
            } else {
                Write-Log "Password differs from the last one set by this script - it will be updated."
            }
        } else {
            Write-Log "Password hash file does not exist - assuming first script run."
        }

        if ($PasswordChangedExternally) {
            Write-Log "Generated new password for '$Username': $NewPassword"

            if ($Test) {
                Write-Log "TEST MODE: Password was NOT changed."
            } else {
                $SecurePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
                Set-LocalUser -Name $Username -Password $SecurePassword
                $NewPasswordHash | Set-Content -Path $HashFile
                Write-Log "Password for user '$Username' was successfully set."
            }
        }
    } catch {
        Write-Log "ERROR while setting password: $_"
    }
}

# - Main section -
Write-Log "=== PASSWORD CHANGE FOR LOCAL USER ==="
if ($Test) {
    Write-Log "Mode: TEST (no changes will be made)"
}

Set-LocalUserPassword

Write-Log "=== COMPLETED ==="