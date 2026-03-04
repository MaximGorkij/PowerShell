<# 
.SYNOPSIS
    Exit proces s načítaním prihlasovacích údajov zo súboru .env.
.DESCRIPTION
    Skript automatizuje offboarding, rieši schránky a licencie.
    Prihlasuje sa pomocou App Registration (Service Principal).
.NOTES
    Verzia: 4.6
    Autor: Automaticky report
    Pozadovane moduly: ActiveDirectory, Microsoft.Graph, LogHelper, ExchangeOnlineManagement
    Datum vytvorenia: 18.02.2026
    Logovanie: C:\TaurisIT\Log\ExitProcess
#>

# 1. Načítanie modulu LogHelper
Import-Module "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogSource = "ExitProcessAutomation"

# 2. Načítanie .env súboru (v aktuálnom adresári skriptu)
$EnvPath = Join-Path -Path $PSScriptRoot -ChildPath ".env"

if (Test-Path $EnvPath) {
    Get-Content $EnvPath | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
        $Name, $Value = $_.Split('=', 2)
        [System.Environment]::SetEnvironmentVariable($Name.Trim(), $Value.Trim())
    }
    Write-Host "Konfigurácia z .env načítaná." -ForegroundColor Gray
}
else {
    Write-Host "CHYBA: Súbor .env nebol nájdený v $PSScriptRoot" -ForegroundColor Red
    return
}

# 3. Automatické prihlásenie do M365 služieb
try {
    $ClientId = $env:CLIENT_ID
    $TenantId = $env:TENANT_ID
    $ClientSecret = $env:CLIENT_SECRET

    # Prihlásenie do Graph
    $SecretSecure = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $SecretSecure -NoWelcome

    # Prihlásenie do Exchange Online
    Connect-ExchangeOnline -TenantId $TenantId -AppId $ClientId -ClientSecret $SecretSecure
}
catch {
    Write-CustomLog -Message "Zlyhalo prihlásenie do M365 služieb: $($_.Exception.Message)" -EventSource $LogSource -Type "Error"
    Write-Host "Chyba pripojenia. Skontrolujte údaje v .env." -ForegroundColor Red
    return
}

# --- KONFIGURÁCIA AD ---
$DisabledOU = "OU=Disabled Users,DC=tauris,DC=local" 
$BackupPath = "C:\TaurisIT\Log\ExitProcess\Backups"

Write-Host "`n--- Vyhľadávanie používateľa pre Exit proces ---" -ForegroundColor Cyan
$SearchName = Read-Host "Zadajte meno a priezvisko zamestnanca"

# 1. Vyhľadávanie v AD (ANR)
$FoundUsers = Get-ADUser -Filter "DisplayName -like '*$SearchName*' -or Name -like '*$SearchName*'" -Properties DisplayName, UserPrincipalName, SamAccountName, Department

$SelectedUser = $null
if ($FoundUsers.Count -eq 0) {
    Write-Host "Používateľ nenájdený." -ForegroundColor Red
    return
}
elseif ($FoundUsers.Count -gt 1) {
    Write-Host "`nNájdených viacero zhôd:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $FoundUsers.Count; $i++) {
        Write-Host "[$i] - $($FoundUsers[$i].DisplayName) ($($FoundUsers[$i].UserPrincipalName))"
    }
    $Selection = Read-Host "Vyberte číslo"
    $SelectedUser = $FoundUsers[[int]$Selection]
}
else {
    $SelectedUser = $FoundUsers[0]
}

# --- VOĽBA SCHRÁNKY ---
Write-Host "`n--- Mailbox ---" -ForegroundColor Cyan
Write-Host "1. Zmazať (+ voliteľne Litigation Hold)"
Write-Host "2. Shared Mailbox (+ delegácia)"
$MailOption = Read-Host "Voľba (1-2)"

$DoLitigationHold = $false
$DoSharedMailbox = $false
$DelegateUser = $null

if ($MailOption -eq "1") {
    if ((Read-Host "Aktivovať Litigation Hold? (y/n)") -eq 'y') { $DoLitigationHold = $true }
}
elseif ($MailOption -eq "2") {
    $DoSharedMailbox = $true
    $DelegateName = Read-Host "Meno osoby pre prístup"
    $DelegateUser = Get-ADUser -Filter "DisplayName -like '*$DelegateName*'" | Select-Object -First 1
}

