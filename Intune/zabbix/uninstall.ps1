Stop-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
sc.exe delete "Zabbix Agent 2"
Remove-Item "C:\Program Files\Zabbix Agent 2" -Recurse -Force
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$env:COMPUTERNAME*" } | Remove-Item -Force