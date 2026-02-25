<# 
.SYNOPSIS
    Klonovanie AD uctu s logovanim + TEST/WHATIF rezim
.DESCRIPTION
    Vyhlada vzoroveho pouzivatela a vytvori presnu kopiu.
    - Orezanie zdrojovej OU osetrene cez regex.
    - Pridany volitelny titul do DisplayName ("Priezvisko Meno, Titul").
    - EmployeeID: 5 alebo 7 miest (musi zacinat 0), kontrola unikatnosti.
    - Email domena dynamicky podla vzoru, validacia prazdneho prefixu.
    - Automaticke prevzatie alebo zmena telefonneho cisla.
    - Doplnkova sluzba: Auto-Enable.
    - Rezim behu sa zadava ako parameter pri spusteni skriptu.
.NOTES
    Verzia: 3.15
    Autor: Automaticky report
    Pozadovane moduly: ActiveDirectory, LogHelper, ScheduledTasks
    Datum vytvorenia: 23.02.2026
    Logovanie: C:\TaurisIT\Log\UserClone
#>

param (
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet("prod", "test")]
    [string]$Mode = "prod"
)

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

# OPRAVA: Nahodny generator hesla – nahradzuje hardcoded 'Tauris$(rok)'
function New-RandomPassword {
    $chars = (65..90) + (97..122) + (48..57) + @(33, 35, 36, 37, 38)
    # Garantovane aspon 1 velke pismeno, 1 male, 1 cifra, 1 specialny znak
    $upper = [char](Get-Random -InputObject (65..90))
    $lower = [char](Get-Random -InputObject (97..122))
    $digit = [char](Get-Random -InputObject (48..57))
    $special = [char](Get-Random -InputObject @(33, 35, 36, 37, 38))
    $rest = -join ((Get-Random -InputObject $chars -Count 8) | ForEach-Object { [char]$_ })
    # Zamiesa vsetky znaky do nahodneho poradia
    return -join (($upper, $lower, $digit, $special + $rest.ToCharArray()) | Get-Random -Count 12)
}

# ---------------------------------------------------------------------------
# NASTAVENIA
# ---------------------------------------------------------------------------

$TestMode = ($Mode -eq "test")
$UseWhatIf = $TestMode

$LogHelperPath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogDir = "C:\TaurisIT\Log\UserClone"
$EventSource = "ADUserCloneApp"

$Timestamp = Get-Date -Format 'yyyyMMddHHmm'
# OPRAVA: Plna cesta k logu namiesto samotneho nazvu suboru
$LogFile = Join-Path $LogDir "$Timestamp-UserClone.log"

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

# OPRAVA: Import ScheduledTasks – bol uvedeny v .NOTES ale nikdy nenaimportovany
Import-Module ScheduledTasks -ErrorAction SilentlyContinue

$LogModuleLoaded = $false
if (Test-Path $LogHelperPath) {
    try {
        Import-Module $LogHelperPath -Force -ErrorAction Stop
        Initialize-LogSystem -LogDirectory $LogDir -EventSource $EventSource -RetentionDays 60
        $LogModuleLoaded = $true
    }
    catch { Write-Warning "LogHelper chyba: $_" }
}

# OPRAVA: Fallback ma rovnaku signaturu ako original (obsahuje -LogFile parameter)
if (-not $LogModuleLoaded) {
    function Write-IntuneLog {
        param ($Message, $Level, $LogFile)
        Write-Host "[$Level] $Message" -ForegroundColor DarkGray
    }
}

$modeMsg = if ($TestMode) { "TEST/WHATIF" } else { "PROD" }
Write-IntuneLog -Message "Start aplikacie [$modeMsg] v3.15. LogFile: $LogFile" -Level INFO -LogFile $LogFile

# ---------------------------------------------------------------------------
# VYHLADANIE PREDLOHY
# ---------------------------------------------------------------------------

$searchName = Read-Host "Zadaj priezvisko vzoroveho pouzivatela"
Write-IntuneLog -Message "Hladam: $searchName" -Level INFO -LogFile $LogFile

$users = @(Get-ADUser -Filter "Surname -like '*$searchName*'" -Properties DisplayName, UserPrincipalName, EmailAddress)

if ($users.Count -eq 0) {
    Write-Host "Nenaslo sa nic." -ForegroundColor Red
    Write-IntuneLog -Message "Ziadny vysledok pre: $searchName" -Level WARN -LogFile $LogFile
    return
}

