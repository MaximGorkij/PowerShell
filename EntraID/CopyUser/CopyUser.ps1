#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Vytvorenie noveho konta v AD ako kopia ineho konta.

.DESCRIPTION
    Skript vykona nasledovne kroky:
    - Na zaklade existujuceho konta vytvori nove konto
    - EmployeeID a email sa doplnia podla vstupu
    - Email je kontrolovany na jedinecnost
    - Heslo je v tvare TaurisYYYYMMDD
    - Zalohuje sa zoznam AD a O365 skupin (s rollback suborom)
    - Povodny ucet sa presunie do Disabled OU, zakaze, odoberie sa zo skupin, mailbox sa zmeni na shared
    - Vsetko sa loguje pomocou Write-CustomLog

.PARAMETER TestMode
    Prepinac pre testovaci rezim - zobrazuje akcie bez ich vykonania

.AUTHOR
    Marek Findrik

.VERSION
    2.1

.USAGE
    .\script.ps1 -OriginalSam "jan.novak" -Meno "Peter" -Priezvisko "Kovac" -EmployeeID "12345"
    .\script.ps1 -OriginalSam "jan.novak" -Meno "Peter" -Priezvisko "Kovac" -EmployeeID "12345" -TestMode
    #>

# Logovacia funkcia
function Write-CustomLog {
    param (
        [string]$Message,
        [string]$EventSource,
        [string]$LogFileName,
        [string]$EventLogName = "CustomizeAD",
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"
    )

    $LogDirectory = "C:\TaurisIT\Log\ADUsers"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $LogFilePath = Join-Path $LogDirectory $LogFileName
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8

    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try { 
            New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction SilentlyContinue
        } 
        catch {
            # Ignore event log creation errors in test mode
        }
    }

    switch ($Type) {
        "Information" { $EventId = 1000 }
        "Warning" { $EventId = 2000 }
        "Error" { $EventId = 3000 }
    }

    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore event log writing errors
    }
}

# ===== HLAVNY SKRIPT =====
param(
    [Parameter(Mandatory = $true)][string]$OriginalSam,
    [Parameter(Mandatory = $true)][string]$Meno,
    [Parameter(Mandatory = $true)][string]$Priezvisko,
    [Parameter(Mandatory = $true)][string]$EmployeeID,
    [switch]$TestMode
)

$Datum = Get-Date -Format "yyyyMMdd"
$Nazov = "$Datum-$Priezvisko"
$LogFile = "$Nazov.log"

if ($TestMode) {
    Write-Host "=== TESTOVACI REZIM ===" -ForegroundColor Yellow
    Write-CustomLog -Message "Spustenie skriptu v TESTOVACOM REZIME pre kopiu konta $OriginalSam" -EventSource "ADUserClone" -LogFileName $LogFile -Type Warning
}
else {
    Write-CustomLog -Message "Spustenie skriptu pre kopiu konta $OriginalSam" -EventSource "ADUserClone" -LogFileName $LogFile
}

# Inicializacia premennych
$BackupDirectory = "C:\TaurisIT\Backup\ADUsers"
if (-not (Test-Path $BackupDirectory)) {
    if ($TestMode) {
        Write-Host "[TEST] Vytvoril by sa adresar: $BackupDirectory" -ForegroundColor Gray
    }
    else {
        New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
    }
}

try {
    if ($TestMode) {
        Write-Host "[TEST] Nacitanie modulov ActiveDirectory a ExchangeOnlineManagement" -ForegroundColor Gray
    }
    else {
        Import-Module ActiveDirectory -ErrorAction Stop
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
    }
}
catch {
    $errorMsg = "Nepodarilo sa nacitat moduly: $_"
    Write-CustomLog -Message $errorMsg -EventSource "ADUserClone" -LogFileName $LogFile -Type Error
    if (-not $TestMode) { exit 1 }
}

# Najdenie originalneho konta
if ($TestMode) {
    Write-Host "[TEST] Hladanie originalneho uzivatela: $OriginalSam" -ForegroundColor Gray
    # Simulacia najdenia uzivatela
    $OriginalUser = @{
        SamAccountName    = $OriginalSam
        Mail              = "$OriginalSam@tauris.sk"
        DistinguishedName = "CN=$OriginalSam,OU=Users,DC=tauris,DC=local"
    }
}
else {
    $OriginalUser = Get-ADUser -Identity $OriginalSam -Properties * -ErrorAction Stop
}

