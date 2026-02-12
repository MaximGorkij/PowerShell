<# 
.SYNOPSIS
    Klonovanie AD uctu s logovanim + TEST/WHATIF rezim.
.DESCRIPTION
    Vyhlada vzoroveho pouzivatela a vytvori noveho.
    Vynucuje vyber cisla pri zvoleni sablony.
    Klonuje: Skupiny, Address tab, Organization tab.
.NOTES
    Verzia: 3.4 (Strict Number Selection)
    Pozadovane moduly: ActiveDirectory, LogHelper
#>

# ---------------------------------------------------------------------------
# POMOCNE FUNKCIE
# ---------------------------------------------------------------------------

function Remove-Diacritics {
    param ([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($char) }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

# ---------------------------------------------------------------------------
# NASTAVENIA
# ---------------------------------------------------------------------------
$TestMode = $false   # $false = ostry beh, $true = test bez vytvorenia
$UseWhatIf = $TestMode

$LogHelperPath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$LogDir = "C:\TaurisIT\Log\UserClone"
$EventSource = "ADUserCloneApp"

$Timestamp = Get-Date -Format 'yyyyMMddHHmm'
$LogFile = "$Timestamp-UserClone.log"

# ---------------------------------------------------------------------------
# INICIALIZACIA
# ---------------------------------------------------------------------------

if ($TestMode) {
    Write-Host "`n=== TESTOVACI REZIM (WHATIF) ===" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host "Ziadne zmeny v AD sa nevykonaju (Simulacia)!`n" -ForegroundColor Yellow
}

if (-not (Test-Path $LogDir)) {
    try { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null } 
    catch { Write-Warning "Nepodarilo sa vytvorit adresar logov: $_" }
}

if (!(Get-Module -ListAvailable ActiveDirectory)) {
    Write-Error "Modul ActiveDirectory chyba."
    return
}
Import-Module ActiveDirectory

$LogModuleLoaded = $false
if (Test-Path $LogHelperPath) {
    try {
        Import-Module $LogHelperPath -Force -ErrorAction Stop
        Initialize-LogSystem -LogDirectory $LogDir -EventSource $EventSource -RetentionDays 60
        $LogModuleLoaded = $true
    }
    catch { Write-Warning "LogHelper chyba: $_" }
}

if (-not $LogModuleLoaded) {
    function Write-IntuneLog { param($Message, $Level) Write-Host "[$Level] $Message" -ForegroundColor DarkGray }
}

$modeMsg = if ($TestMode) { "TEST/WHATIF" } else { "PROD" }
Write-IntuneLog -Message "Start aplikacie [$modeMsg] v3.4. LogFile: $LogFile" -Level INFO -LogFile $LogFile

# ---------------------------------------------------------------------------
# VYHLADANIE PREDLOHY
# ---------------------------------------------------------------------------

$searchName = Read-Host "Zadaj priezvisko vzoroveho pouzivatela"
Write-IntuneLog -Message "Hladam: $searchName" -Level INFO -LogFile $LogFile

$users = @(Get-ADUser -Filter "Surname -like '*$searchName*'" -Properties DisplayName, UserPrincipalName)

if ($users.Count -eq 0) {
    Write-Host "Nenaslo sa nic." -ForegroundColor Red
    Write-IntuneLog -Message "Ziadny vysledok pre: $searchName" -Level WARN -LogFile $LogFile
    return
}

Write-Host "`nNajdene:" -ForegroundColor Cyan
for ($i = 0; $i -lt $users.Count; $i++) {
    Write-Host "[$i] $($users[$i].DisplayName) ($($users[$i].UserPrincipalName))"
}

# --- VYNUTENY VYBER CISLA ---
$validSelection = $false
$selectedIndex = -1

do {
    $choice = Read-Host "`nVyberte číslo (0 - $(($users.Count) - 1))"
    
    # 1. Test ci je to cislo
    if ($choice -match '^\d+$') {
        $selectedIndex = [int]$choice
        
        # 2. Test rozsahu
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $users.Count) {
            $validSelection = $true
        }
        else {
            Write-Host "CHYBA: Číslo $selectedIndex je mimo rozsahu!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "CHYBA: Musíte zadať číslo!" -ForegroundColor Red
    }
} until ($validSelection)

$template = $users[$selectedIndex]
Write-IntuneLog -Message "Vybrata predloha: $($template.UserPrincipalName)" -Level INFO -LogFile $LogFile

# ---------------------------------------------------------------------------
# ZADANIE UDAJOV
# ---------------------------------------------------------------------------

Write-Host "`nZadaj udaje noveho uctu:" -ForegroundColor Cyan
$newName = Read-Host "Meno"
$newSurname = Read-Host "Priezvisko"

# Email
$emailPrefixInput = Read-Host "Email (pred zavinacom, napr. jan.novak)"
if ($emailPrefixInput -match "@") { $emailPrefixInput = $emailPrefixInput.Split('@')[0] }
$newEmail = "$emailPrefixInput@tauris.sk"
Write-Host " -> Email: $newEmail" -ForegroundColor Gray

# Employee ID
do {
    $empIDInput = Read-Host "Employee ID (5 miest, musi zacinat 0)"
    if ($empIDInput -match "^0\d{4}$") {
        $newEmpID = $empIDInput
        $empIDValid = $true
    }
    else {
        Write-Host "CHYBA: ID musi mat presne 5 cislic a zacinat nulou." -ForegroundColor Red
        $empIDValid = $false
    }
} until ($empIDValid)

# SAM Login
$cleanSurname = Remove-Diacritics $newSurname
$baseSam = $cleanSurname.ToLower().Replace(" ", "")
$candidateSam = $baseSam
$counter = 1
Write-Host "Generujem navrh loginu..." -ForegroundColor DarkGray
while (Get-ADUser -Filter "SamAccountName -eq '$candidateSam'" -ErrorAction SilentlyContinue) {
    $candidateSam = "$baseSam$counter"
    $counter++
}
$newSamInput = Read-Host "SAM login [$candidateSam]"
if ([string]::IsNullOrWhiteSpace($newSamInput)) { $newSam = $candidateSam } else { $newSam = $newSamInput }

# Telefon
do {
    $phoneInput = Read-Host "Telefon (format 09XXXXXXXX)"
    if ($phoneInput -match "^09\d{8}$") {
        $newPhone = "{0} {1} {2}" -f $phoneInput.Substring(0, 4), $phoneInput.Substring(4, 3), $phoneInput.Substring(7, 3)
        $phoneValid = $true
        Write-Host " -> Formatovane na: $newPhone" -ForegroundColor Gray
    }
    else {
        Write-Host "CHYBA: Zadajte 10 cislic zacinajucich 09." -ForegroundColor Red
        $phoneValid = $false
    }
} until ($phoneValid)

$displayName = "$newName $newSurname"
$password = "Tauris$(Get-Date -Format yyyy)"
$passwordSecure = ConvertTo-SecureString $password -AsPlainText -Force

Write-Host "`nHeslo: $password" -ForegroundColor Gray
Write-IntuneLog -Message "Priprava: $newSam ($displayName). Tel: $newPhone. ID: $newEmpID" -Level INFO -LogFile $LogFile

# ---------------------------------------------------------------------------
# KONTROLA EXISTENCIE UDAJOV
# ---------------------------------------------------------------------------

Write-Host "`nPrebieha kontrola duplicity..." -ForegroundColor Yellow
$existSam = Get-ADUser -Filter "SamAccountName -eq '$newSam'" -ErrorAction SilentlyContinue
if ($existSam) {
    Write-Host "CHYBA: Login '$newSam' uz existuje!" -ForegroundColor Red
    return
}
$existMail = Get-ADObject -Filter "mail -eq '$newEmail' -or proxyAddresses -like '*:$newEmail'" -Properties mail
if ($existMail) {
    Write-Host "CHYBA: Email '$newEmail' uz je obsadeny!" -ForegroundColor Red
    return
}
Write-Host "Kontrola OK." -ForegroundColor Green

# ---------------------------------------------------------------------------
# VYTVORENIE UCTU + SKUPINY
# ---------------------------------------------------------------------------

try {
    # Nacitanie rozsirenych vlastnosti
    $propsToLoad = @(
        "MemberOf", "Description", "Title", "Department", "Company", 
        "StreetAddress", "City", "PostalCode", "State", "Country", 
        "Manager", "PhysicalDeliveryOfficeName"
    )

    $templateFull = Get-ADUser $template.DistinguishedName -Properties $propsToLoad
    
    $dn = $templateFull.DistinguishedName
    $commaIndex = $dn.IndexOf(",")
    if ($commaIndex -gt 0) { $targetOU = $dn.Substring($commaIndex + 1) } 
    else { throw "Nepodarilo sa urcit rodicovsku cestu z DN: $dn" }

    Write-IntuneLog -Message "Cielova cesta: $targetOU" -Level INFO -LogFile $LogFile

    $userParams = @{
        Name                  = $displayName
        DisplayName           = $displayName
        GivenName             = $newName
        Surname               = $newSurname
        EmailAddress          = $newEmail
        OfficePhone           = $newPhone
        EmployeeID            = $newEmpID
        SamAccountName        = $newSam
        UserPrincipalName     = $newEmail
        Path                  = $targetOU
        Description           = $templateFull.Description
        Title                 = $templateFull.Title
        Department            = $templateFull.Department
        Company               = $templateFull.Company
        Manager               = $templateFull.Manager
        Office                = $templateFull.PhysicalDeliveryOfficeName
        StreetAddress         = $templateFull.StreetAddress
        City                  = $templateFull.City
        PostalCode            = $templateFull.PostalCode
        State                 = $templateFull.State
        Country               = $templateFull.Country
        AccountPassword       = $passwordSecure
        Enabled               = $false
        ChangePasswordAtLogon = $false
        ErrorAction           = "Stop"
    }

    New-ADUser @userParams -WhatIf:$UseWhatIf

    if ($TestMode) { Write-Host "`n[WHATIF] Ucet vytvoreny (vratane adresy a manazera)." -ForegroundColor Cyan } 
    else { Write-Host "`nUcet $displayName vytvoreny." -ForegroundColor Green }
    
    Write-IntuneLog -Message "Ucet $newSam spracovany (WhatIf=$UseWhatIf)" -Level INFO -LogFile $LogFile

    # Skupiny
    $ok = 0; $fail = 0
    foreach ($group in $templateFull.MemberOf) {
        if ($TestMode) {
            Write-Host "WHATIF: Pridanie do skupiny -> $group" -ForegroundColor DarkGray
            $ok++
        }
        else {
            try {
                Add-ADGroupMember -Identity $group -Members $newSam -ErrorAction Stop
                $ok++
            }
            catch {
                $fail++
                Write-Host "Chyba skupiny: $group" -ForegroundColor Yellow
                Write-IntuneLog -Message "Chyba skupiny: $group - $_" -Level WARN -LogFile $LogFile
            }
        }
    }

    Write-Host "Skupiny: OK=$ok, Chyba=$fail" -ForegroundColor Green
    Write-IntuneLog -Message "Skupiny: OK=$ok, Chyba=$fail (WhatIf=$UseWhatIf)" -Level INFO -LogFile $LogFile
}
catch {
    Write-Host "KRITICKA CHYBA: $_" -ForegroundColor Red
    Write-IntuneLog -Message "Kriticka chyba: $_" -Level ERROR -LogFile $LogFile
}

Write-IntuneLog -Message "Koniec aplikacie" -Level INFO -LogFile $LogFile