<#
.SYNOPSIS
    Kontrola neúplných riadkov v Excel súboroch knihy jázd za minulý mesiac
.DESCRIPTION
    Skontroluje všetky ŠPZ v "Kniha jazd" za minulý mesiac.
    Hľadá riadky, kde chýbajú údaje alebo je v bunkách iba znak "-" namiesto textu.
.NOTES
    Verzia: 4.5 (Fix Header Row + Debug Columns)
    Autor: Automatický report
    Požadované moduly: ImportExcel, Microsoft.Graph.Authentication, Microsoft.Graph.Sites, Microsoft.Graph.Users.Actions
    Dátum úpravy: 02.02.2026
    Logovanie: C:\TaurisIT\Log\KnihaJazd
#>

[CmdletBinding()]
param(
    [switch]$ForceCheckModules,
    [string]$ConfigFile = ".env",
    [string]$LogLevel = "INFO" 
)

# ===== KONŠTANTY A CESTY =====
$script:LogPath = "C:\TaurisIT\Log\KnihaJazd"
$script:LogFile = Join-Path $script:LogPath ("KnihaJazd_" + (Get-Date -Format 'yyyyMMdd') + ".log")
$script:TempPath = Join-Path $env:TEMP ("KnihaJazd_Temp_" + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))

# ===== ENUM PRE LOGOVANIE =====
enum LogLevel { DEBUG = 1; INFO = 2; WARNING = 3; ERROR = 4 }

# ===== KONFIGURAČNÁ TRIEDA =====
class KnihaJazdConfiguration {
    [string]$ClientId
    [string]$TenantId
    [string]$ClientSecret
    [string]$SiteUrl
    [string[]]$EmailRecipients
    [string]$EmailFrom
    [string]$EmailSubject
    # OPRAVA: Podľa screenshotu je hlavička na riadku 12
    [int]$StartRow = 12
}

# ===== SPÄTNÉ VOLANIE PRE LOGOVANIE =====
$script:LogCallback = {
    param([string]$Message, [LogLevel]$Level = [LogLevel]::INFO)
    if ($Level.Value__ -lt ([LogLevel]::$LogLevel).Value__) { return }
    
    if (-not (Test-Path $script:LogPath)) {
        try { New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null }
        catch { Write-Warning "Nepodarilo sa vytvoriť log priečinok: $_"; return }
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "$timestamp [$($Level.ToString())] $Message"
    
    try {
        Add-Content -Path $script:LogFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch { Write-Warning "Nepodarilo sa zapísať do logu: $_" }
    
    $color = switch ($Level) { 
        "WARNING" { "Yellow" } 
        "ERROR" { "Red" } 
        "DEBUG" { "Magenta" }
        Default { "Cyan" } 
    }
    Write-Host "[$($timestamp.Substring(11))] [$($Level.ToString().PadRight(9))] $Message" -ForegroundColor $color
}

# ===== FUNKCIA: Zápis logu =====
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [LogLevel]$Level = [LogLevel]::INFO
    )
    
    & $script:LogCallback -Message $Message -Level $Level
}

