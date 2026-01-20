# check-platform.ps1
# Full diagnostika platformy, TPM, Secure Boot, BIOS, BitLocker
# Slovak bez diakritiky, audit-ready

$exportDir = "C:\TaurisIT\Export"
if (-not (Test-Path $exportDir)) {
    New-Item -Path $exportDir -ItemType Directory | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $exportDir "Full_Diag_$timestamp.csv"
$results = @()

$computer = $env:COMPUTERNAME

# Funkcia: detekcia Hyper-V VM
function Get-VMState {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.Model -match "Virtual" -or $cs.Manufacturer -match "Microsoft Corporation") {
            return "Hyper-V VM"
        }
        else {
            return "Fyzicky server alebo PC"
        }
    }
    catch {
        return "Nedostupne"
    }
}

# Funkcia: UEFI / Legacy
function Get-BootMode {
    try {
        # Najpresnejsia detekcia
        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot") {
            return "UEFI"
        }

        # Alternativa
        $firmware = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($firmware.BootupState -match "EFI") {
            return "UEFI"
        }

        return "Legacy BIOS"
    }
    catch {
        return "Nedostupne"
    }
}

# Funkcia: Secure Boot stav
function Get-SecureBootState {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State"

    if (Test-Path $path) {
        try {
            $sb = Get-ItemProperty -Path $path
            if ($sb.UEFISecureBootEnabled -eq 1) {
                return "Secure Boot aktivny"
            }
            else {
                return "Secure Boot vypnuty"
            }
        }
        catch {
            return "Secure Boot informacia nedostupna (chyba pri citani)"
        }
    }
    else {
        return "Secure Boot nedostupny (Legacy BIOS alebo VM)"
    }
}

# Funkcia: TPM stav
function Get-TPMState {
    try {
        $tpm = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop

        $presence = if ($tpm) { "TPM pritomny" } else { "TPM nepritomny" }
        $enabled = if ($tpm.IsEnabled_Initial) { "TPM povoleny" } else { "TPM nepovoleny" }
        $active = if ($tpm.IsActivated_Initial) { "TPM aktivovany" } else { "TPM neaktivovany" }

        return "$presence / $enabled / $active"
    }
    catch {
        return "TPM informacia nedostupna (CIM trieda nie je dostupna)"
    }
}

# Funkcia: TPM verzia
function Get-TPMVersion {
    try {
        $tpm = Get-Tpm
        if ($tpm.TpmPresent -eq $true) {
            return $tpm.ManufacturerVersion
        }
        else {
            return "TPM neprítomny"
        }
    }
    catch {
        return "Nedostupne"
    }
}

# Funkcia: Dell Secure Boot Keys
function Get-DellSecureBootKeys {

    # Overenie existencie namespace "dcim"
    $dcimRoot = Get-CimInstance -Namespace root -ClassName __Namespace -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "dcim" }

    if (-not $dcimRoot) {
        return "Dell DCIM nepodporovane"
    }

    # Overenie existencie namespace "root\dcim\sysman"
    $sysman = Get-CimInstance -Namespace root\dcim -ClassName __Namespace -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "sysman" }

    if (-not $sysman) {
        return "Dell DCIM rozhranie nedostupne"
    }

    try {
        $keys = Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BIOSService -ErrorAction Stop
        return "Dell BIOS DCIM rozhranie dostupne"
    }
    catch {
        return "Dell DCIM rozhranie nedostupne"
    }
}

# Funkcia: BitLocker stav
function Get-BitLockerState {
    try {
        $vol = Get-BitLockerVolume -MountPoint "C:"
        if ($vol.ProtectionStatus -eq "On") {
            return "BitLocker aktivny"
        }
        else {
            return "BitLocker vypnuty"
        }
    }
    catch {
        return "BitLocker informacia nedostupna"
    }
}

# BIOS verzia
$bios = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion

# Zapis vysledkov
$results += [PSCustomObject]@{
    Cas        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Pocitac    = $computer
    Platforma  = Get-VMState
    BootMode   = Get-BootMode
    SecureBoot = Get-SecureBootState
    TPM_Stav   = Get-TPMState
    TPM_Verzia = Get-TPMVersion
    Dell_DCIM  = Get-DellSecureBootKeys
    BitLocker  = Get-BitLockerState
    Firmware   = $bios
}

$results | Export-Csv -Path $logFile -NoTypeInformation -Encoding UTF8

Write-Host "Full diagnostika dokoncena. Log ulozeny:" -ForegroundColor Cyan
Write-Host $logFile -ForegroundColor Yellow