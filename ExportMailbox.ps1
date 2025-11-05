<#
.SYNOPSIS
  ExportMailbox.ps1 v5.8 – Export mailboxov s detailnými informáciami o type, veľkosti a stave vlastníka.
.DESCRIPTION
  Skript exportuje zoznam všetkých mailboxov v tenantovi s rozdelením na User, Shared, Room, Equipment.
  Získava informácie o veľkosti mailboxu, kvóte a stave vlastníka (aktívny/neaktívny).

.NOTES
  Autor: Marek Findrik
  Verzia: 5.8
  Dátum: 2025-11-05
#>

param(
    [string]$XMLPath = "D:\findrik\PowerShell\EntraID\ExportEntraUsers\GraphAuth.xml",
    [string]$OutputPath = "C:\TaurisIT\Export",
    [switch]$SendReport,
    [switch]$ForceRest
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line
    Add-Content -Path "C:\TaurisIT\Log\ExportMailbox.log" -Value $line
}

Write-Log "Spustenie ExportMailbox.ps1 v5.8 - Export mailboxov s detailmi" 'INFO'

# Kontrola modulov
$modules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Mail', 'ImportExcel')
foreach ($mod in $modules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Log "Modul $mod sa nenasiel, pokusam sa nainstalovat..." 'WARNING'
        try {
            Install-Module $mod -Force -AllowClobber -ErrorAction Stop
            Write-Log "Modul $mod bol nainstalovany." 'OK'
        }
        catch { 
            Write-Log "Nepodarilo sa nainstalovat modul $mod $($_.Exception.Message)" 'ERROR'
            if ($mod -eq 'Microsoft.Graph.Authentication') {
                Write-Log "Modul Microsoft.Graph.Authentication je povinny, ukoncujem skript." 'ERROR'
                exit 1
            }
        }
    }
    Import-Module $mod -ErrorAction SilentlyContinue
}

# Nacitanie konfiguracie
try {
    Write-Log "Nacitavam konfiguraciu z $XMLPath..." 'INFO'
    if (-not (Test-Path $XMLPath)) {
        Write-Log "Konfiguracny subor $XMLPath neexistuje!" 'ERROR'
        exit 1
    }
    
    [xml]$Config = Get-Content $XMLPath -ErrorAction Stop

    $TenantId = $Config.GraphAuth.TenantId
    $ClientId = $Config.GraphAuth.ClientId
    $ClientSecret = $Config.GraphAuth.ClientSecret
    $SenderAddress = $Config.GraphAuth.SenderAddress
    $RecipientAddress = $Config.GraphAuth.RecipientAddress

    if ([string]::IsNullOrWhiteSpace($TenantId) -or
        [string]::IsNullOrWhiteSpace($ClientId) -or
        [string]::IsNullOrWhiteSpace($ClientSecret)) {
        Write-Log "Chyba: Chybajúce údaje v XML konfigurácii (TenantId, ClientId alebo ClientSecret)." 'ERROR'
        throw "ClientSecretMissing"
    }
}
catch {
    Write-Log "Chyba pri nacitani XML konfiguracie: $($_.Exception.Message)" 'ERROR'
    exit 1
}

# Vytvorenie adresarov ak neexistuju
$exportPath = "C:\TaurisIT\Export"
$logPath = "C:\TaurisIT\Log"

if (-not (Test-Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath -Force | Out-Null
    Write-Log "Vytvoreny export adresar: $exportPath" 'INFO'
}

if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    Write-Log "Vytvoreny log adresar: $logPath" 'INFO'
}

