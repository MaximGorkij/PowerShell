# Zapnutie Wi-Fi adaptéra
$adapter = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
if ($adapter -and $adapter.Status -eq "Disabled") {
    Enable-NetAdapter -Name "Wi-Fi" -Confirm:$false
    Write-Output "Wi-Fi bol zapnutý."
} else {
    Write-Output "Wi-Fi je už zapnutý alebo nebol nájdený."
}