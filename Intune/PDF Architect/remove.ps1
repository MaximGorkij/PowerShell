#region === Configuration ===
$AppName = "PDF Architect 9"
$uninstallKeyPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

$logName = "IntuneScript"
$sourceName = "PDF Architect Remediation"
$logFile = "C:\TaurisIT\Log\PDFArchitectRemediation_$env:COMPUTERNAME.log"

# Import LogHelper module
Import-Module LogHelper -ErrorAction SilentlyContinue

# Create Event Log source if needed
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

#region === Functions ===
function FindUninstallEntries {
    $entries = @()
    foreach ($path in $uninstallKeyPaths) {
        try {
            $apps = Get-ChildItem $path -ErrorAction SilentlyContinue
            foreach ($app in $apps) {
                $props = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName -like "*$AppName*" -and $props.UninstallString) {
                    $entries += [PSCustomObject]@{
                        DisplayName     = $props.DisplayName
                        UninstallString = $props.UninstallString
                        RegistryPath    = $app.PSPath
                    }
                }
            }
        } catch {
            Write-CustomLog -Message "CHYBA pri pristupe k $path - $($_.Exception.Message)" `
                            -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    }
    return $entries
}

function Uninstall-App {
    param ([string]$Command)

    try {
        Write-CustomLog -Message "Spustam odinstalovanie: $Command" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Command /VERYSILENT /NORESTART`"" -Wait -PassThru
        Write-CustomLog -Message "Odinstalator skoncil s kodom: $($process.ExitCode)" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        return $process.ExitCode -eq 0
    } catch {
        Write-CustomLog -Message "CHYBA pri odinstalovani: $($_.Exception.Message)" `
                        -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        return $false
    }
}
#endregion

#region === Main Execution ===
Write-CustomLog -Message "=== Spustenie odstranenia '$AppName' ===" `
                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile

$uninstallEntries = FindUninstallEntries

if ($uninstallEntries.Count -gt 0) {
    $successCount = 0
    foreach ($entry in $uninstallEntries) {
        Write-CustomLog -Message "Najdene: $($entry.DisplayName) v $($entry.RegistryPath)" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        $result = Uninstall-App -Command $entry.UninstallString
        if ($result) { $successCount++ }
        Start-Sleep -Seconds 5
    }

    # Re-check after uninstall
    $remaining = FindUninstallEntries
    if ($remaining.Count -eq 0) {
        Write-CustomLog -Message "Vsetky instancie '$AppName' boli uspesne odstranene." `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        exit 0
    } else {
        Write-CustomLog -Message "Niektore instancie '$AppName' stale zostavaju." `
                        -Type "Warning" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        exit 1
    }
} else {
    Write-CustomLog -Message "'$AppName' nie je nainstalovany v systemovom ani uzivatelskom rozsahu." `
                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    exit 0
}
#endregion