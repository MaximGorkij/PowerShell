<#
.SYNOPSIS
  ExportMailbox.ps1 v6.2 - Stabilna, bezpecna verzia
.DESCRIPTION
  Kompletny skript na export realnych mailbox dat z Microsoft 365 (Graph API).
  - BOM-safe a robustne nacitanie XML konfiguracie (GraphAuth / Graph fallback)
  - Fix pre Trim() bug (nenavolavame Trim na boolean)
  - Pokus o pripojenie cez MgClientSecretCredential, REST fallback ak nie je dostupny
  - Pouzitie reports/getMailboxUsageDetail ako primarneho zdroja storage dat
  - Paging pre users, pairing podla UserPrincipalName
  - Export do Excelu cez ImportExcel a volitelne odoslanie e-mailom
  - TestMode, ForceRest, SendReport parametre

.NOTES
  Autor: Marek Findrik
  Verzia: 6.2
  Datum: 2025-11-05
#>

param(
    [string]$XMLPath = "D:\\findrik\\PowerShell\\EntraID\\ExportEntraUsers\\GraphAuth.xml",
    [string]$ExportPath = "D:\\TaurisIT\\Export",
    [string]$LogPath = "D:\\TaurisIT\\Log",
    [ValidateSet('D7', 'D30', 'D90', 'D180')][string]$UsagePeriod = 'D30',
    [switch]$SendReport,
    [switch]$ForceRest,
    [switch]$TestMode
)

# Require PowerShell 5.1 behavior
$ErrorActionPreference = 'Stop'
$ScriptVersion = '6.2'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARNING', 'ERROR', 'DEBUG')][string]$Level = 'INFO')
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$timestamp][$Level] $Message"
    if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
    Add-Content -Path (Join-Path $LogPath 'ExportMailbox.log') -Value $line
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARNING' { Write-Host $line -ForegroundColor Yellow }
        'OK' { Write-Host $line -ForegroundColor Green }
        'DEBUG' { Write-Host $line -ForegroundColor Gray }
        default { Write-Host $line }
    }
}

# Ensure paths exist
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

Write-Log "Spustam ExportMailbox.ps1 v$ScriptVersion" 'INFO'
if ($TestMode) { Write-Log 'TestMode zapnuty - preskakujem zapis/odoslanie' 'WARNING' }

# Ensure modules (Install if missing) - safe attempt
$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Reports', 'ImportExcel')
foreach ($m in $requiredModules) {
    try {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            Write-Log "Modul $m sa nenasiel - pokusam sa nainstalovat" 'WARNING'
            Install-Module -Name $m -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Log "Nainstalovany modul: $m" 'OK'
        }
        Import-Module $m -ErrorAction Stop
        Write-Log "Import modulu $m uspesny" 'DEBUG'
    }
    catch {
        Write-Log "Chyba pri instalacii/importe modulu $m $($_.Exception.Message)" 'ERROR'
    }
}

# =====================
# Load & validate XML
# =====================
try {
    if (-not (Test-Path $XMLPath)) { throw "Konfiguracny subor neexistuje: $XMLPath" }
    # Read raw text with UTF8 to avoid BOM surprises
    $xmlText = Get-Content -Path $XMLPath -Raw -Encoding UTF8
    [xml]$cfg = $xmlText
    $root = $cfg.DocumentElement
    Write-Log "XML root element: $($root.Name)" 'DEBUG'

    # find node: accept <GraphAuth> or <Graph>
    if ($root.Name -ieq 'GraphAuth' -or $root.Name -ieq 'Graph') { $node = $root } else { $node = $cfg.SelectSingleNode('//GraphAuth') ; if (-not $node) { $node = $cfg.SelectSingleNode('//Graph') } }
    if (-not $node) { throw 'Nepodarilo sa najst uzol GraphAuth/Graph v XML.' }

    # safe extraction - avoid calling Trim on non-strings
    $TenantId = if ($node.TenantId) { [string]$node.TenantId } elseif ($node.DirectoryId) { [string]$node.DirectoryId } else { $null }
    $ClientId = if ($node.ClientId) { [string]$node.ClientId } elseif ($node.AppId) { [string]$node.AppId } else { $null }
    $ClientSecret = if ($node.ClientSecret) { [string]$node.ClientSecret } else { $null }
    $SenderAddress = if ($node.SenderAddress) { [string]$node.SenderAddress } else { $null }
    $RecipientAddress = if ($node.RecipientAddress) { [string]$node.RecipientAddress } else { $null }

    # Trim only when string not null
    if ($TenantId) { $TenantId = $TenantId.Trim() }
    if ($ClientId) { $ClientId = $ClientId.Trim() }
    if ($ClientSecret) { $ClientSecret = $ClientSecret.Trim() }
    if ($SenderAddress) { $SenderAddress = $SenderAddress.Trim() }
    if ($RecipientAddress) { $RecipientAddress = $RecipientAddress.Trim() }

    Write-Log "TenantId length: $([int]($TenantId.Length))" 'DEBUG'
    Write-Log "ClientId length: $([int]($ClientId.Length))" 'DEBUG'
    Write-Log "ClientSecret length: $([int]($ClientSecret.Length))" 'DEBUG'

    if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
        throw 'Chyba v XML konfiguracii: TenantId, ClientId alebo ClientSecret chybaju alebo su prazdne.'
    }
}
catch {
    Write-Log "Chyba pri nacitani konfiguracie: $($_.Exception.Message)" 'ERROR'
    throw
}