# --- VÝKON ---
if ((Read-Host "`nSpustiť offboarding pre $($SelectedUser.DisplayName)? (y/n)") -eq 'y') {
    try {
        $UPN = $SelectedUser.UserPrincipalName
        $SAM = $SelectedUser.SamAccountName
        $DN = $SelectedUser.DistinguishedName
        $EntraUserId = (Get-MgUser -UserId $UPN).Id

        Write-Host "`n--- Spracovanie členstiev v skupinách ---" -ForegroundColor Cyan

        # 1. Lokálne AD skupiny - Záloha a odstránenie
        Write-Host "Spracovávam lokálne AD skupiny..."
        $ADGroups = Get-ADPrincipalGroupMembership -Identity $DN
        if ($ADGroups) {
            # Záloha do XML
            if (-not (Test-Path $BackupPath)) { New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null }
            $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $BackupFile = Join-Path -Path $BackupPath -ChildPath "${SAM}_ad_groups_$Timestamp.xml"
            $ADGroups | Export-Clixml -Path $BackupFile
            Write-CustomLog -Message "Členstvá v AD skupinách pre $SAM zálohované do $BackupFile" -EventSource $LogSource -Type "Information"
            Write-Host "Členstvá v AD skupinách zálohované do XML." -ForegroundColor Green

            # Odstránenie členstiev
            $ADGroups | Where-Object { $_.Name -ne "Domain Users" } | ForEach-Object {
                Remove-ADGroupMember -Identity $_ -Members $DN -Confirm:$false
                Write-Host "Odstránený z AD skupiny: $($_.Name)"
            }
        }
        else {
            Write-Host "Používateľ nie je členom žiadnych relevantných AD skupín."
        }

        # 2. Cloudové skupiny (Entra ID / Teams / SharePoint) - Kontrola a odstránenie
        Write-Host "`nSpracovávam cloudové skupiny (Teams, SharePoint)..."
        $CloudGroups = Get-MgUserMemberOf -UserId $EntraUserId -All
        $UserTeams = Get-MgUserJoinedTeam -UserId $EntraUserId -All

        if ($UserTeams) {
            Write-Host "Používateľ je členom nasledujúcich Teams:" -ForegroundColor Yellow
            $UserTeams | ForEach-Object { Write-Host " - $($_.DisplayName)" }
            Write-CustomLog -Message "Nájdené členstvá v Teams pre $UPN - $($UserTeams.DisplayName -join ', ')" -EventSource $LogSource -Type "Information"
        }

        if ($CloudGroups) {
            Write-Host "Používateľ je členom $($CloudGroups.Count) cloudových skupín (vrátane Teams)." -ForegroundColor Yellow
            if ((Read-Host "Odstrániť zo všetkých cloudových skupín (okrem dynamických)? (y/n)") -eq 'y') {
                $CloudGroups | Where-Object { -not ($_.GroupTypes -contains 'DynamicMembership') } | ForEach-Object {
                    try {
                        Remove-MgGroupMemberByRef -GroupId $_.Id -DirectoryObjectId $EntraUserId -ErrorAction Stop
                        Write-Host "Odstránený z cloud skupiny: $($_.DisplayName)"
                        Write-CustomLog -Message "Používateľ $UPN odstránený z cloud skupiny '$($_.DisplayName)'" -EventSource $LogSource -Type "Information"
                    }
                    catch {
                        $errMsg = "Nepodarilo sa odstrániť zo skupiny $($_.DisplayName): $($_.Exception.Message)"
                        Write-Warning $errMsg
                        Write-CustomLog -Message $errMsg -EventSource $LogSource -Type "Error"
                    }
                }
            }
        }

        # Exchange Kroky
        if ($DoLitigationHold) {
            Set-Mailbox -Identity $UPN -LitigationHoldEnabled $true -RetentionComment "Exit $(Get-Date -Format 'dd.MM.yyyy')"
        }
        if ($DoSharedMailbox) {
            Set-Mailbox -Identity $UPN -Type Shared
            Add-MailboxPermission -Identity $UPN -User $DelegateUser.UserPrincipalName -AccessRights FullAccess -InheritanceType All -Confirm:$false
        }

        # AD Kroky - Deaktivácia
        Disable-ADAccount -Identity $DN
        Write-Host "AD účet deaktivovaný."

        # Graph Sign-out
        Revoke-MgUserSignInSession -UserId $EntraUserId -ErrorAction SilentlyContinue

        # Premenovanie a presun
        $NewSam = "ex_" + $SAM
        Rename-ADObject -Identity $DN -NewName $NewSam
        Start-Sleep -Seconds 2
        Move-ADObject -Identity (Get-ADUser -Filter "SamAccountName -eq '$NewSam'").DistinguishedName -TargetPath $DisabledOU

        Write-CustomLog -Message "Offboarding $NewSam úspešný." -EventSource $LogSource -Type "Information"
        Write-Host "Hotovo." -ForegroundColor Green
    }
    catch {
        Write-CustomLog -Message "Chyba: $($_.Exception.Message)" -EventSource $LogSource -Type "Error"
        Write-Host "Chyba: $($_.Exception.Message)" -ForegroundColor Red
    }
}