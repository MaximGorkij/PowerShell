#Kill Adobe Acrobat Reader process
Stop-Process -Name acrobat -Force

#Get Adobe Reader GUID
$Adobe = (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object DisplayName -Like "Adobe Acrobat*").PSChildName

#Uninstall Adobe Acrobat
msiexec.exe /X $Adobe /qn

#cleanup
$path64 = 'C:\Program Files\Adobe\Acrobat DC'
$path32 = 'C:\Program Files (x86)\Adobe\Acrobat Reader DC'
Remove-Item -Path "HKLM:\Software\Adobe\Adobe Acrobat" -Recurse -Force
if (Test-Path -Path $path64){
    Remove-Item -Path $path64 -Recurse -Force
}
if (Test-Path -Path $path32){
    Remove-Item -Path $path32 -Recurse -Force
}