$AppName = "PDF Architect 9"
$logName = "IntuneScript"
$sourceName = "PDF Architect Detection"
$logFile = "C:\TaurisIT\Log\PDFArchitectDetection_$env:COMPUTERNAME.log"

# Import modulu LogHelper
Import-Module LogHelper -ErrorAction SilentlyContinue

# Vytvor Event Log, ak neexistuje
if (-not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        New-EventLog -LogName $logName -Source $sourceName
        Write-CustomLog -Message "Vytvoreny Event Log '$logName' a zdroj '$sourceName'" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    } catch {
        Write-CustomLog -Message "CHYBA pri vytvarani Event Logu: $_" `
                        -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
}

# Registry paths to check
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

function IsAppInstalled {
    foreach ($path in $uninstallKeyPaths) {
        try {
            $apps = Get-ChildItem $path -ErrorAction SilentlyContinue
            foreach ($app in $apps) {
                $displayName = Get-ItemPropertyValue -Path $app.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                $uninstallString = Get-ItemPropertyValue -Path $app.PSPath -Name "UninstallString" -ErrorAction SilentlyContinue
                if ($displayName -like "*$AppName*" -and $uninstallString) {
                    Write-CustomLog -Message "Aplikacia najdena v: $path" `
                                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
                    return $true
                }
            }
        } catch {
            Write-CustomLog -Message "CHYBA pri pristupe k $path - $($_.Exception.Message)" `
                            -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    }
    return $false
}

# Výsledok
if (IsAppInstalled) {
    Write-CustomLog -Message "$AppName je nainstalovany." `
                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    exit 1
} else {
    Write-CustomLog -Message "$AppName nie je nainstalovany." `
                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    exit 0
}