# ===== FUNKCIA: Inicializácia prostredia =====
function Initialize-KnihaJazdEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )
    
    $config = [KnihaJazdConfiguration]::new()
    $envFilePath = if ($ConfigPath) { $ConfigPath } else { Join-Path $PSScriptRoot ".env" }
    
    if (-not (Test-Path $envFilePath)) {
        Write-Log "Konfiguračný súbor neexistuje: $envFilePath" -Level ERROR
        return $null
    }
    
    try {
        Get-Content $envFilePath | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
            $key, $val = $_.Split('=', 2).Trim()
            $val = $val -replace '^["'']|["'']$', ''
            
            switch ($key) {
                "CLIENTID" { $config.ClientId = $val }
                "TENANTID" { $config.TenantId = $val }
                "CLIENTSECRET" { $config.ClientSecret = $val }
                "SiteUrl" { $config.SiteUrl = $val }
                "EMAIL_RECIPIENTS" { $config.EmailRecipients = ($val -split ',').Trim() }
                "EMAIL_FROM" { $config.EmailFrom = $val }
                "REPORT_EMAIL_SUBJECT" { $config.EmailSubject = $val }
            }
        }
        
        $missingFields = [System.Collections.Generic.List[string]]::new()
        
        if ([string]::IsNullOrEmpty($config.ClientId)) { $missingFields.Add("ClientId") }
        if ([string]::IsNullOrEmpty($config.TenantId)) { $missingFields.Add("TenantId") }
        if ([string]::IsNullOrEmpty($config.ClientSecret)) { $missingFields.Add("ClientSecret") }
        if ([string]::IsNullOrEmpty($config.EmailFrom)) { $missingFields.Add("EmailFrom") }
        if ($null -eq $config.EmailRecipients -or $config.EmailRecipients.Count -eq 0) { $missingFields.Add("EmailRecipients") }
        
        if ($missingFields.Count -gt 0) {
            Write-Log "Chýbajúce konfiguračné polia: $($missingFields -join ', ')" -Level ERROR
            return $null
        }
        
        return $config
    }
    catch {
        Write-Log "Chyba pri načítaní konfigurácie: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

# ===== FUNKCIA: Kontrola a import modulov =====
function Invoke-ModuleCheck {
    [CmdletBinding()]
    param()
    
    $requiredModules = @('ImportExcel', 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Sites', 'Microsoft.Graph.Users.Actions')
    
    $missingModules = [System.Collections.Generic.List[string]]::new()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) {
            $missingModules.Add($module)
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log "Chýbajúce moduly: $($missingModules -join ', ')" -Level ERROR
        return $false
    }
    
    return $true
}

# ===== FUNKCIA: Pripojenie k Microsoft Graph =====
function Connect-GraphClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [KnihaJazdConfiguration]$Configuration
    )
    
    try {
        Write-Log "Pripájanie k Microsoft Graph..."
        
        $secSecret = ConvertTo-SecureString $Configuration.ClientSecret -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new($Configuration.ClientId, $secSecret)
        
        $null = Connect-MgGraph -TenantId $Configuration.TenantId -Credential $credential -NoWelcome -ErrorAction Stop
        
        $currentContext = Get-MgContext
        if ($null -eq $currentContext) {
            throw "Nepodarilo sa overiť pripojenie k Microsoft Graph"
        }
        
        Write-Log "Úspešne pripojené k Microsoft Graph (Tenant: $($currentContext.TenantId))"
        return $true
    }
    catch {
        Write-Log "Chyba pri pripájaní k Microsoft Graph: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# ===== FUNKCIA: Získanie mesiaca a roku =====
function Get-TargetPeriod {
    [CmdletBinding()]
    param()
    
    $targetDate = (Get-Date).AddMonths(-1)
    $culture = [System.Globalization.CultureInfo]::new("sk-SK")
    
    return @{
        Year       = $targetDate.Year.ToString()
        MonthNum   = "{0:D2}" -f $targetDate.Month
        MonthName  = $culture.DateTimeFormat.GetMonthName($targetDate.Month)
        MonthIndex = $targetDate.Month
    }
}

# ===== FUNKCIA: Vyhľadanie priečinka mesiaca =====
function Find-MonthFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$MonthFolders,
        [Parameter(Mandatory = $true)]
        [string]$MonthNum,
        [Parameter(Mandatory = $true)]
        [string]$MonthName
    )
    
    $targetFolder = $MonthFolders | Where-Object {
        $_.Name -eq $MonthNum -or 
        $_.Name -eq [int]$MonthNum -or 
        $_.Name -like "*$MonthName*" -or
        $_.Name -like "*$($MonthNum.TrimStart('0'))*"
    } | Select-Object -First 1
    
    return $targetFolder
}

