#your cert file
$sourceFichier = "\\servershare\OCS_Inventory\cacert.pem"
$destFichier = "C:\ProgramData\OCS Inventory NG\Agent\"

    
    if((Test-Path -Path "C:\Program Files\OCS Inventory Agent\Download.exe"))
    {
        $VersionDownloadFile = (Get-Command "C:\Program Files\OCS Inventory Agent\Download.exe").Version
       
        #check version of download.exe
        if ($VersionDownloadFile -ne "2.9.2.0") # wrong version
        {
            write-Host "Wrong Version detected ! : Version=$VersionDownloadFile -> Update needed !"
            write-Host "uninstall in progress..."
            Start-Process -Wait "C:\Program Files\OCS Inventory Agent\uninst.exe" /S
            write-Host "commande : \\servershare\OCS_Inventory\setup.exe /S /CA=cacert.pem /SERVER=https://ocsinventory.local/ocsinventory"
            Start-Process -Wait -FilePath "\\servershare\OCS_Inventory\setup.exe" -ArgumentList "/S", "/CA=cacert.pem", "/SERVER=https://ocsinventory.local/ocsinventory"
            write-Host "copy file \\servershare\OCS_Inventory\cacert.pem to C:\ProgramData\OCS Inventory NG\Agent\"
            Copy-Item -Path $sourceFichier -Destination $destFichier -force
            write-Host "reboot needed !"
            #check version of download.exe
            $VersionDownloadFile = (Get-Command "C:\Program Files\OCS Inventory Agent\Download.exe").Version
            if($VersionDownloadFile -eq "2.9.2.0")
            {
                write-Host "Update successfull ! start services...."
                Start-Process -Wait "C:\Program Files\OCS Inventory Agent\OcsService.exe"
                write-Host "Start Systray"
                Start-Process "C:\Program Files\OCS Inventory Agent\OcsSystray.exe"
                write-Host "launch inventory"
                Start-Process "C:\Program Files\OCS Inventory Agent\OCSInventory.exe" -ArgumentList "/NOW"
                write-Host "exit 0"
                exit 0
            }
            else
            {
                write-Host "ERROR : exit 1"
                exit 1
            }
           
        }
        else  # good version
        {
            Start-Process "C:\Program Files\OCS Inventory Agent\OCSInventory.exe" -ArgumentList "/NOW"
            write-Host "Good version : $VersionDownloadFile "
            write-Host "exit 0"
            exit 0
        }
    }
    else
    {
        #agent not present reinstall it
        write-Host "error download.exe not exist ! reinstall needed"
        write-Host "commande : \\servershare\OCS_Inventory\setup.exe /S /CA=cacert.pem /SERVER=https://ocsinventory.local/ocsinventory"
        Start-Process -Wait -FilePath "\\servershare\OCS_Inventory\setup.exe" -ArgumentList "/S", "/CA=cacert.pem", "/SERVER=https://ocsinventory.local/ocsinventory"
        write-Host "copy file \\servershare\OCS_Inventory\cacert.pem to C:\ProgramData\OCS Inventory NG\Agent\"
        Copy-Item -Path $sourceFichier -Destination $destFichier -force
        write-Host "reboot needed !"
        #check version of download.exe
        $VersionDownloadFile = (Get-Command "C:\Program Files\OCS Inventory Agent\Download.exe").Version
        if($VersionDownloadFile -eq "2.9.2.0")
        {
            write-Host "Update successfull ! start services...."
            Start-Process -Wait "C:\Program Files\OCS Inventory Agent\OcsService.exe"
            write-Host "Start Systray"
            Start-Process "C:\Program Files\OCS Inventory Agent\OcsSystray.exe"
            write-Host "launch inventory"
            Start-Process "C:\Program Files\OCS Inventory Agent\OCSInventory.exe" -ArgumentList "/NOW"
            write-Host "exit 0"
            exit 0
        }
        else
        {
            write-Host "ERROR : exit 1"
            exit 1
        }
    }