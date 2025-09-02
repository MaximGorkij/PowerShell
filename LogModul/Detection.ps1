$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
if (Test-Path $ModulePath) {
    Write-Output "Installed"
    exit 0
} else {
    Write-Output "Not Installed"
    exit 1
}