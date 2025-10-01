#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Rollback skript pre obnovu povodneho AD uctu a skupin.

.DESCRIPTION
    Skript podla priezviska najde najnovsi backup subor v adresari C:\TaurisIT\Backup\ADUsers
    a vrati povodny ucet do AD a O365 skupin. Volitelne odstrani klon.

.PARAMETER TestMode
    Prepinac pre testovaci rezim - zobrazuje akcie bez ich vykonania

.AUTHOR
    Marek Findrik

.VERSION
    1.2

.USAGE
    .\rollback.ps1 -OriginalSam "jan.novak" -Priezvisko "Kovac" -RemoveClone
    .\rollback.ps1 -OriginalSam "jan.novak" -Priezvisko "Kovac" -RemoveClone -TestMode
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

# ===== HLAVNY ROLLBACK =====
param(
    [Parameter(Mandatory = $true)][string]$OriginalSam,
    [Parameter(Mandatory = $true)][string]$Priezvisko,
    [switch]$RemoveClone,
    [switch]$TestMode
)

$BackupDirectory = "C:\TaurisIT\Backup\ADUsers"
if (-not (Test-Path $BackupDirectory)) {
    if ($TestMode) {
        Write-Host "[TEST] Vytvoril by sa adresar: $BackupDirectory" -ForegroundColor Gray
    }
    else {
        New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
    }
}

if ($TestMode) {
    Write-Host "=== TESTOVACI REZIM ROLLBACK ===" -ForegroundColor Yellow
    Write-CustomLog -Message "Spustenie rollbacku v TESTOVACOM REZIME pre $OriginalSam" -EventSource "ADUserRollback" -LogFileName "$Priezvisko-rollback-test.log" -Type Warning
}

# Najdi najnovsi backup pre dane priezvisko
if ($TestMode) {
    Write-Host "[TEST] Hladanie backup suborov pre priezvisko: $Priezvisko" -ForegroundColor Gray
    # Simulacia najdenia backup suboru
    $Nazov = "$(Get-Date -Format 'yyyyMMdd')-$Priezvisko"
    $Datum = Get-Date -Format "yyyyMMdd"
}
else {
    $BackupFiles = Get-ChildItem -Path $BackupDirectory -Filter "*-$Priezvisko-ADGroups.txt" | Sort-Object LastWriteTime -Descending
    if (-not $BackupFiles) {
        Write-Host "Nenasiel sa backup pre priezvisko $Priezvisko" -ForegroundColor Red
        exit 1
    }

    $NewestBackup = $BackupFiles[0].BaseName -replace "-ADGroups", ""
    $Datum = $NewestBackup.Split("-")[0]
    $Nazov = "$Datum-$Priezvisko"
}

$LogFile = "$Nazov-rollback.log"

if ($TestMode) {
    Write-Host "[TEST] Pouzity by sa backup: $Nazov" -ForegroundColor Cyan
    Write-Host "[TEST] Log subor: $LogFile" -ForegroundColor Cyan
}
else {
    Write-CustomLog -Message "Spustenie rollbacku pre $OriginalSam s backupom $Nazov" -EventSource "ADUserRollback" -LogFileName $LogFile
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
    Write-CustomLog -Message $errorMsg -EventSource "ADUserRollback" -LogFileName $LogFile -Type Error
    if (-not $TestMode) { exit 1 }
}

# Nacitanie povodneho uctu
if ($TestMode) {
    Write-Host "[TEST] Hladanie povodneho uzivatela: $OriginalSam" -ForegroundColor Gray
    # Simulacia najdenia uzivatela
    $OriginalUser = @{
        SamAccountName    = $OriginalSam
        Mail              = "$OriginalSam@tauris.sk"
        DistinguishedName = "CN=$OriginalSam,OU=Disabled,DC=tauris,DC=local"
        GivenName         = "TestMeno"
        Enabled           = $false
    }
}
else {
    $OriginalUser = Get-ADUser -Identity $OriginalSam -Properties * -ErrorAction SilentlyContinue
}

