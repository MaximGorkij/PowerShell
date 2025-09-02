$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogDir = "C:\TaurisIT\Log"

# Vytvorenie adresára pre modul
if (-not (Test-Path $ModulePath)) {
    New-Item -Path $ModulePath -ItemType Directory -Force
}

# Skopírovanie modulu
Copy-Item -Path ".\LogHelper.psm1" -Destination $ModulePath -Force

# Vytvorenie adresára pre logy
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force
}