if (-not $OriginalUser) {
    $errorMsg = "Originalny uzivatel $OriginalSam nenajdeny"
    Write-CustomLog -Message $errorMsg -EventSource "ADUserClone" -LogFileName $LogFile -Type Error
    if (-not $TestMode) { exit 1 }
}

# Generovanie unikatneho emailu
function New-UniqueEmail($Meno, $Priezvisko) {
    $Base = $Priezvisko.ToLower()
    $Domain = "tauris.sk"
    $Email = "$Base@$Domain"

    if ($TestMode) {
        Write-Host "[TEST] Kontrola jedinecnosti emailu: $Email" -ForegroundColor Gray
        # V testovacom rezime predpokladame, ze email je jedinecny
        return $Email
    }

    $i = 1
    while (Get-ADUser -Filter { Mail -eq $Email }) {
        $Prefix = $Priezvisko.ToLower() + $Meno.Substring(0, $i).ToLower()
        $Email = "$Prefix@$Domain"
        $i++
        if ($i -gt 10) { break } # Bezpecnostny limit
    }
    return $Email
}

$Email = New-UniqueEmail -Meno $Meno -Priezvisko $Priezvisko
$SamAccountName = ($Priezvisko.Substring(0, [Math]::Min(8, $Priezvisko.Length)) + $Meno.Substring(0, 1)).ToLower()
$DisplayName = "$Meno $Priezvisko"
$OU = "OU=Users,DC=tauris,DC=local"
$Password = "Tauris$Datum"

if ($TestMode) {
    Write-Host "[TEST] Vygenerovane udaje pre nove konto:" -ForegroundColor Cyan
    Write-Host "  SamAccountName: $SamAccountName" -ForegroundColor Cyan
    Write-Host "  Email: $Email" -ForegroundColor Cyan
    Write-Host "  DisplayName: $DisplayName" -ForegroundColor Cyan
    Write-Host "  Heslo: $Password" -ForegroundColor Cyan
    Write-Host "  OU: $OU" -ForegroundColor Cyan
}

# Zalohovanie skupin
if ($TestMode) {
    Write-Host "[TEST] Zalohovanie AD a O365 skupin do: $BackupDirectory\$Nazov-*.txt" -ForegroundColor Gray
    # Simulacia ziskania skupin
    $ADGroups = @("Skupina1", "Skupina2", "Skupina3")
    $O365Groups = @("O365Skupina1", "O365Skupina2")
}
else {
    $ADGroups = Get-ADUser $OriginalSam -Property MemberOf | Select-Object -ExpandProperty MemberOf
    $O365Groups = Get-DistributionGroup | Where-Object { (Get-DistributionGroupMember $_.Identity -ResultSize Unlimited -ErrorAction SilentlyContinue | Where-Object { $_.PrimarySmtpAddress -eq $OriginalUser.Mail }) } | Select-Object -ExpandProperty Identity
}

if ($TestMode) {
    Write-Host "[TEST] Najdene AD skupiny: $($ADGroups -join ', ')" -ForegroundColor Gray
    Write-Host "[TEST] Najdene O365 skupiny: $($O365Groups -join ', ')" -ForegroundColor Gray
}
else {
    $ADGroups | Out-File -FilePath "$BackupDirectory\$Nazov-ADGroups.txt" -Encoding UTF8
    $O365Groups | Out-File -FilePath "$BackupDirectory\$Nazov-O365Groups.txt" -Encoding UTF8
}

