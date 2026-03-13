#Requires -Modules ActiveDirectory
<# 
.SYNOPSIS
    Klonovanie AD uctu s logovanim + TEST/WHATIF rezim
.DESCRIPTION
    Vyhlada vzoroveho pouzivatela a vytvori noveho.
    - EmployeeID: 5 alebo 7 miest (musi zacinat 0).
    - Kontrola duplicity Meno+Priezvisko.
    - Logika domeny: masiarstvoubyka.sk vs tauris.sk.
    - Suhlas so suhrnom (Summary) pred vytvorenim.
    - Zaloha clenstva v AD a Cloud skupinach do TXT suboru.
    - Doplnkova sluzba: Auto-Enable.
    - Doplnkova sluzba: Cloud skupiny cez Scheduled Task (+45min).
.NOTES
    Verzia: 4.1
    Autor: Automaticky report
    Pozadovane moduly: ActiveDirectory, LogHelper, ScheduledTasks, Microsoft.Graph.Groups, Microsoft.Graph.Users
    Datum vytvorenia: $(Get-Date -Format 'dd.MM.yyyy')
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
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

# ---------------------------------------------------------------------------
# NASTAVENIA
# ---------------------------------------------------------------------------
$TestMode = ($Mode -eq "test")
$UseWhatIf = $TestMode

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
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
    try {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Warning "Nepodarilo sa vytvorit adresar logov: $_"
    }
}

Import-Module ActiveDirectory

$LogModuleLoaded = $false
if (Test-Path $ModulePath) {
    try {
        Import-Module $ModulePath -Force -ErrorAction Stop
        $LogModuleLoaded = $true
    }
    catch {
        Write-Warning "LogHelper chyba: $_"
    }
}

# Fallback ak LogHelper nie je dostupny
if (-not $LogModuleLoaded) {
    function Write-CustomLog {
        param (
            [Parameter(Mandatory = $true)][string]$Message,
            [Parameter(Mandatory = $true)][string]$EventSource,
            [string]$EventLogName = "IntuneScript",
            [Parameter(Mandatory = $true)][string]$LogFileName,
            [ValidateSet("Information", "Warning", "Error")][string]$Type = "Information"
        )
        Write-Host "[$Type] $Message" -ForegroundColor DarkGray
    }
}

$modeMsg = if ($TestMode) { "TEST/WHATIF" } else { "PROD" }
Write-CustomLog -Message "Start aplikacie [$modeMsg] v4.1. LogFile: $LogFile" `
    -EventSource $EventSource -LogFileName $LogFile -Type Information

# ---------------------------------------------------------------------------
# VYHLADANIE PREDLOHY
# ---------------------------------------------------------------------------

$searchName = Read-Host "Zadaj priezvisko vzoroveho pouzivatela"
Write-CustomLog -Message "Hladam: $searchName" -EventSource $EventSource -LogFileName $LogFile -Type Information

$users = @(Get-ADUser -Filter "Surname -like '*$searchName*'" `
        -Properties DisplayName, UserPrincipalName, EmailAddress, SamAccountName)

if ($users.Count -eq 0) {
    Write-Host "Nenaslo sa nic." -ForegroundColor Red
    Write-CustomLog -Message "Ziadny vysledok pre: $searchName" `
        -EventSource $EventSource -LogFileName $LogFile -Type Warning
    return
}

Write-Host "`nNajdene:" -ForegroundColor Cyan
for ($i = 0; $i -lt $users.Count; $i++) {
    Write-Host "[$i] $($users[$i].DisplayName) ($($users[$i].UserPrincipalName))"
}

# Vynuteny vyber cisla
$validSelection = $false
$selectedIndex = -1
do {
    $choice = Read-Host "`nVyberte cislo (0 - $(($users.Count) - 1))"
    if ($choice -match '^\d+$') {
        $selectedIndex = [int]$choice
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $users.Count) {
            $validSelection = $true
        }
        else {
            Write-Host "CHYBA: Cislo je mimo rozsahu!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "CHYBA: Musite zadat cislo!" -ForegroundColor Red
    }
} until ($validSelection)

$template = $users[$selectedIndex]
Write-CustomLog -Message "Vybrata predloha: $($template.UserPrincipalName)" `
    -EventSource $EventSource -LogFileName $LogFile -Type Information

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
$dupUsers = Get-ADUser -Filter "GivenName -eq '$newName' -and Surname -eq '$newSurname'" `
    -Properties DisplayName, SamAccountName, Enabled
if ($dupUsers) {
    Write-Host "`n!!! POZOR: V AD UZ EXISTUJE UZIVATEL S TYMTO MENOM !!!" `
        -ForegroundColor Red -BackgroundColor Yellow
    foreach ($u in $dupUsers) {
        Write-Host " -> $($u.DisplayName) (Login: $($u.SamAccountName), Aktivny: $($u.Enabled))" `
            -ForegroundColor Red
    }
    $continue = Read-Host "`nChcete napriek tomu pokracovat? (A/N)"
    if ($continue -ne "A") {
        Write-Host "Ukoncene uzivatelom." -ForegroundColor Yellow
        return
    }
}

