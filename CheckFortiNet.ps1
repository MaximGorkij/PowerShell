# FortiClient VPN Log Analyzer - Vylepsena kontrola profilov
# Uklada výsledky do: D:\findrik\Logs

param(
    [string]$OutputPath = "D:\findrik\Logs"
)

# Kontrola a vytvorenie výstupného adresára
if (-not (Test-Path $OutputPath)) {
    try {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-Host "Vytvoril som výstupný adresár: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Chyba pri vytváraní adresára $OutputPath : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Používam desktop ako náhradnú cestu" -ForegroundColor Yellow
        $OutputPath = "$env:USERPROFILE\Desktop"
    }
}

$ErrorActionPreference = "Continue"

# Cesty k logom
$logPaths = @(
    "$env:ProgramFiles\Fortinet\FortiClient\logs",
    "$env:ProgramFiles\Fortinet\FortiClient\Logs",
    "$env:ProgramData\Fortinet\FortiClient\logs",
    "$env:LocalAppData\Fortinet\FortiClient\logs"
)

# Vzory pre chyby
$patterns = @(
    "ChildSa",
    "FAILED",
    "error",
    "connection name is empty",
    "timeout",
    "authentication failed",
    "certificate",
    "tunnel",
    "disconnected",
    "connection lost"
)

function Get-LogFiles {
    param([string[]]$Paths)
    
    $logFiles = @()
    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Write-Host "Prehľadávam cestu: $path" -ForegroundColor Cyan
            try {
                $files = Get-ChildItem -Path $path -Recurse -Include *.log, *.txt -ErrorAction Stop
                $logFiles += $files
                Write-Host "  Našiel som $($files.Count) súborov" -ForegroundColor Green
            }
            catch {
                Write-Host "  Chyba pri čítaní: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  Cesta neexistuje: $path" -ForegroundColor Yellow
        }
    }
    return $logFiles
}

function Format-LogLine {
    param([string]$Line)
    
    if ([string]::IsNullOrEmpty($Line)) {
        return ""
    }
    
    $trimmedLine = $Line.Trim() -replace '\s+', ' '
    
    if ($trimmedLine.Length -gt 100) {
        return $trimmedLine.Substring(0, 100) + "..."
    }
    else {
        return $trimmedLine
    }
}

