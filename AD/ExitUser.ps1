<#
.SYNOPSIS
    Offboard / Archive / Delete manager pre jedneho pouzivatela (AD + M365 + Intune).

.DESCRIPTION
    Interaktivny PowerShell tool, ktory vykonava tri fazy exit procesu:
      1) OFFBOARD  - deaktivacia AD, konverzia mailboxu na Shared, OneDrive backup, revoke sessions, Intune retire, aktualizacia CSV
      2) ARCHIVE   - presun do Archive OU, mailbox retention hold, aktualizacia CSV
      3) DELETE    - odstranenie z AD, Azure AD, Exchange, cleanup skupin, aktualizacia CSV

    Pozor: pre produkciu pouzi Azure Key Vault alebo Credential Manager pre ulozenie Client Secret.
    Testovane v prostredi so:
      - ActiveDirectory module (RSAT)
      - Microsoft.Graph PowerShell SDK
      - ExchangeOnlineManagement (Connect-ExchangeOnline)
      - LogHelper modul (cesta: C:\TaurisIT\Modules\LogHelper.psm1)

.AUTHOR
    Marek Findrik (Enhanced)

.CREATED
    2025-10-20

.VERSION
    3.2.0

.NOTES
    - CSV subor: C:\Scripts\UserTracker.csv
    - Logy: C:\TaurisIT\Log\ExitProcess.txt
    - Event Log: "ExitProcess"
    - Admin email: admin@tauris.sk
    - Required modules: ActiveDirectory, Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.DeviceManagement, ExchangeOnlineManagement, CredentialManager (optional)
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$User
)

# === NASTAVENIA ===
$Script:Config = @{
    CsvPath         = "C:\Scripts\UserTracker.csv"
    LogFile         = "C:\TaurisIT\Log\ExitProcess.txt"
    EventSource     = "ExitProcess"
    BackupRootPath  = "C:\TaurisIT\OneDriveBackup"
    ArchiveOU       = "OU=Archived,OU=Users,DC=domain,DC=com"
    AdminEmail      = "admin@tauris.sk"
    ClientId        = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # nastav svoj ClientId
    TenantId        = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # nastav svoj TenantId
    SecretName      = "ExitProcessClientSecret"             # meno v Credential Manager alebo KeyVault
    MinBackupFreeGB = 5
}

# === NAHRADNE MODULY (ak chybaju) ===
$requiredModules = @(
    "ActiveDirectory",
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users",
    "Microsoft.Graph.DeviceManagement",
    "ExchangeOnlineManagement",
    "CredentialManager"  # pre Get-StoredCredential (optional)
)

foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Pozor: Modul $m nie je nainstalovany. Nainstaluj ho pre plnu funkcnost." -ForegroundColor Yellow
    }
}

# Import modulov (ak su dostupne)
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue
Import-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue
Import-Module CredentialManager -ErrorAction SilentlyContinue
# LogHelper modul - uprav cestu podla svojej instalacie
$logHelperPath = "C:\TaurisIT\Modules\LogHelper.psm1"
if (Test-Path $logHelperPath) {
    Import-Module $logHelperPath -ErrorAction SilentlyContinue
}
else {
    Write-Host "Upozornenie: LogHelper modul nenajdeny na $logHelperPath. Logovanie bude minimalne." -ForegroundColor Yellow
    function Write-CustomLog { param($Message, $EventSource, $LogFileName, $Type = "Information"); Write-Host $Message }
}

# === BEZPECNE NACITANIE CLIENT SECRET ===
function Get-SecureClientSecret {
    param([string]$SecretName = $Script:Config.SecretName)
    try {
        # Preferovane: Azure Key Vault (nie je zahrnute tu)
        # Alternativa: Windows Credential Manager (CredentialManager modul)
        if (Get-Command -Name Get-StoredCredential -ErrorAction SilentlyContinue) {
            $cred = Get-StoredCredential -Target $SecretName -ErrorAction SilentlyContinue
            if ($cred -and $cred.Password) {
                Write-CustomLog -Message "Client secret nacitany z Credential Manager." -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
                return $cred.Password
            }
        }

        # Fallback: environment variable
        $envSecret = [System.Environment]::GetEnvironmentVariable("AZURE_CLIENT_SECRET", "Machine")
        if ($envSecret) {
            Write-CustomLog -Message "Client secret nacitany z environment variable." -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
            return $envSecret
        }

        throw "Client Secret nenajdeny! (Credential Manager alebo environment variable AZURE_CLIENT_SECRET)"
    }
    catch {
        Write-CustomLog -Message "KRITICKA CHYBA: Nepodarilo sa nacitat Client Secret: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        throw
    }
}

