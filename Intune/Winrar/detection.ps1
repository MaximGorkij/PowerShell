# WinRAR Detection Script - LogHelper verzia
try {
    # Import LogHelper modulu
    $modulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        # Inicializácia log systému
        $initSuccess = Initialize-LogSystem -LogDirectory "C:\TaurisIT\Log" -EventSource "WinRAR_Detection" -RetentionDays 30
        if (-not $initSuccess) {
            Write-Warning "Nepodarilo sa inicializovať log systém"
        }
    }
    else {
        Write-Warning "LogHelper modul nenájdený v ceste: $modulePath"
    }
    
    # Log začiatku detection
    Write-IntuneLog -Message "=== Začiatok WinRAR Detection skriptu ===" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    
    # Kontrola či WinRAR existuje
    $winrarPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver"
    )
    
    $winrarInstalled = $false
    $winrarVersion = $null
    
    foreach ($path in $winrarPaths) {
        if (Test-Path $path) {
            $winrarInstalled = $true
            try {
                $version = (Get-ItemProperty -Path $path -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
                if ($version) {
                    $winrarVersion = $version
                    Write-IntuneLog -Message "WinRAR nájdený v registri: $path, verzia: $version" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
                }
            }
            catch {
                Write-IntuneLog -Message "WinRAR nájdený v registri: $path" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
            }
            break
        }
    }
    
    # Kontrola prostredníctvom Get-Package
    if (-not $winrarInstalled) {
        $packages = Get-Package -Name "*WinRAR*" -ErrorAction SilentlyContinue
        if ($packages) {
            $winrarInstalled = $true
            $winrarVersion = $packages[0].Version
            Write-IntuneLog -Message "WinRAR nájdený cez Get-Package: $($packages[0].Name), verzia: $winrarVersion" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        }
    }
    
    # Kontrola asociácie .zip
    $zipAssociation = $null
    try {
        $zipAssociation = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.zip\UserChoice" -Name ProgId -ErrorAction SilentlyContinue).ProgId
        Write-IntuneLog -Message "Aktuálna .zip asociácia: $zipAssociation" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    }
    catch {
        Write-IntuneLog -Message "Nepodarilo sa získať .zip asociáciu: $_" -Level WARN -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    }
    
    # Kontrola compliance
    if (-not $winrarInstalled -and $zipAssociation -like "*7-Zip*") {
        Write-IntuneLog -Message "COMPLIANT: WinRAR nie je nainštalovaný a .zip asociácia je nastavená na 7-Zip ($zipAssociation)" -Level SUCCESS -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        Write-IntuneLog -Message "=== Koniec WinRAR Detection skriptu ===" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        Write-Output "Compliant"
        exit 0
    } 
    else {
        $reasons = @()
        if ($winrarInstalled) {
            $reason = "WinRAR je nainštalovaný"
            if ($winrarVersion) {
                $reason += " (verzia: $winrarVersion)"
            }
            $reasons += $reason
            Write-IntuneLog -Message "NON-COMPLIANT: $reason" -Level WARN -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        }
        
        if (-not ($zipAssociation -like "*7-Zip*")) {
            $reason = ".zip asociácia nie je nastavená na 7-Zip (aktuálne: $zipAssociation)"
            $reasons += $reason
            Write-IntuneLog -Message "NON-COMPLIANT: $reason" -Level WARN -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        }
        
        Write-IntuneLog -Message "=== Koniec WinRAR Detection skriptu ===" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        Write-Output "Not Compliant"
        exit 1
    }
}
catch {
    $errorMsg = "Chyba v detection skripte: $_"
    Write-IntuneLog -Message $errorMsg -Level ERROR -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    Send-IntuneAlert -Message $errorMsg -Severity Error -EventSource "WinRAR_Detection" -LogFile "alerts.log"
    Write-Output "Not Compliant"
    exit 1
}