# --- EMAIL LOGIKA (Masiarstvo vs Tauris) ---
$sourceEmail = $template.UserPrincipalName
if ([string]::IsNullOrEmpty($sourceEmail)) { $sourceEmail = $template.EmailAddress }

$domainPart = "@tauris.sk"
if ($sourceEmail -match "@masiarstvoubyka.sk") {
    $domainPart = "@masiarstvoubyka.sk"
}

$emailPrefixInput = Read-Host "Email (pred $domainPart)"
if ($emailPrefixInput -match "@") { $emailPrefixInput = $emailPrefixInput.Split('@')[0] }
$newEmail = "$emailPrefixInput$domainPart"
Write-Host " -> Vysledny email: $newEmail" -ForegroundColor Gray

# --- EMPLOYEE ID (5 alebo 7 MIEST) ---
do {
    $empIDInput = Read-Host "Employee ID (5 alebo 7 miest, musi zacinat 0)"
    if ($empIDInput -match "^(0\d{4}|0\d{6})$") {
        $newEmpID = $empIDInput
        $empIDValid = $true
    }
    else {
        Write-Host "CHYBA: ID musi mat 5 alebo 7 cislic a zacinat nulou (napr. 01234 alebo 0123456)." `
            -ForegroundColor Red
        $empIDValid = $false
    }
} until ($empIDValid)

# --- SAM LOGIN ---
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
$newSam = if ([string]::IsNullOrWhiteSpace($newSamInput)) { $candidateSam } else { $newSamInput }

# --- TELEFON ---
do {
    $phoneInput = Read-Host "Telefon (zadajte 09XXXXXXXX)"
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

$password = "Tauris$(Get-Date -Format yyyy)"
$passwordSecure = ConvertTo-SecureString $password -AsPlainText -Force

Write-CustomLog -Message "Priprava: $newSam ($displayName). Tel: $newPhone. ID: $newEmpID" `
    -EventSource $EventSource -LogFileName $LogFile -Type Information

# ---------------------------------------------------------------------------
# KONTROLA EXISTENCIE UDAJOV (Technicka duplicita)
# ---------------------------------------------------------------------------
Write-Host "`nPrebieha technicka kontrola..." -ForegroundColor Yellow

if (Get-ADUser -Filter "SamAccountName -eq '$newSam'" -ErrorAction SilentlyContinue) {
    Write-Host "CHYBA: Login '$newSam' uz existuje!" -ForegroundColor Red
    return
}
if (Get-ADObject -Filter "mail -eq '$newEmail' -or proxyAddresses -like '*$newEmail'" `
        -Properties mail -ErrorAction SilentlyContinue) {
    Write-Host "CHYBA: Email '$newEmail' uz je obsadeny!" -ForegroundColor Red
    return
}

# ---------------------------------------------------------------------------
# PRIPRAVA DAT Z PREDLOHY & ZALOHA SKUPIN
# ---------------------------------------------------------------------------
$propsToLoad = @(
    "MemberOf", "Description", "Title", "Department", "Company",
    "StreetAddress", "City", "PostalCode", "State", "Country",
    "Manager", "PhysicalDeliveryOfficeName"
)
$templateFull = Get-ADUser $template.DistinguishedName -Properties $propsToLoad

$dn = $templateFull.DistinguishedName
$targetOU = $dn -replace '^CN=.+?,(?=OU=|CN=)', ''

if ([string]::IsNullOrEmpty($targetOU) -or $targetOU -eq $dn) { 
    throw "Nepodarilo sa urcit rodicovsku cestu z DN: $dn" 
}

$managerName = "---"
if ($templateFull.Manager) {
    $mgrObj = Get-ADUser $templateFull.Manager -Properties DisplayName
    $managerName = $mgrObj.DisplayName
}

# --- NACITANIE CLOUD SKUPIN PRED ZOBRAZENIM SUHRNU ---
$cloudGroups = @()
Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
$askCloud = Read-Host "Chcete preniest aj CLOUD skupiny? (Vyžaduje prihlásenie do M365) (A/N)"

if ($askCloud -eq "A") {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
        Write-Host "CHYBA: Modul Microsoft.Graph.Groups nie je nainstalovany." -ForegroundColor Red
        $askCloud = "N"
    }
    else {
        Import-Module Microsoft.Graph.Groups -Force
        Import-Module Microsoft.Graph.Users  -Force

        try {
            Connect-MgGraph -Scopes "GroupMember.ReadWrite.All", "User.Read.All" -NoWelcome -ErrorAction Stop
            Write-Host " -> Graph pripojenie OK. Nacitavam clenstvo..." -ForegroundColor Green

            $mgTemplate = Get-MgUser -UserId $templateFull.UserPrincipalName -Property Id -ErrorAction Stop
            $cloudGroups = Get-MgUserMemberOf -UserId $mgTemplate.Id -All |
            Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' } |
            ForEach-Object {
                Get-MgGroup -GroupId $_.Id -Property Id, DisplayName, OnPremisesSyncEnabled
            } |
            Where-Object { $_.OnPremisesSyncEnabled -ne $true }

            Write-Host " -> Najdenych cloud skupin predlohy: $($cloudGroups.Count)" -ForegroundColor Cyan
        }
        catch {
            Write-Host "CHYBA Graph: $_" -ForegroundColor Red
            Write-CustomLog -Message "Cloud skupiny: Graph chyba - $_" `
                -EventSource $EventSource -LogFileName $LogFile -Type Error
        }
    }
}

