#Kill OCS Inventory Service process
#Stop-Process -ProcessName 'OcsService' -Force
Stop-Service -Name 'OCS Inventory Service' -Force


#Get OCS Agent uninstall path
if (Test-path -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"){
    $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
}
Elseif (Test-path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"){
    $ocsagent = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent").UninstallString
}

write-host $ocsagent

$ocsagent = $ocsagent + " /x /qn"


#Uninstall OCS Agent
$ocsagent | Out-File -FilePath "C:\Windows\Temp\uninstall_ocsagent2_1.log" -Encoding utf8


#cleanup
# $path = 'C:\Program Files (x86)\OCS Inventory Agent'
if (Test-path -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"){
    Remove-Item -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent" -Recurse -Force
}
Elseif (Test-path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent"){
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OCS Inventory NG Agent" -Recurse -Force
}


if (Test-Path "C:\Program Files (x86)\OCS Inventory Agent"){
    Remove-Item -Path "C:\Program Files (x86)\OCS Inventory Agent" -Recurse -Force
}
elseif (Test-Path "C:\Program Files\OCS Inventory Agent"){
    Remove-Item -Path "C:\Program Files\OCS Inventory Agent" -Recurse -Force
}