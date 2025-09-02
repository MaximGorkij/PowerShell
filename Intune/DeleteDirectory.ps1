$folders = @("C:\Log", "C:\Skript")
$EventLogName = "IntuneScript"
$EventSource = "Delete folders"
$markerPath = "C:\ProgramData\IntuneScriptRan.txt"
$deletedSomething = $false

# Spustiť len raz
if (Test-Path $markerPath) {
    Write-Output "Script has already run. Exiting."
    return
}

# Zoznam existujúcich adresárov
$existingFolders = $folders | Where-Object { Test-Path $_ }

# Vytvor Event Log, ak je čo logovať
if ($existingFolders.Count -gt 0) {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        New-EventLog -LogName $EventLogName -Source $EventSource
    }

    foreach ($folder in $existingFolders) {
        try {
            Remove-Item -Path $folder -Recurse -Force
            $msg = "Deleted folder: $folder"
            Write-Output $msg
            Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType Information -EventId 1000 -Message $msg
            $deletedSomething = $true
        } catch {
            $errorMsg = "Failed to delete folder: $folder. Error: $_"
            Write-Output $errorMsg
            Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType Error -EventId 1001 -Message $errorMsg
        }
    }
} else {
    $msg = "No folders found to delete."
    Write-Output $msg
}

# Vytvor marker len ak sa niečo zmazalo
if ($deletedSomething) {
    New-Item -Path $markerPath -ItemType File -Force | Out-Null
    Write-Output "Marker file created: $markerPath"
} else {
    Write-Output "No folders were deleted. Marker not created."
}