Write-Host "`nNajdene:" -ForegroundColor Cyan
for ($i = 0; $i -lt $users.Count; $i++) {
    Write-Host "[$i] $($users[$i].DisplayName) ($($users[$i].UserPrincipalName))"
}

$validSelection = $false
$selectedIndex = -1
do {
    $choice = Read-Host "`nVyberte cislo (0 - $(($users.Count) - 1))"
    if ($choice -match '^\d+$') {
        $selectedIndex = [int]$choice
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $users.Count) { $validSelection = $true }
        else { Write-Host "CHYBA: Cislo je mimo rozsahu!" -ForegroundColor Red }
    }
    else { Write-Host "CHYBA: Musíte zadat cislo!" -ForegroundColor Red }
} until ($validSelection)

$template = $users[$selectedIndex]
Write-IntuneLog -Message "Vybrata predloha: $($template.UserPrincipalName)" -Level INFO -LogFile $LogFile

$propsToLoad = @("MemberOf", "Description", "Title", "Department", "Company", "StreetAddress", "City", "PostalCode", "State", "Country", "Manager", "PhysicalDeliveryOfficeName", "OfficePhone")
$templateFull = Get-ADUser $template.DistinguishedName -Properties $propsToLoad

# ---------------------------------------------------------------------------
# ZADANIE UDAJOV
# ---------------------------------------------------------------------------

Write-Host "`nZadaj udaje noveho uctu:" -ForegroundColor Cyan
$newTitle = Read-Host "Titul pred menom (napr. Ing., Mgr., Bc. - ak nema, stlacte Enter)"
$newName = Read-Host "Meno"
$newSurname = Read-Host "Priezvisko"

if ([string]::IsNullOrWhiteSpace($newTitle)) {
    $displayName = "$newSurname $newName"
}
else {
    $displayName = "$newSurname $newName, $newTitle"
}

# --- KONTROLA DUPLICITY MENA ---
$dupUsers = Get-ADUser -Filter "GivenName -eq '$newName' -and Surname -eq '$newSurname'" -Properties DisplayName, SamAccountName, Enabled
if ($dupUsers) {
    Write-Host "`n!!! POZOR: V AD UZ EXISTUJE UZIVATEL S TYMTO MENOM !!!" -ForegroundColor Red -BackgroundColor Yellow
    foreach ($u in $dupUsers) {
        Write-Host " -> $($u.DisplayName) (Login: $($u.SamAccountName), Aktivny: $($u.Enabled))" -ForegroundColor Red
    }
    $continue = Read-Host "`nChcete napriek tomu pokracovat a vytvorit dalsieho? (A/N)"
    if ($continue -ne "A") {
        Write-Host "Ukoncene uzivatelom." -ForegroundColor Yellow
        # OPRAVA: Logovanie aj pri zruseni uzivatelom
        Write-IntuneLog -Message "Akcia zrusena uzivatelom pri duplicite mena: $displayName" -Level WARN -LogFile $LogFile
        return
    }
}

# --- EMAIL LOGIKA (Masiarstvo vs Tauris) ---
$sourceEmail = $templateFull.UserPrincipalName
if ([string]::IsNullOrEmpty($sourceEmail)) { $sourceEmail = $templateFull.EmailAddress }

$domainPart = "@tauris.sk"
if ($sourceEmail -match "@masiarstvoubyka.sk") {
    $domainPart = "@masiarstvoubyka.sk"
}

# OPRAVA: Validacia prazdneho email prefixu
do {
    $emailPrefixInput = Read-Host "Email (pred $domainPart)"
    if ($emailPrefixInput -match "@") { $emailPrefixInput = $emailPrefixInput.Split('@')[0] }
    if ([string]::IsNullOrWhiteSpace($emailPrefixInput)) {
        Write-Host "CHYBA: Email prefix nesmie byt prazdny!" -ForegroundColor Red
    }
} until (-not [string]::IsNullOrWhiteSpace($emailPrefixInput))

$newEmail = "$emailPrefixInput$domainPart"
Write-Host " -> Vysledny email: $newEmail" -ForegroundColor Gray


