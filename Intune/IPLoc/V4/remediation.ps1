<#
.SYNOPSIS
    Remediation: Zapíše správnu lokáciu do extensionAttribute1
#>

# ... rovnaký začiatok ako v detection (import, log init, JSON, IP určenie, location výpočet, Graph autentifikácia, Get-MgDevice) ...

try {
    # ... získaj $device a $location ako vyššie ...

    $body = @{
        onPremisesExtensionAttributes = @{
            extensionAttribute1 = $location
        }
    }

    Update-MgDevice -DeviceId $device.Id -BodyParameter $body -ErrorAction Stop

    Write-IntuneLog -Message "SUCCESS – extensionAttribute1 nastavené na $location (IP: $ip)" -Level SUCCESS -LogFile $LogFile
    Write-Output "Opravené – nastavené $location"
    exit 0

}
catch {
    Write-IntuneLog -Message "Remediation CHYBA: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Send-IntuneAlert -Message "Nepodarilo sa nastaviť lokáciu: $($_.Exception.Message)" -Severity Error -EventSource $EventSource -LogFile $LogFile
    Write-Output "Chyba pri zápise: $($_.Exception.Message)"
    exit 1
}