# Vytvorenie noveho konta
if ($TestMode) {
    Write-Host "[TEST] VYTVORENIE NOVEHO KONTA:" -ForegroundColor Yellow
    Write-Host "  New-ADUser -SamAccountName $SamAccountName" -ForegroundColor Gray
    Write-Host "  -UserPrincipalName $SamAccountName@tauris.local" -ForegroundColor Gray
    Write-Host "  -Name '$DisplayName'" -ForegroundColor Gray
    Write-Host "  -EmailAddress $Email" -ForegroundColor Gray
    Write-Host "  -EmployeeID $EmployeeID" -ForegroundColor Gray
    Write-Host "  -Path '$OU'" -ForegroundColor Gray
}
else {
    try {
        New-ADUser -SamAccountName $SamAccountName `
            -UserPrincipalName "$SamAccountName@tauris.local" `
            -Name $DisplayName `
            -GivenName $Meno `
            -Surname $Priezvisko `
            -DisplayName $DisplayName `
            -EmailAddress $Email `
            -EmployeeID $EmployeeID `
            -Path $OU `
            -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
            -Enabled $true -PasswordNeverExpires $false -ChangePasswordAtLogon $false

        Write-CustomLog -Message "Konto $SamAccountName bolo uspesne vytvorene s emailom $Email" -EventSource "ADUserClone" -LogFileName $LogFile
    }
    catch {
        Write-CustomLog -Message "Chyba pri vytvarani konta: $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Error
    }
}

# Priradenie skupin
if ($TestMode) {
    Write-Host "[TEST] PRIADRANIE SKUPIN:" -ForegroundColor Yellow
    foreach ($Group in $ADGroups) {
        Write-Host "  Add-ADGroupMember -Identity $Group -Members $SamAccountName" -ForegroundColor Gray
    }
    foreach ($Group in $O365Groups) {
        Write-Host "  Add-DistributionGroupMember -Identity $Group -Member $Email" -ForegroundColor Gray
    }
}
else {
    foreach ($Group in $ADGroups) {
        try { 
            Add-ADGroupMember -Identity $Group -Members $SamAccountName -ErrorAction SilentlyContinue
        } 
        catch {
            Write-CustomLog -Message "Chyba pri pridavani do AD skupiny $Group : $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Warning
        }
    }
    foreach ($Group in $O365Groups) {
        try { 
            Add-DistributionGroupMember -Identity $Group -Member $Email -ErrorAction SilentlyContinue
        } 
        catch {
            Write-CustomLog -Message "Chyba pri pridavani do O365 skupiny $Group : $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Warning
        }
    }
}

# Uprava originalneho uctu
if ($TestMode) {
    Write-Host "[TEST] UPRAVA ORIGINALNEHO UCTU:" -ForegroundColor Yellow
    Write-Host "  Move-ADObject -Identity '$($OriginalUser.DistinguishedName)' -TargetPath 'OU=Disabled,DC=tauris,DC=local'" -ForegroundColor Gray
    Write-Host "  Disable-ADAccount -Identity $OriginalSam" -ForegroundColor Gray
    foreach ($Group in $ADGroups) {
        Write-Host "  Remove-ADGroupMember -Identity $Group -Members $OriginalSam -Confirm:`$false" -ForegroundColor Gray
    }
    foreach ($Group in $O365Groups) {
        Write-Host "  Remove-DistributionGroupMember -Identity $Group -Member $($OriginalUser.Mail) -Confirm:`$false" -ForegroundColor Gray
    }
    Write-Host "  Connect-ExchangeOnline" -ForegroundColor Gray
    Write-Host "  Set-Mailbox -Identity $($OriginalUser.Mail) -Type Shared" -ForegroundColor Gray
    Write-Host "  Disconnect-ExchangeOnline -Confirm:`$false" -ForegroundColor Gray
}
else {
    try {
        Move-ADObject -Identity $OriginalUser.DistinguishedName -TargetPath "OU=Disabled,DC=tauris,DC=local"
        Disable-ADAccount -Identity $OriginalSam
        foreach ($Group in $ADGroups) { 
            try {
                Remove-ADGroupMember -Identity $Group -Members $OriginalSam -Confirm:$false -ErrorAction SilentlyContinue
            }
            catch {
                Write-CustomLog -Message "Chyba pri odstranovani z AD skupiny $Group : $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Warning
            }
        }
        foreach ($Group in $O365Groups) { 
            try {
                Remove-DistributionGroupMember -Identity $Group -Member $OriginalUser.Mail -Confirm:$false -ErrorAction SilentlyContinue
            }
            catch {
                Write-CustomLog -Message "Chyba pri odstranovani z O365 skupiny $Group : $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Warning
            }
        }

        # Zmena mailboxu na Shared
        try {
            Connect-ExchangeOnline -ErrorAction Stop
            Set-Mailbox -Identity $OriginalUser.Mail -Type Shared
            Disconnect-ExchangeOnline -Confirm:$false
        }
        catch {
            Write-CustomLog -Message "Chyba pri zmene typu mailboxu: $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Warning
        }

        Write-CustomLog -Message "Originalny ucet $OriginalSam bol presunuty do Disabled OU, zakazany a mailbox nastaveny na Shared" -EventSource "ADUserClone" -LogFileName $LogFile
    }
    catch {
        Write-CustomLog -Message "Chyba pri uprave originalneho uctu: $_" -EventSource "ADUserClone" -LogFileName $LogFile -Type Error
    }
}

if ($TestMode) {
    Write-Host "[TEST] Skript by bol uspesne dokonceny" -ForegroundColor Green
    Write-Host "=== KONIEC TESTOVACIEHO REZIMU ===" -ForegroundColor Yellow
}
else {
    Write-CustomLog -Message "Skript dokonceny" -EventSource "ADUserClone" -LogFileName $LogFile
}