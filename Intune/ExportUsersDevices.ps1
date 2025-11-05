#Requires -Version 5.1
#Requires -Modules Microsoft.Graph, ImportExcel

<#
.SYNOPSIS
Export pouzivatelov a zariadeni z Intune do Excelu s prehladom compliance.
.DESCRIPTION
Skript pouziva Microsoft Graph API na ziskanie zoznamu pouzivatelov a spravovanych zariadeni.
Data su spracovane do troch listov Excelu:
- Zariadenia (detailny prehlad)
- Statistiky pouzivatelov (sumar podla pouzivatelov)
- Sumar (celkove statistiky)
.PARAMETER ExportPath
Cesta k vyslednemu Excel suboru (.xlsx).
.PARAMETER AutoOpen
Ak je nastavene, otvori Excel po exporte.
.NOTES
Autor: Marek Findrik
Verzia: 2.4
Datum: 2025-10-28
#>

param(
    [string]$ExportPath = ".\Intune_Uzivatelia_Zariadenia_$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx",
    [switch]$AutoOpen = $true
)

# Nastavenie pre ladienie
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

Write-Host "=== Export Intune pouzivatelov a zariadeni ===" -ForegroundColor Cyan
Write-Host "Start: $(Get-Date)" -ForegroundColor Gray

# --- Overenie modulov ---
Write-Host "`n1. Kontrola modulov..." -ForegroundColor Cyan

