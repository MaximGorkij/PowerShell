#region === Konfiguracia ===
#$AppName = "OCS Inventory Agent"
$expectedVersion = "2.11.0.1"
$exePath = "C:\Program Files (x86)\OCS Inventory Agent\OCSInventory.exe"

$logName = "IntuneScript"
$sourceName = "OCS Detection"
$logFile = "C:\TaurisIT\Log\OCSDetection_$env:COMPUTERNAME.log"

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
#endregion

#region === Detekcia ===
$detectedVersion = "0"

if (Test-Path $exePath) {
    try {
        $versionObj = Get-CimInstance -ClassName Win32_Product | Where-Object {
            $_.Vendor -like "OCS*" -or $_.Name -like "*OCS Inventory*"
        }
        if ($versionObj) {
            $detectedVersion = $versionObj.Version
            Write-CustomLog -Message "OCS Inventory detekovany. Verzia: $detectedVersion" `
                            -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        } else {
            Write-CustomLog -Message "OCS Inventory exe existuje, ale verzia nebola ziskana." `
                            -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    } catch {
        Write-CustomLog -Message "CHYBA pri ziskavani verzie OCS Inventory - $_" `
                        -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} else {
    Write-CustomLog -Message "OCSInventory.exe nebol najdeny na ceste: $exePath" `
                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}
#endregion

#region === Rozhodovacia logika ===
Write-Host $detectedVersion

if (($detectedVersion -ne $expectedVersion) -and ($detectedVersion -ne "0")) {
    Write-Host "je tu je, zmazat - $detectedVersion"
    Write-CustomLog -Message "OCS Inventory verzia $detectedVersion vyzaduje odstranenie." `
                    -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    exit 1
}

Write-CustomLog -Message "OCS Inventory nie je pritomny alebo verzia je akceptovatelna ($detectedVersion)" `
                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
exit 0
#endregion