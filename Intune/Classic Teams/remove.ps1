# === Inicializacia ===
$computerName = $env:COMPUTERNAME
$logName = "IntuneScript"
$sourceName = "TeamsRemediation"
$logFile = "C:\TaurisIT\Log\TeamsRemediation_$computerName.log"

# === Import modulu LogHelper ===
Import-Module LogHelper -ErrorAction SilentlyContinue

# === Vytvor Event Log, ak neexistuje ===
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

Write-CustomLog -Message "=== Spustenie odstranenia Microsoft Teams Classic ===" `
                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile

# === 1. Odstranenie z pouzivatelskych profilov ===
try {
    $users = Get-ChildItem "C:\Users" -Exclude "Public","Default","Default User","All Users"
    foreach ($user in $users) {
        $base = "C:\Users\$($user.Name)\AppData"
        $paths = @(
            "$base\Local\Microsoft\Teams",
            "$base\Roaming\Microsoft\Teams",
            "$base\Local\SquirrelTemp",
            "$base\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Teams.lnk"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                try {
                    Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
                    Write-CustomLog -Message "Odstranene: $p" `
                                    -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
                } catch {
                    Write-CustomLog -Message "CHYBA pri odstraneni: $p - $_" `
                                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
                }
            }
        }
    }
} catch {
    Write-CustomLog -Message "CHYBA pri spracovani pouzivatelskych profilov - $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# === 2. Odinstalovanie cez Get-CimInstance ===
try {
    $teamsInstaller = Get-CimInstance -ClassName Win32_Product | Where-Object {
        $_.Name -like "*Teams*" -and $_.Name -like "*Machine-Wide Installer*"
    }
    if ($teamsInstaller) {
        foreach ($app in $teamsInstaller) {
            try {
                $app.Uninstall() | Out-Null
                Write-CustomLog -Message "Odinstalovane cez CIM: $($app.Name)" `
                                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
            } catch {
                Write-CustomLog -Message "CHYBA pri odinstalovani cez CIM: $($app.Name) - $_" `
                                -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
            }
        }
    } else {
        Write-CustomLog -Message "Machine-Wide Installer nebol najdeny cez CIM" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "CHYBA pri ziskavani CIM objektov - $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# === 3. Odstranenie systemovych priecinkov ===
$systemPaths = @(
    "C:\ProgramData\Teams",
    "C:\Program Files (x86)\Teams Installer"
)
foreach ($p in $systemPaths) {
    if (Test-Path $p) {
        try {
            Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
            Write-CustomLog -Message "Odstranene: $p" `
                            -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        } catch {
            Write-CustomLog -Message "CHYBA pri odstraneni: $p - $_" `
                            -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
        }
    }
}

# === 4. Odstranenie z Run registry kluca ===
try {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path "$runKey\Teams") {
        Remove-ItemProperty -Path $runKey -Name "Teams" -ErrorAction Stop
        Write-CustomLog -Message "Odstranene z Run registry kluca" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
} catch {
    Write-CustomLog -Message "CHYBA pri odstraneni z Run registry - $_" `
                    -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
}

# === 5. Ukoncenie procesu Teams (ak bezi) ===
$teamsProc = Get-Process -Name Teams -ErrorAction SilentlyContinue
if ($teamsProc) {
    try {
        Stop-Process -Name Teams -Force
        Write-CustomLog -Message "Proces Teams bol ukonceny" `
                        -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    } catch {
        Write-CustomLog -Message "CHYBA pri ukonceni procesu Teams - $_" `
                        -Type "Error" -EventSource $sourceName -EventLogName $logName -LogFileName $logFile
    }
}

# === Zaver ===
Write-CustomLog -Message "=== Odstranenie Microsoft Teams Classic dokoncene ===" `
                -EventSource $sourceName -EventLogName $logName -LogFileName $logFile