# --- EMPLOYEE ID (5 alebo 7 MIEST) ---
do {
    $empIDInput = Read-Host "Employee ID (5 alebo 7 miest, musi zacinat 0)"

    if ($empIDInput -match "^(0\d{4}|0\d{6})$") {
        # OPRAVA: Kontrola unikatnosti EmployeeID v AD
        $existingEmpID = Get-ADUser -Filter "EmployeeID -eq '$empIDInput'" -Properties EmployeeID, SamAccountName -ErrorAction SilentlyContinue
        if ($existingEmpID) {
            Write-Host "CHYBA: EmployeeID '$empIDInput' uz pouziva uzivatel: $($existingEmpID.SamAccountName)!" -ForegroundColor Red
            $empIDValid = $false
        }
        else {
            $newEmpID = $empIDInput
            $empIDValid = $true
        }
    }
    else {
        Write-Host "CHYBA: ID musi mat 5 alebo 7 cislic a zacinat nulou (napr. 01234 alebo 0123456)." -ForegroundColor Red
        $empIDValid = $false
    }
} until ($empIDValid)


# --- SAM LOGIN ---
$cleanSurname = Remove-Diacritics $newSurname
# OPRAVA: Orezanie na max 18 znakov, aby bol rezerva pre ciselny suffix (AD limit = 20)
$baseSam = $cleanSurname.ToLower().Replace(" ", "")
if ($baseSam.Length -gt 18) { $baseSam = $baseSam.Substring(0, 18) }

$candidateSam = $baseSam
$counter = 1
Write-Host "Generujem navrh loginu..." -ForegroundColor DarkGray
while (Get-ADUser -Filter "SamAccountName -eq '$candidateSam'" -ErrorAction SilentlyContinue) {
    $candidateSam = "$baseSam$counter"
    $counter++
}
$newSamInput = Read-Host "SAM login [$candidateSam]"
if ([string]::IsNullOrWhiteSpace($newSamInput)) { $newSam = $candidateSam } else { $newSam = $newSamInput }


# --- TELEFON ---
$templatePhone = $templateFull.OfficePhone

do {
    if (-not [string]::IsNullOrWhiteSpace($templatePhone)) {
        $phoneInput = Read-Host "Telefon (Zadajte 09XXXXXXXX, alebo stlacte Enter pre prevzatie vzoroveho cisla: $templatePhone)"
        if ([string]::IsNullOrWhiteSpace($phoneInput)) {
            $newPhone = $templatePhone
            $phoneValid = $true
            Write-Host " -> Pouzije sa vzorove cislo: $newPhone" -ForegroundColor Gray
            continue
        }
    }
    else {
        $phoneInput = Read-Host "Telefon (zadajte 09XXXXXXXX)"
    }

    if ($phoneInput -match "^09\d{8}$") {
        $newPhone = "+421" + $phoneInput.Substring(1)
        $phoneValid = $true
        Write-Host " -> Formatovane na: $newPhone" -ForegroundColor Gray
    }
    else {
        Write-Host "CHYBA: Zadajte 10 cislic zacinajucich 09." -ForegroundColor Red
        $phoneValid = $false
    }
} until ($phoneValid)


# OPRAVA: Nahodne heslo – viac sa nepouziva hardcoded 'Tauris$(rok)'
$password = New-RandomPassword
$passwordSecure = ConvertTo-SecureString $password -AsPlainText -Force

Write-IntuneLog -Message "Priprava: $newSam ($displayName). Tel: $newPhone. ID: $newEmpID" -Level INFO -LogFile $LogFile

# ---------------------------------------------------------------------------
# KONTROLA EXISTENCIE UDAJOV (Technicka duplicita)
# ---------------------------------------------------------------------------
Write-Host "`nPrebieha technicka kontrola..." -ForegroundColor Yellow
if (Get-ADUser -Filter "SamAccountName -eq '$newSam'" -ErrorAction SilentlyContinue) {
    Write-Host "CHYBA: Login '$newSam' uz existuje!" -ForegroundColor Red; return
}
if (Get-ADObject -Filter "mail -eq '$newEmail' -or proxyAddresses -like '*:$newEmail'" -Properties mail) {
    Write-Host "CHYBA: Email '$newEmail' uz je obsadeny!" -ForegroundColor Red; return
}

# ---------------------------------------------------------------------------
# PRIPRAVA DAT Z PREDLOHY PRE VYTVORENIE
# ---------------------------------------------------------------------------

$dn = $templateFull.DistinguishedName

$targetOU = $dn -replace '^CN=.+?,(?=OU=|CN=)', ''