# =====================
# Connect to Graph
# =====================
function Connect-ToGraph {
    param([switch]$ForceRestParam)

    try {
        if ($ForceRestParam) { throw 'ForceRest requested' }

        Write-Log 'Skusam pripojenie cez SDK (MgClientSecretCredential)...' 'INFO'
        $typeName = 'Microsoft.Graph.PowerShell.Authentication.Models.MgClientSecretCredential'
        if ([type]::GetType($typeName, $false)) {
            try {
                $credObj = New-Object -TypeName $typeName
                $credObj.ClientId = $ClientId
                $credObj.TenantId = $TenantId
                $credObj.ClientSecret = $ClientSecret
                Connect-MgGraph -ClientSecretCredential $credObj -Scopes 'https://graph.microsoft.com/.default' -ErrorAction Stop
                Write-Log 'Pripojenie cez SDK uspesne.' 'OK'
                $Global:UseRest = $false
                return
            }
            catch {
                Write-Log "SDK connect failed: $($_.Exception.Message)" 'WARNING'
                throw
            }
        }
        else {
            Write-Log 'MgClientSecretCredential typ nie je dostupny v tejto instancii modulu.' 'WARNING'
            throw 'NoClientSecretCredential'
        }
    }
    catch {
        Write-Log 'Fallback: skusam REST OAuth token' 'INFO'
        try {
            $body = @{ grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $ClientSecret; scope = 'https://graph.microsoft.com/.default' }
            $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body -ErrorAction Stop
            $Global:AccessToken = $tokenResponse.access_token
            Write-Log 'REST token ziskany.' 'OK'
            $Global:UseRest = $true
        }
        catch {
            Write-Log "Nepodarilo sa ziskat access token prostrednictvom REST: $($_.Exception.Message)" 'ERROR'
            throw
        }
    }
}

Connect-ToGraph -ForceRestParam:$ForceRest

# Small helper for REST calls with basic retry
function Invoke-GraphRest {
    param([string]$Method = 'GET', [string]$Uri, [hashtable]$Headers = @{}, [object]$Body = $null)
    $attempts = 3
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            if ($Body) { $json = $Body | ConvertTo-Json -Depth 6 } else { $json = $null }
            $resp = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $json -ContentType 'application/json' -ErrorAction Stop
            return $resp
        }
        catch {
            Write-Log "REST call failed (attempt $i): $($_.Exception.Message)" 'WARNING'
            $status = $null
            try { $status = $_.Exception.Response.StatusCode.Value__ -as [int] } catch {}
            if ($status -eq 429 -or $status -ge 500) { Start-Sleep -Seconds (5 * $i); continue } else { throw }
        }
    }
}

# =====================
# Load usage map
# =====================
function Get-UsageMap {
    param([ValidateSet('D7', 'D30', 'D90', 'D180')][string]$Period = 'D30')
    Write-Log "Stahujem mailbox usage detail pre periodu $Period..." 'INFO'
    $usageMap = @{}
    try {
        if ($Global:UseRest -and $Global:AccessToken) {
            $uri = "https://graph.microsoft.com/v1.0/reports/getMailboxUsageDetail(period='$Period')"
            $headers = @{ Authorization = "Bearer $Global:AccessToken" }
            $csvText = Invoke-GraphRest -Method GET -Uri $uri -Headers $headers
            $csvString = if ($csvText -is [System.Array]) { $csvText -join "`n" } else { $csvText }
            $rows = $csvString | ConvertFrom-Csv
        }
        else {
            $csv = Get-MgReportMailboxUsageDetail -Period $Period -ErrorAction Stop
            $csvString = $csv -join "`n"
            $rows = $csvString | ConvertFrom-Csv
        }

        foreach ($r in $rows) {
            $upn = ($r.UserPrincipalName -as [string])
            if (-not $upn) { continue }
            $upn = $upn.ToLower()
            $bytes = 0
            if ($r.PSObject.Properties.Match('StorageUsedInBytes')) { try { $bytes = [long]$r.StorageUsedInBytes } catch {} }
            elseif ($r.PSObject.Properties.Match('StorageUsed')) { $tmp = ($r.StorageUsed -replace '[^0-9]', ''); if ($tmp) { try { $bytes = [long]$tmp } catch {} } }
            $last = $null
            if ($r.PSObject.Properties.Match('LastActivityDate')) { $last = $r.LastActivityDate }
            $usageMap[$upn] = [PSCustomObject]@{ StorageBytes = $bytes; LastActivity = $last; Raw = $r }
        }

        Write-Log "UsageMap obsahuje $($usageMap.Keys.Count) zaznamov" 'OK'
        return $usageMap
    }
    catch {
        Write-Log "Chyba pri stahovani usage reportu: $($_.Exception.Message)" 'ERROR'
        return @{}
    }
}

