#Kill OCS Inventory Service process
Stop-Process -ProcessName 'OcsService' -Force

#Get OCS Agent uninstall path
$ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString

$ocsagent = $ocsagent + " /x /qn"


#Uninstall OCS Agent
$ocsagent | Out-File -FilePath "C:\Windows\Temp\uninstall_ocsagent2_1.log" -Encoding utf8


#cleanup
$path = 'C:\Program Files (x86)\OCS Inventory Agent'
if (Test-path -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"){
    Remove-Item -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent" -Recurse -Force
}

if (Test-Path -Path $path){
    Remove-Item -Path $path -Recurse -Force
}