# --- VYTVORENIE ZALOHY CLENSTVA DO TXT ---
$backupFileName = "$Timestamp-Skupiny-$($templateFull.SamAccountName).txt"
$backupFilePath = Join-Path $LogDir $backupFileName
$backupContent = "ZALOHA SKUPIN PRE PREDLOHU: $($templateFull.DisplayName) ($($templateFull.UserPrincipalName))`r`n"
$backupContent += "Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')`r`n"
$backupContent += "=============================================================`r`n"
$backupContent += "AD Skupiny ($($templateFull.MemberOf.Count)):`r`n"
foreach ($g in $templateFull.MemberOf) {
    $backupContent += " - $g`r`n"
}

if ($cloudGroups.Count -gt 0) {
    $backupContent += "`r`nCloud Skupiny ($($cloudGroups.Count)):`r`n"
    foreach ($cg in $cloudGroups) {
        $backupContent += " - $($cg.DisplayName) (ID: $($cg.Id))`r`n"
    }
}
$backupContent | Out-File -FilePath $backupFilePath -Encoding UTF8
Write-CustomLog -Message "Zaloha skupin ulozena do: $backupFilePath" -EventSource $EventSource -LogFileName $LogFile -Type Information

# ---------------------------------------------------------------------------
# SUHRN (SUMMARY SCREEN)
# ---------------------------------------------------------------------------
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "          SUHRN NOVEHO UZIVATELA          " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Zobrazovane meno  : " -NoNewline; Write-Host $displayName -ForegroundColor Green
Write-Host "Email             : " -NoNewline; Write-Host $newEmail     -ForegroundColor Green
Write-Host "Telefon           : " -NoNewline; Write-Host $newPhone     -ForegroundColor Green
Write-Host "Osobne cislo (ID) : " -NoNewline; Write-Host $newEmpID     -ForegroundColor Green
Write-Host "Login (SAM)       : " -NoNewline; Write-Host $newSam       -ForegroundColor Green
Write-Host "Heslo             : " -NoNewline; Write-Host $password      -ForegroundColor Green
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host "PRENESENE ZAZNAMY (Zo vzoru):" -ForegroundColor Yellow
Write-Host "Zdrojova OU       : $targetOU"
Write-Host "Manazer           : $managerName"
Write-Host "Kancelaria        : $(if ($templateFull.PhysicalDeliveryOfficeName) { $templateFull.PhysicalDeliveryOfficeName } else { '---' })"
Write-Host "Adresa            : $(if ($templateFull.City) { $templateFull.City + ', ' + $templateFull.StreetAddress } else { '---' })"
Write-Host "Zaloha skupin TXT : Ulozene v zlozke Log"
Write-Host "Pocet AD Skupin   : $($templateFull.MemberOf.Count)"
if ($askCloud -eq "A") {
    Write-Host "Pocet Cloud Skupin: $($cloudGroups.Count) (Prenos o 45 min)"
}
Write-Host "==========================================" -ForegroundColor Cyan

