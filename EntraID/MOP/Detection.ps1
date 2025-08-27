$taskName = "SetPasswordDaily"
$scriptPath = "C:\skript\SetPassMOP-v5.ps1"

$taskExists = $false
$scriptExists = $false

# Overenie ulohy
try {
    $uloha = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $taskExists = $true
} catch {
    $taskExists = $false
}

# Overenie skriptu
if (Test-Path $scriptPath) {
    $scriptExists = $true
}

# Výsledok
if ($taskExists -and $scriptExists) {
    Write-Output "Planovana uloha aj skript existuju."
    exit 0
} else {
    Write-Output "Uloha alebo skript chyba."
    exit 1
}