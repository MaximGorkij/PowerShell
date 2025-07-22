# Zastavenie služby
Stop-Service -Name "Zabbix Agent 2" -ErrorAction SilentlyContinue

# Odstránenie služby
sc.exe delete "Zabbix Agent 2"

# Odstránenie inštalačného priečinka
$agentPath = "C:\Program Files\Zabbix Agent 2"
if (Test-Path $agentPath) {
    Remove-Item -Path $agentPath -Recurse -Force
}

# Odstránenie certifikátu (ak bol importovaný)
$certs = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$env:COMPUTERNAME*" }
foreach ($cert in $certs) {
    Remove-Item -Path "Cert:\LocalMachine\My\$($cert.Thumbprint)" -Force
}

# Odstránenie logov (voliteľné)
$logPath = "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log"
if (Test-Path $logPath) {
    Remove-Item -Path $logPath -Force
}