$confirm = Read-Host "Suhlasite s vytvorenim uctu? (A/N)"
if ($confirm -ne "A") {
    Write-Host "Akcia zrusena uzivatelom." -ForegroundColor Red
    return
}

# ---------------------------------------------------------------------------
# VYTVORENIE UCTU (CORE)
# ---------------------------------------------------------------------------
try {
    Write-CustomLog -Message "Cielova cesta: $targetOU" `
        -EventSource $EventSource -LogFileName $LogFile -Type Information

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

    if ($TestMode) {
        Write-Host "`n[WHATIF] Ucet vytvoreny (simulacia)." -ForegroundColor Cyan
    }
    else {
        Write-Host "`nUcet $displayName uspesne vytvoreny." -ForegroundColor Green
    }

    Write-CustomLog -Message "Ucet $newSam spracovany (WhatIf=$UseWhatIf)" `
        -EventSource $EventSource -LogFileName $LogFile -Type Information

    # -----------------------------------------------------------------------
    # AD SKUPINY
    # -----------------------------------------------------------------------
    $adOk = 0; $adFail = 0
    foreach ($group in $templateFull.MemberOf) {
        if ($TestMode) {
            Write-Host "WHATIF: AD skupina -> $group" -ForegroundColor DarkGray
            $adOk++
        }
        else {
            try {
                Add-ADGroupMember -Identity $group -Members $newSam -ErrorAction Stop
                $adOk++
            }
            catch {
                $adFail++
                Write-Host "Chyba AD skupiny: $group" -ForegroundColor Yellow
            }
        }
    }
    Write-Host "AD Skupiny: OK=$adOk, Chyba=$adFail" -ForegroundColor Green
    Write-CustomLog -Message "AD skupiny: OK=$adOk, Chyba=$adFail" `
        -EventSource $EventSource -LogFileName $LogFile -Type Information

    # -----------------------------------------------------------------------
    # CLOUD SKUPINY - Scheduled Task (+45min)
    # -----------------------------------------------------------------------
    if ($askCloud -eq "A" -and $cloudGroups.Count -gt 0) {
        $groupIdsCsv = ($cloudGroups.Id) -join ","
        $taskRunTime = (Get-Date).AddMinutes(45)
        $taskName = "CloudGroups-$newSam"

        $taskScript = @"
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users
Connect-MgGraph -Scopes 'GroupMember.ReadWrite.All','User.Read.All' -NoWelcome
`$targetUpn = '$newEmail'
`$groupIds  = '$groupIdsCsv' -split ','
`$mgUser    = Get-MgUser -UserId `$targetUpn -Property Id -ErrorAction Stop
`$ok   = 0
`$fail = 0
foreach (`$gid in `$groupIds) {
    try {
        New-MgGroupMember -GroupId `$gid -DirectoryObjectId `$mgUser.Id -ErrorAction Stop
        `$ok++
    }
    catch {
        `$fail++
        Write-EventLog -LogName Application -Source 'ADUserCloneApp' -EventId 101 `
            -EntryType Warning -Message "Cloud skupina `$gid CHYBA: `$_"
    }
}
Write-EventLog -LogName Application -Source 'ADUserCloneApp' -EventId 100 `
    -EntryType Information `
    -Message "Cloud skupiny pre $newEmail dokoncene: OK=`$ok, Chyba=`$fail"
"@
        $encodedCmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($taskScript))

        Write-Host " -> Planujem task '$taskName' na $taskRunTime..." -ForegroundColor Yellow

        if ($TestMode) {
            Write-Host "WHATIF: Register-ScheduledTask '$taskName' - $($cloudGroups.Count) skupin" -ForegroundColor Cyan
            Write-CustomLog -Message "Cloud skupiny WHATIF: task $taskName, skupin=$($cloudGroups.Count)" `
                -EventSource $EventSource -LogFileName $LogFile -Type Information
        }
        else {
            try {
                $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedCmd"
                $trigger = New-ScheduledTaskTrigger -Once -At $taskRunTime

                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
                    -Description "Cloud skupiny pre $newSam ($newEmail)" -RunLevel Highest -ErrorAction Stop | Out-Null

                Write-Host " -> Task uspesne zaregistrovany. Spusti sa o 45 minut ($taskRunTime)." -ForegroundColor Green
                Write-CustomLog -Message "Cloud skupiny: task $taskName zaregistrovany na $taskRunTime, skupin=$($cloudGroups.Count)" `
                    -EventSource $EventSource -LogFileName $LogFile -Type Information
            }
            catch {
                Write-Host "CHYBA registracie tasku: $_" -ForegroundColor Red
                Write-CustomLog -Message "Cloud skupiny: chyba registracie tasku - $_" `
                    -EventSource $EventSource -LogFileName $LogFile -Type Error
            }
        }
    }

    # -----------------------------------------------------------------------
    # DOPLNKOVA SLUZBA - AUTO-ENABLE
    # -----------------------------------------------------------------------
    Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
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
            catch {
                Write-Host "    CHYBA: Nespravny format datumu." -ForegroundColor Red
            }
        } until ($autoEnableDate)

        # Update Description
        $newDescription = "[AUTO-ENABLE: $($autoEnableDate.ToString('dd.MM.yyyy'))] " + $templateFull.Description
        if ($TestMode) {
            Write-Host "WHATIF: Update popis uctu..." -ForegroundColor Cyan
        }
        else {
            try {
                Set-ADUser -Identity $newSam -Description $newDescription -ErrorAction Stop
            }
            catch {
                Write-Warning "Chyba aktualizacie popisu: $_"
            }
        }

        # Vytvorenie Tasku
        $enableTaskName = "Enable-ADUser-$newSam"
        $enableCmd = "Import-Module ActiveDirectory; Set-ADUser -Identity '$newSam' -Enabled `$true; " +
        "Write-EventLog -LogName Application -Source 'ADUserCloneApp' -EventId 100 " +
        "-EntryType Information -Message 'Ucet $newSam bol automaticky povoleny.'"

        Write-Host " -> Planujem ulohu '$enableTaskName' na $autoEnableDate..." -ForegroundColor Yellow

        if ($TestMode) {
            Write-Host "WHATIF: Register-ScheduledTask Auto-Enable..." -ForegroundColor Cyan
        }
        else {
            try {
                $enableAction = New-ScheduledTaskAction -Execute "PowerShell.exe" `
                    -Argument "-NoProfile -WindowStyle Hidden -Command `"$enableCmd`""
                $enableTrigger = New-ScheduledTaskTrigger -Once -At $autoEnableDate

                Register-ScheduledTask -TaskName $enableTaskName -Action $enableAction -Trigger $enableTrigger `
                    -Description "Auto-Enable $newSam" -RunLevel Highest -ErrorAction Stop | Out-Null

                Write-Host " -> Uloha Auto-Enable uspesne vytvorena." -ForegroundColor Green
                Write-CustomLog -Message "Doplnok: Naplanovany Auto-Enable na $autoEnableDate" `
                    -EventSource $EventSource -LogFileName $LogFile -Type Information
            }
            catch {
                Write-Host "CHYBA ulohy Auto-Enable: $_" -ForegroundColor Red
                Write-CustomLog -Message "Doplnok: Chyba Auto-Enable Task - $_" `
                    -EventSource $EventSource -LogFileName $LogFile -Type Error
            }
        }
    }
}
catch {
    Write-Host "KRITICKA CHYBA: $_" -ForegroundColor Red
    Write-CustomLog -Message "Kriticka chyba: $_" -EventSource $EventSource -LogFileName $LogFile -Type Error
}

Write-CustomLog -Message "Koniec aplikacie" -EventSource $EventSource -LogFileName $LogFile -Type Information