# OPRAVA: Validacia targetOU presunutá sem – pred try/catch blokom by throw skript prerusal nekontrolovane
if ([string]::IsNullOrEmpty($targetOU) -or $targetOU -eq $dn) {
    Write-Host "CHYBA: Nepodarilo sa urcit rodicovsku cestu z DN: $dn" -ForegroundColor Red
    Write-IntuneLog -Message "Kriticka chyba: Nepodarilo sa urcit targetOU z DN: $dn" -Level ERROR -LogFile $LogFile
    return
}

$managerName = "---"
if ($templateFull.Manager) {
    $mgrObj = Get-ADUser $templateFull.Manager -Properties DisplayName
    $managerName = $mgrObj.DisplayName
}

# --- OPRAVA: Validacia Country kodu (AD ocakava 2-pismenovy ISO kod) ---
if ($templateFull.Country -and $templateFull.Country.Length -ne 2) {
    Write-Host "POZOR: Vzorovy uzivatel ma nestandartny Country kod '$($templateFull.Country)' (ocakavaju sa 2 znaky ISO). Skontrolujte po vytvoreni." -ForegroundColor Yellow
    Write-IntuneLog -Message "Upozornenie: nestandartny Country kod: $($templateFull.Country)" -Level WARN -LogFile $LogFile
}

# ---------------------------------------------------------------------------
# SUHRN (SUMMARY SCREEN)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "          SUHRN NOVEHO UZIVATELA          " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Zobrazovane meno  : " -NoNewline; Write-Host $displayName -ForegroundColor Green
Write-Host "Email             : " -NoNewline; Write-Host $newEmail -ForegroundColor Green
Write-Host "Telefon           : " -NoNewline; Write-Host $newPhone -ForegroundColor Green
Write-Host "Osobne cislo (ID) : " -NoNewline; Write-Host $newEmpID -ForegroundColor Green
Write-Host "Login (SAM)       : " -NoNewline; Write-Host $newSam -ForegroundColor Green
# OPRAVA: Heslo sa v sumare NEZOBRAZUJE v plain texte – len potvrdenie ze bolo vygenerovane
Write-Host "Heslo             : " -NoNewline; Write-Host "(vygenerovane nahodne – odovzdajte osobne)" -ForegroundColor DarkGray
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host "PRENESENE ZAZNAMY (Zo vzoru):" -ForegroundColor Yellow
Write-Host "Zdrojova OU       : $targetOU"
Write-Host "Manazer           : $managerName"
Write-Host "Kancelaria        : $(if($templateFull.PhysicalDeliveryOfficeName){$templateFull.PhysicalDeliveryOfficeName}else{'---'})"
Write-Host "Adresa            : $(if($templateFull.City){$templateFull.City + ', ' + $templateFull.StreetAddress}else{'---'})"
Write-Host "Pocet AD Skupin   : $($templateFull.MemberOf.Count)"
Write-Host "==========================================" -ForegroundColor Cyan

$confirm = Read-Host "Suhlasite s vytvorenim uctu? (A/N)"
if ($confirm -ne "A") {
    Write-Host "Akcia zrusena uzivatelom." -ForegroundColor Red
    Write-IntuneLog -Message "Akcia zrusena uzivatelom v suhrne." -Level WARN -LogFile $LogFile
    return
}

# ---------------------------------------------------------------------------
# VYTVORENIE UCTU + SKUPINY (CORE)
# ---------------------------------------------------------------------------

