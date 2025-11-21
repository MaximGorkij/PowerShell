# ExportMailbox_v7.0a.ps1
# Requires -Version 5.1
<#
.SYNOPSIS
  ExportMailbox v7.0a - Real mailbox usage via ExchangeOnlineManagement
.DESCRIPTION
  - If GraphAuth.xml exists and contains certificate info -> App-only (certificate) Connect-ExchangeOnline is used.
  - Otherwise falls back to interactive Connect-ExchangeOnline (user prompt).
  - Collects real mailbox usage using Get-Mailbox and Get-MailboxStatistics.
  - Exports a single Excel sheet with MailboxType column (User/Shared).
  - Installs ExchangeOnlineManagement and ImportExcel modules if missing.
.NOTES
  Author: Generated for user
  Version: 7.0a
  Date: 2025-11-05
#>

param(
    [string]$XMLPath = "D:\findrik\PowerShell\EntraID\ExportEntraUsers\GraphAuth.xml",
    [string]$ExportPath = "D:\TaurisIT\Export",
    [string]$LogPath = "D:\TaurisIT\Log",
    [switch]$TestMode
)

# --- Logging function ---
function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "OK", "WARNING", "ERROR", "DEBUG")][string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp][$Level] $Message"
    if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
    $logFile = Join-Path $LogPath "ExportMailbox.log"
    Add-Content -Path $logFile -Value $line
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        "OK" { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

# Ensure directories
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

Write-Log "Spustam ExportMailbox v7.0a" "INFO"

# Ensure required modules
$modules = @("ExchangeOnlineManagement", "ImportExcel")
foreach ($m in $modules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Log "Modul $m nenajdeny, pokus o instalaciu (CurrentUser)..." "WARNING"
        try {
            Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Log "Modul $m nainstalovany." "OK"
        }
        catch {
            Write-Log "Nepodarilo sa nainstalovat modul $m $($_.Exception.Message)" "ERROR"
            throw
        }
    }
    try {
        Import-Module $m -ErrorAction Stop
        Write-Log "Import modulu $m uspesny." "DEBUG"
    }
    catch {
        Write-Log "Import modulu $m neuspesny: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Load XML if exists
$useAppOnly = $false
$xmlConfig = $null
if (Test-Path $XMLPath) {
    try {
        Write-Log "Nacitavam konfiguraciu Z: $XMLPath" "INFO"
        [xml]$xmlConfig = Get-Content -Path $XMLPath -Raw -Encoding UTF8
        $root = $xmlConfig.DocumentElement
        Write-Log "XML root: $($root.Name)" "DEBUG"
        # Accept GraphAuth or Graph or Settings
        $node = $null
        if ($root.Name -in @('GraphAuth', 'Graph', 'Settings')) { $node = $root } else {
            $node = $xmlConfig.SelectSingleNode('//GraphAuth') 
            if (-not $node) { $node = $xmlConfig.SelectSingleNode('//Graph') }
            if (-not $node) { $node = $xmlConfig.SelectSingleNode('//Settings') }
        }
        if ($node) {
            $TenantId = ($node.TenantId -as [string]).Trim()
            $ClientId = (($node.ClientId -as [string]) -or ($node.AppId -as [string])) 
            if ($ClientId) { $ClientId = $ClientId.Trim() }
            $ClientSecret = ($node.ClientSecret -as [string])
            if ($ClientSecret) { $ClientSecret = $ClientSecret.Trim() }
            $CertThumb = ($node.CertificateThumbprint -as [string])
            $CertPath = ($node.CertificatePath -as [string])
            if ($CertThumb) { $CertThumb = $CertThumb.Trim() }
            if ($CertPath) { $CertPath = $CertPath.Trim() }

            if ($CertThumb -or $CertPath) {
                Write-Log "Konfiguracia obsahuje informacie o certifikate, pripravujem App-Only pripojenie (certifikat)." "INFO"
                $useAppOnly = $true
            }
            else {
                Write-Log "Konfiguracia neobsahuje certifikat (app-only via cert). Interaktivne pripojenie bude vyuzite, ak app-only nebude mozne." "INFO"
                # If you want to attempt secret-based Exchange app-only, note EXO PowerShell typically requires certificate.
            }
        }
        else {
            Write-Log "XML subor neobsahuje ocakavane uzly (GraphAuth/Graph/Settings). Prepinam na interaktivny rezim." "WARNING"
        }
    }
    catch {
        Write-Log "Chyba pri nacitani XML konfiguracie: $($_.Exception.Message)" "ERROR"
        $xmlConfig = $null
    }
}
else {
    Write-Log "XML konfiguracia neexistuje na $XMLPath - pouzijem interaktivne prihlasenie." "WARNING"
}

# Connect to Exchange Online
try {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}
catch {}

if ($useAppOnly) {
    try {
        # Prefer certificate thumbprint if provided
        if ($CertThumb) {
            Write-Log "Pripajam sa k Exchange Online pomocou App-Only + CertificateThumbprint ($CertThumb)..." "INFO"
            Connect-ExchangeOnline -CertificateThumbprint $CertThumb -AppId $ClientId -Organization $TenantId -ShowBanner:$false -ErrorAction Stop
            Write-Log "Connect-ExchangeOnline (App-only cert) uspesne." "OK"
        }
        elseif ($CertPath) {
            Write-Log "Pripajam sa k Exchange Online pomocou App-Only + CertificateFile ($CertPath)..." "INFO"
            # If certificate needs password, script will ask interactively
            Connect-ExchangeOnline -CertificateFilePath $CertPath -AppId $ClientId -Organization $TenantId -ShowBanner:$false -ErrorAction Stop
            Write-Log "Connect-ExchangeOnline (App-only cert file) uspesne." "OK"
        }
        else {
            Write-Log "Certifikat nebol dostupny aj ked flag useAppOnly je nastaveny - prepinam na interaktivne pripojenie." "WARNING"
            throw "NoCert"
        }
    }
    catch {
        Write-Log "App-only Connect neuspesny: $($_.Exception.Message)" "WARNING"
        Write-Log "Prepinam na interaktivne prihlasenie..." "INFO"
        try {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            Write-Log "Connect-ExchangeOnline (interactive) uspesne." "OK"
        }
        catch {
            Write-Log "Interaktivne pripojenie neuspesne: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
}
else {
    try {
        Write-Log "Pouzijem interaktivne pripojenie Connect-ExchangeOnline..." "INFO"
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        Write-Log "Connect-ExchangeOnline (interactive) uspesne." "OK"
    }
    catch {
        Write-Log "Interaktivne pripojenie neuspesne: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Now collect mailboxes
try {
    Write-Log "Ziskavam zoznam mailboxov (Get-Mailbox -ResultSize Unlimited)..." "INFO"
    $mailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Pocet mailboxov: $($mailboxes.Count)" "OK"
}
catch {
    Write-Log "Chyba pri ziskavani mailboxov: $($_.Exception.Message)" "ERROR"
    throw
}

# Prepare output array
$results = @()
$i = 0

foreach ($mb in $mailboxes) {
    $i++
    if ($i % 50 -eq 0) {
        Write-Log "Spracovanych $i z $($mailboxes.Count) mailboxov..." "INFO"
    }

    # Determine mailbox type
    $type = $mb.RecipientTypeDetails
    if ($type -match 'Shared') { $mbType = 'Shared' } else { $mbType = 'User' }

    # Get statistics - robustne s retry mechanizmom
    $stats = $null
    $attempt = 0
    $maxAttempts = 3
    $success = $false

    while (-not $success -and $attempt -lt $maxAttempts) {
        $attempt++
        try {
            $stats = Get-MailboxStatistics -Identity $mb.UserPrincipalName -ErrorAction Stop
            $success = $true
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Log "Nepodarilo sa ziskat stats pre $($mb.DisplayName) ($($mb.UserPrincipalName)) - pokus $attempt/$maxAttempts $errMsg" "WARNING"
            # Handle nejednoznacnost identity
            if ($errMsg -match "isn't unique") {
                try {
                    Write-Log "Pouzivam PrimarySmtpAddress namiesto DisplayName..." "INFO"
#                    $stats = Get-MailboxStatistics -Identity $mb.PrimarySmtpAddress -ErrorAction Stop
                    $stats = Get-MailboxStatistics -Identity $mailbox.UserPrincipalName -ErrorAction Stop
                    $success = $true
                }
                catch {
                    Write-Log "Fallback PrimarySmtpAddress zlyhal: $($_.Exception.Message)" "WARNING"
                }
            }
            elseif ($errMsg -match "server side error") {
                Start-Sleep -Seconds (5 * $attempt)
            }
            else {
                Start-Sleep -Seconds 2
            }
        }
    }

    if (-not $success) {
        Write-Log "Trvale zlyhanie pri nacitani statistik pre $($mb.DisplayName)" "ERROR"
    }

    # Parse statistics
    $totalSizeGB = $null
    $totalSizeMB = 0
    $itemCount = 0
    $lastLogon = $null

    if ($stats) {
        try { $itemCount = $stats.ItemCount } catch { $itemCount = 0 }
        try { $lastLogon = $stats.LastLogonTime } catch { $lastLogon = $null }

        # Convert TotalItemSize na bajty
        $sizeBytes = 0
        if ($stats.TotalItemSize -is [string]) {
            if ($stats.TotalItemSize -match '\(([\d,]+)\s*bytes\)') {
                $num = $matches[1] -replace ',', ''
                [long]$sizeBytes = [long]$num
            }
            elseif ($stats.TotalItemSize -match '([\d\.]+)\s*(GB|MB|KB)') {
                $val = [double]$matches[1]
                $unit = $matches[2]
                switch ($unit) {
                    'GB' { $sizeBytes = [long]($val * 1GB) }
                    'MB' { $sizeBytes = [long]($val * 1MB) }
                    'KB' { $sizeBytes = [long]($val * 1KB) }
                }
            }
        }
        elseif ($stats.TotalItemSize -is [object] -and $stats.TotalItemSize.Value) {
            try { $sizeBytes = [long]$stats.TotalItemSize.Value.ToBytes() } catch {}
        }

        if ($sizeBytes -gt 0) {
            $totalSizeMB = [math]::Round($sizeBytes / 1MB, 2)
            $totalSizeGB = [math]::Round($sizeBytes / 1GB, 2)
        }
    }

    # Quotas
    $prohibitSendQuota = $mb.ProhibitSendQuota -as [string]
    if ($prohibitSendQuota) { $prohibitSendQuota = $prohibitSendQuota.Trim() }

    # Build result object
    $obj = [PSCustomObject]@{
        DisplayName          = $mb.DisplayName
        PrimarySmtpAddress   = $mb.PrimarySmtpAddress.ToString()
        MailboxType          = $mbType
        RecipientTypeDetails = $mb.RecipientTypeDetails
        TotalItemSize_GB     = $totalSizeGB
        TotalItemSize_MB     = $totalSizeMB
        ItemCount            = $itemCount
        ProhibitSendQuota    = $prohibitSendQuota
        LastLogonTime        = if ($lastLogon) { $lastLogon.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        Database             = $mb.Database
        Alias                = $mb.Alias
    }

    $results += $obj
}

Write-Log "Spracovane vsetky mailboxy: $($results.Count) zaznamov" "OK"

# Export to Excel (single sheet with MailboxType)
try {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $file = Join-Path $ExportPath "MailboxUsage_Real_$timestamp.xlsx"
    if (-not $TestMode) {
        Write-Log "Exportujem do Excelu: $file" "INFO"
        $results | Sort-Object -Property MailboxType, PrimarySmtpAddress | Export-Excel -Path $file -WorksheetName "Mailboxes" -AutoSize -AutoFilter -BoldTopRow
        Write-Log "Export ulozeny: $file" "OK"
    }
    else {
        Write-Log "TestMode - preskakujem export do Excelu. Ukazka prvych 5 záznamov:" "INFO"
        $results | Select-Object -First 5 | Format-Table | Out-String | ForEach-Object { Write-Log $_ "INFO" }
    }
}
catch {
    Write-Log "Chyba pri exporte do Excelu: $($_.Exception.Message)" "ERROR"
    throw
}

# Disconnect
try {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}
catch {}

Write-Log "Skript dokonceny." "OK"
