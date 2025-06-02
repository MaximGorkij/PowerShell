<#
.SYNOPSIS
    Odstráni súbory 'teams.exe' a ich priečinky LEN ak majú správny popis
.DESCRIPTION
    Prehľadá všetky používateľské profily, nájde súbory teams.exe,
    overí ich popis a zmaže LEN tie, ktoré majú popis "Microsoft Teams"
.PARAMETER FileName
    Názov hľadaného súboru (default: "teams.exe")
.PARAMETER ExpectedDescription
    Očakávaný popis súboru (default: "Microsoft Teams")
.PARAMETER WhatIf
    Testovací režim (nič nemaže)
.EXAMPLE
    # Testovací režim
    .\Remove-TeamsVerified.ps1 -WhatIf
    
    # Reálne vykonanie
    .\Remove-TeamsVerified.ps1
#>

param (
    [string]$FileName = "Update.exe",
    [string]$ExpectedDescription = "Microsoft Teams",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Funkcia na získanie popisu súboru
function Get-FileDescription {
    param([string]$FilePath)
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Get-Item $FilePath).DirectoryName)
        $file = $folder.ParseName((Get-Item $FilePath).Name)
        return $folder.GetDetailsOf($file, 34)  # 34 = File Description
    }
    catch {
        return $null
    }
}

# 1. Nájdenie všetkých používateľských profilov
$userProfiles = Get-ChildItem "C:\Users" -Directory | Where-Object {
    $_.Name -notin @("Public", "Default", "Administrator")
}

# 2. Hľadanie súborov vo všetkých profiloch
Write-Host "Hľadám súbor '$FileName' vo všetkých profiloch..." -ForegroundColor Cyan
$targetFiles = foreach ($profile in $userProfiles) {
    Get-ChildItem -Path $profile.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -eq $FileName }
}

if (-not $targetFiles) {
    Write-Host "Súbor nebol nájdený v žiadnom profile." -ForegroundColor Green
    exit 0
}

# 3. Spracovanie nájdených súborov
$processedCount = 0
$deletedCount = 0

foreach ($file in $targetFiles) {
    $filePath = $file.FullName
    $fileDescription = Get-FileDescription -FilePath $filePath
    
    Write-Host "`nNájdený súbor: $filePath" -ForegroundColor Yellow
    Write-Host "Popis súboru: '$fileDescription'" -ForegroundColor Yellow

    if ($fileDescription -ne $ExpectedDescription) {
        Write-Host "IGNORUJEM: Súbor nemá očakávaný popis." -ForegroundColor Red
        continue
    }

    $processedCount++
    $parentDir = $file.Directory.FullName

    # 4. Zmazanie priečinka
    if (-not $WhatIf) {
        try {
            Remove-Item -Path $parentDir -Recurse -Force -Confirm:$false
            Write-Host "Priečinok úspešne zmazaný." -ForegroundColor Green
            $deletedCount++
        }
        catch {
            Write-Host "Chyba pri mazaní priečinka: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[WHATIF] Zmazal by priečinok: $parentDir" -ForegroundColor Magenta
    }

    # 5. Odstránenie odkazov v Start menu
    $startMenuLocations = @(
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\*"
        "$($file.Directory.Root)Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\*"
    )

    foreach ($location in $startMenuLocations) {
        Get-ChildItem $location -Recurse -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Extension -match "\.lnk|\.url" } |
        ForEach-Object {
            $shell = New-Object -ComObject WScript.Shell
            try {
                $shortcut = $shell.CreateShortcut($_.FullName)
                
                if ($shortcut.TargetPath -eq $filePath -and $shortcut.Arguments -like "--process*") {
                    #write-host $shortcut.Arguments
                    if (-not $WhatIf) {
                        Remove-Item $_.FullName -Force -Confirm:$false
                        Write-Host "Odstránené: $($_.FullName)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[WHATIF] Odstránil by: $($_.FullName)" -ForegroundColor Magenta
                    }
                }
            }
            catch {
                Write-Host "Chyba pri spracovaní odkazu $($_.FullName): $_" -ForegroundColor DarkYellow
            }
        }
    }
}

# 6. Zhrnutie
Write-Host "`nZHRNUTIE:" -ForegroundColor Cyan
Write-Host "Nájdených súborov: $($targetFiles.Count)"
Write-Host "Spracovaných súborov (s popisom '$ExpectedDescription'): $processedCount"
Write-Host "Zmazaných priečinkov: $deletedCount"

if ($WhatIf) {
    Write-Host "`nREÁLNE ZMAZANIE: Spustite skript bez -WhatIf parametra" -ForegroundColor Yellow
}
else {
    Write-Host "`nVŠETKY ZMENY BOLI VYKONANÉ" -ForegroundColor Green
}