$modules = @("Microsoft.Graph.Users", "Microsoft.Graph.DeviceManagement", "ImportExcel")
foreach ($m in $modules) {
    if (Get-Module -ListAvailable -Name $m) {
        Write-Host "   OK: Modul $m je nainstalovany" -ForegroundColor Green
    }
    else {
        Write-Host "   CHYBA: Modul $m nie je nainstalovany" -ForegroundColor Red
        Write-Host "   Spustite: Install-Module $m -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
}

try {
    Import-Module Microsoft.Graph.Users -Force -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -Force -ErrorAction Stop
    Import-Module ImportExcel -Force -ErrorAction Stop
    Write-Host "   Vsetky moduly uspesne nacitane" -ForegroundColor Green
}
catch {
    Write-Host "   CHYBA pri importe modulov: $_" -ForegroundColor Red
    exit 1
}

# --- Pripojenie k Microsoft Graph ---
Write-Host "`n2. Pripojenie k Microsoft Graph..." -ForegroundColor Cyan

try {
    # Odpoj ak uz sme pripojeny
    if (Get-MgContext) {
        Write-Host "   Uz som pripojeny, odpojujem sa..." -ForegroundColor Yellow
        Disconnect-MgGraph -ErrorAction SilentlyContinue
    }
    
    Write-Host "   Pripajam sa..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "User.Read.All", "DeviceManagementManagedDevices.Read.All", "DeviceManagementConfiguration.Read.All" -ErrorAction Stop
    
    $context = Get-MgContext
    Write-Host "   USPEŠNE pripojene k: $($context.Account)" -ForegroundColor Green
    Write-Host "   Tenant: $($context.TenantId)" -ForegroundColor Gray
}
catch {
    Write-Host "   CHYBA pri pripojovani: $_" -ForegroundColor Red
    exit 1
}

# --- Ziskanie pouzivatelov ---
Write-Host "`n3. Ziskanie pouzivatelov..." -ForegroundColor Cyan

try {
    Write-Host "   Ziskavam zoznam pouzivatelov..." -ForegroundColor Yellow
    $users = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AccountEnabled -ErrorAction Stop
    Write-Host "   OK: Nacitanych $($users.Count) pouzivatelov" -ForegroundColor Green
}
catch {
    Write-Host "   CHYBA pri ziskavani pouzivatelov: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

# --- Hash pre rychle parovanie ---
$userHash = @{}
foreach ($u in $users) { 
    $userHash[$u.Id] = $u 
}
Write-Host "   Hash pouzivatelov vytvoreny: $($userHash.Count) zaznamov" -ForegroundColor Gray

# --- Ziskanie zariadeni ---
Write-Host "`n4. Ziskanie zariadeni..." -ForegroundColor Cyan

try {
    Write-Host "   Ziskavam zoznam zariadeni..." -ForegroundColor Yellow
    $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
    Write-Host "   OK: Nacitanych $($devices.Count) zariadeni" -ForegroundColor Green
}
catch {
    Write-Host "   CHYBA pri ziskavani zariadeni: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

# --- Spracovanie zariadeni ---
Write-Host "`n5. Spracovanie zariadeni..." -ForegroundColor Cyan

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$totalDevices = $devices.Count
$current = 0
$currentDate = Get-Date

Write-Host "   Spracuvam $totalDevices zariadeni..." -ForegroundColor Yellow

foreach ($device in $devices) {
    $current++
    if ($current % 100 -eq 0) {
        Write-Host "   Spracovanych $current/$totalDevices zariadeni..." -ForegroundColor Gray
    }
    
    $user = $null
    if ($device.UserId -and $userHash.ContainsKey($device.UserId)) {
        $user = $userHash[$device.UserId]
    }

    $complianceReason = ""
    if ($device.ComplianceState -eq "noncompliant") {
        try {
            $compliancePolicies = Get-MgDeviceManagementManagedDeviceCompliancePolicyState -ManagedDeviceId $device.Id -ErrorAction SilentlyContinue
            $nonCompliantPolicies = $compliancePolicies | Where-Object { $_.State -eq "nonCompliant" }
            if ($nonCompliantPolicies) {
                $complianceReason = ($nonCompliantPolicies.DisplayName) -join "; "
            }
        }
        catch {
            $complianceReason = "Chyba pri nacitani detailov"
        }
    }

    # Vypocet dni od poslednej synchronizacie
    $daysSinceSync = $null
    if ($device.LastSyncDateTime) {
        $daysSinceSync = ($currentDate - $device.LastSyncDateTime).Days
    }

    $results.Add([PSCustomObject]@{
            'Pouzivatel'              = if ($user) { $user.DisplayName } else { "N/A" }
            'Email'                   = if ($user) { $user.UserPrincipalName } else { "N/A" }
            'Stav uctu'               = if ($user) {
                if ($user.AccountEnabled) { "Aktivny" } else { "Neaktivny" }
            }
            else { "N/A" }
            'Nazov zariadenia'        = $device.DeviceName
            'Operacny system'         = $device.OperatingSystem
            'Verzia OS'               = $device.OSVersion
            'Model'                   = $device.Model
            'Vyrobca'                 = $device.Manufacturer
            'Posledna synchronizacia' = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString("dd.MM.yyyy HH:mm") } else { "N/A" }
            'Dni od synchronizacie'   = $daysSinceSync
            'Stav compliance'         = switch ($device.ComplianceState) {
                "compliant" { "Kompliantny" }
                "noncompliant" { "Nekompliantny" }
                "conflict" { "Konflikt" }
                "error" { "Chyba" }
                "notapplicable" { "Neaplikovatelny" }
                default { $device.ComplianceState }
            }
            'Dovod non-compliance'    = $complianceReason
            'Seriove cislo'           = $device.SerialNumber
            'IMEI'                    = $device.Imei
            'Registrovany'            = if ($device.EnrolledDateTime) { $device.EnrolledDateTime.ToString("dd.MM.yyyy HH:mm") } else { "N/A" }
            'Typ zariadenia'          = $device.DeviceType
            'Spravca zariadenia'      = $device.ManagementAgent
        })
}

Write-Host "   OK: Spracovanych vsetkych $current zariadeni" -ForegroundColor Green

# --- Statistiky pouzivatelov ---
Write-Host "`n6. Vytvaranie statistik..." -ForegroundColor Cyan

Write-Host "   Vytvaram statistiky pouzivatelov..." -ForegroundColor Yellow
$userStats = [System.Collections.Generic.List[PSCustomObject]]::new()
$groups = $results | Group-Object 'Pouzivatel'

foreach ($g in $groups) {
    $compliant = ($g.Group | Where-Object { $_.'Stav compliance' -eq "Kompliantny" }).Count
    $nonCompliant = ($g.Group | Where-Object { $_.'Stav compliance' -eq "Nekompliantny" }).Count
    $oldDevices = ($g.Group | Where-Object { $_.'Dni od synchronizacie' -ne $null -and $_.'Dni od synchronizacie' -gt 45 }).Count
    $total = $g.Count

    $userStats.Add([PSCustomObject]@{
            'Pouzivatel'               = $g.Name
            'Email'                    = $g.Group[0].Email
            'Pocet zariadeni'          = $total
            'Kompliantne zariadenia'   = $compliant
            'Nekompliantne zariadenia' = $nonCompliant
            'Zariadenia 45+ dni'       = $oldDevices
            'Podiel kompliantnych'     = if ($total -gt 0) { "$([math]::Round(($compliant / $total) * 100, 1))%" } else { "0%" }
        })
}

Write-Host "   OK: Vytvorene statistiky pre $($userStats.Count) pouzivatelov" -ForegroundColor Green

# --- Suhrnne statistiky ---
Write-Host "   Vytvaram sumarne statistiky..." -ForegroundColor Yellow

$compliantCount = ($results | Where-Object { $_.'Stav compliance' -eq "Kompliantny" }).Count
$nonCompliantCount = ($results | Where-Object { $_.'Stav compliance' -eq "Nekompliantny" }).Count
$oldDevicesCount = ($results | Where-Object { $_.'Dni od synchronizacie' -ne $null -and $_.'Dni od synchronizacie' -gt 45 }).Count
$devicesWithoutUser = ($results | Where-Object { $_.'Pouzivatel' -eq "N/A" }).Count
$usersWithDevices = ($userStats | Where-Object { $_.'Pocet zariadeni' -gt 0 -and $_.Pouzivatel -ne "N/A" }).Count

$summary = @(
    [PSCustomObject]@{
        'Metrica'  = 'Celkovy pocet zariadeni'
        'Hodnota'  = $results.Count
        'Poznamka' = ''
    }
    [PSCustomObject]@{
        'Metrica'  = 'Kompliantne zariadenia'
        'Hodnota'  = $compliantCount
        'Poznamka' = "$([math]::Round(($compliantCount / $results.Count) * 100, 1))%"
    }
    [PSCustomObject]@{
        'Metrica'  = 'Nekompliantne zariadenia'
        'Hodnota'  = $nonCompliantCount
        'Poznamka' = "$([math]::Round(($nonCompliantCount / $results.Count) * 100, 1))%"
    }
    [PSCustomObject]@{
        'Metrica'  = 'Zariadenia 45+ dni bez synchronizacie'
        'Hodnota'  = $oldDevicesCount
        'Poznamka' = "$([math]::Round(($oldDevicesCount / $results.Count) * 100, 1))%"
    }
    [PSCustomObject]@{
        'Metrica'  = 'Zariadenia bez pouzivatela'
        'Hodnota'  = $devicesWithoutUser
        'Poznamka' = "$([math]::Round(($devicesWithoutUser / $results.Count) * 100, 1))%"
    }
    [PSCustomObject]@{
        'Metrica'  = 'Pouzivatelia so zariadeniami'
        'Hodnota'  = $usersWithDevices
        'Poznamka' = "$([math]::Round(($usersWithDevices / $users.Count) * 100, 1))% z $($users.Count) pouzivatelov"
    }
    [PSCustomObject]@{
        'Metrica'  = 'Datum exportu'
        'Hodnota'  = (Get-Date).ToString("dd.MM.yyyy HH:mm")
        'Poznamka' = ''
    }
)

Write-Host "   OK: Sumarne statistiky pripravene" -ForegroundColor Green

# --- Export do Excelu ---
Write-Host "`n7. Export do Excelu..." -ForegroundColor Cyan

try {
    Write-Host "   Vytvaram Excel subor: $ExportPath" -ForegroundColor Yellow
    
    # Jednoduchsi pristup - vytvorime novy subor s vsetkymi listami naraz
    $excelParams = @{
        Path         = $ExportPath
        AutoSize     = $true
        AutoFilter   = $true
        FreezeTopRow = $true
        BoldTopRow   = $true
    }

    # Exportujeme vsetky listy postupne
    Write-Host "   Vytvaram list 'Zariadenia'..." -ForegroundColor Yellow
    $sortedResults = $results | Sort-Object 'Pouzivatel', 'Nazov zariadenia'
    $sortedResults | Export-Excel @excelParams -WorksheetName "Zariadenia" -TableName "Zariadenia" -TableStyle "Medium6"

    Write-Host "   Vytvaram list 'Statistiky pouzivatelov'..." -ForegroundColor Yellow
    $sortedUserStats = $userStats | Sort-Object 'Pocet zariadeni' -Descending
    $sortedUserStats | Export-Excel @excelParams -WorksheetName "Statistiky pouzivatelov" -TableName "StatPouzivatelov" -TableStyle "Medium2"

    Write-Host "   Vytvaram list 'Sumar'..." -ForegroundColor Yellow
    $summary | Export-Excel @excelParams -WorksheetName "Sumar" -TableName "Summary" -TableStyle "Medium3"

    # Teraz otvorime subor pre podmienene formatovanie
    Write-Host "   Aplikujem farebne oznacenie..." -ForegroundColor Yellow
    $excelPackage = Open-ExcelPackage -Path $ExportPath
    
    # Podmienene formatovanie pre list Zariadenia
    $wsZariadenia = $excelPackage.Workbook.Worksheets["Zariadenia"]
    if ($wsZariadenia) {
        # Najdeme index stlpca "Dni od synchronizacie"
        $daysColumnIndex = 0
        for ($i = 1; $i -le $wsZariadenia.Dimension.Columns; $i++) {
            if ($wsZariadenia.Cells[1, $i].Value -eq "Dni od synchronizacie") {
                $daysColumnIndex = $i
                break
            }
        }
        
        if ($daysColumnIndex -gt 0) {
            $markedRows = 0
            for ($row = 2; $row -le $wsZariadenia.Dimension.Rows; $row++) {
                $daysValue = $wsZariadenia.Cells[$row, $daysColumnIndex].Value
                
                # Kontrola ci je hodnota cislo a vacsia ako 45
                if ($null -ne $daysValue -and $daysValue -is [int] -and $daysValue -gt 45) {
                    # Oznacime cely riadok oranzovo
                    for ($col = 1; $col -le $wsZariadenia.Dimension.Columns; $col++) {
                        $wsZariadenia.Cells[$row, $col].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                        $wsZariadenia.Cells[$row, $col].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::LightYellow)
                    }
                    $markedRows++
                }
            }
            Write-Host "   Oznacenych $markedRows riadkov (zariadenia 45+ dni bez synchronizacie)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   VAROVANIE: Nemozem najst list 'Zariadenia'" -ForegroundColor Red
    }
    
    Close-ExcelPackage $excelPackage

    Write-Host "`n*** EXPORT USPESNE DOKONCENY ***" -ForegroundColor Green
    Write-Host "Subor: $ExportPath" -ForegroundColor Cyan
    Write-Host "Listy:" -ForegroundColor White
    Write-Host "  - Zariadenia: $($results.Count) zariadeni" -ForegroundColor White
    Write-Host "  - Statistiky pouzivatelov: $($userStats.Count) pouzivatelov" -ForegroundColor White
    Write-Host "  - Sumar: Celkove statistiky" -ForegroundColor White
    Write-Host "Zariadeni so synchronizaciou 45+ dni: $oldDevicesCount" -ForegroundColor Yellow

    if ($AutoOpen) {
        Write-Host "   Otvaram subor..." -ForegroundColor Cyan
        Start-Process $ExportPath
    }
}
catch {
    Write-Host "   CHYBA pri exporte do Excelu: $_" -ForegroundColor Red
    
    # Fallback - export do CSV
    try {
        Write-Host "   Pokus o export do CSV..." -ForegroundColor Yellow
        $csvBase = $ExportPath -replace '\.xlsx$', ''
        $results | Sort-Object 'Pouzivatel', 'Nazov zariadenia' | Export-Csv "$csvBase_Zariadenia.csv" -NoTypeInformation -Encoding UTF8
        $userStats | Sort-Object 'Pocet zariadeni' -Descending | Export-Csv "$csvBase_Statistiky.csv" -NoTypeInformation -Encoding UTF8
        $summary | Export-Csv "$csvBase_Sumar.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "   OK: Data uspesne exportovane do CSV suborov." -ForegroundColor Green
    }
    catch {
        Write-Host "   CHYBA pri exporte do CSV: $_" -ForegroundColor Red
    }
}

# --- Odpojenie a ukoncenie ---
Write-Host "`n8. Ukoncenie..." -ForegroundColor Cyan

Write-Host "   Odpojujem sa od Microsoft Graph..." -ForegroundColor Yellow
Disconnect-MgGraph -ErrorAction SilentlyContinue

Write-Host "`n=== HOTOVO ===" -ForegroundColor Green
Write-Host "Koniec: $(Get-Date)" -ForegroundColor Gray