# ===== FUNKCIA: Stiahnutie a spracovanie Excel súboru =====
function Invoke-ExcelProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveId,
        [Parameter(Mandatory = $true)]
        [string]$FolderId,
        [Parameter(Mandatory = $true)]
        [string]$Spz,
        [Parameter(Mandatory = $true)]
        [int]$StartRow
    )
    
    $result = @{
        Success   = $false
        ExcelFile = $null
        Errors    = [System.Collections.Generic.List[string]]::new()
        Issues    = @()
    }
    
    $localFile = Join-Path $script:TempPath "$Spz.xlsx"
    
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        $files = Get-MgDriveItemChild -DriveId $DriveId -DriveItemId $FolderId -ErrorAction Stop
        
        $excel = $files | Where-Object { $_.Name -like "*.xlsx" -and $_.Name -notlike "*~*" } | Select-Object -First 1
        
        if (-not $excel) {
            $result.Errors.Add("Excel súbor pre tento mesiac nebol nájdený")
            return $result
        }
        
        $result.ExcelFile = $excel.Name
        Write-Log "Spracúvam: $($excel.Name)"
        
        $downloadUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$($excel.Id)/content"
        Invoke-MgGraphRequest -Method GET -Uri $downloadUri -OutputFilePath $localFile -ErrorAction Stop
        
        # Import dát
        $data = Import-Excel -Path $localFile -StartRow $StartRow -ErrorAction Stop
        
        # DEBUG: Výpis nájdených stĺpcov (pre kontrolu, či sme trafili StartRow)
        if ($data.Count -gt 0) {
            $foundColumns = $data[0].PSObject.Properties.Name -join ", "
            Write-Log "Nájdené stĺpce v Exceli: $foundColumns" -Level DEBUG
        }

        $currentRow = $StartRow + 1
        
        # Názvy stĺpcov musia PRESNE sedieť s tým, čo vidí Import-Excel
        $checkColumns = @('Typ jazdy', 'Vodič', 'Účel jazdy')
        
        foreach ($row in $data) {
            $currentRow++
            
            # Oprava dátumu
            if ($row.Dátum -match '^\d+(\.\d+)?$') {
                try { $row.Dátum = [DateTime]::FromOADate([double]$row.Dátum) } catch {}
            }

            # Preskočíme riadky, kde nie je dátum (alebo je to hlavička z riadku 13)
            # Riadok 13 v Exceli obsahuje 'Čas do', takže ak je v Dátum niečo iné ako dátum, preskočíme
            if ([string]::IsNullOrWhiteSpace($row.Dátum) -or $row.Dátum -match "Čas do") { continue }
            
            $missing = @()
            
            foreach ($colName in $checkColumns) {
                # Ak stĺpec neexistuje (napr. zlý StartRow), vráti $null
                $val = $row.$colName
                
                # Kontrola: Je prázdna? ALEBO Je to pomlčka?
                if ([string]::IsNullOrWhiteSpace($val) -or "$val".Trim() -eq '-') {
                    $missing += "$colName (nevyplnené alebo '-')"
                }
            }
            
            if ($missing.Count -gt 0) {
                $result.Issues += [PSCustomObject]@{
                    ŠPZ      = $Spz
                    Súbor    = $excel.Name
                    Riadok   = $currentRow
                    Problém  = "Neúplné dáta"
                    Detaily  = ($missing -join ", ")
                    Priorita = "STREDNÁ"
                }
            }
        }
        
        $result.Success = $true
    }
    catch {
        $result.Errors.Add($_.Exception.Message)
        Write-Log "Chyba pri spracovaní ŠPZ $($Spz): $($_.Exception.Message)" -Level WARNING
    }
    finally {
        $ProgressPreference = $oldProgress
        if (Test-Path $localFile) {
            Remove-Item $localFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    return $result
}

# ===== FUNKCIA: Odoslanie email reportu =====
function Send-EmailReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ReportData,
        [Parameter(Mandatory = $true)]
        [string]$Period,
        [Parameter(Mandatory = $true)]
        [KnihaJazdConfiguration]$Configuration
    )
    
    try {
        $rows = $ReportData | ForEach-Object {
            $color = if ($_.Priorita -eq "VYSOKÁ") { "#f8d7da" } else { "#fff3cd" }
            @"
            <tr style='background-color: $color;'>
                <td style='border:1px solid #ddd;padding:5px;'>$($_.ŠPZ)</td>
                <td style='border:1px solid #ddd;padding:5px;'>$($_.Súbor)</td>
                <td style='border:1px solid #ddd;padding:5px;'>$($_.Riadok)</td>
                <td style='border:1px solid #ddd;padding:5px;'>$($_.Problém)</td>
                <td style='border:1px solid #ddd;padding:5px;'>$($_.Detaily)</td>
                <td style='border:1px solid #ddd;padding:5px;'>$($_.Priorita)</td>
            </tr>
"@
        }
        
        $rowsHtml = $rows -join ""

        $body = @"
<html>
<body style='font-family: Calibri, sans-serif;'>
<h3>Mesačný report nedostatkov v knihe jázd ($Period)</h3>
<table style='border-collapse:collapse;width:100%;'>
<thead>
<tr style='background:#0078D4;color:white;'>
    <th>ŠPZ</th><th>Súbor</th><th>Riadok</th><th>Problém</th><th>Detaily</th><th>Priorita</th>
</tr>
</thead>
<tbody>
$rowsHtml
</tbody>
</table>
<p style='margin-top:20px;font-size:12px;color:#666;'>Report vygenerovaný: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')</p>
</body>
</html>
"@
        
        $toRecipients = $Configuration.EmailRecipients | ForEach-Object {
            @{ EmailAddress = @{ Address = $_.Trim() } }
        }
        
        $mailParams = @{
            Message = @{
                Subject      = "$($Configuration.EmailSubject) - $Period"
                Body         = @{ Content = $body; ContentType = "HTML" }
                ToRecipients = $toRecipients
            }
        }
        
        Send-MgUserMail -UserId $Configuration.EmailFrom -Message $mailParams.Message -ErrorAction Stop
        Write-Log "Email report úspešne odoslaný príjemcom: $($Configuration.EmailRecipients -join ', ')"
    }
    catch {
        Write-Log "Chyba pri odosielaní emailu: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# ===== HLAVNÁ FUNKCIA: Kontrola knihy jázd =====
function Invoke-KnihaJazdCheck {
    [CmdletBinding()]
    param(
        [switch]$ForceModuleCheck
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:config = $null
    $graphConnected = $false
    
    try {
        if ($ForceModuleCheck -or -not (Invoke-ModuleCheck)) {
            return
        }
        
        $fullConfigPath = Join-Path $PSScriptRoot $ConfigFile
        $script:config = Initialize-KnihaJazdEnvironment -ConfigPath $fullConfigPath

        if ($null -eq $script:config) {
            Write-Log "Konfigurácia nebola načítaná" -Level ERROR
            return
        }
        
        if (-not (Test-Path $script:TempPath)) {
            New-Item -Path $script:TempPath -ItemType Directory -Force | Out-Null
        }
        
        $graphConnected = Connect-GraphClient -Configuration $script:config
        if (-not $graphConnected) {
            return
        }
        
        $period = Get-TargetPeriod
        Write-Log "Kontrolujem obdobie: $($period.MonthName) $($period.Year)"
        
        $site = Get-MgSite -SiteId $script:config.SiteUrl -ErrorAction Stop
        $drive = Get-MgSiteDrive -SiteId $site.Id | Where-Object { $_.DriveType -eq "documentLibrary" } | Select-Object -First 1
        
        if ($null -eq $drive) {
            Write-Log "Drive sa nenašiel" -Level ERROR
            return
        }
        
        $driveId = $drive.Id
        $baseFolder = Get-MgDriveItem -DriveId $driveId -DriveItemId "root:/Kniha jazd" -ErrorAction Stop
        $spzFolders = Get-MgDriveItemChild -DriveId $driveId -DriveItemId $baseFolder.Id -ErrorAction Stop
        
        $allReportData = @()
        $allErrors = @()
        $processedCount = 0
        $errorCount = 0
        
        foreach ($folder in $spzFolders) {
            $spz = $folder.Name
            Write-Log "--- Vozidlo: $($spz) ---"
            
            try {
                $yearRelPath = "Kniha jazd/$spz/$($period.Year)"
                $yearFolder = Get-MgDriveItem -DriveId $driveId -DriveItemId "root:/$yearRelPath" -ErrorAction Stop
                $monthFolders = Get-MgDriveItemChild -DriveId $driveId -DriveItemId $yearFolder.Id -ErrorAction Stop
                
                $targetMonthFolder = Find-MonthFolder -MonthFolders $monthFolders -MonthNum $period.MonthNum -MonthName $period.MonthName
                
                if ($null -eq $targetMonthFolder) {
                    throw "Priečinok mesiaca $($period.MonthName) sa nenašiel"
                }
                
                $result = Invoke-ExcelProcessing -DriveId $driveId -FolderId $targetMonthFolder.Id -Spz $spz -StartRow $script:config.StartRow
                
                if ($result.Errors.Count -gt 0) {
                    $allErrors += [PSCustomObject]@{
                        ŠPZ      = $spz
                        Súbor    = "Súbor neexistuje"
                        Riadok   = "-"
                        Problém  = "Chyba spracovania"
                        Detaily  = ($result.Errors -join "; ")
                        Priorita = "VYSOKÁ"
                    }
                    $errorCount++
                }
                else {
                    $allReportData += $result.Issues
                    $processedCount++
                }
            }
            catch {
                Write-Log "CHYBA: $($_.Exception.Message)" -Level WARNING
                $allErrors += [PSCustomObject]@{
                    ŠPZ      = $spz
                    Súbor    = "Súbor neexistuje"
                    Riadok   = "-"
                    Problém  = "Chyba spracovania"
                    Detaily  = $_.Exception.Message
                    Priorita = "VYSOKÁ"
                }
                $errorCount++
            }
        }
        
        $finalReportData = $allErrors + $allReportData
        
        Write-Log "Spracované: $processedCount vozidiel, Chyby: $errorCount, Nájdené problémy: $($allReportData.Count)"
        
        if ($finalReportData.Count -gt 0) {
            Send-EmailReport -ReportData $finalReportData -Period "$($period.MonthName) $($period.Year)" -Configuration $script:config
        }
        else {
            Write-Log "Kontrola úspešná, nenašli sa žiadne chyby."
        }
    }
    catch {
        Write-Log "Kritická chyba: $($_.Exception.Message)" -Level ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    }
    finally {
        $stopwatch.Stop()
        Write-Log "Celkový čas vykonania: $($stopwatch.Elapsed.TotalSeconds.ToString('F2')) sekúnd"
        
        if ($graphConnected -and (Get-MgContext)) {
            $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
        }
        
        if (Test-Path $script:TempPath) {
            Remove-Item $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ===== VSTUPNÝ BOD =====
Invoke-KnihaJazdCheck @PSBoundParameters