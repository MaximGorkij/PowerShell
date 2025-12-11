# WinRAR Remediation Script - LogHelper verzia
param()

try {
    # Import LogHelper modulu
    $modulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        # Inicializácia log systému
        $initSuccess = Initialize-LogSystem -LogDirectory "C:\TaurisIT\Log\Winrar" -EventSource "WinRAR_Remediation" -RetentionDays 30
        if (-not $initSuccess) {
            Write-Warning "Nepodarilo sa inicializovať log systém"
        }
    }
    else {
        Write-Warning "LogHelper modul nenájdený v ceste: $modulePath"
        # Vytvoriť adresár aspoň pre základné logy
        New-Item -Path "C:\TaurisIT\Log\Winrar" -ItemType Directory -Force | Out-Null
    }
    
    # Log začiatku remediation
    Write-IntuneLog -Message "=== ZAČIATOK WinRAR Remediation skriptu ===" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    
    function Uninstall-WinRAR {
        Write-IntuneLog -Message "Spúšťam odinštaláciu WinRAR..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        $uninstallResults = @()
        
        # 1. Odinštalácia pomocou msiexec (pre MSI inštalácie)
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($path in $registryPaths) {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*WinRAR*" }
            
            foreach ($app in $apps) {
                $appName = $app.DisplayName
                $appVersion = $app.DisplayVersion
                $uninstallString = $app.UninstallString
                $quietUninstallString = $app.QuietUninstallString
                
                Write-IntuneLog -Message "Nájdený WinRAR: $appName (verzia: $appVersion)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                try {
                    if ($quietUninstallString) {
                        # Tichá odinštalácia
                        $uninstallCmd = $quietUninstallString
                        Write-IntuneLog -Message "Používam quiet uninstall string: $uninstallCmd" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        
                        if ($uninstallCmd -match 'MsiExec\.exe') {
                            $arguments = "/x " + ($uninstallCmd -split ' ')[1] + " /quiet /norestart"
                            Start-Process "MsiExec.exe" -ArgumentList $arguments -Wait -NoNewWindow
                        }
                        else {
                            # Štandardný uninstall string
                            Start-Process cmd.exe -ArgumentList "/c `"$uninstallCmd`" /S" -Wait -NoNewWindow
                        }
                    }
                    elseif ($uninstallString) {
                        $uninstallCmd = $uninstallString
                        Write-IntuneLog -Message "Používam uninstall string: $uninstallCmd" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        
                        Start-Process cmd.exe -ArgumentList "/c `"$uninstallCmd`"" -Wait -NoNewWindow
                    }
                    
                    $uninstallResults += @{
                        Name    = $appName
                        Version = $appVersion
                        Status  = "Success"
                        Method  = "Registry"
                    }
                    
                    Write-IntuneLog -Message "Odinštalácia spustená pre: $appName" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    # Krátka prestávka medzi odinštaláciami
                    Start-Sleep -Seconds 3
                }
                catch {
                    $errorMsg = "Chyba pri odinštalácii $appName $_"
                    Write-IntuneLog -Message $errorMsg -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    $uninstallResults += @{
                        Name    = $appName
                        Version = $appVersion
                        Status  = "Failed"
                        Method  = "Registry"
                        Error   = $_.Exception.Message
                    }
                }
            }
        }
        
        # 2. Odinštalácia pomocou Get-Package (pre moderné inštalácie)
        try {
            $packages = Get-Package -Name "*WinRAR*" -ErrorAction SilentlyContinue
            foreach ($package in $packages) {
                Write-IntuneLog -Message "Odinštalovávam prostredníctvom PackageManagement: $($package.Name) (verzia: $($package.Version))" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                try {
                    Uninstall-Package -Name $package.Name -Force -ErrorAction SilentlyContinue
                    
                    $uninstallResults += @{
                        Name    = $package.Name
                        Version = $package.Version
                        Status  = "Success"
                        Method  = "PackageManagement"
                    }
                    
                    Write-IntuneLog -Message "Odinštalované cez PackageManagement: $($package.Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
                catch {
                    $errorMsg = "Chyba pri odinštalácii $($package.Name) cez PackageManagement: $_"
                    Write-IntuneLog -Message $errorMsg -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    $uninstallResults += @{
                        Name    = $package.Name
                        Version = $package.Version
                        Status  = "Failed"
                        Method  = "PackageManagement"
                        Error   = $_.Exception.Message
                    }
                }
            }
        }
        catch {
            Write-IntuneLog -Message "Chyba pri práci s PackageManagement: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        }
        
        # 3. Vymazanie zvyškových súborov a priečinkov
        $winrarFolders = @(
            "${env:ProgramFiles}\WinRAR",
            "${env:ProgramFiles(x86)}\WinRAR",
            "$env:LOCALAPPDATA\WinRAR",
            "$env:APPDATA\WinRAR"
        )
        
        foreach ($folder in $winrarFolders) {
            if (Test-Path $folder) {
                try {
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                    Write-IntuneLog -Message "Odstránený priečinok: $folder" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
                catch {
                    Write-IntuneLog -Message "Nepodarilo sa odstrániť $folder $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
            }
        }
        
        # Logovanie výsledkov odinštalácie
        $successCount = ($uninstallResults | Where-Object { $_.Status -eq "Success" }).Count
        $failedCount = ($uninstallResults | Where-Object { $_.Status -eq "Failed" }).Count
        
        Write-IntuneLog -Message "Odinštalácia WinRAR dokončená - Úspešné: $successCount, Zlyhané: $failedCount" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        if ($failedCount -gt 0) {
            $failedApps = $uninstallResults | Where-Object { $_.Status -eq "Failed" } | ForEach-Object { "$($_.Name) ($($_.Method))" }
            $alertMsg = "Niektoré WinRAR inštalácie sa nepodarilo odinštalovať: $($failedApps -join ', ')"
            Send-IntuneAlert -Message $alertMsg -Severity Warning -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
        }
        
        return $uninstallResults
    }
    
    function Set-ZipAssociation {
        Write-IntuneLog -Message "Nastavujem asociáciu .zip na 7-Zip..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        # Kontrola či je 7-Zip nainštalovaný
        $7zipPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip"
        )
        
        $7zipInstalled = $false
        $7zipPath = $null
        
        foreach ($path in $7zipPaths) {
            if (Test-Path $path) {
                $7zipInstalled = $true
                $7zipPath = $path
                Write-IntuneLog -Message "7-Zip nájdený v registri: $path" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                break
            }
        }
        
        if (-not $7zipInstalled) {
            # Skúsiť nájsť 7-Zip pomocou Get-Package
            $packages = Get-Package -Name "*7-Zip*" -ErrorAction SilentlyContinue
            if ($packages) {
                $7zipInstalled = $true
                Write-IntuneLog -Message "7-Zip nájdený cez PackageManagement: $($packages[0].Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
            }
        }
        
        if ($7zipInstalled) {
            try {
                # Nastavenie asociácie pomocou dism (Windows 10/11)
                $exportPath = "$env:TEMP\assoc_backup_$(Get-Date -Format 'yyyyMMddHHmmss').xml"
                dism /online /Export-DefaultAppAssociations:$exportPath 2>&1 | Out-Null
                
                if (Test-Path $exportPath) {
                    Write-IntuneLog -Message "Exportované aktuálne asociácie do: $exportPath" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
                
                # Pokus o nastavenie cez registry
                $assocPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.zip\UserChoice"
                
                # Získanie aktuálnej asociácie
                $currentAssoc = $null
                try {
                    $currentAssoc = (Get-ItemProperty -Path $assocPath -Name "ProgId" -ErrorAction SilentlyContinue).ProgId
                }
                catch {
                    # Ak neexistuje, ignorujeme
                }
                
                # Skontrolujeme ktoré ProgId je dostupné pre 7-Zip
                $availableProgIds = @("7-Zip.zip", "7zFM.zip", "7-Zip.7z")
                $selectedProgId = $null
                
                foreach ($progId in $availableProgIds) {
                    $testPath = "HKCR:\$progId"
                    if (Test-Path $testPath) {
                        $selectedProgId = $progId
                        break
                    }
                }
                
                if (-not $selectedProgId) {
                    # Default na 7-Zip.zip
                    $selectedProgId = "7-Zip.zip"
                }
                
                # Nastavenie asociácie
                try {
                    if (-not (Test-Path $assocPath)) {
                        New-Item -Path $assocPath -Force | Out-Null
                    }
                    
                    New-ItemProperty -Path $assocPath -Name "ProgId" -Value $selectedProgId -PropertyType String -Force | Out-Null
                    Write-IntuneLog -Message "Asociácia .zip nastavená na $selectedProgId v registry (predchádzajúca: $currentAssoc)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    # Alternatívne cez ftype a assoc (pre staršie Windows)
                    try {
                        # Nájdi cestu k 7zFM.exe
                        $7zPath = "${env:ProgramFiles}\7-Zip\7zFM.exe"
                        if (-not (Test-Path $7zPath)) {
                            $7zPath = "${env:ProgramFiles(x86)}\7-Zip\7zFM.exe"
                        }
                        
                        if (Test-Path $7zPath) {
                            cmd /c "ftype $selectedProgId=`"$7zPath`" `"%1`"" 2>&1 | Out-Null
                            cmd /c "assoc .zip=$selectedProgId" 2>&1 | Out-Null
                            Write-IntuneLog -Message "Asociácia nastavená cez assoc/ftype" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        }
                    }
                    catch {
                        Write-IntuneLog -Message "Nepodarilo sa nastaviť asociáciu cez assoc: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                    
                    Write-IntuneLog -Message "Asociácia .zip bola úspešne nastavená na 7-Zip ($selectedProgId)" -Level SUCCESS -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    return $true
                }
                catch {
                    $errorMsg = "Chyba pri nastavovaní asociácie cez registry: $_"
                    Write-IntuneLog -Message $errorMsg -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    Send-IntuneAlert -Message $errorMsg -Severity Error -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
                    return $false
                }
            }
            catch {
                $errorMsg = "Chyba pri nastavovaní asociácie: $_"
                Write-IntuneLog -Message $errorMsg -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                Send-IntuneAlert -Message $errorMsg -Severity Error -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
                return $false
            }
        }
        else {
            $warningMsg = "7-Zip nie je nainštalovaný, asociáciu .zip nie je možné nastaviť"
            Write-IntuneLog -Message $warningMsg -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
            Send-IntuneAlert -Message $warningMsg -Severity Warning -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
            return $false
        }
    }
    
    # Hlavný proces remediation
    Write-IntuneLog -Message "Spúšťam hlavný remediation proces..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    
    # 1. Odinštalovať WinRAR
    $uninstallResult = Uninstall-WinRAR
    
    # 2. Nastaviť asociáciu .zip
    $associationResult = Set-ZipAssociation
    
    # 3. Reštartovať Explorer pre aplikovanie zmien
    Write-IntuneLog -Message "Reštartujem Explorer pre aplikovanie zmien..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process explorer.exe -WindowStyle Hidden
        Write-IntuneLog -Message "Explorer reštartovaný" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    }
    catch {
        Write-IntuneLog -Message "Nepodarilo sa reštartovať Explorer: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    }
    
    # 4. Výsledková správa
    $summaryMessage = "Remediation dokončená - "
    $summaryMessage += "WinRAR odinštalovaný: " + ($uninstallResult | Where-Object { $_.Status -eq "Success" }).Count + " z " + $uninstallResult.Count + ", "
    $summaryMessage += "Asociácia .zip: " + $(if ($associationResult) { "Úspešne nastavená" } else { "Nenastavená" })
    
    Write-IntuneLog -Message $summaryMessage -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    Write-IntuneLog -Message "=== KONIEC WinRAR Remediation skriptu ===" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    
    # Uprata staré logy
    Clear-OldLogs -LogDirectory "C:\TaurisIT\Log\Winrar" -RetentionDays 30
    
    exit 0
}
catch {
    $errorMsg = "Kritická chyba v remediation skripte: $_"
    Write-IntuneLog -Message $errorMsg -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    Send-IntuneAlert -Message $errorMsg -Severity Critical -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
    exit 1
}