# =====================
# Get users
# =====================
function Get-RealUserData {
    Write-Log 'Ziskavam zoznam pouzivatelov...' 'INFO'
    $allUsers = @()
    try {
        $select = '$select=id,displayName,userPrincipalName,mail,userType,accountEnabled,createdDateTime,assignedLicenses,onPremisesSyncEnabled,mailNickname'
        if ($Global:UseRest -and $Global:AccessToken) {
            $headers = @{ Authorization = "Bearer $Global:AccessToken" }
            $uri = "https://graph.microsoft.com/v1.0/users?$select&`$top=999"
            do {
                $resp = Invoke-GraphRest -Method GET -Uri $uri -Headers $headers
                if ($resp.value) { $allUsers += $resp.value }
                $uri = $resp.'@odata.nextLink'
            } while ($uri)
        }
        else {
            $users = Get-MgUser -All -Property "id,displayName,userPrincipalName,mail,userType,accountEnabled,createdDateTime,assignedLicenses,onPremisesSyncEnabled,mailNickname" -ErrorAction Stop
            $allUsers = @($users)
        }
        Write-Log "Celkovo nacitanych $($allUsers.Count) pouzivatelov" 'OK'
        return $allUsers
    }
    catch {
        Write-Log "Chyba pri ziskavani users: $($_.Exception.Message)" 'ERROR'
        return @()
    }
}

