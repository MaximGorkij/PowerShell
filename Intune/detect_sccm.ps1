$clientPath = "C:\Windows\CCM"
$ccmExec = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue

if (Test-Path $clientPath -or $ccmExec) {
    Write-Output "SCCM client detected"
    exit 1  # Remediation needed
} else {
    Write-Output "SCCM client not found"
    exit 0  # No remediation needed
}