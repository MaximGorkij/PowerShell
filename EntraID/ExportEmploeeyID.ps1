<# 
.SYNOPSIS
    Export analýzy EmployeeID a e-mailových domén do CSV.
.DESCRIPTION
    Skript vytiahne používateľov s vyplneným EmployeeID, vypočíta dĺžku ID, 
    extrahuje doménu e-mailu a uloží detailný zoznam do CSV súboru.
.NOTES
    Verzia: 3.2
    Autor: Automaticky report
    Pozadovane moduly: ActiveDirectory, LogHelper
    Datum vytvorenia: 18.02.2026
    Logovanie: C:\TaurisIT\Log\EmployeeID_Export
#>

# Import modulov
Import-Module ActiveDirectory
Import-Module "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"

$logDir = "C:\TaurisIT\Log\EmployeeID_Export"
$csvPath = Join-Path $logDir "Export_EmployeeID_$(Get-Date -Format 'yyyyMMdd').csv"

if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir }

Write-Log -Message "Spúšťam export AD dát..." -Level Info

# Získanie používateľov
$adUsers = Get-ADUser -Filter 'EmployeeID -like "*"' -Properties EmployeeID, EmailAddress, DisplayName

if ($null -eq $adUsers) {
    Write-Log -Message "Neboli nájdení používatelia s EmployeeID." -Level Warning
    return
}

$results = foreach ($user in $adUsers) {
    $emailDomain = "N/A"
    if ($user.EmailAddress -and $user.EmailAddress -like "*@*") {
        $emailDomain = $user.EmailAddress.Split('@')[1]
    }

    [PSCustomObject]@{
        Meno             = $user.DisplayName
        SAMAccountName   = $user.SamAccountName
        EmployeeID       = $user.EmployeeID
        EmployeeIDLength = $user.EmployeeID.Length
        EmailAddress     = $user.EmailAddress
        EmailDomain      = $emailDomain
    }
}

# Export do CSV (použitý bodkočiarka ako separátor pre slovenský Excel)
try {
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Delimiter ";" -Encoding UTF8
    Write-Log -Message "Dáta boli úspešne exportované do: $csvPath" -Level Info
}
catch {
    Write-Log -Message "Chyba pri zápise do CSV: $($_.Exception.Message)" -Level Error
}

# Výpis štatistík do konzoly pre rýchly prehľad
Write-Host "`n--- Štatistika dĺžky EmployeeID ---" -ForegroundColor Cyan
$results | Group-Object EmployeeIDLength | Select-Object @{N = "Pocet_Miest"; E = { $_.Name } }, @{N = "Pocet_Ludi"; E = { $_.Count } } | Sort-Object Pocet_Miest | Format-Table -AutoSize

Write-Host "--- Štatistika e-mailových domén ---" -ForegroundColor Cyan
$results | Group-Object EmailDomain | Select-Object @{N = "Domena"; E = { $_.Name } }, @{N = "Pocet_Ludi"; E = { $_.Count } } | Sort-Object Pocet_Ludi -Descending | Format-Table -AutoSize

Write-Log -Message "Skript dokončený." -Level Info