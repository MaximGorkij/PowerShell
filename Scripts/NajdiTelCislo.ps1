Import-Module LogHelper

<# 
.SYNOPSIS
    Vyhľadanie používateľa v AD podľa telefónneho čísla
.DESCRIPTION
    Skript prehľadá atribúty telephoneNumber a mobile v Active Directory
    a vráti základné údaje o nájdenej osobe.
.NOTES
    Verzia: 1.0
    Autor: Automaticky report
    Pozadovane moduly: ActiveDirectory, LogHelper
    Datum vytvorenia: 13.03.2026
    Logovanie: C:\TaurisIT\Log\ADSearch
#>

$cislo = "+421 9188" # Sem zadajte hľadané číslo
$logPath = "C:\TaurisIT\Log\ADSearch"

try {
    # Hľadanie v mobile aj v kancelárskom čísle
	$filter = "(Enabled -eq 'True') -and (telephoneNumber -like '*$cislo*' -or mobile -like '*$cislo*')"
	#$filter = "(Enabled -eq 'True') -and (telephoneNumber -eq '$cislo' -or mobile -eq '$cislo')"
 $user = Get-ADUser -Filter $filter -Properties telephoneNumber, mobile, EmailAddress, Enabled

    if ($null -ne $user) {
        Write-Host "Nájdený aktívny používateľ:" -ForegroundColor Green
        $user | Select-Object Name, SamAccountName, telephoneNumber, mobile, EmailAddress | Format-Table
        
        Write-CustomLog -Message "Nájdený aktívny používateľ pre číslo $cislo" -EventSource "ADSearch" -LogFileName "search.log" -Type "Information"
    }
    else {
        Write-Warning "Pre číslo $cislo nebol nájdený žiadny aktívny účet."
    }
}
catch {
    $errorMessage = "Chyba pri hľadaní v AD: $($_.Exception.Message)"
    Write-CustomLog -Message $errorMessage -EventSource "ADSearch" -LogFileName "error.log" -Type "Error"
    Write-Error $errorMessage
}