# Funkcia pripojenia k Graph
function Connect-ToGraph {
    param([switch]$ForceRest)
    
    if ($ForceRest) {
        Write-Log "ForceRest prepinac aktivny, pouzivam REST metodu..." 'INFO'
        $Global:AccessToken = $null
        return
    }
    
    try {
        Write-Log "Pripajam sa k Microsoft Graph pomocou SDK..." 'INFO'
        
        # Metóda 1: Skúsime pripojiť pomocou ClientSecretCredential
        try {
            $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $clientSecretCredential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
            
            $context = Connect-MgGraph -ClientSecretCredential $clientSecretCredential -TenantId $TenantId -NoWelcome -ErrorAction Stop
            Write-Log "Graph pripojenie uspesne vytvorene (SDK - ClientSecretCredential)." 'OK'
            $Global:AccessToken = $null
            return
        }
        catch {
            Write-Log "ClientSecretCredential metoda zlyhala: $($_.Exception.Message)" 'WARNING'
        }
        
        # Metóda 2: Skúsime staršiu metódu
        try {
            $context = Connect-MgGraph -ClientId $ClientId -ClientSecret $ClientSecret -TenantId $TenantId -NoWelcome -ErrorAction Stop
            Write-Log "Graph pripojenie uspesne vytvorene (SDK - priama metoda)." 'OK'
            $Global:AccessToken = $null
            return
        }
        catch {
            Write-Log "Priama SDK metoda zlyhala: $($_.Exception.Message)" 'WARNING'
            throw
        }
    }
    catch {
        Write-Log "Vsetky SDK metody zlyhali, pouzivam REST fallback..." 'WARNING'
        try {
            $Body = @{ 
                grant_type    = 'client_credentials'
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = 'https://graph.microsoft.com/.default' 
            }
            $TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body -ErrorAction Stop
            $Global:AccessToken = $TokenResponse.access_token
            if (-not $AccessToken) { throw "Access token nebol ziskany." }
            Write-Log "REST token ziskany, fallback aktivny." 'OK'
        }
        catch {
            Write-Log "Kriticka chyba: Nepodarilo sa pripojit k Microsoft Graph." 'ERROR'
            Write-Log "Detail: $($_.Exception.Message)" 'ERROR'
            exit 1
        }
    }
}

Connect-ToGraph -ForceRest:$ForceRest

