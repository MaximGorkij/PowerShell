# Detekcia, či existuje aspoň jedna inštalácia Teams
$teamsPaths = @(
    "$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe",
    "$env:ProgramFiles(x86)\Microsoft\Teams\current\Teams.exe",
    "$env:ProgramFiles\Microsoft\Teams\current\Teams.exe"
    "C:\Program Files\WindowsApps\MSTeams*\ms-teams.exe"
)

foreach ($path in $teamsPaths) {
    if (Test-Path $path) { 
        write-host "tu je cesta - " $path
        exit 1 
    } # Teams nájdený → spustiť nápravu
}

if (Get-AppxPackage -Name "*Teams*") { 
    write-host "tu je AppX - " $path
    exit 1 
} # Teams AppX nájdený

exit 0 # Teams nenájdený, náprava nie je potrebná