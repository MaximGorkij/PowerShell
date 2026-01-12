# WinRAR Detection Script - LogHelper verzia
try {
    # Import LogHelper modulu
    $modulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        # Inicializacia log systemu
        $initSuccess = Initialize-LogSystem -LogDirectory "C:\TaurisIT\Log" -EventSource "WinRAR_Detection" -RetentionDays 30
        if (-not $initSuccess) {
            Write-Warning "Nepodarilo sa inicializovat log system"
        }
    }
    else {
        Write-Warning "LogHelper modul nenajdeny v ceste: $modulePath"
    }
    
    # Log zaciatku detection
    Write-IntuneLog -Message "=== Zaciatok WinRAR Detection skriptu ===" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    
    # Kontrola ci WinRAR existuje
    $cestyWinRAR = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver"
    )
    
    $winrarNainstalovany = $false
    $verziaWinRAR = $null
    
    foreach ($cesta in $cestyWinRAR) {
        if (Test-Path $cesta) {
            $winrarNainstalovany = $true
            try {
                $verzia = (Get-ItemProperty -Path $cesta -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
                if ($verzia) {
                    $verziaWinRAR = $verzia
                    Write-IntuneLog -Message "WinRAR najdeny v registri: $cesta, verzia: $verzia" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
                }
            }
            catch {
                Write-IntuneLog -Message "WinRAR najdeny v registri: $cesta" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
            }
            break
        }
    }
    
    # Kontrola prostrednictvom Get-Package
    if (-not $winrarNainstalovany) {
        $baliky = Get-Package -Name "*WinRAR*" -ErrorAction SilentlyContinue
        if ($baliky) {
            $winrarNainstalovany = $true
            $verziaWinRAR = $baliky[0].Version
            Write-IntuneLog -Message "WinRAR najdeny cez Get-Package: $($baliky[0].Name), verzia: $verziaWinRAR" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        }
    }
    
    # Kontrola asociacie .zip
    $zipAsociacia = $null
    try {
        $zipAsociacia = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.zip\UserChoice" -Name ProgId -ErrorAction SilentlyContinue).ProgId
        Write-IntuneLog -Message "Aktualna .zip asociacia: $zipAsociacia" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    }
    catch {
        Write-IntuneLog -Message "Nepodarilo sa ziskat .zip asociaciu: $_" -Level WARN -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    }
    
    # Kontrola compliance
    if (-not $winrarNainstalovany -and $zipAsociacia -like "*7-Zip*") {
        Write-IntuneLog -Message "COMPLIANT: WinRAR nie je nainstalovany a .zip asociacia je nastavena na 7-Zip ($zipAsociacia)" -Level SUCCESS -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        Write-IntuneLog -Message "=== Koniec WinRAR Detection skriptu ===" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        Write-Output "Compliant"
        exit 0
    } 
    else {
        $dovery = @()
        if ($winrarNainstalovany) {
            $dovod = "WinRAR je nainstalovany"
            if ($verziaWinRAR) {
                $dovod += " (verzia: $verziaWinRAR)"
            }
            $dovery += $dovod
            Write-IntuneLog -Message "NON-COMPLIANT: $dovod" -Level WARN -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        }
        
        if (-not ($zipAsociacia -like "*7-Zip*")) {
            $dovod = ".zip asociacia nie je nastavena na 7-Zip (aktualne: $zipAsociacia)"
            $dovery += $dovod
            Write-IntuneLog -Message "NON-COMPLIANT: $dovod" -Level WARN -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        }
        
        Write-IntuneLog -Message "=== Koniec WinRAR Detection skriptu ===" -Level INFO -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
        Write-Output "Not Compliant"
        exit 1
    }
}
catch {
    $chybovaSprava = "Chyba v detection skripte: $_"
    Write-IntuneLog -Message $chybovaSprava -Level ERROR -EventSource "WinRAR_Detection" -LogFile "Winrar_Detection.log"
    Send-IntuneAlert -Message $chybovaSprava -Severity Error -EventSource "WinRAR_Detection" -LogFile "alerts.log"
    Write-Output "Not Compliant"
    exit 1
}