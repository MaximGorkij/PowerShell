<# 
.SYNOPSIS
    Kontrola neuplnych riadkov v Excel suboroch knihy jazd za minuly mesiac
.DESCRIPTION
    Skontroluje vsetky SPZ v "Kniha jazd" za minuly mesiac, najde neuplne riadky
    (vratane pomlcky v stlpci Typ jazdy) a chybajuce subory. Vysledok posle na email.
.NOTES
    Verzia: 3.13
    Autor: Automaticky report
    Pozadovane moduly: ImportExcel, Microsoft.Graph.Authentication, Microsoft.Graph.Sites, Microsoft.Graph.Users.Actions
    Datum vytvorenia: 26.01.2026
    Logovanie: C:\TaurisIT\Log\KnihaJazd
#>

param(
    [switch]$ForceCheckModules,
    [string]$ConfigFile = ".env",
    [string]$LogLevel = "INFO" 
)

# ===== CESTY A LOGOVANIE =====
$LogPath = "C:\TaurisIT\Log\KnihaJazd"
$LogFile = Join-Path $LogPath ("KnihaJazd_" + (Get-Date -Format 'yyyyMMdd') + ".log")
$TempPath = Join-Path $env:TEMP ("KnihaJazd_Temp_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))

enum LogLevel { DEBUG = 1; INFO = 2; VAROVANIE = 3; CHYBA = 4 }

function Write-Log {
    param([string]$Message, [LogLevel]$Level = [LogLevel]::INFO)
    if ($Level.Value__ -lt ([LogLevel]::$LogLevel).Value__) { return }
    if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -Path $LogFile -Value "$timestamp [$($Level.ToString())] $Message" -Encoding UTF8
    $color = switch ($Level) { "VAROVANIE" { "Yellow" }; "CHYBA" { "Red" }; Default { "Cyan" } }
    Write-Host "[$($timestamp.Substring(11))] [$($Level.ToString().PadRight(9))] $Message" -ForegroundColor $color
}

function Initialize-KnihaJazdEnvironment {
    $envPath = Join-Path $PSScriptRoot $ConfigFile
    if (-not (Test-Path $envPath)) { return $false }
    Get-Content $envPath | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
        $key, $val = $_.Split('=', 2).Trim()
        $val = $val -replace '^["'']|["'']$', ''
        switch ($key) {
            "CLIENTID" { $script:ClientId = $val }
            "TENANTID" { $script:TenantId = $val }
            "CLIENTSECRET" { $script:ClientSecret = $val }
            "SiteUrl" { $script:SiteUrl = $val }
            "EMAIL_RECIPIENTS" { $script:EmailRecipients = $val }
            "EMAIL_FROM" { $script:EmailFrom = $val }
            "REPORT_EMAIL_SUBJECT" { $script:EmailSubject = $val }
        }
    }
    $script:StartRow = 14 
    return $true
}

