# WinRAR Remediation Script - LogHelper verzia
param()

try {
    # Import LogHelper modulu
    $modulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        # Inicializacia log systemu
        $initSuccess = Initialize-LogSystem -LogDirectory "C:\TaurisIT\Log\Winrar" -EventSource "WinRAR_Remediation" -RetentionDays 30
        if (-not $initSuccess) {
            Write-Warning "Nepodarilo sa inicializovat log system"
        }
    }
    else {
        Write-Warning "LogHelper modul nenajdeny v ceste: $modulePath"
        # Vytvorit adresar aspon pre zakladne logy
        New-Item -Path "C:\TaurisIT\Log\Winrar" -ItemType Directory -Force | Out-Null
    }
    
    # Log zaciatku remediation
    Write-IntuneLog -Message "=== ZACIATOK WinRAR Remediation skriptu ===" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    
    function Remove-WinRAR {
        Write-IntuneLog -Message "Spustam odinstalaciu WinRAR..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        $vysledkyOdinstalacie = @()
        
        # 1. Odinstalacia pomocou msiexec (pre MSI instalacie)
        $registryCesty = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($cesta in $registryCesty) {
            $aplikacie = Get-ItemProperty -Path $cesta -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*WinRAR*" }
            
            foreach ($app in $aplikacie) {
                $nazovApp = $app.DisplayName
                $verziaApp = $app.DisplayVersion
                $odinstalacnyRetazec = $app.UninstallString
                $tichyOdinstalacnyRetazec = $app.QuietUninstallString
                
                Write-IntuneLog -Message "Najdeny WinRAR: $nazovApp (verzia: $verziaApp)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                try {
                    if ($tichyOdinstalacnyRetazec) {
                        # Ticha odinstalacia
                        $odinstalacnyPrikaz = $tichyOdinstalacnyRetazec
                        Write-IntuneLog -Message "Pouzivam quiet uninstall string: $odinstalacnyPrikaz" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        
                        if ($odinstalacnyPrikaz -match 'MsiExec\.exe') {
                            $argumenty = "/x " + ($odinstalacnyPrikaz -split ' ')[1] + " /quiet /norestart"
                            Start-Process "MsiExec.exe" -ArgumentList $argumenty -Wait -NoNewWindow
                        }
                        else {
                            # Standardny uninstall string
                            Start-Process cmd.exe -ArgumentList "/c `"$odinstalacnyPrikaz`" /S" -Wait -NoNewWindow
                        }
                    }
                    elseif ($odinstalacnyRetazec) {
                        $odinstalacnyPrikaz = $odinstalacnyRetazec
                        Write-IntuneLog -Message "Pouzivam uninstall string: $odinstalacnyPrikaz" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        
                        # Pridanie parametrov pre tichu odinstalaciu ak este nie su pritomne
                        if ($odinstalacnyPrikaz -match '\.exe' -and $odinstalacnyPrikaz -notmatch '/S|/SILENT|/VERYSILENT|/quiet') {
                            $odinstalacnyPrikaz += " /S"
                        }
                        
                        Start-Process cmd.exe -ArgumentList "/c `"$odinstalacnyPrikaz`"" -Wait -NoNewWindow
                    }
                    else {
                        # Ak neexistuje uninstall string, skusit manualnu odinstalaciu
                        Write-IntuneLog -Message "Ziaden uninstall string, skusam manualnu odinstalaciu pre: $nazovApp" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        
                        # Pokus o odinstalaciu pomocou GUID
                        if ($app.PSChildName -match '^{[A-F0-9-]+}$') {
                            $guid = $app.PSChildName
                            Start-Process "msiexec.exe" -ArgumentList "/x $guid /quiet /norestart" -Wait -NoNewWindow
                        }
                    }
                    
                    $vysledkyOdinstalacie += @{
                        Nazov  = $nazovApp
                        Verzia = $verziaApp
                        Stav   = "Success"
                        Metoda = "Registry"
                    }
                    
                    Write-IntuneLog -Message "Odinstalacia spustena pre: $nazovApp" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    # Kratka prestavka medzi odinstalaciami
                    Start-Sleep -Seconds 3
                }
                catch {
                    $chybovaSprava = "Chyba pri odinstalacii $nazovApp $_"
                    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    $vysledkyOdinstalacie += @{
                        Nazov  = $nazovApp
                        Verzia = $verziaApp
                        Stav   = "Failed"
                        Metoda = "Registry"
                        Chyba  = $_.Exception.Message
                    }
                }
            }
        }
        
        # 2. Odinstalacia pomocou Get-Package (pre moderne instalacie)
        try {
            $baliky = Get-Package -Name "*WinRAR*" -ErrorAction SilentlyContinue
            foreach ($balik in $baliky) {
                # Skontrolovat ci uz nebola odinstalovana cez registry
                $uzOdinstalovane = $vysledkyOdinstalacie | Where-Object { $_.Nazov -like "*$($balik.Name)*" -and $_.Stav -eq "Success" }
                if ($uzOdinstalovane) {
                    Write-IntuneLog -Message "WinRAR uz bol odinstalovany cez registry: $($balik.Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    continue
                }
                
                Write-IntuneLog -Message "Odinstalovavam prostrednictvom PackageManagement: $($balik.Name) (verzia: $($balik.Version))" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                try {
                    $null = $balik | Uninstall-Package -Force -ErrorAction SilentlyContinue
                    
                    $vysledkyOdinstalacie += @{
                        Nazov  = $balik.Name
                        Verzia = $balik.Version
                        Stav   = "Success"
                        Metoda = "PackageManagement"
                    }
                    
                    Write-IntuneLog -Message "Odinstalovane cez PackageManagement: $($balik.Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
                catch {
                    $chybovaSprava = "Chyba pri odinstalacii $($balik.Name) cez PackageManagement: $_"
                    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    $vysledkyOdinstalacie += @{
                        Nazov  = $balik.Name
                        Verzia = $balik.Version
                        Stav   = "Failed"
                        Metoda = "PackageManagement"
                        Chyba  = $_.Exception.Message
                    }
                }
            }
        }
        catch {
            Write-IntuneLog -Message "Chyba pri praci s PackageManagement: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        }
        
        # 3. Odinstalacia pomocou WMI (Windows Management Instrumentation)
        try {
            $wmiAplikacie = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*WinRAR*" }
            foreach ($app in $wmiAplikacie) {
                Write-IntuneLog -Message "Najdeny WinRAR cez WMI: $($app.Name) (verzia: $($app.Version))" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                try {
                    $vysledok = $app.Uninstall()
                    if ($vysledok.ReturnValue -eq 0) {
                        $vysledkyOdinstalacie += @{
                            Nazov  = $app.Name
                            Verzia = $app.Version
                            Stav   = "Success"
                            Metoda = "WMI"
                        }
                        Write-IntuneLog -Message "Odinstalovane cez WMI: $($app.Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                    else {
                        throw "WMI Uninstall failed with code: $($vysledok.ReturnValue)"
                    }
                }
                catch {
                    $chybovaSprava = "Chyba pri odinstalacii $($app.Name) cez WMI: $_"
                    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    $vysledkyOdinstalacie += @{
                        Nazov  = $app.Name
                        Verzia = $app.Version
                        Stav   = "Failed"
                        Metoda = "WMI"
                        Chyba  = $_.Exception.Message
                    }
                }
            }
        }
        catch {
            Write-IntuneLog -Message "Chyba pri praci s WMI: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        }
        
        # 4. Odinstalacia pomocou CIM (Common Information Model) - moderna alternativa k WMI
        try {
            $cimAplikacie = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "*WinRAR*" }
            foreach ($app in $cimAplikacie) {
                Write-IntuneLog -Message "Najdeny WinRAR cez CIM: $($app.Name) (verzia: $($app.Version))" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                try {
                    $vysledok = Invoke-CimMethod -InputObject $app -MethodName Uninstall
                    if ($vysledok.ReturnValue -eq 0) {
                        $vysledkyOdinstalacie += @{
                            Nazov  = $app.Name
                            Verzia = $app.Version
                            Stav   = "Success"
                            Metoda = "CIM"
                        }
                        Write-IntuneLog -Message "Odinstalovane cez CIM: $($app.Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                    else {
                        throw "CIM Uninstall failed with code: $($vysledok.ReturnValue)"
                    }
                }
                catch {
                    $chybovaSprava = "Chyba pri odinstalacii $($app.Name) cez CIM: $_"
                    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    $vysledkyOdinstalacie += @{
                        Nazov  = $app.Name
                        Verzia = $app.Version
                        Stav   = "Failed"
                        Metoda = "CIM"
                        Chyba  = $_.Exception.Message
                    }
                }
            }
        }
        catch {
            Write-IntuneLog -Message "Chyba pri praci s CIM: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        }
        
        # 5. Odinstalacia pomocou WMIC (Command Line)
        try {
            $wmicVystup = wmic product where "name like '%WinRAR%'" get name, version 2>$null
            if ($wmicVystup -match 'WinRAR') {
                Write-IntuneLog -Message "Najdeny WinRAR cez WMIC, spustam odinstalaciu..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                
                # WMIC odinstalacia
                $wmicVysledok = wmic product where "name like '%WinRAR%'" call uninstall 2>$null
                
                if ($LASTEXITCODE -eq 0) {
                    $vysledkyOdinstalacie += @{
                        Nazov  = "WinRAR (WMIC)"
                        Verzia = ""
                        Stav   = "Success"
                        Metoda = "WMIC"
                    }
                    Write-IntuneLog -Message "Odinstalovane cez WMIC" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
                else {
                    throw "WMIC uninstall failed with exit code: $LASTEXITCODE"
                }
            }
        }
        catch {
            Write-IntuneLog -Message "Chyba pri praci s WMIC: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        }
        
        # 6. Manualna odinstalacia - ak predchadzajuce metody zlyhali
        if (($vysledkyOdinstalacie | Where-Object { $_.Stav -eq "Success" }).Count -eq 0) {
            Write-IntuneLog -Message "Ziaden automaticka metoda nebola uspesna, skusam manualnu odinstalaciu..." -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
            
            # A. Pokus o najdenie a spustenie uninstall.exe
            $mozneCesty = @(
                "${env:ProgramFiles}\WinRAR\uninstall.exe",
                "${env:ProgramFiles(x86)}\WinRAR\uninstall.exe",
                "$env:LOCALAPPDATA\Programs\WinRAR\uninstall.exe",
                "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\WinRAR\Uninstall WinRAR.lnk"
            )
            
            foreach ($cesta in $mozneCesty) {
                if (Test-Path $cesta) {
                    Write-IntuneLog -Message "Najdeny manualny uninstall: $cesta" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    try {
                        if ($cesta.EndsWith('.lnk')) {
                            # Spracovanie shortcutu
                            $shell = New-Object -ComObject WScript.Shell
                            $shortcut = $shell.CreateShortcut($cesta)
                            $cielovaCesta = $shortcut.TargetPath
                            $argumenty = $shortcut.Arguments
                            
                            if ($cielovaCesta -and (Test-Path $cielovaCesta)) {
                                Start-Process $cielovaCesta -ArgumentList "/S" -Wait -NoNewWindow
                                $vysledkyOdinstalacie += @{
                                    Nazov  = "WinRAR (Manual)"
                                    Verzia = ""
                                    Stav   = "Success"
                                    Metoda = "Manual_Shortcut"
                                }
                                break
                            }
                        }
                        else {
                            # Priamy exe subor
                            Start-Process $cesta -ArgumentList "/S" -Wait -NoNewWindow
                            $vysledkyOdinstalacie += @{
                                Nazov  = "WinRAR (Manual)"
                                Verzia = ""
                                Stav   = "Success"
                                Metoda = "Manual_EXE"
                            }
                            break
                        }
                    }
                    catch {
                        Write-IntuneLog -Message "Chyba pri manualnej odinstalacii: $_" -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                }
            }
        }
        
        # 7. Silova odinstalacia pomocou Process Killer a File Remover
        # Toto je posledna moznost, pouziva sa iba ak vsetky ostatne metody zlyhali
        $potrebnaSilovaOdinstalacia = ($vysledkyOdinstalacie | Where-Object { $_.Stav -eq "Failed" }).Count -gt 0 -and 
        ($vysledkyOdinstalacie | Where-Object { $_.Stav -eq "Success" }).Count -eq 0
        
        if ($potrebnaSilovaOdinstalacia) {
            Write-IntuneLog -Message "Vsetky metody zlyhali, spustam silovu odinstalaciu..." -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
            
            # A. Zastavit vsetky WinRAR procesy
            $winrarProcesy = Get-Process | Where-Object { 
                $_.ProcessName -like "*winrar*" -or 
                $_.ProcessName -like "*rar*" -or
                $_.MainWindowTitle -like "*WinRAR*"
            }
            
            foreach ($proces in $winrarProcesy) {
                try {
                    Stop-Process -Id $proces.Id -Force -ErrorAction SilentlyContinue
                    Write-IntuneLog -Message "Zastaveny proces: $($proces.ProcessName) (ID: $($proces.Id))" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    Start-Sleep -Seconds 1
                }
                catch {
                    Write-IntuneLog -Message "Nepodarilo sa zastavit proces $($proces.ProcessName): $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
            }
            
            # B. Odstranenie zaznamov z registra
            $registryZaznamy = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver",
                "HKLM:\SOFTWARE\WinRAR",
                "HKLM:\SOFTWARE\WOW6432Node\WinRAR",
                "HKCU:\Software\WinRAR"
            )
            
            foreach ($regCesta in $registryZaznamy) {
                if (Test-Path $regCesta) {
                    try {
                        Remove-Item -Path $regCesta -Recurse -Force -ErrorAction SilentlyContinue
                        Write-IntuneLog -Message "Odstraneny registry zaznam: $regCesta" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                    catch {
                        Write-IntuneLog -Message "Nepodarilo sa odstranit registry $regCesta $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                }
            }
            
            # C. Vymazanie zvyskovych suborov a priecinkov
            $winrarPriecinky = @(
                "${env:ProgramFiles}\WinRAR",
                "${env:ProgramFiles(x86)}\WinRAR",
                "$env:LOCALAPPDATA\WinRAR",
                "$env:APPDATA\WinRAR",
                "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\WinRAR",
                "$env:PUBLIC\Desktop\WinRAR.lnk",
                "$env:USERPROFILE\Desktop\WinRAR.lnk"
            )
            
            foreach ($priecinok in $winrarPriecinky) {
                if (Test-Path $priecinok) {
                    try {
                        Remove-Item -Path $priecinok -Recurse -Force -ErrorAction SilentlyContinue
                        Write-IntuneLog -Message "Odstraneny priecinok: $priecinok" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                    catch {
                        Write-IntuneLog -Message "Nepodarilo sa odstranit $priecinok $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                }
            }
            
            # D. Odstranenie file associations
            $typSuborov = @(".rar", ".zip", ".7z", ".tar", ".gz", ".bz2")
            foreach ($ext in $typSuborov) {
                try {
                    $asociacnaCesta = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
                    if (Test-Path $asociacnaCesta) {
                        $progId = (Get-ItemProperty -Path $asociacnaCesta -Name "ProgId" -ErrorAction SilentlyContinue).ProgId
                        if ($progId -like "*WinRAR*") {
                            Remove-Item -Path $asociacnaCesta -Recurse -Force -ErrorAction SilentlyContinue
                            Write-IntuneLog -Message "Odstranena asociacia pre $ext" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        }
                    }
                }
                catch {
                    # Ignorovat chyby pri odstranovani asociacii
                }
            }
            
            $vysledkyOdinstalacie += @{
                Nazov  = "WinRAR (Force)"
                Verzia = ""
                Stav   = "Success"
                Metoda = "Force_Removal"
            }
            
            Write-IntuneLog -Message "Silova odinstalacia dokoncena" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        }
        
        # Logovanie vysledkov odinstalacie
        $pocetUspesnych = ($vysledkyOdinstalacie | Where-Object { $_.Stav -eq "Success" }).Count
        $pocetZlyhanych = ($vysledkyOdinstalacie | Where-Object { $_.Stav -eq "Failed" }).Count
        
        Write-IntuneLog -Message "Odinstalacia WinRAR dokoncena - Uspesne: $pocetUspesnych, Zlyhane: $pocetZlyhanych" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        # Detaily o metodach
        $zhrnutieMetod = $vysledkyOdinstalacie | Group-Object Metoda | ForEach-Object {
            "$($_.Name): $($_.Count) (Uspesne: $(($_.Group | Where-Object { $_.Stav -eq 'Success' }).Count))"
        }
        Write-IntuneLog -Message "Pouzite metody: $($zhrnutieMetod -join ', ')" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        if ($pocetZlyhanych -gt 0) {
            $zlyhaneAplikacie = $vysledkyOdinstalacie | Where-Object { $_.Stav -eq "Failed" } | ForEach-Object { "$($_.Nazov) ($($_.Metoda))" }
            $upozornenie = "Niektore WinRAR instalacie sa nepodarilo odinstalovat: $($zlyhaneAplikacie -join ', ')"
            Send-IntuneAlert -Message $upozornenie -Severity Warning -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
        }
        
        return $vysledkyOdinstalacie
    }
    
    function Set-ZipAsociaciu {
        Write-IntuneLog -Message "Nastavujem asociaciu .zip na 7-Zip..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
        
        # Kontrola ci je 7-Zip nainstalovany
        $cesty7Zip = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip"
        )
        
        $je7ZipNainstalovany = $false
        $cesta7Zip = $null
        
        foreach ($cesta in $cesty7Zip) {
            if (Test-Path $cesta) {
                $je7ZipNainstalovany = $true
                $cesta7Zip = $cesta
                Write-IntuneLog -Message "7-Zip najdeny v registri: $cesta" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                break
            }
        }
        
        if (-not $je7ZipNainstalovany) {
            # Skusit najst 7-Zip pomocou Get-Package
            $baliky = Get-Package -Name "*7-Zip*" -ErrorAction SilentlyContinue
            if ($baliky) {
                $je7ZipNainstalovany = $true
                Write-IntuneLog -Message "7-Zip najdeny cez PackageManagement: $($baliky[0].Name)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
            }
        }
        
        if ($je7ZipNainstalovany) {
            try {
                # Nastavenie asociacie pomocou dism (Windows 10/11)
                $cestaExportu = "$env:TEMP\assoc_backup_$(Get-Date -Format 'yyyyMMddHHmmss').xml"
                dism /online /Export-DefaultAppAssociations:$cestaExportu 2>&1 | Out-Null
                
                if (Test-Path $cestaExportu) {
                    Write-IntuneLog -Message "Exportovane aktualne asociacie do: $cestaExportu" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                }
                
                # Pokus o nastavenie cez registry
                $asociacnaCesta = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.zip\UserChoice"
                
                # Ziskanie aktualnej asociacie
                $aktualnaAsociacia = $null
                try {
                    $aktualnaAsociacia = (Get-ItemProperty -Path $asociacnaCesta -Name "ProgId" -ErrorAction SilentlyContinue).ProgId
                }
                catch {
                    # Ak neexistuje, ignorujeme
                }
                
                # Skontrolujeme ktore ProgId je dostupne pre 7-Zip
                $dostupneProgIds = @("7-Zip.zip", "7zFM.zip", "7-Zip.7z")
                $vybrateProgId = $null
                
                foreach ($progId in $dostupneProgIds) {
                    $testovaciaCesta = "HKCR:\$progId"
                    if (Test-Path $testovaciaCesta) {
                        $vybrateProgId = $progId
                        break
                    }
                }
                
                if (-not $vybrateProgId) {
                    # Default na 7-Zip.zip
                    $vybrateProgId = "7-Zip.zip"
                }
                
                # Nastavenie asociacie
                try {
                    if (-not (Test-Path $asociacnaCesta)) {
                        New-Item -Path $asociacnaCesta -Force | Out-Null
                    }
                    
                    New-ItemProperty -Path $asociacnaCesta -Name "ProgId" -Value $vybrateProgId -PropertyType String -Force | Out-Null
                    Write-IntuneLog -Message "Asociacia .zip nastavena na $vybrateProgId v registry (predchadzajuca: $aktualnaAsociacia)" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    
                    # Alternativne cez ftype a assoc (pre starsie Windows)
                    try {
                        # Najdi cestu k 7zFM.exe
                        $cesta7z = "${env:ProgramFiles}\7-Zip\7zFM.exe"
                        if (-not (Test-Path $cesta7z)) {
                            $cesta7z = "${env:ProgramFiles(x86)}\7-Zip\7zFM.exe"
                        }
                        
                        if (Test-Path $cesta7z) {
                            cmd /c "ftype $vybrateProgId=`"$cesta7z`" `"%1`"" 2>&1 | Out-Null
                            cmd /c "assoc .zip=$vybrateProgId" 2>&1 | Out-Null
                            Write-IntuneLog -Message "Asociacia nastavena cez assoc/ftype" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                        }
                    }
                    catch {
                        Write-IntuneLog -Message "Nepodarilo sa nastavit asociaciu cez assoc: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    }
                    
                    Write-IntuneLog -Message "Asociacia .zip bola uspesne nastavena na 7-Zip ($vybrateProgId)" -Level SUCCESS -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    return $true
                }
                catch {
                    $chybovaSprava = "Chyba pri nastavovani asociacie cez registry: $_"
                    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                    Send-IntuneAlert -Message $chybovaSprava -Severity Error -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
                    return $false
                }
            }
            catch {
                $chybovaSprava = "Chyba pri nastavovani asociacie: $_"
                Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
                Send-IntuneAlert -Message $chybovaSprava -Severity Error -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
                return $false
            }
        }
        else {
            $upozornenie = "7-Zip nie je nainstalovany, asociaciu .zip nie je mozne nastavit"
            Write-IntuneLog -Message $upozornenie -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
            Send-IntuneAlert -Message $upozornenie -Severity Warning -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
            return $false
        }
    }
    
    # Hlavny proces remediation
    Write-IntuneLog -Message "Spustam hlavny remediation proces..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    
    # 1. Odinstalovat WinRAR
    $vysledokOdinstalacie = Remove-WinRAR
    
    # 2. Nastavit asociaciu .zip
    $vysledokAsociacie = Set-ZipAsociaciu
    
    # 3. Restartovat Explorer pre aplikovanie zmien
    Write-IntuneLog -Message "Restartujem Explorer pre aplikovanie zmien..." -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process explorer.exe -WindowStyle Hidden
        Write-IntuneLog -Message "Explorer restartovany" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    }
    catch {
        Write-IntuneLog -Message "Nepodarilo sa restartovat Explorer: $_" -Level WARN -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    }
    
    # 4. Vysledkova sprava
    $zhrnutie = "Remediation dokoncena - "
    $zhrnutie += "WinRAR odinstalovany: " + ($vysledokOdinstalacie | Where-Object { $_.Stav -eq "Success" }).Count + " z " + $vysledokOdinstalacie.Count + ", "
    $zhrnutie += "Asociacia .zip: " + $(if ($vysledokAsociacie) { "Uspesne nastavena" } else { "Nenastavena" })
    
    Write-IntuneLog -Message $zhrnutie -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    Write-IntuneLog -Message "=== KONIEC WinRAR Remediation skriptu ===" -Level INFO -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    
    # Uprata stare logy
    Clear-OldLogs -LogDirectory "C:\TaurisIT\Log\Winrar" -RetentionDays 30
    
    exit 0
}
catch {
    $chybovaSprava = "Kriticka chyba v remediation skripte: $_"
    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Remediation" -LogFile "Winrar_Remediation.log"
    Send-IntuneAlert -Message $chybovaSprava -Severity Critical -EventSource "WinRAR_Remediation" -LogFile "alerts.log"
    exit 1
}