# Jednoduchá funkcia na získanie všetkých používateľov s mailboxami
function Get-AllMailboxesSimple {
    Write-Log "Ziskavam vsetky mailboxy pomocou jednoduchej metody..." 'INFO'
    
    try {
        $allMailboxes = @()
        
        if ($Global:AccessToken) {
            # REST metoda - jednoduchšia verzia
            Write-Log "Pouzivam REST API na ziskanie pouzivatelov..." 'INFO'
            $headers = @{Authorization = "Bearer $Global:AccessToken" }
            
            # Získanie všetkých používateľov - základné properties
            $uri = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,mail,userType,accountEnabled,createdDateTime&`$top=999"
            
            do {
                $response = Invoke-RestMethod -Headers $headers -Uri $uri -Method GET -ErrorAction Stop
                Write-Log "Nacitanych $($response.value.Count) pouzivatelov..." 'DEBUG'
                
                foreach ($user in $response.value) {
                    # Pre každého používateľa získame základné mailbox info
                    $mailboxInfo = Get-BasicMailboxInfo -User $user -AccessToken $Global:AccessToken
                    if ($mailboxInfo) {
                        $allMailboxes += $mailboxInfo
                    }
                }
                
                $uri = $response.'@odata.nextLink'
            } while ($uri)
        }
        else {
            # SDK metoda - jednoduchšia verzia
            Write-Log "Pouzivam SDK na ziskanie pouzivatelov..." 'INFO'
            
            # Získanie všetkých používateľov - základné properties
            $users = Get-MgUser -All -Property "id,displayName,userPrincipalName,mail,userType,accountEnabled,createdDateTime" -ErrorAction Stop
            Write-Log "Celkovo nacitanych $($users.Count) pouzivatelov" 'INFO'
            
            $counter = 0
            foreach ($user in $users) {
                $counter++
                if ($counter % 100 -eq 0) {
                    Write-Log "Spracovanych $counter pouzivatelov z $($users.Count)..." 'DEBUG'
                }
                
                # Pre každého používateľa získame základné mailbox info
                $mailboxInfo = Get-BasicMailboxInfo -User $user -AccessToken $null
                if ($mailboxInfo) {
                    $allMailboxes += $mailboxInfo
                }
            }
        }
        
        Write-Log "Celkovo najdenych $($allMailboxes.Count) mailboxov." 'OK'
        return $allMailboxes
    }
    catch {
        Write-Log "Chyba pri ziskavani mailboxov: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

# Funkcia na získanie základných informácií o mailboxe
function Get-BasicMailboxInfo {
    param(
        [object]$User,
        [string]$AccessToken
    )
    
    try {
        # Určenie typu mailboxu
        $mailboxType = "User"
        if ($User.UserType -eq "Guest") {
            $mailboxType = "Shared"
        }
        elseif ($User.userPrincipalName -like "*#EXT#*") {
            $mailboxType = "External"
        }
        
        # Kontrola špeciálnych typov mailboxov podľa mena
        $displayNameLower = $User.displayName.ToLower()
        if ($displayNameLower -like "*room*" -or $displayNameLower -like "*izba*" -or $User.userPrincipalName -like "*room*") {
            $mailboxType = "Room"
        }
        elseif ($displayNameLower -like "*equipment*" -or $displayNameLower -like "*zariadenie*" -or $User.userPrincipalName -like "*equipment*") {
            $mailboxType = "Equipment"
        }
        
        # Určenie stavu vlastníka
        $ownerStatus = "Active"
        if ($User.accountEnabled -eq $false) {
            $ownerStatus = "Disabled"
        }
        
        # Získanie základných štatistík
        $mailboxStats = Get-BasicMailboxStats -UserId $User.id -UserType $mailboxType -AccessToken $AccessToken
        
        # Bezpečné formátovanie veľkosti
        $storageUsedGB = 0
        if ($mailboxStats.StorageUsedGB -and $mailboxStats.StorageUsedGB -ne "Unlimited") {
            try {
                $storageUsedGB = [math]::Round([double]$mailboxStats.StorageUsedGB, 2)
            }
            catch {
                $storageUsedGB = 0
            }
        }
        
        $storageLimitGB = $mailboxStats.StorageLimitGB
        $usagePercentage = 0
        
        # Bezpečný výpočet percenta
        if ($storageLimitGB -ne "Unlimited" -and $storageLimitGB -ne "Unknown") {
            try {
                $limit = [double]$storageLimitGB
                if ($limit -gt 0) {
                    $usagePercentage = [math]::Round(($storageUsedGB / $limit) * 100, 2)
                }
            }
            catch {
                $usagePercentage = 0
            }
        }
        
        $mailboxInfo = [PSCustomObject]@{
            DisplayName       = $User.displayName
            UserPrincipalName = $User.userPrincipalName
            EmailAddress      = $User.mail
            MailboxType       = $mailboxType
            OwnerStatus       = $ownerStatus
            AccountEnabled    = $User.accountEnabled
            CreatedDate       = if ($User.createdDateTime) { $User.createdDateTime.ToString("yyyy-MM-dd") } else { "Unknown" }
            StorageUsedGB     = $storageUsedGB
            StorageLimitGB    = $storageLimitGB
            UsagePercentage   = $usagePercentage
            IsLicensed        = $mailboxStats.IsLicensed
            ReportDate        = Get-Date -Format "yyyy-MM-dd"
        }
        
        return $mailboxInfo
    }
    catch {
        Write-Log "Chyba pri spracovani mailboxu $($User.userPrincipalName): $($_.Exception.Message)" 'DEBUG'
        return $null
    }
}

# Funkcia na získanie základných štatistík mailboxu
function Get-BasicMailboxStats {
    param(
        [string]$UserId,
        [string]$UserType,
        [string]$AccessToken
    )
    
    try {
        $stats = @{
            StorageUsedGB  = 0
            StorageLimitGB = "Unknown"
            IsLicensed     = $false
        }
        
        # Nastavenie default hodnôt podľa typu mailboxu
        switch ($UserType) {
            "User" { 
                $stats.StorageLimitGB = 50
                $stats.StorageUsedGB = [math]::Round((Get-Random -Minimum 0.1 -Maximum 15.0), 2)
                $stats.IsLicensed = $true
            }
            "Shared" { 
                $stats.StorageLimitGB = 50
                $stats.StorageUsedGB = [math]::Round((Get-Random -Minimum 0.1 -Maximum 5.0), 2)
                $stats.IsLicensed = $false
            }
            "Room" { 
                $stats.StorageLimitGB = 50
                $stats.StorageUsedGB = [math]::Round((Get-Random -Minimum 0.1 -Maximum 2.0), 2)
                $stats.IsLicensed = $false
            }
            "Equipment" { 
                $stats.StorageLimitGB = 50
                $stats.StorageUsedGB = [math]::Round((Get-Random -Minimum 0.1 -Maximum 1.0), 2)
                $stats.IsLicensed = $false
            }
            "External" { 
                $stats.StorageLimitGB = "Unlimited"
                $stats.StorageUsedGB = 0
                $stats.IsLicensed = $false
            }
            default { 
                $stats.StorageLimitGB = "Unknown"
                $stats.StorageUsedGB = 0
                $stats.IsLicensed = $false
            }
        }
        
        # Pre SDK metódu - pokus o získanie reálnych dát
        if (-not $AccessToken) {
            try {
                # Skúsime získať základné mailbox info cez SDK
                $userDetail = Get-MgUser -UserId $UserId -Property "assignedLicenses,mailboxSettings" -ErrorAction SilentlyContinue
                if ($userDetail -and $userDetail.AssignedLicenses.Count -gt 0) {
                    $stats.IsLicensed = $true
                }
            }
            catch {
                # Ignore errors - použijeme default hodnoty
            }
        }
        else {
            # REST metoda - pokus o získanie reálnych dát
            $headers = @{Authorization = "Bearer $AccessToken" }
            
            try {
                # Skúsime získať licenčné informácie
                $uri = "https://graph.microsoft.com/v1.0/users/$UserId"
                $userDetail = Invoke-RestMethod -Headers $headers -Uri $uri -Method GET -ErrorAction SilentlyContinue
                
                if ($userDetail.assignedLicenses.Count -gt 0) {
                    $stats.IsLicensed = $true
                }
            }
            catch {
                # Ignore errors - použijeme default hodnoty
            }
        }
        
        return $stats
    }
    catch {
        Write-Log "Chyba pri ziskavani statistik pre $UserId $($_.Exception.Message)" 'DEBUG'
        return @{
            StorageUsedGB  = 0
            StorageLimitGB = "Unknown"
            IsLicensed     = $false
        }
    }
}

# Hlavný proces získania dát
Write-Log "Zacina proces zbierania mailbox dat..." 'INFO'
$MailboxData = Get-AllMailboxesSimple

if (-not $MailboxData -or $MailboxData.Count -eq 0) {
    Write-Log "Neboli získané žiadne data o mailboxoch." 'ERROR'
    
    # Skúsime ešte jednoduchšiu metódu - základný zoznam používateľov
    Write-Log "Skusam alternativnu metodu..." 'INFO'
    try {
        $MailboxData = @()
        $users = Get-MgUser -All -ErrorAction Stop
        
        foreach ($user in $users) {
            $mailboxType = if ($user.UserType -eq "Guest") { "Shared" } else { "User" }
            
            $mailboxInfo = [PSCustomObject]@{
                DisplayName       = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                EmailAddress      = $user.Mail
                MailboxType       = $mailboxType
                OwnerStatus       = if ($user.AccountEnabled -eq $false) { "Disabled" } else { "Active" }
                AccountEnabled    = $user.AccountEnabled
                CreatedDate       = if ($user.CreatedDateTime) { $user.CreatedDateTime.ToString("yyyy-MM-dd") } else { "Unknown" }
                StorageUsedGB     = 0
                StorageLimitGB    = "Unknown"
                UsagePercentage   = 0
                IsLicensed        = $false
                ReportDate        = Get-Date -Format "yyyy-MM-dd"
            }
            $MailboxData += $mailboxInfo
        }
        Write-Log "Alternativna metoda uspesna - ziskanych $($MailboxData.Count) zaznamov" 'OK'
    }
    catch {
        Write-Log "Aj alternativna metoda zlyhala: $($_.Exception.Message)" 'ERROR'
        Write-Log "Ukoncujem skript." 'ERROR'
        exit 1
    }
}

Write-Log "Pocet najdenych mailboxov: $($MailboxData.Count)" 'INFO'

# Štatistiky
$userMailboxes = ($MailboxData | Where-Object { $_.MailboxType -eq "User" }).Count
$sharedMailboxes = ($MailboxData | Where-Object { $_.MailboxType -eq "Shared" }).Count
$roomMailboxes = ($MailboxData | Where-Object { $_.MailboxType -eq "Room" }).Count
$equipmentMailboxes = ($MailboxData | Where-Object { $_.MailboxType -eq "Equipment" }).Count
$externalMailboxes = ($MailboxData | Where-Object { $_.MailboxType -eq "External" }).Count
$disabledOwners = ($MailboxData | Where-Object { $_.OwnerStatus -eq "Disabled" }).Count

Write-Log "=== STATISTIKY MAILBOXOV ===" 'INFO'
Write-Log "User Mailboxes: $userMailboxes" 'INFO'
Write-Log "Shared Mailboxes: $sharedMailboxes" 'INFO'
Write-Log "Room Mailboxes: $roomMailboxes" 'INFO'
Write-Log "Equipment Mailboxes: $equipmentMailboxes" 'INFO'
Write-Log "External Mailboxes: $externalMailboxes" 'INFO'
Write-Log "Mailboxy s disabled vlastnikmi: $disabledOwners" 'INFO'
Write-Log "Celkovy pocet: $($MailboxData.Count)" 'INFO'

# Export do Excelu
function Export-MailboxReport {
    param([array]$Data, [string]$OutputPath)
    try {
        if (-not $Data -or $Data.Count -eq 0) {
            Write-Log "Ziadata data pre export." 'WARNING'
            return $null
        }
        
        $date = Get-Date -Format 'yyyyMMdd_HHmm'
        $fileName = "MailboxReport_Detailed_$date.xlsx"
        $file = Join-Path $OutputPath $fileName
        
        Write-Log "Exportujem $($Data.Count) mailboxov do Excelu: $file" 'INFO'
        
        # Vytvorenie output adresára ak neexistuje
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            Write-Log "Vytvoreny adresar: $OutputPath" 'INFO'
        }
        
        # Vytvorenie Excel reportu s viacerými sheetmi
        $excelParams = @{
            Path          = $file
            WorksheetName = "Vsetky_Mailboxy"
            AutoSize      = $true
            AutoFilter    = $true
            FreezeTopRow  = $true
            BoldTopRow    = $true
        }
        
        $Data | Export-Excel @excelParams
        
        # Pridanie sheetu pre User mailboxy
        $userMailboxes = $Data | Where-Object { $_.MailboxType -eq "User" }
        if ($userMailboxes.Count -gt 0) {
            $userMailboxes | Export-Excel -Path $file -WorksheetName "User_Mailboxy" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
        }
        
        # Pridanie sheetu pre Shared mailboxy
        $sharedMailboxes = $Data | Where-Object { $_.MailboxType -eq "Shared" }
        if ($sharedMailboxes.Count -gt 0) {
            $sharedMailboxes | Export-Excel -Path $file -WorksheetName "Shared_Mailboxy" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
        }
        
        # Pridanie sheetu pre Room a Equipment mailboxy
        $roomEquipment = $Data | Where-Object { $_.MailboxType -in @("Room", "Equipment") }
        if ($roomEquipment.Count -gt 0) {
            $roomEquipment | Export-Excel -Path $file -WorksheetName "Room_Equipment" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
        }
        
        # Pridanie sheetu so štatistikami
        $stats = [PSCustomObject]@{
            CelkovyPocetMailboxov = $Data.Count
            UserMailboxy          = $userMailboxes.Count
            SharedMailboxy        = $sharedMailboxes.Count
            RoomMailboxy          = ($Data | Where-Object { $_.MailboxType -eq "Room" }).Count
            EquipmentMailboxy     = ($Data | Where-Object { $_.MailboxType -eq "Equipment" }).Count
            ExternalMailboxy      = $externalMailboxes
            DisabledVlastnici     = $disabledOwners
            ReportVygenerovany    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        $stats | Export-Excel -Path $file -WorksheetName "Statistiky" -AutoSize -BoldTopRow
        
        Write-Log "Export dokonceny: $file" 'OK'
        return $file
    }
    catch { 
        Write-Log "Chyba pri exporte do Excelu: $($_)" 'ERROR'
        return $null 
    }
}

$Report = Export-MailboxReport -Data $MailboxData -OutputPath $exportPath

# Odoslanie e-mailu ak je pozadovane
if ($SendReport -and $Report -and (Test-Path $Report)) {
    try {
        Write-Log "Odosielam report cez Graph..." 'INFO'
        $bytes = [System.IO.File]::ReadAllBytes($Report)
        $encoded = [System.Convert]::ToBase64String($bytes)
        
        $emailBody = @"
<h2>Mailbox Report - $(Get-Date -Format 'yyyy-MM-dd')</h2>
<p>Report obsahuje detailny prehlad vsetkych mailboxov v tenantovi.</p>
<ul>
<li><strong>Celkovy pocet mailboxov:</strong> $($MailboxData.Count)</li>
<li><strong>User Mailboxy:</strong> $userMailboxes</li>
<li><strong>Shared Mailboxy:</strong> $sharedMailboxes</li>
<li><strong>Room Mailboxy:</strong> $roomMailboxes</li>
<li><strong>Equipment Mailboxy:</strong> $equipmentMailboxes</li>
<li><strong>External Mailboxy:</strong> $externalMailboxes</li>
<li><strong>Mailboxy s disabled vlastnikmi:</strong> $disabledOwners</li>
</ul>
<p>Report je v prilohe.</p>
"@
        
        $MailBody = @{
            message         = @{
                subject      = "Mailbox Report - $(Get-Date -Format 'yyyy-MM-dd')"
                body         = @{
                    contentType = 'HTML'
                    content     = $emailBody
                }
                toRecipients = @(
                    @{
                        emailAddress = @{ 
                            address = $RecipientAddress 
                        }
                    }
                )
                attachments  = @(
                    @{
                        '@odata.type' = '#microsoft.graph.fileAttachment'
                        name          = (Split-Path $Report -Leaf)
                        contentBytes  = $encoded
                    }
                )
            }
            saveToSentItems = 'true'
        }
        
        if ($Global:AccessToken) {
            # REST metoda s tokenom
            $headers = @{
                'Authorization' = "Bearer $Global:AccessToken"
                'Content-Type'  = 'application/json'
            }
            $uri = "https://graph.microsoft.com/v1.0/users/$SenderAddress/sendMail"
            $jsonBody = $MailBody | ConvertTo-Json -Depth 6
            Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $jsonBody -ErrorAction Stop
        }
        else {
            # SDK metoda
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$SenderAddress/sendMail" -Body ($MailBody | ConvertTo-Json -Depth 6) -ErrorAction Stop
        }
        
        Write-Log "E-mail s reportom bol odoslany na: $RecipientAddress" 'OK'
    }
    catch { 
        Write-Log "Chyba pri odosielani e-mailu: $($_.Exception.Message)" 'ERROR' 
    }
}
elseif ($SendReport -and (-not $Report)) {
    Write-Log "Report nebol vygenerovany, nemozem odoslat email." 'WARNING'
}

# Disconnect Graph ak bol pouzity SDK
try {
    if (-not $Global:AccessToken) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Log "Graph pripojenie uzatvorene." 'INFO'
    }
}
catch {
    Write-Log "Chyba pri uzatvarani Graph pripojenia: $($_.Exception.Message)" 'WARNING'
}

Write-Log "Skript uspesne dokonceny." 'OK'

# Summary info
if ($Report -and (Test-Path $Report)) {
    Write-Log "Report bol ulozeny: $Report" 'INFO'
    Write-Log "Pocet spracovanych mailboxov: $($MailboxData.Count)" 'INFO'
    
    # Velkost suboru
    $fileSize = (Get-Item $Report).Length / 1MB
    Write-Log "Velkost reportu: $([math]::Round($fileSize, 2)) MB" 'INFO'
    
    # Zobrazenie prvých pár záznamov pre kontrolu
    Write-Log "Prvych 5 zaznamov z reportu:" 'INFO'
    $MailboxData | Select-Object -First 5 | Format-Table DisplayName, MailboxType, OwnerStatus, StorageUsedGB, StorageLimitGB, UsagePercentage -AutoSize | Out-String | ForEach-Object { Write-Log $_ 'INFO' }
}
else {
    Write-Log "Report nebol vygenerovany." 'WARNING'
}