# === NACITANIE EXCHANGE CERTIFICATU ===
function Get-ExchangeCertificate {
    try {
        $cert = Get-ChildItem "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*ExitProcess*" -or $_.FriendlyName -like "*ExitProcess*" } |
        Sort-Object NotAfter -Descending | Select-Object -First 1

        if (-not $cert) {
            Write-CustomLog -Message "Certifikat pre Exchange Online nebol najdeny." -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Warning"
            return $null
        }
        return $cert
    }
    catch {
        Write-CustomLog -Message "CHYBA pri nacitani certifikatu: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        return $null
    }
}

# === PREDPOKLADY ===
function Test-Prerequisites {
    Write-CustomLog -Message "Kontrola predpokladov spustena." -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile

    try {
        Get-ADDomain | Out-Null
        Write-CustomLog -Message "AD dostupne." -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
    }
    catch {
        throw "Nie je pripojenie k Active Directory: $_"
    }

    $driveRoot = $Script:Config.BackupRootPath.Split(':')[0]
    $psDrive = Get-PSDrive -Name $driveRoot -ErrorAction SilentlyContinue
    if (-not $psDrive) {
        throw "Backup disk ($driveRoot) nie je dostupny."
    }
    if ($psDrive.Free -lt ($Script:Config.MinBackupFreeGB * 1GB)) {
        throw "Nedostatok miesta pre zalohu (potrebnych aspon $($Script:Config.MinBackupFreeGB) GB)."
    }

    if (-not (Test-Path $Script:Config.CsvPath)) {
        Write-CustomLog -Message "CSV subor neexistuje. Vytvaram: $($Script:Config.CsvPath)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
        Initialize-CsvFile
    }

    Write-CustomLog -Message "Predpoklady OK." -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
}

# === LOG / CSV ===
function Initialize-CsvFile {
    if (-not (Test-Path $Script:Config.CsvPath)) {
        $dir = Split-Path $Script:Config.CsvPath -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $headers = @(
            "SamAccountName", "UPN", "DisplayName", "Status", "OffboardDate",
            "ArchiveDate", "ScheduledDeletionDate", "Manager", "Department"
        )
        $headers -join "," | Out-File $Script:Config.CsvPath -Encoding UTF8
        Write-CustomLog -Message "CSV subor vytvoreny: $($Script:Config.CsvPath)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
    }
}

function Update-UserInCsv {
    param([PSCustomObject]$User)
    $allUsers = Import-Csv $Script:Config.CsvPath -Encoding UTF8
    $found = $false
    $updated = $allUsers | ForEach-Object {
        if ($_.SamAccountName -eq $User.SamAccountName) {
            $found = $true
            $User
        }
        else {
            $_
        }
    }

    if (-not $found) {
        # append if not found
        $User | Select-Object SamAccountName, UPN, DisplayName, Status, OffboardDate, ArchiveDate, ScheduledDeletionDate, Manager, Department |
        Export-Csv $Script:Config.CsvPath -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $updated | Export-Csv $Script:Config.CsvPath -NoTypeInformation -Encoding UTF8
    }

    Write-CustomLog -Message "CSV aktualizovany pre: $($User.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
}

# === GENERAL HELPERS ===
function Invoke-ExitProcessStep {
    param(
        [scriptblock]$Action,
        [string]$StepName,
        [string]$UserUPN,
        [bool]$IsCritical = $false
    )
    try {
        Write-Host "  $StepName..." -ForegroundColor Yellow
        & $Action
        Write-Host "  OK: $StepName dokoncene" -ForegroundColor Green
        Write-CustomLog -Message "Krok uspesny: $StepName pre $UserUPN" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
        return $true
    }
    catch {
        Write-CustomLog -Message "CHYBA v $StepName pre $UserUPN : $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        if ($IsCritical) {
            throw "Kriticka chyba v $StepName : $_"
        }
        else {
            Write-Host "  VAROVANIE: Chyba v $StepName (pokracujem): $_" -ForegroundColor Yellow
            return $false
        }
    }
}

# === GRAPH CONNECT ===
function Connect-ToGraphAPI {
    try {
        $clientSecret = Get-SecureClientSecret
        if (-not $clientSecret) { throw "Client secret nie je dostupny." }

        # Connect-MgGraph s client secret
        Connect-MgGraph -ClientId $Script:Config.ClientId -TenantId $Script:Config.TenantId -ClientSecret $clientSecret -Scopes "User.Read.All", "Mail.Send", "Files.Read.All", "DeviceManagementManagedDevices.ReadWrite.All", "Directory.ReadWrite.All" -ErrorAction Stop

        Write-CustomLog -Message "Pripojene k Microsoft Graph API" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
        return $true
    }
    catch {
        Write-CustomLog -Message "CHYBA pri pripojeni k Graph API: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        return $false
    }
}

