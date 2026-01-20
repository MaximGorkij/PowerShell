# check-tpm.ps1
# Slovak bez diakritiky, audit-ready

$exportDir = "C:\TaurisIT\Export"
if (-not (Test-Path $exportDir)) {
    New-Item -Path $exportDir -ItemType Directory | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $exportDir "TPM_SecureBoot_Audit_$timestamp.csv"
$results = @()

$computer = $env:COMPUTERNAME

# TPM cez CIM
try {
    $tpm = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop
    $tpmStatus = if ($tpm.IsEnabled_Initial -and $tpm.IsActivated_Initial) {
        "TPM aktivovany a povoleny"
    }
    else {
        "TPM nie je aktivovany alebo povoleny"
    }
}
catch {
    $tpmStatus = "TPM informacia nedostupna (CIM trieda nie je dostupna)"
}

# Secure Boot fallback detekcia
# Confirm-SecureBootUEFI NEFUNGUJE na serveroch a VM
try {
    $sb = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop
    $secureBootStatus = if ($sb.UEFISecureBootEnabled -eq 1) {
        "Secure Boot aktivny"
    }
    else {
        "Secure Boot neaktivny"
    }
}
catch {
    $secureBootStatus = "Secure Boot informacia nedostupna (pravdepodobne VM alebo BIOS)"
}

# BIOS verzia
$bios = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion

# Zapis vysledkov
$results += [PSCustomObject]@{
    Cas             = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Pocitac         = $computer
    TPM_Stav        = $tpmStatus
    SecureBoot_Stav = $secureBootStatus
    Firmware        = $bios
}

$results | Export-Csv -Path $logFile -NoTypeInformation -Encoding UTF8

Write-Host "Audit dokonceny. Log ulozeny:" -ForegroundColor Cyan
Write-Host $logFile -ForegroundColor Yellow