function Invoke-KnihaJazdCheck {
    if (-not (Initialize-KnihaJazdEnvironment)) { Write-Log "Chyba inicializacie .env" -Level CHYBA; return }
    
    try {
        Write-Log "Pripajanie k Microsoft Graph..."
        $secSecret = ConvertTo-SecureString $script:ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($script:ClientId, $secSecret)
        Connect-MgGraph -TenantId $script:TenantId -Credential $credential -NoWelcome -ErrorAction Stop

        if (-not (Test-Path $TempPath)) { New-Item -Path $TempPath -ItemType Directory -Force | Out-Null }
        
        $TargetDate = (Get-Date).AddMonths(-1)
        $Year = $TargetDate.Year.ToString()
        $MonthNum = "{0:D2}" -f $TargetDate.Month
        $MonthName = (Get-Culture "sk-SK").DateTimeFormat.GetMonthName($TargetDate.Month)

        $site = Get-MgSite -SiteId $script:SiteUrl -ErrorAction Stop
        $drive = Get-MgSiteDrive -SiteId $site.Id | Where-Object { $_.DriveType -eq "documentLibrary" } | Select-Object -First 1
        $driveId = $drive.Id

        $baseFolder = Get-MgDriveItem -DriveId $driveId -DriveItemId "root:/Kniha jazd" -ErrorAction Stop
        $spzFolders = Get-MgDriveItemChild -DriveId $driveId -DriveItemId $baseFolder.Id -ErrorAction Stop

        $reportData = @()
        foreach ($f in $spzFolders) {
            $folderName = $f.Name
            Write-Log "--- Vozidlo: $folderName ---"
            
            try {
                $yearRelPath = "Kniha jazd/$folderName/$Year"
                $yearFolder = Get-MgDriveItem -DriveId $driveId -DriveItemId "root:/$yearRelPath" -ErrorAction Stop
                $monthFolders = Get-MgDriveItemChild -DriveId $driveId -DriveItemId $yearFolder.Id -ErrorAction Stop
                
                $targetMonthFolder = $monthFolders | Where-Object { 
                    $_.Name -eq $MonthNum -or $_.Name -eq [int]$MonthNum -or $_.Name -like "*$MonthName*" 
                } | Select-Object -First 1

                if (-not $targetMonthFolder) { throw "Priečinok mesiaca nenájdený." }

                $files = Get-MgDriveItemChild -DriveId $driveId -DriveItemId $($targetMonthFolder.Id) -ErrorAction Stop
                $excel = $files | Where-Object { $_.Name -like "*.xlsx" } | Select-Object -First 1
                
                if ($excel) {
                    Write-Log "Sťahujem: $($excel.Name)"
                    $localFile = Join-Path $TempPath "$folderName.xlsx"
                    
                    # FIX: Eliminacia chyby PercentComplete vypnutim progresu
                    $oldProgress = $ProgressPreference
                    $ProgressPreference = 'SilentlyContinue'
                    Get-MgDriveItemContent -DriveId $driveId -DriveItemId $excel.Id -OutFile $localFile -ErrorAction Stop
                    $ProgressPreference = $oldProgress
                    
                    $data = Import-Excel -Path $localFile -StartRow $script:StartRow
                    $currRow = $script:StartRow + 1
                    
                    foreach ($row in $data) {
                        $currRow++
                        
                        # Preskoč riadok ak je úplne prázdny (žiadny dátum)
                        if ([string]::IsNullOrWhiteSpace($row.'Dátum')) { continue }

                        $missing = @()
                        
                        # KONTROLA: Pomlčka v stĺpci 'Typ jazdy'
                        if ($row.'Typ jazdy' -eq '-') { 
                            $missing += "Neplatný Typ jazdy (-)" 
                        }
                        
                        if ([string]::IsNullOrWhiteSpace($row.'Vodič')) { $missing += "Chýba Vodič" }
                        if ([string]::IsNullOrWhiteSpace($row.'Účel jazdy')) { $missing += "Chýba Účel jazdy" }

                        if ($missing.Count -gt 0) {
                            $reportData += [PSCustomObject]@{ "ŠPZ" = $folderName; "Súbor" = $excel.Name; "Riadok" = $currRow; "Problém" = "Neúplné dáta"; "Detaily" = ("Problém: " + ($missing -join ", ")); "Priorita" = "STREDNÁ" }
                        }
                    }
                    Remove-Item $localFile -Force
                }
                else { throw "Excel nenájdený." }
            }
            catch {
                Write-Log "CHYBA: $($_.Exception.Message)" -Level VAROVANIE
                $reportData += [PSCustomObject]@{ "ŠPZ" = $folderName; "Súbor" = "CHÝBA"; "Riadok" = "-"; "Problém" = "Chyba spracovania"; "Detaily" = $_.Exception.Message; "Priorita" = "VYSOKÁ" }
            }
        }
        
        if ($reportData.Count -gt 0) {
            Send-KnihaJazdEmailReport -ReportData $reportData -Period "$MonthName $Year"
        }
        else {
            Write-Log "Kontrola úspešná, nenašli sa žiadne chyby."
        }
    }
    catch { 
        Write-Log "Kritická chyba: $($_.Exception.Message)" -Level CHYBA 
    }
    finally {
        if (Get-MgContext) { Disconnect-MgGraph | Out-Null }
        if (Test-Path $TempPath) { Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Send-KnihaJazdEmailReport {
    param($ReportData, $Period)
    $rows = ""
    foreach ($r in $ReportData) {
        $color = if ($r.Priorita -eq "VYSOKÁ") { "#f8d7da" } else { "#fff3cd" }
        $rows += "<tr style='background-color:$color;'><td style='border:1px solid #ddd;padding:5px;'>$($r.ŠPZ)</td><td style='border:1px solid #ddd;padding:5px;'>$($r.Súbor)</td><td style='border:1px solid #ddd;padding:5px;'>$($r.Riadok)</td><td style='border:1px solid #ddd;padding:5px;'>$($r.Problém)</td><td style='border:1px solid #ddd;padding:5px;'>$($r.Detaily)</td><td style='border:1px solid #ddd;padding:5px;'>$($r.Priorita)</td></tr>"
    }
    $body = "<html><body style='font-family: Calibri, sans-serif;'><h3>Mesačný report nedostatkov v knihe jázd ($Period)</h3><table style='border-collapse:collapse;width:100%;'><thead><tr style='background:#0078D4;color:white;'><th>ŠPZ</th><th>Súbor</th><th>Riadok</th><th>Problém</th><th>Detaily</th><th>Priorita</th></tr></thead><tbody>$rows</tbody></table></body></html>"

    $mailParams = @{
        Message = @{
            Subject      = "$script:EmailSubject - $Period"
            Body         = @{ Content = $body; ContentType = "HTML" }
            ToRecipients = ($script:EmailRecipients.Split(',') | ForEach-Object { @{ EmailAddress = @{ Address = $_.Trim() } } })
        }
    }
    Send-MgUserMail -UserId $script:EmailFrom -Message $mailParams.Message -ErrorAction Stop
    Write-Log "Email report úspešne odoslaný."
}

Invoke-KnihaJazdCheck