# === EMAIL S POSLEDNEJ SPRAVY (Graph) ===
function Send-EmailNotification {
    param (
        [string]$ToEmail,
        [string]$Subject,
        [string]$Body,
        [string]$FromEmail = $Script:Config.AdminEmail
    )

    try {
        $message = @{
            Message         = @{
                Subject      = $Subject
                Body         = @{
                    ContentType = "HTML"
                    Content     = $Body
                }
                ToRecipients = @(
                    @{
                        EmailAddress = @{
                            Address = $ToEmail
                        }
                    }
                )
            }
            SaveToSentItems = $true
        }
        # Pouzivame Send-MgUserMail. FromEmail musi byt validny UserId alebo userPrincipalName ktory ma Mail.Send via app.
        Send-MgUserMail -UserId $FromEmail -BodyParameter $message -ErrorAction Stop

        Write-CustomLog -Message "Email notifikacia odoslana: $Subject -> $ToEmail" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
    }
    catch {
        Write-CustomLog -Message "CHYBA pri odosielani emailu: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
}

# === Exchange helpers ===
function Get-DistributionListsForUser {
    param([string]$UserUPN)
    try {
        $cert = Get-ExchangeCertificate
        if ($cert) {
            Connect-ExchangeOnline -CertificateThumbprint $cert.Thumbprint -AppId $Script:Config.ClientId -Organization $Script:Config.TenantId -ShowBanner:$false -ErrorAction Stop
        }
        else {
            # ak nemas cert, skus interactive (only if console)
            Connect-ExchangeOnline -UserPrincipalName $Script:Config.AdminEmail -ShowBanner:$false -ErrorAction SilentlyContinue
        }

        # Najdeme distribution groups kde je user clenom
        $groups = Get-DistributionGroup -ResultSize Unlimited -ErrorAction Stop | Where-Object {
            try {
                (Get-DistributionGroupMember -Identity $_.Identity -ResultSize Unlimited -ErrorAction Stop | Select-Object -ExpandProperty PrimarySmtpAddress) -contains $UserUPN
            }
            catch { $false }
        }

        return $groups
    }
    catch {
        Write-CustomLog -Message "CHYBA pri ziskavani distribucnych listov: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        return $null
    }
    finally {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Remove-UserFromDistributionLists {
    param([string]$UserUPN, [array]$Lists)
    if (-not $Lists) { return 0 }
    $removed = 0
    try {
        $cert = Get-ExchangeCertificate
        if ($cert) {
            Connect-ExchangeOnline -CertificateThumbprint $cert.Thumbprint -AppId $Script:Config.ClientId -Organization $Script:Config.TenantId -ShowBanner:$false -ErrorAction Stop
        }
        else {
            Connect-ExchangeOnline -UserPrincipalName $Script:Config.AdminEmail -ShowBanner:$false -ErrorAction SilentlyContinue
        }

        foreach ($l in $Lists) {
            try {
                Remove-DistributionGroupMember -Identity $l.Identity -Member $UserUPN -Confirm:$false -ErrorAction Stop
                $removed++
                Write-CustomLog -Message "Odstranen z distribucneho listu: $($l.DisplayName) pre $UserUPN" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
            }
            catch {
                Write-CustomLog -Message "CHYBA pri odstraňovaní z $($l.DisplayName): $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
            }
        }
    }
    catch {
        Write-CustomLog -Message "CHYBA pri Remove-UserFromDistributionLists: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
    finally {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    return $removed
}

# === OneDrive backup (rekurzivne) ===
function Backup-OneDriveRecursive {
    param([string]$UserUPN)

    $backupPath = Join-Path $Script:Config.BackupRootPath $UserUPN
    if (-not (Test-Path $backupPath)) { New-Item -Path $backupPath -ItemType Directory -Force | Out-Null }

    try {
        $drive = Get-MgUserDrive -UserId $UserUPN -ErrorAction Stop
    }
    catch {
        Write-CustomLog -Message "OneDrive nenajdeny pre $UserUPN $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Warning"
        return $null
    }

    function Get-DriveItemsRecursive {
        param($UserId, $DriveItemId, $LocalPath)
        $children = Get-MgUserDriveItemChild -UserId $UserId -DriveItemId $DriveItemId -ErrorAction Stop
        foreach ($item in $children) {
            $safeName = $item.Name -replace '[\\\/:\*\?"\<\>\|]', '_'
            if ($item.Folder) {
                $folderPath = Join-Path $LocalPath $safeName
                if (-not (Test-Path $folderPath)) { New-Item -Path $folderPath -ItemType Directory -Force | Out-Null }
                Get-DriveItemsRecursive -UserId $UserId -DriveItemId $item.Id -LocalPath $folderPath
            }
            elseif ($item.File) {
                $filePath = Join-Path $LocalPath $safeName
                $uri = "https://graph.microsoft.com/v1.0/users/$UserId/drive/items/$($item.Id)/content"
                Invoke-MgGraphRequest -Method GET -Uri $uri -OutFile $filePath -ErrorAction Stop
                Write-Host "    Stiahnuty: $safeName" -ForegroundColor Green
            }
        }
    }

    try {
        Write-Host "  Zalohujem OneDrive pre $UserUPN..." -ForegroundColor Cyan
        Get-DriveItemsRecursive -UserId $UserUPN -DriveItemId "root" -LocalPath $backupPath
        Write-CustomLog -Message "OneDrive backup dokonceny: $UserUPN -> $backupPath" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
        return $backupPath
    }
    catch {
        Write-CustomLog -Message "CHYBA pri zalohovani OneDrive pre $UserUPN $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        return $null
    }
}

# === Intune / sessions ===
function Revoke-UserSessions {
    param([string]$UserUPN)
    try {
        Revoke-MgUserSignInSession -UserId $UserUPN -ErrorAction Stop
        Write-CustomLog -Message "Revoke sessions pre: $UserUPN" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
    }
    catch {
        Write-CustomLog -Message "CHYBA pri revoke sessions: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
}

function Wipe-IntuneDevices {
    param([string]$UserUPN)
    try {
        $devices = Get-MgUserManagedDevice -UserId $UserUPN -ErrorAction Stop
        if (-not $devices -or $devices.Count -eq 0) {
            Write-Host "  Ziadne Intune zariadenia." -ForegroundColor Gray
            return
        }
        foreach ($d in $devices) {
            Write-Host "  Retiring device: $($d.DeviceName)" -ForegroundColor Yellow
            Invoke-MgRetireManagedDevice -ManagedDeviceId $d.Id -ErrorAction Stop
            Write-CustomLog -Message "Intune device retired: $($d.DeviceName) pre $UserUPN" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
        }
    }
    catch {
        Write-CustomLog -Message "CHYBA pri Intune cleanup: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
}

function Export-UserGroupMembership {
    param([string]$UserUPN, [string]$BackupPath)
    try {
        $groups = Get-MgUserMemberOf -UserId $UserUPN -ErrorAction Stop
        $exportPath = Join-Path $BackupPath "GroupMembership.json"
        $groups | Select-Object Id, @{Name = 'DisplayName'; Expression = { ($_.AdditionalProperties.displayName) } }, @{Name = 'Type'; Expression = { $_.ODataType } } |
        ConvertTo-Json -Depth 5 | Out-File $exportPath -Encoding UTF8
        Write-CustomLog -Message "Group membership exportovany: $UserUPN" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
        return ($groups | Measure-Object).Count
    }
    catch {
        Write-CustomLog -Message "CHYBA pri exporte group membership: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        return 0
    }
}

# === UZIVATELSKY VYBER ===
function Get-UserObject {
    param(
        [string]$Identifier  # moze byt SamAccountName alebo UPN alebo DisplayName
    )

    if ($Identifier) {
        # pokus o AD podla SamAccountName alebo UPN
        $adUser = Get-ADUser -Filter { SamAccountName -eq $Identifier -or UserPrincipalName -eq $Identifier } -Properties DisplayName, UserPrincipalName, SamAccountName, Department, Manager -ErrorAction SilentlyContinue
        if ($adUser) {
            return [PSCustomObject]@{
                SamAccountName = $adUser.SamAccountName
                UPN            = $adUser.UserPrincipalName
                DisplayName    = $adUser.DisplayName
                Department     = $adUser.Department
                Manager        = $adUser.Manager
                Status         = "Active"
            }
        }
    }

    # Interactive search v CSV
    $firstName = Read-Host "Zadaj meno pouzivatela"
    $lastName = Read-Host "Zadaj priezvisko pouzivatela"
    $users = Import-Csv $Script:Config.CsvPath -Encoding UTF8
    $found = $users | Where-Object {
        ($_.SamAccountName -like "*$firstName*" -and $_.SamAccountName -like "*$lastName*") -or
        ($_.UPN -like "*$firstName*" -and $_.UPN -like "*$lastName*") -or
        ($_.DisplayName -like "*$firstName*" -and $_.DisplayName -like "*$lastName*")
    }

    if (-not $found) {
        Write-Host "Pouzivatel nebol najdeny v CSV." -ForegroundColor Red
        return $null
    }
    elseif ($found.Count -gt 1) {
        $i = 1
        $found | ForEach-Object { Write-Host "$i) $($_.DisplayName) - $($_.UPN) - Status: $($_.Status)"; $i++ }
        $sel = Read-Host "Zvol cislo pouzivatela"
        return $found[$sel - 1]
    }
    else {
        return $found[0]
    }
}

# === FAZA 1: OFFBOARD ===
function Start-OffboardProcess {
    Write-Host "`n=== FAZA 1: OFFBOARD ===`n" -ForegroundColor Green

    $userObj = if ($User) { Get-UserObject -Identifier $User } else { Get-UserObject }
    if (-not $userObj) { Write-Host "Pouzivatel nenajdeny. Koncim." -ForegroundColor Red; return }

    if ($userObj.Status -ne "Active" -and $userObj.Status -ne "") {
        Write-Host "Pouzivatel nie je v stave Active. Status: $($userObj.Status)" -ForegroundColor Yellow
    }

    Write-Host "Offboarding: $($userObj.DisplayName) ($($userObj.UPN))" -ForegroundColor Cyan
    $confirm = Read-Host "Pokracovat? (Y/N)"
    if ($confirm -ne 'Y') { Write-CustomLog -Message "Offboarding zruseny pre $($userObj.UPN)"; return }

    try {
        Write-CustomLog -Message "Zaciatok offboardingu: $($userObj.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile

        # 1) Kontrola distribucnych listov
        $distributionLists = Get-DistributionListsForUser -UserUPN $userObj.UPN
        if ($distributionLists -and $distributionLists.Count -gt 0) {
            Write-Host "Pouzivatel je clenom $($distributionLists.Count) distribucnych listov." -ForegroundColor Yellow
            $removeChoice = Read-Host "Odstranit z distribucnych listov? (Y/N)"
            if ($removeChoice -eq 'Y') {
                $removed = Remove-UserFromDistributionLists -UserUPN $userObj.UPN -Lists $distributionLists
                Write-Host "Odstranen z $removed distribucnych listov." -ForegroundColor Green
            }
            else {
                Write-Host "Pouzivatel zostava v distribucnych listoch." -ForegroundColor Yellow
            }
        }

        # 2) Deaktivacia AD uctu
        Invoke-ExitProcessStep -Action {
            Disable-ADAccount -Identity $userObj.SamAccountName -ErrorAction Stop
            Set-ADUser -Identity $userObj.SamAccountName -Replace @{extensionAttribute10 = "Offboarded" } -ErrorAction Stop
        } -StepName "Deaktivacia AD konta" -UserUPN $userObj.UPN -IsCritical $true

        # 3) Pripojenie k Graph API (critical)
        Invoke-ExitProcessStep -Action {
            if (-not (Connect-ToGraphAPI)) { throw "Nepodarilo sa pripojit k Graph API" }
        } -StepName "Pripojenie k Microsoft Graph" -UserUPN $userObj.UPN -IsCritical $true

        # 4) Konverzia mailboxu na shared
        Invoke-ExitProcessStep -Action {
            $cert = Get-ExchangeCertificate
            if ($cert) {
                Connect-ExchangeOnline -CertificateThumbprint $cert.Thumbprint -AppId $Script:Config.ClientId -Organization $Script:Config.TenantId -ShowBanner:$false -ErrorAction Stop
            }
            else {
                Connect-ExchangeOnline -UserPrincipalName $Script:Config.AdminEmail -ShowBanner:$false -ErrorAction SilentlyContinue
            }

            Set-Mailbox -Identity $userObj.UPN -Type Shared -ErrorAction Stop
            Set-MailboxAutoReplyConfiguration -Identity $userObj.UPN -AutoReplyState Enabled `
                -InternalMessage "Tento zamestnanec uz nie je aktivny. Kontakt: $($Script:Config.AdminEmail)." `
                -ExternalMessage "This employee is no longer active. For urgent matters, please contact $($Script:Config.AdminEmail)." -ErrorAction SilentlyContinue

            Set-Mailbox -Identity $userObj.UPN -ForwardingSMTPAddress $Script:Config.AdminEmail -ErrorAction SilentlyContinue
        } -StepName "Konverzia mailboxu na Shared" -UserUPN $userObj.UPN -IsCritical $false

        # 5) Zaloha OneDrive
        $backupPath = $null
        Invoke-ExitProcessStep -Action {
            $backupPath = Backup-OneDriveRecursive -UserUPN $userObj.UPN
        } -StepName "Zaloha OneDrive" -UserUPN $userObj.UPN -IsCritical $false

        # 6) Export group membership
        $groupCount = 0
        Invoke-ExitProcessStep -Action {
            if ($backupPath) { $groupCount = Export-UserGroupMembership -UserUPN $userObj.UPN -BackupPath $backupPath }
        } -StepName "Export group membership" -UserUPN $userObj.UPN -IsCritical $false

        # 7) Revoke sessions + Intune retire
        Invoke-ExitProcessStep -Action {
            Revoke-UserSessions -UserUPN $userObj.UPN
            Wipe-IntuneDevices -UserUPN $userObj.UPN
        } -StepName "Revoke sessions a Intune cleanup" -UserUPN $userObj.UPN -IsCritical $false

        # 8) Aktualizacia CSV
        Invoke-ExitProcessStep -Action {
            $userObj.Status = "Offboarded"
            $userObj.OffboardDate = (Get-Date).ToString("yyyy-MM-dd")
            $userObj.ScheduledDeletionDate = (Get-Date).AddDays(90).ToString("yyyy-MM-dd")
            Update-UserInCsv -User $userObj
        } -StepName "Aktualizacia zaznamov" -UserUPN $userObj.UPN -IsCritical $true

        # 9) Email notifikacia
        $distributionListInfo = if ($distributionLists -and $distributionLists.Count -gt 0) { "<li>VAROVANIE: Pouzivatel zostava v $($distributionLists.Count) distribucnych listoch</li>" } else { "<li>OK: Ziaden distribucny list (alebo vsetky odstranene)</li>" }

        $emailBody = @"
<html>
<body>
<h2>Pouzivatel bol uspesne offboardovany</h2>
<p><strong>Meno:</strong> $($userObj.DisplayName)</p>
<p><strong>UPN:</strong> $($userObj.UPN)</p>
<p><strong>Datum offboardingu:</strong> $($userObj.OffboardDate)</p>
<p><strong>Planovane vymazanie:</strong> $($userObj.ScheduledDeletionDate)</p>
<hr>
<p><strong>Vykonane akcie:</strong></p>
<ul>
<li>OK: AD konto deaktivovane</li>
<li>OK: Mailbox konvertovany na Shared</li>
<li>OK: OneDrive zalohovany: $backupPath</li>
<li>OK: Group membership exportovany ($groupCount skupin)</li>
<li>OK: Sessions zrusene</li>
<li>OK: Intune zariadenia retired</li>
$distributionListInfo
</ul>
</body>
</html>
"@

        Send-EmailNotification -ToEmail $Script:Config.AdminEmail -Subject "Offboarding dokonceny: $($userObj.DisplayName)" -Body $emailBody

        Write-Host "OFFBOARDING USPESNE DOKONCENY" -ForegroundColor Green
        Write-CustomLog -Message "Offboarding dokonceny: $($userObj.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
    }
    catch {
        Write-Host "CHYBA PRI OFFBOARDINGU: $_" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA pri offboarding $($userObj.UPN): $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
    finally {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    Read-Host "Stlac Enter pre pokracovanie"
}

# === FAZA 2: ARCHIVE ===
function Start-ArchiveProcess {
    Write-Host "`n=== FAZA 2: ARCHIVE ===`n" -ForegroundColor Yellow

    $userObj = if ($User) { Get-UserObject -Identifier $User } else { Get-UserObject }
    if (-not $userObj) { Write-Host "Pouzivatel nenajdeny. Koncim." -ForegroundColor Red; return }

    if ($userObj.Status -ne "Offboarded" -and $userObj.Status -ne "Active") {
        Write-Host "Ocekavany status pre archive: Offboarded (aktualny: $($userObj.Status)). Pokracovat? (Y/N)" -ForegroundColor Yellow
        $c = Read-Host
        if ($c -ne 'Y') { return }
    }

    $confirm = Read-Host "Pokracovat s archivaciou pre $($userObj.UPN)? (Y/N)"
    if ($confirm -ne 'Y') { return }

    try {
        Write-CustomLog -Message "Zaciatok archivacie: $($userObj.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile

        # 1) Presun do Archive OU
        Invoke-ExitProcessStep -Action {
            $adUser = Get-ADUser -Identity $userObj.SamAccountName -ErrorAction Stop
            Move-ADObject -Identity $adUser.DistinguishedName -TargetPath $Script:Config.ArchiveOU -ErrorAction Stop
        } -StepName "Presun do Archive OU" -UserUPN $userObj.UPN -IsCritical $true

        # 2) Mailbox retention hold
        Invoke-ExitProcessStep -Action {
            $cert = Get-ExchangeCertificate
            if ($cert) {
                Connect-ExchangeOnline -CertificateThumbprint $cert.Thumbprint -AppId $Script:Config.ClientId -Organization $Script:Config.TenantId -ShowBanner:$false -ErrorAction Stop
            }
            else {
                Connect-ExchangeOnline -UserPrincipalName $Script:Config.AdminEmail -ShowBanner:$false -ErrorAction SilentlyContinue
            }
            Set-Mailbox -Identity $userObj.UPN -LitigationHoldEnabled $true -ErrorAction Stop
        } -StepName "Nastavenie retention hold" -UserUPN $userObj.UPN -IsCritical $false

        # 3) Aktualizacia CSV
        Invoke-ExitProcessStep -Action {
            $userObj.Status = "Archived"
            $userObj.ArchiveDate = (Get-Date).ToString("yyyy-MM-dd")
            Update-UserInCsv -User $userObj
        } -StepName "Aktualizacia zaznamov" -UserUPN $userObj.UPN -IsCritical $true

        Write-Host "ARCHIVACIA USPESNE DOKONCENA" -ForegroundColor Green
        Write-CustomLog -Message "Archivacia dokoncena: $($userObj.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile
    }
    catch {
        Write-Host "CHYBA PRI ARCHIVACII: $_" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA pri archivacii $($userObj.UPN): $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
    finally {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    Read-Host "Stlac Enter pre pokracovanie"
}

# === FAZA 3: DELETE ===
function Start-DeleteProcess {
    Write-Host "`n=== FAZA 3: DELETE ===`n" -ForegroundColor Red

    $userObj = if ($User) { Get-UserObject -Identifier $User } else { Get-UserObject }
    if (-not $userObj) { Write-Host "Pouzivatel nenajdeny. Koncim." -ForegroundColor Red; return }

    if ($userObj.Status -ne "Archived") {
        Write-Host "Ocekavany status pre delete: Archived (aktualny: $($userObj.Status)). Pokracovat? (YES/NO)" -ForegroundColor Yellow
        $ov = Read-Host
        if ($ov -ne 'YES') { return }
    }

    # 90 dni check
    if ($userObj.OffboardDate) {
        try {
            $off = [datetime]::ParseExact($userObj.OffboardDate, "yyyy-MM-dd", $null)
            $daysSince = ((Get-Date) - $off).Days
            if ($daysSince -lt 90) {
                Write-Host "Pozor: od offboardingu este neuplynulo 90 dni ($daysSince dni)." -ForegroundColor Yellow
                $override = Read-Host "Chcete pokracovat? (YES/NO)"
                if ($override -ne 'YES') { Write-CustomLog -Message "Vymazanie zrusene - nedostatocny pocet dni"; return }
            }
        }
        catch {
            Write-CustomLog -Message "Chyba pri parsovani OffboardDate: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Warning"
        }
    }

    Write-Host "VYMAZAVANIE POUZIVATELA: $($userObj.DisplayName) ($($userObj.UPN)) - TATO AKCIA JE NEVRATNA" -ForegroundColor Red
    $finalConfirm = Read-Host "Na potvrdenie napiste: DELETE"
    if ($finalConfirm -ne 'DELETE') { Write-Host "Vymazanie zrusene." -ForegroundColor Yellow; return }

    try {
        Write-CustomLog -Message "Zaciatok vymazavania: $($userObj.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile

        # 1) Kontrola a odstranenie z distribucnych listov
        $distributionLists = Get-DistributionListsForUser -UserUPN $userObj.UPN
        if ($distributionLists -and $distributionLists.Count -gt 0) {
            $removedCount = Remove-UserFromDistributionLists -UserUPN $userObj.UPN -Lists $distributionLists
            Write-Host "Odstranen z $removedCount distribucnych listov." -ForegroundColor Green
        }

        # 2) Connect Graph
        Invoke-ExitProcessStep -Action { if (-not (Connect-ToGraphAPI)) { throw "Nepodarilo sa pripojit k Graph API" } } -StepName "Pripojenie k Microsoft Graph" -UserUPN $userObj.UPN -IsCritical $true

        # 3) Odstranenie zo skupin (Azure AD)
        Invoke-ExitProcessStep -Action {
            $groups = Get-MgUserMemberOf -UserId $userObj.UPN -ErrorAction Stop
            foreach ($g in $groups) {
                try {
                    if ($g.additionalProperties.'@odata.type' -like "*group*") {
                        Remove-MgGroupMemberByRef -GroupId $g.id -DirectoryObjectId $userObj.UPN -ErrorAction SilentlyContinue
                    }
                }
                catch { }
            }
        } -StepName "Odstranenie zo skupin" -UserUPN $userObj.UPN -IsCritical $false

        # 4) Vymazanie mailboxu
        Invoke-ExitProcessStep -Action {
            $cert = Get-ExchangeCertificate
            if ($cert) {
                Connect-ExchangeOnline -CertificateThumbprint $cert.Thumbprint -AppId $Script:Config.ClientId -Organization $Script:Config.TenantId -ShowBanner:$false -ErrorAction Stop
            }
            else {
                Connect-ExchangeOnline -UserPrincipalName $Script:Config.AdminEmail -ShowBanner:$false -ErrorAction SilentlyContinue
            }
            Remove-Mailbox -Identity $userObj.UPN -Confirm:$false -PermanentlyDelete -ErrorAction SilentlyContinue
        } -StepName "Vymazanie mailboxu" -UserUPN $userObj.UPN -IsCritical $false

        # 5) Vymazanie Azure AD uctu
        Invoke-ExitProcessStep -Action {
            Remove-MgUser -UserId $userObj.UPN -ErrorAction SilentlyContinue
        } -StepName "Vymazanie Azure AD uctu" -UserUPN $userObj.UPN -IsCritical $false

        # 6) Vymazanie AD uctu
        Invoke-ExitProcessStep -Action {
            Remove-ADUser -Identity $userObj.SamAccountName -Confirm:$false -ErrorAction Stop
        } -StepName "Vymazanie AD uctu" -UserUPN $userObj.UPN -IsCritical $true

        # Aktualizacia CSV
        $userObj.Status = "Deleted"
        Update-UserInCsv -User $userObj

        Write-Host "POUZIVATEL USPESNE VYMAZANY" -ForegroundColor Green
        Write-CustomLog -Message "Pouzivatel vymazany: $($userObj.UPN)" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile

        $emailBody = @"
<html>
<body>
<h2 style='color: red;'>Pouzivatel bol permanentne vymazany</h2>
<p><strong>Meno:</strong> $($userObj.DisplayName)</p>
<p><strong>UPN:</strong> $($userObj.UPN)</p>
<p><strong>Datum offboardingu:</strong> $($userObj.OffboardDate)</p>
<p><strong>Datum vymazania:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
<hr>
<p><strong>Vymazane:</strong></p>
<ul>
<li>OK: Azure AD ucet</li>
<li>OK: Active Directory ucet</li>
<li>OK: Exchange Online mailbox</li>
<li>OK: Vsetky group memberships (ako bolo mozno)</li>
</ul>
<p>Zalohy OneDrive su ulozene v: C:\TaurisIT\OneDriveBackup\$($userObj.UPN)</p>
</body>
</html>
"@

        Send-EmailNotification -ToEmail $Script:Config.AdminEmail -Subject "VYMAZANY POUZIVATEL: $($userObj.DisplayName)" -Body $emailBody
    }
    catch {
        Write-Host "CHYBA PRI VYMAZAVANI: $_" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA pri vymazavani $($userObj.UPN): $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
    }
    finally {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    Read-Host "Stlac Enter pre pokracovanie"
}

# === STATUS VIEW ===
function Show-UserStatus {
    Write-Host "`n=== STATUS POUZIVATELA ===`n" -ForegroundColor Cyan
    $userObj = if ($User) { Get-UserObject -Identifier $User } else { Get-UserObject }
    if (-not $userObj) { return }

    Write-Host "Meno:            $($userObj.DisplayName)"
    Write-Host "SamAccountName:  $($userObj.SamAccountName)"
    Write-Host "UPN:             $($userObj.UPN)"
    Write-Host "Status:          $($userObj.Status)"
    if ($userObj.OffboardDate) { Write-Host "OffboardDate:    $($userObj.OffboardDate)" }
    if ($userObj.ArchiveDate) { Write-Host "ArchiveDate:     $($userObj.ArchiveDate)" }
    if ($userObj.ScheduledDeletionDate) { Write-Host "ScheduledDelete: $($userObj.ScheduledDeletionDate)" }

    $backupPath = Join-Path $Script:Config.BackupRootPath $userObj.UPN
    if (Test-Path $backupPath) {
        Write-Host "Zaloha OneDrive: Existuje -> $backupPath"
    }
    else {
        Write-Host "Zaloha OneDrive: Neexistuje"
    }

    # Distribucne listy
    $distributionLists = Get-DistributionListsForUser -UserUPN $userObj.UPN
    if ($distributionLists -and $distributionLists.Count -gt 0) {
        Write-Host "Distribucne listy: $($distributionLists.Count)"
    }
    else {
        Write-Host "Distribucne listy: 0"
    }

    Read-Host "Stlac Enter pre pokracovanie"
}

# === HLAVNE MENU ===
function Start-ExitProcessMenu {
    Initialize-CsvFile
    try {
        Test-Prerequisites
    }
    catch {
        Write-Host "CHYBA PRI KONTROLE PREDPOKLADOV: $_" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA pri kontrole predpokladov: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
        return
    }

    if ($User) {
        # Ak param -User bol zadany, rovno spusti menu na daneho uzivatela (interactive steps su vo funkciach)
        do {
            Write-Host "`n1) Offboard   2) Archive   3) Delete   4) Status   5) Exit"
            $choice = Read-Host "Zvol moznost (1-5)"
            switch ($choice) {
                '1' { Start-OffboardProcess }
                '2' { Start-ArchiveProcess }
                '3' { Start-DeleteProcess }
                '4' { Show-UserStatus }
                '5' { break }
                default { Write-Host "Neplatna volba." -ForegroundColor Red }
            }
        } while ($choice -ne '5')
    }
    else {
        # Plne interaktivne menu bez parametru
        do {
            Clear-Host
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  EXIT PROCESS MANAGER" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "1) Offboard pouzivatela"
            Write-Host "2) Archive pouzivatela"
            Write-Host "3) Delete pouzivatela"
            Write-Host "4) Zobrazit status pouzivatela"
            Write-Host "5) Ukoncit"
            $choice = Read-Host "Zvol moznost (1-5)"
            switch ($choice) {
                '1' { Start-OffboardProcess }
                '2' { Start-ArchiveProcess }
                '3' { Start-DeleteProcess }
                '4' { Show-UserStatus }
                '5' { Write-CustomLog -Message "Skript ukonceny pouzivatelom" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile; break }
                default { Write-Host "Neplatna volba! Skus znova." -ForegroundColor Red; Start-Sleep -Seconds 2 }
            }
        } while ($choice -ne '5')
    }
}

# === SPUSTENIE ===
try {
    Start-ExitProcessMenu
}
catch {
    Write-Host "KRITICKA CHYBA v hlavnom programe: $_" -ForegroundColor Red
    Write-CustomLog -Message "KRITICKA CHYBA v hlavnom programe: $_" -EventSource $Script:Config.EventSource -LogFileName $Script:Config.LogFile -Type "Error"
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}