function Find-ErrorsInLogs {
    param($LogFiles, $Patterns)
    
    $results = @()
    $totalFiles = $LogFiles.Count
    $currentFile = 0
    
    foreach ($file in $LogFiles) {
        $currentFile++
        if ($totalFiles -gt 0) {
            Write-Progress -Activity "Analyzujem log súbory" -Status "Spracovávam: $($file.Name)" -PercentComplete (($currentFile / $totalFiles) * 100)
        }
        
        try {
            foreach ($pattern in $Patterns) {
                $matches = Select-String -Path $file.FullName -Pattern $pattern -CaseSensitive:$false -ErrorAction Stop
                foreach ($match in $matches) {
                    $formattedLine = Format-LogLine -Line $match.Line
                    
                    $results += [PSCustomObject]@{
                        Čas    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        Súbor  = $file.FullName
                        Riadok = $formattedLine
                        Číslo  = $match.LineNumber
                        Vzor   = $pattern
                    }
                }
            }
        }
        catch {
            Write-Host "Chyba pri čítaní súboru $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Progress -Activity "Analyzujem log súbory" -Completed
    return $results
}

function Test-VPNProfile {
    $profilePaths = @(
        "$env:ProgramData\Fortinet\FortiClient",
        "$env:ProgramFiles\Fortinet\FortiClient",
        "$env:LocalAppData\Fortinet\FortiClient",
        "$env:APPDATA\Fortinet\FortiClient"
    )

    $profileInfo = @{
        Nájdené      = $false
        Platné       = $false
        Cesta        = ""
        PočetSúborov = 0
        Detaily      = @()
    }

    foreach ($path in $profilePaths) {
        if (Test-Path $path) {
            try {
                # Hľadáme všetky konfiguračné súbory
                $configFiles = Get-ChildItem -Path $path -Include *.xml, *.conf, *.cfg, *.ini -Recurse -ErrorAction Stop
                $profileInfo.PočetSúborov = $configFiles.Count
                
                if ($configFiles.Count -gt 0) {
                    $profileInfo.Nájdené = $true
                    $profileInfo.Cesta = $path
                    
                    foreach ($file in $configFiles) {
                        try {
                            $content = Get-Content $file.FullName -Raw -ErrorAction Stop
                            $fileInfo = @{
                                Súbor   = $file.Name
                                Cesta   = $file.FullName
                                Veľkosť = "$([math]::Round($file.Length/1024, 2)) KB"
                                Typ     = $file.Extension
                            }
                            
                            # Rozšírené vzory pre VPN profily
                            $vpnPatterns = @(
                                "connection_name", "vpn_profile", "remote_gateway", "server_addr",
                                "server", "host", "gateway", "vpntunnel", "sslvpn", "fortigate",
                                "username", "password", "certificate", "auth", "ipsec"
                            )
                            
                            $foundPatterns = @()
                            foreach ($vpnPattern in $vpnPatterns) {
                                if ($content -match $vpnPattern) {
                                    $foundPatterns += $vpnPattern
                                }
                            }
                            
                            $fileInfo.NájdenéVzory = $foundPatterns -join ", "
                            $fileInfo.JeVPN = ($foundPatterns.Count -gt 2)  # Aspoň 3 vzory = pravdepodobne VPN profil
                            
                            if ($fileInfo.JeVPN) {
                                $profileInfo.Platné = $true
                            }
                            
                            $profileInfo.Detaily += $fileInfo
                            
                        }
                        catch {
                            $profileInfo.Detaily += @{
                                Súbor = $file.Name
                                Cesta = $file.FullName
                                Chyba = $_.Exception.Message
                                JeVPN = $false
                            }
                        }
                    }
                }
            }
            catch {
                Write-Host "Chyba pri hľadaní profilov v: $path" -ForegroundColor Red
            }
        }
    }
    return $profileInfo
}

function Show-ProfileDetails {
    param($ProfileInfo)
    
    Write-Host "`nDETAILNÁ ANALÝZA PROFILOV:" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    foreach ($detail in $ProfileInfo.Detaily) {
        Write-Host "Súbor: $($detail.Súbor)" -ForegroundColor White
        Write-Host "  Cesta: $($detail.Cesta)" -ForegroundColor Gray
        Write-Host "  Veľkosť: $($detail.Veľkosť)" -ForegroundColor Gray
        Write-Host "  Typ: $($detail.Typ)" -ForegroundColor Gray
        
        if ($detail.Chyba) {
            Write-Host "  Stav: CHYBA - $($detail.Chyba)" -ForegroundColor Red
        }
        elseif ($detail.JeVPN) {
            Write-Host "  Stav: VPN PROFIL" -ForegroundColor Green
            Write-Host "  Nájdené vzory: $($detail.NájdenéVzory)" -ForegroundColor Green
        }
        else {
            Write-Host "  Stav: Iný konfiguračný súbor" -ForegroundColor Yellow
            if ($detail.NájdenéVzory) {
                Write-Host "  Nájdené vzory: $($detail.NájdenéVzory)" -ForegroundColor Yellow
            }
        }
        Write-Host ""
    }
}

# HLAVNÝ PROGRAM
Write-Host "=== FortiClient VPN Log Analyzer ===" -ForegroundColor Magenta
Write-Host "Výstupný adresár: $OutputPath" -ForegroundColor Cyan
Write-Host "Spustenie: $(Get-Date)" -ForegroundColor Gray

# 1. Hľadanie log súborov
Write-Host "`n1. HĽADANIE LOG SÚBOROV..." -ForegroundColor Yellow
$logFiles = Get-LogFiles -Paths $logPaths

if ($logFiles.Count -gt 0) {
    # 2. Analýza chýb
    Write-Host "`n2. ANALÝZA CHÝB V LOGOCH..." -ForegroundColor Yellow
    $results = Find-ErrorsInLogs -LogFiles $logFiles -Patterns $patterns
}
else {
    Write-Host "Neboli nájdené žiadne log súbory!" -ForegroundColor Yellow
    $results = @()
}

# 3. Detailná kontrola VPN profilu
Write-Host "`n3. KONTROLA VPN PROFILU..." -ForegroundColor Yellow
$profileInfo = Test-VPNProfile

# 4. Výstupy
Write-Host "`n4. VÝSTUPY A VÝSLEDKY" -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if ($results.Count -gt 0) {
    $outFile = Join-Path $OutputPath "FortiVPN_LogReport_$timestamp.csv"
    $results | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "`nNašlo sa $($results.Count) chýb v logoch:" -ForegroundColor Red
    
    $groupedResults = $results | Group-Object -Property Vzor
    foreach ($group in $groupedResults) {
        Write-Host "  $($group.Name): $($group.Count) výskytov" -ForegroundColor Yellow
    }
    
    Write-Host "`nVýsledky boli exportované do: $outFile" -ForegroundColor Green
    
    # Vytvorenie súhrnného reportu
    $summaryFile = Join-Path $OutputPath "FortiVPN_Summary_$timestamp.txt"
    $summary = @"
FortiClient VPN Analyzer - Súhrnný report
Vygenerované: $(Get-Date)

VŠEOBECNÉ INFORMÁCIE:
- Spustené na: $env:COMPUTERNAME
- Používateľ: $env:USERNAME
- Výstupný adresár: $OutputPath

VÝSLEDKY ANALÝZY LOGOV:
- Prehľadávaných súborov: $($logFiles.Count)
- Nájdených chýb: $($results.Count)
- Hľadaných vzorov: $($patterns.Count)

VPN PROFIL:
- Profil nájdený: $(if ($profileInfo.Nájdené) {'ÁNO'} else {'NIE'})
- Hlavná cesta: $($profileInfo.Cesta)
- Počet súborov: $($profileInfo.PočetSúborov)
- Profil platný: $(if ($profileInfo.Platné) {'ÁNO'} else {'NIE'})

NAJČASTEJŠIE CHYBY:
$($groupedResults | ForEach-Object { "  - $($_.Name): $($_.Count) výskytov" } | Out-String)
"@
    
    $summary | Out-File -FilePath $summaryFile -Encoding UTF8
    Write-Host "Súhrnný report vytvorený: $summaryFile" -ForegroundColor Cyan
    
}
else {
    Write-Host "`nNenašli sa žiadne chyby v logoch!" -ForegroundColor Green
}

# Zobrazenie detailov o profile
Write-Host "`nZÁKLADNÉ INFORMÁCIE O PROFILOCH:" -ForegroundColor Cyan
Write-Host "  Profil nájdený: $(if ($profileInfo.Nájdené) {'ÁNO'} else {'NIE'})" -ForegroundColor $(if ($profileInfo.Nájdené) { 'Green' } else { 'Red' })
Write-Host "  Hlavná cesta: $($profileInfo.Cesta)" -ForegroundColor Gray
Write-Host "  Počet súborov: $($profileInfo.PočetSúborov)" -ForegroundColor Gray
Write-Host "  Profil platný: $(if ($profileInfo.Platné) {'ÁNO'} else {'NIE'})" -ForegroundColor $(if ($profileInfo.Platné) { 'Green' } else { 'Yellow' })

# Zobrazenie detailnej analýzy
if ($profileInfo.Nájdené) {
    Show-ProfileDetails -ProfileInfo $profileInfo
}

# Manuálna kontrola
Write-Host "`nMANUÁLNA KONTROLA:" -ForegroundColor Magenta
Write-Host "1. Otvorte FortiClient a skontrolujte, či máte nastavené VPN pripojenie" -ForegroundColor White
Write-Host "2. Skúste sa prihlásiť do VPN a pozorovať chybové hlásenia" -ForegroundColor White
Write-Host "3. Skontrolujte nastavenia siete a firewall" -ForegroundColor White

Write-Host "`nDokončené: $(Get-Date)" -ForegroundColor Gray
Write-Host "Všetky súbory boli uložené do: $OutputPath" -ForegroundColor Green