# =====================
# Get mailbox stats (use usageMap primary)
# =====================
function Get-RealMailboxStats {
    param([string]$UserId, [string]$UPN, [hashtable]$UsageMap)
    $stats = @{ StorageUsedGB = 0; StorageLimitGB = 'Unknown'; LastActivity = 'Unknown' }
    try {
        if ($UsageMap -and $UsageMap.ContainsKey($UPN.ToLower())) {
            $m = $UsageMap[$UPN.ToLower()]
            $stats.StorageUsedGB = [math]::Round($m.StorageBytes / 1GB, 2)
            if ($m.LastActivity) { $stats.LastActivity = $m.LastActivity }
            return $stats
        }

        if ($Global:UseRest -and $Global:AccessToken) {
            $headers = @{ Authorization = "Bearer $Global:AccessToken" }
            try { $mb = Invoke-GraphRest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/mailboxSettings" -Headers $headers } catch {}
            try {
                $lm = Invoke-GraphRest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/messages?`$select=receivedDateTime&`$top=1&`$orderby=receivedDateTime desc" -Headers $headers
                if ($lm.value -and $lm.value[0].receivedDateTime) { $stats.LastActivity = $lm.value[0].receivedDateTime }
            }
            catch {}
        }
        else {
            try { $lm = Get-MgUserMessage -UserId $UserId -Top 1 -Sort 'receivedDateTime desc' -ErrorAction SilentlyContinue; if ($lm) { $stats.LastActivity = $lm.receivedDateTime } } catch {}
        }

        return $stats
    }
    catch {
        Write-Log "Chyba pri mailbox stats pre $UPN $($_.Exception.Message)" 'DEBUG'
        return $stats
    }
}

# =====================
# MAIN
# =====================
try {
    Write-Log "Spustam zber usage ($UsagePeriod) a users" 'INFO'
    $UsageMap = Get-UsageMap -Period $UsagePeriod
    $Users = Get-RealUserData
    if (-not $Users -or $Users.Count -eq 0) { throw 'Neboli nacitani ziaden pouzivatelia' }

    $result = @()
    $i = 0
    foreach ($u in $Users) {
        $i++
        if ($i % 50 -eq 0) { Write-Log "Spracovanych $i z $($Users.Count) users" 'INFO' }
        $upn = ($u.userPrincipalName -as [string])
        if (-not $upn) { continue }
        $stats = Get-RealMailboxStats -UserId $u.id -UPN $upn -UsageMap $UsageMap
        $isLicensed = $false
        if ($u.assignedLicenses -and $u.assignedLicenses.Count -gt 0) { $isLicensed = $true }
        $ownerStatus = if ($u.accountEnabled -eq $false) { 'Disabled' } else { 'Active' }
        $mailboxInfo = [PSCustomObject]@{
            DisplayName       = $u.displayName
            UserPrincipalName = $upn
            EmailAddress      = $u.mail
            MailboxType       = 'User'
            OwnerStatus       = $ownerStatus
            AccountEnabled    = $u.accountEnabled
            CreatedDate       = if ($u.createdDateTime) { ([datetime]$u.createdDateTime).ToString('yyyy-MM-dd') } else { 'Unknown' }
            StorageUsedGB     = $stats.StorageUsedGB
            StorageLimitGB    = $stats.StorageLimitGB
            UsagePercentage   = if ($stats.StorageLimitGB -is [string] -and $stats.StorageLimitGB -eq 'Unknown') { 0 } else { if ($stats.StorageLimitGB -gt 0) { [math]::Round(($stats.StorageUsedGB / $stats.StorageLimitGB) * 100, 2) } else { 0 } }
            IsLicensed        = $isLicensed
            LastActivity      = $stats.LastActivity
            IsSyncedFromAD    = if ($u.onPremisesSyncEnabled) { 'Yes' } else { 'No' }
            ReportDate        = (Get-Date).ToString('yyyy-MM-dd')
        }
        $result += $mailboxInfo
    }

    Write-Log "Dokoncene spracovanie: vytvorenych $($result.Count) zaznamov" 'OK'

    # Export
    if (-not $TestMode) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
        $file = Join-Path $ExportPath "MailboxReport_RealData_$timestamp.xlsx"
        Write-Log "Exportujem do Excelu: $file" 'INFO'
        $result | Export-Excel -Path $file -WorksheetName 'All' -AutoSize -AutoFilter -BoldTopRow
        $result | Where-Object { $_.IsLicensed -eq $true } | Export-Excel -Path $file -WorksheetName 'Licensed' -AutoSize -Append
        $result | Where-Object { $_.OwnerStatus -eq 'Disabled' } | Export-Excel -Path $file -WorksheetName 'Disabled' -AutoSize -Append
        Write-Log 'Export do Excelu dokonceny' 'OK'
    }
    else { Write-Log 'TestMode - preskakujem export' 'INFO'; $file = $null }

    # Send
    if ($SendReport -and -not $TestMode -and $file -and (Test-Path $file)) {
        Write-Log 'Priprava odoslania reportu cez Graph' 'INFO'
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $b64 = [System.Convert]::ToBase64String($bytes)
        $attachmentName = Split-Path $file -Leaf
        $emailBodyHtml = "<h3>Mailbox Report - Real data - $(Get-Date -Format 'yyyy-MM-dd')</h3><p>Celkovy pocet zaznamov: $($result.Count)</p>"
        $mail = @{ message = @{ subject = "Mailbox Report - Real data - $(Get-Date -Format 'yyyy-MM-dd')"; body = @{ contentType = 'HTML'; content = $emailBodyHtml }; toRecipients = @(@{ emailAddress = @{ address = $RecipientAddress } }); attachments = @(@{ '@odata.type' = '#microsoft.graph.fileAttachment'; name = $attachmentName; contentBytes = $b64 }) }; saveToSentItems = 'true' }

        if ($Global:UseRest -and $Global:AccessToken) {
            $headers = @{ Authorization = "Bearer $Global:AccessToken"; 'Content-Type' = 'application/json' }
            $uri = "https://graph.microsoft.com/v1.0/users/$SenderAddress/sendMail"
            Invoke-GraphRest -Method POST -Uri $uri -Headers $headers -Body $mail
            Write-Log 'Report bol odoslany cez REST Graph' 'OK'
        }
        else {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$SenderAddress/sendMail" -Body ($mail | ConvertTo-Json -Depth 6) -ErrorAction Stop
            Write-Log 'Report bol odoslany cez SDK (Mg)' 'OK'
        }
    }

    if ($TestMode) { Write-Log 'TestMode: Skript dobehol bez zapisov/odoslania' 'OK' }
}
catch {
    Write-Log "Kriticka chyba v hlavnom spracovani: $($_.Exception.Message)" 'ERROR'
    Write-Log "StackTrace: $($_.Exception.StackTrace)" 'ERROR'
    throw
}
finally {
    try { if (-not $Global:UseRest) { Disconnect-MgGraph -ErrorAction SilentlyContinue } } catch {}
    Write-Log 'Skript dokonceny' 'INFO'
}

# Show sample
if ($result -and $result.Count -gt 0) {
    Write-Log 'Ukazka prvych 5 zaznamov:' 'INFO'
    $result | Select-Object -First 5 | Format-Table DisplayName, UserPrincipalName, StorageUsedGB, IsLicensed, OwnerStatus -AutoSize | Out-String | ForEach-Object { Write-Log $_ 'INFO' }
}
else { Write-Log 'Ziadne vysledky pre zobrazenie' 'WARNING' }
