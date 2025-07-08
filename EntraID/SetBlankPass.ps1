#
# Real run (applies changes)
#.\Set-BlankPassword-Secure.ps1 -Username "TestUser"

# Test run (logs changes without applying)
#.\Set-BlankPassword-Secure.ps1 -Username "TestUser" -Test
#

param (
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [switch]$Test
)

# Log file setup
$LogFolder = "C:\Log"
$LogFile = "$LogFolder\BlankPassword.log"

# Ensure log folder exists
if (-not (Test-Path -Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# Logging function
function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
    Write-Host "$Timestamp - $Message" -ForegroundColor Cyan
}

# Disable password complexity policy (local machine only)
function Disable-PasswordPolicy {
    try {
        $SecPolicyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        $OriginalComplexity = Get-ItemProperty -Path $SecPolicyPath -Name "NoLmHash" -ErrorAction SilentlyContinue
        $OriginalLimitBlank = Get-ItemProperty -Path $SecPolicyPath -Name "LimitBlankPasswordUse" -ErrorAction SilentlyContinue

        if (-not $Test) {
            Set-ItemProperty -Path $SecPolicyPath -Name "NoLmHash" -Value 0
            Set-ItemProperty -Path $SecPolicyPath -Name "LimitBlankPasswordUse" -Value 0
        }
        Write-Log "Temporarily disabled local password complexity policy."

        return @{
            NoLmHash = if ($OriginalComplexity) { $OriginalComplexity.NoLmHash } else { $null }
            LimitBlankPasswordUse = if ($OriginalLimitBlank) { $OriginalLimitBlank.LimitBlankPasswordUse } else { $null }
        }
    } catch {
        Write-Log "ERROR disabling password policy: $_"
        return $nulla
    }
}

# Restore original password policy
function Restore-PasswordPolicy {
    param (
        [hashtable]$OriginalSettings
    )
    try {
        $SecPolicyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        if (-not $Test) {
            if ($OriginalSettings.NoLmHash -ne $nulla) {
                Set-ItemProperty -Path $SecPolicyPath -Name "NoLmHash" -Value $OriginalSettings.NoLmHash
            }
            if ($OriginalSettings.LimitBlankPasswordUse -ne $nulla) {
                Set-ItemProperty -Path $SecPolicyPath -Name "LimitBlankPasswordUse" -Value $OriginalSettings.LimitBlankPasswordUse
            }
        }
        Write-Log "Restored original password policy settings."
    } catch {
        Write-Log "ERROR restoring password policy: $_"
    }
}

# Set blank password (using 'net user' command)
function Set-BlankPassword {
    param ([string]$Username)
    try {
        if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
            Write-Log "ERROR: User '$Username' does not exist."
            return
        }
        Write-Log "Attempting to set blank password for: $Username"
        if (-not $Test) {
            $Process = Start-Process -FilePath "net.exe" -ArgumentList "user $Username """ -NoNewWindow -Wait -PassThru
            if ($Process.ExitCode -ne 0) {
                Write-Log "ERROR: 'net user' failed with exit code $($Process.ExitCode)"
            } else {
                Write-Log "Successfully set blank password for $Username."
            }
        } else {
            Write-Log "Test mode enabled. No changes applied to $Username."
        }
    } catch {
        Write-Log "ERROR setting blank password: $_"
    }
}

# --- MAIN SCRIPT ---
Write-Log "=== BLANK PASSWORD CONFIGURATION (STANDALONE PC) ==="
Write-Log "WARNING: Blank passwords are insecure! Use only in test environments."

if ($Test) {
    Write-Host "=== TEST MODE: No changes will be applied. ===" -ForegroundColor Yellow
    Write-Log "TEST MODE active: changes are simulated only."
}

$OriginalSettings = Disable-PasswordPolicy

if ($OriginalSettings) {
    Set-BlankPassword -Username $Username
    Restore-PasswordPolicy -OriginalSettings $OriginalSettings
} else {
    Write-Log "Failed to modify security policies. Aborting."
}

Write-Log "=== SCRIPT COMPLETED ==="
