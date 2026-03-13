<# 
.SYNOPSIS
    MFA Export a vyhladavanie podla cisla (poslednych 9 cifier)
.DESCRIPTION
    Skript umoznuje export vsetkych dat alebo cielené vyhladavanie majitela cisla.
    Opravena cesta exportu na C:\TaurisIT\Export\MFA_Export.
.NOTES
    Verzia: 2.8
    Autor: Automaticky report
    Pozadovane moduly: Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns, LogHelper
    Datum vytvorenia: 04.03.2026
    Logovanie: C:\TaurisIT\Log\MFA_Export
    Export: C:\TaurisIT\Export\MFA_Export
#>

# Import logovacieho modulu
Import-Module "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"

# Definicia ciest
$subDir = "MFA_Export"
$fullLogDirPath = "C:\TaurisIT\Log\$subDir"
$logFileNameOnly = "$subDir\MFA_Search_$(Get-Date -Format 'yyyyMMdd').log"
$exportDir = "C:\TaurisIT\Export\$subDir"
$exportPath = "$exportDir\MFA_Result.csv"

# --- AUTOMATICKE VYTVORENIE PRIECINKOV ---
if (-not (Test-Path $fullLogDirPath)) { New-Item -ItemType Directory -Path $fullLogDirPath -Force | Out-Null }
if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

# --- INTERAKTIVNA PONUKA ---
Write-Host "=== MFA MANAZER (M365) ===" -ForegroundColor Cyan
Write-Host "1. Exportovat VSETKYCH (vsetky riadky)"
Write-Host "2. Exportovat VSETKYCH (jedno najlepsie cislo na osobu)"
Write-Host "3. VYHLADAT KONKRETNE CISLO (zhoda poslednych 9 cifier)"
$choice = Read-Host "Vasa volba (1/2/3)"

$searchNumber = ""
if ($choice -eq "3") {
    $searchNumber = Read-Host "Zadajte 9 cislic (napr. 905123456)"
    if ($searchNumber -notmatch '^\d{9}$') {
        Write-Error "Chyba: Musite zadat presne 9 cislic bez medzier!"
        return
    }
}

# Prihlasenie do Graph
try {
    Write-Host "Pripajam sa k Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "User.Read.All", "UserAuthenticationMethod.Read.All" -ErrorAction Stop
}
catch {
    Write-Error "Chyba pripojenia: $($_.Exception.Message)"
    return
}

Write-CustomLog -Message "Start MFA operacie (Volba: $choice, Hladane: $searchNumber)" -EventSource "M365_MFA_Script" -LogFileName $logFileNameOnly -Type "Information"

try {
    Write-Host "Nacitavam data z M365 (cakajte prosim)..." -ForegroundColor Cyan
    $allUsers = Get-MgUser -All -Property "DisplayName", "UserPrincipalName", "Id", "MobilePhone" -Filter "accountEnabled eq true"

    $results = $allUsers | ForEach-Object -Parallel {
        $user = $_
        $mode = $using:choice
        $target = $using:searchNumber
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction SilentlyContinue

        try {
            $phoneMethods = Get-MgUserAuthenticationPhoneMethod -UserId $user.Id -ErrorAction SilentlyContinue
            if ($phoneMethods) {
                foreach ($method in $phoneMethods) {
                    # Odstranenie vsetkeho okrem cislic pre porovnanie
                    $cleanNum = $method.PhoneNumber -replace '\D', ''
                    
                    $isMatch = $false
                    if ($mode -eq "3") {
                        if ($cleanNum -like "*$target") { $isMatch = $true }
                    }
                    else {
                        $isMatch = $true
                    }

                    if ($isMatch) {
                        [PSCustomObject]@{
                            Meno           = $user.DisplayName
                            Email          = $user.UserPrincipalName
                            KontaktneCislo = $user.MobilePhone
                            MFACislo       = $method.PhoneNumber
                            MFATyp         = $method.Type
                            JeValidne      = ($method.PhoneNumber -replace '\s', '') -match '^\+421\d{9}$'
                        }
                    }
                }
            }
        }
        catch { }
    } -ThrottleLimit 20

    # Finalna filtracia/upratovanie
    $finalOutput = $null
    if ($choice -eq "2") {
        $finalOutput = $results | Group-Object Email | ForEach-Object {
            $_.Group | Sort-Object JeValidne -Descending | Select-Object -First 1
        }
    }
    else {
        $finalOutput = $results
    }

    # --- VYSTUP ---
    if ($finalOutput -and $finalOutput.Count -gt 0) {
        $finalOutput | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8 -Delimiter ";"
        
        Write-Host "`n--- VYSLEDOK ---" -ForegroundColor Cyan
        $finalOutput | ForEach-Object {
            Write-Host "Nasiel sa: $($_.Meno) ($($_.Email)) -> MFA: $($_.MFACislo)" -ForegroundColor Green
        }
        
        Write-Host "`nPocet zaznamov: $($finalOutput.Count)" -ForegroundColor Yellow
        Write-Host "CSV ulozene: $exportPath" -ForegroundColor Yellow
        Write-CustomLog -Message "Uspesne najdenych $($finalOutput.Count) zaznamov." -EventSource "M365_MFA_Script" -LogFileName $logFileNameOnly -Type "Information"
    }
    else {
        Write-Host "`nZiadna zhoda pre cislo $searchNumber nebola najdena." -ForegroundColor Red
        Write-CustomLog -Message "Hladanie ukoncene bez vysledku." -EventSource "M365_MFA_Script" -LogFileName $logFileNameOnly -Type "Warning"
    }
}
catch {
    $err = "Kriticka chyba: $($_.Exception.Message)"
    Write-CustomLog -Message $err -EventSource "M365_MFA_Script" -LogFileName $logFileNameOnly -Type "Error"
    Write-Error $err
}