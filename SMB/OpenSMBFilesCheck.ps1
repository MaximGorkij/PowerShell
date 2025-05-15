$serverName = "FSKE21"
# Funkcia na získanie zoznamu otvorených súborov na vzdialenom serveri
function Get-OpenFiles {
    param (
        [string]$serverName
    )
    $openFiles = @()
    $sessions = Invoke-Command -ComputerName $serverName -ScriptBlock { Get-SmbOpenFile }
    foreach ($session in $sessions) {
        if ($session.ClientUserName -eq "Disconnected") {
            $openFiles += $session
        }
    }
    return $openFiles
}

# Funkcia na zatvorenie súboru na vzdialenom serveri
function Close-OpenFile {
    param (
        [string]$serverName,
        [Microsoft.Management.Infrastructure.CimInstance]$file
    )
    Invoke-Command -ComputerName $serverName -ScriptBlock { param($fileId) Close-SmbOpenFile -FileId $fileId -Force } -ArgumentList $file.FileId
    Write-Output "Súbor s ID $($file.FileId) na serveri $serverName bol zatvorený."
}

# Názov vzdialeného servera
#$serverName = "tvoj_server"

# Hlavný skript
try {
    while ($true) {
        $openFiles = Get-OpenFiles -serverName $serverName
        foreach ($file in $openFiles) {
            #Close-OpenFile -serverName $serverName -file $file
            write-host $file
        }
        Start-Sleep -Seconds 5  # Skontroluj stav každých 5 sekúnd
    }
} catch {
    Write-Output "Došlo k chybe: $_"
}