if (-not $OriginalUser) {
    $errorMsg = "Povodny uzivatel $OriginalSam nenajdeny"
    Write-CustomLog -Message $errorMsg -EventSource "ADUserRollback" -LogFileName $LogFile -Type Error
    if (-not $TestMode) { exit 1 }
}

if ($TestMode) {
    Write-Host "[TEST] Povodny uzivatel najdeny: $($OriginalUser.DistinguishedName)" -ForegroundColor Green
    Write-Host "[TEST] Stav uctu: $($OriginalUser.Enabled ? 'Povoleny' : 'Zakazany')" -ForegroundColor Gray
}

# Cesty k backup suborom
$ADGroupsFile = Join-Path $BackupDirectory "$Nazov-ADGroups.txt"
$O365GroupsFile = Join-Path $BackupDirectory "$Nazov-O365Groups.txt"

if ($TestMode) {
    Write-Host "[TEST] Backup subory:" -ForegroundColor Cyan
    Write-Host "[TEST]   AD Groups: $ADGroupsFile" -ForegroundColor Gray
    Write-Host "[TEST]   O365 Groups: $O365GroupsFile" -ForegroundColor Gray
}

# Obnova AD skupin
if ($TestMode) {
    if (Test-Path $ADGroupsFile) {
        Write-Host "[TEST] OBNOVA AD SKUPIN:" -ForegroundColor Yellow
        $ADGroups = Get-Content $ADGroupsFile -ErrorAction SilentlyContinue
        foreach ($Group in $ADGroups) {
            Write-Host "[TEST]   Add-ADGroupMember -Identity $Group -Members $OriginalSam" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "[TEST] Subor AD skupin neexistuje: $ADGroupsFile" -ForegroundColor Yellow
    }
}
else {
    if (Test-Path $ADGroupsFile) {
        $ADGroups = Get-Content $ADGroupsFile
        foreach ($Group in $ADGroups) {
            try {
                # Skontroluj ci uz uzivatel nie je v skupine
                $Members = Get-ADGroupMember -Identity $Group -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
                if ($Members -contains $OriginalSam) {
                    Write-CustomLog -Message "Uzivatel $OriginalSam uz je v AD skupine $Group" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
                }
                else {
                    Add-ADGroupMember -Identity $Group -Members $OriginalSam -ErrorAction Stop
                    Write-CustomLog -Message "Uzivatel $OriginalSam pridan do AD skupiny $Group" -EventSource "ADUserRollback" -LogFileName $LogFile
                }
            }
            catch {
                Write-CustomLog -Message "Chyba pri pridavani do AD skupiny $Group - $_" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
            }
        }
    }
    else {
        Write-CustomLog -Message "Subor $ADGroupsFile nenajdeny" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
    }
}

# Obnova O365 skupin
if ($TestMode) {
    if (Test-Path $O365GroupsFile) {
        Write-Host "[TEST] OBNOVA O365 SKUPIN:" -ForegroundColor Yellow
        Write-Host "[TEST]   Connect-ExchangeOnline" -ForegroundColor Gray
        $O365Groups = Get-Content $O365GroupsFile -ErrorAction SilentlyContinue
        foreach ($Group in $O365Groups) {
            Write-Host "[TEST]   Add-DistributionGroupMember -Identity $Group -Member $($OriginalUser.Mail)" -ForegroundColor Gray
        }
        Write-Host "[TEST]   Disconnect-ExchangeOnline -Confirm:`$false" -ForegroundColor Gray
    }
    else {
        Write-Host "[TEST] Subor O365 skupin neexistuje: $O365GroupsFile" -ForegroundColor Yellow
    }
}
else {
    if (Test-Path $O365GroupsFile) {
        try {
            Connect-ExchangeOnline -ErrorAction SilentlyContinue
            $O365Groups = Get-Content $O365GroupsFile
            foreach ($Group in $O365Groups) {
                try {
                    Add-DistributionGroupMember -Identity $Group -Member $OriginalUser.Mail -ErrorAction Stop
                    Write-CustomLog -Message "Uzivatel $OriginalSam pridan do O365 skupiny $Group" -EventSource "ADUserRollback" -LogFileName $LogFile
                }
                catch {
                    Write-CustomLog -Message "Chyba pri pridavani do O365 skupiny $Group - $_" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
                }
            }
            Disconnect-ExchangeOnline -Confirm:$false
        }
        catch {
            Write-CustomLog -Message "Chyba pri pripajani k Exchange Online: $_" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
        }
    }
    else {
        Write-CustomLog -Message "Subor $O365GroupsFile nenajdeny" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
    }
}

# Volitelne odstranenie klonu
if ($RemoveClone) {
    if ($TestMode) {
        $CloneSam = ($Priezvisko.Substring(0, [Math]::Min(8, $Priezvisko.Length)) + $OriginalUser.GivenName.Substring(0, 1)).ToLower()
        Write-Host "[TEST] ODSTANENIE KLONA:" -ForegroundColor Yellow
        Write-Host "[TEST]   Remove-ADUser -Identity $CloneSam -Confirm:`$false" -ForegroundColor Gray
        Write-Host "[TEST]   Vygenerovane meno klona: $CloneSam" -ForegroundColor Cyan
    }
    else {
        $CloneSam = ($Priezvisko.Substring(0, [Math]::Min(8, $Priezvisko.Length)) + $OriginalUser.GivenName.Substring(0, 1)).ToLower()
        try {
            $CloneUser = Get-ADUser -Identity $CloneSam -ErrorAction SilentlyContinue
            if ($CloneUser) {
                Remove-ADUser -Identity $CloneSam -Confirm:$false
                Write-CustomLog -Message "Klonovany ucet $CloneSam bol odstraneny" -EventSource "ADUserRollback" -LogFileName $LogFile
            }
            else {
                Write-CustomLog -Message "Klonovany ucet $CloneSam neexistuje" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Warning
            }
        }
        catch {
            Write-CustomLog -Message "Chyba pri odstraneni klonu: $_" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Error
        }
    }
}
elseif ($TestMode) {
    Write-Host "[TEST] Odstranenie klona NEBUDE vykonane (parameter -RemoveClone nebol zadany)" -ForegroundColor Gray
}

# Aktivacia povodneho uctu
if ($TestMode) {
    Write-Host "[TEST] AKTIVACIA POVODNEHO UCTU:" -ForegroundColor Yellow
    Write-Host "[TEST]   Enable-ADAccount -Identity $OriginalSam" -ForegroundColor Gray
    Write-Host "[TEST]   Move-ADObject -Identity '$($OriginalUser.DistinguishedName)' -TargetPath 'OU=Users,DC=tauris,DC=local'" -ForegroundColor Gray
}
else {
    try {
        # Presun spat do povodneho OU
        Move-ADObject -Identity $OriginalUser.DistinguishedName -TargetPath "OU=Users,DC=tauris,DC=local"
        
        # Aktivacia uctu
        Enable-ADAccount -Identity $OriginalSam
        
        Write-CustomLog -Message "Povodny ucet $OriginalSam bol obnoveny a aktivovany" -EventSource "ADUserRollback" -LogFileName $LogFile
    }
    catch {
        Write-CustomLog -Message "Chyba pri aktivacii povodneho uctu: $_" -EventSource "ADUserRollback" -LogFileName $LogFile -Type Error
    }
}

if ($TestMode) {
    Write-Host "[TEST] Rollback skript by bol uspesne dokonceny" -ForegroundColor Green
    Write-Host "=== KONIEC TESTOVACIEHO REZIMU ROLLBACK ===" -ForegroundColor Yellow
}
else {
    Write-CustomLog -Message "Rollback skript dokonceny" -EventSource "ADUserRollback" -LogFileName $LogFile
    Write-Host "Rollback pre uzivatela $OriginalSam bol uspesne dokonceny" -ForegroundColor Green
}