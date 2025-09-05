param(
    [string]$LogFolder = "C:\TaurisIT\Log",
    [switch]$TryQuickFix
)

# --- príprava ciest ---
$null = New-Item -ItemType Directory -Path $LogFolder -Force -ErrorAction SilentlyContinue
$TimeTag = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $LogFolder "PasswordPolicy-Diagnostics-$TimeTag.txt"
$SeceditLog = Join-Path $LogFolder "secedit-config.log"
$ExportPath = Join-Path $LogFolder "policy-export-$TimeTag.inf"
$AnalyzeDb = Join-Path $env:windir "security\Database\secanalysis-$TimeTag.sdb"
$AnalyzeLog = Join-Path $LogFolder "secedit-analyze-$TimeTag.log"
$GpResult = Join-Path $LogFolder "gpresult-computer-$TimeTag.txt"

# --- helper: zápis do reportu ---
function Write-Section([string]$Title) { Add-Content $ReportPath "`r`n===== $Title =====`r`n" }
function Write-Line([string]$Text) { Add-Content $ReportPath $Text }

# --- Základné info o systéme ---
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$uac = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")

Write-Section "System info"
Write-Line   "ComputerName : $env:COMPUTERNAME"
Write-Line   "OS           : $($os.Caption) ($($os.Version))"
Write-Line   "User         : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Line   "Elevated     : $uac"
Write-Line   "PartOfDomain : $($cs.PartOfDomain)"
Write-Line   "LogFolder    : $LogFolder"

# --- Export aktuálnej politiky (secedit /export) ---
Write-Section "secedit /export"
try {
    secedit /export /cfg $ExportPath /quiet 2>&1 | Tee-Object -Variable seceditExportOut | Out-Null
    Write-Line "Exported to: $ExportPath"
    if ($seceditExportOut) { Write-Line ($seceditExportOut -join [Environment]::NewLine) }
}
catch {
    Write-Line "ERROR exporting policy: $_"
}

# --- Parsovanie exportu do hashtable ---
$pol = @{}
if (Test-Path $ExportPath) {
    Get-Content $ExportPath | ForEach-Object {
        if ($_ -match "^(?<k>\w+)\s*=\s*(?<v>.+)$") { $pol[$matches.k] = $matches.v.Trim() }
    }
}

# --- net accounts (rýchly pohľad) ---
Write-Section "net accounts"
$netAcc = (net accounts) 2>&1
Write-Line ($netAcc -join [Environment]::NewLine)

# --- gpresult (aplikované GPO) ---
Write-Section "gpresult /SCOPE COMPUTER /V"
try {
    gpresult /SCOPE COMPUTER /V > $GpResult 2>&1
    Write-Line "Full output saved to: $GpResult"
    # do reportu dáme len prvých ~120 riadkov kvôli čitateľnosti
    $preview = Get-Content $GpResult | Select-Object -First 120
    Write-Line ($preview -join [Environment]::NewLine)
}
catch {
    Write-Line "ERROR running gpresult: $_"
}

# --- Tail z existujúceho secedit logu (ak je) ---
Write-Section "Tail of secedit-config.log (last 200 lines)"
if (Test-Path $SeceditLog) {
    Get-Content $SeceditLog -Tail 200 | ForEach-Object { Write-Line $_ }
}
else {
    Write-Line "secedit-config.log nenájdený ($SeceditLog)"
}

# --- ANALÝZA voči očakávaným hodnotám cez /analyze ---
Write-Section "secedit /analyze vs expected"
$TestInf = Join-Path $env:TEMP "PasswordPolicy-Expected.inf"
$expectedContent = @"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordLength = 4
MaximumPasswordAge = 365
PasswordComplexity = 1
PasswordHistorySize = 1
"@
# DÔLEŽITÉ: Unicode encoding, aby zodpovedal hlavičke [Unicode]
Set-Content -Path $TestInf -Value $expectedContent -Encoding Unicode

try {
    secedit /analyze /db $AnalyzeDb /cfg $TestInf /log $AnalyzeLog /quiet 2>&1 | Tee-Object -Variable analyzeOut | Out-Null
    Write-Line "Analyze DB    : $AnalyzeDb"
    Write-Line "Analyze Log   : $AnalyzeLog"
    if ($analyzeOut) { Write-Line ($analyzeOut -join [Environment]::NewLine) }
}
catch {
    Write-Line "ERROR running secedit /analyze: $_"
}

# --- Porovnanie kľúčových hodnôt (export vs. expected) ---
Write-Section "Diff (current vs expected)"
$expected = @{
    'MinimumPasswordLength' = '4'
    'MaximumPasswordAge'    = '365'
    'PasswordComplexity'    = '1'
    'PasswordHistorySize'   = '1'
}
$diff = foreach ($k in $expected.Keys) {
    $cur = if ($pol.ContainsKey($k)) { $pol[$k] } else { '<not-set>' }
    if ($cur -ne $expected[$k]) {
        [pscustomobject]@{ Setting = $k; Expected = $expected[$k]; Current = $cur }
    }
}
if ($diff) {
    $diff | ForEach-Object { Write-Line ("{0}: Expected={1} Current={2}" -f $_.Setting, $_.Expected, $_.Current) }
}
else {
    Write-Line "OK: Exportované hodnoty sa zhodujú s očakávaním."
}

# --- Voliteľný QUICK FIX (bez záruky), typické príčiny Extended error ---
if ($TryQuickFix) {
    Write-Section "QuickFix attempt (reconfigure)"
    try {
        $ConfigDb = Join-Path $env:windir "security\Database\secedit-$TimeTag.sdb"
        $ConfigInf = Join-Path $env:TEMP "PasswordPolicy-Fix-$TimeTag.inf"
        Set-Content -Path $ConfigInf -Value $expectedContent -Encoding Unicode

        # Dôležité: databázu drž v %windir%\security\Database
        $out = secedit /configure /db $ConfigDb /cfg $ConfigInf /log $SeceditLog 2>&1
        Write-Line "secedit /configure output:"
        if ($out) { Write-Line ($out -join [Environment]::NewLine) } else { Write-Line "(no output)" }

        # re-export po pokuse
        secedit /export /cfg $ExportPath /quiet 2>&1 | Out-Null
        Write-Line "Re-exported to: $ExportPath"
    }
    catch {
        Write-Line "QuickFix ERROR: $_"
    }
}

# --- Odporúčania / root cause checklist ---
Write-Section "Recommendations & Common Root Causes"
Write-Line @"
1) INF encoding: ak máš v INF [Unicode] / Unicode=yes, zapisuj súbor s -Encoding Unicode.
2) DB path: používaj databázu v %windir%\security\Database (napr. $env:windir\security\Database\secedit.sdb).
3) Súbežné operácie: počas secedit/gpupdate nemaj otvorenú Local Security Policy (secpol.msc) a nespúšťaj paralelný gpupdate.
4) Práva: spúšťaj ako Administrátor alebo SYSTEM (cez plánovač/Intune). Na členovi domény môžu doménové GPO prepisovať lokálne nastavenia.
5) Obsah INF: iba číselné hodnoty (bez úvodzoviek), sekcia [System Access] a kľúče presne pomenované.
6) X86 vs X64: používaj 64-bit PowerShell, aby sa neriadili cesty/registry redirekciou.
7) Diagnostika: pozri $SeceditLog a gpresult ($GpResult) - hľadaj GPO, ktoré nastavujú Account Policies.
"@

Write-Section "DONE"
Write-Line  "Report saved: $ReportPath"
Write-Output "Diagnostics complete. See: $ReportPath"