try {
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

    if ($TestMode) { Write-Host "`n[WHATIF] Ucet vytvoreny." -ForegroundColor Cyan }
    else { Write-Host "`nUcet $displayName uspesne vytvoreny." -ForegroundColor Green }

    Write-IntuneLog -Message "Ucet $newSam spracovany (WhatIf=$UseWhatIf)" -Level INFO -LogFile $LogFile

    # Skupiny
    $ok = 0; $fail = 0
    foreach ($group in $templateFull.MemberOf) {
        if ($TestMode) { Write-Host "WHATIF: Pridanie do skupiny -> $group" -ForegroundColor DarkGray; $ok++ }
        else {
            try { Add-ADGroupMember -Identity $group -Members $newSam -ErrorAction Stop; $ok++ }
            catch { $fail++; Write-Host "Chyba skupiny: $group" -ForegroundColor Yellow }
        }
    }
    Write-Host "Skupiny: OK=$ok, Chyba=$fail" -ForegroundColor Green
    Write-IntuneLog -Message "Skupiny: OK=$ok, Chyba=$fail" -Level INFO -LogFile $LogFile

    # Zobrazenie hesla operatorovi AZ po uspesnom vytvoreni – nie skor
    Write-Host "`n------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Vygenerovane heslo (odovzdajte osobne): " -NoNewline
    Write-Host $password -ForegroundColor Yellow
    Write-Host "UPOZORNENIE: Toto heslo sa uz znova nezobrazí." -ForegroundColor Red
    Write-Host "------------------------------------------`n" -ForegroundColor DarkGray

    # -----------------------------------------------------------------------
    # DOPLNKOVE SLUZBY (AUTO-ENABLE)
    # -----------------------------------------------------------------------
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    $askEnable = Read-Host "DOPLNOK: Naplanovat automaticke zapnutie uctu? (A/N)"

    if ($askEnable -eq "A") {
        $autoEnableDate = $null
        do {
            $dateStr = Read-Host " -> Zadajte datum aktivacie (dd.MM.yyyy)"
            try {
                $autoEnableDate = [DateTime]::ParseExact($dateStr, "dd.MM.yyyy", $null).Date.AddHours(6)
                if ($autoEnableDate -le (Get-Date)) {
                    Write-Host "    CHYBA: Datum musi byt v buducnosti!" -ForegroundColor Red
                    $autoEnableDate = $null
                }
            }
            catch { Write-Host "    CHYBA: Nespravny format datumu." -ForegroundColor Red }
        } until ($autoEnableDate)

        # 1. Update Description
        $newDescription = "[AUTO-ENABLE: $($autoEnableDate.ToString('dd.MM.yyyy'))] " + $templateFull.Description
        if ($TestMode) { Write-Host "WHATIF: Update popis..." -ForegroundColor Cyan }
        else {
            try { Set-ADUser -Identity $newSam -Description $newDescription -ErrorAction Stop }
            catch { Write-Warning "Chyba popisu: $_" }
        }

        # 2. Vytvorenie Tasku
        # OPRAVA: Prikaz ulozeny do docasneho ps1 suboru – ziadne citlive udaje v inline -Command retazci
        $taskName = "Enable-ADUser-$newSam"
        $taskScriptDir = "C:\TaurisIT\Tasks"
        $taskScriptPath = "$taskScriptDir\$taskName.ps1"

        $taskScriptContent = @"
Import-Module ActiveDirectory -ErrorAction Stop
Set-ADUser -Identity '$newSam' -Enabled `$true -ErrorAction Stop
Write-EventLog -LogName Application -Source 'ADUserCloneApp' -EventId 100 -EntryType Information -Message 'Ucet $newSam bol automaticky povoleny.'
"@

        Write-Host " -> Planujem ulohu '$taskName' na $($autoEnableDate)..." -ForegroundColor Yellow

        if ($TestMode) {
            Write-Host "WHATIF: Vytvorenie skriptu: $taskScriptPath" -ForegroundColor Cyan
            Write-Host "WHATIF: Register-ScheduledTask..." -ForegroundColor Cyan
        }
        else {
            try {
                # Vytvorenie adresara pre skripty taskov
                if (-not (Test-Path $taskScriptDir)) {
                    New-Item -Path $taskScriptDir -ItemType Directory -Force | Out-Null
                }
                # Zapis prikazu do suboru – nie do inline -Command
                $taskScriptContent | Out-File -FilePath $taskScriptPath -Encoding UTF8 -Force

                $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$taskScriptPath`""
                $trigger = New-ScheduledTaskTrigger -Once -At $autoEnableDate

                # OPRAVA: Explicitny RunLevel, bez -User = bezi pod SYSTEM (bezpecnejsie ako aktualna relacia)
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description "Auto-Enable $newSam" -ErrorAction Stop | Out-Null

                Write-Host " -> Uloha uspesne vytvorena. Skript: $taskScriptPath" -ForegroundColor Green
                Write-IntuneLog -Message "Doplnok: Naplanovany Auto-Enable na $($autoEnableDate). Skript: $taskScriptPath" -Level INFO -LogFile $LogFile
            }
            catch {
                Write-Host "CHYBA ulohy: $_" -ForegroundColor Red
                Write-IntuneLog -Message "Doplnok: Chyba Task: $_" -Level ERROR -LogFile $LogFile
            }
        }
    }
}
catch {
    Write-Host "KRITICKA CHYBA: $_" -ForegroundColor Red
    Write-IntuneLog -Message "Kriticka chyba: $_" -Level ERROR -LogFile $LogFile
}

Write-IntuneLog -Message "Koniec aplikacie" -Level INFO -LogFile $LogFile