# AD Revizia - S pouzitim specifickeho domenoveho uctu
# Vyzaduje: ActiveDirectory modul a ImportExcel modul

# Kontrola a instalacia potrebnych modulov
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "ActiveDirectory modul nie je nainstalovany!" -ForegroundColor Red
    Write-Host "Spustite: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    exit
}

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "ImportExcel modul nie je nainstalovany. Instalujem..." -ForegroundColor Yellow
    Install-Module -Name ImportExcel -Force -Scope CurrentUser -Confirm:$false
}

Import-Module ActiveDirectory
Import-Module ImportExcel

# Nastavenie prihlasovacich udajov
$domainUser = "tauris\adminfindrik"
$credential = Get-Credential -Message "Zadajte heslo pre domenovy ucet $domainUser" -UserName $domainUser

if (-not $credential) {
    Write-Host "Nie je zadane heslo! Skript sa ukoncuje." -ForegroundColor Red
    exit
}

Write-Host "Pouzivam domenovy ucet: $domainUser" -ForegroundColor Cyan

# Testovanie pripojenia k domene
try {
    $testComputer = Get-ADComputer -Filter "Name -like '*'" -Credential $credential -ResultSetSize 1 -ErrorAction Stop
    Write-Host "Uspesne pripojenie k Active Directory" -ForegroundColor Green
}
catch {
    Write-Host "Chyba pri pripojeni k Active Directory: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Nastavenie vystupneho suboru
$outputPath = "C:\Temp\AD_Revizia_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
$tempFolder = Split-Path $outputPath
if (-not (Test-Path $tempFolder)) {
    New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
}

Write-Host "Zacinam reviziu Active Directory..." -ForegroundColor Green
Write-Host "Vystupny subor: $outputPath" -ForegroundColor Cyan

# Funkcia pre kontrolu vynechanej OU
function Test-ExcludedOU {
    param($DistinguishedName)
    
    $dnLower = $DistinguishedName.ToLower()
    
    # Zoznam vynechanych OU
    $excludedOUs = @(
        'ou=disabled accounts,dc=tauris,dc=local',
        'ou=disabled,ou=obchodny partner,ou=resources,ou=hq tg,dc=tauris,dc=local'
    )
    
    # Kontrola presnych OU
    foreach ($ou in $excludedOUs) {
        if ($dnLower -like "*$ou*") {
            return $true
        }
    }
    
    # Kontrola OU zacinajucich na "zmaz"
    if ($dnLower -match 'ou=zmaz') {
        return $true
    }
    
    # Kontrola akejkolvek OU obsahujucej "disabled"
    if ($dnLower -match 'ou=.*disabled') {
        return $true
    }
    
    return $false
}

# Funkcia pre detekciu servisnych uctov
function Test-ServiceAccount {
    param($User)
    
    $samAccountName = $User.SamAccountName.ToLower()
    $distinguishedName = $User.DistinguishedName.ToLower()
    
    # Servisne ucty podla mena
    $servicePatterns = @('svc', 'srv', 'service', 'admin', 'backup', 'sql', 'iis', 'app')
    
    foreach ($pattern in $servicePatterns) {
        if ($samAccountName -like "*$pattern*") {
            return $true
        }
    }
    
    # Servisne ucty podla OU
    $serviceOUPatterns = @('ou=service', 'ou=admin', 'ou=servisne')
    foreach ($ouPattern in $serviceOUPatterns) {
        if ($distinguishedName -like "*$ouPattern*") {
            return $true
        }
    }
    
    return $false
}

# Funkcia pre detekciu typu pocitaca
function Get-ComputerType {
    param($OperatingSystem)
    
    if ([string]::IsNullOrEmpty($OperatingSystem)) {
        return 'Neznamy'
    }
    
    $osLower = $OperatingSystem.ToLower()
    
    if ($osLower -match 'server') {
        return 'Server'
    }
    elseif ($osLower -match 'windows 10|windows 11|windows 7|windows 8') {
        return 'Desktop'
    }
    else {
        return 'Iny'
    }
}

# Ziskanie pouzivatelskych uctov s pouzitim credentialov
Write-Host "`nZyskavam pouzivatelske ucty..." -ForegroundColor Yellow
try {
    $allUsers = Get-ADUser -Filter * -Properties Name, SamAccountName, LastLogonDate, PasswordNeverExpires, Enabled, DistinguishedName, Description -Credential $credential
    
    # Rozdelenie na pouzivatelske a servisne ucty (s filtrom vynechanych OU)
    $serviceUsers = @()
    $regularUsers = @()
    $excludedCount = 0

    foreach ($user in $allUsers) {
        # Preskocit vynechane OU
        if (Test-ExcludedOU -DistinguishedName $user.DistinguishedName) {
            $excludedCount++
            continue
        }
        
        $ou = $user.DistinguishedName -replace '^CN=.+?,(.*)', '$1'
        
        $userObject = [PSCustomObject]@{
            'Typ'                     = if (Test-ServiceAccount -User $user) { 'Servisny ucet' } else { 'Pouzivatel' }
            'Meno'                    = $user.Name
            'Prihlasovacie meno'      = $user.SamAccountName
            'Posledne prihlasenie'    = $user.LastLogonDate
            'Heslo nikdy neexspiruje' = $user.PasswordNeverExpires
            'Enabled'                 = $user.Enabled
            'OU'                      = $ou
            'Description'             = $user.Description
        }
        
        if (Test-ServiceAccount -User $user) {
            $serviceUsers += $userObject
        }
        else {
            $regularUsers += $userObject
        }
    }

    Write-Host "Najdenych pouzivatelov: $($regularUsers.Count)" -ForegroundColor Green
    Write-Host "Najdenych servisnych uctov: $($serviceUsers.Count)" -ForegroundColor Green
    Write-Host "Vynechanych uctov (disabled OU): $excludedCount" -ForegroundColor Yellow
}
catch {
    Write-Host "Chyba pri zyskani pouzivatelov: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Ziskanie pocitacovych uctov s pouzitim credentialov
Write-Host "`nZyskavam pocitacove ucty..." -ForegroundColor Yellow
try {
    $allComputers = Get-ADComputer -Filter * -Properties Name, OperatingSystem, LastLogonDate, Enabled, DistinguishedName, Description -Credential $credential
    
    # Roztriedenie pocitacov podla typu
    $desktopComputers = @()
    $serverComputers = @()
    $otherComputers = @()
    $excludedComputersCount = 0

    foreach ($computer in $allComputers) {
        # Preskocit vynechane OU
        if (Test-ExcludedOU -DistinguishedName $computer.DistinguishedName) {
            $excludedComputersCount++
            continue
        }
        
        $ou = $computer.DistinguishedName -replace '^CN=.+?,(.*)', '$1'
        $computerType = Get-ComputerType -OperatingSystem $computer.OperatingSystem
        
        $computerObject = [PSCustomObject]@{
            'Typ'                  = $computerType
            'Meno'                 = $computer.Name
            'Operacny system'      = $computer.OperatingSystem
            'Posledne prihlasenie' = $computer.LastLogonDate
            'Enabled'              = $computer.Enabled
            'OU'                   = $ou
            'Description'          = $computer.Description
        }
        
        switch ($computerType) {
            'Desktop' { $desktopComputers += $computerObject }
            'Server' { $serverComputers += $computerObject }
            default { $otherComputers += $computerObject }
        }
    }

    Write-Host "Najdenych desktopov: $($desktopComputers.Count)" -ForegroundColor Green
    Write-Host "Najdenych serverov: $($serverComputers.Count)" -ForegroundColor Green
    Write-Host "Najdenych ostatnych pocitacov: $($otherComputers.Count)" -ForegroundColor Green
    Write-Host "Vynechanych pocitacov (disabled OU): $excludedComputersCount" -ForegroundColor Yellow
}
catch {
    Write-Host "Chyba pri zyskani pocitacov: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Export do Excelu
Write-Host "`nExportujem do Excelu..." -ForegroundColor Yellow

$excelParams = @{
    Path         = $outputPath
    AutoSize     = $true
    AutoFilter   = $true
    FreezeTopRow = $true
    BoldTopRow   = $true
}

# Export jednotlivych listov
try {
    $regularUsers | Export-Excel @excelParams -WorksheetName "Pouzivatelia"
    $serviceUsers | Export-Excel @excelParams -WorksheetName "Servisne ucty"
    $desktopComputers | Export-Excel @excelParams -WorksheetName "Desktopy"
    $serverComputers | Export-Excel @excelParams -WorksheetName "Servery"
    
    if ($otherComputers.Count -gt 0) {
        $otherComputers | Export-Excel @excelParams -WorksheetName "Ostatne pocitace"
    }

    # Vytvorenie suhrnneho listu
    $summary = @(
        [PSCustomObject]@{
            'Kategoria' = 'Pouzivatelia celkom'
            'Pocet'     = $regularUsers.Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Pouzivatelia - aktivni'
            'Pocet'     = ($regularUsers | Where-Object { $_.Enabled -eq $true }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Pouzivatelia - neaktivni'
            'Pocet'     = ($regularUsers | Where-Object { $_.Enabled -eq $false }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Pouzivatelia - nikdy neprihlaseni'
            'Pocet'     = ($regularUsers | Where-Object { $null -eq $_.'Posledne prihlasenie' }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Pouzivatelia - heslo nikdy neexspiruje'
            'Pocet'     = ($regularUsers | Where-Object { $_.'Heslo nikdy neexspiruje' -eq $true }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servisne ucty celkom'
            'Pocet'     = $serviceUsers.Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servisne ucty - aktivne'
            'Pocet'     = ($serviceUsers | Where-Object { $_.Enabled -eq $true }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servisne ucty - neaktivne'
            'Pocet'     = ($serviceUsers | Where-Object { $_.Enabled -eq $false }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servisne ucty - heslo nikdy neexspiruje'
            'Pocet'     = ($serviceUsers | Where-Object { $_.'Heslo nikdy neexspiruje' -eq $true }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Desktopy celkom'
            'Pocet'     = $desktopComputers.Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Desktopy - aktivne'
            'Pocet'     = ($desktopComputers | Where-Object { $_.Enabled -eq $true }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Desktopy - neaktivne'
            'Pocet'     = ($desktopComputers | Where-Object { $_.Enabled -eq $false }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servery celkom'
            'Pocet'     = $serverComputers.Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servery - aktivne'
            'Pocet'     = ($serverComputers | Where-Object { $_.Enabled -eq $true }).Count
        },
        [PSCustomObject]@{
            'Kategoria' = 'Servery - neaktivne'
            'Pocet'     = ($serverComputers | Where-Object { $_.Enabled -eq $false }).Count
        }
    )
    
    if ($otherComputers.Count -gt 0) {
        $summary += [PSCustomObject]@{
            'Kategoria' = 'Ostatne pocitace celkom'
            'Pocet'     = $otherComputers.Count
        }
    }

    $summary | Export-Excel -Path $outputPath -WorksheetName "Suhrn" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -MoveToStart

    Write-Host "`nRevizia dokoncena!" -ForegroundColor Green
    Write-Host "Vystupny subor: $outputPath" -ForegroundColor Cyan

    # Zobrazenie statistik
    Write-Host "`nStatistiky:" -ForegroundColor Yellow
    $summary | Format-Table -AutoSize
}
catch {
    Write-Host "Chyba pri exporte do Excelu: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Otvorenie suboru
$openFile = Read-Host "`nChcete otvorit Excel subor? (A/N)"
if ($openFile -eq 'A' -or $openFile -eq 'a') {
    try {
        Invoke-Item $outputPath
    }
    catch {
        Write-Host "Nepodarilo sa otvorit subor: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nSkript dokonceny." -ForegroundColor Green